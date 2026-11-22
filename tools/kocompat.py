# Will our out-of-tree .ko files load on another firmware? Compares every symbol CRC each .ko imports
# (its __versions) with the CRCs the target firmware's own stock modules import, plus the exports of
# the target's stock modules that ours depend on (cnss2, mhi, cfg80211...).
# Usage: python3 -I kocompat.py <target modules dir> <our.ko>...
import os, struct, sys

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

def versions(s):
    v, r = s.get('__versions', b''), {}
    for i in range(0, len(v), 64):
        crc, = struct.unpack_from('<Q', v, i)
        r[v[i + 8:i + 64].split(b'\0')[0].decode()] = crc & 0xffffffff
    return r

def crc_exports(data):
    # __crc_<sym> absolute symbols in .symtab: the CRCs of what this module exports
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum, _ = struct.unpack_from('<HHH', data, 0x3A)
    hdrs = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    out = {}
    for h in hdrs:
        if h[1] != 2: continue                      # SHT_SYMTAB
        strh = hdrs[h[6]]; st = data[strh[4]:strh[4] + strh[5]]; sym = data[h[4]:h[4] + h[5]]
        for i in range(0, len(sym), 24):
            nm, info, oth, shndx, val, sz = struct.unpack_from('<IBBHQQ', sym, i)
            n = st[nm:st.index(b'\0', nm)].decode()
            if n.startswith('__crc_') and shndx == 0xfff1: out[n[6:]] = val & 0xffffffff
    return out

def modinfo(s):
    return dict(kv.split(b'=', 1) for kv in s.get('.modinfo', b'').split(b'\0') if b'=' in kv)

target, conflicts, where = {}, 0, {}
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        if not f.endswith('.ko'): continue
        p = os.path.join(root, f)
        try: d = open(p, 'rb').read(); s = sections(d)
        except Exception: continue
        for n, c in list(versions(s).items()) + list(crc_exports(d).items()):
            if n in target and target[n] != c: conflicts += 1
            target.setdefault(n, c); where.setdefault(n, f)
print(f'target: {len(target)} symbol CRCs harvested ({conflicts} conflicts)')
bad = 0
for ko in sys.argv[2:]:
    s = sections(open(ko, 'rb').read()); mi = modinfo(s)
    mism = [(n, c, target[n]) for n, c in versions(s).items() if n in target and target[n] != c]
    miss = [n for n in versions(s) if n not in target]
    bad += len(mism)
    print(f'{os.path.basename(ko)}: {len(versions(s))} imports, {len(mism)} CRC mismatches, '
          f'{len(miss)} not seen in target; depends={mi.get(b"depends", b"").decode()}; '
          f'vermagic={mi.get(b"vermagic", b"").decode()}')
    for n, a, b in mism[:40]: print(f'   MISMATCH {n}: ours 0x{a:08x} target 0x{b:08x} (seen in {where[n]})')
    for n in miss[:40]: print(f'   unseen {n}')
sys.exit(1 if bad else 0)
