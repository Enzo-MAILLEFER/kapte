import AppKit
import ImageIO

struct KapteError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Envoie une capture à l'API Gemini et renvoie la réponse (sur le thread principal).
enum Gemini {
    static func prompt(_ cfg: Config) -> String {
        """
        Voici une capture d'écran de l'utilisateur.
        Donne uniquement l'information utile, en tutoyant, \(cfg.maxWords) mots maximum,
        sans markdown :
        - si l'écran pose une question (quiz, exercice, formulaire…) : donne seulement la réponse ;
        - sinon : seulement l'explication ou l'action utile, en une phrase.
        Langue : réponds dans la langue de la question affichée, avec l'orthographe usuelle
        de cette langue pour les noms propres (ex. en français : Kiev, Pékin, Londres ;
        en anglais : Kyiv, Beijing, London), comme l'attendrait un quiz dans cette langue.
        Pour une traduction, réponds dans la langue cible demandée (« traduis en anglais »
        → réponse en anglais). S'il n'y a pas de question, réponds en français.
        Rien d'autre : pas d'introduction, pas de commentaire, pas d'encouragement,
        pas de description de l'écran, pas de phrase de conclusion.
        Exemples : « Framboise » · « Il manque un point-virgule ligne 12. »
        \(cfg.extraInstructions)
        """
    }

    /// Réduit l'image (les captures Retina sont énormes) et la convertit en JPEG base64.
    static func prepareImage(_ url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw KapteError("image illisible")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1568,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let jpeg = NSBitmapImageRep(cgImage: image)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw KapteError("conversion de l'image impossible")
        }
        return jpeg.base64EncodedString()
    }

    static func analyze(_ url: URL, cfg: Config, completion: @escaping (Result<String, Error>) -> Void) {
        let image: String
        do {
            image = try prepareImage(url)
        } catch {
            completion(.failure(error))
            return
        }
        let body: [String: Any] = ["contents": [["parts": [
            ["inline_data": ["mime_type": "image/jpeg", "data": image]],
            ["text": prompt(cfg)],
        ]]]]
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        var models = [cfg.geminiModel]
        if !cfg.fallbackModel.isEmpty && cfg.fallbackModel != cfg.geminiModel {
            models.append(cfg.fallbackModel)
        }
        Attempts(key: cfg.geminiKey, payload: payload, models: models, completion: completion).launch()
    }

    /// Analyse la réponse HTTP : texte, ou erreur (temporaire = on peut réessayer).
    fileprivate static func parse(data: Data?, response: URLResponse?, error: Error?)
        -> Result<String, AttemptError> {
        if let error {
            return .failure(AttemptError(message: "Gemini injoignable : \(error.localizedDescription)",
                                         temporary: true))
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data ?? Data(), as: UTF8.self)
        guard code == 200 else {
            // 503 surcharge, 429 quota minute, 404 modèle retiré : on tente l'autre modèle
            return .failure(AttemptError(message: "Gemini \(code) : \(text.prefix(200))",
                                         temporary: [404, 429, 500, 502, 503, 504].contains(code)))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return .failure(AttemptError(message: "réponse de Gemini inattendue : \(text.prefix(200))",
                                         temporary: true))
        }
        let answer = parts.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty
            ? .failure(AttemptError(message: "Gemini n'a rien répondu", temporary: true))
            : .success(answer)
    }
}

fileprivate struct AttemptError: Error {
    let message: String
    let temporary: Bool
}

/// Essais d'une analyse. Si Gemini ne répond pas en 5 s, un 2e essai part en parallèle
/// (en alternant avec le modèle de secours) et la première réponse gagne : les lenteurs
/// ponctuelles de Google ne bloquent plus la bulle 30 s ou plus.
private final class Attempts {
    static let maxLaunches = 4
    static let hedgeDelay = 5.0     // secondes sans réponse avant un essai en parallèle
    static let timeout = 15.0       // abandon d'un essai

    private let key: String
    private let payload: Data
    private let models: [String]
    private let completion: (Result<String, Error>) -> Void

    private var launched = 0
    private var inFlight = 0
    private var finished = false
    private var tasks: [URLSessionDataTask] = []
    private var lastError = "Gemini n'a pas répondu"

    init(key: String, payload: Data, models: [String], completion: @escaping (Result<String, Error>) -> Void) {
        self.key = key
        self.payload = payload
        self.models = models
        self.completion = completion
    }

    func launch() {
        guard !finished, launched < Attempts.maxLaunches else { return }
        let model = models[launched % models.count]
        launched += 1
        inFlight += 1
        let number = launched

        let path = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(path):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = Attempts.timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = payload

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.handle(Gemini.parse(data: data, response: response, error: error), model: model)
            }
        }
        tasks.append(task)
        task.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + Attempts.hedgeDelay) {
            if !self.finished && self.launched == number && number < Attempts.maxLaunches {
                log("Gemini lent (\(model)), essai en parallèle")
                self.launch()
            }
        }
    }

    private func handle(_ result: Result<String, AttemptError>, model: String) {
        inFlight -= 1
        guard !finished else { return }  // un autre essai a déjà répondu
        switch result {
        case .success(let answer):
            finish(.success(answer))
        case .failure(let error):
            lastError = error.message
            log("Gemini (\(model)) : \(error.message)")
            if !error.temporary {
                finish(.failure(KapteError(error.message)))
            } else if inFlight == 0 {
                if launched < Attempts.maxLaunches {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.launch() }
                } else {
                    finish(.failure(KapteError(lastError)))
                }
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        finished = true
        tasks.forEach { $0.cancel() }
        completion(result)
    }
}
