# 🔔 Huoltokello — kiinteistonhuollon taktinen työhallinta

**Huoltokello-Multiasennus** on suomenkielinen asennuspaketti, jolla Huoltokello-työhallintaohjelma asennetaan **kolmella tavalla**: omalle Windows-koneelle, Microsoft Azure -pilveen tai yrityksen omalle Windows-palvelimelle. Asennus hoituu graafisella, lupaperiaatteella toimivalla **asennusvelholla** (`Asenna.cmd`), joka kysyy tarvittavat tiedot, näyttää jokaisen vaiheen edistymisen ja pyytää lupaa ennen kuin yhtään muutosta koneelle voidaan tehdä.

![Asennusvelhon käynnistys](Asennusoppaaseen%20kuvia/Asennusvelhon_kaynnistys.jpg)

| | |
|---|---|
| Ohjelmaversio | **v2.7.3** (30.9.2026) — historia: [docs/Versioloki.md](docs/Versioloki.md) |
| Alusta | Windows 10/11 (64-bittinen), PowerShell 5.1 (pakko ei ole lisäasennus) |
| Teknologia | itsenäinen (self-contained) .NET-sovellus — **.NET-latauksia EI tarvita** |
| Asennuksen alkutila | täysin tyhjä (ei demodataa) — ensimmäinen Johto-tili luodaan asennuksessa |
| Internet | ei vaadita paikallisessa asennuksessa eikä käytössä; vaaditaan vain Azure-asennuksessa ja sähköpostilähetyksissä |

## Asennustavat

| Tapa | Mihin asennetaan | Soveltuu kun |
|---|---|---|
| **1) Paikallinen** | oma kone (`%LOCALAPPDATA%\Huoltokello`), oletusportti 8088 | yhden koneen ja/tai pienen tiimin WiFi-käyttö |
| **2) Microsoft Azure** | käyttäjän oma Azure-tili (App Service: B1/F1/P1v2) | koko organisaation käyttö Internet-yhteydellä ja mobiilikäyttö mistä vain |
| **3) Windows-palvelin** | yrityksen oma Windows-palvelin (WinRM-ajo, oletusportti 8080) | sisäverkon monikäyttö omalla palvelimella |

Huom: Azure-käyttö maksaa (F1/B1-taso on hyvin edullinen) ja vaatii Azure-tilin, jolla on tilauksen kirjoitusoikeus; palvelinasennus vaatii WinRM-käytön ja ylläpitäjätunnukset. Kaikki yksityiskohdat ja hiljaiset komennot: [docs/Multiasennusopas.md](docs/Multiasennusopas.md).

## Mikä Huoltokello on

Huoltokello on selainpohjainen taktinen **työhallinta kiinteistonhuoltoon**: yhdestä paikasta hallitaan kohteet, vuosikellotehtävät, työt, kuittaukset, laskutus ja raportit — ja tiimi näkee saman tiedon yhtä aikaa tietokoneilla ja puhelimilla. Käyttöönotto on suunniteltu helpoksi: se etenee vaihe vaiheelta käyttöönottoppaan avulla, ja valmiiksi rakennettu PWA-näkymä tuo saman ohjelman puhelimeen ilman sovelluskauppaa.

### Keskeiset ominaisuudet

- **Vuosikello** — vuodenhuoltonäkymä: tehtäväkortit raahaus, kiireellisyyssuodatus, prioriteettivärit (vihreä/matala, sininen/normaali, punainen/kiireellinen)
- **Kuittaukset & QR** — kohteiden QR-tarrojen massatulostus; kohteen tarran lukeminen puhelimella avaa sen tehtävälistan suoraan (jsQR-skannaus Skannaa-valikossa)
- **Reaaliaikainen monikäyttö** — muut koneet JA puhelimet samassa WiFi-verkossa käyttävät samaa tietokantaa reaaliajassa (SignalR); samat tunnukset toimivat kaikista laitteista
- **PWA + tumma tila** — puhelimen selaimesta "Lisää aloitusnäytölle": apin näkymä, isommat painikkeet, tumma tila
- **Offline-kirjaus** — kuittauslomake toimii ilman verkkoa; kirjaus lähtee automaattisesti verkon palatessa; service worker pitää sovelluksen käytössä ilman nettiä
- **Web Push -ilmoitukset** — uudesta tehtävistä ilmoitus laitteelle vaikka sovellus ei olisi auki (Turvalokkikoordinoidut VAPID-avaimet)
- **Kuittausliitteet ja allekirjoitus** — liitteet kortteihin; asiakkaan vastaanoton allekirjoitus kuittauslomakkeella (myös offline-kirjauksessa)
- **Laskutus ja kirjanpitovienti** — vienti yhdellä klikkauksella kirjanpitojärjestelmään (Procountor, Netvisor, Fennoa); vientiloki ja uusintalähetys epäonnistuneille
- **Raportit, uudistusniput ja vuosikellon suunnitellut toimenpiteet**
- **Käyttäjähallinta + sähköposti** — alkusalasana lähetetään sähköpostilla (valmiit SMTP-esiasetukset: Gmail, Outlook/M365, ProtonMail, Yahoo, Telia, Elisa/Saunalahti, DNA, Zoho, iCloud); palautussähköpostin vahvustuslinkki (24h), pakotettu salasanan vaihto, kirjautumislukitus (5 yritystä → 15 min)

## Pika-asennus (paikallinen, velholla)

1. Hae paketti: **Releases**-sivulta (`Huoltokello-Multiasennus-*.zip`) — tai kloonaus alla
2. Pura ja siirrä kansio sille koneelle, jolta asennus ajetaan
3. Kaksoisnapsauta **`Asenna.cmd`**
4. Seuraa velhoa: kansio + portti → ensimmäinen Johto-tili → valinnat → yhteenveto → asennus (11 vaiheet, 1–3 min) → valmis
5. Selain avautuu osoitteeseen `http://127.0.0.1:8088` ja olet kirjautunut Johto-tilillä

## Kloonaus GitHubista (= sama sisältö kuin purettu paketti)

Repositorio sisältää ohjelmapaketin (`app.zip`) ja kaikki skriptit — asennusvelho toimii suoraan kloonista:

```powershell
git clone https://github.com/janimalmberg-art/Huoltokello-Multiasennus.git
cd Huoltokello-Multiasennus
.\Asenna.cmd
```

> Kokonaisasennuspaketti (`Huoltokello-Multiasennus.zip`, jaettava yhdellä napsautuksella esim. sähköpostitse) on **Releases-sivulla**. Repositorion `app.zip` riittää velhon työntämiseen.

## Hiljainen asennus (esimerkit)

```powershell
# Paikallinen
powershell -NoProfile -ExecutionPolicy Bypass -File Asenna-Huoltokello-Multa.ps1 `
  -Silent -Mode paikallinen -InstallDir "C:\Huoltokello" -Port 8088 `
  -AdminName "Maija Meikäläinen" -AdminEmail "maija@firma.fi" `
  -AdminPassword "Salasana1" -HyvaksyLuvat -AutoStart -PhoneAccess

# Azure   (-AzName, -AzRg, -AzRegion, -AzSku [-AzSubscription])
# Palvelin (-ServerHost, -ServerUser, -ServerPass [-ServerPath -ServerPort -ServerNotDomain])
```

Komennot ja kaikki liput: [docs/Multiasennusopas.md](docs/Multiasennusopas.md).

## Ylläpitotyökalut

Päivittäinen käyttö: `Kaynnista` / `Lopeta` — **varmuuskopiointi** (`Varmuuskopioi` / `Palauta-Varmuuskopio`) — salasanan unohtuminen: `Luo-YllapitajaTili` — päivitys: `Paivita` — poisto: `Poista-Asennus-GUI` — puhelinkäyttö: `PuhelinKaytto` — kuvakkeet: `Korjaa-Kuvakkeet`. Tarkemmin: [docs/Tyokalut.md](docs/Tyokalut.md).

## Dokumentaatio

| Dokumentti | Sisältö |
|---|---|
| [docs/Asennusopas.md](docs/Asennusopas.md) | paikallinen asennus vaihe vaiheelta (velhon vaiheet, hiljainen asennus, käyttöönotto, vianetsintä, kuvakkeet) |
| [docs/Multiasennusopas.md](docs/Multiasennusopas.md) | kolme asennustapaa (paikallinen / Azure / palvelin), vaatimukset, hiljaiset komennot, paketin kuntotesti |
| [docs/Tyokalut.md](docs/Tyokalut.md) | kaikki ylläpitotyökalut |
| [docs/Arkkitehtuuri-ja-rakenne.md](docs/Arkkitehtuuri-ja-rakenne.md) | mitä asennetaan ja mihin, tietokanta, tietoturvaliitokset, verkkoliitokset |
| [docs/Versioloki.md](docs/Versioloki.md) | versiohistoria (kokonaislogi: `VERSIO.txt`) |
| `Ohjeet/Kayttoonotto-Opas.html` | käyttöönottopassi (avautuu asennuksen jälkeen; sisältää: kirjautuminen, tehtävätyypit, työryhmät, käyttäjät, asiakkaat, sopimukset, kohteet + QR, vuosikellon tehtävät, laskutus, puhelinkäyttö) |
| `Huoltokello-Dokumentaatio.zip` | dokumentaatiopaketti yhdistettynä |

## Yleisimmät vianetsinnät

| Oire | Korjaus |
|---|---|
| Velho ei avaudu | Aja: `powershell -ExecutionPolicy Bypass -STA -File .\Asenna-Huoltokello-Multa.ps1` |
| "Portti on varattu" | Vaihda portti (esim. 8090) tai sulje se käyttävä ohjelma (`Tyokalut/Lopeta.ps1`) |
| Ohjelma ei käynnisty | Lokit: asennuskansio `AppData\app-out.log` ja `app-err.log`; käynnistä uudelleen `Huoltokello.cmd` tai `Tyokalut/Kaynnista.ps1` |
| Kirjautuminen ei onnistu | Tarkista tunnus (sähköposti) + salasana; salasana unohtunut → `Tyokalut/Luo-YllapitajaTili.ps1` UUDELLA sähköpostilla |
| Puhelin/toinen kone ei saa yhteyttä | Samassa WiFi:ssä ei vierasta verkkoa; sovelluksen Asetukset-sivulta verkko-osoitteet + palomuuritikia; vaihtoehtoisesti `Tyokalut/PuhelinKaytto.ps1` uudelleen |
| SMTP "530 5.7.0 Authentication Required" | Lähetys suojataan automaattisesti (v2.7.3): STARTTLS kytkeytyy olemalla ja tallennetaan asetuksiin; portti 465 ei ole tuettu (implisiittinen SSL) — vie siirtyminen porttiin 587; Gmail/M365: käytä sovellussalasanaa jos 2FA päällä |

## Tekijätunnuksiin liittyvät huomiot turvaliitoksista

- VAPID-yksityisavain (Web Push) ei matkustaa julkaisupaketissa: asennusvelho luo jokaiselle asennukselle **oman avainparin** ja kirjoittaa sen `appsettings.Production.json`-tiedostoon, jota päivityspaketti ei ylikirjoita; Azure lukee avaimen App Settings -muuttujasta
- demotunnukset pois tuotantoista (`SeedDemoData` oletuksena pois)
- turvallisuusotsikot: Content-Security-Policy, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy (kamera sallittu QR-skannaukseen)
- palautussähköpostin varmennustokenit tallennetaan vain SHA-256-tiivisteenä

## Lisenssi

Kaupallinen ohjelmisto; **kaikki oikeudet pidätetään** — katso [LICENSE.txt](LICENSE.txt). Yhteydenotot ja käyttöoikeuskysymykset: dev@huolto.fi.