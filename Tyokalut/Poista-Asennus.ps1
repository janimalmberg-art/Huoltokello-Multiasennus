# Poistaa Huoltokellon asennuksen: prosessi, ajastus, pikakuvakkeet,
# Windowsin Sovellukset-listauksesta, (palomuurisääntö) ja asennuskansion.
# Data voidaan sailyttaa varmuuskopiona tyopoydalle.
param(
    [switch]$Silent,
    [string]$InstallDir
)
# Osoitettu asennuskansio voittaa: pakettikansiosta ajettuna taman
# skriptin sijainti ei ole asennuskansio.
if ($InstallDir) { $script:HkInstallDirOverride = $InstallDir.TrimEnd('\') }
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\_yhteinen.ps1"

$dir = Get-HkInstallDir
$port = Get-HkPort

Write-Host "=== HUOLTOKELLO - Asennuksen poisto ===" -ForegroundColor Yellow

# 1) Sovellus pois
Stop-HkApp | Out-Null

# 2) Automaattinen kaynnistys pois
schtasks /Delete /TN "Huoltokello" /F | Out-Null

# 3) Pikakuvakkeet
$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
foreach ($lnk in @(
    (Join-Path $desktop 'Huoltokello.lnk'),
    (Join-Path $desktop 'Huoltokello-Ohjeet.lnk'),
    (Join-Path $startMenu 'Huoltokello.lnk'),
    (Join-Path $startMenu 'Huoltokello-Ohjeet.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Startup')) 'Huoltokello.lnk')
)) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }

# 4) Windowsin Sovellukset-listaus (HKCU)
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Huoltokello' -Recurse -Force -ErrorAction SilentlyContinue

# 5) Palomuurisääntö (jos lisatty - vaatii yllapito-oikeudet)
if ($Silent) {
    # Hiljainen ajo: ei UAC-ikkunaa (toimii jos korotettu, muuten saanto jaanyt)
    $null = Start-Process netsh -ArgumentList 'advfirewall firewall delete rule name=Huoltokello' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
} else {
    try {
        Start-Process netsh -ArgumentList 'advfirewall firewall delete rule name=Huoltokello' -Verb RunAs -Wait
    } catch { Write-Host "Palomuurisääntöä ei poistettu (yllapito-oikeuksia ei annettu). Poista tarvittaessa manuaalisesti." }
}

# 6) Data
$appData = Join-Path $dir 'AppData'
$keepData = $true
if (-not $Silent) {
    $ans = Read-Host "Sailytetaanko tietokanta ja liitteet varmuuskopiona tyopoydalle? (k/o, Enter = k)"
    if ($ans -match '^[oO]') { $keepData = $false }
}
if ($keepData -and (Test-Path $appData)) {
    $dest = Join-Path $desktop ("Huoltokello-data-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".zip")
    try {
        Compress-Archive -Path $appData -DestinationPath $dest -Force
        Write-Host "Data varmuuskopioitu: $dest"
    } catch { Write-Host "Varmuuskopiointi epaonnistui: $_" }
}

# 7) Asennuskansio
Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $dir) { Write-Warning "Kansio ei tyhjennyt kokonaan (jokin tiedosto kaytossa): $dir" }
else { Write-Host "Asennuskansio poistettu: $dir" }

Write-Host ""
Write-Host "Poisto valmis." -ForegroundColor Green
if (-not $Silent) { Read-Host "Sulje painamalla Enter" | Out-Null }