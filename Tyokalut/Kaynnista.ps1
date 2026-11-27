# Kaynnistaa Huoltokellon (ja avaa selaimen, ellei -NoBrowser annettu).
param([switch]$NoBrowser, [switch]$Lisenssi)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_yhteinen.ps1"

# LISENSSIHALLINTA: avaa lisenssidialogin (aktivointi / paivitys) milloin tahansa.
if ($Lisenssi) {
    . "$PSScriptRoot\_lisenssi.ps1"
    [void](Show-HkLisHallintaIkkuna)
    exit 0
}

$port = Get-HkPort
$base = "http://127.0.0.1:$port"

if (Test-HkHealth -Port $port) {
    Write-Host "Huoltokello on jo kaynnissa: $base"
    if (-not $NoBrowser) { Start-Process $base }
    exit 0
}

Write-Host "Kaynnistetaan Huoltokello..."

# KOKEILUVERSIO: tarkista 90 paivan kokeilujakso ennen kaynnistysta
# (Test-HkKokeiluGate tarkistaa ENSIN voimassa olevan lisenssin).
. "$PSScriptRoot\_lisenssi.ps1"
. "$PSScriptRoot\_kokeilu.ps1"
if (-not (Test-HkKokeiluGate -InstallDir (Get-HkInstallDir))) { exit 2 }

Start-HkApp -NoBrowser
if (Wait-HkHealth -Port $port -Seconds 90) {
    Write-Host "Huoltokello kaynnissa: $base"
    if (-not $NoBrowser) { Start-Process $base }
} else {
    Write-Warning "Sovellus ei vastannut 90 sekunnin sisalla. Tarkista loki:" -ErrorAction SilentlyContinue
    Write-Host "  $(Join-Path (Get-HkInstallDir) 'AppData\app-err.log')"
    exit 1
}