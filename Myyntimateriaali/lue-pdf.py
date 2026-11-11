# -*- coding: utf-8 -*-
"""Nauttaa PDF:n tekstin pypdf:lla ja etsii osoitteet."""
import sys
from pypdf import PdfReader

P = sys.argv[1]
r = PdfReader(P)
teksti = "\n".join((lv.extract_text() or "") for lv in r.pages)
print("Pdf:", P)
print("Sivuja:", len(r.pages))
for s in ["dev@huolto.fi", "jani.malmberg@gmail.com", "malmberg", "gmail"]:
    print("  %-25s: %d" % (s, teksti.count(s)))
rivit = [ln.strip() for ln in teksti.splitlines() if "malmberg" in ln]
print("Esimerkkirivit:")
for ln in rivit[:6]:
    print("    " + ln[:110])
