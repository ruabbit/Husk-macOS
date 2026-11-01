# SPDX-License-Identifier: GPL-2.0-or-later
from pathlib import Path
import subprocess, sys, tempfile
with tempfile.TemporaryDirectory(prefix='AOSP-', dir=sys.argv[2]) as temp:
    root=Path(temp)
    def check(count, capacity=20):
        subprocess.run([sys.argv[1],str(root),str(count),str(capacity)],check=True)
    check(-1)
    names=['com.android.art/javalib/'+x+'.jar' for x in ['core-oj','core-libart','okhttp','bouncycastle','apache-xml']]
    names+=['com.android.i18n/javalib/core-icu4j.jar','com.android.conscrypt/javalib/conscrypt.jar','husk-framework.dex','org.apache.http.legacy.jar']
    for name in names:
        p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.touch()
    check(9)
    (root/'aosp').mkdir();(root/'aosp/framework.jar').touch()
    check(-1)  # core is required; do not shadow real framework classes with generated stubs
    (root/'husk-framework-core.dex').touch();check(10);check(-1,9)
    (root/'framework.jar').touch();check(10)  # one copy, preferred aosp namespace
    required=root/names[0];required.unlink();required.symlink_to(root/names[1]);check(-1)
