# Licensing and distribution

## macOS distribution status (updated 2026-10-13)

**The macOS artifacts are local development candidates. P6 distribution clearance is incomplete.** The earlier iOS decision below does not clear a macOS `.app`, `.zip` or `.dmg` for release. This section describes the current CMake targets, packaging scripts, pinned source licenses and actual packaged dependency closure.

### Executable boundaries

| Executable | In-process components | Distribution consequence |
| --- | --- | --- |
| `HuskMac` | Husk UI, SharedLibrary and SharedCore | Husk-authored code is GPL-2.0-or-later; no QEMU or StikJIT links in this process |
| `NativeRunner` | Husk translation layer, ANGLE; MoltenVK when Vulkan is loaded | ANGLE is BSD-3-Clause with additional third-party notices; MoltenVK is Apache-2.0 with its own dependency notices. `dlopen` is still in-process integration, not separate-program aggregation |
| `WebRunner` | Husk WebAppRuntime bridge, SharedLibrary/SharedCore, system WebKit | Husk code remains GPL-2.0-or-later; WebKit is provided by macOS, no separate WebKit binary or JIT entitlement is bundled |
| Optional `VMRunner` | Husk VM bridge, QEMU 10.0.12-utm, static virgl/libepoxy, ANGLE and the dylib closure below | QEMU's top-level `LICENSE` specifies GPL version 2 for the emulator as a whole. The combined VM executable and its corresponding source must satisfy that license and every dependency's terms |

The parent communicates with each helper using JSON over pipes. The current VM helper neither links nor loads MoltenVK; the Vulkan translation layer resides in NativeRunner. Storing MoltenVK in the parent bundle's `Frameworks` directory does not imply the parent loads it. These facts support treating the independently executed helpers as an aggregation within one app bundle, but a process boundary alone is not a blanket license exemption. Each executable's complete dependency combination must first be distributable.

For the translation-layer executable, a GPLv3 distribution path may be available under the project's `GPL-2.0-or-later` grant, since Apache-2.0 is compatible with GPLv3, not GPLv2. **This is a proposed release path, not a completed per-file license audit or a repository relicensing decision.** P6 must confirm the licenses of every compiled translation-layer and graphics dependency and include the GPLv3 text if that option is selected. Applying GPLv3 to the QEMU executable cannot be assumed from Husk's own `-or-later` headers.

### Actual VM dependency closure

The review candidate's `VMRunner.app/Contents/Resources/dependencies.json` records each source dylib and SHA-256. The packager currently embeds these components, including dependencies found indirectly through Homebrew:

| Component | Observed version / source | License evidence and remaining obligation |
| --- | --- | --- |
| QEMU | 10.0.12-utm; archive hash in [VM lock](../dependencies/macos-vm.lock.json) | `LICENSE`, `COPYING`, `COPYING.LIB`; provide modified corresponding source and build/install scripts |
| virglrenderer / libepoxy | Commits `482f9d8` / `bf98587`, statically linked | Their `COPYING` files contain permissive notices; retain them and publish Husk patches with the VM source |
| ANGLE | WebKit commit `f488eac`, [graphics lock](../dependencies/macos.lock.json) | BSD-3-Clause plus bundled third-party licenses; audit the compiled dependency subset as well as collecting notices |
| GLib, GObject, GIO, GModule | 2.90.0 | LGPL-2.1-or-later; source and LGPL replacement/relinking obligations apply. The installed Homebrew keg has no license file, so it is not a sufficient notice source |
| pixman | 0.46.4 | MIT; retain `COPYING` |
| libslirp | 4.9.5 | BSD-3-Clause and component notices in `LICENSE` |
| PCRE2 | 10.49 | `LICENCE.md`: BSD-3-Clause WITH PCRE2-exception, plus the JIT's BSD-2-Clause terms |
| libintl | gettext 1.0 | LGPL-2.1-or-later; use `gettext-runtime/intl/COPYING.LIB`. The gettext package's top-level GPLv3 `COPYING` describes other components and cannot substitute for this library's license |
| libssh | 0.12.2 | LGPL-2.1-or-later; currently auto-detected by QEMU's build |
| OpenSSL libcrypto | 3.6.5, loaded by libssh | Apache-2.0; **unresolved conflict with the current GPLv2 QEMU distribution route** |

The observed chain is `VMRunner → libqemu-aarch64-softmmu → libssh → libcrypto.3`. It shares one address space. Separating QEMU from NativeRunner does not remove this issue. The checked QEMU top-level license supplies no blanket OpenSSL linking exception; no exception covering this exact combination has been established. Before distributing the VM, disable the unused SSH block backend and rebuild/recheck its closure, or establish an applicable license grant for the exact linked work. Merely omitting `libcrypto` from the bundle would create a broken application.

The graphics package copies ANGLE/MoltenVK and SPIRV-Cross notices, MoltenVK dependency revisions, the applied `husk-spirv-cross-zero-init-stride.patch` and `moltenvk-build.json` provenance. The modified SPIRV-Cross source must be included in the corresponding-source set for a binary release. The VM builder copies only QEMU, virgl and libepoxy notices. It does **not** yet gather all GLib/PCRE2/libintl/libssh/OpenSSL/slirp/pixman notices and source obligations. Host package versions are partly locked, but the entire transitive dependency source set is not. These are explicit release blockers, not evidence of completed compliance. Keeping both helpers in one `.app` does not remove notice obligations for either.

### Java runtime resources

The macOS candidate now embeds Android userspace components under `Contents/Resources/JavaRuntime`: DEX boot jars, selected ART/libcore/ICU/Conscrypt native libraries and data, tzdata, platform resources and the framework DEX built from this repository. The exact source image, D8 compiler and file hashes are recorded in [java-runtime.lock.json](../dependencies/java-runtime.lock.json) and the packaged `runtime-manifest.json`. It does not embed the source Android disk, kernel, GApps or user APKs.

The build copies the original ART, ICU, Conscrypt and tzdata `NOTICE.html.gz` files and system `NOTICE.xml.gz` into `JavaRuntime/Notices`; it also packages framework/compiler provenance and the source image's build properties. These notices preserve the source material but do not establish complete redistribution compliance. Before P6, map the selected binary and resource subset to its exact corresponding sources and licenses, audit generated framework code and third-party components, and satisfy applicable source/notice requirements. A pinned upstream image and a successful resource hash check prove identity, not release clearance.

### Before distributing a macOS binary

1. Resolve each executable's license combination, including the QEMU/libssh/OpenSSL chain and the NativeRunner/MoltenVK GPL version choice. Repeat the closure audit after rebuilding; review ANGLE's compiled dependencies separately.
2. Ship the applicable license texts, copyright statements and NOTICE files with the app. Include a readable source/version manifest covering direct, static and transitive dependencies. Preserve modified-file notices required by their licenses.
3. Provide the **complete corresponding source for the exact shipped binaries**, including pinned dependency sources, all applied patches, generated-source inputs and scripts controlling compilation and installation. A moving GitHub branch, download URL or the current lock files alone is insufficient. Choose and fulfill a valid GPLv2 §3 / LGPL source-delivery method; if using a written offer, meet its duration and recipient requirements. No source offer is created by this document.
4. Preserve recipients' ability to modify/relink LGPL components and satisfy the relevant license's reverse-engineering requirements. Document how to rebuild and re-sign a modified macOS app; the current ad-hoc signing check is not a release-license acceptance test.
5. Review every distributed guest/firmware artifact separately. The app does not currently contain Android disks or user Minecraft APKs. The optional preparation script downloads LineageOS and extracts EDK2/seed files from a pinned upstream IPA. If those bytes are later redistributed, obtain the exact kernel/system/firmware sources, license notices and build information; an upstream binary hash proves identity, not redistribution compliance.

P6 must produce this source/notice package alongside the signed binary before publication. The current VM packager already refuses non-ad-hoc signing, but that guard is not a compliance certificate. No macOS release, notarization or source offer has been published by this review.

Primary evidence: [macOS targets](../CMakeLists.txt), [VM builder](../scripts/build_macos_vm.py), [VM packager](../scripts/package_macos_vm.py), [native packager](../scripts/package_macos.py), [QEMU source](https://github.com/utmapp/qemu/tree/v10.0.12-utm), [GLib 2.90.0 license](https://github.com/GNOME/glib/blob/2.90.0/LICENSES/LGPL-2.1-or-later.txt), [libintl license](https://github.com/autotools-mirror/gettext/blob/v1.0/gettext-runtime/intl/COPYING.LIB), [GNU Apache-2.0 compatibility explanation](https://www.gnu.org/licenses/license-list.html#apache2), and the license files from the installed versions listed above. Historical P5 candidate hashes remain in the [P5 results](2026-10-08-macos-p5-results.json); the [review report](2026-10-08-macos-review-report.md) records the newer build's validation scope.

## Historical iOS licensing decision

The remainder is the upstream iOS/IPA analysis retained for context. Its “resolved” and “distribution” statements refer to that earlier decision, not the current macOS candidates or their full transitive dependencies.

The brief asked for this to be resolved before substantial original code gets
written. It is resolved. Every claim below was checked against the actual
LICENSE file in the actual source tree, not from memory.

## Decision

**Husk is GPL-2.0-or-later. The source is public. Distribution is a sideloaded
IPA plus the full corresponding source, never the App Store.**

Add `LICENSE` (GPL-2.0), and an SPDX header on every Husk-authored file:

```c
/* SPDX-License-Identifier: GPL-2.0-or-later */
```

## Why GPL-2.0, and why there was never really a choice

QEMU's own `LICENSE`, verbatim from `qemu-10.0.12-utm/LICENSE`:

> 1) The QEMU emulator as a whole is released under the GNU General
>    Public License, version 2.

Husk links QEMU into its own process as `libqemu-aarch64-softmmu.dylib`, and we
ship that dylib inside the IPA. That is distribution of a combined work, so the
combined work must be offered under GPLv2. Choosing `GPL-2.0-or-later` for
Husk's own files is the right shade: it is compatible with QEMU's GPLv2 (the
combination is simply GPLv2 in practice) while leaving the door open to GPLv3
for anything that later needs it.

The second, independent reason: `husk-ios-jit.c` is derived from AetherPS4-iOS's
`src/core/ios/ios_jit_allocator.cpp`, whose header reads

```
// SPDX-FileCopyrightText: Copyright 2024-2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later
```

so that file was going to be GPL-2.0-or-later regardless of QEMU.

## The trap worth naming: UTM's app code is Apache-2.0

`utm/LICENSE` is Apache License 2.0. **Apache-2.0 is not compatible with
GPLv2** (it is compatible with GPLv3, which does not help us, because QEMU as a
whole is GPLv2). So:

| Thing | License | Usable in Husk? |
|---|---|---|
| `utmapp/qemu` fork (the tarball we build) | GPL-2.0 — it *is* QEMU | **Yes** |
| UTM's `scripts/build_dependencies.sh` | ISC (header credits Angelo Haller, 2014) | **Yes** — permissive |
| UTM's Swift/ObjC app code, CocoaSpice, their UI | Apache-2.0 | **No — do not copy** |

Husk has so far taken the QEMU tarball and *ideas* from the build script
(toolchain triple, meson cross-file shape). No UTM application code has been
copied, and none should be. When Phase 0's display bridge gets written, it must
be written fresh rather than adapted from CocoaSpice.

## StikDebug is AGPL-3.0, and that is fine

`StikDebug-PiP/LICENSE` is the GNU Affero GPL v3. That would be a serious
problem if Husk linked it. Husk does not. StikDebug is a **separate application**
that attaches to Husk as a debugger over the gdb-remote protocol. There is no
linking, no shared address space, and no derived work — the only thing crossing
the boundary is a wire protocol, which is not copyrightable subject matter.

Users install StikDebug themselves from its own distribution. Husk should
document that dependency and link to it, not bundle it.

## Built-in StikJIT: MPL-2.0 and MIT, bundled

Built-in StikJIT (docs/06-built-in-jit.md) does bundle code, and it is not
StikDebug's AGPL app:

| Thing | License | Where |
|---|---|---|
| StikJIT 1.9.0 XCFramework, unmodified ([`StikDebug/StikJIT` tag `1.9.0`](https://github.com/StikDebug/StikJIT/tree/1.9.0), `StikJIT.xcframework.zip` SHA-256 `806664393770c68e75f2b6429955bfdd88cfaad09fec2ba70f8ed615ff90c060`) | MPL-2.0 | `src/app/Frameworks/`, embedded in `Husk.app/Frameworks` and used only by the `HuskJITHelper` extension |
| [idevice](https://github.com/jkcoxson/idevice), inside StikJIT and in `libhusk_rppairing.a` (0.1.68) | MIT | linked |
| idevice's Rust dependencies, pinned by `src/rppairing-ios/Cargo.lock` | MIT, Apache-2.0, BSD-3-Clause or ISC | static in the app |
| Husk's pairing wrapper (`src/rppairing-ios`) | GPL-2.0-or-later | static in the app |

MPL-2.0 is file-level copyleft and compatible with the GPL (MPL-2.0 §3.3), and
StikJIT's source is public at the tag above, which is the corresponding source
for the binary. The licence texts ship in the app as `LICENSE-StikJIT-MPL-2.0.txt`,
`LICENSE-idevice-MIT.txt` and `LICENSES-rppairing-crates.txt` (regenerated by
`scripts/build_rppairing_ios.sh`).

## BreakpointJIT: resolved by removing the dependency

`BreakpointJIT.framework` (bundle id `com.stossy11.BreakpointJIT`) ships as a
bare Mach-O with **no license file anywhere in its distribution**. MeloNX, which
vendors it, is MIT — but that covers Ryujinx's code, not a third party's binary
dropped into `Dependencies/`. An unlicensed binary is not something a GPL project
can take a dynamic-linking dependency on.

This turned out not to matter, because the framework is 11 instructions. `otool -tV`
disassembles the whole thing:

```
_BreakGetJITMapping:  mov x16, #0x1 ; brk #0xf00d ; ret
_BreakJITDetach:      mov x16, #0x0 ; brk #0xf00d ; ret
_BreakMarkJITMapping: brk #0x69     ; ret
```

Husk implements these itself in `src/ios-jit/husk-brk.S`, assembled to
byte-identical encodings. What is being reproduced is the *interface* to
StikDebug — the brk immediates and the x16 command numbers, all of which are
plainly documented in StikDebug's own AGPL JavaScript — not anyone's creative
expression. Three instruction pairs dictated entirely by an external protocol are
not a meaningful authorship contribution.

This is also better engineering. Dropping the framework removes the `dlopen`
indirection and, more importantly, removes the AMFI failure mode that forced the
lazy load in the first place: an embedded framework carrying entitlements is
rejected at launch on sideloaded builds ("has entitlements but is not a main
binary"), killing the process during static init before `main()`.

## Distribution

- **Public source repository**, complete and buildable. This is what satisfies
  GPLv2 §3 when we hand someone an IPA.
- **IPA releases** sideloaded via AltStore / SideStore / TrollStore, matching how
  AetherPS4 already ships.
- **Not the App Store.** Two independent blockers, either one sufficient: GPLv2's
  terms conflict with the App Store's distribution restrictions (the long-settled
  VLC question), and Husk fundamentally requires `get-task-allow` plus an external
  debugger attaching at runtime, which App Review does not permit.

## Bundled guest images — the one still-open item

This one is deferred to Phase 1, not answered here, but it should not be
forgotten:

- **Phase 0's Debian arm64 guest** is not redistributed. The build fetches it;
  it never goes in the repo or the IPA.
- **AOSP** is Apache-2.0 for userspace, but the **Linux kernel Husk boots is
  GPLv2**, which means shipping a kernel binary obliges us to offer its source
  too. Pin the exact kernel tag and keep the source link next to the image.
- **Google Play Services must not be bundled**, as the brief already states — the
  brief is right, and this is a licensing prohibition, not just a complexity
  argument.
