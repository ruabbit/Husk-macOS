#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Pinned macOS graphics dependencies. Never uses system-installed runtime dylibs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "dependencies/macos.lock.json").read_text())
SOURCES = ROOT / "third_party/build/macos"
OUT = ROOT / "build/macos-deps"
LOGS = ROOT / "build/logs"

def record(name, binary):
    manifest = {"commit": LOCK[name]["commit"], "binary": str(binary.relative_to(OUT)),
                "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
    (OUT / f"{name}.json").write_text(json.dumps(manifest, indent=2) + "\n")

def verify(prefix):
    for name in ("angle", "moltenvk"):
        manifest = json.loads((prefix / f"{name}.json").read_text())
        binary = prefix / manifest["binary"]
        if manifest["commit"] != LOCK[name]["commit"] or hashlib.sha256(binary.read_bytes()).hexdigest() != manifest["sha256"]:
            raise RuntimeError(f"{name} cached artifact does not match its pinned source record")
    print("Pinned macOS graphics cache verified", flush=True)


def run(args, cwd=None, log=None):
    print(" ".join(str(a) for a in args[:5]), flush=True)
    if log:
        with (LOGS / log).open("w") as f:
            result = subprocess.run([str(a) for a in args], cwd=cwd, stdout=f, stderr=subprocess.STDOUT)
        if result.returncode:
            print((LOGS / log).read_text(errors="replace")[-8000:])
            result.check_returncode()
    else:
        subprocess.run([str(a) for a in args], cwd=cwd, check=True)


def fetch(name):
    spec = LOCK[name]
    path = SOURCES / name
    if not (path / ".git").exists():
        path.mkdir(parents=True, exist_ok=True)
        run(["git", "init", path])
        run(["git", "remote", "add", "origin", spec["repository"]], cwd=path)
        if name == "angle":
            run(["git", "config", "remote.origin.promisor", "true"], cwd=path)
            run(["git", "config", "remote.origin.partialclonefilter", "blob:none"], cwd=path)
            run(["git", "sparse-checkout", "init", "--cone"], cwd=path)
            run(["git", "sparse-checkout", "set", "Source/ThirdParty/ANGLE", "Configurations", "Tools/ccache"], cwd=path)
        run(["git", "fetch", "--depth", "1", *(["--filter=blob:none"] if name == "angle" else []), "origin", spec["commit"]], cwd=path)
        run(["git", "checkout", "--detach", spec["commit"]], cwd=path)
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=path, text=True).strip()
    if actual != spec["commit"]:
        raise RuntimeError(f"{path} is at {actual}; expected {spec['commit']}. Refusing to overwrite it.")
    return path


def angle(path):
    source = path / LOCK["angle"]["subdirectory"]
    derived = OUT / "angle-derived"
    args = ["xcodebuild", "-project", "ANGLE.xcodeproj", "-scheme", "ANGLE", "-configuration", "Release",
            "-sdk", "macosx", "-arch", "arm64", "-jobs", os.environ.get("HUSK_BUILD_JOBS", "4"), "-derivedDataPath", derived,
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "MACOSX_DEPLOYMENT_TARGET=14.0",
            "WK_AVAILABILITY_OVERLAY_FLAGS=", "WK_AVAILABILITY_OVERLAY_SWIFT_FLAGS=", "WK_ADDITIONAL_SDKS=",
            "WEBCORE_LIBRARY_DIR=/usr/local/lib", "NORMAL_UMBRELLA_FRAMEWORKS_DIR=", "build"]
    run(args, cwd=source, log="macos-angle.log")
    candidates = list(derived.glob("Build/Products/Release/libANGLE-shared.dylib"))
    if len(candidates) != 1:
        raise RuntimeError("ANGLE output missing")
    lib = candidates[0]
    symbols = subprocess.check_output(["nm", "-gU", lib], text=True)
    aliases = OUT / "angle-aliases.txt"
    aliases.write_text("".join(f"{s} {s.replace('_EGL_', '_egl', 1)}\n" for s in
                              (line.split()[-1] for line in symbols.splitlines() if line.split()) if s.startswith("_EGL_")))
    if aliases.stat().st_size:
        run([*args, f"OTHER_LDFLAGS=$(inherited) -Wl,-alias_list,{aliases}"], cwd=source, log="macos-angle-aliases.log")
    target = OUT / "lib/libANGLE-shared.dylib"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(lib, target)
    run(["install_name_tool", "-id", "@rpath/libANGLE-shared.dylib", target])
    shutil.copytree(source / "include", OUT / "include", dirs_exist_ok=True)
    shutil.copy2(source / "LICENSE", OUT / "notices/ANGLE-LICENSE")
    for notice in source.rglob("*"):
        if notice.is_file() and notice.name.lower().startswith(("license", "copying", "notice")) and ".git" not in notice.parts:
            destination = OUT / "notices/ANGLE" / notice.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(notice, destination)
    record("angle", target)


def moltenvk(path):
    if not (path / "External/build/Release/SPIRVCross.xcframework").exists():
        run(["./fetchDependencies", "--macos"], cwd=path, log="macos-moltenvk-dependencies.log")
    run(["make", "macos"], cwd=path, log="macos-moltenvk.log")
    framework = path / "Package/Release/MoltenVK/dynamic/MoltenVK.xcframework/macos-arm64_x86_64/MoltenVK.framework"
    if not framework.exists():
        raise RuntimeError(f"MoltenVK output missing: {framework}")
    dest = OUT / "lib/MoltenVK.framework"
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(framework, dest, symlinks=True)
    shutil.copy2(path / "LICENSE", OUT / "notices/MoltenVK-LICENSE")
    shutil.copytree(path / "External/Vulkan-Headers/include", OUT / "include", dirs_exist_ok=True)
    shutil.copytree(path / "ExternalRevisions", OUT / "notices/MoltenVK-ExternalRevisions", dirs_exist_ok=True)
    for dependency in (path / "External").iterdir():
        if dependency.is_dir() and (dependency / ".git").exists():
            for notice in dependency.glob("LICENSE*"):
                if notice.is_file():
                    shutil.copy2(notice, OUT / "notices" / f"{dependency.name}-{notice.name}")
    record("moltenvk", dest / "Versions/A/MoltenVK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", choices=["angle", "moltenvk", "all"], default="all")
    parser.add_argument("--fetch-only", action="store_true")
    parser.add_argument("--verify", type=Path, metavar="PREFIX", help="Read-only validation of cached artifacts")
    args = parser.parse_args()
    if args.verify:
        verify(args.verify)
        raise SystemExit(0)
    LOGS.mkdir(parents=True, exist_ok=True)
    (OUT / "notices").mkdir(parents=True, exist_ok=True)
    for name in (["angle", "moltenvk"] if args.only == "all" else [args.only]):
        source = fetch(name)
        if not args.fetch_only:
            globals()[name](source)
    shutil.copy2(ROOT / "dependencies/macos.lock.json", OUT / "lock.json")
