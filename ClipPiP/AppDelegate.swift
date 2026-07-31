import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let pip = PiPController()
    private var showItem: NSMenuItem!
    private var shortcutWC: ShortcutWindowController?
    private var shortcut = ShortcutStore.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        applyShortcut(shortcut)
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pip", accessibilityDescription: "ClipPiP")
        }

        let menu = NSMenu()
        showItem = menu.addItem(withTitle: "Show Clipboard PiP",
                                action: #selector(showPiP), keyEquivalent: "")
        menu.addItem(withTitle: "Close PiP",
                     action: #selector(closePiP), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Change Shortcut…",
                     action: #selector(changeShortcut), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipPiP",
                     action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    // MARK: - Hot key

    /// Register (or re-register) the global hot key and reflect it in the menu.
    private func applyShortcut(_ s: Shortcut) {
        shortcut = s
        let ok = HotKeyManager.shared.setPrimary(
            keyCode: s.keyCode,
            modifiers: s.carbonModifiers
        ) { [weak self] in
            self?.pip.toggleFromClipboard()
        }
        showItem?.title = ok
            ? "Show Clipboard PiP  (\(s.displayString))"
            : "Show Clipboard PiP  (shortcut unavailable)"
        if !ok { NSLog("ClipPiP: failed to register global hot key \(s.displayString)") }
    }

    // MARK: - Actions

    @objc private func showPiP() { pip.showFromClipboard() }
    @objc private func closePiP() { pip.close() }

    @objc private func changeShortcut() {
        let wc = shortcutWC ?? ShortcutWindowController(current: shortcut)
        shortcutWC = wc
        wc.onChange = { [weak self] s in self?.applyShortcut(s) }
        wc.showCentered()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
