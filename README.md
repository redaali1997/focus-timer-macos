# Focus Timer for macOS

A native SwiftUI port of [Focus Timer](https://github.com/focustimerhq/FocusTimer) (formerly gnome-pomodoro).

## Features

| Original (GNOME) | macOS port |
|---|---|
| Custom pomodoro / short / long break lengths, cycles | ✅ + 25/5, 50/10, 90/20 presets |
| Confirm before starting a break / pomodoro | ✅ with "Start" / "Skip" notification actions, or start the pomodoro on your first mouse/keyboard activity after a break |
| Pause on lock screen, session expiry | ✅ (lock screen + sleep) |
| Screen overlay during breaks (blur, reopen delay, lock delay, dismiss gesture) | ✅ on every display |
| System tray indicator | ✅ menu bar with live countdown |
| Compact timer | ✅ floating always-on-top window |
| Global hotkeys | ✅ recordable (default ⌃⌥P / ⌃⌥S / ⌃⌥X) |
| Sounds: finished alerts + background (clock, metronome, brown noise), volumes | ✅ + system sounds + custom files |
| Daily / weekly / monthly stats | ✅ charts + month heatmap |
| Automation (shell commands on events) | ✅ with `$FT_*` env variables and run log |
| D-Bus / CLI | ✅ `focustimer://` URL scheme, `focustimer` CLI, `status.json` |
| Light / dark color scheme, autostart | ✅ + hide Dock icon |

Extras: Arabic UI (RTL) with an in-app language switch; per-task **focus profiles** (turn on a macOS Focus via Shortcuts and keep chosen apps closed during pomodoros, reopened on the break); task name per session with per-task stats, daily goal + streak, +1 minute / restart interval, CSV export.

## Build

```bash
xcodegen generate
xcodebuild -project FocusTimer.xcodeproj -scheme FocusTimer -configuration Release -derivedDataPath build build
open "build/Build/Products/Release/Focus Timer.app"
```

Data lives in `~/Library/Application Support/FocusTimer/`.

## License

GPL-3.0, like the original. Sounds are CC-BY, see `Resources/Sounds/CREDITS.txt`.
