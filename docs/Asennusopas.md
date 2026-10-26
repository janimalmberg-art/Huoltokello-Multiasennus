# Asennusopas — paikallinen asennus Windows-koneelle

Huoltokello-työhallintaohjelman asennus omalle koneelle (Windows 10/11, 64-bittinen). Asennus on täysin tyhjä (ei demodataa): luot ensimmäisen ylläpitotilin asennuksen yhteydessä ja lisäät tiedot itse vaihe vaiheelta. Yksityiskohtainen käyttöönottopass avautuu asennuksen jälkeen (`Ohjeet/Kayttoonotto-Opas.html`).

## 1. Vaatimukset

- Windows 10 tai 11 (64-bittinen)
- Noin 600 Mt vapaata levytilaa
- .NET-latauksia EI tarvita (ohjelma on paketoitu itsenäisesti — self-contained)
- Internet-yhteyttä ei tarvita asennuksen aikana eikä käytössä

## 2. Nopea asennus (graafinen velho) — suositeltu tapa

1. Avaa paketin kansio
2. Kaksoisnapsauta: **`Asenna.cmd`**
3. Seuraa velhoa (luku 3)
4. Kun velho ilmoittaa "ASENNUS VALMIS", ohjelma on käynnissä ja selain avautuu kirjautumissivulle

Jos velho ei avaa kaksoisnapsautuksella, käynnistä se PowerShellista:

```powershell
powershell -ExecutionPolicy Bypass -STA -File .\Asenna-Huoltokello-Multa.ps1
```

## 3. Velhon vaiheet

| Sivu | Aihe | Huomiot |
|---|---|---|
| 1 | Tervetuloa | yleiskuva asennuksesta |
| 2 | Kansio ja portti | asennuskansio (oletus `%LOCALAPPDATA%\Huoltokello`) ja portti (oletus 8088). Velho tarkistaa, ettei portti ole varattu ja ettei kansiossa ole estäviä oikeuksia |
| 3 | Ylläpitotili | luodaan ensimmäinen Johto-tili: nimi (esim. "Matti Meikäläinen"), sähköposti = kirjautumistunnus, salasana (vähintään 8 merkkiä, iso kirjain ja numero, esim. "Kello2026"). **TILI TULEE MUISTAA** — salasanaa ei voi nollata sovelluksesta; jos se unohtuu: `Tyokalut/Luo-YllapitajaTili.ps1` (uudella sähköpostilla!) |
| 4 | Valinnat | työpöytä- ja valikkopikakuvakkeet; käynnistys automaattisesti kirjautumisen yhteydessä (suositeltu); lähiverkkokäyttö (OLETUS PÄÄLLÄ): muut koneet JA puhelimet samaa dataa reaaliajassa (SignalR) — vaatii palomuurikysymyksen, valitse "Salli"; muutettavissa jälkikäteen Asetukset-sivulta tai `PuhelinKaytto.ps1` |
| 5 | Yhteenveto | tarkista tiedot ja paina "Asenna" |
| 6 | Asennus | 11 vaiheita, edistymispalkki (1–3 min) |
| 7 | Valmis | painikkeet: Avaa Huoltokello, Avaa käyttöönottopassi, Avaa asennuskansio |

> Jos valitsemassasi kansiossa on jo aiempi Huoltokello-asennus, velho päivittää ohjelman ja **säilyttää kaikki tiedot** — ylläpitotilia ei kysytä uudelleen.

## 4. Hiljainen asennus (komentorivi, kehittyneille)

```powershell
powershell -ExecutionPolicy Bypass -File .\Asenna-Huoltokello-Multa.ps1 `
  -Silent -InstallDir "C:\Huoltokello" -Port 8088 `
  -AdminName "Matti Meikäläinen" -AdminEmail "matti@yritys.fi" `
  -AdminPassword "Kello2026" -HyvaksyLuvat
```

Lisävalinnat: `-AutoStart` · `-PhoneAccess` · `-NoShortcuts` (ei pikakuvakkeita) · `-NoBrowser` (älä avaa selainta asennuksen jälkeen).## 7. Tyokalut-kansio (asennuskansion Tyokalut-alikansio)

Aja skriptit kaksoisnapsauttamalla tai PowerShellista:

| Työkalu | Tehtävä |
|---|---|
| `Kaynnista.ps1` | käynnistää ohjelman + avaa selaimen |
| `Lopeta.ps1` | sulkee ohjelman |
| `Luo-YllapitajaTili.ps1` | ohjattu uuden Johto-tilin luonti (esim. salasana unohtui; käytä UUTTA sähköpostia) |
| `Luo-Kayttaja.ps1` | ohjattu käyttäjien luonti sovelluksen kautta (kirjautuu Johto-tilillä) |
| `Varmuuskopioi.ps1` | varmuuskopioi AppData-kansion (`%USERPROFILE%\Huoltokello-Varmuuskopiot`) |
| `Palauta-Varmuuskopio.ps1` | palauttaa varmuuskopion (ohjattu) |
| `PuhelinKaytto.ps1` | ottaa käytön puhelimista samassa WiFi-verkossa; `-Poista` kumoaa muutokset |
| `Paivita.ps1` | päivittää ohjelman uudella app.zip-paketilla (data säilyy) |
| `Poista-Asennus.ps1` | poistaa asennuksen komentoriviltä (kysyy ensin varmistuksen) |
| `Poista-Asennus-GUI.ps1` | GRAAFINEN poisto: valinta tietojen varmuuskopiosta (suositeltu tapa) |

Tarkemmat kuvaukset: [Tyokalut.md](Tyokalut.md).

## 8. Varmuuskopiointi (suositeltu päivittäin)

- Yksittäinen kopio: `Tyokalut/Varmuuskopioi.ps1`
- Ajastus: `Ohjeet/Kayttoonotto-Opas.html` — luku "Varmuuskopiointi" (Windowsin Tehtävä-ajastus ajaa skriptin päivittäin)
- Palautus: `Tyokalut/Palauta-Varmuuskopio.ps1` (ohjattu)
- Varmuuskopiot ovat käyttäjän kotikansiossa (`Huoltokello-Varmuuskopiot`) — kopioi ne säännöllisesti myös toiselle asemalle tai pilveen

## 9. Puhelinkäyttö ja muiden koneiden käyttö (lähiverkko)

Kaikki saman WiFi/verkon laitteet (puhelimet JA muut tietokoneet) käyttävät samaa tietokantaa — tiedot kaikilla aina ajantasalla (reaaliaikainen synkronointi).

1. Jos valitsit puhelin/lähiverkkokäytön asennuksessa, kaikki on jo valmista. Muuten aja `Tyokalut/PuhelinKaytto.ps1` (salli palomuurikysymys) TAI sovelluksen Asetukset-sivu (Johto-rooli) → "Ota puhelinkäyttö käyttöön"
2. Puhelin tai toinen kone SAMASSA WiFi-verkossa: selain osoitteeseen `http://KONEEN-IP:PORTTI` — osoitteet näkyvät Asetukset-sivulla, `Asennus-yhteenveto.txt`-tiedostossa ja asennuksen valmis-sivulla
3. Puhelimen selaimesta: Lisää aloitusnäytölle (PWA) — toimii sovelluksen kaltaisena (offline-kirjaus, ilmoitukset, tumma tila)
4. Käyttäjät: kaikilla laitteilla käytetään SAMOJA tunnuksia (Hallinta > Käyttäjät) — tunnus ei sido yhteen laitteeseen
- Kumoa: Asetukset-sivu → "Palauta vain paikallinen käyttö" tai `Tyokalut/PuhelinKaytto.ps1 -Poista` (sulkee portin + poistaa palomuurisäännön)

## 10. Päivitys uudempaan versioon

1. Hanki uusi app.zip-paketti (sähköpostitse toimitettu)
2. Sulje ohjelma: `Tyokalut/Lopeta.ps1`
3. Kopioi uusi app.zip asennuskansioon ja aja: `Tyokalut/Paivita.ps1` — data (tietokanta, liitteet, asetukset) säilyy; SeedDemoData pysyy pois päältä

VAIHTOEHTO: aja `Asenna.cmd` ja valitse SAMalle koneelle SAMA kansio — velho havaitsee aiemman asennuksen ja päivittää sen.

## 11. Asennuksen poisto

- Suositus: Windowsin Asetukset > Sovellukset > Huoltokello > Poista (käynnistää graafisen poistotyökalun)
- Tai suoraan: `Tyokalut/Poista-Asennus-GUI.ps1` (graafinen) tai `Tyokalut/Poista-Asennus.ps1` (komentorivi, kysyy varmistuksen)
- Poisto sulkee ohjelman, poistaa pikakuvakkeet, Tehtävä-ajastuksen, rekisterimerkinnän ja asennuskansion
- Tietokanta varmuuskopioidaan työpöydälle (`Huoltokello-data-<pvm>.zip`) ENNEN poistoa
- Graafisessa poistossa voit valita, että data poistetaan lopullisesti ilman varmuuskopiota
- Jos haluat säilyttää datan itse: kopioi asennuskansion **AppData**-kansio talteen ennen poistoa

## 12. Ongelmatilanteet

| Oire | Syy/korjaus |
|---|---|
| Velho ei avaudu kaksoisnapsautuksella | Aja PowerShellista: `powershell -ExecutionPolicy Bypass -STA -File .\Asenna-Huoltokello-Multa.ps1` |
| "Portti on varattu" | Valitse velhossa toinen portti (esim. 8090) tai sulje porttia käyttävä sovellus (`Tyokalut/Lopeta.ps1`) |
| Ohjelma ei käynnisty / selain ei saa yhteyttä | Lokit: asennuskansio `AppData\app-out.log` ja `app-err.log`; käynnistä uudelleen `Huoltokello.cmd` tai `Tyokalut/Kaynnista.ps1` |
| Kirjautuminen ei onnistu | Tarkista tunnus (sähköposti) ja salasana; salasana unohtunut: `Tyokalut/Luo-YllapitajaTili.ps1` → uusi Johto-tili UUDELLA sähköpostilla |
| Puhelin ei saa yhteyttä | Asetukset-sivulta: lähiverkkokäyttö päällä? Palomuurisääntö OK (TCP portti)? Puhelin samassa verkossa? Vaihtoehtoisesti aja `Tyokalut/PuhelinKaytto.ps1` uudelleen |
| Toinen tietokone ei saa yhteyttä | Sama tarkistus kuin puhelimella; varmista sama verkko (ei vierasverkon eristystä) |

Muu ongelma: `Ohjeet/Kayttoonotto-Opas.html` — luku "Ongelmatilanteet".

## 13. Työpöydän kuvakkeet (ikonit)

Pikakuvakkeet käyttävät paketin omia kuvakkeita — **Huoltokello** = tietokone ja kello (`huoltokello.ico`), **Huoltokello-Ohjeet** = lamppu (`huoltokello-ohjeet.ico`). Asennus kopioi kuvakkeet asennuskansioon ja asettaa ne pikakuvakkeisiin automaattisesti.

Jos kuvakkeet näyttävät tyhjiltä tai valkoisilta, aja asennuskansiossa:

```powershell
powershell -ExecutionPolicy Bypass -File Tyokalut\Korjaa-Kuvakkeet.ps1
```

Työkalu korjaa pikakuvakkeet ja päivittää Windowsin kuvakevälimuistin (ilman uudelleenasennusta).

Kuvakkeen vaihto käsin:

1. Napsauta pikakuvaketta hiiren oikealla → Ominaisuudet
2. Muokkaa-painike (tai Vaihda kuvake pikakuvakkeille) → "Vaihda kuvake..."
3. Selaa asennuskansioon ja valitse `huoltokello.ico` (tai `huoltokello-ohjeet.ico`) → OK
4. Jos kuvake ei päivity heti: F5 työpöydällä tai ulos/takaisin-kirjautuminen

Vinkki: "Vaihda kuvake"-ikkunasta voi valita muunnoskuvan myös Microsoftin omista kuvakkeista: `C:\Windows\System32\imageres.dll` (järjestelmäkuvakkeet), `shell32.dll` (klassiset), `ddores.dll` (laitteet).

## 14. Lisätiedot

- [README.md](../README.md) — paketin yleiskuva (GitHub)
- [Multiasennusopas.md](Multiasennusopas.md) — kolme asennustapaa ja hiljaiset komennot
- [Arkkitehtuuri-ja-rakenne.md](Arkkitehtuuri-ja-rakenne.md) — tekninen rakenne ja tietoturva
- [Tyokalut.md](Tyokalut.md) — kaikki ylläpitotyökalut tarkemmin
- `Ohjeet/Kayttoonotto-Opas.html` — yksityiskohtainen käyttöönottopassi
- Asennuskansion `Asennus-yhteenveto.txt` — asennuksen tiedot (osoite, tili, ajat)
- Huoltokello — kiinteistonhuollon taktinen työhallinta; valmistaja: Huoltokello (dev@huolto.fi)

## 5. Ensimmäinen käyttö ja käyttöönottö

1. Avaa selain osoitteeseen `http://127.0.0.1:8088` (tai velhon ilmoittama osoite) ja kirjaudu ylläpitotilillä
2. Käyttöönottopassi vaihe vaiheelta (`Ohjeet/Kayttoonotto-Opas.html`), luvut:
   1. kirjautuminen · 2. tehtävätyypit · 3. työryhmät · 4. käyttäjät · 5. asiakkaat · 6. sopimukset · 7. kohteet (+ QR-koodit) · 8. vuosikellon tehtävät · 9. laskutus · 10. puhelinkäyttö (PWA, tumma tila)
3. Ohjelman voi käynnistää myös työpöydän "Huoltokello"-pikakuvakkeesta tai asennuskansion `Huoltokello.cmd`-tiedostosta

## 6. Mitä asennetaan ja mihin

- **Asennuskansio**: ohjelma (app), Ohjeet, Tyokalut, `huoltokello.ico`, Asennus-yhteenveto.txt (osoite, tili, asennusaika)
- **Asennuskansio\AppData**: tietokanta (`huoltokello.db`), liitteet, salausavaimet ja lokit (`app-out.log` / `app-err.log`)
- **Työpöytä + Käynnistyvalikko**: "Huoltokello" ja "Huoltokello-Ohjeet"-pikakuvakkeet (jos valittu)
- **Windowsin Tehtävä-ajastus**: käynnistys kirjautumisen yhteydessä (jos valittu)
- **Windowsin Sovellukset-lista**: "Huoltokello" — poisto mahdollinen sieltä
- **Windowsin palomuuri**: sääntö TCP-portille (vain jos puhelin/lähiverkkokäyttö valittiin)