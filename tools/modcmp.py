# Compare two firmwares' stock kernel modules section by section, ignoring .modinfo and the build id.
# Usage: python3 -I modcmp.py dirA dirB
import os, struct, sys
IGN = {'.modinfo', '.note.gnu.build-id'}
WIFI = ('cnss2.ko', 'mhi.ko', 'cnss_utils.ko', 'cfg80211.ko', 'mac80211.ko', 'ipa_fmwk.ko', 'cnss_prealloc.ko',
        'cnss_nl.ko', 'qca_cld3_kiwi_v2.ko', 'wlan_firmware_service.ko', 'cnss_plat_ipc_qmi_svc.ko')

def sections(data):
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3A)
    hdrs = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    stro = hdrs[shstrndx][4]
    return {data[stro + h[0]:data.index(b'\0', stro + h[0])].decode(): data[h[4]:h[4] + h[5]] for h in hdrs}

def index(root):
    r = {}
    for d, _, fs in os.walk(root):
        for f in fs:
            if f.endswith('.ko'): r.setdefault(f, os.path.join(d, f))
    return r

a, b = index(sys.argv[1]), index(sys.argv[2])
same, diff = 0, []
for f in sorted(set(a) & set(b)):
    x, y = sections(open(a[f], 'rb').read()), sections(open(b[f], 'rb').read())
    d = sorted(k for k in set(x) | set(y) if k not in IGN and not k.startswith('.bss') and x.get(k) != y.get(k))
    if d: diff.append((f, d[:5]))
    else: same += 1
print(f'modules: {same} same code, {len(diff)} differ, {len(set(a) - set(b))} only in A, {len(set(b) - set(a))} only in B')
for f, d in diff: print(('  WIFI ' if f in WIFI else '  ') + f, d)
missing = [w for w in WIFI if w in a and w not in b]
print('Wi-Fi stack:', 'IDENTICAL' if not any(f in WIFI for f, _ in diff) and not missing else 'DIFFERS', missing or '')
