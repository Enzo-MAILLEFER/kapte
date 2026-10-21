import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bubble = Bubble()
    private let watcher = Watcher()
    private let updater = Updater()
    private let history = History()
    private var recentCaptures: [(image: String, date: Date)] = []
    static let contextDelay = 180.0  // secondes pendant lesquelles une capture sert de contexte aux suivantes
    static let contextCount = 2      // captures précédentes envoyées avec la nouvelle (même requête)

    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "")

    private var queue: [URL] = []
    private var busy = false

    /// Réponse de l'historique affichée (0 = la plus récente), nil = pas en train de défiler.
    private var browsing: Int?
    private var historyKeys: [EventHotKeyRef] = []

    private var isPaused: Bool { FileManager.default.fileExists(atPath: pauseFlag.path) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOverToLaunchAgent() { return }
        try? FileManager.default.createDirectory(at: kapteDir, withIntermediateDirectories: true)
        log("Kapte v\(updater.currentVersion) démarre")

        setUpMenu()
        refreshMenu()

        watcher.onScreenshot = { [weak self] url in self?.enqueue(url) }
        watcher.start()

        updater.bubble = bubble
        updater.isBusy = { [weak self] in self?.busy ?? false }
        updater.announceIfJustUpdated()
        updater.start()
    }

    /// Ouverte à la main (double-clic sur Kapte.app) alors que le démarrage auto est installé :
    /// on laisse launchd lancer (ou garder) l'exemplaire officiel et on s'arrête.
    private func handOverToLaunchAgent() -> Bool {
        let env = ProcessInfo.processInfo.environment
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
        guard env["XPC_SERVICE_NAME"] != launchAgentLabel, env["KAPTE_DEV"] == nil,
              FileManager.default.fileExists(atPath: plist.path) else { return false }
        try? FileManager.default.removeItem(at: pauseFlag)  // rouvrir l'app = la réactiver
        runCommand("/bin/launchctl", ["kickstart", "gui/\(getuid())/\(launchAgentLabel)"])
        NSApp.terminate(nil)
        return true
    }

    // MARK: - Captures

    private func enqueue(_ url: URL) {
        if isPaused {
            log("En pause, capture ignorée : \(url.lastPathComponent)")
            return
        }
        queue.append(url)
        processNext()
    }

    private func processNext() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let url = queue.removeFirst()
        waitUntilStable(url, tries: 20, lastSize: -1) { [weak self] ready in
            guard let self else { return }
            guard ready else { return self.finish() }
            log("Nouvelle capture : \(url.lastPathComponent)")
            let cfg = Config.load()
            guard !cfg.apiKey.isEmpty else {
                self.bubble.show("Clé Gemini manquante : relance l'installateur Kapte.", seconds: 8)
                return self.finish()
            }
            let image: String
            do {
                image = try Gemini.prepareImage(url)
            } catch {
                self.bubble.show("Erreur : \(error.localizedDescription)", seconds: cfg.displaySeconds)
                return self.finish()
            }
            // La capture d'avant sert de contexte si elle est récente (texte de lecture sur un autre écran)
            self.recentCaptures.removeAll { Date().timeIntervalSince($0.date) > AppDelegate.contextDelay }
            let context = self.recentCaptures.suffix(AppDelegate.contextCount).map(\.image)
            self.recentCaptures = Array((self.recentCaptures + [(image, Date())]).suffix(AppDelegate.contextCount))
            self.bubble.showLoading()
            Gemini.analyze(image: image, context: context, cfg: cfg) { result in
                switch result {
                case .success(let answer):
                    // Analyse réussie : la capture ne sert plus (gardée en cas d'erreur pour réessayer)
                    try? FileManager.default.removeItem(at: url)
                    self.watcher.forget(url)
                    log("Réponse : \(answer)")
                    self.history.add(answer)
                    self.browsing = nil
                    if cfg.copyAnswer {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer, forType: .string)
                    }
                    self.bubble.show(answer, seconds: cfg.displaySeconds)
                case .failure(let error):
                    log("Erreur : \(error.localizedDescription)")
                    self.bubble.show("Erreur : \(error.localizedDescription)", seconds: cfg.displaySeconds)
                }
                self.finish()
            }
        }
    }

    // MARK: - Historique (⌃⌥← plus ancienne, ⌃⌥→ plus récente)

    private func browse(older: Bool) {
        guard !busy, !isPaused, !history.answers.isEmpty else { return }
        let last = history.answers.count - 1
        let index: Int
        if let current = browsing, bubble.isVisible {
            index = older ? min(current + 1, last) : max(current - 1, 0)
        } else {
            index = 0  // la bulle était cachée : on repart de la dernière réponse
        }
        browsing = index
        let cfg = Config.load()
        bubble.show("\(index + 1)/\(last + 1) · \(history.answers[index])", seconds: cfg.displaySeconds)
    }

    /// Les flèches ne sont réservées que quand Kapte est activé.
    private func updateHistoryKeys() {
        historyKeys.forEach { HotKeys.unregister($0) }
        historyKeys = []
        guard !isPaused else { return }
        let mods = controlKey | optionKey
        historyKeys = [
            HotKeys.register(kVK_LeftArrow, modifiers: mods, name: "⌃⌥←") { [weak self] in self?.browse(older: true) },
            HotKeys.register(kVK_RightArrow, modifiers: mods, name: "⌃⌥→") { [weak self] in self?.browse(older: false) },
        ].compactMap { $0 }
    }

    private func finish() {
        busy = false
        processNext()
    }

    /// Attend que macOS ait fini d'écrire la capture (taille stable).
    private func waitUntilStable(_ url: URL, tries: Int, lastSize: Int, done: @escaping (Bool) -> Void) {
        guard tries > 0,
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else {
            return done(false)
        }
        if size > 0 && size == lastSize { return done(true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.waitUntilStable(url, tries: tries - 1, lastSize: size, done: done)
        }
    }

    // MARK: - Barre des menus

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let update = NSMenuItem(title: "Rechercher les mises à jour", action: #selector(checkUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter (met en pause)", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func refreshMenu() {
        let paused = isPaused
        let image = NSImage(systemSymbolName: paused ? "eye.slash" : "eye", accessibilityDescription: "Kapte")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.alphaValue = paused ? 0.5 : 1
        statusLine.title = "\(paused ? "Kapte : en pause" : "Kapte : activé")  ·  v\(updater.currentVersion)"
        toggleItem.title = paused ? "Activer" : "Mettre en pause"
        updateHistoryKeys()
    }

    @objc private func togglePause() {
        if isPaused {
            try? FileManager.default.removeItem(at: pauseFlag)
        } else {
            FileManager.default.createFile(atPath: pauseFlag.path, contents: nil)
        }
        refreshMenu()
    }

    @objc private func checkUpdates() {
        updater.check(manual: true)
    }

    @objc private func quit() {
        // Sans icône on ne verrait plus l'état : quitter = mettre en pause.
        // L'icône revient à la prochaine ouverture de session (ou en rouvrant Kapte.app).
        FileManager.default.createFile(atPath: pauseFlag.path, contents: nil)
        NSApp.terminate(nil)
    }
}
