# ============================================================
# HUOLTOKELLO - Graafinen MULTIASENNUSVELHO (WPF / PowerShell 5.1)
#
# Ohjattu asennus KOLMELLA tavalla (kayttaja valitsee velhossa):
#   1) PAIKALLINEN       - ohjelma omalle koneelle (tyhja asennus)
#   2) MICROSOFT AZURE   - ohjelma Microsoftin pilveen Kayttajan
#                          omalla Microsoft/Azure-tililla (kirjautuminen
#                          laitteistokoodilla, App Service -sovellus)
#   3) YRITYKSEN OMA SERVERI - kaikilta palvelintiedot syotetaan kasin:
#                          osoite, Windows-tunnukset, polku, portti
#
# Velho selvittaa ETENEMIN kertoo joka vaiheessa mita tapahtuu ja kysyy
# LUVAN "skripti saa toimia kayttajan puolesta" -toimenpiteille ennen
# kuin yhtaan muutosta tehdaan.
#
# Kaytto:      Asenna.cmd  (tai: powershell -File Asenna-Huoltokello-Multa.ps1)
# Hiljainen:   powershell -File Asenna-Huoltokello-Multa.ps1 -Silent -Mode paikallinen
#              -InstallDir "C:\Huoltokello" -Port 8088
#              -AdminName "Maija Meikalainen" -AdminEmail "maija@firma.fi"
#              -AdminPassword "Salasana1" -HyvaksyLuvat
#              (Mode: paikallinen | azure | serveri; azure vaatii -AzName,
#               serveri vaatii -ServerHost -ServerUser -ServerPass)
# Itsetesti:   powershell -File Asenna-Huoltokello-Multa.ps1 -SelfTest
# ============================================================
param(
    [switch]$Silent,
    [ValidateSet('', 'paikallinen', 'azure', 'serveri')]
    [string]$Mode,
    [string]$InstallDir,
    [int]$Port = 8088,
    [string]$AdminName,
    [string]$AdminEmail,
    [string]$AdminTitle,
    [string]$AdminPassword,
    [switch]$AutoStart,
    [switch]$PhoneAccess,
    [switch]$LanAccess,
    [switch]$NoShortcuts,
    [switch]$NoBrowser,
    # Azure-ohitus (hiljainen asennus)
    [string]$AzName,
    [string]$AzRg,
    [string]$AzRegion,
    [string]$AzSku,
    [string]$AzSubscription,
    # Yrityksen oman serverin ohitus (hiljainen asennus)
    [string]$ServerHost,
    [string]$ServerUser,
    [string]$ServerPass,
    [string]$ServerPath,
    [int]$ServerPort = 8080,
    [switch]$ServerNotDomain,
    # Annapa skriptille lupa toimia puolestasi (vaaditaan hiljaisessa asennuksessa)
    [switch]$HyvaksyLuvat,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
$PackageDir = $PSScriptRoot
$AppZip = Join-Path $PackageDir 'app.zip'
$IconFile     = Join-Path $PackageDir 'assets\huoltokello.ico'
$OhjeIconFile = Join-Path $PackageDir 'assets\huoltokello-ohjeet.ico'
$AzureOsat    = Join-Path $PackageDir 'Osa-Azure.ps1'
$PalvelinOsat = Join-Path $PackageDir 'Osa-Palvelin.ps1'
$DefaultPort = 8088
# TLS 1.2 selkeasti kayttoon (Azureen yhdistettaessa PowerShell 5.1:ssa)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
if (-not (Test-Path $AzureOsat))    { throw "Osa-Azure.ps1 puuttuu paketista - asenna kokonaisuudessaan kansio Huoltokello-Multiasennus." }
if (-not (Test-Path $PalvelinOsat)) { throw "Osa-Palvelin.ps1 puuttuu paketista - asenna kokonaisuudessaan kansio Huoltokello-Multiasennus." }
. $AzureOsat
. $PalvelinOsat

# ---------- Apufunktiot ----------

function Test-Email {
    param([string]$Address)
    return ($Address -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

function Test-HkPasswordRule {
    param([string]$Password)
    if ([string]::IsNullOrWhiteSpace($Password)) { return 'Salasana vaaditaan.' }
    if ($Password.Length -lt 8) { return 'Salasanan on oltava vahintaan 8 merkkiä pitkä.' }
    if ($Password -notmatch '[A-ZÄÖÜ]') { return 'Salasanassa on oltava vahintaan yksi suuraakkonen.' }
    if ($Password -notmatch '\d') { return 'Salasanassa on oltava vahintaan yksi numero.' }
    return $null
}

function Test-PortFree {
    param([int]$PortNumber)
    try {
        $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, $PortNumber)
        $listener.Start()
        $listener.Stop()
        return $true
    } catch { return $false }
}

function ConvertTo-PlainText {
    param([System.Security.SecureString]$SecurePassword)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# ---------- VAPID-avainparin luonti (v2.4.1 tietoturva) ----------
# Web Push: jokaiselle asennukselle luodaan oma ES256/P-256-avainpari.
# Yksityisavain tallennetaan appsettings.Production.json-tiedostoon — EI
# appsettings.jsoniin, joka tulee app.zip-paketissa mukana jokaisessa
# päivityksessä (yksityisavain ei saa lähteä julkaisupaketista).
function New-HkVapidKeys {
    $curve = [System.Security.Cryptography.ECCurve]::CreateFromValue('1.2.840.10045.3.1.7') # P-256 (prime256v1)
    $ec = [System.Security.Cryptography.ECDsa]::Create($curve)
    if (-not $ec) { $ec = New-Object System.Security.Cryptography.ECDsaCng -ArgumentList $curve }
    try {
        $p = $ec.ExportParameters($true)
        if (-not $p.D -or $p.D.Length -eq 0) { throw 'Yksityista avainta ei saatu vietyä.' }
        $b64u = { param([byte[]]$b) [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
        # Julkinen VAPID-avain = pakkaamaton piste: 0x04 || X || Y (base64url)
        $pub = New-Object byte[] (1 + $p.Q.X.Length + $p.Q.Y.Length)
        $pub[0] = 4
        [Array]::Copy($p.Q.X, 0, $pub, 1, $p.Q.X.Length)
        [Array]::Copy($p.Q.Y, 0, $pub, 1 + $p.Q.X.Length, $p.Q.Y.Length)
        return @{ PublicKey = (& $b64u $pub); PrivateKey = (& $b64u $p.D) }
    } finally { $ec.Dispose() }
}

function Protect-HkSecretFile {
    param([string]$Path)
    # Salatiedoston ACL: vain nykyinen käyttäjä ja SYSTEM (poistetaan periytyvät oikeudet).
    try {
        $id = "$env:USERDOMAIN\$env:USERNAME"
        $null = & icacls $Path /inheritance:r /grant:r "$($id):F" /grant:r "SYSTEM:F"
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

# ---------- Yhteiset apur multiasennukselle ----------

function Test-HkUrlOk {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

# Pollaa palvelun /health-osoitetta; kertoo etenemisen OnStep-callbackilla.
function Wait-HkHealthUrl {
    param(
        [string]$Url,
        [int]$Seconds = 150,
        $OnStep,
        [string]$StepId = 'kaynnistys'
    )
    $tries = [Math]::Max(1, [int]($Seconds * 1000 / 750))
    for ($i = 0; $i -lt $tries; $i++) {
        if (Test-HkUrlOk -Url "$Url/health") { return $true }
        if ($OnStep) { & $OnStep $StepId 'info' ("odotetaan vastausta... {0}" -f [int]($i * 0.75)) }
        Start-Sleep -Milliseconds 750
    }
    return $false
}

# ---------- Ohjelmapaketin valmistelu (Azure-vienti / yritys-palvelin) ----------

# Palveluskaynnistimen (tehtava-ajastuksen watchdog) luonti paketin juureen.
function New-HkServiceWrapper {
    param([string]$StageDir, [int]$ServicePort)
    $svc = @'
# Huoltokello - palveluskaynnistin (luotu multiasennusvelhossa)
# Tarkkailee ohjelmaa ja kaynnistaa sen uudelleen tarvittaessa (tehtava-ajastus ONSTART).
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = SERVICEPORTTILA
$exe = Join-Path $dir 'KiinteistoHuolto.Web.exe'
$exeName = 'KiinteistoHuolto.Web'
function Test-LocalHk {
    try {
        $r = Invoke-WebRequest ("http://127.0.0.1:$port/health") -UseBasicParsing -TimeoutSec 3
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}
while ($true) {
    if (-not (Test-LocalHk)) {
        try {
            Get-Process -Name $exeName -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -and ($_.Path -like ($dir + '*')) } |
                Stop-Process -Force -ErrorAction SilentlyContinue
        } catch { }
        Start-Sleep -Seconds 2
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'AppData') | Out-Null
        $out = Join-Path $dir 'AppData\app-out.log'
        $err = Join-Path $dir 'AppData\app-err.log'
        try {
            Start-Process $exe -WorkingDirectory $dir -ArgumentList ("--urls=http://0.0.0.0:$port") -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
        } catch {
            try { Start-Process $exe -WorkingDirectory $dir -ArgumentList ("--urls=http://0.0.0.0:$port") -WindowStyle Hidden } catch { }
        }
    }
    Start-Sleep -Seconds 60
}
'@
    $svc = $svc.Replace('SERVICEPORTTILA', [string]$ServicePort)
    [IO.File]::WriteAllText((Join-Path $StageDir 'Huoltokello-Palvelu.ps1'), $svc, (New-Object Text.UTF8Encoding $true))
}
# Purkaa app.zipin tyokansioon, muokkaa asetukset tyhjaksi asennukseksi
# (SeedDemoData=false, VAPID-yksityisavain pois julkaisupaketista),
# lisaa ensimmaisen yllapitajatilin tiedoston ja pakkaa valmiin zipin.
function New-HkAppPackage {
    param(
        [string]$Mode,                      # 'azure' | 'palvelin'
        [string]$AdminName,
        [string]$AdminEmail,
        [string]$AdminTitle,
        [string]$AdminPassword,
        [switch]$IsUpdate,                  # olemassa oleva asennus: tietoja ei kosketa
        [hashtable]$VapidKeys,              # palvelin-asennus: avaimet pakettiin (ACL rajataan palvelimella)
        [int]$ServicePort = 8080,           # palveluskaynnistimen portti
        $OnStep
    )
    $tmpRoot = Join-Path $env:TEMP ("Huoltokello-Multa-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $stageDir = Join-Path $tmpRoot 'stage'
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    if ($OnStep) { & $OnStep 'pakkaus' 'start' '' }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($AppZip)
    try {
        $total = $zip.Entries.Count
        $done = 0
        foreach ($entry in $zip.Entries) {
            $target = Join-Path $stageDir $entry.FullName
            $targetDir = Split-Path -Parent $target
            if ($entry.FullName -match '[/\\]$') {
                if (-not (Test-Path $target)) { New-Item -ItemType Directory -Force -Path $target | Out-Null }
            } else {
                if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
            $done++
            if (($done % 40) -eq 0 -or $done -eq $total) {
                if ($OnStep) { & $OnStep 'pakkaus' 'info' ("{0}/{1}" -f $done, $total) }
            }
        }
    } finally { $zip.Dispose() }
    # Asetukset: tyhja asennus, yksityisavain ei jaa julkaisupakettiin
    $settingsPath = Join-Path $stageDir 'appsettings.json'
    $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $json.SeedDemoData = $false
    if ($json.Vapid -and $json.Vapid.PSObject.Properties['PrivateKey']) {
        $json.Vapid.PSObject.Properties.Remove('PrivateKey')
    }
    $json | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8
    # Palvelinversio: VAPID-yksityisavain appsettings.Production.json (ACL rajataan palvelimella)
    if ($Mode -ne 'azure' -and $VapidKeys) {
        $vapidSubject = 'mailto:info@huoltokello.fi'
        if ($json.Vapid -and $json.Vapid.Subject) { $vapidSubject = [string]$json.Vapid.Subject }
        @{ Vapid = @{ Subject = $vapidSubject; PublicKey = [string]$VapidKeys.PublicKey; PrivateKey = [string]$VapidKeys.PrivateKey } } |
            ConvertTo-Json -Depth 5 | Set-Content (Join-Path $stageDir 'appsettings.Production.json') -Encoding UTF8
    }
    # Ensimmäinen ylläpitäjätili (ohjelma luo tilin ensimmaisella kaynnistyksella)
    if (-not $IsUpdate) {
        New-Item -ItemType Directory -Force -Path (Join-Path $stageDir 'AppData') | Out-Null
        @{ Email = $AdminEmail; FullName = $AdminName; Title = $AdminTitle; Password = $AdminPassword } |
            ConvertTo-Json | Set-Content (Join-Path $stageDir 'AppData\first-admin.json') -Encoding UTF8
    }
    if ($Mode -eq 'palvelin') {
        New-HkServiceWrapper -StageDir $stageDir -ServicePort $ServicePort
    }
    $zipOut = Join-Path $env:TEMP ("Huoltokello-Multa-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".zip")
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $zipOut, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    if ($OnStep) { & $OnStep 'pakkaus' 'ok' ("{0} tiedostoa pakattu valmiiksi" -f $done) }
    return @{ Zip = $zipOut; Stage = $stageDir; Root = $tmpRoot; Files = [int]$done }
}

# ---------- Asennuslogiikka ----------
# Ottaa settings-hashtablen ja kertoo etenemisen OnStep-callbackilla:
#   & $OnStep 'vaihe-id' 'start'|'ok'|'fail'|'info' 'yksityiskohta'
# Heittaa poikkeuksen jos jokin vaihe epaonnistuu (GUI nayttaa virheen).
function Invoke-HkInstall {
    param([hashtable]$s, [scriptblock]$OnStep)

    $dir       = $s.InstallDir
    $port      = $s.Port
    $exe       = Join-Path $dir 'KiinteistoHuolto.Web.exe'
    $appData   = Join-Path $dir 'AppData'
    $launcher  = Join-Path $dir 'Huoltokello.ps1'
    $baseUrl   = "http://127.0.0.1:$port"

    # --- 1) Asennuskansio ---
    & $OnStep 'kansio' 'start' ''
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    # Kirjoitustesti
    $probe = Join-Path $dir '.asennustesti'
    try {
        Set-Content -Path $probe -Value 'ok' -Encoding ASCII
        Remove-Item $probe -Force
    } catch {
        & $OnStep 'kansio' 'fail' ("Kansioon ei voi kirjoittaa: " + $_.Exception.Message)
        throw "Kansioon ei voi kirjoittaa: $dir"
    }
    $isUpdate = (Test-Path (Join-Path $appData 'huoltokello.db'))
    # v2.4.1: talteen mahdollinen aiempi VAPID-yksityisavain ENNEN app.zip-purkua
    # (purku ylikirjoittaa appsettings.json - aiempi avain siirretään appsettings.Production.json,
    #  jolloin laitteille tehdyt push-tilaukset jäävät voimaan).
    $oldVapid = $null
    $prevSettings = Join-Path $dir 'appsettings.json'
    if (Test-Path $prevSettings) {
        try {
            $prevJson = Get-Content $prevSettings -Raw | ConvertFrom-Json
            if ($prevJson.Vapid -and $prevJson.Vapid.PrivateKey) {
                $oldVapid = @{ Subject = [string]$prevJson.Vapid.Subject; PublicKey = [string]$prevJson.Vapid.PublicKey; PrivateKey = [string]$prevJson.Vapid.PrivateKey }
            }
        } catch { }
    }
    & $OnStep 'kansio' 'ok' $dir

    # --- 2) Ohjelmatiedostot (app.zip) ---
    if (-not (Test-Path $AppZip)) {
        & $OnStep 'tiedostot' 'fail' "app.zip puuttuu paketista!"
        throw "app.zip puuttuu paketista: $AppZip"
    }
    & $OnStep 'tiedostot' 'start' ''
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($AppZip)
    try {
        $total = $zip.Entries.Count
        $done = 0
        foreach ($entry in $zip.Entries) {
            $target = Join-Path $dir $entry.FullName
            $targetDir = Split-Path -Parent $target
            if ($entry.FullName -match '[/\\]$') {
                if (-not (Test-Path $target)) { New-Item -ItemType Directory -Force -Path $target | Out-Null }
            } else {
                if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
            $done++
            if (($done % 20) -eq 0 -or $done -eq $total) {
                & $OnStep 'tiedostot' 'info' ("{0}/{1}" -f $done, $total)
            }
        }
    } finally { $zip.Dispose() }
    & $OnStep 'tiedostot' 'ok' ("{0} tiedostoa purettu" -f $total)

    # --- 3) Asetukset: tyhja asennus (ei demodataa) + VAPID-avaimet suojattuun tiedostoon ---
    & $OnStep 'asetukset' 'start' ''
    $settingsPath = Join-Path $dir 'appsettings.json'
    $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $json.SeedDemoData = $false
    # v2.4.1: VAPID-yksityisavain EI jää appsettings.jsoniin (se lähtisi päivityspaketissa)
    if ($json.Vapid -and $json.Vapid.PSObject.Properties['PrivateKey']) {
        $json.Vapid.PSObject.Properties.Remove('PrivateKey')
    }
    $json | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8

    # VAPID-avaimet: aiempi pari siirretään, muutoin luodaan uusi asennuskohtainen pari.
    # Tallennus: appsettings.Production.json (sama kansio, luetaan Production-ympäristössä) -
    # EI osa app.zip-pakettia, ei lähde päivityksissä, ACL rajattu nykyiseen käyttäjään.
    $vapidSubject = 'mailto:info@huoltokello.fi'
    if ($json.Vapid -and $json.Vapid.Subject) { $vapidSubject = [string]$json.Vapid.Subject }
    if ($oldVapid) {
        $vapidPub = $oldVapid.PublicKey; $vapidPriv = $oldVapid.PrivateKey
        $keySrc = 'aiempi avainpari siirretty (push-tilaukset säilyvät)'
    } else {
        try {
            $kp = New-HkVapidKeys
            $vapidPub = $kp.PublicKey; $vapidPriv = $kp.PrivateKey
            $keySrc = 'uusi asennuskohtainen avainpari luotu'
        } catch {
            $vapidPub = if ($json.Vapid -and $json.Vapid.PublicKey) { [string]$json.Vapid.PublicKey } else { '' }
            $vapidPriv = ''
            $keySrc = 'AVAINLUONTI EPAONNISTUI - push-ilmoitukset eivät toimi (' + $_.Exception.Message + ')'
        }
    }
    $prodPath = Join-Path $dir 'appsettings.Production.json'
    @{ Vapid = @{ Subject = $vapidSubject; PublicKey = $vapidPub; PrivateKey = $vapidPriv } } |
        ConvertTo-Json -Depth 5 | Set-Content $prodPath -Encoding UTF8
    $aclOk = Protect-HkSecretFile -Path $prodPath
    $aclTxt = if ($aclOk) { ' | ACL: vain nykyinen käyttäjä' } else { '' }
    & $OnStep 'asetukset' 'ok' ('SeedDemoData = false (tyhja asennus); VAPID-yksityisavain -> appsettings.Production.json (' + $keySrc + $aclTxt + ')')

    # --- 4) Yllapitajatili (vain jos tietokantaa ei vielä ole) ---
    if ($isUpdate) {
        & $OnStep 'tili' 'info' 'Olemassa oleva asennus havaittu - tietoja ei kosketa, tiliä ei luoda uudestaan.'
    } else {
        & $OnStep 'tili' 'start' ''
        New-Item -ItemType Directory -Force -Path $appData | Out-Null
        @{ Email = $s.AdminEmail; FullName = $s.AdminName; Title = $s.AdminTitle; Password = $s.AdminPassword } |
            ConvertTo-Json | Set-Content (Join-Path $appData 'first-admin.json') -Encoding UTF8
        & $OnStep 'tili' 'ok' ("Johto-tili luodaan ensimmaisella kaynnistyksella: " + $s.AdminEmail)
    }

    # --- 5) Kaynnistin, työkalut ja ohjeet ---
    & $OnStep 'tyokalut' 'start' ''
    $bindDefault = if ($s.LanAccess) { '0.0.0.0' } else { '127.0.0.1' }
    $launcherText = @"
# Huoltokello - kaynnistin (luotu asennusvelhossa)
param([switch]`$NoBrowser)
`$InstallDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$Port = $port
`$Bind = '$bindDefault'   # PuhelinKaytto.ps1 voi vaihtaa tarvittaessa 0.0.0.0
`$Exe = Join-Path `$InstallDir 'KiinteistoHuolto.Web.exe'
`$Url = "http://127.0.0.1:`$Port"

function Wait-Hk([int]`$sec) {
    for (`$i = 0; `$i -lt (`$sec * 1000 / 700); `$i++) {
        try { `$r = Invoke-WebRequest "`$Url/health" -UseBasicParsing -TimeoutSec 2; if (`$r.StatusCode -eq 200) { return `$true } } catch { }
        Start-Sleep -Milliseconds 700
    }
    return `$false
}

`$already = `$false
try { `$h = Invoke-WebRequest "`$Url/health" -UseBasicParsing -TimeoutSec 2; if (`$h.StatusCode -eq 200) { `$already = `$true } } catch { }

if (`$already) {
    if (-not `$NoBrowser) { Start-Process `$Url }
    exit 0
}

New-Item -ItemType Directory -Force -Path (Join-Path `$InstallDir 'AppData') | Out-Null
Start-Process `$Exe -WorkingDirectory `$InstallDir -ArgumentList "--urls=http://`${Bind}:`$Port" -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path `$InstallDir 'AppData\app-out.log') `
    -RedirectStandardError  (Join-Path `$InstallDir 'AppData\app-err.log')

if (Wait-Hk 90) {
    if (-not `$NoBrowser) { Start-Process `$Url }
} else {
    Write-Warning "Huoltokello ei vastannut 90 sekunnin sisalla."
    Write-Host "Tarkista loki: AppData\app-err.log"
    exit 1
}
"@
    [IO.File]::WriteAllText($launcher, $launcherText, (New-Object Text.UTF8Encoding $true))
    $cmdText = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"%~dp0Huoltokello.ps1`"`r`n"
    [IO.File]::WriteAllText((Join-Path $dir 'Huoltokello.cmd'), $cmdText, (New-Object Text.UTF8Encoding $false))

    Copy-Item (Join-Path $PackageDir 'Tyokalut') (Join-Path $dir 'Tyokalut') -Recurse -Force
    if (Test-Path (Join-Path $PackageDir 'Ohjeet')) {
        Copy-Item (Join-Path $PackageDir 'Ohjeet') (Join-Path $dir 'Ohjeet') -Recurse -Force
    }
    foreach ($doc in @('Asennusohjeet.txt', 'README.txt')) {
        $docPath = Join-Path $PackageDir $doc
        if (Test-Path $docPath) { Copy-Item $docPath (Join-Path $dir $doc) -Force }
    }
    if (Test-Path $IconFile) { Copy-Item $IconFile (Join-Path $dir 'huoltokello.ico') -Force }
    if (Test-Path $OhjeIconFile) { Copy-Item $OhjeIconFile (Join-Path $dir 'huoltokello-ohjeet.ico') -Force }
    & $OnStep 'tyokalut' 'ok' 'Kaynnistin, Tyokalut ja Ohjeet kopioitu'

    # Asennus-yhteenveto
    $summary = @"
HUOLTOKELLO - ASENNUKSEN YHTEENVETO
===================================
Asennettu:    $(Get-Date -Format 'dd.MM.yyyy klo HH:mm')
Sijainti:     $dir
Osoite:       $baseUrl  (paikallinen)
Portti:       $port
Yllapitaja:   $($s.AdminName) <$($s.AdminEmail)>  (Johto-rooli)
Puhelinkaytto: $(if ($s.LanAccess) { 'kylla (lahiverkko + palomuurisaanto)' } else { 'ei (vain tietokoneelta)' })

KAYTTOONOTTO (yksityiskohtainen opas: Ohjeet\Kayttoonotto-Opas.html):
 1. Avaa $baseUrl ja kirjaudu yllapitajatililla
 2. Hallinta > Tehtavatyypit: lisaa omat tyypit (tarvitaan tehtaville)
 3. Hallinta > Ryhmat: luo tyoryhmat
 4. Hallinta > Kayttajat: luo muut kayttajat (tai Tyokalut\Luo-Kayttaja.ps1)
 5. Asiakkaat > Uusi asiakas
 6. Sopimukset > Uusi sopimus (hinnat, ALV, laskutusvalit)
 7. Kohteet > Uusi kohde (+ QR-koodi tulostettavaksi)
 8. Kalenteri/Vuosikello > lisaa tehtavat (tai Toistuvat tehtavat -pohjat)

HUOM: salasanaa ei tallenneta tahan tiedostoon. Jos salasana unohtuu:
aja Tyokalut\Luo-YllapitajaTili.ps1 ja luo UUSI johtotili toisella sahkopostilla.
"@
    $lanUrls = @()
    if ($s.LanAccess) {
        try {
            $lanUrls = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                Select-Object -ExpandProperty IPAddress -Unique)
        } catch { }
    }
    if ($s.LanAccess -and $lanUrls.Count -gt 0) {
        $summary += "`nVerkossa:     " + (($lanUrls | ForEach-Object { "http://${_}:$port" }) -join '  ')
    }
    [IO.File]::WriteAllText((Join-Path $dir 'Asennus-yhteenveto.txt'), $summary, (New-Object Text.UTF8Encoding $true))

    # --- 6) Pikakuvakkeet ---
    if (-not $s.NoShortcuts) {
        & $OnStep 'pikakuvakkeet' 'start' ''
        $ico = Join-Path $dir 'huoltokello.ico'
        $icoOhje = Join-Path $dir 'huoltokello-ohjeet.ico'
        $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $psArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $launcher
        $ohjeFile = Join-Path $dir 'Ohjeet\Kayttoonotto-Opas.html'
        $targets = @()
        if ($s.DesktopShortcut) {
            $desktop = [Environment]::GetFolderPath('Desktop')
            $targets += ,@((Join-Path $desktop 'Huoltokello.lnk'), 'ps', $psExe, $psArgs, $ico)
            if (Test-Path $ohjeFile) { $targets += ,@((Join-Path $desktop 'Huoltokello-Ohjeet.lnk'), 'file', $ohjeFile, '', $icoOhje) }
        }
        if ($s.StartMenuShortcut) {
            $sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
            $targets += ,@((Join-Path $sm 'Huoltokello.lnk'), 'ps', $psExe, $psArgs, $ico)
            if (Test-Path $ohjeFile) { $targets += ,@((Join-Path $sm 'Huoltokello-Ohjeet.lnk'), 'file', $ohjeFile, '', $icoOhje) }
        }
        foreach ($t in $targets) {
            $wsh = New-Object -ComObject WScript.Shell
            $sc = $wsh.CreateShortcut($t[0])
            $sc.TargetPath = $t[2]
            if ($t[3]) { $sc.Arguments = $t[3] }
            if ($t[1] -eq 'ps') { $sc.WorkingDirectory = $dir }
            if ($t[4] -and (Test-Path $t[4])) { $sc.IconLocation = $t[4] }
            $sc.Description = 'Huoltokello - kiinteistonhuollon tyonhallinta'
            $sc.Save()
        }
        & $OnStep 'pikakuvakkeet' 'ok' ("{0} pikakuvaketta luotu" -f $targets.Count)
    } else {
        & $OnStep 'pikakuvakkeet' 'info' 'Ohitettu (ei pyydetty)'
    }

    # --- 6b) Windowsin Sovellukset-listaus (poisto kohdasta Asetukset > Sovellukset) ---
    & $OnStep 'rekisteri' 'start' ''
    $regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Huoltokello'
    try {
        New-Item -Path $regKey -Force | Out-Null
        $estKb = 0
        try {
            Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $estKb += [int]($_.Length / 1KB) }
        } catch { }
        Set-ItemProperty $regKey -Name 'DisplayName'     -Value 'Huoltokello'
        Set-ItemProperty $regKey -Name 'DisplayVersion'  -Value '2.4.1'
        Set-ItemProperty $regKey -Name 'Publisher'       -Value 'Huoltokello'
        Set-ItemProperty $regKey -Name 'InstallLocation' -Value $dir
        if (Test-Path (Join-Path $dir 'huoltokello.ico')) { Set-ItemProperty $regKey -Name 'DisplayIcon' -Value (Join-Path $dir 'huoltokello.ico') }
        Set-ItemProperty $regKey -Name 'UninstallString' -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $dir 'Tyokalut\Poista-Asennus-GUI.ps1') + '"')
        Set-ItemProperty $regKey -Name 'NoModify' -Value 1 -Type DWord
        Set-ItemProperty $regKey -Name 'NoRepair' -Value 1 -Type DWord
        if ($estKb -gt 0) { Set-ItemProperty $regKey -Name 'EstimatedSize' -Value $estKb -Type DWord }
        & $OnStep 'rekisteri' 'ok' 'Näkyy Windowsin Sovellukset-listassa'
    } catch {
        & $OnStep 'rekisteri' 'info' ('Rekisterimerkintää ei voitu luoda: ' + $_.Exception.Message)
    }

    # --- 7) Automaattinen kaynnistys kirjautumisen yhteydessa ---
    if ($s.AutoStart) {
        & $OnStep 'autostart' 'start' ''
        $tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -NoBrowser' -f $launcher
        $null = schtasks /Create /F /TN 'Huoltokello' /SC ONLOGON /RL LIMITED /TR $tr 2>&1
        if ($LASTEXITCODE -eq 0) {
            & $OnStep 'autostart' 'ok' 'Kaynnistyy automaattisesti kirjautumisen yhteydessa'
        } else {
            & $OnStep 'autostart' 'info' 'Tehtava-ajastusta ei voitu luoda (voit lisata sen myohemmin)'
        }
    } else {
        & $OnStep 'autostart' 'info' 'Ohitettu (ei pyydetty)'
    }

    # --- 8) Palomuuri (lähiverkkokaytto) ---
    if ($s.LanAccess) {
        & $OnStep 'palomuuri' 'start' ''
        $netshArgs = 'advfirewall firewall add rule name="Huoltokello" dir=in action=allow protocol=TCP localport=' + $port + ' profile=any'
        try {
            if ($s.Silent) {
                # Hiljainen asennus: ei UAC-ikkunaa. Toimii, jos asennus ajetaan korotettuna;
                # muuten ohje jaetaan ja saaanto voida lisa myohemmin.
                $null = Start-Process netsh -ArgumentList $netshArgs -Wait -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                & $OnStep 'palomuuri' 'info' ('Yritettiin hiljaista lisaamista (TCP ' + $port + '). Jos ei onnistunut, aja: Tyokalut\PuhelinKaytto.ps1')
            } else {
                Start-Process netsh -ArgumentList $netshArgs -Verb RunAs -Wait
                & $OnStep 'palomuuri' 'ok' ('Palomuurisaanto lisatty (TCP ' + $port + ')')
            }
        } catch {
            & $OnStep 'palomuuri' 'info' 'Palomuuria ei muokattu (oikeuksia ei annettu). Aja myohemmin: Tyokalut\PuhelinKaytto.ps1'
        }
    } else {
        & $OnStep 'palomuuri' 'info' 'Ei tarvita (paikallinen kaytto)'
    }

    # --- 9) Kaynnistys ja tarkistus ---
    & $OnStep 'kaynnistys' 'start' ''
    $bind = if ($s.LanAccess) { '0.0.0.0' } else { '127.0.0.1' }
    $cmdArgs = '/c start "" /min /d "' + $dir + '" "' + $exe + '" --urls=http://' + $bind + ':' + $port
    Start-Process cmd -ArgumentList $cmdArgs -WindowStyle Hidden

    $healthy = $false
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Milliseconds 750
        try {
            $r = Invoke-WebRequest "$baseUrl/health" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { $healthy = $true; break }
        } catch { }
        & $OnStep 'kaynnistys' 'info' ("odotetaan... {0}" -f [int]($i * 0.75))
    }
    if (-not $healthy) {
        & $OnStep 'kaynnistys' 'fail' 'Sovellus ei vastannut /health-tarkistukseen 90 sekunnin sisalla.'
        throw "Sovellus ei kayntynyt. Tarkista loki: $appData\app-err.log"
    }
    & $OnStep 'kaynnistys' 'ok' $baseUrl

    & $OnStep 'varmistus' 'start' ''
    $loginOk = $false
    try {
        $lp = Invoke-WebRequest "$baseUrl/Account/Login" -UseBasicParsing -TimeoutSec 10
        $loginOk = ($lp.StatusCode -eq 200)
    } catch { }
    if (-not $loginOk) {
        & $OnStep 'varmistus' 'fail' 'Kirjautumissivu ei vastannut.'
        throw 'Kirjautumissivu ei vastannut - asennus vaatii tarkistusta.'
    }
    & $OnStep 'varmistus' 'ok' 'Kirjautumissivu vastaa'
    & $OnStep 'valmis' 'ok' $baseUrl

    return @{ Ok = $true; Url = $baseUrl; Dir = $dir; Port = $port; Email = $s.AdminEmail; Updated = $isUpdate; Lan = [bool]$s.LanAccess }
}

# ---------- GUI ----------
$script:Installing = $false

$script:StepLabels = @{
    kansio         = 'Asennuskansio'
    tiedostot      = 'Ohjelmatiedostot (app.zip)'
    asetukset      = 'Asetukset (tyhjä asennus)'
    tili           = 'Ylläpitäjätili'
    tyokalut       = 'Käynnistin ja työkalut'
    pikakuvakkeet  = 'Pikakuvakkeet'
    rekisteri      = 'Windowsin Sovellukset-listaus'
    autostart      = 'Automaattinen käynnistys'
    palomuuri      = 'Palomuuri (lähiverkko)'
    kaynnistys     = 'Käynnistetään Huoltokello'
    varmistus      = 'Varmistus'
    valmis         = 'Valmis'
}
$script:StepOrder = @('kansio','tiedostot','asetukset','tili','tyokalut','pikakuvakkeet','rekisteri','autostart','palomuuri','kaynnistys','varmistus')

$script:AzureStepLabels = @{
    'azure-cli'       = 'Azure CLI -työkalu'
    'azure-kirjaudu'  = 'Kirjautuminen Microsoft-tilillä'
    'azure-tilaus'    = 'Azure-tilaus'
    'azure-resurssit' = 'Resurssiryhmä ja palvelupaketti'
    'azure-sivusto'   = 'Sovelluksen luonti Azureen'
    'pakkaus'         = 'Ohjelmapaketin valmistelu'
    'azure-asetukset' = 'Sovellusasetukset (HTTPS, avaimet)'
    'azure-vienti'    = 'Ohjelmatiedostojen vienti Azureen'
    'azure-kaynnistys' = 'Käynnistys ja tarkistus'
    'azure-varmistus' = 'Varmistus (kirjautumissivu)'
    valmis            = 'Valmis'
}
$script:AzureStepOrder = @('azure-cli','azure-kirjaudu','azure-tilaus','azure-resurssit','azure-sivusto','pakkaus','azure-asetukset','azure-vienti','azure-kaynnistys','azure-varmistus')

$script:ServerStepLabels = @{
    'server-yhteys'    = 'Yhteys palvelimeen'
    'pakkaus'          = 'Ohjelmapaketin valmistelu'
    'server-tiedostot' = 'Tiedostojen siirto palvelimelle'
    'server-ajo'       = 'Suojaukset palvelimella'
    'server-palomuuri' = 'Palomuuri (palvelin)'
    'server-ajastus'   = 'Tehtävä-ajastus (palvelu)'
    'server-kaynnistys' = 'Käynnistys palvelimella'
    'server-varmistus' = 'Varmistus (kirjautumissivu)'
    'server-pikakuva'  = 'Pikakuvake tälle koneelle'
    valmis             = 'Valmis'
}
$script:ServerStepOrder = @('server-yhteys','pakkaus','server-tiedostot','server-ajo','server-palomuuri','server-ajastus','server-kaynnistys','server-varmistus','server-pikakuva')

$script:LocalStepLabels = $script:StepLabels
$script:LocalStepOrder = $script:StepOrder

function Show-HkWizard {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Huoltokello - Asennusvelho" Height="740" Width="700"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize">
  <Window.Resources>
    <Style TargetType="TextBox"><Setter Property="Padding" Value="6,4"/><Setter Property="Margin" Value="0,4,0,8"/></Style>
    <Style TargetType="PasswordBox"><Setter Property="Padding" Value="6,4"/><Setter Property="Margin" Value="0,4,0,8"/></Style>
    <Style TargetType="CheckBox"><Setter Property="Margin" Value="0,8,0,8"/><Setter Property="FontSize" Value="13"/></Style>
    <Style TargetType="Button"><Setter Property="Padding" Value="18,7"/><Setter Property="FontSize" Value="13"/></Style>
    <Style TargetType="TextBlock"><Setter Property="FontSize" Value="13"/></Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Border Background="#1E3A8A" Padding="20,14">
      <StackPanel>
        <TextBlock Text="🕰️  Huoltokello - Asennusvelho" Foreground="White" FontSize="21" FontWeight="Bold"/>
        <TextBlock Text="Kiinteistönhuollon taktinen työnhallinta · paikallinen, Azure tai yrityksen palvelin" Foreground="#C7D2FE" FontSize="12"/>
      </StackPanel>
    </Border>
    <Grid Grid.Row="1" Margin="24,18,24,8">
      <StackPanel x:Name="PageWelcome">
        <TextBlock Text="Tervetuloa!" FontSize="19" FontWeight="Bold" Margin="0,0,0,10"/>
        <TextBlock TextWrapping="Wrap" LineHeight="20"
                   Text="Tämä velho asentaa Huoltokello-ohjelman tyhjänä — ilman demodataa. Valitse ensin, mihin ohjelma asennetaan: omalle koneellesi, Microsoft Azureen omalla Microsoft-tililläsi tai yrityksen omaan Windows-palvelimeen. Käytön aloitat itse vaihe vaiheelta: lisäät tehtävätyypit, työryhmät, käyttäjät, asiakkaat, sopimukset, kohteet ja vuosikellon tehtävät."/>
        <TextBlock TextWrapping="Wrap" LineHeight="20" Margin="0,14,0,0" Text="Velho pyytää ja kysyy:"/>
        <TextBlock Margin="14,4,0,0" Text="• asennustavan ja sen tarvitsemat tiedot (kansio/portti, Azure-kohde tai palvelintiedot)"/>
        <TextBlock Margin="14,0,0,0" Text="• ensimmäisen ylläpitäjätilin tiedot (nimi, sähköposti, salasana)"/>
        <TextBlock Margin="14,0,0,0" Text="• LUVAT-sivulla luvan toimia puolestasi ennen kuin yhtään muutosta tehdään"/>
        <TextBlock TextWrapping="Wrap" Margin="0,14,0,0" Foreground="#374151"
                   Text="Vaatimukset: Windows 10/11 (64-bit), n. 600 Mt vapaata levytilaa. .NET-latauksia ei tarvita — ohjelma on paketoitu itsenäisesti."/>
        <TextBlock TextWrapping="Wrap" Margin="0,14,0,0" Foreground="#6B7280" FontStyle="Italic"
                   Text="Asennuksen jälkeen avautuu vaiheittainen käyttöönotto-opas. Ohjelma jää käynniksi taustalle ja toimii selaimessa osoitteessa http://127.0.0.1:PORTTI."/>
        <Border Background="#FEF3C7" Padding="12,8" Margin="0,16,0,0" CornerRadius="6" x:Name="ExistingWarn" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Text="⚠️ Tälle koneelle löytyy jo aiempi Huoltokello-asennus. Uudelleenasennus säilyttää olemassa olevan datan (päivitys)." TextWrapping="Wrap"/>
            <Button x:Name="btnUninstall" Content="Poista asennus…" Margin="0,8,0,0" HorizontalAlignment="Left"/>
          </StackPanel>
        </Border>
      </StackPanel>
      <StackPanel x:Name="PageDir" Visibility="Collapsed">
        <TextBlock Text="Asennuskansio ja portti" FontSize="19" FontWeight="Bold" Margin="0,0,0,10"/>
        <TextBlock Text="Asennuskansio (ohjelma + tietokanta sijoitetaan tähän):"/>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBox x:Name="txtDir"/>
          <Button x:Name="btnBrowse" Grid.Column="1" Content="Selaa..." Margin="8,4,0,8"/>
        </Grid>
        <TextBlock Text="Portti (1–65535, oletus 8088):"/>
        <TextBox x:Name="txtPort" Width="140" HorizontalAlignment="Left"/>
        <TextBlock x:Name="lblDirError" Foreground="#DC2626" TextWrapping="Wrap" FontWeight="SemiBold"/>
        <TextBlock Foreground="#6B7280" TextWrapping="Wrap" Margin="0,8,0,0"
                   Text="Vinkki: oletuskansio ei vaadi ylläpito-oikeuksia. Jos kansiossa on jo aiempi asennus, olemassa oleva data säilytetään (päivitysasennus)."/>
      </StackPanel>
      <StackPanel x:Name="PageAdmin" Visibility="Collapsed">
        <TextBlock Text="Ensimmäinen ylläpitäjätili" FontSize="19" FontWeight="Bold" Margin="0,0,0,4"/>
        <TextBlock TextWrapping="Wrap" Foreground="#6B7280" Margin="0,0,0,10"
                   Text="Tämä tili saa Johto-roolin: voi luoda käyttäjiä, asiakkaita, sopimuksia ja tehtäviä. Salasana tallennetaan tietokantaan salattuna — kirjoita se ylös."/>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="200"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
          <TextBlock Text="Koko nimi *" VerticalAlignment="Center"/>
          <TextBox x:Name="txtName" Grid.Column="1"/>
          <TextBlock Text="Sähköposti (tunnus) *" Grid.Row="1" VerticalAlignment="Center"/>
          <TextBox x:Name="txtEmail" Grid.Column="1" Grid.Row="1"/>
          <TextBlock Text="Tehtävänimike" Grid.Row="2" VerticalAlignment="Center"/>
          <TextBox x:Name="txtTitle" Grid.Column="1" Grid.Row="2"/>
          <TextBlock Text="Salasana *" Grid.Row="3" VerticalAlignment="Center"/>
          <PasswordBox x:Name="pwPassword" Grid.Column="1" Grid.Row="3"/>
          <TextBlock Text="Salasana uudelleen *" Grid.Row="4" VerticalAlignment="Center"/>
          <PasswordBox x:Name="pwPassword2" Grid.Column="1" Grid.Row="4"/>
        </Grid>
        <TextBlock Text="Vähintään 8 merkkiä, suuraakkonen ja numero (esim. Huolto2026!)" Foreground="#6B7280" FontSize="12"/>
        <TextBlock x:Name="lblAdminError" Foreground="#DC2626" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,6,0,0"/>
      </StackPanel>
      <StackPanel x:Name="PageOptions" Visibility="Collapsed">
        <TextBlock Text="Valinnaiset asetukset (paikallinen asennus)" FontSize="19" FontWeight="Bold" Margin="0,0,0,10"/>
        <CheckBox x:Name="chkDesktop" IsChecked="True" Content="Työpöydän pikakuvake (Huoltokello)"/>
        <CheckBox x:Name="chkStartMenu" IsChecked="True" Content="Käynnistysvalikon pikakuvake (+ Ohjeet)"/>
        <CheckBox x:Name="chkAutoStart" Content="Käynnistä automaattisesti Windows-kirjautumisen yhteydessä"/>
        <CheckBox x:Name="chkPhone" IsChecked="True" Content="Salli käyttö samassa WiFi/lähiverkossa (muut tietokoneet ja puhelimet) — Windows kysyy ylläpito-oikeudet palomuurisääntöön"/>
        <CheckBox x:Name="chkOpenBrowser" IsChecked="True" Content="Avaa selain automaattisesti asennuksen jälkeen"/>
        <TextBlock TextWrapping="Wrap" Margin="0,14,0,0" Foreground="#6B7280"
                   Text="Lähiverkkokäyttö: kaikki saman verkon laitteet käyttävät samaa dataa reaaliajassa (SignalR). Verkko-osoitteet näkyvät yhteenvedossa, lopputuloksessa ja sovelluksen ⚙️ Asetukset-sivulla. Voit muuttaa asetusta myöhemmin asetuksista tai Tyokalut-kansiosta (PuhelinKaytto.ps1)."/>
      </StackPanel>
      <StackPanel x:Name="PageMode" Visibility="Collapsed">
        <TextBlock Text="1. Asennustapa" FontSize="19" FontWeight="Bold" Margin="0,0,0,10"/>
        <TextBlock TextWrapping="Wrap" Foreground="#6B7280" Margin="0,0,0,12"
                   Text="Valitse, minne Huoltokello asennetaan. Velho kysyy seuraavilla sivuilla tarvittavat tiedot ja pyytää lupaa toimia puolestasi ennen kuin yhtään muutosta tehdään."/>
        <Border CornerRadius="8" BorderBrush="#1D4ED8" BorderThickness="2" Padding="12,10" Margin="0,0,0,8" Background="#EFF6FF">
          <RadioButton x:Name="rbModePaikallinen" GroupName="hkMode" IsChecked="True">
            <StackPanel>
              <TextBlock Text="Paikallinen asennus — tälle koneelle" FontWeight="Bold" FontSize="14"/>
              <TextBlock TextWrapping="Wrap" Foreground="#374151" Text="Ohjelma omalle tietokoneellesi, käyttö selaimessa osoitteessa http://127.0.0.1:portti. Ei vaadi tunnuksia muualle."/>
            </StackPanel>
          </RadioButton>
        </Border>
        <Border CornerRadius="8" BorderBrush="#CBD5E1" BorderThickness="1" Padding="12,10" Margin="0,0,0,8">
          <RadioButton x:Name="rbModeAzure" GroupName="hkMode">
            <StackPanel>
              <TextBlock Text="Microsoft Azure — pilveen omalla Microsoft-tililläsi" FontWeight="Bold" FontSize="14"/>
              <TextBlock TextWrapping="Wrap" Foreground="#374151" Text="Velho luo App Service -sovelluksen sinun Azureen (vaatii Microsoft-tilin ja Azure-tilauksen). Kirjautuminen selaimella laitteistokoodilla."/>
            </StackPanel>
          </RadioButton>
        </Border>
        <Border CornerRadius="8" BorderBrush="#CBD5E1" BorderThickness="1" Padding="12,10">
          <RadioButton x:Name="rbModeServeri" GroupName="hkMode">
            <StackPanel>
              <TextBlock Text="Yrityksen oma Windows-palvelin" FontWeight="Bold" FontSize="14"/>
              <TextBlock TextWrapping="Wrap" Foreground="#374151" Text="Asennus yrityksen Windows-palvelimelle etäyhteydellä: anna palvelimen osoite, ylläpitotunnukset, asennuspolku ja portti."/>
            </StackPanel>
          </RadioButton>
        </Border>
        <TextBlock x:Name="lblModeError" Foreground="#DC2626" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,10,0,0"/>
      </StackPanel>
      <StackPanel x:Name="PageAzure" Visibility="Collapsed">
        <TextBlock Text="2. Azure-kohteen tiedot" FontSize="19" FontWeight="Bold" Margin="0,0,0,4"/>
        <TextBlock TextWrapping="Wrap" Foreground="#6B7280" Margin="0,0,0,10"
                   Text="Velho kirjautuu puolestasi Microsoft-tilillä (laitteistokoodi selaimessa) ja luo Azureen resurssiryhmän, palvelupaketin ja sovelluksen. Käyttöoikeudet säilyvät sinulla."/>
        <TextBlock Text="Sovelluksen nimi (osoitteesta tulee NIMI.azurewebsites.net):"/>
        <TextBox x:Name="txtAzName"/>
        <TextBlock Text="Resurssiryhmä:"/>
        <TextBox x:Name="txtAzRg"/>
        <TextBlock Text="Alue (region):"/>
        <ComboBox x:Name="cmbAzRegion"/>
        <TextBlock Text="Hintataso:"/>
        <ComboBox x:Name="cmbAzSku"/>
        <TextBlock Text="Tilaustunnus (valinnainen — jätä tyhjäksi, jos tilauksia on vain yksi):"/>
        <TextBox x:Name="txtAzSubId"/>
        <TextBlock x:Name="lblAzError" Foreground="#DC2626" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,6,0,0"/>
        <TextBlock x:Name="lblAzInfo" Foreground="#92400E" TextWrapping="Wrap" Margin="0,6,0,0"/>
      </StackPanel>
      <StackPanel x:Name="PageServer" Visibility="Collapsed">
        <TextBlock Text="2. Palvelintiedot" FontSize="19" FontWeight="Bold" Margin="0,0,0,4"/>
        <TextBlock TextWrapping="Wrap" Foreground="#6B7280" Margin="0,0,0,10"
                   Text="Velho yhdistää palvelimeen PowerShell-etäyhteydellä (WinRM 5985) ja kopioi ohjelmatiedostot jaetulla hallintoyhteydellä (C$). Käyttäjällä täytyy olla palvelimen ylläpito-oikeudet."/>
        <TextBlock Text="Palvelimen osoite (koneen nimi tai IP, esim. PALVELIN-A tai 10.0.0.5):"/>
        <TextBox x:Name="txtSrvHost"/>
        <TextBlock Text="Ylläpitotunnus (esim. PALVELIN-A\Administrator tai FIRMA\admin):"/>
        <TextBox x:Name="txtSrvUser"/>
        <TextBlock Text="Salasana:"/>
        <PasswordBox x:Name="pwSrvPass"/>
        <TextBlock Text="Asennuskansio palvelimella:"/>
        <TextBox x:Name="txtSrvPath"/>
        <TextBlock Text="Portti:"/>
        <TextBox x:Name="txtSrvPort"/>
        <CheckBox x:Name="chkSrvNotDomain" Content="Palvelin EI ole toimialueessa (lisää tälle koneelle TrustedHosts-tietueen — Windows kysyy ylläpitoluvan)"/>
        <CheckBox x:Name="chkSrvShortcut" IsChecked="True" Content="Luo työpöydälle pikakuvake kyseiseen osoitteeseen"/>
        <TextBlock x:Name="lblSrvError" Foreground="#DC2626" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,6,0,0"/>
      </StackPanel>
      <StackPanel x:Name="PageLuvat" Visibility="Collapsed">
        <TextBlock Text="Luvat ja tietoturva" FontSize="19" FontWeight="Bold" Margin="0,0,0,4"/>
        <TextBlock TextWrapping="Wrap" Foreground="#6B7280" Margin="0,0,0,10"
                   Text="Skripti tekee alla luetellut toimenpiteet puolistasi, jotta asennus ei vaadi käsin ajettavia komentoja. Lue luettelo — jatka vain, jos hyväksyt sen."/>
        <Border Background="#FEF9C3" CornerRadius="6" Padding="12,10">
          <TextBlock x:Name="lblLuvatList" TextWrapping="Wrap" LineHeight="20"/>
        </Border>
        <CheckBox x:Name="chkLuvat" Content="Skripti saa toimia puolestani — annan luvan yllä oleviin toimenpiteisiin" FontWeight="SemiBold"/>
        <TextBlock x:Name="lblLuvatError" Foreground="#DC2626" FontWeight="SemiBold" TextWrapping="Wrap"/>
        <TextBlock TextWrapping="Wrap" Margin="0,8,0,0" Foreground="#6B7280"
                   Text="Tietoturva: salasanat kirjoitetaan vain muistiin asennuksen ajaksi; VAPID-yksityisavain tallennetaan suojattuun tiedostoon (paikallinen/palvelin) tai Azure-ympäristöasetuksiin; asetustiedostoihin voi lukea vain sinä (paikallinen) tai palvelimen ylläpitäjät (palvelin). "/>
      </StackPanel>
      <StackPanel x:Name="PageSummary" Visibility="Collapsed">
        <TextBlock Text="Yhteenveto" FontSize="19" FontWeight="Bold" Margin="0,0,0,10"/>
        <TextBlock x:Name="lblSummary" TextWrapping="Wrap" LineHeight="21"/>
        <TextBlock TextWrapping="Wrap" Margin="0,16,0,0" Foreground="#9A3412" FontWeight="SemiBold"
                   Text="Muistutus: kirjaa ylläpitäjätilin salasana talteen — sitä ei näytetä enää uudelleen."/>
      </StackPanel>
      <StackPanel x:Name="PageInstall" Visibility="Collapsed">
        <TextBlock Text="Asennus" FontSize="19" FontWeight="Bold" Margin="0,0,0,10"/>
        <ProgressBar x:Name="pbProgress" Height="16" Minimum="0" Maximum="100"/>
        <ListBox x:Name="lstSteps" Height="330" Margin="0,12,0,0" FontSize="13" BorderBrush="#CBD5E1"/>
        <TextBlock x:Name="lblInstStatus" Margin="0,10,0,0" Foreground="#374151" TextWrapping="Wrap"/>
      </StackPanel>
      <StackPanel x:Name="PageDone" Visibility="Collapsed">
        <TextBlock x:Name="lblDoneTitle" Text="✓ Asennus valmis!" FontSize="22" FontWeight="Bold" Foreground="#15803D" Margin="0,0,0,10"/>
        <TextBlock x:Name="lblDoneInfo" TextWrapping="Wrap" LineHeight="21"/>
        <TextBlock Text="Käyttöönotto vaihe vaiheelta (yksityiskohtainen opas: Ohjeet-kansio):" Margin="0,16,0,4" FontWeight="SemiBold"/>
        <TextBlock TextWrapping="Wrap" LineHeight="20" Foreground="#374151"
                   Text="1. Kirjaudu sisään ylläpitäjätililläsi&#10;2. Hallinta → Tehtävätyypit: lisää omat työtyypit&#10;3. Hallinta → Ryhmät: luo työryhmät&#10;4. Hallinta → Käyttäjät: luo muut käyttäjät (tai Tyokalut\Luo-Kayttaja.ps1)&#10;5. Asiakkaat → Uusi asiakas&#10;6. Sopimukset → Uusi sopimus (hinnat + ALV)&#10;7. Kohteet → Uusi kohde (+ tulosta QR)&#10;8. Vuosikello → lisää tehtävät / Toistuvat tehtävät -pohjat"/>
        <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
          <Button x:Name="btnOpenBrowser" Content="Avaa Huoltokello" Background="#1D4ED8" Foreground="White" Margin="0,0,8,0"/>
          <Button x:Name="btnOpenHelp" Content="Avaa käyttöönotto-opas" Margin="0,0,8,0"/>
          <Button x:Name="btnOpenFolder" Content="Avaa asennuskansio" Margin="0,0,8,0"/>
          <Button x:Name="btnFinish" Content="Valmis"/>
        </StackPanel>
      </StackPanel>
    </Grid>
    <Border Grid.Row="2" Background="#E8EDF7" Padding="16,10">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="lblFooterError" Foreground="#DC2626" TextWrapping="Wrap" VerticalAlignment="Center" FontWeight="SemiBold"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="btnBack" Content="&lt; Takaisin" Margin="0,0,8,0"/>
          <Button x:Name="btnNext" Content="Jatka &gt;" Background="#1D4ED8" Foreground="White" Margin="0,0,8,0"/>
          <Button x:Name="btnCancel" Content="Peruuta"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@
    [xml]$x = $xaml
    $reader = New-Object System.Xml.XmlNodeReader $x
    $win = [Windows.Markup.XamlReader]::Load($reader)
    if (Test-Path $IconFile) {
        try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($IconFile)) } catch { }
    }

    # Ohjainviittaukset
    $c = @{}
    foreach ($name in @('PageWelcome','PageMode','PageDir','PageAzure','PageServer','PageAdmin','PageOptions',
                        'PageLuvat','PageSummary','PageInstall','PageDone',
                        'rbModePaikallinen','rbModeAzure','rbModeServeri','lblModeError',
                        'txtAzName','txtAzRg','cmbAzRegion','cmbAzSku','txtAzSubId','lblAzError','lblAzInfo',
                        'txtSrvHost','txtSrvUser','pwSrvPass','txtSrvPath','txtSrvPort','chkSrvNotDomain','chkSrvShortcut','lblSrvError',
                        'lblLuvatList','chkLuvat','lblLuvatError',
                        'txtDir','btnBrowse','txtPort','lblDirError','txtName','txtEmail','txtTitle',
                        'pwPassword','pwPassword2','lblAdminError','chkDesktop','chkStartMenu','chkAutoStart',
                        'chkPhone','chkOpenBrowser','lblSummary','pbProgress','lstSteps','lblInstStatus',
                        'lblDoneTitle','lblDoneInfo','btnOpenBrowser','btnOpenHelp','btnOpenFolder','btnFinish',
                        'lblFooterError','btnBack','btnNext','btnCancel',
                        'ExistingWarn','btnUninstall')) {
        $c[$name] = $win.FindName($name)
        if (-not $c[$name]) { throw "Velhon ohjain puuttuu XAML:sta: $name" }
    }

    # Pudotusvalikoiden sisalto (merkkijonoina; SelectedItem on silloin [string])
    $c.cmbAzRegion.ItemsSource = @('finlandiacentral','northeurope','westeurope','swedencentral','eastus','westus2')
    $c.cmbAzRegion.SelectedIndex = 0
    $c.cmbAzSku.ItemsSource = @('B1','F1','P1v2')
    $c.cmbAzSku.SelectedIndex = 0
    $c.txtAzRg.Text = 'huoltokello-rg'

    $script:PageIdx = 0
    $script:Mode = 'paikallinen'
    $script:Pages = @('PageWelcome','PageMode','PageDir','PageAdmin','PageOptions','PageLuvat','PageSummary','PageInstall','PageDone')

    function Get-HkSelectedMode {
        if ($c.rbModeAzure.IsChecked) { return 'azure' }
        if ($c.rbModeServeri.IsChecked) { return 'serveri' }
        return 'paikallinen'
    }

    function Set-HkPagesForMode {
        param([string]$m)
        $script:Mode = $m
        if ($m -eq 'azure') {
            $script:Pages = @('PageWelcome','PageMode','PageAzure','PageAdmin','PageLuvat','PageSummary','PageInstall','PageDone')
        } elseif ($m -eq 'serveri') {
            $script:Pages = @('PageWelcome','PageMode','PageServer','PageAdmin','PageLuvat','PageSummary','PageInstall','PageDone')
        } else {
            $script:Pages = @('PageWelcome','PageMode','PageDir','PageAdmin','PageOptions','PageLuvat','PageSummary','PageInstall','PageDone')
        }
    }

    function Get-HkLuvatText {
        param([string]$m)
        if ($m -eq 'azure') {
            return @"
• Asennetaan Azure CLI -työkalu, jos se ei vielä ole koneellasi (Microsoftin virallinen jakelu; Windows saattaa kysyä ylläpitoluvan).
• Kirjaudutaan puolestasi Microsoft-tilille laitteistokoodilla (koodi näytetään velhossa).
• Luodaan Azureen resurssiryhmä, App Service -palvelupaketti ja sovellus valitsemallesi alueelle ja hintatason mukaisesti (veloittaa tilauksessasi sovitun hintatason mukaan).
• Tallennetaan sovellusasetukset (HTTPS-pakotus, HTTP/2, VAPID-ilmoitusavaimet ympäristöasetuksiin).
• Viedään Huoltokello-ohjelmapaketti Azureen (zip-vienti) ja avataan sovellus.
• Luodaan ensimmäinen ylläpitäjätili annetuilla tiedoilla (ei demodataa).
"@
        }
        if ($m -eq 'serveri') {
            return @"
• Kirjaudutaan puolestasi palvelimelle PowerShell-etäyhteydellä (WinRM/TCP 5985) antamasi ylläpitotunnuksella.
• Kopioidaan Huoltokello-ohjelmatiedostot palvelimelle jaetulla hallintoyhteydellä ja puretaan ne annettuun kansioon.
• Tehdään palvelimella: asetustiedostojen käyttöoikeudet rajataan ylläpitäjille (icacls), lisätään palomuurisääntö TCP-portille, luodaan tehtävä-ajastus (Huoltokello-Palvelu, ylläpitää ohjelmaa käynnissä) ja käynnistetään sovellus.
• Luodaan ensimmäinen ylläpitäjätili annetuilla tiedoilla (ei demodataa).
• Vanhat tiedostot ylikirjoitetaan; olemassa oleva tietokanta (AppData\huoltokello.db) säilyy, eikä sitä poisteta.
"@
        }
        return @"
• Kirjoitetaan ohjelmatiedostot valitsemaasi kansioon ja luodaan pikakuvakkeet/käynnistysvalikko-merkinnät.
• Luodaan ensimmäinen ylläpitäjätili annetuilla tiedoilla (ei demodataa) ja suojataan VAPID-yksityisavain sovelluksen AppData-kansioon.
• Rekisteröidään ohjelma Windowsin Sovellukset-listaan.
• Jos valitset lähiverkkokäytön: lisätään palomuurisääntö (Windows kysyy ylläpitoluvan).
• Autom. käynnistys: luodaan tehtävä-ajastus Huoltokello (tapahtuu vain, jos valitset sen).
"@
    }

    function Show-Page([int]$idx) {
        $script:PageIdx = $idx
        for ($i = 0; $i -lt $script:Pages.Count; $i++) {
            $vis = if ($i -eq $idx) { 'Visible' } else { 'Collapsed' }
            $c[$script:Pages[$i]].Visibility = $vis
        }
        $pname = $script:Pages[$idx]
        $isLast = ($idx -ge ($script:Pages.Count - 2))
        $c.btnBack.Visibility = if ($idx -eq 0 -or $isLast) { 'Collapsed' } else { 'Visible' }
        $c.btnCancel.Visibility = if ($isLast) { 'Collapsed' } else { 'Visible' }
        if ($pname -eq 'PageSummary') {
            $c.btnNext.Content = 'Asenna >'
            $c.btnNext.Visibility = 'Visible'
        } elseif ($isLast) {
            $c.btnNext.Visibility = 'Collapsed'
        } else {
            $c.btnNext.Content = 'Jatka >'
            $c.btnNext.Visibility = 'Visible'
        }
        if ($pname -eq 'PageLuvat') { $c.lblLuvatList.Text = Get-HkLuvatText -m $script:Mode; $c.lblLuvatError.Text = '' }
        if ($pname -eq 'PageSummary') { Update-Summary }
        $c.lblFooterError.Text = ''
        $win.UpdateLayout()
    }

    function Get-Settings {
        $srvPort = 0
        [void][int]::TryParse($c.txtSrvPort.Text.Trim(), [ref]$srvPort)
        return @{
            Mode              = $script:Mode
            InstallDir        = $c.txtDir.Text.Trim()
            Port              = [int]$c.txtPort.Text.Trim()
            AdminName         = $c.txtName.Text.Trim()
            AdminEmail        = $c.txtEmail.Text.Trim().ToLower()
            AdminTitle        = $c.txtTitle.Text.Trim()
            AdminPassword     = ConvertTo-PlainText $c.pwPassword.SecurePassword
            DesktopShortcut   = [bool]$c.chkDesktop.IsChecked
            StartMenuShortcut = [bool]$c.chkStartMenu.IsChecked
            AutoStart         = [bool]$c.chkAutoStart.IsChecked
            PhoneAccess       = [bool]$c.chkPhone.IsChecked
            LanAccess         = [bool]$c.chkPhone.IsChecked
            OpenBrowser       = [bool]$c.chkOpenBrowser.IsChecked
            NoShortcuts       = $false
            Silent            = $false
            AzName            = $c.txtAzName.Text.Trim().ToLower()
            AzRg              = $c.txtAzRg.Text.Trim()
            AzRegion          = [string]$c.cmbAzRegion.SelectedItem
            AzSku             = [string]$c.cmbAzSku.SelectedItem
            AzSubscriptionId  = $c.txtAzSubId.Text.Trim()
            ServerHost        = $c.txtSrvHost.Text.Trim()
            ServerUser        = $c.txtSrvUser.Text.Trim()
            ServerPass        = ConvertTo-PlainText $c.pwSrvPass.SecurePassword
            ServerPath        = $c.txtSrvPath.Text.Trim()
            ServerPort        = $srvPort
            ServerNotDomain   = [bool]$c.chkSrvNotDomain.IsChecked
            MakeShortcut      = [bool]$c.chkSrvShortcut.IsChecked
            HyvaksyLuvat      = [bool]$c.chkLuvat.IsChecked
        }
    }

    # --- Validoinnit ---
    function Test-Page2 {
        $c.lblDirError.Text = ''
        $dir = $c.txtDir.Text.Trim()
        $portTxt = $c.txtPort.Text.Trim()
        if (-not $dir -or $dir -notmatch '^[A-Za-z]:\\') { $c.lblDirError.Text = 'Anna kelvollinen kansio (esim. C:\Huoltokello).'; return $false }
        $port = 0
        if (-not [int]::TryParse($portTxt, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
            $c.lblDirError.Text = 'Portin on oltava numero valilla 1-65535.'; return $false
        }
        try {
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            $probe = Join-Path $dir '.velhotesti'
            Set-Content -Path $probe -Value 'ok' -Encoding ASCII
            Remove-Item $probe -Force
        } catch {
            $c.lblDirError.Text = 'Kansioon ei voi kirjoittaa. Valitse toinen kansio (esim. Documents tai C:\Huoltokello).'
            return $false
        }
        if (-not (Test-PortFree $port)) {
            try {
                $h = Invoke-WebRequest "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 2
                $c.lblDirError.Text = "Portissa $port on jo palvelu. Jos se on aiempi Huoltokello-asennus, valitse toinen portti."
            } catch {
                $c.lblDirError.Text = "Portti $port on varattu toiselle ohjelmalle. Valitse toinen portti."
            }
            return $false
        }
        return $true
    }

    function Test-Page3 {
        $c.lblAdminError.Text = ''
        $name = $c.txtName.Text.Trim()
        $email = $c.txtEmail.Text.Trim()
        if (-not $name) { $c.lblAdminError.Text = 'Anna koko nimi.'; return $false }
        if (-not (Test-Email $email)) { $c.lblAdminError.Text = 'Anna kelvollinen sahkopostiosoite (esim. maija@firma.fi).'; return $false }
        $pw = ConvertTo-PlainText $c.pwPassword.SecurePassword
        $pw2 = ConvertTo-PlainText $c.pwPassword2.SecurePassword
        $err = Test-HkPasswordRule $pw
        if ($err) { $c.lblAdminError.Text = $err; return $false }
        if ($pw -ne $pw2) { $c.lblAdminError.Text = 'Salasanat eivat tasmalle.'; return $false }
        return $true
    }

    function Test-PageMode {
        $c.lblModeError.Text = ''
        $m = Get-HkSelectedMode
        Set-HkPagesForMode -m $m
        if ($m -eq 'azure') {
            if (-not (Test-HkAzInstalled)) {
                Add-HkAzPath
                if (Test-HkAzInstalled) {
                    $c.lblAzInfo.Text = 'Azure CLI loytyi nyt polusta.'
                } else {
                    $c.lblAzInfo.Text = 'Huom: Azure CLI ei viela loydy koneelta - velho asentaa sen asennuksen aikana puolestasi (Microsoftin virallinen jakelu).'
                }
            } else {
                $c.lblAzInfo.Text = ''
            }
        }
        return $true
    }

    function Test-PageAzure {
        $c.lblAzError.Text = ''
        $name = $c.txtAzName.Text.Trim().ToLower()
        $rg = $c.txtAzRg.Text.Trim()
        if (-not $name -or $name.Length -lt 3 -or $name.Length -gt 60) {
            $c.lblAzError.Text = 'Sovelluksen nimen pituus on oltava 3-60 merkkiä (osoitteesta tulee NIMI.azurewebsites.net).'; return $false
        }
        if ($name -notmatch '^[a-z0-9\-]+$') {
            $c.lblAzError.Text = 'Nimessä saa olla vain pieniä kirjaimia, numeroita ja viivoja (-).'; return $false
        }
        if (-not $rg) { $c.lblAzError.Text = 'Anna resurssiryhmän nimi (esim. huoltokello-rg).'; return $false }
        if ($rg -notmatch '^[A-Za-z0-9._\-()]+$') {
            $c.lblAzError.Text = 'Resurssiryhmän nimessä saa olla kirjaimia, numeroita, pisteitä, viivoja, alaviivoja ja sulkuja.'; return $false
        }
        $sub = $c.txtAzSubId.Text.Trim()
        if ($sub -and $sub -notmatch '^[0-9a-fA-F\-]{8,40}$') {
            $c.lblAzError.Text = 'Tilaustunnus näyttää virheelliseltä (pois jättäminen ok, jos tilauksia on vain yksi).'; return $false
        }
        return $true
    }

    function Test-PageServer {
        $c.lblSrvError.Text = ''
        $svHost = $c.txtSrvHost.Text.Trim()
        $svUser = $c.txtSrvUser.Text.Trim()
        $svPath = $c.txtSrvPath.Text.Trim()
        $svPort = 0
        if (-not $svHost) { $c.lblSrvError.Text = 'Anna palvelimen osoite (koneen nimi tai IP).'; return $false }
        if (-not $svUser) { $c.lblSrvError.Text = 'Anna ylläpitotunnus (esim. PALVELIN\Administrator).'; return $false }
        $svPw = ConvertTo-PlainText $c.pwSrvPass.SecurePassword
        if (-not $svPw) { $c.lblSrvError.Text = 'Anna ylläpitäjän salasana.'; return $false }
        if ($svPath -notmatch '^[A-Za-z]:\\') { $c.lblSrvError.Text = 'Asennuskansion on oltava kelvollinen polku palvelimella (esim. C:\Huoltokello).'; return $false }
        if (-not [int]::TryParse($c.txtSrvPort.Text.Trim(), [ref]$svPort) -or $svPort -lt 1 -or $svPort -gt 65535) {
            $c.lblSrvError.Text = 'Portin on oltava numero välillä 1-65535.'; return $false
        }
        if ($c.chkSrvNotDomain.IsChecked) {
            Invoke-HkServerFixTrustedHosts -HostToAdd $svHost
        }
        return $true
    }

    function Test-PageLuvat {
        $c.lblLuvatError.Text = ''
        if (-not $c.chkLuvat.IsChecked) {
            $c.lblLuvatError.Text = 'Asennus jatkuu vasta, kun annat skriptille luvan toimia puolestasi.'
            return $false
        }
        return $true
    }

    function Update-Summary {
        $s = Get-Settings
        if ($s.Mode -eq 'azure') {
            $c.lblSummary.Text = @"
Asennustapa:    MICROSOFT AZURE (App Service, omalla Microsoft-tilillä)
Osoite:         https://$($s.AzName).azurewebsites.net
Resurssiryhmä:  $($s.AzRg)    Alue: $($s.AzRegion)    Hintataso: $($s.AzSku)
Ylläpitäjätili: $($s.AdminName) <$($s.AdminEmail)>$(if ($s.AdminTitle) { " - $($s.AdminTitle)" })
Rooli:          Johto (voi hallita kaikkea)
VAPID:          luodaan ja tallennetaan Azure-ympäristöasetuksiin

Velho toimii puolestasi: CLI (tarvittaessa), Microsoft-kirjautuminen,
resurssien luonti, asetukset, ohjelmapaketin vienti ja käynnistys.

Ohjelma asennetaan TYHJÄNÄ: käyttöönotto tapahtuu vaihe vaiheelta
opasta seuraten (tehtävätyypit, käyttäjät, asiakkaat, sopimukset...).
"@
            return
        }
        if ($s.Mode -eq 'serveri') {
            $url = 'http://' + $s.ServerHost + ':' + $s.ServerPort
            $c.lblSummary.Text = @"
Asennustapa:    YRITYKSEN OMA WINDOWS-PALVELIN
Palvelin:       $($s.ServerHost)    Portti: $($s.ServerPort)
Kansio:         $($s.ServerPath) (palvelimella)
Osoite:         $url
Tunnus:         $($s.ServerUser)
Ylläpitäjätili: $($s.AdminName) <$($s.AdminEmail)>$(if ($s.AdminTitle) { " - $($s.AdminTitle)" })
Rooli:          Johto (voi hallita kaikkea)
Pikakuvake:     $(if ($s.MakeShortcut) { 'luodaan tälle koneelle' } else { 'ei luoda' })

Velho toimii puolestasi: WinRM-yhteys, tiedostojen siirto, käyttöoikeudet,
palomuuri, tehtävä-ajastus (palvelu) ja käynnistys palvelimella.

Ohjelma asennetaan TYHJÄNÄ: käyttöönotto tapahtuu vaihe vaiheelta
opasta seuraten (tehtävätyypit, käyttäjät, asiakkaat, sopimukset...).
"@
            return
        }
        $update = Test-Path (Join-Path $s.InstallDir 'AppData\huoltokello.db')
        $bindTxt = if ($s.LanAccess) { 'http://0.0.0.0:' + $s.Port + ' (koko lahiverkko)' } else { 'http://127.0.0.1:' + $s.Port }
        $c.lblSummary.Text = @"
Asennustapa:    PAIKALLINEN (tälle koneelle)
Asennuskansio:  $($s.InstallDir)$(if ($update) { '  (OLEMASSA OLEVA ASENNU - data sailytetaan)' })
Osoite:         $bindTxt
Ylläpitäjätili: $($s.AdminName) <$($s.AdminEmail)>$(if ($s.AdminTitle) { " - $($s.AdminTitle)" })
Rooli:          Johto (voi hallita kaikkea)

Valinnaiset:
  Työpöydän pikakuvake:      $(if ($s.DesktopShortcut) { 'kyllä' } else { 'ei' })
  Käynnistysvalikko:         $(if ($s.StartMenuShortcut) { 'kyllä' } else { 'ei' })
  Automaattinen käynnistys:  $(if ($s.AutoStart) { 'kyllä' } else { 'ei' })
  Puhelinkäyttö (WiFi):      $(if ($s.LanAccess) { 'kyllä - koko lähiverkko (pyytää ylläpito-oikeudet)' } else { 'ei' })
  Selain asennuksen jälkeen: $(if ($s.OpenBrowser) { 'kyllä' } else { 'ei' })

Ohjelma asennetaan TYHJÄNÄ: käyttöönotto tapahtuu vaihe vaiheelta
opasta seuraten (tehtävätyypit, käyttäjät, asiakkaat, sopimukset...).
"@
    }

    # --- Asennuksen ajo (UI-saikeessa, DoEvents pitaa ikkunan elossa) ---
    $script:CurrentStep = -1
    function Add-StepLine([string]$id, [string]$symbol) {
        $label = if ($script:StepLabels.ContainsKey($id)) { $script:StepLabels[$id] } else { $id }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = "$symbol $label"
        if ($symbol -eq '>') { $item.Foreground = [Windows.Media.Brushes]::Gray }
        elseif ($symbol -eq 'OK') { $item.Foreground = [Windows.Media.Brushes]::Green }
        else { $item.Foreground = [Windows.Media.Brushes]::DarkRed }
        $c.lstSteps.Items.Add($item) | Out-Null
        $c.lstSteps.SelectedIndex = $c.lstSteps.Items.Count - 1
        $c.lstSteps.ScrollIntoView($item)
    }
    function Update-LastStep([string]$symbol, [string]$detail) {
        $item = $c.lstSteps.Items[$c.lstSteps.Items.Count - 1]
        $base = ($item.Content -split '  ', 2)[0]
        $item.Content = if ($detail) { "$base  ($detail)" } else { $base }
        if ($symbol -eq 'OK') { $item.Foreground = [Windows.Media.Brushes]::Green }
    }
    function Invoke-StepCallback {
        param([string]$id, [string]$status, [string]$detail)
        switch ($status) {
            'start' { $script:CurrentStep = $script:StepOrder.IndexOf($id); Add-StepLine $id '>' }
            'ok'    { Update-LastStep 'OK' $detail }
            'fail'  { Update-LastStep 'X' $detail }
            'info'  { Update-LastStep '>' $detail }
        }
        $pct = 0
        if ($script:CurrentStep -ge 0) { $pct = [Math]::Min(99, [int](100 * $script:CurrentStep / $script:StepOrder.Count)) }
        if ($id -eq 'tiedostot' -and $detail -match '(\d+)/(\d+)') {
            $pct = [Math]::Min(99, [int](100 * ($script:CurrentStep + [double]($Matches[1]) / [double]($Matches[2])) / $script:StepOrder.Count))
        }
        if ($id -eq 'valmis') { $pct = 100 }
        $c.pbProgress.Value = $pct
        $c.lblInstStatus.Text = if ($detail) { $detail } else { $script:StepLabels[$id] }
        [System.Windows.Forms.Application]::DoEvents()
    }

    function Start-Install {
        $s = Get-Settings
        $script:Installing = $true
        $c.lstSteps.Items.Clear()
        $c.btnNext.Visibility = 'Collapsed'; $c.btnBack.Visibility = 'Collapsed'; $c.btnCancel.Visibility = 'Collapsed'
        $c.lblFooterError.Text = ''
        $result = $null
        try {
            if ($s.Mode -eq 'azure') {
                $script:StepLabels = $script:AzureStepLabels
                $script:StepOrder = $script:AzureStepOrder
                $result = Invoke-HkAzureInstall -s $s -OnStep ${function:Invoke-StepCallback}
                $c.pbProgress.Value = 100
                $script:DoneUrl = $result.Url
                if ($s.OpenBrowser) { try { Start-Process $result.Url } catch { } }
                Show-Page ($script:Pages.Count - 1)
                $c.lblDoneTitle.Text = 'Azure-asennus valmis!'
                $c.lblDoneInfo.Text = @"
Osoite:  $($result.Url)
Sovellus: $($result.AppName)
Tili:    $($result.Email) (Johto)$(if ($result.Updated) { "`n`nHUIPPU: aiempi Azure-asennus paivitettiin." })
"@
                $c.btnOpenFolder.Visibility = 'Collapsed'
            } elseif ($s.Mode -eq 'serveri') {
                $script:StepLabels = $script:ServerStepLabels
                $script:StepOrder = $script:ServerStepOrder
                $result = Invoke-HkServerInstall -s $s -OnStep ${function:Invoke-StepCallback}
                $c.pbProgress.Value = 100
                $script:DoneUrl = $result.Url
                if ($s.MakeShortcut) { try { Start-Process $result.Url } catch { } }
                Show-Page ($script:Pages.Count - 1)
                $c.lblDoneTitle.Text = 'Palvelinasennus valmis!'
                $c.lblDoneInfo.Text = @"
Palvelin: $($result.ServerName)
Osoite:   $($result.Url)
Kansio:   $($result.Path) (palvelimella)
Tili:     $($result.Email) (Johto)$(if ($result.Updated) { "`n`nHUIPPU: aiempi palvelinasennus paivitettiin - data sailytettiin." })
"@
                $c.btnOpenFolder.Visibility = 'Collapsed'
            } else {
                $script:StepLabels = $script:LocalStepLabels
                $script:StepOrder = $script:LocalStepOrder
                $result = Invoke-HkInstall -s $s -OnStep ${function:Invoke-StepCallback}
                $c.pbProgress.Value = 100
                $script:DoneUrl = $result.Url
                if ($s.OpenBrowser) { try { Start-Process $result.Url } catch { } }
                Show-Page ($script:Pages.Count - 1)
                $c.lblDoneInfo.Text = @"
Sijainti:  $($result.Dir)
Osoite:    $($result.Url)
Tili:      $($result.Email) (Johto)$(if ($result.Updated) { "`n`nHUIPPU: aiempi asennus paivitettiin - vanha data sailytettiin." })
"@
                if ($result.Lan) {
                    try {
                        $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                            Select-Object -ExpandProperty IPAddress -Unique)
                        if ($ips.Count -gt 0) {
                            $c.lblDoneInfo.Text += "`n`nLahiverkko (puhelimet ja muut koneet, sama WiFi):"
                            foreach ($ip in $ips) { $c.lblDoneInfo.Text += "`n  http://${ip}:$($result.Port)" }
                        }
                    } catch { }
                }
            }
        } catch {
            $c.lblFooterError.Text = "VIRHE: $($_.Exception.Message)"
            $c.lblInstStatus.Text = "Asennus pysähtyi. Korjaa ongelma ja käynnistä velho uudelleen."
        } finally {
            $script:Installing = $false
        }
    }

    # --- Painikkeet ---
    $c.btnBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Valitse kansio, johon Huoltokello asennetaan'
        if ($dlg.ShowDialog() -eq 'OK') { $c.txtDir.Text = $dlg.SelectedPath }
    })
    $c.btnBack.Add_Click({ if ($script:PageIdx -gt 0) { Show-Page ($script:PageIdx - 1) } })
    $c.btnCancel.Add_Click({ $win.Close() })
    $c.btnNext.Add_Click({
        $ok = $true
        switch ($script:Pages[$script:PageIdx]) {
            'PageMode'    { $ok = Test-PageMode }
            'PageDir'     { $ok = Test-Page2 }
            'PageAzure'   { $ok = Test-PageAzure }
            'PageServer'  { $ok = Test-PageServer }
            'PageAdmin'   { $ok = Test-Page3 }
            'PageOptions' { Update-Summary }
            'PageLuvat'   { $ok = Test-PageLuvat; if ($ok) { Update-Summary } }
            'PageSummary' { Start-Install; return }
        }
        if ($ok) { Show-Page ([Math]::Min($script:PageIdx + 1, $script:Pages.Count - 1)) }
    })
    $c.btnOpenBrowser.Add_Click({ if ($script:DoneUrl) { try { Start-Process $script:DoneUrl } catch { } } })
    $c.btnUninstall.Add_Click({
        # Poisto kohdistuu aina OIKEAAN asennuskansioon (oletus:
        # %LOCALAPPDATA%\Huoltokello) — EI velhon omaan pakettikansioon.
        $hkDir = Join-Path $env:LOCALAPPDATA 'Huoltokello'
        $asennettu = Join-Path (Join-Path $hkDir 'Tyokalut') 'Poista-Asennus-GUI.ps1'
        $paketti = Join-Path $PackageDir 'Tyokalut\Poista-Asennus-GUI.ps1'
        if (Test-Path $asennettu) {
            # Asennetun kansion tyokalu loytaa asennuskansion oikein itse
            $argStr = '-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f $asennettu
        } elseif (Test-Path $paketti) {
            # Paketin tyokalulle osoitetaan asennuskansio erikseen
            $argStr = '-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -InstallDir "{1}"' -f $paketti, $hkDir
        } else { return }
        try { Start-Process powershell -ArgumentList $argStr -Wait } catch { }
        # Jos asennus poistettiin, piilota varoitus ja painike
        if (-not (Test-Path (Join-Path $hkDir 'AppData\huoltokello.db'))) {
            $c.ExistingWarn.Visibility = 'Collapsed'
            $c.btnUninstall.Visibility = 'Collapsed'
        }
    })
    $c.btnOpenHelp.Add_Click({
        $ohje = Join-Path (Get-Settings).InstallDir 'Ohjeet\Kayttoonotto-Opas.html'
        if (Test-Path $ohje) { Start-Process $ohje }
    })
    $c.btnOpenFolder.Add_Click({ try { Start-Process explorer.exe (Get-Settings).InstallDir } catch { } })
    $c.btnFinish.Add_Click({ $win.Close() })

    $win.Add_Closing({
        if ($script:Installing) {
            [Windows.MessageBox]::Show('Asennus on kesken — odota kunnes se valmistuu.', 'Huoltokello', 'OK', 'Warning') | Out-Null
            $args[1].Cancel = $true
        }
    })

    # Oletusarvot
    $c.txtDir.Text = Join-Path $env:LOCALAPPDATA 'Huoltokello'
    $c.txtPort.Text = "$DefaultPort"
    $c.txtSrvPath.Text = 'C:\Huoltokello'
    $c.txtSrvPort.Text = "$DefaultPort"
    $c.txtAzName.Text = ''
    if (Test-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Huoltokello') 'AppData\huoltokello.db')) {
        $c.ExistingWarn.Visibility = 'Visible'
    }
    Show-Page 0
    $win.ShowDialog() | Out-Null
}

# ---------- Itsetesti ----------
function Test-HkSelfTest {
    $ok = $true
    $out = @()
    $out += 'HUOLTOKELLO MULTIASENNUKSEN ITSETESTI'
    $out += ('Pakettikansio: ' + $PackageDir)
    $out += ''
    $out += '1) Paketin tiedostot:'
    foreach ($p in @($AppZip, $AzureOsat, $PalvelinOsat, (Join-Path $PackageDir 'assets\huoltokello.ico'))) {
        $fileOk = Test-Path $p
        $out += ('   [{0}] {1}' -f ($(if ($fileOk) { 'OK' } else { 'PUUTTUU' })), (Split-Path -Leaf $p))
        if (-not $fileOk) { $ok = $false }
    }
    $out += ''
    $out += '2) VAPID-avainparin luonti:'
    try {
        $k = New-HkVapidKeys
        $out += ('   [OK] luotu ({0}...)' -f $k.PublicKey.Substring(0, 12))
    } catch {
        $out += ('   [PUUTTUU] ' + $_.Exception.Message); $ok = $false
    }
    $out += ''
    $out += '3) Palveluskaynnistimen luonti (Huoltokello-Palvelu.ps1):'
    try {
        $tmp = Join-Path $env:TEMP ('hk-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        New-HkServiceWrapper -StageDir $tmp -ServicePort 8080
        $svcPath = Join-Path $tmp 'Huoltokello-Palvelu.ps1'
        if (-not (Test-Path $svcPath)) { throw 'tiedostoa ei luotu' }
        if (-not ((Get-Content $svcPath -Raw).Contains('8080'))) { throw 'portin korvaus epaonnistui' }
        Remove-Item $tmp -Recurse -Force
        $out += '   [OK] luotu, portti korvattu'
    } catch {
        $out += ('   [PUUTTUU] ' + $_.Exception.Message); $ok = $false
    }
    $out += ''
    $out += '4) PowerShell-syntaksi:'
    foreach ($f in @((Join-Path $PackageDir 'Asenna-Huoltokello-Multa.ps1'), $AzureOsat, $PalvelinOsat)) {
        $errs = $null
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $f -Raw), [ref]$errs)
        if ($errs -and $errs.Count -gt 0) {
            $out += ('   [VIRHETTA] ' + (Split-Path -Leaf $f) + ' (' + $errs.Count + ' kpl)'); $ok = $false
        } else {
            $out += ('   [OK] ' + (Split-Path -Leaf $f))
        }
    }
    $out += ''
    $out += '5) Tyokalut:'
    if (-not (Test-HkAzInstalled)) { Add-HkAzPath }
    if (Test-HkAzInstalled) { $out += '   [OK] Azure CLI (az) loytyy' } else { $out += '   [HUOM] Azure CLI ei loydy - velho asentaa sen asennuksen aikana puolestasi' }
    if (Test-PortFree $Port) { $out += ('   [OK] portti ' + $Port + ' vapaana') } else { $out += ('   [HUOM] portti ' + $Port + ' on kaytossa - valitse paikalliseen asennukseen toinen (-Port)') }
    $out += ''
    $out -join "`n"
    Write-Host ''
    if ($ok) { Write-Host 'ITSETESTI: OK - paketti kayttokelpoinen' -ForegroundColor Green; exit 0 }
    else { Write-Host 'ITSETESTI: ONGELMIA - korjaa ennen jakelua' -ForegroundColor Red; exit 1 }
}
if ($SelfTest) { Test-HkSelfTest }

# ---------- Paaohjelma ----------
if ($Silent) {
    # Hiljainen asennus (testaus + edistyneet kayttajat)
    if (-not $HyvaksyLuvat) {
        Write-Host 'Hiljainen asennus vaatii -HyvaksyLuvat: annat skriptille luvan toimia puolestasi.' -ForegroundColor Red
        Write-Host '(GUI-asennus kysyy saman luvan velhossa LUVAT-sivulla.)'
        exit 2
    }
    $m = if ($Mode) { $Mode } else { 'paikallinen' }
    $missing = @()
    if (-not $AdminName) { $missing += '-AdminName' }
    if (-not $AdminEmail) { $missing += '-AdminEmail' }
    if (-not $AdminPassword) { $missing += '-AdminPassword' }
    if ($m -eq 'azure') {
        if (-not $AzName) { $missing += '-AzName' }
    } elseif ($m -eq 'serveri') {
        if (-not $ServerHost) { $missing += '-ServerHost' }
        if (-not $ServerUser) { $missing += '-ServerUser' }
        if (-not $ServerPass) { $missing += '-ServerPass' }
    }
    if ($missing.Count -gt 0) {
        Write-Host 'Hiljainen asennus vaatii puuttuvat parametrit:' -ForegroundColor Red
        Write-Host ('Puuttuvat: ' + ($missing -join ', '))
        exit 2
    }
    $pwErr = Test-HkPasswordRule $AdminPassword
    if ($pwErr) { Write-Host "Salasanavaatimus ei taydy: $pwErr" -ForegroundColor Red; exit 2 }
    if (-not (Test-Email $AdminEmail)) { Write-Host "Kelvoton sahkopostiosoite: $AdminEmail" -ForegroundColor Red; exit 2 }

    $script:hkStep = 0
    $stepPrinter = {
        param($id, $status, $detail)
        $color = 'DarkGray'
        if ($status -eq 'start') { $script:hkStep++; $color = 'Cyan' }
        elseif ($status -eq 'ok') { $color = 'Green' }
        elseif ($status -eq 'fail') { $color = 'Red' }
        $line = if ($detail) { "[$status] $id - $detail" } else { "[$status] $id" }
        Write-Host $line -ForegroundColor $color
    }

    $baseAdmin = @{
        AdminName     = $AdminName
        AdminEmail    = $AdminEmail
        AdminTitle    = if ($AdminTitle) { $AdminTitle } else { 'Vastaava' }
        AdminPassword = $AdminPassword
        OpenBrowser   = (-not $NoBrowser)
        NoShortcuts   = [bool]$NoShortcuts
        Silent        = $true
        HyvaksyLuvat  = $true
    }
    if ($m -eq 'azure') {
        $s = $baseAdmin + @{
            Mode             = 'azure'
            AzName           = $AzName.ToLower()
            AzRg             = if ($AzRg) { $AzRg } else { 'huoltokello-rg' }
            AzRegion         = if ($AzRegion) { $AzRegion } else { 'finlandiacentral' }
            AzSku            = if ($AzSku) { $AzSku } else { 'B1' }
            AzSubscriptionId = [string]$AzSubscription
        }
    } elseif ($m -eq 'serveri') {
        $s = $baseAdmin + @{
            Mode            = 'serveri'
            ServerHost      = $ServerHost
            ServerUser      = $ServerUser
            ServerPass      = $ServerPass
            ServerPath      = if ($ServerPath) { $ServerPath } else { 'C:\Huoltokello' }
            ServerPort      = $ServerPort
            ServerNotDomain = [bool]$ServerNotDomain
            MakeShortcut    = (-not $NoShortcuts)
        }
    } else {
        if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Huoltokello' }
        if (-not (Test-PortFree $Port)) { Write-Host "Portti $Port on varattu - valitse toinen (-Port)." -ForegroundColor Red; exit 2 }
        $s = $baseAdmin + @{
            Mode              = 'paikallinen'
            InstallDir        = $InstallDir
            Port              = $Port
            DesktopShortcut   = (-not $NoShortcuts)
            StartMenuShortcut = (-not $NoShortcuts)
            AutoStart         = [bool]$AutoStart
            PhoneAccess       = [bool]($PhoneAccess -or $LanAccess)
            LanAccess         = [bool]($PhoneAccess -or $LanAccess)
        }
    }

    try {
        if ($m -eq 'azure') { $r = Invoke-HkAzureInstall -s $s -OnStep $stepPrinter }
        elseif ($m -eq 'serveri') { $r = Invoke-HkServerInstall -s $s -OnStep $stepPrinter }
        else { $r = Invoke-HkInstall -s $s -OnStep $stepPrinter }
        Write-Host ''
        Write-Host 'ASENNUS VALMIS!' -ForegroundColor Green
        Write-Host ('  Osoite : ' + $r.Url)
        if ($r.Dir) { Write-Host ('  Kansio : ' + $r.Dir) }
        elseif ($r.Path) { Write-Host ('  Kansio : ' + $r.Path + ' (palvelimella)') }
        elseif ($r.AppName) { Write-Host ('  App    : ' + $r.AppName) }
        Write-Host ('  Tili   : ' + $r.Email + ' (Johto)')
        Write-Host '  Ohjeet : Ohjeet\Kayttoonotto-Opas.html'
        exit 0
    } catch {
        Write-Host ('ASENNUS EPAONNISTU: ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
} else {
    Show-HkWizard
    exit 0
}