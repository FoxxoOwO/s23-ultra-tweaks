# Build a Module.symvers from the __versions sections of stock .ko files (aarch64 ELF64).
# Usage: python3 -I symvers.py OUT module.ko...   Also prints import_ns tags seen.
import struct, sys

def sections(data):
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3A)
    hdrs = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    stro = hdrs[shstrndx][4]
    out = {}
    for h in hdrs:
        name = data[stro + h[0]:data.index(b'\0', stro + h[0])].decode()
        out[name] = data[h[4]:h[4] + h[5]]
    return out

crcs, ns = {}, set()
for path in sys.argv[2:]:
    d = open(path, 'rb').read()
    s = sections(d)
    v = s.get('__versions', b'')
    for i in range(0, len(v), 64):
        crc, = struct.unpack_from('<Q', v, i)
        name = v[i + 8:i + 64].split(b'\0')[0].decode()
        if name in crcs and crcs[name] != crc:
            print('CRC conflict', name, hex(crcs[name]), hex(crc), path, file=sys.stderr)
        crcs[name] = crc
    for kv in s.get('.modinfo', b'').split(b'\0'):
        if kv.startswith(b'import_ns='):
            ns.add(kv[10:].decode())
with open(sys.argv[1], 'w') as f:
    for n in sorted(crcs):
        f.write(f'0x{crcs[n] & 0xffffffff:08x}\t{n}\tvmlinux\tEXPORT_SYMBOL\t\n')
print(len(crcs), 'symbols; import_ns seen:', sorted(ns))
