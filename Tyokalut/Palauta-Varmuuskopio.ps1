# Palauttaa AppData-kansion valitusta varmuuskopiosta (zip).
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_yhteinen.ps1"

$dir = Get-HkInstallDir
$port = Get-HkPort
$appData = Join-Path $dir 'AppData'
$backupDir = Join-Path $env:USERPROFILE 'Huoltokello-Varmuuskopiot'

# Valitse varmuuskopio
$zip = $null
if ($args.Count -ge 1 -and (Test-Path $args[0])) { $zip = $args[0] }
elseif (Test-Path $backupDir) {
    $cands = Get-ChildItem $backupDir -Filter '*.zip' | Sort-Object LastWriteTime -Descending
    if ($cands.Count -eq 0) { throw "Varmuuskopioita ei loytynyt kansiosta: $backupDir" }
    Write-Host "Saatavilla olevat varmuuskopiot:"
    for ($i = 0; $i -lt $cands.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2:N1} Mt, {3})" -f ($i + 1), $cands[$i].Name, ($cands[$i].Length / 1MB), $cands[$i].LastWriteTime)
    }
    $sel = Read-Host ("Valitse numero (1-" + $cands.Count + "), tai anna polku suoraan")
    $n = 0
    if ([int]::TryParse($sel, [ref]$n) -and $n -ge 1 -and $n -le $cands.Count) { $zip = $cands[$n - 1].FullName }
    elseif ($sel -and (Test-Path $sel)) { $zip = $sel }
}
if (-not $zip -or -not (Test-Path $zip)) { throw "Varmuuskopiota ei valittu." }

$confirm = Read-Host "KAikki sovelluksen nykyinen data korvataan varmuuskopiolla. Jatketaanko? (k/o)"
if ($confirm -notmatch '^[kK]') { Write-Host "Peruutettu."; exit 0 }

$wasRunning = Test-HkHealth -Port $port
if ($wasRunning) { Stop-HkApp | Out-Null; Start-Sleep -Seconds 1 }

try {
    # Varmuuskopioi nykyinen tilanne ennen palautusta (turvaverkko)
    if (Test-Path $appData) {
        $pre = Join-Path $backupDir ("ennen-palautusta-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".zip")
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Compress-Archive -Path $appData -DestinationPath $pre -Force
        Write-Host "Nykyinen data varmuuskopioitu ensin: $pre"
    }

    Write-Host "Palautetaan: $zip"
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    Write-Host "Palautus valmis."
}
finally {
    if ($wasRunning) {
        Start-HkApp -NoBrowser
        if (Wait-HkHealth -Port $port -Seconds 90) { Write-Host "Huoltokello taas kaynnissa." }
        else { Write-Warning "Kaynnista manuaalisesti: Tyokalut\Kaynnista.ps1" }
    }
}