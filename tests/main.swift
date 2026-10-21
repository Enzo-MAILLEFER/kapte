// Vérifie le prompt : envoie chaque capture de tests/captures/ à Gemini (avec le vrai code
// de Kapte) et compare la réponse à ce qu'attend tests/cas.json. Lancé par tests/verifier-prompt.sh.
import Foundation

struct Cas {
    var attendu = ""
    var lignes: Int?
    var lignesMax: Int?
    var contient: [String] = []
    var interdit: [String] = []
    var reponses: [String: String] = [:]  // numéro (ou lettre) → réponse attendue
    var contexte: [String] = []  // captures précédentes envoyées comme contexte, comme dans Kapte
}

let dossier = URL(fileURLWithPath: CommandLine.arguments[1])
let choisies = Set(CommandLine.arguments.dropFirst(2))  // vide = toutes les captures
let pause = 5.0  // secondes entre deux captures : reste sous le quota gratuit (15 requêtes/min)
Gemini.parallelAttempts = false
var cas: [String: Cas] = [:]
if let data = try? Data(contentsOf: dossier.appendingPathComponent("cas.json")),
   let liste = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
    for c in liste {
        guard let capture = c["capture"] as? String else { continue }
        cas[capture] = Cas(attendu: c["attendu"] as? String ?? "",
                           lignes: (c["lignes"] as? NSNumber)?.intValue,
                           lignesMax: (c["lignes_max"] as? NSNumber)?.intValue,
                           contient: c["contient"] as? [String] ?? [],
                           interdit: c["interdit"] as? [String] ?? [],
                           reponses: c["reponses"] as? [String: String] ?? [:],
                           contexte: c["contexte"] as? [String] ?? [])
    }
} else {
    print("⚠️  tests/cas.json illisible : les réponses seront seulement affichées")
}

/// Problèmes de la réponse par rapport à ce qui est attendu (vide = OK).
func problemes(_ reponse: String, _ c: Cas) -> [String] {
    var p: [String] = []
    let texte = reponse.lowercased()
    let n = reponse.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    if let lignes = c.lignes, n != lignes { p.append("\(n) ligne(s) au lieu de \(lignes)") }
    if let max = c.lignesMax, n > max { p.append("\(n) lignes, \(max) maximum") }
    for mot in c.contient where !texte.contains(mot.lowercased()) { p.append("ne contient pas « \(mot) »") }
    for mot in c.interdit where texte.contains(mot.lowercased()) { p.append("contient « \(mot) »") }
    for (numero, attendu) in c.reponses.sorted(by: { $0.key < $1.key }) {
        // « 2 están », « 2. están », « 2) están »… en début de ligne ou après « · »
        let motif = "(^|[\\s·])" + NSRegularExpression.escapedPattern(for: numero) + "[.):]?\\s+"
            + NSRegularExpression.escapedPattern(for: attendu) + "(?![\\p{L}])"
        if texte.range(of: motif, options: [.regularExpression, .caseInsensitive]) == nil {
            p.append("\(numero) ≠ « \(attendu) »")
        }
    }
    return p
}

let images = ((try? FileManager.default.contentsOfDirectory(at: dossier.appendingPathComponent("captures"),
                                                              includingPropertiesForKeys: nil)) ?? [])
    .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    .filter { choisies.isEmpty || choisies.contains($0.lastPathComponent)
              || choisies.contains($0.deletingPathExtension().lastPathComponent) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

let cfg = Config.load()
guard !cfg.geminiKey.isEmpty else {
    print("Clé Gemini introuvable dans ~/.kapte/config.json")
    exit(1)
}

var echecs = 0

func suivante(_ i: Int) {
    guard i < images.count else {
        print(echecs == 0 ? "✅ \(images.count) capture(s), tout est bon"
                          : "❌ \(echecs) capture(s) sur \(images.count) ne passent pas")
        exit(echecs == 0 ? 0 : 1)
    }
    let image = images[i]
    let nom = image.lastPathComponent
    let c = cas[nom]
    let jpeg: String
    do {
        jpeg = try Gemini.prepareImage(image)
    } catch {
        print("── \(nom)\n   ❌ \(error.localizedDescription)\n")
        echecs += 1
        return suivante(i + 1)
    }
    let contexte = (c?.contexte ?? []).compactMap {
        try? Gemini.prepareImage(dossier.appendingPathComponent("captures").appendingPathComponent($0))
    }
    Gemini.analyze(image: jpeg, context: contexte, cfg: cfg) { resultat in
        print("── \(nom)")
        if let c, !c.attendu.isEmpty { print("   attendu : \(c.attendu)") }
        switch resultat {
        case .success(let reponse):
            print("   réponse : " + reponse.replacingOccurrences(of: "\n", with: "\n             "))
            if let c {
                let p = problemes(reponse, c)
                if p.isEmpty {
                    print("   ✅ OK")
                } else {
                    echecs += 1
                    print("   ❌ " + p.joined(separator: " · "))
                }
            } else {
                print("   (pas de vérification : ajoute-la dans tests/cas.json)")
            }
        case .failure(let erreur):
            echecs += 1
            print("   ❌ erreur : \(erreur.localizedDescription)")
        }
        print("")
        DispatchQueue.main.asyncAfter(deadline: .now() + (i + 1 < images.count ? pause : 0)) {
            suivante(i + 1)
        }
    }
}

suivante(0)
dispatchMain()
