# Multiasennusopas — kolme asennustapaa

Tämä paketti asentaa Huoltokellon (Kiinteistonhuollon taktinen työhallinta) kolmella tavalla. Siirrä **koko kansio** sille koneelle, jolta asennus ajetaan, ja käynnistä:

```
Asenna.cmd   ← graafinen asennusvelho (suositeltu)
```

Velho kysyy asennustavan ja kaikki tarvittavat tiedot, näyttää jokaisen vaiheen edistymisen ja pyytää **LUVAT-sivulla** luvan siihen, että skripti saa toimia käyttäjän puolesta, ennen kuin yhtään muutosta tehdään.

> Vaihtoehtoinen aloitus: `powershell -ExecutionPolicy Bypass -STA -File .\Asenna-Huoltokello-Multa.ps1` (avautuu sama velho GUI:lla)

---

## 1) Paikallinen

Ohjelma asennetaan omalle koneelle (`%LOCALAPPDATA%\Huoltokello` tai valitsemaasi kansioon, oletusportti **8088**):

- luo pikakuvakkeet, ylläpitotilin (Johto) ja tarvittaessa: palomuurisallinnan (puhelin/lähiverkkokäyttöön), automaattisen käynnistyksen ja rekisterimerkinnän
- ei muita vaatimuksia: **.NET-latauksia ei tehdä**, internet-yhteyttä ei vaadita

Yksityiskohtainen opas velhon vaiheet: [Asennusopas.md](Asennusopas.md)

## 2) Microsoft Azure

Ohjelma asennetaan Microsoftin pilveen **käyttäjän omalle Microsoft/Azure-tilille**:

- kirjautuminen laitelaitekoodilla (`www.microsoft.com/devicelogin`)
- velho luo Azure-tilillesi: resurssiryhmän, App Service -palvelupaketin (**B1/F1/P1v2**), sovelluksen, asetukset + vie ohjelman + käynnistää sen
- tili tarvitsee oikeuden luoda resursseja tilaukseen (esim. Omistaja tai Osallistuja)
- **Huom**: Azure-käyttö maksaa — B1-testitaso on halvin. Poisto onnistuu poistamalla resurssiryhmä Azure-portaalista (velho tulostaa nimen)
- HTTPS ja HSTS pakotetaan (tietoturvakovitettu versio: v2.4.1 lähtien)

## 3) Yrityksen oma Windows-palvelin

Ohjelma siirretään ja käynnistetään yrityksen omalle Windows-serverille:

- yhteydenotto **WinRM**:lla, tiedostojen siirto, käyttöoikeudet, palomuuri, tehtävä-ajastuksena toimiva palvelu
- tarvitset palvelimen osoitteen ja ylläpitotunnukset; TCP-portin vapaana (oletus 8080)
- jos palvelin ei ole samassa toimialueessa, velho pyytää lupaa käyttää TrustedHosts-korjausta **omalla koneellasi**
- palvelimen vanhat Huoltokello-tiedostot ylikirjoitetaan; **tietokanta ja asetukset säilytetään**

---

## Vaatimukset

| | Paikallainen | Azure | Palvelin |
|---|---|---|---|
| Windows 10/11 + PowerShell 5.1 | ✔ | ✔ | ✔ |
| N. 600 Mt vapaa levytila | ✔ | (asennuskone) | ✔ |
| Internet | ei vaadita | ✔ | WinRM-yhteys |
| Muut | ei mitään | Microsoft/Azure-tili + Azure CLI (velho asentaa sen UAC-kyselyllä jos puuttuu) + tilauksen kirjoitusoikeus | WinRM käytössä, ylläpitotunnukset, vapaa TCP-portti |

---

## Hiljainen asennus (komentorivi, skriptattu käyttöön)

Hiljainen asennus vaatii lipun **`-HyvaksyLuvat`** (sama lupa, jonka LUVAT-sivu kysyy GUI:ssa).

Paikallinen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Asenna-Huoltokello-Multa.ps1 `
  -Silent -Mode paikallinen -InstallDir "C:\Huoltokello" -Port 8088 `
  -AdminName "Maija Meikäläinen" -AdminEmail "maija@firma.fi" -AdminPassword "Salasana1" `
  -HyvaksyLuvat
```

Valinnaiset liput: `-AutoStart`, `-PhoneAccess`, `-NoShortcuts`, `-NoBrowser`.

Azure:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Asenna-Huoltokello-Multa.ps1 `
  -Silent -Mode azure -HyvaksyLuvat ...
```

Palvelin:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Asenna-Huoltokello-Multa.ps1 `
  -Silent -Mode serveri -HyvaksyLuvat ...
```

Tarkista paketin kunto ennen jakelua:

```powershell
powershell -File Asenna-Huoltokello-Multa.ps1 -SelfTest
```

---

## Paketin sisältö

| Tiedosto/Kansio | Selitys |
|---|---|
| `Asenna.cmd` | käynnistin (graafinen velho) |
| `Asenna-Huoltokello-Multa.ps1` | asennusvelho (GUI + hiljainen); osat: `Osa-Azure.ps1`, `Osa-Palvelin.ps1` |
| `app.zip` | Huoltokello-ohjelma (n. 48 Mt) |
| `assets\` | kuvakkeet |
| `Ohjeet\` | Kayttoonotto-Opas.html, Multiasennus-Opas.html |
| `Tyokalut\` | ylläpitotyökalut — katso [Tyokalut.md](Tyokalut.md) |
| `VERSIO.txt` | ohjelman versiotiedot |

---

## Tuki ja vianetsintä

- velho näyttää jokaisen vaiheiden tuloksen; virhessä viimeisin vaihe kertoo syyn
- katso lokit: `%LOCALAPPDATA%\Huoltokello\AppData\logit` (paikallinen) tai palvelimen `AppData`-kansio (palvelin)
- portti varattu? valitse toinen portti (paikallisesti: `-Port`; muuten velhon kohdekenttä)
- Azure-kirjautuminen ei aukea? aja velho uudelleen ja kirjaudu `www.microsoft.com/devicelogin` -osoitteessa uudella koodilla
- lisätiedot: `Ohjeet/Kayttoonotto-Opas.html` ja [Asennusopas.md](Asennusopas.md)