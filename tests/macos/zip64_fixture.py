"""Force ZIP64 central fields and end records on small ordinary test ZIPs."""
import struct

def force_zip64(data):
    end = data.rfind(b'PK\x05\x06')
    count = struct.unpack_from('<H', data, end + 10)[0]
    offset = struct.unpack_from('<I', data, end + 16)[0]
    directory = bytearray()
    at = offset
    for _ in range(count):
        header = bytearray(data[at:at+46])
        assert header[:4] == b'PK\x01\x02'
        ns, es, cs = struct.unpack_from('<HHH', header, 28)
        compressed, size = struct.unpack_from('<II', header, 20)
        local = struct.unpack_from('<I', header, 42)[0]
        extra = struct.pack('<HHQQQ', 1, 24, size, compressed, local)
        struct.pack_into('<H', header, 6, 45)
        struct.pack_into('<II', header, 20, 0xffffffff, 0xffffffff)
        struct.pack_into('<H', header, 30, es+len(extra))
        struct.pack_into('<I', header, 42, 0xffffffff)
        directory += header + data[at+46:at+46+ns+es] + extra + data[at+46+ns+es:at+46+ns+es+cs]
        at += 46+ns+es+cs
    record_offset = offset + len(directory)
    record = struct.pack('<IQHHIIQQQQ', 0x06064b50, 44, 45, 45, 0, 0, count, count, len(directory), offset)
    locator = struct.pack('<IIQI', 0x07064b50, 0, record_offset, 1)
    eocd = struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, 0xffff, 0xffff, 0xffffffff, 0xffffffff, 0)
    return data[:offset] + directory + record + locator + eocd
