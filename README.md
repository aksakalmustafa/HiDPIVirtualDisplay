# HiDPI Display

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%2015%2B-lightgrey.svg)](https://www.apple.com/macos/)

Menu bar app that gets you HiDPI (Retina) rendering on large external monitors that macOS won't give it to natively.

macOS gates HiDPI on pixel density, so big monitors don't qualify — you're stuck with either tiny native-res text or blurry scaled rendering. HiDPI Display works around this by creating a virtual display with the HiDPI flag set, then mirroring it to your physical monitor. macOS renders at 2x into the virtual framebuffer, and you get sharp text at whatever effective resolution you pick.

## Install

### Build from source

```bash
git clone https://github.com/aksakalmustafa/HiDPIVirtualDisplay.git
cd HiDPIVirtualDisplay/App
./build.sh
cp -r "build/HiDPI Display.app" /Applications/
```

macOS will probably block it on first launch — right-click the app, hit "Open", confirm in the dialog.

## Usage

Click the display icon in your menu bar, pick your monitor, pick a resolution. Takes a few seconds to apply. To turn it off, select **Disable HiDPI** from the same menu.

### Resolution options

The menu builds HiDPI resolution options dynamically based on your monitor's actual panel resolution (scaled logical sizes derived from the panel’s native pixel dimensions).

### Custom scale

Every monitor submenu has a **Custom Scale...** option — opens a slider for any factor between 1.1× and 2.0×. The resolution preview updates as you drag.

## Monitor-aware auto-apply

When you apply a preset, HiDPI Display remembers which monitor was connected (by vendor and model ID). Auto-apply on reconnect, crash recovery, and wake-from-sleep will only activate if the same monitor is plugged in. If you switch to a different display, the app stays idle instead of applying the wrong configuration. Manually applying a preset on a new monitor updates the binding.

## Auto-start & crash recovery

The app uses private macOS APIs for the virtual display, and those can occasionally crash. There's a built-in restart mechanism:

**Settings → Start at Login** — registers the app as a login item (via `SMAppService`) so it auto-starts on login, restores your last preset, and cleans up any orphaned virtual displays after a crash.

## Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon recommended
  - Base chips (M1/M2/M3/M4): up to ~6144px horizontal
  - Pro/Max/Ultra: 7680px+ horizontal
- Intel Macs may work but are not tested

## Known issues & limitations

- Uses private macOS APIs — could break with future macOS updates
- HDR doesn't work in mirrored mode
- Switching presets or disabling HiDPI briefly restarts the app (virtual displays can only be fully torn down when the process exits)
- Refresh rate is auto-detected; if your monitor flickers, set it manually under Settings → Refresh Rate

## Troubleshooting

**App won't open** — right-click, select "Open", confirm in the security dialog.

**Resolution doesn't apply** — disable HiDPI first, wait a few seconds, try again.

**Phantom displays showing up in System Settings** — the app auto-cleans these on launch, but if you see extras, use **Clean Up Phantom Displays** from the menu bar.

**Flickering** — go to Settings → Refresh Rate and manually match your monitor's refresh rate (common with 165Hz/240Hz displays).

**Notifications not showing while virtual display is active** — enable "Allow notifications when mirroring or sharing the display" in System Settings → Notifications. For Zoom/Teams meetings, enable their built-in DND-during-calls setting so notification banners don't appear on shared screens.

## How it works

1. Reads the connected monitor's native panel resolution at runtime
2. Creates a virtual display with the HiDPI flag and a 2× framebuffer
3. Mirrors the virtual display to your physical monitor
4. macOS renders at 2× into the virtual framebuffer, which is scaled to your monitor's native resolution

Built with Swift (UI) and Objective-C (display management). The VirtualDisplayManager is compiled without ARC (`-fno-objc-arc`) because the private CGVirtualDisplay APIs need manual memory control.

## Uninstall

1. Menu bar icon → Settings → toggle off **Start at Login**
2. Menu bar icon → **Quit**
3. Trash the app from /Applications

## Credits

Forked from [knightynite/HiDPIVirtualDisplay](https://github.com/knightynite/HiDPIVirtualDisplay) by AL in Dallas — the original app and all core virtual display logic. This fork adds dynamic resolution detection, macOS Sequoia support, SMAppService login items, and various UX improvements.

## License

MIT — free software, use at your own risk. This relies on undocumented macOS APIs that Apple could change at any time.

---

Made by AL in Dallas
