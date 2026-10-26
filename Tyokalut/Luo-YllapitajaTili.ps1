# Ohjattu ensimmaisen yllapitajatilin luonti (tai uuden Johto-tilin lisays,
# jos sovellukseen ei paase kirjautumaan). Kirjoittaa AppData\first-admin.json -
# tiedoston, jonka sovellus lukee seuraavassa kaynnistyksessa ja luo tilin.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_yhteinen.ps1"

$dir = Get-HkInstallDir
$port = Get-HkPort
$exe = Join-Path $dir 'KiinteistoHuolto.Web.exe'

if (-not (Test-Path $exe)) { throw "Huoltokelloa ei ole asennettu kansioon $dir" }

Write-Host ""
Write-Host "=== HUOLTOKELLO - Ohjattu yllapitajatilin luonti ===" -ForegroundColor Cyan
Write-Host "Sovellus luo tilin seuraavassa kaynnistyksessa (Johto-rooli)."
Write-Host "Huom: samalla sahkopostilla olevaa tili EI muuteta - salasanan voi vaihtaa"
Write-Host "sovelluksessa (Hallinta > Kayttajat > Muokkaa) tai luoda tahan uusi tunnus."
Write-Host ""

# Sähköposti
do {
    $email = (Read-Host "Sahkoposti (kirjautumistunnus)").Trim()
    if ($email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Write-Host "  Anna kelvollinen sahkopostiosoite." -ForegroundColor Yellow; $email = '' }
} while (-not $email)

# Nimi
do { $name = (Read-Host "Koko nimi (esim. Maija Meikalainen)").Trim() } while (-not $name)

# Nimike
$title = (Read-Host "Tehtavanimike (valinnainen, Enter = 'Vastaava')").Trim()
if (-not $title) { $title = 'Vastaava' }

# Salasana x2
while ($true) {
    $pw1 = ConvertTo-PlainText (Read-Host "Salasana" -AsSecureString)
    $err = Test-HkPassword $pw1
    if ($err) { Write-Host "  $err" -ForegroundColor Yellow; continue }
    $pw2 = ConvertTo-PlainText (Read-Host "Salasana uudelleen" -AsSecureString)
    if ($pw1 -ne $pw2) { Write-Host "  Salasanat eivat tasmalle - yrita uudelleen." -ForegroundColor Yellow; continue }
    break
}

# Kirjoita first-admin.json
$appData = Join-Path $dir 'AppData'
New-Item -ItemType Directory -Force -Path $appData | Out-Null
$jsonPath = Join-Path $appData 'first-admin.json'
@{
    Email    = $email
    FullName = $name
    Title    = $title
    Password = $pw1
} | ConvertTo-Json | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host ""
Write-Host "Tilin tiedot kirjoitettu. Kaynnistetaan Huoltokello..." -ForegroundColor Cyan
$wasRunning = Test-HkHealth -Port $port
if ($wasRunning) { Stop-HkApp | Out-Null }
Start-HkApp -NoBrowser
if (Wait-HkHealth -Port $port -Seconds 90) {
    Write-Host ""
    Write-Host "VALMIS! Kirjaudu osoitteessa http://127.0.0.1:$port" -ForegroundColor Green
    Write-Host "  Tunnus: $email"
    Write-Host "  Rooli:  Johto (voi luoda kayttajia, asiakkaita, sopimuksia ja tehtavia)"
    Write-Host ""
    $open = Read-Host "Avataanko selain kirjautumissivulle? (k/o)"
    if ($open -match '^[kK]') { Start-Process "http://127.0.0.1:$port/Account/Login" }
} else {
    Write-Warning "Sovellus ei kayntynyt. Tarkista: $(Join-Path $appData 'app-err.log')"
    Write-Host "Tilin luonti yritetaan uudelleen sovelluksen seuraavassa kaynnistyksessa."
}