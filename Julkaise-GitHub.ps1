# ============================================================
# HUOLTOKELLO-MULTIASENNUS -> GITHUB (automaattinen julkaisu)
# ============================================================
# Tama skripti tekee kaiken yhdella ajolla:
#
#   1. Tarkistaa gitin ja Git Credential Managerin
#   2. Hakee GitHub-tunnistautumisen koneen tallennetusta
#      tunnuksesta (salasanaa/tokenia EI tulosteta eika
#      tallenneta mihinkaan)
#   3. Luo GitHub-repositorion jos sita ei ole
#      (oletus: julkinen; vaihto: -Nakyvyys yksityinen)
#   4. git init + .gitignore + ensimmainen commit
#   5. Tyontaa main-haaran GitHubiin
#   6. Lisaa aihekoodit (topics) repositoriolle
#   7. Rakentaa tuoreen asennuspaketin (ZIP, mukana README + docs)
#      ja vie sen GitHub Releaseen liitteena
#
# KAYTTO (PowerShell, projektikansiossa):
#
#   powershell -ExecutionPolicy Bypass -File .\Julkaise-GitHub.ps1
#
# Valinnaiset parametrit:
#   -Nimi "Huoltokello-Multiasennus"    repositorion nimi
#   -Nakyvyys julkinen|yksityinen       repositorion nakyvyys
#   -Kuvaus "..."                       repositorion kuvaus
#   -Haara main                         tyonnettava haara
#   -EiReleasea                         ei rakenna/releasea pakettia
#
# Jos koneella EI ole tallennettua GitHub-tunnusta, skripti
# ohjeistaa kirjautumiseen (git credential-manager github login
# tai gh auth login) ja loppuu - ajan jalkeen aja uudelleen.
# ============================================================

[CmdletBinding()]
param(
    [string] $Nimi     = 'Huoltokello-Multiasennus',
    [ValidateSet('julkinen','yksityinen')]
    [string] $Nakyvyys = 'julkinen',
    [string] $Kuvaus   = 'Huoltokello - kiinteistonhuollon taktinen tyonhallinta. Moniasennuspaketti: paikallinen asennus, Microsoft Azure tai yrityksen Windows-palvelin.',
    [string] $Haara    = 'main',
    [switch] $EiReleasea
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ------------------------------------------------------------
# APUFUNKTIIOT
# ------------------------------------------------------------

function Get-GitExe {
    $g = Get-Command git -ErrorAction SilentlyContinue
    if (-not $g) {
        throw 'Git ei loytynyt polusta. Asenna se: winget install --id Git.Git -e (tai https://git-scm.com/download/win), aja sitten skripti uudelleen.'
    }
    return $g.Source
}

function Get-GitHubCredential {
    # Hakee koneen tallennetun GitHub-tunnuksen (Git Credential Manager).
    # TOKEN EI TULOSTU eika tallennu lokitiedostoon mihinkaan.
    $stdinTxt = "protocol=https`nhost=github.com`n`n"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = 'credential fill'
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    $null = $p.StandardInput.Write($stdinTxt)
    $p.StandardInput.Close()
    $taskOut = $p.StandardOutput.ReadToEndAsync()
    if (-not $taskOut.Wait(30000)) {
        try { $p.Kill() } catch {}
        throw 'Ei tallennettua GitHub-tunnusta (git credential fill ei valmistunut 30 sekunnissa).'
    }
    $out = $taskOut.Result
    $rows = $out -split "`n" | ForEach-Object { $_ -replace "`r", '' }
    $pass = $rows | Where-Object { $_ -like 'password=*' } | ForEach-Object { $_.Substring(9) }
    $user = $rows | Where-Object { $_ -like 'username=*' } | ForEach-Object { $_.Substring(9) }
    if ([string]::IsNullOrEmpty($pass)) {
        throw 'GitHub-tunnuksessa ei ole salasanaa (tokenia).'
    }
    [pscustomobject]@{ Token = $pass; Username = $user }
}

$script:ApiStatus = $null
function Invoke-GhApi {
    # Kutsuu GitHub REST APIa. Palauttaa $null virhessa ja asettaa $script:ApiStatus.
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [string]$Metodi = 'Get',
        [Parameter(Mandatory)] [hashtable]$Otsakkeet,
        $Body = $null,
        [string]$SisaltoTyyppi = 'application/json'
    )
    $script:ApiStatus = $null
    $ap = @{
        Uri           = $Uri
        Method        = $Metodi
        Headers       = $Otsakkeet
        ContentType   = $SisaltoTyyppi
        UseBasicParsing = $true
        ErrorAction   = 'Stop'
    }
    if ($null -ne $Body) { $ap.Body = $Body }
    try {
        return Invoke-RestMethod @ap
    } catch {
        if ($_.Exception.Response) {
            try { $script:ApiStatus = [int]$_.Exception.Response.StatusCode } catch { $script:ApiStatus = -1 }
        } else {
            $script:ApiStatus = -1
        }
        return $null
    }
}

# ------------------------------------------------------------
# KANSIO JA GIT-ALUSTUS
# ------------------------------------------------------------

Set-Location -LiteralPath $PSScriptRoot
Write-Host ''
Write-Host '=== HOLTOKELLO-MULTIASENNUS -> GITHUB ===' -ForegroundColor Cyan
Write-Host "Kansio:      $PSScriptRoot" -ForegroundColor Gray
Write-Host "Repositorio: $Nimi  ($Nakyvyys)" -ForegroundColor Gray
Write-Host ''

$gitExe = Get-GitExe
Write-Host "Git loyty: $gitExe" -ForegroundColor DarkGray

try {
    $ch = git config --get credential.helper 2>$null
} catch { $ch = $null }
if ([string]::IsNullOrWhiteSpace(($ch | Out-String))) {
    git config --global credential.helper manager
    Write-Host 'Asetettiin credential.helper = manager (Git Credential Manager)' -ForegroundColor DarkGray
}

# ------------------------------------------------------------
# GITHUB-TUNNISTAUTUMINEN (koneen tallennettu tunnus)
# ------------------------------------------------------------

Write-Host 'Haetaan GitHub-tunnistautuminen koneen tallennetuista tunnuksista...'
try {
    $cred = Get-GitHubCredential
} catch {
    Write-Host ''
    Write-Host ('VIRHE GitHub-tunnistautumisessa: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host (@'
Koneella ei ole kaytossa GitHub-tunnusta. Kirjauduminen komentorivilta

(suosikkiselain aukeaa -> kirjaudu -> aja taman jalkeen tama skripti uudelleen):

    git credential-manager github login

tai GitHub CLI:lla (jos asennettu):

    gh auth login
'@) -ForegroundColor Yellow
    exit 2
}

$hdr = @{
    Authorization = "token $($cred.Token)"
    'User-Agent'  = 'huoltokello-julkaisija'
    Accept        = 'application/vnd.github+json'
}

$ghMe = Invoke-GhApi 'https://api.github.com/user' -Otsakkeet $hdr
if ($null -eq $ghMe) {
    throw "GitHub-token ei kay (api-status: $script:ApiStatus). Kirjaudu uudelleen komentorivilla: git credential-manager github login   Sen jalkeen aja tama skripti uudelleen."
}
$User = $ghMe.login
$UserId = $ghMe.id
Write-Host "GitHub-tunnistautuminen OK: $User" -ForegroundColor Green

try {
    $wr = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $hdr -UseBasicParsing -ErrorAction Stop
    $sc = $wr.Headers['X-OAuth-Scopes']
    if (-not [string]::IsNullOrWhiteSpace($sc) -and $sc -notmatch 'repo') {
        Write-Warning "Tokenin oikeudet ('repo' tarkistus): $sc"
    }
} catch { }

# ------------------------------------------------------------
# GIT: INIT, IDENTITEETTI, ADD + COMMIT
# ------------------------------------------------------------

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git'))) {
    git init -b $Haara | Out-Null
    Write-Host "Git-repositorio alustettu (haara: $Haara)" -ForegroundColor Green
}

$gName = $null; $gMail = $null
try { $gName = git config --get user.name 2>$null } catch { }
try { $gMail = git config --get user.email 2>$null } catch { }
if ([string]::IsNullOrWhiteSpace(($gName | Out-String))) { git config user.name $User }
if ([string]::IsNullOrWhiteSpace(($gMail | Out-String))) {
    git config user.email ('{0}+{1}@users.noreply.github.com' -f $UserId, $User)
}

git add -A
$hasHead = $null
try { $hasHead = git rev-parse --verify HEAD 2>$null } catch { $hasHead = $null }
if ([string]::IsNullOrWhiteSpace(($hasHead | Out-String))) {
    git commit -m 'Huoltokello-Multiasennus v2.7.3: asennuspaketti, velho, tyokalut, dokumentaatio (README + docs)' | Out-Null
    Write-Host 'Ensimmoinen commit tehty.' -ForegroundColor Green
} elseif (git status --porcelain) {
    git commit -m 'Paivitys README-dokumentaatioon' | Out-Null
    Write-Host 'Muutokset commitoitu.' -ForegroundColor Green
} else {
    Write-Host 'Ei muutoksia commitoitavana.' -ForegroundColor DarkGray
}

# ------------------------------------------------------------
# GITHUB-REPOSITORION LUONTI (jos ei ole) + PUSH
# ------------------------------------------------------------

Write-Host "Tarkistetaan repositorio: $User/$Nimi ..."
$repo = Invoke-GhApi "https://api.github.com/repos/$User/$Nimi" -Otsakkeet $hdr
if ($null -eq $repo) {
    if ($script:ApiStatus -ne 404) {
        throw "Repositorion tila tarkistus epaonnistui (status: $script:ApiStatus). Token tarvitsee 'repo'-oikeuden."
    }
    $priv = ($Nakyvyys -eq 'yksityinen')
    $body = @{
        name        = $Nimi
        description = $Kuvaus
        private     = $priv
        auto_init   = $false
        has_issues  = $true
        has_wiki    = $false
    } | ConvertTo-Json
    $created = Invoke-GhApi 'https://api.github.com/user/repos' -Metodi Post -Otsakkeet $hdr -Body $body
    if ($null -eq $created -and $script:ApiStatus -ne 422) {
        throw "Repositorion luonti epaonnistui (status: $script:ApiStatus). Token tarvitsee 'repo'-oikeuden."
    }
    Write-Host "Repositorio luotu: https://github.com/$User/$Nimi" -ForegroundColor Green
} else {
    Write-Host "Repositorio on jo olemassa: https://github.com/$User/$Nimi" -ForegroundColor DarkGray
}

$remoteUrl = "https://github.com/$User/$Nimi.git"
$cur = $null
try { $cur = git remote get-url origin 2>$null } catch { }
if ([string]::IsNullOrWhiteSpace(($cur | Out-String))) {
    git remote add origin $remoteUrl
} else {
    git remote set-url origin $remoteUrl
}

Write-Host "Tyonnetaan haara $Haara GitHubiin (app.zip mukana, hetkeen menessa)..."
git push -u origin $Haara
if ($LASTEXITCODE -ne 0) {
    throw "Push epaonnistui (koodi $LASTEXITCODE). Tarkista tunnistautuminen: git credential-manager github login"
}
Write-Host 'Push OK.' -ForegroundColor Green

# ------------------------------------------------------------
# AIHEEKOODIT (TOPICS)
# ------------------------------------------------------------

$topics = @('huoltokello','kiinteistonhuolto','tyonhallinta','asennuspaketti','powershell','windows','azure','pwa','signalr','qrcode','offline','smtp')
$null = Invoke-GhApi "https://api.github.com/repos/$User/$Nimi/topics" -Metodi Put -Otsakkeet $hdr -Body (@{ names = $topics } | ConvertTo-Json)
Write-Host 'Aihekoodit (topics) lisatty.' -ForegroundColor DarkGray

# ------------------------------------------------------------
# RELEASE: ASENNUSPAKETTI (ZIP) LIITTEENA
# ------------------------------------------------------------

$rel = $null; $asset = $null
if (-not $EiReleasea) {
    # ---- versio VERSIO.txt-tiedostosta ----
    $versio = $null
    try {
        $vlhead = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSIO.txt') -TotalCount 15 -ErrorAction Stop
        foreach ($l in $vlhead) {
            if ($l -match '^(v\d+\.\d+\.\d+)') { $versio = $Matches[1]; break }
        }
    } catch { }
    if ([string]::IsNullOrWhiteSpace($versio)) { $versio = 'v2.7.3' }
    Write-Host "Luettiin versionumero: $versio"

    # ---- rakenna tuore jaettava paketti (sisalto + README + docs) ----
    $stage = Join-Path $env:TEMP 'hk-zip-ohi'
    try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    $root = Join-Path $stage 'Huoltokello-Multiasennus'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    robocopy $PSScriptRoot $root /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD ".git" ".idea" ".vscode" /XF "_julkaisu*.log" "Huoltokello-Multiasennus*.zip" ".gitignore" ".gitattributes" | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Pakkaus epaonnistui (robocopy-koodi $LASTEXITCODE)."
    }

    $zipUusi = Join-Path $env:TEMP "Huoltokello-Multiasennus-$versio.zip"
    try { Remove-Item -LiteralPath $zipUusi -Force -ErrorAction SilentlyContinue } catch { }
    Write-Host "Rakennetaan jaettava asennuspaketti: $zipUusi  (1-3 min)..."
    Compress-Archive -Path $root -DestinationPath $zipUusi -CompressionLevel Optimal
    $zipMB = [math]::Round((Get-Item -LiteralPath $zipUusi).Length / 1MB, 1)
    Write-Host "Paketti valmis ($zipMB Mt)."

    # ---- release ( jos ei jo olemassa versiotunnistteella ) ----
    $rel = Invoke-GhApi "https://api.github.com/repos/$User/$Nimi/releases/tags/$versio" -Otsakkeet $hdr
    if ($null -eq $rel) {
        $relBody = @{
            tag_name         = $versio
            target_commitish = $Haara
            name             = "Huoltokello $versio - asennuspaketti"
            body             = @"
Huoltokello-tyonhallinta moniasennuspaketti.

- Pura ja kaksoisnapsauta **Asenna.cmd** (asennusvelho)
- Kolme asennustapaa: paikallinen kone, Microsoft Azure, yrityksen Windows-palvelin
- Mukana asennusvelho (GUI + hiljainen), yllapitotyokalut, kayttoonotto-opas ja dokumentaatio
- Tyhja asennus: ei demodataa; paikallisessa kaytossa ei tarvita internetia

Muutoshistoria: repositorion **VERSIO.txt**.
"@
            draft      = $false
            prerelease = $false
        } | ConvertTo-Json
        $rel = Invoke-GhApi "https://api.github.com/repos/$User/$Nimi/releases" -Metodi Post -Otsakkeet $hdr -Body $relBody
        if ($null -ne $rel) { Write-Host "Release $versio luotu." -ForegroundColor Green }
    } else {
        Write-Host "Release $versio on jo olemassa - paivitetaan liite." -ForegroundColor DarkGray
    }

    # ---- liite (saman niminen liite poistetaan ensin) ----
    if ($null -ne $rel) {
        $zipName = Split-Path -Leaf $zipUusi
        $assets = Invoke-GhApi $rel.assets_url -Otsakkeet $hdr
        foreach ($a in @($assets)) {
            if ($a.name -eq $zipName) {
                $null = Invoke-GhApi $a.url -Metodi Delete -Otsakkeet $hdr
                Write-Host "Vanha liite poistettu: $zipName" -ForegroundColor DarkGray
            }
        }
        $upUrl = $rel.upload_url -replace '\{\?name.*?\}', "?name=$zipName"
        Write-Host "Lisataan asennuspaketti liitteeksi ($zipName, hetkeen menessa)..."
        $bytes = [System.IO.File]::ReadAllBytes($zipUusi)
        $asset = Invoke-GhApi $upUrl -Metodi Post -Otsakkeet $hdr -Body $bytes -SisaltoTyyppi 'application/octet-stream'
        if ($null -eq $asset) {
            Write-Warning "Liitteen lataus epaonnistui (status: $script:ApiStatus). Release on GitHubissa, mutta ilman pakettia."
        } else {
            Write-Host 'Asennuspaketti on nyt liitteena.' -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------
# VALMIS
# ------------------------------------------------------------

Write-Host ''
Write-Host '==============================' -ForegroundColor Green
Write-Host ' JULKAISU VALMIS             ' -ForegroundColor Green
Write-Host '==============================' -ForegroundColor Green
Write-Host ''
Write-Host "  Repositorio : https://github.com/$User/$Nimi"
if ($asset) {
    Write-Host "  Paketti     : $($asset.name)  (Release-liite)"
    Write-Host "  Download    : $($asset.browser_download_url)"
} elseif ($rel) {
    Write-Host "  Release     : $($rel.html_url)"
}
Write-Host ''
Write-Host 'Myohemmat muutokset: tavallisilla git-komennoilla:' 
Write-Host ('    git add --all ; git commit -m "kuvaus" ; git push origin ' + $Haara)
Write-Host ''
if (($Host.Name -eq 'ConsoleHost') -and (-not [System.Console]::IsInputRedirected)) {
    $null = Read-Host 'Paina Enter sulkeaksesi'
}