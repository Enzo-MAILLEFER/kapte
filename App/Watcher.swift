import Foundation

/// Surveille le dossier des captures de macOS et signale chaque nouvelle capture.
/// Les fichiers déjà présents au démarrage ne sont jamais touchés.
final class Watcher {
    var onScreenshot: ((URL) -> Void)?

    private var folder: URL?
    private var seen = Set<String>()
    private var timer: Timer?
    private var ticks = 0
    private var accessErrorLogged = false

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    /// À appeler quand une capture a été supprimée après analyse.
    func forget(_ url: URL) {
        seen.remove(url.path)
    }

    static func screenshotFolder(watchDir: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if !watchDir.isEmpty {
            return URL(fileURLWithPath: (watchDir as NSString).expandingTildeInPath)
        }
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !location.isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath)
        }
        return home.appendingPathComponent("Desktop")
    }

    static func isScreenshot(_ url: URL) -> Bool {
        let name = url.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()
        if name.hasPrefix(".") { return false }
        guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { return false }
        return ["screenshot", "capture d", "captura de pantalla", "bildschirmfoto"]
            .contains { name.hasPrefix($0) }
    }

    private func scan() {
        // Le dossier peut changer (réglage macOS ou config) : on le relit toutes les ~10 s.
        if folder == nil || ticks % 15 == 0 {
            let current = Watcher.screenshotFolder(watchDir: Config.load().watchDir)
            if current != folder {
                folder = current
                seen = Set((list(current) ?? []).map(\.path))
                log("Kapte surveille : \(current.path)")
            }
        }
        ticks += 1
        guard let folder, let files = list(folder) else { return }

        let fresh = files
            .filter { !seen.contains($0.path) }
            .sorted { modificationDate($0) < modificationDate($1) }
        for url in fresh {
            seen.insert(url.path)
            onScreenshot?(url)
        }
    }

    private func list(_ dir: URL) -> [URL]? {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            accessErrorLogged = false
            return urls.filter(Watcher.isScreenshot)
        } catch {
            if !accessErrorLogged {
                log("Accès impossible à \(dir.path) : \(error.localizedDescription). " +
                    "Choisis un dossier hors Bureau/Documents/Téléchargements, ex. ~/Screenshots.")
                accessErrorLogged = true
            }
            return nil
        }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
    }
}
