import AppKit
import Carbon.HIToolbox

/// Petite bulle discrète en bas à gauche de l'écran ; les clics passent au travers.
/// Échap la cache : la touche n'est réservée que pendant que la bulle est visible
/// (raccourci global Carbon, aucune permission d'accessibilité nécessaire).
final class Bubble {
    private static weak var current: Bubble?
    private var escapeHotKey: EventHotKeyRef?

    private let panel: NSPanel
    private let background = NSView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hideWork: DispatchWorkItem?
    private var dotsTimer: Timer?

    private let maxWidth: CGFloat = 280
    private let margin: CGFloat = 12
    private let padX: CGFloat = 10
    private let padY: CGFloat = 7

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.7).cgColor

        label.font = .systemFont(ofSize: 12)
        label.textColor = NSColor(calibratedWhite: 1, alpha: 0.9)
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false

        background.addSubview(label)
        panel.contentView = background

        Bubble.current = self
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                log("Bulle cachée (Échap)")
                Bubble.current?.hide()
            }
            return noErr
        }, 1, &pressed, nil, nil)
    }

    /// Cache la bulle tout de suite (touche Échap).
    func hide() {
        hideWork?.cancel()
        stopDots()
        panel.orderOut(nil)
        releaseEscape()
    }

    /// Affiche un texte pendant `seconds` secondes.
    func show(_ text: String, seconds: Double) {
        stopDots()
        display(text)
        scheduleHide(after: seconds)
    }

    /// Petits points animés pendant l'analyse (remplacés par la réponse).
    func showLoading(timeout: Double = 120) {
        stopDots()
        let frames = ["•  ", "•• ", "•••"]
        var i = 0
        display(frames[2])
        label.stringValue = frames[0]
        dotsTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            i += 1
            self?.label.stringValue = frames[i % frames.count]
        }
        scheduleHide(after: timeout)
    }

    private func display(_ text: String) {
        label.stringValue = text
        label.preferredMaxLayoutWidth = maxWidth
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxWidth, height: 10_000))
            ?? NSSize(width: maxWidth, height: 16)
        let tw = ceil(min(size.width, maxWidth)), th = ceil(size.height)
        let w = tw + 2 * padX, h = th + 2 * padY

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrame(NSRect(x: frame.minX + margin, y: frame.minY + margin, width: w, height: h),
                       display: true)
        background.frame = NSRect(x: 0, y: 0, width: w, height: h)
        label.frame = NSRect(x: padX, y: padY, width: tw, height: th)
        panel.orderFrontRegardless()
        reserveEscape()
    }

    private func reserveEscape() {
        guard escapeHotKey == nil else { return }
        let id = EventHotKeyID(signature: OSType(0x4B415054), id: 1)  // 'KAPT'
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &escapeHotKey)
        if status != noErr { log("Touche Échap indisponible (erreur \(status))") }
    }

    private func releaseEscape() {
        if let escapeHotKey { UnregisterEventHotKey(escapeHotKey) }
        escapeHotKey = nil
    }

    private func scheduleHide(after seconds: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func stopDots() {
        dotsTimer?.invalidate()
        dotsTimer = nil
    }
}
