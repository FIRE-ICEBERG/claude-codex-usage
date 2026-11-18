import AppKit

/// The status item's hover tooltip, shown and hidden by Pulse itself instead of `button.toolTip`.
/// AppKit's tooltip tracking for the status-bar window goes stale (a mouse-exited lost while the
/// menu is open, then the image/tooltip is re-set on every poll): it then pops the tooltip up with
/// the pointer elsewhere, and it stays until the pointer crosses the item again. Here a watchdog
/// checks the real pointer position, so the tip can never outlive the hover.
final class StatusHoverTip: NSObject {
    private weak var button: NSStatusBarButton?
    private let label = NSTextField(labelWithString: "")  // shows "\n" lines without wrapping
    private lazy var panel: NSPanel = makePanel()
    private var showAt: Date?
    private var watchdog: Timer?

    /// The tooltip text; nil means no tooltip. Updates a visible tip in place.
    var text: String? {
        didSet {
            guard text != oldValue else { return }
            if text == nil { hide() } else if panel.isVisible { show() }
        }
    }

    init(button: NSStatusBarButton) {
        self.button = button
        super.init()
        button.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    @objc func mouseEntered(with event: NSEvent) {
        showAt = Date().addingTimeInterval(1)
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    @objc func mouseExited(with event: NSEvent) { hide() }

    private var pointerInside: Bool {
        guard let button, let frame = button.window?.frame else { return false }
        return frame.contains(NSEvent.mouseLocation) && !button.isHighlighted  // highlighted = menu open
    }

    private func tick() {
        guard pointerInside, text != nil else { return hide() }
        if let showAt, Date() >= showAt {
            self.showAt = nil
            show()
        }
    }

    private func show() {
        guard let text, let itemFrame = button?.window?.frame else { return }
        label.stringValue = text
        let size = label.fittingSize
        let pad: CGFloat = 4
        panel.setContentSize(NSSize(width: size.width + pad * 2, height: size.height + pad * 2))
        label.frame = NSRect(x: pad, y: pad, width: size.width, height: size.height)
        let screen = (NSScreen.screens.first { $0.frame.contains(itemFrame.origin) } ?? NSScreen.main)?.visibleFrame
            ?? .infinite
        var origin = NSPoint(x: NSEvent.mouseLocation.x, y: itemFrame.minY - panel.frame.height - 4)
        origin.x = max(screen.minX, min(origin.x, screen.maxX - panel.frame.width))
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func hide() {
        showAt = nil
        watchdog?.invalidate()
        watchdog = nil
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 4
        label.font = .toolTipsFont(ofSize: 0)
        label.textColor = .labelColor
        background.addSubview(label)
        panel.contentView = background
        return panel
    }
}
