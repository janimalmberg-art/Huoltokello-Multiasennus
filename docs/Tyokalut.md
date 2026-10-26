# Ylläpitotyökalut (Tyokalut)

Työkalut ovat asennuskansion `Tyokalut`-alikansiosta — aja ne sieltä kaksoisnapsauttamalla tai PowerShellista. Samat skriptit löytyvät myös asennuspaketin kansiosta; ne osaavat etsiä asennuskansion itse (kutsujan osoitus → Sovellukset-listan InstallLocation → ohjelmatiedoston etsintä → oletuskansio)

## Tyokalut/_yhteinen.ps1 — yhteinen kirjasto

Muut työkalut lataavat tämän: antaa yleiset funktiot (`Get-HkInstallDir`, `Get-HkPort`, `Test-HkHealth`, `Stop-HkApp` ym.). Sitä ei ajeta suoraan.

## Päivittäiseen käyttöön

| Työkalu | Mitä se tekee |
|---|---|
| `Kaynnista.ps1` | käynnistää Huoltokellon + avaa selaimen kirjautumissivulle |
| `Lopeta.ps1` | sulkee Huoltokellon (odottaa prosessin varmaa päättymistä — tiedostolukot pois) |
| `Varmuuskopioi.ps1` | sulkee ohjelman ajaksi, varmuuskopioi `AppData`-kansion (tietokanta + salausavaimet + liitteet) ja pitää **30 uusinta** kopiota: `%USERPROFILE%\Huoltokello-Varmuuskopiot` |
| `Palauta-Varmuuskopio.ps1` | palauttaa AppData-kansion valitusta varmuuskopiosta (ohjattu) |

## Käyttäjien ja tunnusten ylläpito

| Työkalu | Mitä se tekee |
|---|---|
| `Luo-YllapitajaTili.ps1` | ohjattu uuden **Johto-tilin** luonti: kirjoittaa `AppData\first-admin.json`, jonka sovellus lukee seuraavassa käynnistyksessä. Käytä esim. kun salasana unohtui — käytä **UUTTA sähköpostia** (vanhaa ei voi ylikirjoittaa) |
| `Luo-Kayttaja.ps1` | ohjattu käyttäjätunnusten luonti sovelluksen kautta (kirjautuu Johto-tilillä) |

## Verkkokäyttö

| Työkalu | Mitä se tekee |
|---|---|
| `PuhelinKaytto.ps1` | ottaa käytön puhelimista/lähiverkosta: kuunteluosoite `0.0.0.0` + Windows-palomuurisääntö + uudelleenkäynnistys; näyttää laitteiden osoitteet. `-Poista` palauttaa vain paikallisen käytön (127.0.0.1) ja poistaa palomuurisäännön |

## Ylläpito ja poisto

| Työkalu | Mitä se tekee |
|---|---|
| `Paivita.ps1` | päivittää ohjelman uudella `app.zip`-paketilla — data (tietokanta, liitteet, asetukset) **säästyy**; `SeedDemoData` pysyy pois |
| `Poista-Asennus.ps1` | poistaa asennuksen komentoriviltä; varmistaa ensin. Parametri `-InstallDir` osoittaa asennuskansion suoraan (pakettikansiosta ajettuna tarpeen) |
| `Poista-Asennus-GUI.ps1` | **graafinen poisto** (suositellut menetelmä): valinta, että poistetaanko vai säilytetäänkö data varmuuskopion kera |
| `Korjaa-Kuvakkeet.ps1` | korjaa jo asennetun version pikakuvakkeet ilman uudelleenasennusta ja päivittää Windowsin kuvakevälimuistin |
| `Luo-Kuvakkeet.ps1` | piirtää paketin omat monikokoiset kuvakkeet (16–256 px): Huoltokello = toimistokone + kello, Huoltokello-Ohjeet = lamppu |

## Muistilista

- **Varmuuskopiointi** suositellaan päivittäin (Windowsin Tehtävä-ajastus — ohjeet `Ohjeet/Kayttoonotto-Opas.html`, luku "Varmuuskopiointi"); kopioi kopiot säännöllisesti myös toiselle asemalle/pilveen
- Jos portti on varattu: vaihda portti velhon asetuksissa tai sulje sitä käyttävä ohjelma (`Lopeta.ps1`)
- Poistot tarkistavat ja sulkevat prosessin ensin ja varmuuskopioivat datan työpöydälle (`Huoltokello-data-<pvm>.zip`) ennen asennuskansion poistoa