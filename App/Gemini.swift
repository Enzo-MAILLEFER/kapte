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
        let model = cfg.geminiModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cfg.geminiModel
        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(cfg.geminiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        send(request, attempt: 0, completion: completion)
    }

    private static func send(_ request: URLRequest, attempt: Int,
                             completion: @escaping (Result<String, Error>) -> Void) {
        // 503 (surcharge), 429 (quota minute), délai dépassé : temporaires, on réessaie (3 fois max)
        func retryOr(_ error: String) {
            if attempt < 3 {
                let delay = 2.0 * pow(2.0, Double(attempt))
                log("Gemini : \(error), nouvel essai dans \(Int(delay)) s")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    send(request, attempt: attempt + 1, completion: completion)
                }
            } else {
                completion(.failure(KapteError(error)))
            }
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    retryOr("Gemini injoignable : \(error.localizedDescription)")
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let text = String(decoding: data ?? Data(), as: UTF8.self)
                guard code == 200 else {
                    let message = "Gemini \(code) : \(text.prefix(200))"
                    if [429, 500, 503].contains(code) {
                        retryOr(message)
                    } else {
                        completion(.failure(KapteError(message)))
                    }
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    completion(.failure(KapteError("réponse de Gemini inattendue : \(text.prefix(200))")))
                    return
                }
                let answer = parts.compactMap { $0["text"] as? String }.joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if answer.isEmpty {
                    completion(.failure(KapteError("Gemini n'a rien répondu")))
                } else {
                    completion(.success(answer))
                }
            }
        }.resume()
    }
}
