import AppKit
import Carbon.HIToolbox

/// Capture d'une zone avec le raccourci de Kapte : un simple trait fin pendant qu'on glisse
/// (pas de croix, pas de coordonnées, pas de vignette ni de son), Échap annule.
/// Nécessite l'autorisation « Enregistrement de l'écran ».
final class Selection {
    private var panels: [NSPanel] = []
    private var escapeHotKey: EventHotKeyRef?
    private var done: ((URL) -> Void)?

    var isActive: Bool { !panels.isEmpty }

    func start(_ done: @escaping (URL) -> Void) {
        guard !isActive else { return }
        self.done = done
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.001)  // 0 laisserait passer les clics
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = SelectionView()
            view.onSelect = { [weak self, weak panel] rect in
                guard let self, let panel else { return }
                self.capture(NSRect(origin: NSPoint(x: panel.frame.minX + rect.minX,
                                                    y: panel.frame.minY + rect.minY), size: rect.size))
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        NSCursor.crosshair.set()
        escapeHotKey = HotKeys.register(kVK_Escape, name: "Échap (sélection)") { [weak self] in self?.cancel() }
    }

    func cancel() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        HotKeys.unregister(escapeHotKey)
        escapeHotKey = nil
        NSCursor.arrow.set()
    }

    private func capture(_ rect: NSRect) {
        let done = self.done
        cancel()
        guard rect.width >= 4, rect.height >= 4 else { return }  // simple clic : rien
        // screencapture compte en points depuis le coin haut gauche de l'écran principal
        let top = (NSScreen.screens.first?.frame.height ?? 0) - rect.maxY
        let region = [rect.minX, top, rect.width, rect.height].map { String(Int($0.rounded())) }.joined(separator: ",")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kapte \(Int(Date().timeIntervalSince1970 * 1000)).png")
        // Laisse le temps au trait de disparaître de l'écran avant la capture
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            let status = runCommand("/usr/sbin/screencapture", ["-x", "-R", region, url.path])
            DispatchQueue.main.async {
                if status == 0, FileManager.default.fileExists(atPath: url.path) {
                    done?(url)
                } else {
                    log("Capture Kapte impossible (screencapture : \(status))")
                }
            }
        }
    }
}

private final class SelectionView: NSView {
    var onSelect: ((NSRect) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        NSCursor.crosshair.set()
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        if let rect = selection { onSelect?(rect) }
    }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Zone encore plate (début du glissé) : insetBy renverrait un rectangle nul (infini → NaN, plantage)
        guard let rect = selection, rect.width >= 2, rect.height >= 2 else { return }
        // Seulement les 4 coins, gris clair à moitié transparent : la zone reste lisible sans cadre voyant
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        let len = min(8, r.width / 2, r.height / 2)
        let path = NSBezierPath()
        for (corner, dx, dy) in [(NSPoint(x: r.minX, y: r.minY), len, len), (NSPoint(x: r.maxX, y: r.minY), -len, len),
                                 (NSPoint(x: r.minX, y: r.maxY), len, -len), (NSPoint(x: r.maxX, y: r.maxY), -len, -len)] {
            path.move(to: NSPoint(x: corner.x + dx, y: corner.y))
            path.line(to: corner)
            path.line(to: NSPoint(x: corner.x, y: corner.y + dy))
        }
        NSColor(calibratedWhite: 0.6, alpha: 0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
