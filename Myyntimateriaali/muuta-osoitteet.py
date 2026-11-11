# -*- coding: utf-8 -*-
"""Vaihtaa materiaalin dev@huolto.fi-osoitteen Gmail-osoitteeseen (idempotenti)."""
import io

KOHEDE = [
    r"C:\Users\PC\Desktop\Huoltokello-Multiasennus\Myyntimateriaali\Huoltokello-Esittely-Asiakkaalle.html",
    r"C:\Users\PC\Desktop\Huoltokello-Multiasennus\docs\Asennusopas.md",
    r"C:\Users\PC\Desktop\Huoltokello-Multiasennus\Asennusohjeet.txt",
    r"C:\Users\PC\Desktop\Huoltokello-Multiasennus\LICENSE.txt",
    r"C:\Users\PC\Desktop\Huoltokello-Multiasennus\README.md",
]
VANHA = "dev@huolto.fi"
UUSI = "jani.malmberg@gmail.com"

for kohde in KOHEDE:
    with io.open(kohde, "r", encoding="utf-8") as f:
        t = f.read()
    n = t.count(VANHA)
    if n:
        t = t.replace(VANHA, UUSI)
        with io.open(kohde, "w", encoding="utf-8", newline="") as f:
            f.write(t)
    print("%s : vaihdettiin %d" % (kohde.rsplit("\\", 1)[1], n))
