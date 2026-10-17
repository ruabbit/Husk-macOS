#!/usr/bin/env python3
"""Real provider tests in separate, headless processes with disposable app data."""
from pathlib import Path
import hashlib
import os
import subprocess
import sys
import tempfile

runner, runtime, apk, angle, output = sys.argv[1:]
Path(output).mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='keystore-', dir=output) as temporary:
    root = Path(temporary)
    def run(data, phase):
        data.mkdir(exist_ok=True, mode=0o700)
        result = subprocess.run([runner, runtime, apk, angle, str(data), phase],
                                capture_output=True, text=True, timeout=25,
                                env=dict(os.environ, TL_AUDIO_MUTE='1', TL_XMEM_MIB='1024'))
        if result.returncode:
            print(result.stdout); print(result.stderr); raise SystemExit(result.returncode)
        assert f'PASS KeyStore {phase}' in result.stdout
        print(f'PASS KeyStore {phase}', flush=True)
    app = root/'app'; store = app/'.husk_keystore'
    run(app, 'import')
    assert store.stat().st_mode & 0o777 == 0o600
    run(app, 'reopen')
    before = hashlib.sha256(store.read_bytes()).digest()
    run(app, 'write-failed')
    assert hashlib.sha256(store.read_bytes()).digest() == before
    assert not list(app.glob('.husk_keystore-*.tmp'))
    run(app, 'reopen')
    run(root/'other-app', 'empty')
    run(app, 'delete'); run(app, 'empty')
    store.write_bytes(b'invalid-key-store-fixture')
    run(app, 'corrupt')
    assert store.read_bytes() == b'invalid-key-store-fixture'
print('PASS imported AES/GCM, policy, persistence failure, isolation, deletion, restart and corrupt-store preservation')
