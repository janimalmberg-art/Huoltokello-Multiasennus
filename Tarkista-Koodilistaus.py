# -*- coding: utf-8 -*-
"""Varmistaa, että koodilistaus-PDF on olemassa ja sisältää odotetun sisällön."""
import os
import pypdf

P = r"C:\Users\PC\Desktop\Huoltokello-Multiasennus-Koodilistaus.pdf"

if not os.path.isfile(P):
    raise SystemExit("VIRHE: PDF ei löydy: " + P)

r = pypdf.PdfReader(P)
print("OK: PDF löytyy")
print("SIVUJA:", len(r.pages))
print("KOKO kt:", os.path.getsize(P) // 1024)
print("NIMI:", (r.metadata or {}).get("/Title", "?"))

c = r.pages[0].extract_text().replace("\n", " | ")
print("KANSI:", c[:180])
t = r.pages[1].extract_text().replace("\n", " | ")
print("SISALLYSEN ALKU:", t[:150])
m = r.pages[5].extract_text().splitlines()
print("SIVU 6 EKA RIVIT:", " || ".join(m[:4])[:160])
last = r.pages[len(r.pages) - 1].extract_text()
print("VIIMEINEN SIVU ALKAA:", last[:80].replace("\n", " | "))
print("ALATUNNISTE OK:", "Sivu" in r.pages[5].extract_text())
