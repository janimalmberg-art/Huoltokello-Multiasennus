# Lopettaa Huoltokellon taustalla pyorivan prosessin.
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\_yhteinen.ps1"

$stopped = Stop-HkApp
if ($stopped) { Write-Host "Huoltokello lopetettu." }
else { Write-Host "Huoltokello ei ollut kaynnissa." }