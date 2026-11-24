# Huoltokello-Multiasennus v2.7.3 – koodikatselmointi ja tietoturvakorjaukset

Katselmoitu: 16.11.2026 · Lähde: `Huoltokello-Multiasennus-Koodilistaus.pdf` (124 s., 39 tiedostoa, 6 048 riviä)

## Mitä katselmoitiin ja mitä ei

Koodilistaus sisältää **asennusvelhon, Azure- ja palvelinasennuksen, 14 ylläpitotyökalua, julkaisuskriptit,
dokumentaation ja HTML-oppaat**. Itse Huoltokello-sovellus (C#/.NET, `KiinteistoHuolto.Web.exe`) on listauksessa
vain käännettynä `app.zip`-pakettina, joten **sovelluksen laskutus-, kirjanpitovienti- ja kirjautumiskoodia ei
voitu katselmoida eikä muuttaa**. Siksi uudet toiminnot (työajanseuranta, hinnoittelu, laskutus, kirjanpito,
palkkakoosteet, viennit) on toteutettu erillisenä, testattuna **Huoltokello-Talous**-moduulina (ks. README.md),
joka toimii Huoltokellon rinnalla ja ottaa työajat vastaan CSV-tuonnilla tai rajapinnalla.

Vakavuusluokat: **KRIITTINEN** = tietojen menetys, tunnusten vuoto tai toiminto ei toimi lainkaan ·
**KORKEA** = hyödynnettävä tietoturvapuute · **KESKITASO** = puute, joka vaatii lisäehdon · **MATALA** = laatu.

Sarake *Tila*: **Korjattu** = korjattu tiedosto kansiossa `korjatut-skriptit/` · **Ohje** = korjausohje alla
(tiedosto liian suuri luotettavasti rekonstruoitavaksi PDF:stä) · **Sovellus** = vaatii muutoksen C#-koodiin.

## Löydökset

| # | Vakavuus | Tiedosto (rivi) | Havainto | Tila |
|---|---|---|---|---|
| 1 | KRIITTINEN | Osa-Palvelin.ps1 (16–21), Asenna-…Multa.ps1 (1006, 1492) | Velho ja hiljainen asennus välittävät palvelimen salasanan avaimella `ServerPass`, mutta `Get-HkServerCredential` lukee vain `ServerPassword`/`ServerPasswordSecure`. `ConvertTo-SecureString` tyhjällä merkkijonolla kaatuu → **palvelinasennus ei toimi lainkaan**. | Korjattu |
| 2 | KRIITTINEN | Poista-Asennus.ps1 (56–65), Poista-Asennus-GUI.ps1 (62–80) | Jos datan varmuuskopiointi epäonnistuu (PS 5.1:n `Compress-Archive` ei tue yli 2 Gt:n tiedostoja, levy täynnä, tiedosto lukittu), virhe vain tulostetaan ja **asennuskansio tietokantoineen poistetaan silti** → pysyvä tietojen menetys. | Korjattu (GUI: Ohje A) |
| 3 | KRIITTINEN | _yhteinen.ps1 (20–27), Poista-Asennus*.ps1 | `Get-HkInstallDir` palauttaa viimeisenä vaihtoehtona skriptin yläkansion, vaikka siellä ei ole Huoltokelloa, ja `-InstallDir` hyväksyy minkä tahansa kansion. Poistotyökalu ajaa sille `Remove-Item -Recurse -Force` → esim. `-InstallDir C:\Users\Nimi` tyhjentäisi profiilin. | Korjattu |
| 4 | KRIITTINEN | Tyokalut/asenna-sahkoposti.py (28–35, 54) | TLS-varmennetarkistus kytkeytyy **hiljaa pois minkä tahansa virheen jälkeen**, minkä jälkeen cPanel-tunnukset lähetetään varmentamattomaan yhteyteen (välimieshyökkäys). Lisäksi tunnukset yritetään automaattisesti myös porttiin 2087 (WHM/root). Laatikon salasana kulkee URL:ssa (GET → palvelinlokit) ja tallennetaan selkokielisenä työpöydälle. | Korjattu |
| 5 | KRIITTINEN | Osa-Palvelin.ps1 (161) | Huoltokello ajetaan palvelimella **SYSTEM-tililla, RunLevel Highest**. Mikä tahansa web-sovelluksen haavoittuvuus antaisi täydet oikeudet koko palvelimeen. | Korjattu (LOCAL SERVICE + rajatut ACL:t) |
| 6 | KRIITTINEN | Asenna-…Multa.ps1 (262–263, 387–388), Luo-YllapitajaTili.ps1 (47–52) | `first-admin.json` sisältää johto-tunnuksen **salasanan selkokielisenä**, kirjoitetaan ilman käyttöoikeusrajausta, eikä työkalu varmista sen poistoa. Azure-asennuksessa tiedosto viedään App Servicen `wwwroot`-kansioon (Kudu/FTP-luettava). | Työkalut korjattu, velho: Ohje B, sovellus: varmista poisto |
| 7 | KORKEA | Asenna-…Multa.ps1 (560), PuhelinKaytto.ps1 (33), Osa-Palvelin.ps1 (150) | Lähiverkko- ja palvelinkäyttö on **salaamatonta HTTP:tä** (salasanat ja istuntoevästeet WiFi-verkossa), ja palomuurisääntö `profile=any` avaa portin myös julkisissa verkoissa koko internetiin päin. | Sääntö korjattu (private/domain + localsubnet); HTTPS: Ohje C |
| 8 | KORKEA | Osa-Azure.ps1 (325–330) | Kudu-varaviennissä **perustunnistautuminen (SCM basic auth) kytketään pysyvästi päälle** eikä sitä koskaan kytketä pois; julkaisutunnukset jäävät voimaan. | Ohje D |
| 9 | KORKEA | Osa-Azure.ps1 (272–276) | VAPID-yksityisavain annetaan `az`-komentorivillä → näkyy prosessilistassa, mahdollisesti komentolokeissa. | Ohje D |
| 10 | KORKEA | Osa-Azure.ps1 (103–106) | Azure CLI:n MSI ladataan ja asennetaan **korotetuin oikeuksin ilman allekirjoituksen tarkistusta**. | Ohje D |
| 11 | KORKEA | Tyokalut/Paivita.ps1 (60) | Mikä tahansa zip puretaan asennuskansion päälle (`Expand-Archive -Force`) ilman eheys- tai sisältötarkistusta. Paketti, jossa on `AppData\huoltokello.db` tai `appsettings.Production.json`, **ylikirjoittaisi tietokannan tai avaimet**. Ei paluuta edelliseen versioon, jos uusi ei käynnisty. | Korjattu (SHA-256, sisältötarkistus, rollback) |
| 12 | KORKEA | Tyokalut/Palauta-Varmuuskopio.ps1 (30–43) | Varmuuskopio puretaan nykyisen AppDatan päälle: vanhat SQLite `-wal`/`-shm`-tiedostot voivat jäädä ja **korruptoida palautetun kannan**. Sovellusta ei suljeta, jos se on käynnissä mutta /health ei vastaa. Ei rakennetarkistusta. | Korjattu |
| 13 | KORKEA | Tyokalut/Varmuuskopioi.ps1 (12–24) | Tietokanta kopioidaan sovelluksen ollessa käynnissä, jos /health ei vastaa (epäjohdonmukainen kopio). 2 Gt:n raja. Varmuuskopiot (kanta + avaimet + henkilötiedot) **ilman käyttöoikeusrajausta**. | Korjattu |
| 14 | KORKEA | Julkaise-GitHub.ps1 (38, 205) | Oletusnäkyvyys **julkinen**, ja `git add -A` lisää koko kansion: kaupallinen `app.zip` ("kaikki oikeudet pidätetään") ja mahdolliset paikalliset tunnustiedostot päätyvät julkiseen repositorioon. Ei salaisuuksien tarkistusta. Asettaa globaalin `credential.helper`-arvon kysymättä. | Ohje E |
| 15 | KORKEA | Asenna-…Multa.ps1 (34, 49), README, oppaat | Hiljaisen asennuksen `-AdminPassword` ja `-ServerPass` komentorivillä → PowerShell-historia, prosessilista, lokit. Dokumenteissa esimerkkisalasana `Salasana1`. | Ohje F |
| 16 | KORKEA | Asenna-…Multa.ps1 (1115) | `Test-PageServer` kutsuu `Invoke-HkServerFixTrustedHosts -HostToAdd`, jota parametria ei ole → **velho kaatuu** ei-toimialuepalvelimella. Lisäksi TrustedHosts muutettaisiin jo validoinnissa, **ennen LUVAT-sivun suostumusta**. | Ohje G |
| 17 | KESKITASO | Asenna-…Multa.ps1 (229–237, 327–335) | Zip-purku ilman polkujen tarkistusta (zip slip), jos paketti on muokattu. | Ohje H (apufunktio korjatussa _yhteinen.ps1:ssä) |
| 18 | KESKITASO | _yhteinen.ps1 (149–156), Asenna (127–135) | ACL-rajaus käyttää `USERDOMAIN\USERNAME`-nimeä: epäonnistuu hiljaa mm. Entra ID -tileillä → avaintiedosto jää perittyjen oikeuksien varaan. | Korjattu (SID) |
| 19 | KESKITASO | _yhteinen.ps1 (115–123), sovellus | Salasanasääntö 8 merkkiä + iso kirjain + numero (`Salasana1` kelpaa). Istunto 30 päivää liukuvana (v2.1.0) talous- ja henkilötiedoille. | Työkalut 12+; Sovellus |
| 20 | KESKITASO | Tyokalut/Luo-Kayttaja.ps1 (36–43) | Kirjautumistarkistus on aina tosi: uudelleenohjaus kirjautumissivulle palauttaa HTTP 200, joten virheellinenkin kirjautuminen "onnistuu". | Korjattu |
| 21 | KESKITASO | Osa-Palvelin.ps1 (83–85) | Päivityksessä VAPID-avaimet luetaan vain `appsettings.json`:sta, vaikka ne ovat v2.4.1:stä alkaen `appsettings.Production.json`:ssa → uudet avaimet, push-tilaukset katkeavat. | Korjattu |
| 22 | KESKITASO | Asenna-…Multa.ps1 (530) | Rekisterin `DisplayVersion` on kovakoodattu `2.4.1`, vaikka versio on 2.7.3. | Ohje I |
| 23 | KESKITASO | Osa-Palvelin.ps1 (29–35) | TrustedHosts-korjausskripti jää `%TEMP%`-kansioon; WinRM HTTP (5985) + NTLM ei-toimialueella. | Korjattu; suositus WinRM HTTPS 5986 |
| 24 | KESKITASO | Asenna-…Multa.ps1 (182–199) | Palveluvahti tappaa prosessin (`Stop-Process -Force`), jos /health ei vastaa 60 s:ssa – esim. pitkä tietokantamigraatio keskeytyy. | Ohje J |
| 25 | KESKITASO | Asenna-…Multa.ps1 (88–96) | Porttitarkistus vain 127.0.0.1:ssä, vaikka lähiverkkokäytössä kuunnellaan 0.0.0.0:ssa. | Ohje J |
| 26 | MATALA | Myyntimateriaali/*.py | Kovakoodatut polut `C:\Users\PC\Desktop\…` ja henkilökohtainen Gmail-osoite. | Suositus |
| 27 | MATALA | Useat | Merkistöt: osa tiedostoista ilman ääkkösiä, osa UTF-8 BOM; dokumenteissa kirjoitusvirheitä ("laitelaitekoodilla", "Tama"); viestit "90 sekuntia" eivät vastaa todellisia odotusaikoja. | Suositus |
| 28 | MATALA | Koko paketti | Ei automaattisia testejä; `-SelfTest` tarkistaa vain syntaksin ja tiedostojen olemassaolon. Skriptejä ei ole allekirjoitettu (ExecutionPolicy Bypass kaikkialla). | Suositus: Pester-testit, Authenticode-allekirjoitus |

### Sovellukseen (C#) kohdistuvat suositukset, joita listauksesta ei voitu tarkistaa

- Varmista, että sovellus **poistaa `first-admin.json`:n** heti tilin luonnin jälkeen ja ettei salasana päädy lokiin.
- Lyhennä istunto (esim. 8–12 h) ja lisää tyhjäkäyntiaikakatkaisu; harkitse kaksivaiheista tunnistusta johdolle.
- HTTPS myös lähiverkossa (Kestrel-varmenne tai käänteisvälitys) ja `Secure`-evästeet.
- Kirjautumisen nopeusrajoitus myös IP-kohtaisesti (nyt tilikohtainen lukitus 5 → 15 min).
- Data Protection -avainten sijainti ja suojaus (AppData) sekä SQLite-kannan salaus tai BitLocker-vaatimus.
- SignalR-hubin autentikointi ja ryhmäkohtaiset oikeudet; kuittausliitteiden tiedostotyyppi- ja kokorajat.
- Laskutus: katkeamaton numerosarja, vahvistetun laskun muuttumattomuus, hyvityslaskut ja kirjausketju
  (nämä on toteutettu Huoltokello-Talous-moduulissa, jota voi käyttää mallina).

## Korjausohjeet tiedostoihin, joita ei toimitettu kokonaisina

**A – Poista-Asennus-GUI.ps1, `Remove-HkData`:** keskeytä poisto, jos varmuuskopio epäonnistuu:

```powershell
if (-not $DeleteData) {
    & $Status 'Varmuuskopioidaan data tyopoydalle...'
    $dest = Join-Path ([Environment]::GetFolderPath('Desktop')) ("Huoltokello-data-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".zip")
    try { New-HkZipFromFolder -Folder $appData -ZipPath $dest | Out-Null; $script:BackupPath = $dest }
    catch { & $Status ("Varmuuskopio epaonnistui - mitaan ei poistettu: " + $_.Exception.Message); return $false }
}
```
ja skriptin alkuun `$dir = Assert-HkSafeInstallDir (Get-HkInstallDir)` (korjatusta `_yhteinen.ps1`:stä).
Kun käyttäjä valitsee "Poista data lopullisesti", pyydä kirjoittamaan `POISTA`.

**B – Asenna-Huoltokello-Multa.ps1, first-admin.json (r. 262–263 ja 387–388):** kirjoita ensin tyhjä tiedosto,
rajaa ACL (`Protect-HkSecretFile`, SID-versio), vasta sitten sisältö; poista tiedosto vaiheessa 9, kun
kirjautumissivu vastaa. Azure-asennuksessa älä vie tiedostoa pakettiin: anna ensimmäinen johto-tili
sovellusasetuksina (`FirstAdmin__Email` jne.) ja poista ne `az webapp config appsettings delete` -komennolla
ensimmäisen käynnistyksen jälkeen (vaatii sovellukseen asetuksen lukemisen).

**C – HTTPS lähiverkossa:** joko Kestrel-varmenne (`--urls https://0.0.0.0:8443` + `Kestrel__Certificates__Default__Path`)
tai käänteisvälitys (Caddy/IIS ARR) omalla varmenteella. Palomuurisääntö (korjattu):
`netsh advfirewall firewall add rule name=Huoltokello dir=in action=allow protocol=TCP localport=<portti> profile=private,domain remoteip=localsubnet`.

**D – Osa-Azure.ps1:**
```powershell
# (r. 103–106) MSI:n allekirjoitus ennen asennusta
$sig = Get-AuthenticodeSignature -LiteralPath $msi
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    Remove-Item $msi -Force; throw 'Azure CLI -paketin allekirjoitus ei kelpaa - asennus keskeytetty.' }
# (r. 272–276) asetukset tiedostosta, ei komentorivilta
$tmpJson = Join-Path $env:TEMP ("hkaz-" + [guid]::NewGuid().ToString('N') + ".json")
@{ 'ASPNETCORE_ENVIRONMENT'='Production'; 'SeedDemoData'='False'; 'Vapid__Subject'='mailto:info@huoltokello.fi'
   'Vapid__PublicKey'=$keys.PublicKey; 'Vapid__PrivateKey'=$keys.PrivateKey } | ConvertTo-Json | Set-Content $tmpJson -Encoding UTF8
try { $r = Invoke-HkAz -Arguments @('webapp','config','appsettings','set','-g',$rg,'-n',$appName,'--settings',"@$tmpJson") }
finally { Remove-Item $tmpJson -Force -ErrorAction SilentlyContinue }
# (r. 325–330) perustunnistautuminen pois heti viennin jälkeen
try { <Kudu-vienti> } finally {
    $null = Invoke-HkAz -Arguments @('resource','update','-g',$ResourceGroup,'--name','scm','--namespace','Microsoft.Web',
        '--resource-type','basicPublishingCredentialsPolicies','--parent',"sites/$AppName",'--set','properties.allow=false') }
```
Lisäksi `az webapp config set --min-tls-version 1.2 --ftps-state Disabled`.

**E – Julkaise-GitHub.ps1:** oletus `[string]$Nakyvyys = 'yksityinen'`; ennen `git add -A` tarkista, ettei
`app.zip`-pakettia viedä julkiseen repositorioon (`if ($Nakyvyys -eq 'julkinen') { git rm --cached app.zip }` ja
`.gitignore`en `app.zip`, `*.db`, `AppData/`, `appsettings.Production.json`, `*tunnukset*.txt`); aja
`git diff --cached --name-only | Select-String -Pattern 'tunnukset|secret|\.db$|Production'` ja keskeytä osumista.
Poista `git config --global credential.helper manager` – tee asetus vain kysymällä.

**F – Hiljainen asennus ilman salasanaa komentorivillä:** lisää parametrit `-AdminPasswordFile` (luetaan ja
tiedosto poistetaan) ja ympäristömuuttuja `HK_ADMIN_PASSWORD`; jos kumpaakaan ei ole, kysy
`Read-Host -AsSecureString`. Vaihda dokumentaation esimerkit muotoon `-AdminPasswordFile .\salasana.txt`.

**G – Asenna-Huoltokello-Multa.ps1 r. 1114–1116:** poista koko `if ($c.chkSrvNotDomain.IsChecked) { … }` -lohko
validoinnista. Asennusvaihe (Osa-Palvelin.ps1 r. 74) tekee korjauksen oikeilla parametreilla, ja vasta LUVAT-sivun jälkeen.

**H – Zip slip -esto velhossa:** korvaa purkusilmukat (r. 229–237 ja 327–335) kutsulla
`Expand-HkZipSafe -ZipPath $AppZip -Destination $dir` (funktio korjatussa `_yhteinen.ps1`:ssä; dot-sourcaa se velhossa).

**I – r. 530:** lue versio `VERSIO.txt`:n ensimmäiseltä `vX.Y.Z`-riviltä (kuten Julkaise-GitHub.ps1 r. 279–283)
ja kirjoita se `DisplayVersion`-arvoon.

**J – Palveluvahti ja porttitarkistus:** vahdissa kolme peräkkäistä epäonnistunutta tarkistusta ennen uudelleenkäynnistystä
ja vähintään 5 min käynnistyksen jälkeen ennen ensimmäistä tarkistusta. `Test-PortFree`: tarkista
`[IPAddress]::Any`, kun `LanAccess` on valittu.

## Testaus

- Korjattuja PowerShell-skriptejä **ei ole ajettu Windowsissa** (katselmointiympäristössä ei ole PowerShelliä).
  Niiden sulkeet ja lohkot on tarkistettu, ja ne käyttävät vain PowerShell 5.1:n komentoja.
  Testaa ne ensin testikoneella: asennus → varmuuskopio → palautus → päivitys → poisto.
- Korjattu `asenna-sahkoposti.py` on käännetty (syntaksi) mutta ajamatta cPanelia vastaan.
- Huoltokello-Talous-moduulilla on 30 automaattista testiä (kaikki läpi), ks. README.md.
