# Arkkitehtuuri, rakenne ja tietoturva

## Paketin rakenne (Huoltokello-Multiasennus)

```
Huoltokello-Multiasennus/
├─ Asenna.cmd                       ← käynnistin (kaksoisnapsautus)
├─ Asenna-Huoltokello-Multa.ps1     ← asennusvelho (GUI + -Silent-tila)
├─ Osa-Azure.ps1                    ← Azure-asennuksen osa (velhon kutsu)
├─ Osa-Palvelin.ps1                 ← palvelinasennuksen osa (WinRM)
├─ app.zip                          ← Huoltokello-ohjelma (itsenäinen, n. 48 Mt)
├─ assets/                          ← huoltokello.ico, huoltokello-ohjeet.ico
├─ Ohjeet/                          ← Kayttoonotto-Opas.html, Multiasennus-Opas.html
├─ Tyokalut/                        ← 12 ylläpitotyökalua + _yhteinen.ps1-kirjasto
├─ VERSIO.txt                       ← täydellinen versioloki
└─ docs/                            ← tämä dokumentaatio (GitHub-Markdown)
```

Kokonaisasennuspaketti (`Huoltokello-Multiasennus.zip`, jokelijaettava) on GitHub **Releases**-sivulla.

## Mitä paikallinen asennus luo ja mihin

| Kohde | Sisältö |
|---|---|
| Asennuskansio (oletus `%LOCALAPPDATA%\Huoltokello`) | ohjelma (app), Ohjeet, Tyokalut, kuvakkeet, `appsettings.json` (asetukset), Asennus-yhteenveto.txt |
| Asennuskansio`\AppData` | **tietokanta** (`huoltokello.db`), liitteet, salausavaimet, lokit (`app-out.log`, `app-err.log`) |
| Työpöytä + Käynnistyvalikko | "Huoltokello" ja "Huoltokello-Ohjeet"-pikakuvakkeet (paksetin omilla kuvakkeilla) |
| Windowsin Tehtävä-ajastus | autonomaattinen käynnistys kirjautumisen yhteydessä (jos valittu) |
| Windowsin Sovellukset-lista | merkintä "Huoltokello" — poisto listasta käynnistää graafisen poistotyökalun |
| Windowsin palomuuri | sisääntulosääntö TCP-portille (vain lähiverkkokäytössä) |

## Sovelluksen toiminta

- **Web-sovellus selaimessa**: ohjelma palvelee HTTP-rajapinnan osoitteessa `http://127.0.0.1:<PORTTI>` (paikallinen) tai palvelimen/Internetin osoitteessa (palvelin/Azure)
- **Reaaliaikainen yhteys**: SignalR välittää muutokset (tehtävät, kuitit) kaikkiin avoisiin selaimiin heti
- **PWA**: puhelimen selaimella "Lisää aloitusnäytölle" — apinäkymä; **service worker** valmisti sovelluksen ja avatut sivut toimimaan **offline-tilassa**; verkko-terveystesti `/health` aina suoraan verkosta
- **Offline-kirjaus**: kuittauslomake tallentaa kirjauksen laitteeseen ja lähettää sen automaattisesti verkon palatessa
- **Web Push**: VAPID-tekniikka → ilmoitus uudesta tehtävästä ilman, että sovellus on auki
- **QR**: kohteiden tarrat luodaan/tulostetaan massatulostuksella Kohteet-sivulta; puhelimen kamera lukee tarraa jsQR-kirjastolla
- **Sähköposti**: SMTP (STARTTLS suositeltu, portti 587); sallittujen vastaanottojen hoito Johdon valikossa

## Tietoturvamalli (kovitukset v2.4.1 → v2.7.3)

| Alue | Ratkaisu |
|---|---|
| Kuljetus | HTTPS-pakotus + HSTS Azure App Servicessa; HTTP/2; lähiverkossa paikallinen HTTP (portti koneen muurin takana, sääntö vain TCP-portille) |
| Push-avaimet (VAPID) | yksityisavain EI julkaisupaketissa: työpöytäasennus luo **oman avainparin** asennukselle ja kirjoittaa sen `appsettings.Production.json`iin (tiedoston ACL vain nykyiselle käyttäjälle); päivityspaketti ei ylikirjoita; Azure lukee avaimen App Settings -muuttujasta (`Vapid__PrivateKey`) |
| Demodata | `SeedDemoData` oletuksena pois (appsettings.json + koodin oletusarvot) — demopainikkeet eivät näy kirjautumissivulla |
| Otsikot | Content-Security-Policy, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy (kamera sallittu QR-skannaukseen) |
| Salasanasähköpostit | sallittuja vain Johdon valitsemiksi; alkusalasana lähtee vain **vahvistettuun** palautussähköpostiin (vahvistuslinkki 24 h, token vain SHA-256-tiivisteenä); salasana ei näy käyttöliittymässä eikä tietokannassa |
| Tunnistautuminen | kirjautumislukitos (5 väärää yritystä → 15 min); istunto 30 päivää liukuvanhennuksella |
| Levosalaus | Azure App Servicen tallennuksen salaus alustan puolesta; työpöytäasennuksessa vastuu on koneen BitLockerilla |
| Asetukset | SMTP-sähköpostitilin salasana ei näy käyttöliittymässä eikä tallenneta tietokantaan — asennuskansion `appsettings.json`iin; päivitys (`Paivita.ps1`) säilyttää asetukset |

## Verkkovaatimukset

| Käyttötapa | Osoite/portti |
|---|---|
| Paikallinen käytön | `http://127.0.0.1:8088` (oletus; portti valittavissa) |
| Lähiverkkokäyttö (muut koneet + puhelimet) | `http://<koneenIP>:<PORTTI>` — palomuurisääntö TCP-portille; osoitteet näkyvät Asetukset-sivulla, Asennus-yhteenveto.txt ja asennuksen valmis-sivulla |
| Palvelinasennus | `http://<palvelin>:8080` (oletus; valittavissa) |
| Azure | App Servicen URL; HTTPS-only + HTTP/2 |

## Päivitys- ja palautusajattelu

- uusi versio = uusi `app.zip` + `Tyokalut\Paivita.ps1` — data (tietokanta, liitteet, asetukset, VAPID-avain) **säilyy**; `SeedDemoData` säilyy pois
- varmuuskopiot: `Varmuuskopioi.ps1` (30 uusinta `%USERPROFILE%\Huoltokello-Varmuuskopiot`), palautus `Palauta-Varmuuskopio.ps1`
- poisto: Windowsin Sovellukset-lista → graafinen poistotyökalu; tietokanta varmuuskopioidaan työpöydälle poiston yhteydessä