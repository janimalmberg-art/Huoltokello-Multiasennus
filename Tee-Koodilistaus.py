# -*- coding: utf-8 -*-
"""
Tee-Koodilistaus.py — kokoaa Huoltokello-Multiasennus -projektin kaikki
tekstimuotoiset lähdetiedostot yhdeksi PDF-koodilistaukseksi.

Kirjoittaa: C:\\Users\\PC\\Desktop\\Huoltokello-Multiasennus-Koodilistaus.pdf
Käyttö:     python Tee-Koodilistaus.py
"""
import os
import datetime
from fpdf import FPDF
from fpdf.enums import XPos, YPos

ROOT = r"C:\Users\PC\Desktop\Huoltokello-Multiasennus"
OUT  = r"C:\Users\PC\Desktop\Huoltokello-Multiasennus-Koodilistaus.pdf"
VERSION  = "v2.7.3"
SUBTITLE = "Täydellinen koodilistaus ja toimintaohjeet"
DATE = datetime.date.today().strftime("%d.%m.%Y")

SECTIONS = [
    ("ASENNUSVELHO JA ASENNUSOSAT", [
        "Asenna-Huoltokello-Multa.ps1",
        "Asenna.cmd",
        "Osa-Azure.ps1",
        "Osa-Palvelin.ps1",
    ]),
    ("TYÖKALUSKRIPTIT (Tyokalut)", [
        "Tyokalut/_yhteinen.ps1",
        "Tyokalut/Kaynnista.ps1",
        "Tyokalut/Korjaa-Kuvakkeet.ps1",
        "Tyokalut/Lopeta.ps1",
        "Tyokalut/Luo-Kayttaja.ps1",
        "Tyokalut/Luo-Kuvakkeet.ps1",
        "Tyokalut/Luo-YllapitajaTili.ps1",
        "Tyokalut/Paivita.ps1",
        "Tyokalut/Palauta-Varmuuskopio.ps1",
        "Tyokalut/Poista-Asennus.ps1",
        "Tyokalut/Poista-Asennus-GUI.ps1",
        "Tyokalut/PuhelinKaytto.ps1",
        "Tyokalut/Varmuuskopioi.ps1",
        "Tyokalut/asenna-sahkoposti.py",
    ]),
    ("JULKAISU- JA MATERIAALISKRIPTIT", [
        "Julkaise-GitHub.ps1",
        "Myyntimateriaali/korjaa-tekstit.py",
        "Myyntimateriaali/muuta-osoitteet.py",
        "Myyntimateriaali/lue-pdf.py",
        "Myyntimateriaali/tarkista-pdf.py",
    ]),
    ("DOKUMENTAATIO", [
        "README.md",
        "Lueminut.txt",
        "Asennusohjeet.txt",
        "VERSIO.txt",
        "docs/Arkkitehtuuri-ja-rakenne.md",
        "docs/Asennusopas.md",
        "docs/Multiasennusopas.md",
        "docs/Tyokalut.md",
        "docs/Versioloki.md",
        "LICENSE.txt",
        ".gitignore",
        ".gitattributes",
    ]),
    ("HTML-OPPAAT", [
        "Ohjeet/Kayttoonotto-Opas.html",
        "Ohjeet/Multiasennus-Opas.html",
        "Myyntimateriaali/Huoltokello-Esittely-Asiakkaalle.html",
        "Myyntimateriaali/dev-huoltofi-Gmail-Ohje.html",
    ]),
]

# Värit (R, G, B)
ACCENT  = (26, 61, 110)
BANDBG  = (224, 232, 244)
BANDTX  = (20, 42, 82)
TXT     = (23, 29, 38)
NUM     = (150, 156, 166)
ZEBRA   = (246, 248, 251)
GRAY    = (110, 118, 132)
COMMENT = (96, 122, 96)
LINCOL  = (196, 202, 212)

LH = 3.8        # koodirivin korkeus (mm)
MW = 186.0      # kirjoitusalan leveys (A4, marginaalit 12+12 mm)

def read_text(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    for enc in ("utf-8-sig", "utf-16", "cp1252", "latin-1"):
        try:
            return raw.decode(enc), enc
        except (UnicodeDecodeError, UnicodeError):
            pass
    return raw.decode("utf-8", errors="replace"), "utf-8 (korjattu)"

def collect():
    files = []
    idx = 0
    for sec_title, rels in SECTIONS:
        for rel in rels:
            p = os.path.join(ROOT, rel.replace("/", os.sep))
            if not os.path.isfile(p):
                print("HUOM. puuttuu, ohitetaan:", rel)
                continue
            idx += 1
            txt, enc = read_text(p)
            lines = txt.replace("\r\n", "\n").replace("\r", "\n").split("\n")
            lines = [l.replace("\x00", "").replace("\x1a", "").rstrip() for l in lines]
            if lines and lines[-1] == "":
                lines.pop()
            ext = os.path.splitext(rel)[1].lower()
            files.append(dict(idx=idx, rel=rel, name=rel.replace("/", "\\"),
                              sec=sec_title, lines=lines, enc=enc,
                              size=os.path.getsize(p),
                              code=ext in (".ps1", ".py", ".cmd")))
    return files

class Doc(FPDF):
    def __init__(self):
        super().__init__(orientation="P", unit="mm", format="A4")
        self.set_margins(12, 16, 12)
        self.set_auto_page_break(True, margin=16)
        self.alias_nb_pages()
        self.header_file = None
        self.header_sec = ""
        self.numcol = 10.0
        self.total_pages = None
        self.set_title("Huoltokello-Multiasennus — koodilistaus " + VERSION)
        self.set_author("Huoltokello")
        self.set_creator("Tee-Koodilistaus.py (Cline)")
        self.set_lang("fi")

    def header(self):
        if not self.header_file:
            return
        self.set_y(9)
        self.set_font("Arial", "", 7)
        self.set_text_color(*GRAY)
        self.cell(126, 4, self.header_file, align="L")
        self.cell(60, 4, self.header_sec, align="R")
        self.set_draw_color(*LINCOL)
        self.line(12, 14.2, 198, 14.2)
        self.set_y(20)

    def footer(self):
        if self.page_no() == 1:
            return
        self.set_y(-12)
        self.set_font("Arial", "", 7)
        self.set_text_color(*GRAY)
        self.cell(126, 5, "Huoltokello-Multiasennus " + VERSION + " — koodilistaus", align="L")
        tp = getattr(self, "total_pages", None)
        self.cell(60, 5, "Sivu " + str(self.page_no()) + " / " + (str(tp) if tp else "{nb}"), align="R")

def add_fonts(pdf):
    fdir = r"C:\Windows\Fonts"
    def add(family, style, cands):
        for c in cands:
            if os.path.isfile(c):
                pdf.add_font(family, style, fname=c)
                return
        raise RuntimeError("Fonttia ei löydy: " + family + " " + style)
    add("Consolas", "",  [os.path.join(fdir, "consola.ttf"), os.path.join(fdir, "lucon.ttf")])
    add("Consolas", "B", [os.path.join(fdir, "consolab.ttf")])
    add("Arial", "",     [os.path.join(fdir, "arial.ttf"), os.path.join(fdir, "segoeui.ttf")])
    add("Arial", "B",    [os.path.join(fdir, "arialbd.ttf"), os.path.join(fdir, "segoeusbdemo.ttf")])
    add("SegoeSym", "",  [os.path.join(fdir, "seguisym.ttf")])
    try:
        pdf.set_fallback_fonts(["SegoeSym"], exact_match=False)
    except Exception:
        pass

def fmt_n(n):
    return f"{n:,}".replace(",", " ")

def trunc(pdf, s, max_mm):
    if pdf.get_string_width(s) <= max_mm:
        return s
    while s and pdf.get_string_width(s + "...") > max_mm:
        s = s[:-1]
    return s + "..."

def wrap_line(line, max_cols):
    line = line.expandtabs(4)
    segs = []
    first = True
    while len(line) > max_cols:
        keep = max_cols if first else max_cols - 2
        segs.append(line[:keep])
        line = "  " + line[keep:]
        first = False
    segs.append(line)
    return segs

def file_banner(pdf, f):
    y, h = 20, 13.2
    pdf.set_fill_color(*BANDBG)
    pdf.rect(12, y, MW, h, "F")
    pdf.set_fill_color(*ACCENT)
    pdf.rect(12, y, 2.2, h, "F")
    pdf.set_font("Arial", "B", 11)
    pdf.set_text_color(*BANDTX)
    pdf.set_xy(17.5, y + 1.4)
    pdf.cell(MW - 6, 5.2, trunc(pdf, f"{f['idx']:02d}.   {f['name']}", MW - 8), align="L")
    pdf.set_font("Arial", "", 7.2)
    pdf.set_text_color(*GRAY)
    pdf.set_xy(17.5, y + 7.2)
    meta = (f"{len(f['lines'])} riviä  ·  {fmt_n(f['size'])} tavua  ·  merkistö: {f['enc']}  ·  "
            + ("skripti/koodi" if f["code"] else "teksti/ohje"))
    pdf.cell(MW - 6, 3.6, trunc(pdf, meta, MW - 8), align="L")
    pdf.set_xy(12, y + h + 2.5)

def code_row(pdf, num, seg, zebra, comment):
    y = pdf.get_y()
    w2 = MW - pdf.numcol - 1.2
    pdf.set_fill_color(*ZEBRA)
    pdf.set_font("Consolas", "", 8)
    pdf.set_text_color(*NUM)
    pdf.set_xy(12, y)
    pdf.cell(pdf.numcol, LH, num, align="R", fill=zebra)
    pdf.set_text_color(*(COMMENT if comment else TXT))
    pdf.set_xy(12 + pdf.numcol + 1.2, y)
    pdf.cell(w2, LH, seg, align="L", fill=zebra)
    pdf.set_xy(12, y + LH)

def render_file(pdf, f):
    pdf.header_file = f["name"]
    pdf.header_sec = f["sec"]
    pdf.add_page()
    f["page"] = pdf.page_no()
    file_banner(pdf, f)
    pdf.set_font("Consolas", "", 8)
    cw = pdf.get_string_width("0")
    pdf.numcol = cw * 6 + 1.0
    max_cols = int((MW - pdf.numcol - 1.2) / cw) - 1
    for i, line in enumerate(f["lines"], 1):
        comment = f["code"] and line.lstrip().startswith("#")
        for j, seg in enumerate(wrap_line(line, max_cols)):
            if pdf.will_page_break(LH):
                pdf.add_page()
            code_row(pdf, str(i) if j == 0 else "", seg, (i % 2 == 0), comment)
    print(f"  {f['idx']:02d}. {f['name']}: {len(f['lines'])} riviä, sivut {f['page']}–{pdf.page_no()}")

def cover(pdf, files, pages_map):
    pdf.add_page()
    pdf.set_fill_color(*ACCENT)
    pdf.rect(0, 0, 210, 6, "F")
    y = 36
    pdf.set_font("Arial", "B", 38)
    pdf.set_text_color(*ACCENT)
    pdf.set_xy(20, y)
    pdf.cell(172, 14, "HUOLTOKELLO", align="L")
    y += 15.5
    pdf.set_font("Arial", "B", 21)
    pdf.set_text_color(*GRAY)
    pdf.set_xy(20, y)
    pdf.cell(172, 11, "MULTIASENNUS", align="L")
    y += 13
    pdf.set_draw_color(*ACCENT)
    pdf.set_line_width(0.8)
    pdf.line(20.5, y, 93, y)
    y += 7
    pdf.set_font("Arial", "B", 13.5)
    pdf.set_text_color(*TXT)
    pdf.set_xy(20, y)
    pdf.cell(172, 8, SUBTITLE, align="L")
    y += 12
    pdf.set_font("Arial", "B", 11)
    pdf.set_text_color(*ACCENT)
    pdf.set_xy(20, y)
    pdf.cell(172, 6.5, "Ohjelmaversio " + VERSION + "   ·   kooste laadittu " + DATE, align="L")
    y += 11
    pdf.set_font("Arial", "", 9.5)
    pdf.set_text_color(*GRAY)
    pdf.set_xy(20, y)
    pdf.cell(172, 5.5, r"Lähdeprojekti: C:\Users\PC\Desktop\Huoltokello-Multiasennus", align="L")
    y += 11
    n = len(files)
    tl = sum(len(f["lines"]) for f in files)
    tb = sum(f["size"] for f in files)
    tot = (pages_map or {}).get("__TOTAL__", "?")
    pdf.set_fill_color(240, 243, 249)
    pdf.set_draw_color(*LINCOL)
    pdf.set_line_width(0.25)
    pdf.rect(20, y, 172, 33, "DF")
    pdf.set_font("Arial", "B", 10)
    pdf.set_text_color(*TXT)
    pdf.set_xy(28, y + 5)
    pdf.cell(156, 5.5, f"Tekstitiedostoja luetteloidaan:  {n}   kpl", align="L")
    pdf.set_xy(28, y + 12)
    pdf.cell(156, 5.5, f"Lähdetiedostojen rivejä yhteensä:  {fmt_n(tl)}", align="L")
    pdf.set_xy(28, y + 19)
    pdf.cell(156, 5.5, f"Lähdetiedostojen kokonaiskoko:  {fmt_n(tb // 1024)} kt    ·    PDF-sivuja:  {tot}", align="L")
    y += 43
    pdf.set_font("Arial", "B", 10)
    pdf.set_text_color(*TXT)
    pdf.set_xy(20, y)
    pdf.cell(172, 6, "Sisältöjaksot luettelossa", align="L")
    y += 6.5
    pdf.set_font("Arial", "", 9)
    pdf.set_text_color(*GRAY)
    for sec_title, rels in SECTIONS:
        cnt = sum(1 for f in files if f["sec"] == sec_title)
        pdf.set_xy(20, y)
        pdf.cell(172, 5.2, "  •  " + sec_title + f"  ({cnt} tiedostoa)", align="L")
        y += 5.2
    y += 4
    pdf.set_font("Arial", "", 7.8)
    pdf.set_text_color(*GRAY)
    pdf.set_xy(20, 252)
    note = ("Tämä PDF sisältää kaikki projektin tekstimuotoiset lähdetiedostot: PowerShell- ja Python-skriptit, "
            "asennuksen käynnistyskomennon, dokumentaation (md/txt) sekä HTML-oppaat. Binääriset tiedostot "
            "(.zip-paketit, kuvakkeet, kuvat, .pyc-välimuisti) eivät kuulu koodilistaukseen. Koodi on tulostettu "
            "sellaisenaan rivinumeroilla; kun rivi ylittää leveysrajan, jatko tulee sisennetylle jatkosiirrolle.")
    pdf.multi_cell(172, 4.2, note)

def toc(pdf, files, pages_map):
    pdf.header_file = None
    pdf.header_sec = ""
    pdf.add_page()
    pdf.set_font("Arial", "B", 16)
    pdf.set_text_color(*TXT)
    pdf.set_xy(12, 20)
    pdf.cell(186, 9, "SISÄLLYS", align="L")
    pdf.set_draw_color(*ACCENT)
    pdf.set_line_width(0.7)
    pdf.line(12, 30, 53, 30)
    y = 34
    for sec_title, _rels in SECTIONS:
        group = [f for f in files if f["sec"] == sec_title]
        if not group:
            continue
        if pdf.will_page_break(14):
            pdf.add_page()
        pdf.set_fill_color(226, 233, 244)
        pdf.set_font("Arial", "B", 9)
        pdf.set_text_color(*BANDTX)
        pdf.set_xy(12, y)
        pdf.cell(148, 5.4, sec_title, align="L", fill=True)
        pdf.set_xy(160, y)
        pdf.cell(38, 5.4, f"{len(group)} tiedostoa", align="R", fill=True)
        y += 6.6
        for f in group:
            pg = str(pages_map.get(f["rel"], "?")) if pages_map else "?"
            pdf.set_font("Arial", "", 8.6)
            pdf.set_text_color(*TXT)
            pdf.set_xy(12, y)
            pdf.cell(158, 4.3, f"{f['idx']:02d}   {f['name']}", align="L")
            pdf.set_font("Arial", "B", 8.6)
            pdf.set_text_color(*ACCENT)
            pdf.set_xy(170, y)
            pdf.cell(28, 4.3, ("sivu " + str(pg)) if pg != "?" else "?", align="R")
            y += 4.3
        y += 1.6

def build(files, pages_map):
    pdf = Doc()
    pdf.total_pages = (pages_map or {}).get("__TOTAL__")
    add_fonts(pdf)
    cover(pdf, files, pages_map)
    toc(pdf, files, pages_map)
    for f in files:
        render_file(pdf, f)
    pages = {f["rel"]: f["page"] for f in files}
    pages["__TOTAL__"] = pdf.page_no()
    return pdf, pages

def main():
    print("Kootaan luettelotiedostoja...")
    files = collect()
    if not files:
        raise SystemExit("Virhe: yhtään lähdetiedostoa ei löytynyt")
    print("Läpikäynti 1/2 (sivunumeroiden laskenta)...")
    _, m1 = build(files, None)
    print("Läpikäynti 2/2 (lopullinen PDF)...")
    pdf, m2 = build(files, m1)
    pdf.output(OUT)
    print()
    print(f"VALMIS: {OUT}")
    print(f"Tiedostoja: {len(files)}  |  rivejä: {fmt_n(sum(len(f['lines']) for f in files))}  |  PDF-sivuja: {m2['__TOTAL__']}")

if __name__ == "__main__":
    main()