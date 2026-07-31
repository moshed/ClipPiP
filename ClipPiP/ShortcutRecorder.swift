import AppKit
import Carbon.HIToolbox

/// A button that records a keyboard shortcut. Click it, then press the desired
/// key combination; it captures the next key-with-modifier and reports it.
final class RecorderButton: NSButton {
    var onCapture: ((Shortcut) -> Void)?
    var shortcut: Shortcut? { didSet { updateTitle() } }

    private var monitor: Any?
    private var isRecording = false

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); commonInit() }
    required init?(coder: NSCoder) { super.init(coder: coder); commonInit() }

    private func commonInit() {
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }

    private func updateTitle() {
        if isRecording {
            title = "Type shortcut…  (Esc to cancel)"
        } else if let s = shortcut {
            title = "\(s.displayString)   —  click to change"
        } else {
            title = "Click to set a shortcut"
        }
    }

    @objc private func toggleRecording() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        updateTitle()
        // Local monitor reliably captures ⌘/⌥ combos that would otherwise be
        // routed as menu key-equivalents. Returning nil swallows the event.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        updateTitle()
    }

    private func handle(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { stop(); return }   // cancel

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Require at least one "hard" modifier so the global hot key is sane.
        guard mods.contains(.command) || mods.contains(.option) || mods.contains(.control) else {
            NSSound.beep()
            return
        }
        let s = Shortcut(keyCode: UInt32(event.keyCode), modifierFlags: mods)
        shortcut = s
        stop()
        onCapture?(s)
    }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}

/// A small window that lets the user set the global shortcut.
final class ShortcutWindowController: NSWindowController, NSWindowDelegate {
    var onChange: ((Shortcut) -> Void)?

    convenience init(current: Shortcut) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "ClipPiP Shortcut"
        self.init(window: window)
        window.delegate = self
        window.isReleasedWhenClosed = false
        build(current: current)
    }

    private func build(current: Shortcut) {
        guard let content = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "Global shortcut to show the clipboard PiP:")
        heading.font = .systemFont(ofSize: 13, weight: .medium)

        let recorder = RecorderButton()
        recorder.shortcut = current
        recorder.onCapture = { [weak self] s in
            ShortcutStore.save(s)
            self?.onChange?(s)
        }

        let hint = NSTextField(wrappingLabelWithString:
            "Click the button, then press the keys you want (e.g. ⌃⌥C). "
            + "Needs at least ⌘, ⌥, or ⌃ so it won't clash with typing.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [heading, recorder, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
    }

    func showCentered() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
