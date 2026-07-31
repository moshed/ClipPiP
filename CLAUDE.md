# ClipPiP

A macOS menu-bar utility that shows the current clipboard contents in a floating,
always-on-top "picture-in-picture" panel, triggered by a global keyboard shortcut.

## Behavior
- **Global shortcut (default ⌥⌘V, user-configurable)** — reads the clipboard and
  shows it in a floating PiP panel. Pressing it again while open **toggles closed**.
- **Change the shortcut**: menu-bar icon → "Change Shortcut…" opens a recorder
  window (`ShortcutWindowController` + `RecorderButton`). Records the next
  key-with-modifier via a local `NSEvent` keyDown monitor, persists it
  (`ShortcutStore` → UserDefaults `hotKeyCode`/`hotKeyModifierFlags`), and
  re-registers live via `HotKeyManager.setPrimary` (unregisters the old Carbon
  hot key first). Requires ≥1 of ⌘/⌥/⌃. Menu label shows the active combo.
- Handles **images** (pasteboard image data or a copied image file), and **text**
  (shown in a scrollable, selectable monospace view). Non-image files / empty
  clipboard → system beep.
- Panel is `.floating` level, joins **all Spaces**, survives app deactivation.
- **Move**: drag anywhere on the content. Works because content views override
  `mouseDownCanMoveWindow = true` (image + a non-selectable text view) combined
  with `isMovableByWindowBackground`. Borderless panels swallow drags on plain
  subviews, so this override is required — that's why it "wasn't movable" before.
- **Resize**: two ways — (a) a `ResizeGripView` in the bottom-right corner
  (revealed on hover) drags to resize, anchoring the top-left; (b) **scroll-wheel
  anywhere on the window** scales it (`PiPPanel.resize(byScrollDelta:)`),
  aspect-preserved, clamped between `minSize` and the full screen. Zoom is
  **anchored at the cursor** (point under the mouse stays fixed), not the center.
  Momentum coast is damped (not dropped) so two-finger scroll always responds. Scroll is
  intercepted on the image view, text view, and background (the text view's
  `scrollWheel` override suppresses text scrolling by design).
- **Default size**: fits within **50% of the active screen** (width AND height),
  aspect-preserved, never upscaled — `PiPController.halfScreen()` +
  `defaultSize(for:)`. Text defaults to min(420×300, half-screen).
- Close via: the **× button** (appears on hover, top-left), **Esc**, or the
  menu-bar item.
- **No Dock icon** (`LSUIElement`); lives in the menu bar (SF Symbol `pip`).

## Architecture
- `main.swift` — AppKit entry point, `.accessory` activation policy.
- `AppDelegate.swift` — menu-bar status item + registers the ⌥⌘V hot key.
- `HotKeyManager.swift` — Carbon `RegisterEventHotKey` wrapper. Chosen over an
  `NSEvent` global monitor because Carbon hot keys need **no Accessibility
  permission**.
- `PiPController.swift` — reads clipboard (`ClipboardContent` enum), builds the
  panel (`PiPPanel`) + rounded chrome (`RoundedContainerView` with hover close
  button). Reuses one panel while visible so a refresh keeps position/size.

## Redeploy (IMPORTANT — changes only land on a full restart)

`open` on a still-running app just re-activates the **stale** instance, so a
rebuild appears to "do nothing." Always fully quit, wait for the process to be
gone, replace the bundle, relaunch, then verify. Use `./redeploy.sh` which does
exactly this and confirms the launched binary matches the fresh build.

## Build
```
cd "/Users/moshe/Apps/ClipPiP"
xcodebuild -project ClipPiP.xcodeproj -scheme ClipPiP -configuration Release \
  -derivedDataPath build build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```
Product: `build/Build/Products/Release/ClipPiP.app`. Bundle id `com.DNZ.clippip`.

## Notes / gotchas
- Project pbxproj written **by hand** (no xcodegen, per user preference).
- To change the shortcut, edit `registerHotKey()` in `AppDelegate.swift`
  (`kVK_ANSI_V` + `cmdKey | optionKey`).
- Carbon hot keys are process-global; no TCC prompt on first launch.
- Deploy like the other menu-bar apps (Beam / Clipboard Manager): copy the built
  `.app` to `/Applications` and relaunch.
