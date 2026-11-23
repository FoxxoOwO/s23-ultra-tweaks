#!/usr/bin/env python3
"""Make device/files/SamsungCamera-24fps-<build>.patch for a firmware's SamsungCamera.apk (cam24fps).
Finds Lte/f0;-><clinit>() in the APK's stored dex files and swaps two unused Fold/Flip-only slots in the
te.f0.i standard-Video allowlist:
  - RESOLUTION_4000X1868 -> RESOLUTION_3840X2160_24FPS (4K 24 fps)
  - RESOLUTION_2224X1080 -> RESOLUTION_1920X1080_24FPS (1080p 24 fps)
(8K 24 fps / RESOLUTION_7680X4320_24FPS is already in te.f0.i.)
Leaves te.c0.c() stock so QHD stays excluded from non-Super-Steady Video, and fixes dex SHA-1, adler32 and zip CRCs.
Usage: cam24patch.py SamsungCamera.apk <build> [out.patch]     (prints the stock and patched MD5)"""
import hashlib, struct, sys, zlib

def uleb(d, p):
    r = s = 0
    while True:
        b = d[p]; p += 1; r |= (b & 0x7f) << s; s += 7
        if b < 0x80: return r, p

def find_clinit_patches(d):
    """Return list of (byte_offset_in_dex, old_reg, new_reg, label) for UHD24 and FHD24 swaps in Lte/f0;-><clinit>()."""
    u32 = lambda o: struct.unpack_from('<I', d, o)[0]
    u16 = lambda o: struct.unpack_from('<H', d, o)[0]
    strs, typs, flds, mths, clss = u32(60), u32(68), u32(84), u32(92), u32(100)
    nfld, nmth, ncls = u32(80), u32(88), u32(96)
    def string(i):
        _, p = uleb(d, u32(strs + 4 * i)); return d[p:d.index(b'\0', p)].decode('utf-8', 'replace')
    def typ(i):
        return string(u32(typs + 4 * i))

    wanted = {
        'RESOLUTION_3840X2160_24FPS': None,
        'RESOLUTION_1920X1080_24FPS': None,
        'RESOLUTION_4000X1868': None,
        'RESOLUTION_2224X1080': None,
    }
    a2_e_meth = None
    for fi in range(nfld):
        ci, _, ni = struct.unpack_from('<HHI', d, flds + 8 * fi)
        if typ(ci) == 'Ll9/a2;':
            n = string(ni)
            if n in wanted: wanted[n] = fi
    for mi in range(nmth):
        ci, _, ni = struct.unpack_from('<HHI', d, mths + 8 * mi)
        if typ(ci) == 'Ll9/a2;' and string(ni) == 'e':
            a2_e_meth = mi; break
    if any(v is None for v in wanted.values()) or a2_e_meth is None:
        return None

    for c in range(ncls):
        o = clss + 32 * c
        if typ(u32(o)) != 'Lte/f0;': continue
        p = u32(o + 24); assert p, 'Lte/f0; has no class data'
        ns, p = uleb(d, p); ni, p = uleb(d, p); nd, p = uleb(d, p); nv, p = uleb(d, p)
        for _ in range(2 * (ns + ni)): _, p = uleb(d, p)
        m = 0
        for _ in range(nd):
            diff, p = uleb(d, p); _, p = uleb(d, p); code, p = uleb(d, p); m += diff
            if string(u32(mths + 8 * m + 4)) != '<clinit>' or not code: continue
            units = u32(code + 12); base = code + 16
            reg_info = {}  # name -> (reg, saved_unit)
            for u in range(units - 2):
                if d[base + 2 * u] == 0x62:
                    ref = u16(base + 2 * u + 2); src_reg = d[base + 2 * u + 1]
                    for name, fid in wanted.items():
                        if ref == fid and name not in reg_info:
                            for k in range(u + 2, min(u + 30, units - 1)):
                                if d[base + 2 * k] == 0x08 and u16(base + 2 * k + 2) == src_reg:
                                    reg_info[name] = (d[base + 2 * k + 1], k); break
            assert len(reg_info) == 4, 'could not resolve all 4 registers: %r' % (reg_info,)
            # Anchor the map8 (te.f0.i) put() block right after RESOLUTION_4000X1868 is saved
            block_start = reg_info['RESOLUTION_4000X1868'][1] + 1
            block_end = min(block_start + 220, units - 2)
            pairs = [
                ('RESOLUTION_4000X1868', 'RESOLUTION_3840X2160_24FPS', 'UHD24'),
                ('RESOLUTION_2224X1080', 'RESOLUTION_1920X1080_24FPS', 'FHD24'),
            ]
            patches = []
            for old_name, new_name, label in pairs:
                old_reg, _ = reg_info[old_name]
                new_reg, saved_u = reg_info[new_name]
                hits = []
                for u in range(block_start, block_end):
                    if d[base + 2 * u] == 0x74 and d[base + 2 * u + 1] == 0x01 and u16(base + 2 * u + 2) == a2_e_meth:
                        if u16(base + 2 * u + 4) == old_reg:
                            hits.append(base + 2 * u + 4)
                assert len(hits) == 1, 'expected 1 te.f0.i put() for %s, found %d' % (old_name, len(hits))
                hit_u = (hits[0] - base) // 2
                for u in range(saved_u + 1, hit_u):
                    if d[base + 2 * u] in (0x08, 0x09, 0x0c, 0x0a, 0x62, 0x13, 0x14, 0x1a, 0x22) and d[base + 2 * u + 1] == new_reg:
                        raise AssertionError('%s register v%d overwritten at unit %d' % (label, new_reg, u))
                assert old_reg < 256 and new_reg < 256
                patches.append((hits[0], old_reg, new_reg, label))
            return patches
    return None

if len(sys.argv) < 3:
    raise SystemExit('Usage: cam24patch.py SamsungCamera.apk <build> [out.patch]')

apk = bytearray(open(sys.argv[1], 'rb').read()); build = sys.argv[2]
stock = hashlib.md5(apk).hexdigest(); orig = bytes(apk)
eocd = apk.rindex(b'PK\x05\x06'); ncd, _, cd = struct.unpack_from('<HII', apk, eocd + 10)
done = False
for _ in range(ncd):
    assert apk[cd:cd + 4] == b'PK\x01\x02'
    method, = struct.unpack_from('<H', apk, cd + 10)
    size, = struct.unpack_from('<I', apk, cd + 24)
    nl, el, cl = struct.unpack_from('<HHH', apk, cd + 28); lh, = struct.unpack_from('<I', apk, cd + 42)
    name = apk[cd + 46:cd + 46 + nl].decode()
    if name.endswith('.dex') and '/' not in name:
        assert method == 0, name + ' is compressed; this patch format needs stored dex files'
        lnl, lel = struct.unpack_from('<HH', apk, lh + 26); start = lh + 30 + lnl + lel
        dex = apk[start:start + size]; patches = find_clinit_patches(dex)
        if patches is not None:
            for at, old_reg, new_reg, label in patches:
                assert dex[at] == old_reg and dex[at + 1] == 0x00, 'unexpected register bytes at 0x%x' % at
                dex[at] = new_reg
                print('%s: te.f0.<clinit> te.f0.i %s v%d -> v%d at file offset %d' % (name, label, old_reg, new_reg, start + at))
            dex[12:32] = hashlib.sha1(dex[32:]).digest()
            dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])))
            apk[start:start + size] = dex
            crc = struct.pack('<I', zlib.crc32(bytes(dex)))
            apk[lh + 14:lh + 18] = crc; apk[cd + 16:cd + 20] = crc
            done = True
    cd += 46 + nl + el + cl
assert done, 'Lte/f0;-><clinit> allowlist slots not found in any dex'
new = hashlib.md5(apk).hexdigest()
out = ['# 24 FPS in standard Video (FHD/UHD/8K): SamsungCamera.apk (%s, md5 %s) -> md5 %s' % (build, stock, new),
       '# Adds ONLY UHD24 and FHD24 to te.f0.i in Lte/f0;-><clinit>() by replacing unused Fold/Flip slots',
       '# (4000x1868 -> UHD24, 2224x1080 -> FHD24; 8K24 is already in te.f0.i). Leaves te.c0.c() stock so QHD stays hidden.',
       '# Made by tools/cam24patch.py. Format: <zero-based file offset> <new byte in octal>']
out += ['%d %o' % (i, b) for i, (a, b) in enumerate(zip(orig, apk)) if a != b]
out_path = sys.argv[3] if len(sys.argv) > 3 else 'SamsungCamera-24fps-%s.patch' % build
open(out_path, 'w', newline='\n').write('\n'.join(out) + '\n')
print('stock md5  ', stock); print('patched md5', new); print(len(out) - 4, 'bytes changed')
