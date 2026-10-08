#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Verify platform, dependency paths, runtime flags and least-privilege split."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess

def command(*args):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, check=True)

def verify(app):
    command('codesign','--verify','--deep','--strict',app)
    main=app/'Contents/MacOS/HuskMac'
    runner=app/'Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner'
    angle=app/'Contents/Frameworks/libANGLE-shared.dylib'
    molten=(app/'Contents/Frameworks/MoltenVK.framework/MoltenVK').resolve()
    results={}
    for path in [main,runner,angle,molten]:
        relative=str(path.relative_to(app))
        arch=command('lipo','-archs',path).stdout.strip()
        assert arch=='arm64',(relative,arch)
        platform=command('xcrun','vtool','-show-build',path).stdout
        assert 'platform MACOS' in platform,(relative,platform)
        minimum=re.findall(r'minos (\d+(?:\.\d+)+)',platform)
        assert minimum and all(tuple(map(int,v.split('.'))) <= (14,0) for v in minimum),(relative,minimum)
        dependencies=command('otool','-L',path).stdout.splitlines()[1:]
        deps=[line.strip().split(' (compatibility')[0] for line in dependencies]
        assert all(d.startswith(('/usr/lib/','/System/Library/','@rpath/')) for d in deps),(relative,deps)
        # Non-system imports must resolve within the signed bundle's Frameworks.
        for dep in deps:
            if dep.startswith('@rpath/'):
                assert (app/'Contents/Frameworks'/dep.removeprefix('@rpath/')).exists(),dep
        load=command('otool','-l',path).stdout
        rpaths=re.findall(r'cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset',load)
        assert all(r.startswith(('@executable_path/','@loader_path/','/usr/lib/')) for r in rpaths),(relative,rpaths)
        signature=command('codesign','-dvv',path).stderr
        assert 'runtime' in signature,(relative,signature)
        ent=command('codesign','-d','--entitlements','-','--xml',path).stdout
        entitlements=plistlib.loads(ent.encode()) if ent.strip() else {}
        if path==runner:
            expected={'com.apple.security.cs.allow-unsigned-executable-memory':True}
            if 'Signature=adhoc' in signature: expected['com.apple.security.cs.disable-library-validation']=True
            assert entitlements==expected,(relative,entitlements)
        else:
            assert entitlements=={},(relative,entitlements)
        results[relative]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'architecture':arch,
            'minimumOS':minimum,'dependencies':deps,'rpaths':rpaths,'entitlements':entitlements,'hardenedRuntime':True}
    vm=app/'Contents/Helpers/VMRunner.app'
    if vm.exists():
        executable=vm/'Contents/MacOS/VMRunner'
        vm_paths=[executable,*sorted((vm/'Contents/Frameworks').glob('*.dylib'))]
        for path in vm_paths:
            relative=str(path.relative_to(app))
            arch=command('lipo','-archs',path).stdout.strip()
            assert arch=='arm64',(relative,arch)
            platform=command('xcrun','vtool','-show-build',path).stdout
            assert 'platform MACOS' in platform,(relative,platform)
            minimum=re.findall(r'minos (\d+(?:\.\d+)+)',platform)
            assert minimum and all(tuple(map(int,v.split('.'))) <= (27,0) for v in minimum),(relative,minimum)
            deps=[line.strip().split(' (compatibility')[0] for line in command('otool','-L',path).stdout.splitlines()[1:]]
            assert all(d.startswith(('/usr/lib/','/System/Library/','@rpath/','@loader_path/')) for d in deps),(relative,deps)
            for dep in deps:
                if dep.startswith('@rpath/'):
                    assert (vm/'Contents/Frameworks'/dep.removeprefix('@rpath/')).exists(),dep
                if dep.startswith('@loader_path/'):
                    assert (path.parent/dep.removeprefix('@loader_path/')).resolve().is_relative_to(vm.resolve()),dep
                    assert (path.parent/dep.removeprefix('@loader_path/')).exists(),dep
            load=command('otool','-l',path).stdout
            rpaths=re.findall(r'cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset',load)
            assert all(r.startswith(('@executable_path/','@loader_path/','/usr/lib/')) for r in rpaths),(relative,rpaths)
            signature=command('codesign','-dvv',path).stderr
            assert 'runtime' in signature,(relative,signature)
            ent=command('codesign','-d','--entitlements','-','--xml',path).stdout
            entitlements=plistlib.loads(ent.encode()) if ent.strip() else {}
            expected={}
            if path==executable:
                expected={'com.apple.security.hypervisor':True,'com.apple.security.cs.allow-jit':True,
                          'com.apple.security.cs.allow-unsigned-executable-memory':True,
                          'com.apple.security.cs.disable-library-validation':True}
            assert entitlements==expected,(relative,entitlements)
            results[relative]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'architecture':arch,
                'minimumOS':minimum,'dependencies':deps,'rpaths':rpaths,'entitlements':entitlements,'hardenedRuntime':True}
    forbidden=['StikJIT','HuskJITHelper','embedded.mobileprovision','.dSYM']
    if not vm.exists(): forbidden.append('libqemu')
    for path in app.rglob('*'):
        assert not any(term in path.name for term in forbidden),path
    return {'passed':True,'app':str(app),'binaries':results,'signing':'local ad-hoc unless an explicit identity was supplied'}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('app',type=Path);parser.add_argument('--output',type=Path)
    args=parser.parse_args();result=verify(args.app.resolve())
    encoded=json.dumps(result,indent=2)+'\n'
    if args.output:args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(encoded)
    print('PASS signed macOS arm64 bundle; UI entitlements empty; dependency paths contained')
