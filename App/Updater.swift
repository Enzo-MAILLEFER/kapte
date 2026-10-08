import AppKit

/// Mises à jour automatiques depuis les releases GitHub : vérifie au démarrage puis
/// toutes les 6 h, télécharge Kapte.zip, remplace l'app et redémarre (jamais pendant une analyse).
final class Updater {
    static let repo = "Enzo-MAILLEFER/kapte"

    var isBusy: () -> Bool = { false }
    var bubble: Bubble?

    private var timer: Timer?
    private var updating = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.check(manual: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check(manual: false)
        }
    }

    /// Bulle « mis à jour » au premier démarrage après une mise à jour.
    func announceIfJustUpdated() {
        guard let version = try? String(contentsOf: justUpdatedFlag, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: justUpdatedFlag)
        let v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        bubble?.show("Kapte a été mis à jour (v\(v)) ✓", seconds: 5)
    }

    func check(manual: Bool) {
        guard !updating else { return }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("Kapte/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let assets = json["assets"] as? [[String: Any]],
                      let asset = assets.first(where: { $0["name"] as? String == "Kapte.zip" }),
                      let link = asset["browser_download_url"] as? String,
                      let zipURL = URL(string: link) else {
                    log("Vérification des mises à jour impossible")
                    if manual {
                        self.bubble?.show("Impossible de vérifier les mises à jour (connexion ?)", seconds: 6)
                    }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                guard isNewer(latest, than: self.currentVersion) else {
                    if manual { self.bubble?.show("Kapte est à jour (v\(self.currentVersion))", seconds: 4) }
                    return
                }
                log("Nouvelle version disponible : v\(latest)")
                if manual { self.bubble?.show("Mise à jour vers la v\(latest)…", seconds: 30) }
                self.install(zipURL, version: latest)
            }
        }.resume()
    }

    private func install(_ zipURL: URL, version: String) {
        if isBusy() {  // une capture est en cours d'analyse : on repasse dans 1 min
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                self?.install(zipURL, version: version)
            }
            return
        }
        updating = true
        URLSession.shared.downloadTask(with: zipURL) { file, response, error in
            // Le fichier temporaire est effacé à la fin de ce bloc : on le déplace tout de suite.
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("kapte-update-\(UUID().uuidString)")
            let zip = work.appendingPathComponent("Kapte.zip")
            var ok = false
            if let file, error == nil, (response as? HTTPURLResponse)?.statusCode == 200 {
                ok = (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil
                    && (try? FileManager.default.moveItem(at: file, to: zip)) != nil
            }
            DispatchQueue.main.async {
                if ok {
                    self.replaceApp(zip: zip, work: work, version: version)
                } else {
                    self.fail("téléchargement échoué")
                }
            }
        }.resume()
    }

    private func replaceApp(zip: URL, work: URL, version: String) {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: work) }

        guard runCommand("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) == 0 else {
            return fail("archive illisible")
        }
        let newApp = work.appendingPathComponent("Kapte/Kapte.app")
        guard Bundle(url: newApp)?.infoDictionary?["CFBundleShortVersionString"] as? String == version else {
            return fail("archive incomplète")
        }
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app" else {
            return fail("Kapte ne tourne pas depuis Kapte.app")
        }
        runCommand("/usr/bin/xattr", ["-cr", newApp.path])
        do {
            _ = try fm.replaceItemAt(current, withItemAt: newApp)
        } catch {
            return fail("remplacement impossible (\(error.localizedDescription))")
        }
        try? version.write(to: justUpdatedFlag, atomically: true, encoding: .utf8)
        log("Mise à jour installée : v\(version), redémarrage")

        // Relance via launchd (qui gère le démarrage auto) ; sinon on rouvre l'app nous-mêmes.
        if runCommand("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(launchAgentLabel)"]) != 0 {
            runCommand("/usr/bin/open", ["-n", current.path])
            NSApp.terminate(nil)
        }
    }

    private func fail(_ reason: String) {
        updating = false
        log("Mise à jour impossible : \(reason)")
    }
}
