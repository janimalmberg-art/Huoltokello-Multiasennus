# ============================================================
# HUOLTOKELLO MULTIASENNUUS - OSA-AZURE
# Asentaa Huoltokellon Microsoft Azureen kayttajan omalla
# Microsoft-tililla (Azure App Service). Kutsutaan multavelhosta;
# kayttaja on antanut LUVAT-sivulla luvan toimia tilin puolesta.
#
# Tyokalu: Azure CLI (az). Jos sita ei ole, skripti asentaa sen
# puolestasi (winget tai Microsoftin virallinen MSI + UAC).
# ============================================================

function Test-HkAzInstalled {
    try { $null = Get-Command az -ErrorAction Stop; return $true } catch { return $false }
}

function Add-HkAzPath {
    $cands = @("$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin", "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin")
    foreach ($p in $cands) {
        if (Test-Path $p) {
            if ($env:Path -notlike ("*" + $p + "*")) { $env:Path = $env:Path + ';' + $p }
        }
    }
}

# Ajaa az-komennon taustalla ja pitaa OnStep-callbackin ajan tasalla.
# Palauttaa hashtable: Exit, Out, Err.
function Invoke-HkAz {
    param(
        [string[]]$Arguments,
        [int]$TimeoutSec = 1200,
        $OnStep,
        [string]$StepId = ''
    )
    Add-HkAzPath
    $tag  = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $outF = Join-Path $env:TEMP ("hkaz-$tag.out")
    $errF = Join-Path $env:TEMP ("hkaz-$tag.err")
    $cmdLine = 'az ' + ($Arguments -join ' ') + ' > "' + $outF + '" 2> "' + $errF + '"'
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ' + $cmdLine) -WindowStyle Hidden -PassThru
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastTick = [DateTime]::MinValue
    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 400
        if ($OnStep -and $StepId) {
            if (((Get-Date) - $lastTick).TotalSeconds -ge 3) {
                $lastTick = Get-Date
                & $OnStep $StepId 'info' ("ajetaan az-komentoa: " + [string]($Arguments[0..1] -join ' ') + "  ($([int]$sw.Elapsed.TotalSeconds) s)")
            }
        }
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
            try { $proc.Kill() } catch { }
            throw ("az-komento aikakatkaistiin {0} s kuluttua: az {1}" -f $TimeoutSec, ($Arguments -join ' '))
        }
    }
    $out = if (Test-Path $outF) { Get-Content $outF -Raw -ErrorAction SilentlyContinue } else { '' }
    $err = if (Test-Path $errF) { Get-Content $errF -Raw -ErrorAction SilentlyContinue } else { '' }
    try { Remove-Item $outF, $errF -Force -ErrorAction SilentlyContinue } catch { }
    return @{ Exit = $proc.ExitCode; Out = [string]$out; Err = [string]$err }
}

# Ajaa az-komennon ja jattaa JSON-vastauksen; heittaa jos poistumiskoodi != 0.
function Invoke-HkAzJson {
    param([string[]]$Arguments, $OnStep, [string]$StepId = '', [int]$TimeoutSec = 1200)
    $r = Invoke-HkAz -Arguments $Arguments -TimeoutSec $TimeoutSec -OnStep $OnStep -StepId $StepId
    if ($r.Exit -ne 0) {
        $msg = ($r.Err.Trim() + ' ' + $r.Out.Trim()).Trim()
        if (-not $msg) { $msg = "az poistuminen: $($r.Exit)" }
        throw ("az-komento epaonnistui: az {0}`n{1}" -f ($Arguments -join ' '), $msg)
    }
    $txt = $r.Out.Trim()
    if (-not $txt) { return $null }
    try { return (ConvertFrom-Json $txt) } catch { throw ("az-vastaus ei ollut JSONia: " + $txt.Substring(0, [Math]::Min(300, $txt.Length))) }
}

function Get-HkAzAccounts {
    try {
        $acc = Invoke-HkAzJson -Arguments @('account', 'list', '--output', 'json') -TimeoutSec 120
        if ($null -eq $acc) { return @() }
        return @($acc)
    } catch { return @() }
}

# Varmistaa etta Azure CLI on kaytossa, asentaa sen tarvittaessa
# (winget tai virallinen MSI + UAC-kysely - kayttajalle jo kerrottu LUVAT-sivulla).
function Ensure-HkAzCli {
    param($OnStep)
    & $OnStep 'azure-cli' 'start' ''
    if (-not (Test-HkAzInstalled)) {
        Add-HkAzPath
    }
    if (-not (Test-HkAzInstalled)) {
        & $OnStep 'azure-cli' 'info' 'Azure CLI -tyokalua ei loytynyt - asennetaan se puolestasi (Windows saattaa kysyaa lupa)...'
        # 1) yrita wingetilla (ei vaadi UAC:ta)
        $wingetOk = $false
        try {
            $null = Get-Command winget -ErrorAction Stop
            $p = Start-Process -FilePath 'winget' -ArgumentList @('install','--id','Microsoft.AzureCLI','-e','--silent','--accept-source-agreements','--accept-package-agreements') -Wait -PassThru -WindowStyle Hidden
            $wingetOk = ($p.ExitCode -eq 0)
        } catch { }
        if ($wingetOk) { Add-HkAzPath }
        if (-not (Test-HkAzInstalled)) {
            # 2) lataa Microsoftin virallinen MSI ja asenna korotetusti (UAC-kysely kayttajalle)
            & $OnStep 'azure-cli' 'info' 'Ladataan Azure CLI:n asennuspaketti (Microsoftin virallinen jakelu)...'
            $msi = Join-Path $env:TEMP 'huoltokello-azurecli.msi'
            Invoke-WebRequest 'https://aka.ms/installazurecliwindows' -OutFile $msi -UseBasicParsing
            & $OnStep 'azure-cli' 'info' 'Azure CLI:n asennus vaatii yllapito-oikeudet - hyvaksy Windowsin lupa-kysely.'
            $pr = Start-Process msiexec.exe -ArgumentList @('/i', ('"' + $msi + '"'), '/qn', '/norestart') -Verb RunAs -Wait -PassThru
            if ($pr.ExitCode -ne 0) { throw ("Azure CLI:n asennus keskeytyi (msiexec=" + $pr.ExitCode + "). Asenna kaasin: https://aka.ms/installazurecliwindows") }
            Add-HkAzPath
        }
        if (-not (Test-HkAzInstalled)) {
            throw 'Azure CLI ei kayntynyt asennuksen jalkeenkaan. Asenna se kasin osoitteesta https://aka.ms/installazurecliwindows ja kaynnista velho uudelleen.'
        }
    }
    Add-HkAzPath
    $v = Invoke-HkAz -Arguments @('version', '--output', 'json') -TimeoutSec 180
    if ($v.Exit -ne 0) { throw ('Azuria ei voi ajaa: ' + ($v.Err.Trim())) }
    & $OnStep 'azure-cli' 'ok' 'Azure CLI valmiina'
}

# Laitteistokoodikirjautuminen Microsoft-tililla. Nayttaa koodin velhossa
# ja avaa kirjautumissivun selaimeen; odottaa ja vahvistaa onnistumisen.
function Start-HkAzDeviceLogin {
    param($OnStep)
    & $OnStep 'azure-kirjaudu' 'start' ''
    Add-HkAzPath
    $tag  = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $outF = Join-Path $env:TEMP ("hkaz-login-$tag.out")
    $errF = Join-Path $env:TEMP ("hkaz-login-$tag.err")
    $cmdLine = 'az login --use-device-code --output json > "' + $outF + '" 2> "' + $errF + '"'
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ' + $cmdLine) -WindowStyle Hidden -PassThru
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $codeShown = $false
    $lastTick = [DateTime]::MinValue
    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 500
        if (-not $codeShown) {
            $txt = ''
            try { $txt = (Get-Content $outF, $errF -Raw -ErrorAction SilentlyContinue) -join ' ' } catch { }
            if ($txt -match 'devicelogin') {
                $m = [regex]::Match($txt, 'code\s+([A-Z0-9]{5,10})')
                $code = if ($m.Success) { $m.Groups[1].Value } else { '?' }
                & $OnStep 'azure-kirjaudu' 'info' ('KOODI:' + $code)
                try { Start-Process 'https://microsoft.com/devicelogin' } catch { }
                $codeShown = $true
            }
        } else {
            if (((Get-Date) - $lastTick).TotalSeconds -ge 5) {
                $lastTick = Get-Date
                & $OnStep 'azure-kirjaudu' 'info' ('odotetaan kirjautumista selaimessa... ' + [int]$sw.Elapsed.TotalSeconds + ' s')
            }
        }
        if ($sw.Elapsed.TotalMinutes -gt 15) {
            try { $proc.Kill() } catch { }
            throw 'Microsoft-tilikirjautumista ei vahvistettu selaimessa 15 minuutin sisalla.'
        }
    }
    $out = if (Test-Path $outF) { Get-Content $outF -Raw -ErrorAction SilentlyContinue } else { '' }
    $err = if (Test-Path $errF) { Get-Content $errF -Raw -ErrorAction SilentlyContinue } else { '' }
    try { Remove-Item $outF, $errF -Force -ErrorAction SilentlyContinue } catch { }
    if ($proc.ExitCode -ne 0) {
        throw ('Microsoft-tilikirjautuminen epaonnistui: ' + [string]$err.Trim())
    }
    $acc = @()
    try { $acc = @(ConvertFrom-Json ([string]$out)) } catch { }
    if ($acc.Count -eq 0) { throw 'Kirjautuminen ei tuottanut Azure-tilitietoja.' }
    & $OnStep 'azure-kirjaudu' 'ok' ('Kirjautuminen ok: ' + $acc[0].user.name)
    return $acc[0]
}

# Kirjautumistarkistus: kayttaa olemassa olevan istunnon, jos sellainen on; tarvittaessa
# muutoin kaynnistaa laitteistokoodikirjautumisen.
function Request-HkAzLogin {
    param($OnStep, [switch]$AlwaysNew)
    if (-not $AlwaysNew) {
        $acc = Get-HkAzAccounts
        if ($acc.Count -gt 0) {
            & $OnStep 'azure-kirjaudu' 'ok' ('Jo kirjautunut: ' + $acc[0].user.name + ' - kaytetaan olemassa olevaa istuntoa')
            return $acc[0]
        }
    }
    return Start-HkAzDeviceLogin -OnStep $OnStep
}
# Valitsee App Servicen .NET-runtime (itseriittava EXE ei tarvitse .NET-
# ajonaikaa palvelimelta, mutta stack-asetusta tarvitaan IIS-integraatioon).
function Get-HkAzRuntime {
    try {
        $list = Invoke-HkAzJson -Arguments @('webapp', 'list-runtimes', '--os', 'windows', '--output', 'json') -TimeoutSec 180
        if ($null -eq $list) { return 'DOTNET:8' }
        $arr = @($list)
        $pick = $arr | Where-Object { $_ -match '^dotnet:8' } | Select-Object -First 1
        if (-not $pick) { $pick = $arr | Where-Object { $_ -match '^dotnet' } | Select-Object -First 1 }
        if ($pick) { return [string]$pick }
    } catch { }
    return 'DOTNET:8'
}

# ============================================================
# YKSITTAINEN ASENNUS: MICROSOFT AZURE (kayttajan Microsoft-tili)
# s = asetukset (AzName, AzRg, AzRegion, AzSku, AzSubscription,
#     AzSubscriptionId, AdminName/Email/Title/Password)
# ============================================================
function Invoke-HkAzureInstall {
    param([hashtable]$s, [scriptblock]$OnStep)

    $appName = $s.AzName.Trim().ToLower()
    $rg      = $s.AzRg.Trim()
    $region  = $s.AzRegion
    $sku     = if ($s.AzSku) { $s.AzSku } else { 'B1' }
    $planName = ('plan-' + $appName)
    if ($planName.Length -gt 60) { $planName = $planName.Substring(0, 60) }
    $url = "https://$appName.azurewebsites.net"

    # --- 1) Azure CLI ---
    Ensure-HkAzCli -OnStep $OnStep

    # --- 2) Kirjautuminen Microsoft-tililla (puolesta, lupa annettu) ---
    $account = Request-HkAzLogin -OnStep $OnStep

    # --- 3) Tilaus ---
    & $OnStep 'azure-tilaus' 'start' ''
    if ($s.AzSubscriptionId) {
        $r = Invoke-HkAz -Arguments @('account', 'set', '--subscription', $s.AzSubscriptionId) -TimeoutSec 180
        if ($r.Exit -ne 0) { throw ('Tilauksen valinta epaonnistui: ' + $r.Err.Trim()) }
    }
    $sub = Invoke-HkAzJson -Arguments @('account', 'show', '--output', 'json') -TimeoutSec 180
    & $OnStep 'azure-tilaus' 'ok' ('Tilaus: ' + $sub.name)

    # --- 4) Resurssiryhma ja palvelupaketti ---
    & $OnStep 'azure-resurssit' 'start' ''
    $g = Invoke-HkAz -Arguments @('group', 'show', '--name', $rg) -TimeoutSec 180
    if ($g.Exit -ne 0) {
        $g = Invoke-HkAz -Arguments @('group', 'create', '--name', $rg, '--location', $region) -TimeoutSec 300
        if ($g.Exit -ne 0) { throw ('Resurssiryhman luonti epaonnistui: ' + $g.Err.Trim()) }
        & $OnStep 'azure-resurssit' 'info' ('Resurssiryhma luotu: ' + $rg)
    } else {
        & $OnStep 'azure-resurssit' 'info' ('Resurssiryhma oli jo olemassa: ' + $rg)
    }
    $p = Invoke-HkAz -Arguments @('appservice', 'plan', 'show', '--resource-group', $rg, '--name', $planName) -TimeoutSec 180
    if ($p.Exit -ne 0) {
        $p = Invoke-HkAz -Arguments @('appservice', 'plan', 'create', '--resource-group', $rg, '--name', $planName, '--sku', $sku) -TimeoutSec 600
        if ($p.Exit -ne 0) { throw ('Palvelupaketin luonti epaonnistui: ' + $p.Err.Trim()) }
        & $OnStep 'azure-resurssit' 'info' ('Palvelupaketti luotu, hintataso: ' + $sku)
    } else {
        & $OnStep 'azure-resurssit' 'info' ('Palvelupaketti oli jo olemassa: ' + $planName)
    }
    & $OnStep 'azure-resurssit' 'ok' ($rg + ' / ' + $planName)

    # --- 5) Sovelluksen luonti ---
    & $OnStep 'azure-sivusto' 'start' ''
    try {
        $null = Resolve-DnsName ("$appName.azurewebsites.net") -ErrorAction Stop
        & $OnStep 'azure-sivusto' 'info' "Huom: nimelle loytyy jo DNS-tietue - jos luonti epaonnistuu nimikonain uudelleenkaa."
    } catch { }
    $runtime = Get-HkAzRuntime
    $r = Invoke-HkAz -Arguments @('webapp', 'create', '--resource-group', $rg, '--name', $appName, '--plan', $planName, '--runtime', $runtime) -TimeoutSec 900
    if ($r.Exit -ne 0) {
        $errTxt = $r.Err.Trim()
        if ($errTxt -match 'already exists|already taken|reserved') {
            throw ("Nimi '$appName' on jo varattu Azureen. Kayta toista sovelluksen nimea (esim. huoltokello-firmanne).`n$errTxt")
        }
        throw ('Sovelluksen luonti epaonnistui: ' + $errTxt)
    }
    & $OnStep 'azure-sivusto' 'ok' ($url + "  (runtime: $runtime)")
    # --- 6) Ohjelmapaketin valmistelu (tyhja asennus + yllapitajatili) ---
    $keys = New-HkVapidKeys           # uusi asennuskohtainen avainpari (ymparistoasetuksiin)
    $pkg = New-HkAppPackage -Mode 'azure' `
        -AdminName $s.AdminName -AdminEmail $s.AdminEmail -AdminTitle $s.AdminTitle -AdminPassword $s.AdminPassword `
        -OnStep $OnStep

    # --- 7) Sovellusasetukset: HTTPS, HTTP/2, avaimet (ymparistoasetukset) ---
    & $OnStep 'azure-asetukset' 'start' ''
    $settingsArgs = @('webapp', 'config', 'appsettings', 'set', '--resource-group', $rg, '--name', $appName, '--settings',
        'ASPNETCORE_ENVIRONMENT=Production', 'SeedDemoData=False',
        ('Vapid__Subject=mailto:info@huoltokello.fi'),
        ('Vapid__PublicKey=' + $keys.PublicKey),
        ('Vapid__PrivateKey=' + $keys.PrivateKey))
    $r = Invoke-HkAz -Arguments $settingsArgs -TimeoutSec 600
    if ($r.Exit -ne 0) { throw ('Sovellusasetusten tallennus epaonnistui: ' + $r.Err.Trim()) }
    $r = Invoke-HkAz -Arguments @('webapp', 'update', '--resource-group', $rg, '--name', $appName, '--https-only', 'true') -TimeoutSec 300
    if ($r.Exit -ne 0) { & $OnStep 'azure-asetukset' 'info' 'HTTPS-pakotusta ei voitu kytkea (kytke myohemmin Azure-portaalissa).' }
    $r = Invoke-HkAz -Arguments @('webapp', 'config', 'set', '--resource-group', $rg, '--name', $appName, '--http2-enabled', 'true') -TimeoutSec 300
    if ($r.Exit -ne 0) { & $OnStep 'azure-asetukset' 'info' 'HTTP/2:a ei voitu kytkea.' }
    if ($sku -ne 'F1') {
        $r = Invoke-HkAz -Arguments @('webapp', 'config', 'set', '--resource-group', $rg, '--name', $appName, '--always-on', 'true') -TimeoutSec 300
        if ($r.Exit -eq 0) { & $OnStep 'azure-asetukset' 'info' 'Always On kytketty paalle.' }
    }
    & $OnStep 'azure-asetukset' 'ok' 'HTTPS-pakotus, HTTP/2 ja VAPID-avaimet tallennettu'

    # --- 8) Vienti Azureen (zip-deploy) ---
    & $OnStep 'azure-vienti' 'start' ''
    $r = Invoke-HkAz -Arguments @('webapp', 'deploy', '--resource-group', $rg, '--name', $appName, '--src-path', $pkg.Zip, '--type', 'zip', '--timeout', '900') -TimeoutSec 1100
    if ($r.Exit -ne 0) {
        & $OnStep 'azure-vienti' 'info' 'az webapp deploy epaonnistui - kaytetaan suoraa Kudu-vientia (vaatii lyhyen SCM-oikeuksen avauksen)...'
        Invoke-HkAzZipDeployDirect -AppName $appName -ResourceGroup $rg -ZipPath $pkg.Zip -OnStep $OnStep
    }
    $sizeMt = [Math]::Round((Get-Item $pkg.Zip).Length / 1MB, 1)
    try { Remove-Item $pkg.Zip -Force -ErrorAction SilentlyContinue } catch { }
    & $OnStep 'azure-vienti' 'ok' ("Vienti valmis ({0} Mt)" -f $sizeMt)

    # --- 9) Kaynnistys ja terveystarkistus ---
    & $OnStep 'azure-kaynnistys' 'start' ''
    $healthy = Wait-HkHealthUrl -Url $url -Seconds 600 -OnStep $OnStep -StepId 'azure-kaynnistys'
    if (-not $healthy) {
        & $OnStep 'azure-kaynnistys' 'fail' 'Sovellus ei vastannut /health-tarkistukseen 10 minuutin sisalla.'
        throw ("Sovellus ei kayntynyt Azureen. Tarkista sovelluslogit Azure-portaalista ($appName -> Log stream).")
    }
    & $OnStep 'azure-kaynnistys' 'ok' $url

    # --- 10) Varmistus ---
    & $OnStep 'azure-varmistus' 'start' ''
    $loginOk = Test-HkUrlOk -Url "$url/Account/Login"
    if (-not $loginOk) {
        & $OnStep 'azure-varmistus' 'fail' 'Kirjautumissivu ei vastannut.'
        throw 'Kirjautumissivu ei vastannut - asennus vaatii tarkistusta Azure-portaalissa.'
    }
    & $OnStep 'azure-varmistus' 'ok' 'Kirjautumissivu vastaa'
    & $OnStep 'valmis' 'ok' $url

    return @{ Ok = $true; Url = $url; AppName = $appName; Group = $rg; Region = $region; Sku = $sku; Email = [string]$account.user.name; Subscription = [string]$sub.name; Updated = $false }
}

# Suora Kudu-zip-vienti basic-tunnistautumisella (varahukku CLI-vientikaan).
function Invoke-HkAzZipDeployDirect {
    param([string]$AppName, [string]$ResourceGroup, [string]$ZipPath, $OnStep)
    $r = Invoke-HkAz -Arguments @('resource', 'update', '--resource-group', $ResourceGroup, '--name', 'scm', '--namespace', 'Microsoft.Web', '--resource-type', 'basicPublishingCredentialsPolicies', '--parent', ('sites/' + $AppName), '--set', 'properties.allow=true') -TimeoutSec 300
    if ($r.Exit -ne 0) { throw ('SCM-oikeuden avaaminen epaonnistui: ' + $r.Err.Trim()) }
    $creds = Invoke-HkAzJson -Arguments @('webapp', 'deployment', 'list-publishing-credentials', '--resource-group', $ResourceGroup, '--name', $AppName, '--output', 'json') -TimeoutSec 300
    $pair = ('{0}:{1}' -f $creds.publishingUserName, $creds.publishingPassword)
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    $null = Invoke-RestMethod -Uri ("https://$AppName.scm.azurewebsites.net/api/zipdeploy") -Method Post -Headers @{ Authorization = ('Basic ' + $token) } -ContentType 'application/zip' -InFile $ZipPath -TimeoutSec 1500
}