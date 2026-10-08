import AppKit

/// Petite bulle discrète en bas à gauche de l'écran ; les clics passent au travers.
final class Bubble {
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
    }

    private func scheduleHide(after seconds: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stopDots()
            self?.panel.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func stopDots() {
        dotsTimer?.invalidate()
        dotsTimer = nil
    }
}
