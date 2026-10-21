import AppKit
import ImageIO

struct KapteError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Envoie une capture à l'API Gemini (ou Claude, selon `provider`) et renvoie la réponse
/// (sur le thread principal).
enum Gemini {
    /// Essai en parallèle si Gemini est lent (coupé par le vérificateur de prompt, pour le quota).
    static var parallelAttempts = true

    static func prompt(_ cfg: Config, withContext: Bool = false) -> String {
        let context = withContext ? """
            Les premières images sont les captures précédentes, fournies seulement comme contexte
            (texte de lecture, messages, consignes ou liste de mots qui concernent les questions
            suivantes). Ne réponds qu'aux questions de la dernière image, jamais à celles des
            précédentes (sauf si la dernière n'a aucune question).

            """ : ""
        return """
        \(context)Voici une capture d'écran de l'utilisateur.
        Donne uniquement l'information utile, en tutoyant, \(cfg.maxWords) mots maximum,
        sans markdown :
        - si l'écran pose une question (quiz, exercice, formulaire…) : donne seulement la réponse ;
        - réponds seulement aux questions et trous qui ont un endroit où répondre (rond, case,
          menu déroulant, champ) ; un texte à trous affiché au-dessus sans menu n'est que du
          contexte. Numérote avec les numéros affichés dans le quiz (« 17. doble »), jamais 1, 2, 3
          à la place ;
        - choisis toujours parmi les options proposées, jamais un mot qui n'y figure pas ;
          vérifie la grammaire avant de choisir (accord, genre, nombre, préposition : « desde las
          nueve hasta la una », « de tres a cinco », « por la tarde ») ;
        - s'il y a plusieurs questions : réponds à chacune, précédée de son numéro ou de sa
          lettre, sans en sauter ; la limite de mots vaut alors par réponse. Réponses courtes
          (un mot ou quelques mots) : toutes à la suite sur une seule ligne, séparées par « · »
          (« a veintisiete · b cincuenta y dos · c ciento dieciséis ») ; réponses qui sont
          des phrases : une par ligne (« 1. … ») ;
        - texte suivi à trous sans numéros (lettre, paragraphe) : donne seulement les mots à
          mettre dans les trous vides, dans l'ordre, numérotés 1, 2, 3… à la suite
          (« 1 Madrid · 2 mis amigos »), sans recopier le texte autour ni les trous déjà remplis ;
        - exercice numéroté où il faut réécrire ou transformer une phrase : donne seulement la
          phrase transformée, entière, mots imprimés compris ; si un exemple est déjà fait (en
          général le 1), c'est le modèle : applique exactement la même transformation à chaque
          phrase (ex. 1 au pluriel → toutes au pluriel) ;
        - question à choix (ronds, V/F, Verdadero/Falso) : recopie le texte exact de la bonne
          option (« Falso, les gusta usar la alberca en el verano », « V », « F »), sans le
          reformuler ; cases à cocher (carrés) : il peut y avoir plusieurs bonnes options,
          donne-les toutes (« piso · casa ») ;
        - menus déroulants ou colonnes à relier : pour chaque ligne, dans l'ordre, donne le
          début de la ligne puis le choix à faire, avec son numéro si la colonne d'options est
          numérotée (« ir 4 volver · entrar 5 salir ») ; si les options du menu ne sont pas
          visibles, donne le mot attendu (« arriba abajo ») ; trous numérotés « 1)… 2)… » :
          numéro du trou puis le mot (« 1 a · 2 de ») ;
        - questions sur un texte (lecture, correo, mensajes) : base-toi uniquement sur ce que
          dit le texte, lu attentivement ; si une option dit « No lo dice » et que le texte ne
          donne pas l'information, c'est elle ; un détail faux (lieu, jour, ordre, raison)
          rend l'affirmation fausse ;
        - question audio (« Escucha… ») : tu ne peux pas l'entendre, choisis l'option la plus
          probable sans le signaler ;
        - question d'orthographe (même mot écrit de plusieurs façons) : choisis la forme
          correcte, avec sa majuscule telle qu'affichée ;
        - si la question est ouverte (exercice de langue, conversation, question personnelle) :
          invente une réponse naturelle et plausible, comme le ferait un élève ;
        - ne recopie jamais la question ni le texte de l'écran à la place d'une réponse ;
        - sinon : seulement l'explication ou l'action utile, en une phrase.
        Langue : réponds dans la langue de la question ou de l'exercice affiché (un exercice
        sans consigne visible se fait dans la langue de ses mots), avec l'orthographe usuelle
        de cette langue pour les noms propres (ex. en français : Kiev, Pékin, Londres ;
        en anglais : Kyiv, Beijing, London), comme l'attendrait un quiz dans cette langue.
        Pour une traduction, réponds dans la langue cible demandée (« traduis en anglais »
        → réponse en anglais). S'il n'y a ni question ni exercice, réponds en français.
        Rien d'autre : pas d'introduction, pas de commentaire, pas d'encouragement,
        pas de description de l'écran, pas de phrase de conclusion.
        Exemples : « Framboise » · « Il manque un point-virgule ligne 12. »
        · « ¿Qué van a tomar de primero? » → « De primero, voy a tomar una ensalada mixta. »
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

    /// `context` : captures précédentes, de la plus ancienne à la plus récente (JPEG base64, voir
    /// `prepareImage`), envoyées dans la même requête pour les questions dont le texte est avant.
    static func analyze(image: String, context: [String] = [], cfg: Config,
                        completion: @escaping (Result<String, Error>) -> Void) {
        if cfg.usesClaude {
            return analyzeWithClaude(image: image, context: context, cfg: cfg, completion: completion)
        }
        var parts: [[String: Any]] = []
        for old in context { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": old]]) }
        parts.append(["inline_data": ["mime_type": "image/jpeg", "data": image]])
        parts.append(["text": prompt(cfg, withContext: !context.isEmpty)])
        let body: [String: Any] = [
            "contents": [["parts": parts]],
            // un peu de réflexion : sans elle, le modèle se trompe sur les prépositions et accords
            "generationConfig": ["thinkingConfig": ["thinkingLevel": "low"]],
        ]
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        var models = [cfg.geminiModel]
        if !cfg.fallbackModel.isEmpty && cfg.fallbackModel != cfg.geminiModel {
            models.append(cfg.fallbackModel)
        }
        Attempts(models: models, request: { model in
            let path = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            var request = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(path):generateContent")!)
            request.setValue(cfg.geminiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = payload
            return request
        }, parse: parse, completion: completion).launch()
    }

    private static func analyzeWithClaude(image: String, context: [String], cfg: Config,
                                          completion: @escaping (Result<String, Error>) -> Void) {
        var content: [[String: Any]] = (context + [image]).map {
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0]]
        }
        content.append(["type": "text", "text": prompt(cfg, withContext: !context.isEmpty)])
        let body: [String: Any] = [
            "model": cfg.claudeModel,
            "max_tokens": 4000,  // réflexion comprise
            "output_config": ["effort": cfg.claudeEffort],  // low par défaut : réfléchit sans ralentir la bulle
            "messages": [["role": "user", "content": content]],
        ]
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        Attempts(models: [cfg.claudeModel], request: { _ in
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(cfg.claudeKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = payload
            return request
        }, parse: parseClaude, completion: completion).launch()
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

extension Gemini {
    fileprivate static func parseClaude(data: Data?, response: URLResponse?, error: Error?)
        -> Result<String, AttemptError> {
        if let error {
            return .failure(AttemptError(message: "Claude injoignable : \(error.localizedDescription)",
                                         temporary: true))
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data ?? Data(), as: UTF8.self)
        guard code == 200 else {
            // 529 surcharge, 429 limite de débit
            return .failure(AttemptError(message: "Claude \(code) : \(text.prefix(200))",
                                         temporary: [408, 429, 500, 502, 503, 504, 529].contains(code)))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            return .failure(AttemptError(message: "réponse de Claude inattendue : \(text.prefix(200))",
                                         temporary: true))
        }
        if json["stop_reason"] as? String == "refusal" {
            return .failure(AttemptError(message: "Claude a refusé de répondre", temporary: false))
        }
        let answer = content.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty
            ? .failure(AttemptError(message: "Claude n'a rien répondu", temporary: true))
            : .success(answer)
    }
}

fileprivate struct AttemptError: Error {
    let message: String
    let temporary: Bool
}

/// Essais d'une analyse. Si l'API ne répond pas en 5 s, un 2e essai part en parallèle
/// (en alternant avec le modèle de secours) et la première réponse gagne : les lenteurs
/// ponctuelles de Google ne bloquent plus la bulle 30 s ou plus.
private final class Attempts {
    static let maxLaunches = 4
    static let hedgeDelay = 5.0     // secondes sans réponse avant un essai en parallèle
    static let timeout = 30.0       // abandon d'un essai (Gemini met parfois plus de 15 s)

    private let models: [String]
    private let request: (String) -> URLRequest
    private let parse: (Data?, URLResponse?, Error?) -> Result<String, AttemptError>
    private let completion: (Result<String, Error>) -> Void

    private var launched = 0
    private var inFlight = 0
    private var finished = false
    private var tasks: [URLSessionDataTask] = []
    private var lastError = "pas de réponse"

    init(models: [String], request: @escaping (String) -> URLRequest,
         parse: @escaping (Data?, URLResponse?, Error?) -> Result<String, AttemptError>,
         completion: @escaping (Result<String, Error>) -> Void) {
        self.models = models
        self.request = request
        self.parse = parse
        self.completion = completion
    }

    func launch() {
        guard !finished, launched < Attempts.maxLaunches else { return }
        let model = models[launched % models.count]
        launched += 1
        inFlight += 1
        let number = launched

        var request = self.request(model)
        request.httpMethod = "POST"
        request.timeoutInterval = Attempts.timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.handle(self.parse(data, response, error), model: model)
            }
        }
        tasks.append(task)
        task.resume()

        guard Gemini.parallelAttempts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Attempts.hedgeDelay) {
            if !self.finished && self.launched == number && number < Attempts.maxLaunches {
                log("\(model) lent, essai en parallèle")
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
            log("\(model) : \(error.message)")
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
