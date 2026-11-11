# -*- coding: utf-8 -*-
"""Tarkistaa PDF:n tekstin purkamalla Flate-virrat (zlib) + raakatarkan."""
import re
import sys
import zlib

P = sys.argv[1]
with open(P, "rb") as f:
    data = f.read()

puretut = []
for m in re.finditer(rb"stream\r?\n(.*?)endstream", data, re.S):
    try:
        puretut.append(zlib.decompress(m.group(1)))
    except Exception:
        pass

kaikki = b"".join(puretut) + data

print("Tiedosto:", P)
print("Koko:", len(data))
for s in ["dev@huolto", "huolto.fi", "jani", "malmberg", "gmail.com", "@gmail"]:
    n = kaikki.count(s.encode("utf-8"))
    print("  %-22s: %d" % (s, n))

counts = sorted(set(int(c) for c in re.findall(rb"/Count (\d+)", kaikki)))
print("/Count-arvot:", counts)
print("/Type /Page :", len(re.findall(rb"/Type\s*/Page[^s]", kaikki)))
