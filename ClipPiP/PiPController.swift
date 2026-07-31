import Cocoa

/// Manages a single floating "picture-in-picture" panel that shows whatever is
/// currently on the clipboard — an image or text.
final class PiPController {

    private var panel: PiPPanel?

    /// Show (or refresh) the PiP window with the current clipboard contents.
    func showFromClipboard() {
        let pb = NSPasteboard.general
        guard let content = ClipboardContent.read(from: pb) else {
            NSSound.beep()
            return
        }
        present(content)
    }

    /// Toggle: if already visible, close it; otherwise show from clipboard.
    func toggleFromClipboard() {
        if let panel = panel, panel.isVisible {
            close()
        } else {
            showFromClipboard()
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Presentation

    private func present(_ content: ClipboardContent) {
        let contentView = makeContentView(for: content)

        // Reuse existing panel when already visible so a refresh keeps position/size.
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = contentView

        // Size the window for new content. Aspect is preserved by our own uniform
        // scaling (grip + scroll), NOT by contentAspectRatio — setting the latter
        // makes AppKit clamp `setFrame` and causes the window to drift instead of
        // resize when it meets the ratio/min boundary.
        switch content {
        case .image(let image):
            if panel.frame.size == .zero || !panel.isVisible {
                panel.setContentSize(defaultSize(for: image.size))
                centerOnActiveScreen(panel)
            }
        case .text:
            if !panel.isVisible {
                let cap = PiPController.halfScreen()
                panel.setContentSize(NSSize(width: min(420, cap.width),
                                            height: min(300, cap.height)))
                centerOnActiveScreen(panel)
            }
        }

        panel.orderFrontRegardless()
    }

    private func makePanel() -> PiPPanel {
        let panel = PiPPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 140, height: 100)
        panel.onClose = { [weak self] in self?.close() }
        return panel
    }

    private func makeContentView(for content: ClipboardContent) -> RoundedContainerView {
        let container = RoundedContainerView()

        let inner: NSView
        switch content {
        case .image(let image):
            // Draggable image view: dragging anywhere on it moves the window.
            let imageView = DraggableImageView()
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            inner = imageView
            if image.size.height > 0 {
                container.aspectRatio = image.size.width / image.size.height
            }

        case .text(let string):
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false

            // Non-selectable so a click-drag moves the window instead of selecting;
            // scroll wheel still scrolls long text.
            let textView = DraggableTextView()
            textView.string = string
            textView.isEditable = false
            textView.isSelectable = false
            textView.drawsBackground = false
            textView.textColor = .white
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.textContainerInset = NSSize(width: 14, height: 14)
            textView.autoresizingMask = [.width]
            scroll.documentView = textView
            inner = scroll
        }

        inner.translatesAutoresizingMaskIntoConstraints = false
        container.installContent(inner)
        return container
    }

    // MARK: - Sizing helpers

    /// Half the active screen, used as the default upper bound for a new PiP.
    static func halfScreen() -> NSSize {
        let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
            ?? NSSize(width: 1440, height: 900)
        return NSSize(width: vf.width * 0.5, height: vf.height * 0.5)
    }

    private func defaultSize(for imageSize: NSSize) -> NSSize {
        let cap = PiPController.halfScreen()
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: min(360, cap.width), height: min(240, cap.height))
        }
        // Fit within the 50%-of-screen box, preserving aspect; never upscale.
        let scale = min(cap.width / imageSize.width, cap.height / imageSize.height, 1)
        var size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        // Enforce a sensible minimum so tiny images stay usable (still within cap).
        if size.width < 180 || size.height < 120 {
            let up = min(max(180 / max(size.width, 1), 120 / max(size.height, 1)),
                         min(cap.width / max(size.width, 1), cap.height / max(size.height, 1)))
            size = NSSize(width: size.width * up, height: size.height * up)
        }
        return size
    }

    private func centerOnActiveScreen(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - Clipboard content

enum ClipboardContent {
    case image(NSImage)
    case text(String)

    static func read(from pb: NSPasteboard) -> ClipboardContent? {
        // 1. Direct image data on the pasteboard.
        if let image = NSImage(pasteboard: pb), imageHasBitmap(image) {
            return .image(image)
        }
        // 2. File URLs pointing at an image on disk.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where isImageFile(url) {
                if let image = NSImage(contentsOf: url) {
                    return .image(image)
                }
            }
        }
        // 3. Plain text.
        if let string = pb.string(forType: .string), !string.isEmpty {
            return .text(string)
        }
        return nil
    }

    private static func imageHasBitmap(_ image: NSImage) -> Bool {
        return image.representations.contains { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let exts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "bmp", "webp"]
        return exts.contains(url.pathExtension.lowercased())
    }
}

// MARK: - Rounded container: chrome (close button + resize grip) over content

/// Draws a rounded, dark, subtly-bordered background and hosts the PiP "chrome":
/// a close button (top-left) and a resize grip (bottom-right), both revealed on
/// hover. Dragging the background moves the window.
final class RoundedContainerView: NSView {

    /// width / height. When set (images), the resize grip keeps this ratio.
    var aspectRatio: CGFloat? {
        didSet { grip.aspectRatio = aspectRatio }
    }

    private let closeButton = NSButton()
    private let grip = ResizeGripView()
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // Dragging the empty background moves the window.
    override var mouseDownCanMoveWindow: Bool { true }

    // Scrolling over the background resizes the window.
    override func scrollWheel(with event: NSEvent) {
        PiPScroll.resize(window, event)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: "Close")
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.isHidden = true
        addSubview(closeButton)

        grip.translatesAutoresizingMaskIntoConstraints = false
        grip.alphaValue = 0.0
        addSubview(grip)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            grip.trailingAnchor.constraint(equalTo: trailingAnchor),
            grip.bottomAnchor.constraint(equalTo: bottomAnchor),
            grip.widthAnchor.constraint(equalToConstant: 22),
            grip.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    /// Insert the clipboard content view below the chrome so close/grip stay on top.
    func installContent(_ view: NSView) {
        addSubview(view, positioned: .below, relativeTo: closeButton)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @objc private func closeTapped() {
        (window as? PiPPanel)?.onClose?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
        grip.animator().alphaValue = 1.0
    }
    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
        grip.animator().alphaValue = 0.0
    }
}

// MARK: - Resize grip (bottom-right corner)

/// A draggable corner grip that resizes the window, anchoring the top-left.
/// Honors an optional aspect ratio (used for images).
final class ResizeGripView: NSView {
    var aspectRatio: CGFloat?

    private var startMouse = NSPoint.zero
    private var startFrame = NSRect.zero

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        let w = bounds.width
        for off in stride(from: CGFloat(3), through: 13, by: 5) {
            path.move(to: NSPoint(x: w - 3, y: off))
            path.line(to: NSPoint(x: w - off, y: 3))
        }
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x
        let dy = now.y - startMouse.y   // screen coords: up is positive
        var newW = max(window.minSize.width, startFrame.width + dx)
        var newH = max(window.minSize.height, startFrame.height - dy)
        if let a = aspectRatio, a > 0 {
            newH = newW / a
            if newH < window.minSize.height {
                newH = window.minSize.height
                newW = newH * a
            }
        }
        // Anchor the top-left corner (Cocoa origin is bottom-left).
        let origin = NSPoint(x: startFrame.minX, y: startFrame.maxY - newH)
        window.setFrame(NSRect(origin: origin, size: NSSize(width: newW, height: newH)),
                        display: true)
    }
}

// MARK: - Draggable content views

/// Shared scroll→resize routing that ignores trackpad momentum-coast events so a
/// single flick can't run the window down to its minimum in one gesture.
enum PiPScroll {
    static func resize(_ window: NSWindow?, _ event: NSEvent) {
        var delta = event.scrollingDeltaY
        if delta == 0 { delta = event.deltaY }              // classic mouse wheel
        if !event.momentumPhase.isEmpty { delta *= 0.3 }    // damp inertial coast
        (window as? PiPPanel)?.resize(byScrollDelta: delta)
    }
}

/// An NSImageView whose whole surface drags the window, and where scrolling resizes.
final class DraggableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func scrollWheel(with event: NSEvent) { PiPScroll.resize(window, event) }
}

/// A non-selectable NSTextView that drags the window; scrolling resizes instead
/// of scrolling the text.
final class DraggableTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func scrollWheel(with event: NSEvent) { PiPScroll.resize(window, event) }
}

// MARK: - Panel subclass

final class PiPPanel: NSPanel {
    var onClose: (() -> Void)?

    // Borderless panels can't become key by default; allow it for Esc-to-close.
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onClose?()   // Esc closes the panel.
    }

    /// Scale the window by a single factor (preserving aspect) around its center,
    /// clamped so it never drops below `minSize` or grows past the screen.
    /// Positive `delta` (scroll up) grows; negative shrinks.
    func resize(byScrollDelta delta: CGFloat) {
        guard delta != 0 else { return }
        let old = frame
        var factor = 1 + delta * 0.006
        factor = min(1.12, max(0.89, factor))                 // cap per-tick change

        let minFactor = max(minSize.width / old.width, minSize.height / old.height)
        var maxFactor = CGFloat.greatestFiniteMagnitude
        if let vf = (screen ?? NSScreen.main)?.visibleFrame.size {
            maxFactor = min(vf.width / old.width, vf.height / old.height)
        }
        factor = min(max(factor, minFactor), max(minFactor, maxFactor))

        let newSize = NSSize(width: old.width * factor, height: old.height * factor)

        // Anchor the point under the cursor so the window zooms toward the mouse.
        let mouse = NSEvent.mouseLocation
        var fx = old.width  > 0 ? (mouse.x - old.minX) / old.width  : 0.5
        var fy = old.height > 0 ? (mouse.y - old.minY) / old.height : 0.5
        fx = min(1, max(0, fx))
        fy = min(1, max(0, fy))

        let origin = NSPoint(x: mouse.x - fx * newSize.width,
                             y: mouse.y - fy * newSize.height)
        setFrame(NSRect(origin: origin, size: newSize), display: true)
    }
}
