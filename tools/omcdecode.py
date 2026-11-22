#!/usr/bin/env python3
"""Decode Samsung OMC-encoded cscfeature.xml / customer_carrier_feature.json (logic from SemCscFeature._decode).
Usage: omcdecode.py salts.txt shifts.txt in out"""
import gzip, re, sys
def arr(p): return [int(x) & 0xff for x in re.findall(r'-?\d+', open(p).read().split('{', 1)[1])]
salts, shifts = arr(sys.argv[1]), arr(sys.argv[2])
assert len(salts) == 256 and len(shifts) == 256, (len(salts), len(shifts))
data = open(sys.argv[3], 'rb').read()
out = bytearray()
for i, b in enumerate(data):
    s = shifts[i % 256] & 7
    r = ((b >> (8 - s)) | (b << s)) & 0xff if s else b
    out.append(r ^ salts[i % 256])
open(sys.argv[4], 'wb').write(gzip.decompress(bytes(out)))
