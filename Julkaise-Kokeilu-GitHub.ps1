# =====================================================================
# Julkaise-Kokeilu-GitHub.ps1 - Huoltokello-Multiasennuksen KOKEILU-
# VERSION julkaisija (GitHub API, janimalmberg-art).
#
# Mitka tekee:
#   1. Poistaa GITHUBISTA kaikki aiemmat releaset SEKA niiden tagit
#      (taydet asennuspaketit eivat jaa nakyviin).
#   2. Rakentaa puhtaan kokeiluasennuspaketin git-arkiston HEAD-versiosta
#      (kansio Huoltokello-Multiasennus zipin juuressa) ja lisaa siihen
#      kokeilutalousmoduulin Huoltokello-Talous-1.3.1-Kokeilu-90pv.zip.
#      Aja vasta kun muutokset on commitoitu ja pushattu mainiin!
#   3. Luo releasen v2.8.2-kokeilu ja lataa zipin liitteeksi
#      (Huoltokello-Multiasennus-2.8.2-Kokeilu-90pv.zip).
#
# Desktop-asennuspaketit jaetulla koneella eivat muutu: tama skripti
# rakentaa oman pakettinsa VAIN GitHub-julkaisulle.
#
# Kaytto:  powershell -ExecutionPolicy Bypass -File Julkaise-Kokeilu-GitHub.ps1
# Valinnaiset parametrit:
#   -EiJulkaisua     rakentaa zipin mutta ei koske GitHubia (testiajo)
#   -TalousKoeZip    polku kokeilutalousmoduuliin (oletus talousrepon
#                    kokeilu-tmp-kansio)
# =====================================================================
[CmdletBinding()]
param(
    [switch]$EiJulkaisua,
    [string]$TalousKoeZip = 'C:\Users\PC\Desktop\Huoltokello-Talous\kokeilu-tmp\Huoltokello-Talous-1.3.1-Kokeilu-90pv.zip'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-Location $PSScriptRoot

$omistaja = 'janimalmberg-art'
$arkisto = 'Huoltokello-Multiasennus'
$versio = 'v2.8.2-kokeilu'
$relNimi = 'Huoltokello-Multiasennus v2.8.2 KOKEILUVERSIO (toimii 90 paivaa)'
$zipinNimi = 'Huoltokello-Multiasennus-2.8.2-Kokeilu-90pv.zip'
$zipinPolkuKoe = 'Huoltokello-Talous-1.3.1-Kokeilu-90pv.zip'
$zipinPolkuTay = 'Huoltokello-Talous-1.1.0.zip'
$api = "https://api.github.com/repos/$omistaja/$arkisto"

# ------------------------------------------------- tunnukset (GCM)

function Get-GitHubCredential {
    $qFile = Join-Path $env:TEMP ('hk-kokeilu-multi-q-' + [IO.Path]::GetRandomFileName() + '.txt')
    $pass = $null; $user = $null
    try {
        $q = "protocol=https" + [Environment]::NewLine +
             "host=github.com" + [Environment]::NewLine +
             [Environment]::NewLine
        Set-Content -LiteralPath $qFile -Value $q -Encoding ASCII
        $rows = (cmd /c "git credential fill < ""$qFile""" 2>$null) | ForEach-Object { ($_ -replace "\r", '') }
        $pass = $rows | Where-Object { $_ -like 'password=*' } | ForEach-Object { $_.Substring(9) } | Select-Object -First 1
        $user = $rows | Where-Object { $_ -like 'username=*' } | ForEach-Object { $_.Substring(9) } | Select-Object -First 1
    } finally {
        Remove-Item -LiteralPath $qFile -Force -ErrorAction SilentlyContinue
    }
    if ([string]::IsNullOrEmpty(($pass | Out-String))) { throw 'Ei tallennettua GitHub-tunnusta.' }
    [pscustomobject]@{ Token = $pass; Username = $user }
}

$script:ApiStatus = $null
function Invoke-GhApi {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [string]$Metodi = 'Get',
        [Parameter(Mandatory)] [hashtable]$Otsakkeet,
        $Body = $null,
        [string]$SisaltoTyyppi = 'application/json'
    )
    $script:ApiStatus = $null
    $ap = @{
        Uri = $Uri; Method = $Metodi; Headers = $Otsakkeet
        ContentType = $SisaltoTyyppi; UseBasicParsing = $true; ErrorAction = 'Stop'
    }
    if ($null -ne $Body) { $ap.Body = $Body }
    try { return Invoke-RestMethod @ap }
    catch {
        if ($_.Exception.Response) {
            try { $script:ApiStatus = [int]$_.Exception.Response.StatusCode } catch { $script:ApiStatus = -1 }
        } else { $script:ApiStatus = -1 }
        return $null
    }
}

$cred = Get-GitHubCredential
$User = $cred.Username
if ([string]::IsNullOrWhiteSpace($User)) { $User = $omistaja }
$hdr = @{
    Authorization = "token $($cred.Token)"
    'User-Agent'  = 'huoltokello-kokeilu-julkaisija'
    Accept        = 'application/vnd.github+json'
}

# ------------------------------------------------- 1) vanhojen poisto

function Flatten-HkReleet {
    param($X)
    $ulos = @()
    if ($null -eq $X) { return , $ulos }
    foreach ($i in @($X)) {
        if ($i -is [System.Array]) {
            $ulos += Flatten-HkReleet $i
        }
        elseif ($null -ne $i) { $ulos += $i }
    }
    return , $ulos
}

if (-not $EiJulkaisua) {
    Write-Host 'Poistetaan GitHubista aiemmat releaset ja tagit...'
    $raaka = @(Invoke-GhApi "$api/releases?per_page=100" -Otsakkeet $hdr) | ForEach-Object { $_ }
    $releaset = Flatten-HkReleet $raaka | Where-Object { $_ -and -not [string]::IsNullOrEmpty($_.tag_name) }
    if ($releaset.Count -gt 0) {
        foreach ($r in $releaset) {
            $tag = $r.tag_name
            $null = Invoke-GhApi "$api/releases/$($r.id)" -Metodi Delete -Otsakkeet $hdr
            Write-Host ("  poistettu release: {0} (id {1}, liitteineen)" -f $tag, $r.id)
            # tagi poistetaan erikseen, etta se lakkaa nakyemasta repositoriossa
            $null = Invoke-GhApi "$api/git/refs/tags/$tag" -Metodi Delete -Otsakkeet $hdr
            if ($script:ApiStatus -eq 404) {
                # tagia ei ollut (esim. release ilman tagia) - ei haittaa
            } elseif ($script:ApiStatus -ge 200 -and $script:ApiStatus -lt 300) {
                Write-Host ("  poistettu tagi: {0}" -f $tag)
            } else {
                Write-Host ("  VAROITUS: tagin {0} poisto palautti status {1}" -f $tag, $script:ApiStatus)
            }
        }
    } else {
        Write-Host '  aiempia realeasetta ei loytynyt.'
    }
    # jaljelle jauneet orphan-tagit pois (release luodaan uudella tagilla)
    $tagitRaaka = @(Invoke-GhApi "$api/tags?per_page=100" -Otsakkeet $hdr) | ForEach-Object { $_ }
    $tagit = Flatten-HkReleet $tagitRaaka | Where-Object { $_ -and -not [string]::IsNullOrEmpty($_.name) }
    foreach ($t in $tagit) {
        $null = Invoke-GhApi "$api/git/refs/tags/$($t.name)" -Metodi Delete -Otsakkeet $hdr
        if ($script:ApiStatus -ge 200 -and $script:ApiStatus -lt 300) {
            Write-Host ("  poistettu orphan-tagi: {0}" -f $t.name)
        }
    }
}

# ------------------------------------------------- 2) paketin rakennus

Write-Host "Rakennetaan kokeilupaketti ($zipinNimi)..."

$kokeiluTy = Join-Path $PSScriptRoot 'kokeilu-tmp-multa'
if (Test-Path $kokeiluTy) { Remove-Item $kokeiluTy -Recurse -Force }
New-Item -ItemType Directory -Path $kokeiluTy | Out-Null
$root = Join-Path $kokeiluTy $arkisto
New-Item -ItemType Directory -Path $root | Out-Null

# vienti git-arkiston HEADista: ei .gitia, ei gitignore-artefakteja,
# ei tyohakemiston zippeja eika tyokansioita
$vienti = Join-Path $kokeiluTy 'vienti.zip'
git archive --format=zip --output $vienti HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive epaonnistui.' }
Expand-Archive -LiteralPath $vienti -DestinationPath $root
Remove-Item -LiteralPath $vienti -Force

# kokeiluversio (1.3.1) tilalle: tuore -TalousKoeZip aina yli, jos tarjolla;
# muuten kaytetaan repon versiota (HEAD) sellaisenaan
$tayTalous = Join-Path $root $zipinPolkuTay
if (Test-Path -LiteralPath $tayTalous) { Remove-Item -LiteralPath $tayTalous -Force }
$rootKoe = Join-Path $root $zipinPolkuKoe
if (Test-Path -LiteralPath $TalousKoeZip) {
    Copy-Item -LiteralPath $TalousKoeZip -Destination $rootKoe -Force
    Write-Host ("  talousosa: kaytettiin tuoretta kopiota: {0}" -f $TalousKoeZip)
} elseif (-not (Test-Path -LiteralPath $rootKoe)) {
    throw "Kokeilutalousmoduulia ei loytynyt zipin rakennukseen ($rootKoe, varallapulku $TalousKoeZip)."
}

# zip-rakentaja, joka kirjoittaa merkinnat aina kauttaviivoin ('/'),
# jotta paketti puretaan oikein myos ei-Windows-tyokaluilla
# (PS 5.1:n Compress-Archive kayttaa kenoviivoja)
function New-HkZip {
    param([string]$LahdeKansio, [string]$KohdeZip)
    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    $lahde = (Resolve-Path -LiteralPath $LahdeKansio).Path.TrimEnd('\')
    $juuriNimi = Split-Path -Leaf $lahde
    if (Test-Path -LiteralPath $KohdeZip) { Remove-Item -LiteralPath $KohdeZip -Force }
    $fs = [IO.File]::Open($KohdeZip, [IO.FileMode]::CreateNew)
    $ark = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $lo = Get-ChildItem -LiteralPath $lahde -Recurse -File
        foreach ($tied in $lo) {
            $rel = $tied.FullName.Substring($lahde.Length).TrimStart('\', '/')
            $nimi = $juuriNimi + '/' + ($rel -replace '\\', '/')
            $e = $ark.CreateEntry($nimi, [IO.Compression.CompressionLevel]::Optimal)
            $e.LastWriteTime = $tied.LastWriteTime
            $inn = [IO.File]::OpenRead($tied.FullName)
            $ulos = $e.Open()
            try { $inn.CopyTo($ulos) } finally { $ulos.Dispose(); $inn.Dispose() }
        }
    } finally {
        $ark.Dispose()
        $fs.Dispose()
    }
}


$zipPolku = Join-Path $kokeiluTy $zipinNimi
New-HkZip -LahdeKansio $root -KohdeZip $zipPolku
if (-not (Test-Path $zipPolku)) { throw 'Zipin luonti epaonnistui.' }
$tiivistelma = Get-FileHash -LiteralPath $zipPolku -Algorithm SHA256
Write-Host ("  valmis: {0}" -f $zipPolku)
Write-Host ("  SHA256 : {0}" -f $tiivistelma.Hash)

if ($EiJulkaisua) {
    Write-Host '-EiJulkaisua: ei kosketa GitHubia. Poistu.'
    exit 0
}

# ------------------------------------------------- 3) julkaisu

$kuvaus = @"
**Huoltokello-Multiasennus KOKEILUVERSIO v2.8.2 - toimii 90 päivää ensimmäisestä käynnistyksestä.**

- Asennus: pura zip ja käynnistä **Asenna.cmd** (asennusvelho: paikallinen kone, Microsoft Azure tai yrityksen Windows-palvelin).
- Kokeilujakso: **90 päivää** ensimmäisestä käynnistyksestä. Jaksontäytyessä ohjelma ei käynnisty ja näyttää ruudun keskellä
  ilmoituksen **"Kokeilujaksosi on päättynyt."** - kokeilussa on mukana kaikki ominaisuudet, myös talousmoduuli
  (Huoltokello-Talous 1.3.1 kokeiluversio).
- **Kehittäjä: Jani Malmberg** (ohjelman kehittäjä) - **jani.malmberg@gmail.com**
- Ohjelman ** täyden version ja lisenssit voi pyytää kehittäjältä sähköpostitse**.

Täysi versio ei ole saatavilla tässä julkaisussa - se saadaan kehittäjältä. Versiohistoria: VERSIO.txt.
"@

$relBody = @{
    tag_name         = $versio
    target_commitish = 'main'
    name             = $relNimi
    body             = $kuvaus
    draft            = $false
    prerelease       = $false
} | ConvertTo-Json

$rel = Invoke-GhApi "$api/releases" -Metodi Post -Otsakkeet $hdr -Body $relBody
if ($null -eq $rel) { throw "Releasen luonti epaonnistui (status: $($script:ApiStatus))." }
Write-Host "Release $versio luotu." -ForegroundColor Green

$upUrl = $rel.upload_url -replace '\{\?name.*?\}', "?name=$zipinNimi"
Write-Host "Lisataan liite ($zipinNimi)..."
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $zipPolku))
$asset = Invoke-GhApi $upUrl -Metodi Post -Otsakkeet $hdr -Body $bytes -SisaltoTyyppi 'application/octet-stream'
if ($null -eq $asset) { throw "Liitteen lataus epaonnistui (status: $($script:ApiStatus))." }
Write-Host 'Liite valmis.' -ForegroundColor Green
Write-Host ''
Write-Host "  Release   : $($rel.html_url)"
Write-Host "  Download  : $($asset.browser_download_url)"
Write-Host "  Tarkiste  : $($tiivistelma.Hash)"
Write-Host ("  Koko Mt   : {0}" -f [math]::Round($bytes.Length / 1MB, 1))
