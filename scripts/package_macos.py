#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Embed and ad-hoc sign local development bundles, inside out."""
import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def copytree(source, destination):
    if destination.exists(): shutil.rmtree(destination)
    shutil.copytree(source, destination, symlinks=True)

def sign(path, entitlements=None, identity="-"):
    args=["codesign","--force","--sign",identity,"--timestamp=none","--options","runtime"]
    if entitlements: args += ["--entitlements",str(entitlements)]
    subprocess.run([*args,str(path)],check=True)

def package(app, runner, deps, fixtures, destination, identity="-", vm_runner=None):
    if destination.exists(): shutil.rmtree(destination)
    (destination/'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(app/'Contents/Info.plist',destination/'Contents/Info.plist')
    shutil.copy2(app/'Contents/MacOS/HuskMac',destination/'Contents/MacOS/HuskMac')
    shutil.copytree(app/'Contents/Resources',destination/'Contents/Resources',symlinks=True)
    app=destination
    frameworks=app/'Contents/Frameworks';frameworks.mkdir(parents=True,exist_ok=True)
    resources=app/'Contents/Resources';resources.mkdir(parents=True,exist_ok=True)
    helpers=app/'Contents/Helpers';helpers.mkdir(parents=True,exist_ok=True)
    shutil.copy2(deps/'lib/libANGLE-shared.dylib',frameworks/'libANGLE-shared.dylib')
    copytree(deps/'lib/MoltenVK.framework',frameworks/'MoltenVK.framework')
    binary=(frameworks/'MoltenVK.framework/MoltenVK').resolve()
    archs=subprocess.check_output(['lipo','-archs',binary],text=True).split()
    if archs!=['arm64']:
        thin=binary.with_suffix('.thin');subprocess.run(['lipo',binary,'-thin','arm64','-output',thin],check=True);thin.replace(binary)
    embedded=helpers/'NativeRunner.app';copytree(runner,embedded)
    if vm_runner:
        if identity != '-':
            raise RuntimeError('VM signing currently supports local development only; release signing is a separate gate')
        copytree(vm_runner,helpers/'VMRunner.app')
    (embedded/'Contents/Resources').mkdir(parents=True,exist_ok=True)
    shutil.copy2(fixtures/'fixture-catalog.json',embedded/'Contents/Resources/fixture-catalog.json')
    fixture_dest=resources/'Fixtures';fixture_dest.mkdir(exist_ok=True)
    for name in ['OrbitGarden.apk','OrbitGardenDusk.apk']: shutil.copy2(fixtures/name,fixture_dest/name)
    shutil.copy2(fixtures/'fixture-catalog.json',resources/'fixture-catalog.json')
    copytree(deps/'notices',resources/'Notices')
    shutil.copy2(ROOT/'LICENSE',resources/'Notices/Husk-LICENSE')
    shutil.copy2(ROOT/'dependencies/macos.lock.json',resources/'Notices/macos.lock.json')
    sign(frameworks/'libANGLE-shared.dylib',identity=identity);sign(frameworks/'MoltenVK.framework',identity=identity)
    entitlement='NativeRunner.development.entitlements' if identity=='-' else 'NativeRunner.entitlements'
    sign(embedded,ROOT/'src/macos/NativeRunner'/entitlement,identity=identity)
    sign(app,identity=identity)
    subprocess.run(['codesign','--verify','--deep','--strict',app],check=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['app','runner','deps','fixtures','destination']: p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--identity',default='-',help='Explicit identity only; default is local ad-hoc, never automatic certificate selection')
    p.add_argument('--vm-runner',type=Path,help='Optional, already packaged native VM helper')
    package(**vars(p.parse_args()))
