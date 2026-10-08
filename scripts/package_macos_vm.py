#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Collect the VM dylib closure into a standalone, ad-hoc signed helper."""
import argparse
import json
import re
from pathlib import Path
import shutil
import subprocess
from build_macos_vm import ROOT, digest
from package_macos import sign

def dependencies(binary):
    lines = subprocess.check_output(['otool', '-L', binary], text=True).splitlines()[1:]
    return [s.strip().split(' (')[0] for s in lines]

def package(runner, deps, graphics, destination):
    receipt=json.loads((deps/'receipt.json').read_text())
    if digest(deps/'lib/libqemu-aarch64-softmmu.dylib') != receipt['qemu']:
        raise RuntimeError('QEMU build receipt mismatch')
    if digest(ROOT/'dependencies/macos-vm.lock.json') != receipt['lock']:
        raise RuntimeError('VM dependency lock changed; rebuild the dependency set')
    for name, expected in receipt['notices'].items():
        if digest(deps/'Notices'/name) != expected:
            raise RuntimeError(f'VM notice mismatch: {name}')
    if destination.exists(): shutil.rmtree(destination)
    shutil.copytree(runner,destination,symlinks=True)
    framework=destination/'Contents/Frameworks';framework.mkdir(exist_ok=True)
    pending=[deps/'lib/libqemu-aarch64-softmmu.dylib', graphics/'lib/libANGLE-shared.dylib']
    copied={}; provenance={}
    while pending:
        source=pending.pop().resolve();name=source.name
        # Preserve load-command basename, even when Homebrew uses versioned symlinks.
        if str(source) in copied: continue
        target=framework/name
        if target.exists() and digest(target)!=digest(source): raise RuntimeError(f'Conflicting dylib: {name}')
        shutil.copy2(source,target);copied[str(source)]=target;provenance[name]={'source':str(source),'sha256':digest(source)}
        for dep in dependencies(source)[1:]:
            if dep.startswith('/opt/homebrew/'): pending.append(Path(dep))
            elif dep.startswith('/') and not dep.startswith(('/System/Library/','/usr/lib/')): raise RuntimeError(f'Uncontained dependency: {dep}')
    for target in copied.values():
        subprocess.run(['install_name_tool','-id','@rpath/'+target.name,target],check=True)
        for dep in dependencies(target)[1:]:
            if dep.startswith('/opt/homebrew/'):
                local=copied[str(Path(dep).resolve())]
                subprocess.run(['install_name_tool','-change',dep,'@loader_path/'+local.name,target],check=True)
    # CMake adds the link-time dependency directory as a build rpath. Remove it
    # from the packaged executable and libraries so the bundle is self-contained.
    for target in [destination/'Contents/MacOS/VMRunner',*copied.values()]:
        load=subprocess.check_output(['otool','-l',target],text=True)
        for rpath in re.findall(r'cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset',load):
            if not rpath.startswith(('@executable_path/','@loader_path/','/usr/lib/')):
                subprocess.run(['install_name_tool','-delete_rpath',rpath,target],check=True)
        if target.suffix=='.dylib': sign(target)
    resources=destination/'Contents/Resources';resources.mkdir(exist_ok=True)
    shutil.copy2(ROOT/'dependencies/macos-vm.lock.json',resources/'macos-vm.lock.json')
    shutil.copy2(ROOT/'dependencies/macos.lock.json',resources/'macos.lock.json')
    shutil.copy2(ROOT/'LICENSE',resources/'Husk-LICENSE')
    shutil.copytree(deps/'Notices', resources/'Notices', dirs_exist_ok=True)
    (resources/'dependencies.json').write_text(json.dumps(provenance,indent=2)+'\n')
    sign(destination,ROOT/'src/macos/VMRunner/VMRunner.development.entitlements')
    subprocess.run(['codesign','--verify','--deep','--strict',destination],check=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['runner','deps','graphics','destination']:p.add_argument('--'+name,type=Path,required=True)
    package(**vars(p.parse_args()))
