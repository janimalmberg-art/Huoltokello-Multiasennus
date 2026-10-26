# ============================================================
# Huoltokello - yhteiset apurit Tyokalut-kansion skripteille.
# Eia dot-sourata: . "$PSScriptRoot\_yhteinen.ps1"
# ============================================================

function Get-HkInstallDir {
    # 1) Kutsujan (esim. asennusvelhon) asettama ohitus voittaa aina.
    #    Tarpeellinen, koska pakettikansiosta kaynnistettyna taman
    #    skriptin sijainti EI kerro asennuskansiota.
    if ($script:HkInstallDirOverride -and (Test-Path $script:HkInstallDirOverride)) {
        return ($script:HkInstallDirOverride.TrimEnd('\'))
    }
    # 2) Asennuksen kirjaama Windowsin Sovellukset-listaus (HKCU)
    try {
        $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Huoltokello' -ErrorAction Stop
        if ($reg.InstallLocation -and (Test-Path $reg.InstallLocation)) {
            return ($reg.InstallLocation.TrimEnd('\'))
        }
    } catch { }
    # 3) Taman skriptin ylempi kansio, JOS sielta loytyy asennuksen ohjelmatiedosto
    $parent = Split-Path -Parent $PSScriptRoot
    if (Test-Path (Join-Path $parent 'KiinteistoHuolto.Web.exe')) { return $parent }
    # 4) Oletusasennuskansio (asennusvelhon oletus)
    $default = Join-Path $env:LOCALAPPDATA 'Huoltokello'
    if (Test-Path (Join-Path $default 'KiinteistoHuolto.Web.exe')) { return $default }
    # 5) Vanha logiikka viimeisena vaihtoehtona
    return $parent
}

function Get-HkPort {
    $launcher = Join-Path (Get-HkInstallDir) 'Huoltokello.ps1'
    if (Test-Path $launcher) {
        $m = [regex]::Match((Get-Content $launcher -Raw), "(?m)^\s*\`$Port\s*=\s*(\d+)")
        if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    return 8088
}

function Get-HkBind {
    $launcher = Join-Path (Get-HkInstallDir) 'Huoltokello.ps1'
    if (Test-Path $launcher) {
        $m = [regex]::Match((Get-Content $launcher -Raw), "(?m)^\s*\`$Bind\s*=\s*'([^']*)'")
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return '127.0.0.1'
}

function Test-HkHealth {
    param([int]$Port = (Get-HkPort))
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 2
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Wait-HkHealth {
    param(
        [int]$Port = (Get-HkPort),
        [int]$Seconds = 60
    )
    $tries = [Math]::Max(1, [int]($Seconds * 1000 / 700))
    for ($i = 0; $i -lt $tries; $i++) {
        if (Test-HkHealth -Port $Port) { return $true }
        Start-Sleep -Milliseconds 700
    }
    return $false
}

function Stop-HkApp {
    param([int]$WaitSeconds = 10)
    $dir = Get-HkInstallDir
    $procs = @(Get-Process -Name 'KiinteistoHuolto.Web' -ErrorAction SilentlyContinue |
             Where-Object { $_.Path -and ($_.Path -like "$dir\*") })
    if ($procs.Count -eq 0) { return $false }
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    # Odota etta prosessi varmasti loppuu — tiedostolukot vapautuvat
    # vasta prosessin paityttya. Muuten kansion poisto jaa kesken.
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        Start-Sleep -Milliseconds 400
        $left = @(Get-Process -Name 'KiinteistoHuolto.Web' -ErrorAction SilentlyContinue |
                  Where-Object { $_.Path -and ($_.Path -like "$dir\*") })
    } while ($left.Count -gt 0 -and (Get-Date) -lt $deadline)
    Start-Sleep -Milliseconds 600
    return $true
}

function Start-HkApp {
    param([switch]$NoBrowser, [int]$WaitSeconds = 60)
    $dir = Get-HkInstallDir
    $launcher = Join-Path $dir 'Huoltokello.ps1'
    if (-not (Test-Path $launcher)) { throw "Kaynnistinta ei loytynyt: $launcher" }
    & $launcher -NoBrowser:$NoBrowser
}

function New-HkShortcut {
    param(
        [string]$Path,
        [string]$TargetFile,
        [string]$Arguments = '',
        [string]$WorkingDir = '',
        [string]$IconPath = '',
        [string]$Description = ''
    )
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($Path)
    $sc.TargetPath = $TargetFile
    if ($Arguments) { $sc.Arguments = $Arguments }
    if ($WorkingDir) { $sc.WorkingDirectory = $WorkingDir }
    if ($IconPath) { $sc.IconLocation = $IconPath }
    if ($Description) { $sc.Description = $Description }
    $sc.Save()
}

function Test-HkPassword {
    param([string]$Password)
    # Samat saannot kuin sovelluksessa: min 8 merkkiä, suuraakkonen ja numero
    if ([string]::IsNullOrWhiteSpace($Password)) { return 'Salasana vaaditaan.' }
    if ($Password.Length -lt 8) { return 'Salasanan on oltava vahintaan 8 merkkiä pitkä.' }
    if ($Password -notmatch '[A-ZÄÖÜ]') { return 'Salasanassa on oltava vahintaan yksi suuraakkonen.' }
    if ($Password -notmatch '\d') { return 'Salasanassa on oltava vahintaan yksi numero.' }
    return $null
}

function ConvertTo-PlainText {
    param([System.Security.SecureString]$SecurePassword)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function New-HkVapidKeys {
    # v2.4.1: VAPID-avainparin (ES256/P-256) luonti base64url-muotoon (Web Push).
    $curve = [System.Security.Cryptography.ECCurve]::CreateFromValue('1.2.840.10045.3.1.7')
    $ec = [System.Security.Cryptography.ECDsa]::Create($curve)
    if (-not $ec) { $ec = New-Object System.Security.Cryptography.ECDsaCng -ArgumentList $curve }
    try {
        $p = $ec.ExportParameters($true)
        if (-not $p.D -or $p.D.Length -eq 0) { throw 'Yksityista avainta ei saatu vietyä.' }
        $b64u = { param([byte[]]$b) [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
        $pub = New-Object byte[] (1 + $p.Q.X.Length + $p.Q.Y.Length)
        $pub[0] = 4
        [Array]::Copy($p.Q.X, 0, $pub, 1, $p.Q.X.Length)
        [Array]::Copy($p.Q.Y, 0, $pub, 1 + $p.Q.X.Length, $p.Q.Y.Length)
        return @{ PublicKey = (& $b64u $pub); PrivateKey = (& $b64u $p.D) }
    } finally { $ec.Dispose() }
}

function Protect-HkSecretFile {
    # v2.4.1: salatiedoston ACL rajataan nykyiseen käyttäjään + SYSTEM.
    param([string]$Path)
    try {
        $id = "$env:USERDOMAIN\$env:USERNAME"
        $null = & icacls $Path /inheritance:r /grant:r "$($id):F" /grant:r "SYSTEM:F"
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}