# Husk

This fork provides a native **macOS / Apple Silicon** app with an AppKit game
window, a SwiftUI library and independent NativeRunner, WebRunner and optional
VMRunner processes. The arm64 translation paths include Minecraft, Unity,
Java/Dalvik, Cocos, Godot, GameMaker, SDL, Rockstar and NativeActivity. Engine
routing and controlled lifecycle tests do not establish compatibility with every
game. See the [macOS feature and evidence matrix](docs/development/macos/upstream-parity.md)
for implemented behavior, real-application evidence and open work.

Upstream main through `8f65f2f`, four commits after the `3.2.1` tag, is merged with its Git history. The new
ARM32 interpreter is compiled and exercised with controlled ARM/Thumb ELF files,
but macOS launch remains unavailable until input, worker shutdown and save
handling are connected. AOSP boot-path/core-DEX preparation and partial local
Binder transport are not a complete Android system service implementation.
The existing arm64 runtime remains available. Per-game Play without JIT uses
local signing and defaults to off; it does not make engines that generate code
fully compatible.

Build with `./scripts/build_macos.sh`, then open
`build/macos/Product/HuskMac.app`. The build retains pinned graphics and Java
runtime dependencies. `./scripts/test_macos.sh` runs the default background suite;
package verification and hosted CI results are recorded with the exact candidate
in [progress.md](docs/development/macos/progress.md) and the
[source receipt](dependencies/upstream.lock.json). Keep those results separate
from physical input, authenticated Play, real game save/reopen and iOS device
acceptance.

See the [macOS guide](docs/macos.md) for prerequisites and data handling. The main
app and native runner target macOS 14. Optional VM dependencies currently require
macOS 27; VM gameplay and P6 remain open (see the
[P5 report](docs/2026-10-08-macos-p5-report.md)). The translation layer requires no
USB device, Android VM image or personal iOS signing certificate. Distribution
licensing remains documented in the [license audit](docs/01-licensing.md#macos-distribution-status-2026-10-08).
Development work and validation boundaries are tracked under
[`docs/development/macos`](docs/development/macos/task_plan.md); the P0 runner is
retained as a [test harness](tests/macos-p0/README.md).
The iOS source and documentation remain below.

<p align="center">
  <img src="src/app/Husk/Assets.xcassets/AppIcon.appiconset/Icon-Default.png" width="120" height="120" alt="Husk">
</p>

<h1 align="center">Husk</h1>

<p align="center">Android apps and games on your iPhone.</p>

<p align="center">
  <a href="https://itslevii.dev/docs/install">Install</a>
  ·
  <a href="https://itslevii.dev/husk">Compatibility</a>
  ·
  <a href="https://itslevii.dev">Website</a>
  ·
  <a href="https://github.com/Leviidev/Husk/releases">Releases</a>
</p>

<p align="center">
  <a href="https://github.com/Leviidev/Husk/releases"><img src="https://img.shields.io/github/downloads/Leviidev/Husk/total?style=flat-square&color=5B49EB&labelColor=111111" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Leviidev/Husk?style=flat-square&color=5B49EB&labelColor=111111" alt="GPL-2.0-or-later"></a>
</p>

Add an APK, tap it, and it opens full-screen.

- **Translation layer** — the game’s own 64-bit Android code runs on the iPhone. Husk stands in for Android around it (C library, Java, GL, Vulkan, audio, input). No Android boot; a game starts in seconds.
- **Emulation** — a full LineageOS guest under QEMU, for apps the translation layer cannot run yet.
- **PS4** — fake packages and game folders on iOS 17.4+.

## Install

Sideload with SideStore, AltStore, or TrollStore. iOS 15.5 or later.

**Guide:** [itslevii.dev/docs/install](https://itslevii.dev/docs/install)

Add this source in SideStore or AltStore (Sources › +). It also lists AetherPS4, Utsuro, Podium and Fathom:

```
https://itslevii.dev/repo.json
```

Or download `Husk.ipa` from [Releases](https://github.com/Leviidev/Husk/releases).

Games need [JIT](https://itslevii.dev/docs/jit), or they can run from [Play without JIT](https://itslevii.dev/docs/play-without-jit) after you import the certificate that installed Husk.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="Screenshots/gta-san-andreas.jpeg" alt="GTA: San Andreas"><br><sub>GTA: San Andreas</sub></td>
    <td align="center"><img src="Screenshots/minecraft-dungeons.jpeg" alt="Minecraft Dungeons"><br><sub>Minecraft Dungeons</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="Screenshots/library.png" alt="Library"><br><sub>Library</sub></td>
    <td align="center" width="33%"><img src="Screenshots/game-settings.png" alt="Game Settings"><br><sub>Game Settings</sub></td>
    <td align="center" width="33%"><img src="Screenshots/settings.png" alt="Settings"><br><sub>Settings</sub></td>
  </tr>
</table>

## Building

On a Mac with Xcode, plus `meson`, `ninja`, `pkg-config`, `python3`, `xcodegen`, `qemu-img`, and a Rust toolchain with `aarch64-apple-ios`:

```sh
./scripts/ci_build.sh
```

That produces `build/Husk.ipa`. Later app-only rebuilds: `./scripts/package_ipa.sh` → `~/Desktop/Husk.ipa`.

## Licence

GPL-2.0-or-later. Husk links QEMU (GPLv2), so the shipped binary is a combined GPLv2 work. It cannot go on the App Store. See [docs/01-licensing.md](docs/01-licensing.md).
