# Kaynnistaa Huoltokellon (ja avaa selaimen, ellei -NoBrowser annettu).
param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_yhteinen.ps1"

$port = Get-HkPort
$base = "http://127.0.0.1:$port"

if (Test-HkHealth -Port $port) {
    Write-Host "Huoltokello on jo kaynnissa: $base"
    if (-not $NoBrowser) { Start-Process $base }
    exit 0
}

Write-Host "Kaynnistetaan Huoltokello..."
Start-HkApp -NoBrowser
if (Wait-HkHealth -Port $port -Seconds 90) {
    Write-Host "Huoltokello kaynnissa: $base"
    if (-not $NoBrowser) { Start-Process $base }
} else {
    Write-Warning "Sovellus ei vastannut 90 sekunnin sisalla. Tarkista loki:" -ErrorAction SilentlyContinue
    Write-Host "  $(Join-Path (Get-HkInstallDir) 'AppData\app-err.log')"
    exit 1
}