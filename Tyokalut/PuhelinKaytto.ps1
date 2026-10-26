# Ottaa Huoltokellon kayttoon puhelimista/lahiverkosta:
# 1) vaihtaa kuunteluosoitteeksi 0.0.0.0 (kaikki verkkokortit)
# 2) lisaa Windows-palomuurisäännön portille (vaatii yllapito-oikeudet)
# 3) kaynnistaa sovelluksen uudelleen ja nayttaa laitteiden osoitteet.
# -Poista palauttaa vain paikallisen kayton (127.0.0.1) ja poistaa palomuurisaannon.
param([switch]$Poista)
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\_yhteinen.ps1"

$dir = Get-HkInstallDir
$port = Get-HkPort
$launcher = Join-Path $dir 'Huoltokello.ps1'

if (-not (Test-Path $launcher)) { throw "Kaynnistinta ei loytynyt: $launcher" }

$wasRunning = Test-HkHealth -Port $port
if ($wasRunning) { Write-Host "Suljetaan Huoltokello..."; Stop-HkApp | Out-Null }

$newBind = if ($Poista) { '127.0.0.1' } else { '0.0.0.0' }
$text = Get-Content $launcher -Raw
$text = [regex]::Replace($text, "\`$Bind\s*=\s*'[^']*'", "`$Bind = '$newBind'")
Set-Content -Path $launcher -Value $text -Encoding UTF8

if ($Poista) {
    Write-Host "Poistetaan palomuurisääntö (vaatii yllapito-oikeudet)..."
    try {
        Start-Process netsh -ArgumentList 'advfirewall firewall delete rule name=Huoltokello' -Verb RunAs -Wait
    } catch { Write-Host "  Poikkeus peruttiin - saanto jaannyt paikalleen. Poista se yllapitajana:" -ForegroundColor Yellow }
    Write-Host "  netsh advfirewall firewall delete rule name=Huoltokello"
} else {
    Write-Host "Lisataan Windows-palomuurisääntö TCP $port (vaatii yllapito-oikeudet, UAC-ikkuna avautuu)..."
    try {
        Start-Process netsh -ArgumentList ('advfirewall firewall add rule name="Huoltokello" dir=in action=allow protocol=TCP localport=' + $port + ' profile=any') -Verb RunAs -Wait
        Write-Host "  Palomuurisääntö lisatty." -ForegroundColor Green
    } catch {
        Write-Host "  Palomuurin kayttäjän oikeuksia ei annettu (UAC peruttiin)." -ForegroundColor Yellow
        Write-Host "  Paikallinen kaytto toimii silti, mutta puhelimet eivat paase palvelimelle ennen"
        Write-Host "  saannon lisaamista. Aja skripti uudelleen tai aja yllapitajana:"
        Write-Host "  netsh advfirewall firewall add rule name=`"Huoltokello`" dir=in action=allow protocol=TCP localport=$port profile=any"
    }
}

Write-Host "Kaynnistetaan Huoltokello uudelleen..."
Start-HkApp -NoBrowser
if (-not (Wait-HkHealth -Port $port -Seconds 90)) { Write-Warning "Sovellus ei vastannut."; exit 1 }

Write-Host ""
if ($Poista) {
    Write-Host "VALMIS: Huoltokello vastaa nyt vain tasta koneesta (http://127.0.0.1:$port)." -ForegroundColor Green
} else {
    Write-Host "VALMIS! Huoltokello on nyt tavoitettavissa lahiverkosta." -ForegroundColor Green
    Write-Host ""
    Write-Host "Avaa puhelimella (sama WiFi-verkko) jokin seuraavista osoitteista:" -ForegroundColor Cyan
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -ExpandProperty IPAddress -Unique
    foreach ($ip in $ips) { Write-Host ("  http://{0}:{1}" -f $ip, $port) -ForegroundColor White }
    Write-Host ""
    Write-Host "Vinkit puhelimeen asentamiseen (PWA):" 
    Write-Host "  Android/Chrome : avaa osoite > valikko (3 pistetta) > 'Lisaa sovellus aloitusnaytolle'"
    Write-Host "  iPhone/Safari  : avaa osoite > Jaa > 'Lisaa Koti-valikkoon'"
    Write-Host "  Tumma tila: sovelluksen ylavalikosta (kk-ikoni)."
    Write-Host ""
    Write-Host "Kumoa myohemmin: Tyokalut\PuhelinKaytto.ps1 -Poista"
}