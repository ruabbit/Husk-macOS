#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build and run local, synthetic macOS P0 checks. No dependency downloads."""
import argparse
import glob
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "build/macos-p0"
NEXT = ROOT / "src/translation-layer-next"
CLASSIC = ROOT / "src/translation-layer"
RESULTS = []
COMMANDS = []


def command(args, **kwargs):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, **kwargs)
    COMMANDS.append(dict(argv=result.args, exit=result.returncode, stdout=result.stdout, stderr=result.stderr))
    result.check_returncode()
    return result.stdout.strip()


def tool(env, candidates):
    for candidate in [os.environ.get(env), *candidates]:
        if candidate and (found := shutil.which(str(candidate))):
            return found
    raise RuntimeError(f"Set {env} to an installed tool; no tools are downloaded")


def sign(path, entitlements=None):
    args = ["codesign", "--force", "--sign", "-", "--options", "runtime"]
    if entitlements:
        args += ["--entitlements", entitlements]
    command([*args, path])
    command(["codesign", "--verify", "--strict", path])
    command(["codesign", "-dvv", path])
    flags = re.search(r"flags=0x([0-9a-fA-F]+)", COMMANDS[-1]["stderr"])
    assert flags and int(flags[1], 16) & 0x10000, "Hardened Runtime is missing"


def run(name, args, expected=(0,), contains=None, env=None):
    start = time.monotonic()
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True,
                            timeout=30, env={**os.environ, **(env or {})})
    output = result.stdout + result.stderr
    (OUT / f"{name}.log").write_text(output)
    ok = result.returncode in expected and (contains is None or contains in output)
    RESULTS.append(dict(name=name, passed=ok, exit=result.returncode,
                        seconds=round(time.monotonic() - start, 3), log=f"{name}.log"))
    print(f"{'PASS' if ok else 'FAIL'} {name} exit={result.returncode}", flush=True)
    if not ok:
        raise AssertionError(output or f"unexpected status {result.returncode}")
    return output


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("P0 execution requires an Apple Silicon Mac")
    host = os.environ.get("HOST_CC") or command(["xcrun", "--find", "clang"])
    elf = tool("ELF_CC", ["/opt/homebrew/opt/llvm/bin/clang", "/usr/local/opt/llvm/bin/clang", "clang"])
    ndk = sorted(glob.glob(str(Path.home() / "Library/Android/sdk/ndk/*/toolchains/llvm/prebuilt/darwin-*/bin/ld.lld")), reverse=True)
    ld = tool("ELF_LD", ["ld.lld", *ndk])
    provenance = dict(platform=platform.platform(), machine=platform.machine(),
                      head=command(["git", "rev-parse", "HEAD"], cwd=ROOT),
                      xcode=command(["xcodebuild", "-version"]),
                      host_cc=host, host_version=command([host, "--version"]),
                      elf_cc=elf, elf_version=command([elf, "--version"]),
                      elf_ld=ld, ld_version=command([ld, "--version"]),
                      python=sys.version, page_size=os.sysconf("SC_PAGE_SIZE"))
    (OUT / "environment.json").write_text(json.dumps(provenance, indent=2) + "\n")
    for name, keys in {"none": [], "jit": ["allow-jit"], "unsigned": ["allow-unsigned-executable-memory"],
                       "both": ["allow-jit", "allow-unsigned-executable-memory"]}.items():
        with (OUT / f"{name}.plist").open("wb") as f:
            plistlib.dump({f"com.apple.security.cs.{key}": True for key in keys}, f)
    sdk = command(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    common = [host, "-isysroot", sdk, "-O2", "-g", "-Wall", "-Wextra", "-I", NEXT, "-I", CLASSIC]
    command([*common, HERE / "xmem-test.c", HERE / "host-adapter.c", NEXT / "husk-tl-xmem.c", "-o", OUT / "xmem-dev"])
    modern = [NEXT / "husk-tl-ld.c", NEXT / "husk-tl-a64.c", NEXT / "husk-tl-xmem.c",
              CLASSIC / "husk-tl-elf.c", CLASSIC / "husk-tl-zip.c", HERE / "host-adapter.c"]
    command([*common, HERE / "loader-test.c", *modern, "-lz", "-o", OUT / "loader-test"])
    sign(OUT / "loader-test", OUT / "unsigned.plist")
    command([*common, HERE / "classic-test.c", CLASSIC / "husk-tl-elf.c", CLASSIC / "husk-tl-json.c",
             "-Wl,-dead_strip", "-o", OUT / "classic-test"])
    sign(OUT / "classic-test", OUT / "jit.plist")

    libs = {}
    for name, page, tls, packing in [("rela4", 4096, True, "none"), ("relr16", 16384, True, "relr"),
                                     ("aps2-4", 4096, True, "android"), ("initial-exec", 4096, True, "none"),
                                     ("classic4", 4096, False, "none"), ("classic16", 16384, False, "none")]:
        objects = []
        for src in ["fixture.c", "x18.S"] if tls else ["fixture.c"]:
            obj = OUT / f"{name}-{src}.o"
            flags = ["-DP0_TLS", "-fno-emulated-tls"] if tls else []
            if name == "initial-exec":
                flags.append("-ftls-model=initial-exec")
            command([elf, "--target=aarch64-linux-android29", "-O2", "-fPIC", "-ffreestanding",
                     "-fno-stack-protector", "-mno-outline-atomics", *flags, "-c", HERE / src, "-o", obj])
            objects.append(obj)
        lib = OUT / f"lib{name}.so"
        command([ld, "-shared", "--no-relax", "--hash-style=gnu", "-soname", lib.name, "-z", f"max-page-size={page}",
                 f"--pack-dyn-relocs={packing}", *objects, "-o", lib])
        raw = lib.read_bytes()
        phoff = struct.unpack_from("<Q", raw, 32)[0]
        phsize, phnum = struct.unpack_from("<HH", raw, 54)
        headers = [struct.unpack_from("<IIQQQQQQ", raw, phoff + i * phsize) for i in range(phnum)]
        loads = [p for p in headers if p[0] == 1]
        assert loads and all(p[7] == page for p in loads)
        writable_pages, code_pages = set(), set()
        for p in loads:
            pages = set(range(p[3] // 16384, (p[3] + p[6] + 16383) // 16384))
            if p[1] & 1:
                code_pages |= pages
            if p[1] & 2:
                writable_pages |= pages
        mixed = sorted(writable_pages & code_pages)
        assert bool(mixed) == (page == 4096)
        dynamic = next(p for p in headers if p[0] == 2)
        tags = [struct.unpack_from("<qQ", raw, i)[0] for i in range(dynamic[2], dynamic[2] + dynamic[5], 16)]
        assert (36 in tags) == (packing == "relr")
        assert (0x60000011 in tags) == (packing == "android")
        libs[lib.name] = dict(sha256=hashlib.sha256(raw).hexdigest(), page_alignment=page,
                             mixed_host_pages=mixed, dynamic_tags=[hex(tag) for tag in tags],
                             load_segments=[dict(flags=p[1], vaddr=p[3], memsz=p[6]) for p in loads])
    (OUT / "fixtures.json").write_text(json.dumps(libs, indent=2) + "\n")
    with zipfile.ZipFile(OUT / "fixtures.apk", "w", compression=zipfile.ZIP_DEFLATED) as z:
        for name in libs:
            z.write(OUT / name, f"lib/arm64-v8a/{name}")
    app = OUT / "Husk P0 Runner.app"
    (app / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    with (app / "Contents/Info.plist").open("wb") as f:
        plistlib.dump(dict(CFBundleIdentifier="org.husk.macos.p0.runner", CFBundleName="Husk P0 Runner",
                          CFBundleExecutable="NativeRunner", CFBundlePackageType="APPL",
                          CFBundleVersion="1", NSHighResolutionCapable=True, LSMinimumSystemVersion="14.0"), f)
    command([*common, "-mmacosx-version-min=14.0", "-fobjc-arc", ROOT / "tests/macos-p0/harness/NativeRunner.m",
             *modern, "-framework", "AppKit", "-framework", "Security", "-lz",
             "-o", app / "Contents/MacOS/NativeRunner"])
    sign(app, ROOT / "tests/macos-p0/harness/NativeRunner.entitlements")
    runtime = app / "Contents/MacOS/NativeRunner"
    dependencies = command(["otool", "-L", runtime])
    assert all(line.strip().startswith(("/usr/lib/", "/System/Library/")) for line in dependencies.splitlines()[1:]), dependencies
    assert command(["lipo", "-archs", runtime]) == "arm64"
    entitlement_xml = command(["codesign", "-d", "--entitlements", "-", "--xml", runtime])
    assert plistlib.loads(entitlement_xml.encode()) == {"com.apple.security.cs.allow-unsigned-executable-memory": True}
    (OUT / "runner-dependencies.txt").write_text(dependencies + "\n")
    sources = [ROOT / "scripts/test_macos_p0.sh", *HERE.glob("*"), *(ROOT / "tests/macos-p0/harness").glob("*"),
               *NEXT.glob("*.h"), *CLASSIC.glob("*.h"), *modern, CLASSIC / "husk-tl-load.c"]
    manifest = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sources if p.is_file()}
    (OUT / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return common, modern


def memory_tests(faults=False):
    run("alias-development", [OUT / "xmem-dev"])
    run("invalid-sizes", [OUT / "xmem-dev", "invalid"])
    for value in ["0", "-1", "bogus", "18446744073709551615"]:
        run(f"invalid-env-{value}", [OUT / "xmem-dev"], expected=(11,), contains="TL_XMEM_MIB", env={"TL_XMEM_MIB": value})
    for config in ["none", "jit", "unsigned", "both"]:
        target = OUT / f"xmem-{config}"
        shutil.copy2(OUT / "xmem-dev", target)
        sign(target, OUT / f"{config}.plist")
        if config in ("none", "jit"):
            if faults:
                run(f"alias-{config}-refused", [target], expected=(-signal.SIGKILL,))
        else:
            run(f"alias-{config}", [target], contains="PASS dual alias")
    run("map-jit-code", [OUT / "xmem-jit", "map-jit"], contains="constant=42")
    if faults:
        run("map-jit-data-refused", [OUT / "xmem-jit", "map-jit", "store"],
            expected=(-signal.SIGBUS, -signal.SIGSEGV), contains="attempting guest store")
    for name in ["rela4", "relr16", "aps2-4", "initial-exec"]:
        run(f"elf-{name}", [OUT / "loader-test", OUT / "fixtures.apk", f"lib{name}.so"])
    run("elf-exhaustion", [OUT / "loader-test", OUT / "fixtures.apk", "exhaust"])
    run("classic-tls-refused", [OUT / "classic-test", OUT / "librela4.so"], expected=(20,), contains="uses TLS")
    run("classic-16k", [OUT / "classic-test", OUT / "libclassic16.so"])
    run("classic-4k-refused", [OUT / "classic-test", OUT / "libclassic4.so"], expected=(20,), contains="cannot execute this layout")


def core_tests(common):
    specs = {
        "planner": [ROOT / "tests/translation-layer/plan_test.c", CLASSIC / "husk-tl-elf.c"],
        "prefs": [ROOT / "tools/prefs-test.c", CLASSIC / "husk-tl-prefs.c"],
        "blit": [ROOT / "tools/blit-test.c", CLASSIC / "husk-tl-blit.c"],
        "variadic": [ROOT / "tools/va-test.c", NEXT / "husk-tl-va.c", HERE / "host-adapter.c"],
    }
    for name, sources in specs.items():
        target = OUT / f"core-{name}"
        extra = ["-framework", "CoreGraphics"] if name == "blit" else []
        command([*common, *sources, *extra, "-o", target])
        run(f"core-{name}", [target])
    # Keep the existing scanner oracle with explicit ELF tool provenance.
    env = json.loads((OUT / "environment.json").read_text())
    tool_dir = OUT / "fixture-tools"
    tool_dir.mkdir(exist_ok=True)
    llvm_dir = Path(env["elf_ld"]).parent
    for name, path in {"clang": env["elf_cc"], "ld.lld": env["elf_ld"],
                       "llvm-readelf": tool("ELF_READELF", [llvm_dir / "llvm-readelf", "llvm-readelf"]),
                       "llvm-objdump": tool("ELF_OBJDUMP", [llvm_dir / "llvm-objdump", "llvm-objdump"])}.items():
        link = tool_dir / name
        if link.is_symlink():
            link.unlink()
        link.symlink_to(path)
    scanner = OUT / "core-scanner"
    command([*common, "-fsanitize=address,undefined", ROOT / "tests/translation-layer/scan_cli.c",
             *[CLASSIC / f"husk-tl-{name}.c" for name in ["json", "zip", "elf", "scan", "probe"]],
             HERE / "probe-adapter.c", "-lz", "-o", scanner])
    scanner_out = OUT / "scanner"
    scanner_out.mkdir(exist_ok=True)
    run("core-scanner", [sys.executable, ROOT / "tests/translation-layer/test_scan.py", scanner_out, scanner],
        env={"PATH": str(tool_dir) + os.pathsep + os.environ["PATH"]})
    sdk = command(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"])
    for source in [NEXT / "husk-tl-xmem.c", NEXT / "husk-tl-ld.c", CLASSIC / "husk-tl-load.c"]:
        run(f"ios-syntax-{source.stem}", [common[0], "-isysroot", sdk, "-target", "arm64-apple-ios16.4",
            "-fsyntax-only", "-I", NEXT, "-I", CLASSIC, source])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--suite", choices=["all", "memory", "runner", "core"], default="all")
    parser.add_argument("--gui", action="store_true", help="Opt in to visible windows and focus/menu checks")
    parser.add_argument("--faults", action="store_true", help="Opt in to deliberate crashes/kills; macOS may show crash reports")
    parser.add_argument("--cycles", type=int, help="Runner start/stop count (default 2 in background, 1 with --gui)")
    args = parser.parse_args()
    if args.gui and args.faults:
        parser.error("Run fault injection separately without --gui")
    cycles = args.cycles if args.cycles is not None else (1 if args.gui else 2)
    if not 1 <= cycles <= 100:
        parser.error("--cycles must be between 1 and 100")
    try:
        common, _ = build()
        if not args.build_only:
            if args.suite in ("all", "memory"):
                memory_tests(args.faults)
            if args.suite in ("all", "runner"):
                from lifecycle_test import tests
                tests(OUT, RESULTS, sign, gui=args.gui, faults=args.faults, cycles=cycles)
            if args.suite in ("all", "core"):
                core_tests(common)
    finally:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / "results.json").write_text(json.dumps(RESULTS, indent=2) + "\n")
        (OUT / "commands.json").write_text(json.dumps(COMMANDS, indent=2) + "\n")
        (OUT / "test-selection.json").write_text(json.dumps(dict(suite=args.suite, gui=args.gui,
            faults=args.faults, cycles=cycles, build_only=args.build_only), indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stdout, error.stderr, file=sys.stderr)
        raise
