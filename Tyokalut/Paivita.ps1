# Paivittaa Huoltokellon uudempaan versioon uudesta app.zip-paketista.
# Kayttajan data (AppData-kansio) sailytetaan ja varmuuskopioidaan ensin.
# Kaytto: Tyokalut\Paivita.ps1 [-ZipPath "C:\polku\app.zip"]
param([string]$ZipPath)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_yhteinen.ps1"

$dir = Get-HkInstallDir
$port = Get-HkPort

$zip = $ZipPath
if (-not $zip) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Valitse uusi app.zip-paivityspaketti'
    $dlg.Filter = 'ZIP-paketit (*.zip)|*.zip'
    if ($dlg.ShowDialog() -eq 'OK') { $zip = $dlg.FileName }
}
if (-not $zip -or -not (Test-Path $zip)) { throw "app.zip ei valittu tai ei loytynyt." }

Write-Host "Suljetaan Huoltokello..."
Stop-HkApp | Out-Null
Start-Sleep -Seconds 1

# v2.4.1: talteen mahdollinen aiempi VAPID-yksityisavain ENNEN purkua.
# Uusi appsettings.json ei enää sisällä yksityisavainta; se sijoitetaan
# appsettings.Production.json -tiedostoon, jota päivityspaketti ei koskaan ylikirjoita.
$prodPath = Join-Path $dir 'appsettings.Production.json'
$settingsPath = Join-Path $dir 'appsettings.json'
$migratedVapid = $null
if ((Test-Path $settingsPath) -and (-not (Test-Path $prodPath))) {
    try {
        $j0 = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($j0.Vapid -and $j0.Vapid.PrivateKey) {
            $migratedVapid = @{ Subject = [string]$j0.Vapid.Subject; PublicKey = [string]$j0.Vapid.PublicKey; PrivateKey = [string]$j0.Vapid.PrivateKey }
        }
    } catch { }
}

# v2.5.0: talteen aiemmin tallennetut SMTP-lahetusasetukset — paivitys ei saa nollata niita
$smtpKeep = $null
if (Test-Path $settingsPath) {
    try {
        $jOld = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($jOld.Smtp -and $jOld.Smtp.Host) { $smtpKeep = $jOld.Smtp }
    } catch { }
}

# Pikavarmuus ennen paivitysta
$appData = Join-Path $dir 'AppData'
if (Test-Path $appData) {
    $backupDir = Join-Path $env:USERPROFILE 'Huoltokello-Varmuuskopiot'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $pre = Join-Path $backupDir ("ennen-paivitysta-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".zip")
    Compress-Archive -Path $appData -DestinationPath $pre -Force
    Write-Host "Data varmuuskopioitu: $pre"
}

Write-Host "Puretaan paivitys: $zip"
Expand-Archive -Path $zip -DestinationPath $dir -Force

# Varmista etta asennus pysyy tyhjana (ei demodataa) eika yksityisavainta jaada appsettings.jsoniin
if (Test-Path $settingsPath) {
    $j = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $j.SeedDemoData = $false
    if ($j.Vapid -and $j.Vapid.PSObject.Properties['PrivateKey']) {
        $j.Vapid.PSObject.Properties.Remove('PrivateKey')
    }
    # v2.5.0: SMTP-asetukset palautetaan, jos niita oli tallennettu aiemmin
    if ($smtpKeep) { $j | Add-Member -NotePropertyName Smtp -NotePropertyValue $smtpKeep -Force }
    $j | ConvertTo-Json -Depth 6 | Set-Content $settingsPath -Encoding UTF8
}

# VAPID-yksityisavain suojattuun tiedostoon: siirretään aiempi pari tai luodaan uusi
if (-not (Test-Path $prodPath)) {
    $vapidSubject = 'mailto:info@huoltokello.fi'
    if ($j -and $j.Vapid -and $j.Vapid.Subject) { $vapidSubject = [string]$j.Vapid.Subject }
    if ($migratedVapid) {
        $vapidPub = $migratedVapid.PublicKey; $vapidPriv = $migratedVapid.PrivateKey
        $src = 'aiempi avainpari siirrettiin (push-tilaukset säilyvät)'
    } else {
        try {
            $kp = New-HkVapidKeys
            $vapidPub = $kp.PublicKey; $vapidPriv = $kp.PrivateKey
            $src = 'luotiin uusi asennuskohtainen avainpari'
        } catch {
            $vapidPub = ''; $vapidPriv = ''
            $src = 'avainluonti epaonnistui: ' + $_.Exception.Message
        }
    }
    @{ Vapid = @{ Subject = $vapidSubject; PublicKey = $vapidPub; PrivateKey = $vapidPriv } } |
        ConvertTo-Json -Depth 5 | Set-Content $prodPath -Encoding UTF8
    Protect-HkSecretFile -Path $prodPath | Out-Null
    Write-Host ("VAPID-avaimet: " + $src + " -> appsettings.Production.json")
}

Write-Host "Kaynnistetaan Huoltokello..."
Start-HkApp -NoBrowser
if (Wait-HkHealth -Port $port -Seconds 90) {
    Write-Host "Paivitys valmis - Huoltokello kaynnissa: http://127.0.0.1:$port" -ForegroundColor Green
} else {
    Write-Warning "Sovellus ei vastannut. Tarkista: $(Join-Path $appData 'app-err.log')"
}