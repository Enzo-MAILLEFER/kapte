import Foundation

let kapteDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kapte")
let configURL = kapteDir.appendingPathComponent("config.json")
let pauseFlag = kapteDir.appendingPathComponent("paused")       // présent = en pause
let justUpdatedFlag = kapteDir.appendingPathComponent("just_updated")  // version, affichée au démarrage
let launchAgentLabel = "com.kapte"

/// Réglages lus dans ~/.kapte/config.json (relus à chaque capture).
struct Config {
    var geminiKey = ""
    var geminiModel = "gemini-3.5-flash-lite"
    var displaySeconds = 15.0
    var maxWords = 45
    var watchDir = ""           // vide = dossier de captures de macOS
    var extraInstructions = ""

    static func load() -> Config {
        var c = Config()
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("Config illisible ou absente : \(configURL.path)")
            return c
        }
        if let v = json["gemini_api_key"] as? String { c.geminiKey = v }
        if let v = json["gemini_model"] as? String, !v.isEmpty { c.geminiModel = v }
        if let v = json["display_seconds"] as? NSNumber { c.displaySeconds = v.doubleValue }
        if let v = json["max_words"] as? NSNumber { c.maxWords = v.intValue }
        if let v = json["watch_dir"] as? String { c.watchDir = v }
        if let v = json["extra_instructions"] as? String { c.extraInstructions = v }
        if c.geminiKey.isEmpty, let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            c.geminiKey = env
        }
        return c
    }
}

private let logDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

func log(_ message: String) {
    print("\(logDateFormatter.string(from: Date())) \(message)")
}

/// "1.10.0" est plus récent que "1.9.2".
func isNewer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }
    let y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let d = (i < x.count ? x[i] : 0) - (i < y.count ? y[i] : 0)
        if d != 0 { return d > 0 }
    }
    return false
}

/// Lance une commande et attend sa fin ; renvoie le code de sortie (-1 si impossible).
@discardableResult
func runCommand(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    } catch {
        return -1
    }
}
