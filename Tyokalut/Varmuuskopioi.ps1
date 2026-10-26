# Tekee varmuuskopion AppData-kansiosta (tietokanta + avaimet + liitteet)
# kansioon %USERPROFILE%\Huoltokello-Varmuuskopiot ja pitaa 30 uusinta.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_yhteinen.ps1"

$dir = Get-HkInstallDir
$port = Get-HkPort
$appData = Join-Path $dir 'AppData'

if (-not (Test-Path $appData)) { throw "AppData-kansiota ei loytynyt: $appData (asennettu ohjelma ei viela kaynnistynyt?)" }

$wasRunning = Test-HkHealth -Port $port
if ($wasRunning) {
    Write-Host "Suljetaan Huoltokello varmuuskopion ajaksi..."
    Stop-HkApp | Out-Null
    Start-Sleep -Seconds 1
}

try {
    $destDir = Join-Path $env:USERPROFILE 'Huoltokello-Varmuuskopiot'
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $destDir "huoltokello-varmuuskopio-$stamp.zip"
    Compress-Archive -Path $appData -DestinationPath $dest -Force

    # Siivous: sailyta 30 uusinta varmuuskopiota
    Get-ChildItem $destDir -Filter 'huoltokello-varmuuskopio-*.zip' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 30 |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Host "Varmuuskopio valmis: $dest"
    Write-Host ("Koko: {0:N1} Mt" -f ((Get-Item $dest).Length / 1MB))
}
finally {
    if ($wasRunning) {
        Write-Host "Kaynnistetaan Huoltokello uudelleen..."
        Start-HkApp -NoBrowser
        if (Wait-HkHealth -Port $port -Seconds 90) { Write-Host "Huoltokello taas kaynnissa." }
        else { Write-Warning "Huoltokello ei vastannut - kaynnista: Tyokalut\Kaynnista.ps1" }
    }
}