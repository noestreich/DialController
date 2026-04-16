# Dial Controller

A lightweight macOS menu bar app that turns the **Ulanzi Dial D100H** into a fully customisable shortcut launcher.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## What it does

The Ulanzi Dial D100H presents itself as a standard HID keyboard — every button and the scroll wheel emit hardcoded key combos (Cmd+V, Cmd+C, media keys, volume, etc.). Dial Controller intercepts those events before they reach any other app, suppresses them, and fires whatever shortcut *you* assigned instead.

- **7 buttons + scroll wheel** (clockwise / counter-clockwise), all mappable
- **Any shortcut** — including multi-modifier combos and global hotkeys registered by other apps
- Assignments survive restarts (stored in UserDefaults)
- No Dock icon, lives entirely in the menu bar

## Requirements

- macOS 13 Ventura or later (tested on macOS 26 Tahoe)
- Ulanzi Dial D100H (VID `0xFFF1`, PID `0x0082`)
- **Accessibility access** must be granted in System Settings → Privacy & Security → Accessibility

## Installation

1. Download `DialController.app.zip` from the [latest release](../../releases/latest)
2. Unzip and move `DialController.app` to `/Applications`
3. Launch the app — macOS will ask for Accessibility permission; grant it and relaunch
4. The dial icon appears in the menu bar

## Usage

Click the menu bar icon to open the configuration popover.

| Action | How |
|---|---|
| Map a button | Click **Learn**, press the dial button you want to map, then record the shortcut |
| Map scroll wheel | Click **Learn**, turn the dial (CW or CCW), then record the shortcut |
| Remove a mapping | Click the × next to any entry |

The app intercepts the dial's built-in events system-wide, so mappings work in any app.

## Building from source

Requires Xcode Command Line Tools.

```bash
git clone https://github.com/noestreich/DialController.git
cd DialController
make run        # build, bundle (ad-hoc signed), and launch
```

For a Developer-ID-signed and notarised build:

```bash
# One-time: store your Apple notary credentials
xcrun notarytool store-credentials DialControllerNotary \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "xxxx-xxxx-xxxx-xxxx"

make release DEV_ID="Developer ID Application: Your Name (TEAMID)"
```

## How it works

- **HIDManager** — opens the device via `IOHIDManager`, seizes it exclusively, and collects button/dial events. Because the Ulanzi fires the entire press+release sequence in ~300 µs (modifier *after* key, unlike normal keyboards), emission is delayed 25 ms so all IOKit callbacks of a burst arrive before the shortcut is dispatched.
- **EventSuppressor** — an always-active `CGEventTap` at session level. When HIDManager detects a dial event it calls `suppressNext()`, which opens a 100 ms suppression window. Any keyDown/keyUp/flagsChanged that arrives during that window is dropped before reaching other apps.
- **ShortcutRecorder** — records shortcuts via a `CGEventTap` (not `NSEvent`) so it sees events even when another app holds a global hotkey via `RegisterEventHotKey`. Uses `CGEventSource(stateID: .privateState)` when translating key codes so held modifiers don't bleed into the displayed character.
- **KeySender** — synthesises events with a private `CGEventSource` and marks them with a custom userData tag so EventSuppressor lets them pass through.

## License

MIT
