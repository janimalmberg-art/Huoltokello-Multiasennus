# -*- coding: utf-8 -*-
"""
asenna-sahkoposti.py — dev@huolto.fi <-> Gmail -automaatiotyökalu  (Huoltokello-työkalu)
Tekee cPanel/UAPI-toiminnot: laatikko, uudelleenohjaus -> Gmail, DKIM, DMARC,
alidomain dev.huolto.fi (+MX), SMTP-testiviesti, Gmail-asetussivun avaus.

Käyttö:    python asenna-sahkoposti.py            (valikko)
           python asenna-sahkoposti.py --tarkistus (vain DNS/porttitarkistus, ei tunnuksia)

HUOM: Gmailin "Lähetä postia nimellä" -asetus on Google-tilin asetus; työkalu avaa
      kyseisen sivun ja antaa arvot, mutta viimeinen klikkaus tehdään selaimessa.
"""
import base64, getpass, json, os, secrets, smtplib, socket, ssl, subprocess, sys
from urllib import parse, request as rq

HOST = "huolto.fi"
GMAIL = "jani.malmberg@gmail.com"
DMARC = f"_dmarc.{HOST}"
DESK = os.path.join(os.environ.get("USERPROFILE", r"C:\Users\PC"), "Desktop")
CP = {"user": None, "pw": None, "base": f"https://{HOST}:2083", "ctx": None}

def banner():
    print("=" * 62)
    print(" dev@huolto.fi -> Gmail  -asennustyökalu (cPanel/UAPI)")
    print(" Gmail-kohde:", GMAIL)
    print("=" * 62)

def _sslctx():
    if CP["ctx"] is None:
        try:
            r = rq.urlopen(rq.Request(f"https://{HOST}:2083"), timeout=8)
            CP["ctx"] = ssl.create_default_context()
        except Exception:
            CP["ctx"] = ssl._create_unverified_context()
            print("  (TLS-varmennusta ei vahvistettu — palvelimen itseallekirjoitettu sertifikaatti?)")
        # sulje mahdollinen socket urllibin ulkopuolelta ei tarvita; ctx vain luotiin
    return CP["ctx"]

def uapi(module, func, params=None, api="execute"):
    """Kutsuu cPanel UAPIa tai API2:sta. Palauttaa parsed JSON -lasketun sanakirjan."""
    params = params or {}
    if not CP["user"] or not CP["pw"]:
        print("Tarvitaan cPanel-tunnukset (myös API-token käy).")
        CP["user"] = input("  cPanel-käyttäjä: ").strip()
        CP["pw"] = getpass.getpass("  Salasana/token: ")
    if api == "execute":
        url = f"{CP['base']}/execute/{module}/{func}?{parse.urlencode(params)}"
    else:  # API2
        q = {"cpanel_jsonapi_apiversion": "2", "cpanel_jsonapi_module": module,
             "cpanel_jsonapi_func": func}
        q.update(params)
        url = f"{CP['base']}/json-api/cpanel?{parse.urlencode(q)}"
    auth = base64.b64encode(f"{CP['user']}:{CP['pw']}".encode()).decode()
    for url_try in [url, url.replace(":2083", ":2087")]:  # 2087 = root/proxy fallback
        req = rq.Request(url_try, headers={"Authorization": "Basic " + auth,
                                           "User-Agent": "hk-sahkoposti-tool/1.0"})
        try:
            with rq.urlopen(req, timeout=25, context=_sslctx()) as r:
                out = json.loads(r.read().decode("utf-8", "replace"))
            return out
        except Exception as e:
            err = str(e)
            if "403" in err or "401" in err:
                print("  Hylätty (401/403): tarkista käyttäjä/salasana. Myös API-token käy salasanana.")
                return {"status": 0, "errors": [err]}
    print("  Yhteysongelma:", err)
    return {"status": 0, "errors": [err]}

def ok(res, label):
    if res.get("status") in (1, True):
        print(f"  ✓ {label} OK")
        return True
    print("  ✗", label, "->", res.get("errors") or res)
    return False
# ---------------- toimintatilat ----------------

def dns_ja_portit():
    print("\n[1] DNS- ja porttitarkistus")
    for tyyppi, kys in (("MX", "-type=MX"), ("TXT", "-type=TXT"), ("NS", "-type=NS")):
        r = subprocess.run(["nslookup", kys, HOST, "8.8.8.8"], capture_output=True, text=True, timeout=20)
        rivit = [l.strip() for l in r.stdout.splitlines() if l.strip()]
        print(f"  {tyyppi}: " + " | ".join(rivit[2:6]))
    for p, nimi in ((25,"SMTP 25"),(465,"SMTPS 465"),(587,"SMTP 587"),(993,"IMAPS 993"),(143,"IMAP 143"),(2083,"cPanel 2083")):
        s = socket.socket(); s.settimeout(3)
        auki = s.connect_ex((HOST, p)) == 0
        s.close()
        print(f"  {nimi:<12} {'AUKI' if auki else 'suljettu'}")

def luo_laatikko():
    print("\n[2] Luo sähköpostilaatikko")
    local = input(f"  Laatikon nimi [{HOST} -osaa edellä] (oletus dev): ").strip() or "dev"
    print("  a) luo vahva salasana  b) itse  a/b [a]")
    if input().strip().lower() == "b":
        pw = getpass.getpass("  Salasana: ")
    else:
        pw = secrets.token_urlsafe(12)
    res = uapi("Email", "add_pop", {"domain": HOST, "username": local,
                                    "password": pw, "quota": 0})
    if ok(res, f"Laatikko {local}@{HOST}"):
        tied = os.path.join(DESK, f"{local}-{HOST}-SMTP-tunnukset.txt")
        with open(tied, "w", encoding="utf-8") as f:
            f.write(f"SÄHKÖPOSTI: {local}@{HOST}\nSALASANA : {pw}\nSMTP      : {HOST} portti 465 (SSL) tai 587 (STARTTLS)\nIMAP      : {HOST} portti 993 (SSL)\n")
        print(f"  -> Tunnukset tallennettu: {tied}")
        print("  !! Poista tiedosto Gmail-asetuksen jälkeen (sisältää salasanan selkokielisenä).")
        return {"local": local, "pw": pw}
    return None

def luo_uudelleenohjaus(local=None):
    print("\n[3] Uudelleenohjaus -> Gmail")
    dom_ = input(f"  Domain (huolto.fi / dev.huolto.fi) [huolto.fi]: ").strip() or HOST
    local = local or input("  Osoitteen nimi (kohta @-merkin edessä) [dev]: ").strip() or "dev"
    dest = input(f"  Kohdesähköposti [{GMAIL}]: ").strip() or GMAIL
    res = uapi("Email", "add_forwarder", {"domain": dom_, "email": local,
                                          "fwdopt": "fwd", "fwdemail": dest})
    ok(res, f"Uudelleenohjaus {local}@{dom_} -> {dest}")

def dkim_dmarc():
    print("\n[4] DKIM + DMARC")
    ok(uapi("Email", "enable_dkim"), "DKIM aktivointi (toimitusvarmuus)")
    # DMARC vain jos ei jo olemassa
    r = subprocess.run(["nslookup", "-type=TXT", DMARC, "8.8.8.8"], capture_output=True, text=True, timeout=20)
    if "v=DMARC1" in (r.stdout + r.stderr):
        print("  DMARC ok jo olemassa")
        return
    val = "v=DMARC1; p=quarantine; rua=mailto:" + GMAIL
    ok(uapi("DNS", "add_zone_record", {"domain": HOST, "name": DMARC,
                                       "type": "TXT", "record": val, "ttl": 3600}),
       "DMARC-tietue lisätty")

def luo_alidomain():
    print("\n[5] Alidomain dev.huolto.fi (+MX)")
    res = uapi("SubDomain", "addsubdomain",
               {"domain": "dev", "rootdomain": HOST, "dir": "public_html/dev"},
               api="api2")
    if res.get("cpanelresult", {}).get("event", {}).get("result") in (1, "1"):
        print("  ✓ Alidomain dev.%s luotu" % HOST)
    else:
        print("  ! Alidomainia ei voitu luoda API:lla — luo se cPanelissa: Domains -> Create a New Domain: dev.huolto.fi")
    # MX osoittamaan pääpalvelimelle
    ok(uapi("DNS", "add_zone_record", {"domain": HOST, "name": f"dev.{HOST}",
                                       "type": "MX", "record": f"0 {HOST}.", "ttl": 14400}),
       f"MX dev.{HOST} -> {HOST}")
# ---------------- Gmail-apurit ----------------

def smtp_testi(laatikko=None):
    """Lähettää testiviestin laatikolta Gmailille sekä dev@ -> dev@ (forwarder-testi)."""
    print("\n[6] SMTP-testiviestit")
    if laatikko is None:
        local = input(f"  Lähettävä laatikko [dev]: ").strip() or "dev"
        pw = getpass.getpass(f"  Salasana ({local}@{HOST}): ")
        laatikko = {"local": local, "pw": pw}
    src = f"{laatikko['local']}@{HOST}"
    msg = ("From: %s\r\nTo: %s\r\nSubject: Testi %s\r\n\r\n"
           "Hei! Tama on automaattinen kokoonpanotesti.\r\n" % (src, GMAIL, secrets.token_hex(3)))
    try:
        s = smtplib.SMTP_SSL(HOST, 465, timeout=25)
        s.login(src, laatikko["pw"])
        s.sendmail(src, [GMAIL], msg)   # testi suoraan Gmailiin
        s.sendmail(src, [src], msg)     # forwarder-testi: itselleen -> kulkeutuu Gmailiin
        s.quit()
        print(f"  ✓ Lahetys onnistui ({src} -> {GMAIL} ja {src} -> {src}).")
        print("  Tarkista Gmail 1–2 min kuluttua: saapuvat molemmat? (toinen on forwarder-testi)")
    except Exception as e:
        print("  ✗ SMTP-virhe:", e)

def avaa_gmail():
    print("\n[7] Avaa Gmailin 'Lähetä postia muilla osoitteilla' -sivu")
    url = "https://mail.google.com/mail/u/0/#settings/accounts"
    os.system(f'start "" "{url}"')
    print("  Lisaa -> nimi Huoltokello, osoite dev@" + HOST)
    print("  SMTP: %s | portti 465 | SSL | kayttaja: dev@%s | salasana: laatikon salasana" % (HOST, HOST))
    print('  Muista rastittaa "Käsittele aliaksena" ja vahvistaa koodi (saapuu forwarderilla).')

# ---------------- pääohjelma ----------------

def main():
    banner()
    if "--tarkistus" in sys.argv:
        dns_ja_portit()
        return
    laatikko = None
    while True:
        print("\nValinta:")
        print("  1) DNS- ja porttitarkistus (ei tunnuksia)")
        print("  2) Luo sähköpostilaatikko (dev@huolto.fi, arkisto/kopio rinnalle)")
        print("  3) Luo uudelleenohjaus (forwarder) -> Gmail            [SUOSITELTU: 2+3]")
        print("  4) DKIM + DMARC (toimitusvarmuus)")
        print("  5) Luo alidomain dev.huolto.fi (+MX)")
        print("  6) SMTP-testiviestit (laatikko -> Gmail ja itselleen)")
        print("  7) Avaa Gmailin asetussivu ja näytä arvot")
        print("  0) Lopeta")
        val = input("Valintasi: ").strip()
        if val == "1": dns_ja_portit()
        elif val == "2": laatikko = luo_laatikko() or laatikko
        elif val == "3": luo_uudelleenohjaus()
        elif val == "4": dkim_dmarc()
        elif val == "5": luo_alidomain()
        elif val == "6": smtp_testi(laatikko)
        elif val == "7": avaa_gmail()
        elif val == "0":
            print("Lopetetaan. Ohje PDF: C:\\Users\\PC\\Desktop\\dev-huoltofi-Gmail-Ohje.pdf")
            break
        else: print("  Tuntematon valinta")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nKeskeytetty.")


