#!/usr/bin/env python3
"""Production archive extraction: bounded chunks, Zip64, corruption and ownership."""
import io
import random
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile
from zip64_fixture import force_zip64

tool, parent = sys.argv[1:]
Path(parent).mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='Archive-', dir=parent) as tmp:
    root = Path(tmp)
    payload = bytes(range(256)) * (32 << 10)  # 8 MiB, crosses many input/output chunks
    def archive(method, data=payload):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w', compression=method) as z:
            z.writestr('resource.obb', data)
        return stream.getvalue()
    def run(data, success=True):
        source = root/'case.zip'; destination = root/'result.obb'
        source.write_bytes(data)
        result = subprocess.run([tool, source, 'resource.obb', destination], capture_output=True)
        assert (result.returncode == 0) == success, result.stderr.decode()
        if not success:
            assert not destination.exists(), 'failed extraction left a partial destination'
        return destination
    for method in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
        for data in (payload, b''):
            original = archive(method, data)
            for encoded in (original, force_zip64(original)):
                output = run(encoded)
                assert output.read_bytes() == data
                assert output.stat().st_mode & 0o777 == 0o600
                output.unlink()
        original = archive(method)
        central = original.index(b'PK\x01\x02')
        for label, offset, value in [('crc', central+16, 0), ('short-output', central+24, 4),
                                     ('excess-input', central+20, struct.unpack_from('<I', original, central+20)[0]+1),
                                     ('oversize', central+24, (512 << 20)+1)]:
            damaged = bytearray(original); struct.pack_into('<I', damaged, offset, value)
            run(damaged, False)
        broken = bytearray(force_zip64(original)); record = broken.index(b'PK\x06\x06')
        struct.pack_into('<Q', broken, record+48, 0xffffffffffffffff)
        run(broken, False)
        broken = bytearray(force_zip64(original)); extra = central+46+len('resource.obb')
        struct.pack_into('<H', broken, extra+2, 1)
        run(broken, False)
    noisy = random.Random(42).randbytes(2 << 20)
    output = run(force_zip64(archive(zipfile.ZIP_DEFLATED, noisy)))
    assert output.read_bytes() == noisy
    output.unlink()
    class NonSeekable(io.BytesIO):
        def seek(self, *args):
            raise io.UnsupportedOperation('streaming archive')
    stream = NonSeekable()
    with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        with z.open('resource.obb', 'w', force_zip64=True) as entry:
            entry.write(noisy)
    output = run(force_zip64(stream.getvalue()))
    assert output.read_bytes() == noisy
    output.unlink()
    (root/'case.zip').write_bytes(archive(zipfile.ZIP_DEFLATED))
    output = root/'protected'; output.write_bytes(b'existing')
    link = root/'symlink'; link.symlink_to(output)
    for destination in (output, link):
        result = subprocess.run([tool, root/'case.zip', 'resource.obb', destination], capture_output=True)
        assert result.returncode != 0 and output.read_bytes() == b'existing'
    print('PASS stored/deflated/empty Zip64, CRC/size/metadata rejection, partial cleanup, existing file and symlink preservation')
