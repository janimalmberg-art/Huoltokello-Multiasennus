# ============================================================
# HUOLTOKELLO MULTIASENNUUS - OSA-PALVELIN
# Asentaa Huoltokellon yrityksen omaan Windows-palvelimeen
# kayttaen WinRM:aa (PowerShell-remoting) ja SMB-tiedostojakoa.
# Kayttaja antaa kaikki palvelintiedot velhossa ja luvan
# toimia puolestaan LUVAT-sivulla.
#
# Vaatimukset palvelimella: Windows Server 2016+ (tai 2012 R2 +
# PowerShell 5.1), kayttaja jolla yllapito-oikeudet,
# WinRM (PowerShell-remoting) sallittu ja jaettu hallinnollinen
# yhteenliittama (C$ / D$) kaytossa.
# ============================================================

function Get-HkServerCredential {
    param([hashtable]$s)
    if ($s.ServerPasswordSecure) {
        $pass = $s.ServerPasswordSecure
    } else {
        $pass = ConvertTo-SecureString -String ([string]$s.ServerPassword) -AsPlainText -Force
    }
    return New-Object System.Management.Automation.PSCredential ([string]$s.ServerUser), $pass
}

# Avaa UAC-korotetusti pienen korjausskriptin, joka lisaa palvelimen
# talle koneelle WSMan TrustedHosts -luetteloon (workgroup-skenaario).
function Invoke-HkServerFixTrustedHosts {
    param([string]$ComputerName, [string]$ServerUser, $OnStep)
    & $OnStep 'server-yhteys' 'info' 'Lisataan palvelimeltalle koneen TrustedHosts-luetteloon (Windows kysyy yllapitoluvan)...'
    $fix = Join-Path $env:TEMP 'huoltokello-th-fix.ps1'
    $svc = ('param($h) $cur = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value; $list = @(); if ($cur -ne ''*'') { $list = @($cur -split "," | Where-Object { $_.Trim() }) }; $h2 = $h.Trim().ToLower(); if (($list | ForEach-Object { $_.Trim().ToLower() }) -notcontains $h2) { $list += $h; Set-Item WSMan:\localhost\Client\TrustedHosts -Value ($list -join ",") -Force }')
    [IO.File]::WriteAllText($fix, $svc, (New-Object Text.UTF8Encoding $true))
    $pr = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $fix, $ComputerName) -Verb RunAs -Wait -PassThru
    if ($pr.ExitCode -ne 0) {
        throw 'TrustedHosts-korjaus peruttiin tai epaonnistui (Windowsin lupa-kysely). Voit jatkaa myohemmin tai kayttaa toimialuetunnusta.'
    }
}

# Ajaa skriptiblokin palvelimelle; heittaa selkeat ohjeet virhatilanteisiin.
function Invoke-HkServerCommand {
    param([string]$ComputerName, $Credential, [scriptblock]$Script, $Arguments = @())
    try {
        return Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock $Script -ArgumentList $Arguments -ErrorAction Stop
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'cannot be resolved|ei loytynyt|getaddrinfo|The RPC server is unavailable|connection.*refused|Connection attempted') {
            throw ("Yhteytta palvelimeen '$ComputerName' ei saatu. Tarkista nimi, verkko ja etayhteydet (WinRM 5985).`nYksityiskohta: $msg")
        }
        if ($msg -match 'access is denied|Access denied|logon failure|kielletty|authentication') {
            throw ("Tunnistautuminen palvelimelle epaonnistui. Tarkista kayttajatunnus ja salasana, ja varmista etta kayttajalla on palvelimen yllapito-oikeudet.`nYksityiskohta: $msg")
        }
        if ($msg -match 'winrm|wsman|cannot be found.*session|remoting') {
            throw ("PowerShell-remoting (WinRM) ei ole kaytossa palvelimella '$ComputerName'.`n`nSalli se palvelimella nain:`n  1) Kirjaudu palvelimelle paikallisesti yllapitajana.`n  2) Kaynnista PowerShell jarjestelmanvalvojana.`n  3) Aja: Enable-PSRemoting -Force`nLisatietoja: Ohjeet\Multiasennus-Opas.html, luku 4.`n`nYksityiskohta: $msg")
        }
        throw ("Palvelinoperaatio epaonnistui: $msg")
    }
}
# ============================================================
# YKSITTAINEN ASENNUS: YRITYKSEN OMA WINDOWS-PALVELIN
# s = asetukset (ServerHost, ServerUser, ServerPassword/Secure,
#     ServerPath, ServerPort, ServerNotDomain, MakeShortcut,
#     AdminName/Email/Title/Password)
# ============================================================
function Invoke-HkServerInstall {
    param([hashtable]$s, [scriptblock]$OnStep)

    $hostName = $s.ServerHost.Trim()
    $path     = $s.ServerPath.Trim().TrimEnd('\')
    $port     = [int]$s.ServerPort
    $url      = ('http://{0}:{1}' -f $hostName, $port)
    $cred     = Get-HkServerCredential -s $s

    # --- 1) yhteys ja paikanna olemassa oleva asennus ---
    & $OnStep 'server-yhteys' 'start' ''
    if ($s.ServerNotDomain) { Invoke-HkServerFixTrustedHosts -ComputerName $hostName -ServerUser $s.ServerUser -OnStep $OnStep }
    $remote = Invoke-HkServerCommand -ComputerName $hostName -Credential $cred -Script {
        param($p)
        $existsExe = Test-Path (Join-Path $p 'KiinteistoHuolto.Web.exe')
        $data = Join-Path $p 'AppData\huoltokello.db'
        $isUpdate = (Test-Path $data)
        $vapid = $null
        if ($isUpdate) {
            try {
                $cfg = Get-Content (Join-Path $p 'appsettings.json') -Raw | ConvertFrom-Json
                if ($cfg.Vapid -and $cfg.Vapid.PublicKey -and $cfg.Vapid.PrivateKey) { $vapid = $cfg.Vapid }
            } catch { }
        }
        @{ Name = $env:COMPUTERNAME; Exe = $existsExe; Update = $isUpdate; Vapid = $vapid }
    } -Arguments @($path)
    $isUpdate = [bool]$remote.Update
    & $OnStep 'server-yhteys' 'ok' ('Yhteys ok: {0}{1}' -f $remote.Name, $(if ($isUpdate) { ' (paivitys: aiempi asennus loytyi)' } else { ' (uusi asennus)' }))

    # --- 2) paketin valmistelu ---
    $keys = $null
    if ($isUpdate -and $remote.Vapid) { $keys = @{ Subject = 'mailto:info@huoltokello.fi'; PublicKey = [string]$remote.Vapid.PublicKey; PrivateKey = [string]$remote.Vapid.PrivateKey } }
    if ($isUpdate -and -not $keys) { & $OnStep 'pakkaus' 'info' 'Aiempia ilmoitusavaimia ei voitu lukea - uudet avaimet luodaan (vanhat selaimen ilmoitusluvat menetetaan).' }
    $pkg = New-HkAppPackage -Mode 'palvelin' `
        -AdminName $s.AdminName -AdminEmail $s.AdminEmail -AdminTitle $s.AdminTitle -AdminPassword $s.AdminPassword `
        -IsUpdate:$isUpdate -VapidKeys $keys -ServicePort $port `
        -OnStep $OnStep

    # --- 3) tiedostojen siirto (SMB) ja purku (WinRM) ---
    & $OnStep 'server-tiedostot' 'start' ''
    $null = Invoke-HkServerCommand -ComputerName $hostName -Credential $cred -Script {
        param($p, $ex)
        $proc = Get-Process -Name 'KiinteistoHuolto.Web' -ErrorAction SilentlyContinue
        if ($proc) {
            foreach ($pr in @($proc)) { if ($pr.Path -and ($pr.Path -like ($p + '*'))) { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue } }
        }
        try { $null = schtasks.exe /End /TN 'Huoltokello' 2>$null } catch { }
        New-Item -ItemType Directory -Force -Path $p | Out-Null
        if (-not $ex) { 'uusi' } else { 'paivitys' }
    } -Arguments @($path, $remote.Exe)
    $drive = $path.Substring(0, 1)
    $share = ("\\{0}\{1}`$" -f $hostName, $drive)
    $tempZip = Join-Path $share '_hk-stage.zip'
    try {
        Copy-Item $pkg.Zip $tempZip -ErrorAction Stop
    } catch {
        throw ("Tiedostojen kopiointi palvelimeen epaonnistui ($share). Tarkista etta kayttajalla on yllapito-oikeudet, ja etta jaettu hallinnollinen yhteenliittama ({0}) on sallittu.`nYksityiskohta: {1}" -f ("{0}`$ -asema" -f $drive), $_.Exception.Message)
    }
    $count = Invoke-HkServerCommand -ComputerName $hostName -Credential $cred -Script {
        param($p, $z)
        Expand-Archive -Path $z -DestinationPath $p -Force -ErrorAction Stop
        Remove-Item $z -Force
        (Get-ChildItem -Path $p -Recurse -File | Measure-Object).Count
    } -Arguments @($path, 'C:\_hk-stage.zip'.Replace('C', $drive))
    try { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item $pkg.Zip -Force -ErrorAction SilentlyContinue } catch { }
    & $OnStep 'server-tiedostot' 'ok' ('{0} tiedostoa paivitetty palvelimella ({1})' -f $count, $path)
    # --- 4) salaisuudet: ACL-lukitus yllapito-/jarjestelmalle ---
    & $OnStep 'server-ajo' 'start' ''
    $null = Invoke-HkServerCommand -ComputerName $hostName -Credential $cred -Script {
        param($p)
        $prod = Join-Path $p 'appsettings.Production.json'
        if (Test-Path $prod) {
            & icacls.exe @($prod, '/inheritance:r') | Out-Null
            & icacls.exe @($prod, '/grant:r', '*S-1-5-32-544:F') | Out-Null
            & icacls.exe @($prod, '/grant:r', '*S-1-5-18:F') | Out-Null
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $p 'AppData') | Out-Null
        'ok'
    } -Arguments @($path)
    & $OnStep 'server-ajo' 'ok' 'appsettings.Production.json lukittu vain yllapidolle, tietokanta valmiina'

    # --- 5) palomuurisaanto (TCP-portti) ---
    & $OnStep 'server-palomuuri' 'start' ''
    $null = Invoke-HkServerCommand -ComputerName $hostName -Credential $cred -Script {
        param($port)
        $null = netsh.exe @('advfirewall', 'firewall', 'delete', 'rule', 'name=Huoltokello-Palvelin') 2>$null
        $null = netsh.exe @('advfirewall', 'firewall', 'add', 'rule', 'name=Huoltokello-Palvelin', 'dir=in', 'action=allow', 'protocol=TCP', ('localport=' + $port)) 
        'ok'
    } -Arguments @($port)
    & $OnStep 'server-palomuuri' 'ok' ("TCP " + $port + " sallittu saapuvalle liikenteelle (Huoltokello-Palvelin)")

    # --- 6) tehtava-ajastus: Huoltokello-Palvelu, yllapitajana SYSTEM, ONSTART ---
    & $OnStep 'server-ajastus' 'start' ''
    $null = Invoke-HkServerCommand -ComputerName $hostName -Credential $cred -Script {
        param($p)
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $p 'Huoltokello-Palvelu.ps1') + '"')
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $null = Register-ScheduledTask -TaskName 'Huoltokello-Palvelu' -Action $action -Trigger $trigger -User 'SYSTEM' -RunLevel Highest -Force -ErrorAction Stop
        Start-ScheduledTask -TaskName 'Huoltokello-Palvelu'
        'ok'
    } -Arguments @($path)
    & $OnStep 'server-ajastus' 'ok' 'Tehtava-ajastus Huoltokello-Palvelu kirjattu (jarjestelma tili, kaynnistyy koneen annistuessa)'

    # --- 7) kaynnistys + terveystarkistus ---
    & $OnStep 'server-kaynnistys' 'start' ''
    $healthy = Wait-HkHealthUrl -Url $url -Seconds 240 -OnStep $OnStep -StepId 'server-kaynnistys'
    if (-not $healthy) {
        & $OnStep 'server-kaynnistys' 'fail' ("Sovellus ei vastannut osoitteessa " + $url)
        throw ("Sovellus ei vastannut kohteessa $url. Tarkista palomuuri (TCP $port), portti ja Huoltokello-Palvelu-tehtavan loki $path\AppData\app-err.log.")
    }
    & $OnStep 'server-kaynnistys' 'ok' $url

    # --- 8) varmistus ---
    & $OnStep 'server-varmistus' 'start' ''
    $loginOk = Test-HkUrlOk -Url ($url + '/Account/Login')
    if (-not $loginOk) {
        & $OnStep 'server-varmistus' 'fail' 'Kirjautumissivu ei vastannut.'
        throw 'Kirjautumissivu ei vastannut palvelimelta - tarkista asennus palvelimen lokien perusteella.'
    }
    & $OnStep 'server-varmistus' 'ok' 'Kirjautumissivu vastaa'

    # --- 9) pikakuvake talle koneelle ---
    if ($s.MakeShortcut) {
        & $OnStep 'server-pikakuva' 'start' ''
        try {
            $desktop = [Environment]::GetFolderPath('Desktop')
            $sc = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Huoltokello.url'))
            $sc.TargetPath = $url
            $sc.Save()
            & $OnStep 'server-pikakuva' 'ok' 'Tyopoydan pikakuvake Huoltokello.url luotu'
        } catch {
            & $OnStep 'server-pikakuva' 'fail' ('Pikakuvaketta ei voitu luoda: ' + $_.Exception.Message)
        }
    }

    & $OnStep 'valmis' 'ok' $url
    return @{ Ok = $true; Url = $url; ServerName = $hostName; Path = $path; Port = $port; Email = [string]$s.AdminEmail; Updated = $isUpdate; Mode = 'palvelin' }
}