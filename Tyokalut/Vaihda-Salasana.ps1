# Vaihda-Salasana.ps1 - unohtuneen salasanan vaihto paikalliselle Huoltokello-asennukselle.
# Ohjattu tyokalu: luo tilapaisen apu-Johto-tilin (first-admin.json), kaynnistaa sovelluksen,
# kirjautuu aputililla ja vaihtaa valitun kayttajan salasanan sovelluksen omalla
# Hallinta-lomakkeella - tietokantaan ei kosketa suoraan (hashaus ja validation jaavat sovellukselle).
#
# Kaytto (aja paketin Tyokalut-kansiosta - tyokalu etsii asennuskansion itse):
#   Vaihda-Salasana.ps1                          (ohjattu)
#   Vaihda-Salasana.ps1 -Sahkoposti kayttaja@firma.fi
#   Vaihda-Salasana.ps1 -Tarkista                (ei muuta mitaan - nayttaa tilan)
param([string]$Sahkoposti = '', [switch]$Tarkista)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_yhteinen.ps1"

# v2.7.4:n apufunktiot pakollisia - estaa ajon asennuskansion vanhalla Tyokalut-kirjastolla:
if (-not (Get-Command Test-HkPassword -ErrorAction SilentlyContinue) -or
    -not (Get-Command Protect-HkSecretFile -ErrorAction SilentlyContinue)) {
  throw "Vanha Tyokalut\_yhteinen.ps1 - aja tyokalu asennuspaketin Tyokalut-kansiosta (esim. C:\Users\<tunus>\Desktop\Huoltokello-Multiasennus\Tyokalut), ei asennuskansiosta."
}

$dir  = Get-HkInstallDir
$port = Get-HkPort
$base = "http://127.0.0.1:$port"
$exe  = Join-Path $dir 'KiinteistoHuolto.Web.exe'
$db   = Join-Path $dir 'AppData\huoltokello.db'
if (-not (Test-Path $exe)) { throw "Huoltokelloa ei loytynyt kansioosta $dir" }

function Get-Plain([string]$p) { ConvertTo-PlainText (Read-Host $p -AsSecureString) }
function Get-Html([string]$url, $sess) { Invoke-WebRequest $url -WebSession $sess -UseBasicParsing -TimeoutSec 25 }
function Get-Token([string]$html) {
  $m = [regex]::Match($html, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"')
  if (-not $m.Success) { throw 'Kirjautumislomakkeelta ei loytynyt tietoturvatahtea.' }
  $m.Groups[1].Value
}
function New-Login([string]$email, [string]$pw) {
  $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $lp = Get-Html "$base/Account/Login" $s
  $tk = Get-Token $lp.Content
  $r = Invoke-WebRequest "$base/Account/Login" -Method Post -WebSession $s -UseBasicParsing -TimeoutSec 25 `
       -Body @{ Email = $email; Password = $pw; RememberMe = 'false'; __RequestVerificationToken = $tk }
  [pscustomobject]@{ Session = $s; Response = $r }
}
# Kirjautumismenestyksen tunnistus: /Account/Login ei enaa palauta lomaketta kirjautuneena
# (siirtyy etusivulle = uudelleenohjaus), ja sesiolle jaotuu AspNetCore-evaste.
function Test-Logged([string]$email, [string]$pw) {
  try {
    $l = New-Login $email $pw
    $redirect = $false
    try {
      $null = Invoke-WebRequest "$base/Account/Login" -WebSession $l.Session -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 25
    } catch { $redirect = $true }
    $hasCookie = $false
    foreach ($c in $l.Session.Cookies.GetCookies($base)) { if ($c.Name -like '*AspNetCore*') { $hasCookie = $true } }
    return ($redirect -or $hasCookie)
  } catch { return $false }
}
function Get-KayttajaSahkopostit {
  # Tietokantaluku ajetaan pwsh:lla (PowerShell 7): Microsoft.Data.Sqlite ei lataudu PS 5.1:iin.
  if (-not (Test-Path $db)) { return @() }
  $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if (-not $pwsh) { return @() }
  try {
    $out = & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '_lue-tunnukset.ps1') -InstallDir $dir 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return @($out | Where-Object { $_ -match '@' } | Sort-Object -Unique) }
  } catch { }
  return @()
}
# Palauttaa lomakkeen kaikki input- ja select-kentat sita muuttamatta (paitsi Password, joka sytteetaan uudelleen).
function Get-FormFields([string]$html) {
  $fields = [ordered]@{}
  foreach ($im in [regex]::Matches($html, '<input\b[^>]*>')) {
    $tag = $im.Value
    $n = [regex]::Match($tag, 'name\s*=\s*"([^"]*)"').Groups[1].Value
    if (-not $n) { continue }
    $t = [regex]::Match($tag, 'type\s*=\s*"([^"]*)"').Groups[1].Value.ToLower()
    if ($t -in @('submit','button','file','image')) { continue }
    if ($t -eq 'checkbox') {
      $fields[$n] = if ($tag -match 'checked(\s|>|=)') { 'true' } else { 'false' }
    } else {
      $fields[$n] = [Net.WebUtility]::HtmlDecode([regex]::Match($tag, 'value\s*=\s*"([^"]*)"').Groups[1].Value)
    }
  }
  foreach ($sm in [regex]::Matches($html, '<select\b[^>]*name="([^"]*)"[^>]*>((?s:.*?))</select>')) {
    $n = $sm.Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($n)) { continue }
    $opts = [regex]::Matches($sm.Groups[2].Value, '<option\b([^>]*)>([^<]*)</option>')
    if (-not $opts.Count) { continue }
    $chosen = $null
    foreach ($o in $opts) { if ($o.Groups[1].Value -match 'selected(\s|>|=)') { $chosen = $o; break } }
    if (-not $chosen) { $chosen = $opts[0] }
    $ov = [regex]::Match($chosen.Groups[1].Value, 'value\s*=\s*"([^"]*)"')
    $fields[$n] = if ($ov.Success) { [Net.WebUtility]::HtmlDecode($ov.Groups[1].Value) } else { [Net.WebUtility]::HtmlDecode($chosen.Groups[2].Value) }
  }
  return $fields
}
function Post-Form($sess, [string]$url, $fields) {
  $pairs = foreach ($k in $fields.Keys) { $k + '=' + [Uri]::EscapeDataString([string]$fields[$k]) }
  Invoke-WebRequest $url -Method Post -WebSession $sess -UseBasicParsing -TimeoutSec 30 `
    -ContentType 'application/x-www-form-urlencoded; charset=utf-8' -Body ($pairs -join '&')
}
# Etsii kayttajan muokkauslomakkeen osoitteen /Admin/Users-sivulta sahkopostin ymparilta.
function Find-EditUrl([string]$html, [string]$email) {
  $i = $html.IndexOf($email)
  while ($i -ge 0) {
    $s = [Math]::Max(0, $i - 700)
    $len = [Math]::Min(1400, $html.Length - $s)
    $lm = [regex]::Match($html.Substring($s, $len), 'href="([^"]*(UserForm|Users/Edit|Muokkaa)[^"]*)"')
    if ($lm.Success) { return [Net.WebUtility]::HtmlDecode($lm.Groups[1].Value) }
    $i = $html.IndexOf($email, $i + 1)
  }
  return $null
}

function Resolve-Url([string]$u) { if ($u.StartsWith('http')) { $u } elseif ($u.StartsWith('/')) { $base + $u } else { $u } }

# ---------------------------------------------------------------- TARKISTA-lippu
if ($Tarkista) {
  Write-Host "=== Vaihda-Salasana - tilatarkistus (ei muuta mitaan) ===" -ForegroundColor Cyan
  Write-Host ("Asennuskansio : " + $dir)
  Write-Host ("Sovellus exe  : " + (Test-Path $exe))
  Write-Host ("Portti/osoite : $port  ->  $base")
  Write-Host ("Tietokanta    : " + (Test-Path $db))
  $alive = Test-HkHealth -Port $port
  Write-Host ("Sovellus kaynnissa: $alive")
  $emails = Get-KayttajaSahkopostit
  if ($emails.Count) { Write-Host ("Tunnukset DB:ssa (" + $emails.Count + "): " + ($emails -join ', ')) }
  else { Write-Host "Tunnuksia ei saatu luettua tietokannasta (ei haittaa - sahkoposti kysytaan ohjatussa ajossa)." }
  return
}

Write-Host ""
Write-Host "=== HUOLTOKELLO - Unohtuneen salasanan vaihto ===" -ForegroundColor Cyan
Write-Host ("Asennus: $dir  ($base)")
Write-Host "Tyokalu luo tilapaisen apu-Johto-tilin, vaihtaa valitun tunnuksen salasanan"
Write-Host "sovelluksen Hallinta-lomakkeella ja kertoo kirjautumisvalmiin salasanan."
Write-Host ""

$emails = Get-KayttajaSahkopostit
if ($emails.Count) {
  Write-Host ("Tunnukset tietokannassa: " + ($emails -join ', '))
  Write-Host ""
}

do {
  if ($Sahkoposti) { $email = $Sahkoposti } else { $email = (Read-Host "Kenelle vaihdetaan salasana (sahkoposti = tunnus)").Trim() }
  if ($email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Write-Host "  Kelvoton sahkopostiosoite." -ForegroundColor Yellow; $email = ''; $Sahkoposti = '' }
} while (-not $email)
if ($emails.Count -and ($emails -notcontains $email)) {
  Write-Host "  HUOM: tunnusta ei loytynyt tietokannan listauksesta - jatketaan silti jos osoite on oikein." -ForegroundColor Yellow
}

while ($true) {
  $pw1 = Get-Plain "UUSI salasana (min 12 merkkin, suuraakkonen ja numero)"
  $err = Test-HkPassword $pw1
  if ($err) { Write-Host ("  " + $err) -ForegroundColor Yellow; continue }
  $pw2 = Get-Plain "UUSI salasana uudelleen"
  if ($pw1 -ne $pw2) { Write-Host "  Salasanat eivat tasmalle - yrita uudelleen." -ForegroundColor Yellow; continue }
  break
}

if (Test-HkHealth -Port $port) {
  Write-Host ""
  $ok = Read-Host "Sovellus on kaynnissa. Lopetetaan se ajaksi (data tallentuu automaattisesti)? (k/n)"
  if ($ok -notmatch '^[kK]') { throw "Peruttu - sovellus kaynnissa." }
  Stop-HkApp | Out-Null
  Start-Sleep -Seconds 2
}

# --- Tilapainen apu-Johto-tili -> first-admin.json
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$tempEmail = "yllapitaja-$stamp@huoltokello.local"
$chars     = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
$rng       = [System.Random]::new()
$tempPw    = 'Aa1!' + (-join (1..13 | ForEach-Object { $chars[$rng.Next($chars.Length)] }))
if (Test-HkPassword $tempPw) { throw "Apusalasanaksi muodostui hylattava arvo - aja tyokalu uudelleen." }

$appData = Join-Path $dir 'AppData'
$faPath  = Join-Path $appData 'first-admin.json'
New-Item -ItemType Directory -Force -Path $appData | Out-Null
@{
  Email    = $tempEmail
  FullName = 'Tilapainen yllapitaja (Vaihda-Salasana)'
  Title    = 'Aputili'
  Password = $tempPw
} | ConvertTo-Json | Set-Content -Path $faPath -Encoding UTF8
$null = Protect-HkSecretFile -Path $faPath
Write-Host ("Aputili kirjoitettu: $tempEmail") -ForegroundColor DarkGray

Write-Host "Kaynnistetaan Huoltokello..."
Start-HkApp -NoBrowser
if (-not (Wait-HkHealth -Port $port -Seconds 120)) {
  Write-Warning ("Sovellus ei kayntynyt. Tarkista: " + (Join-Path $appData 'app-err.log'))
  throw ("Vaihto keskeytyi - aputilin tiedot tallessa: sahkoposti $tempEmail, salasana $tempPw")
}

$adminSess = $null
for ($i = 0; $i -lt 6 -and -not $adminSess; $i++) {
  Start-Sleep -Seconds 5
  try { $adminSess = (New-Login $tempEmail $tempPw).Session } catch { $adminSess = $null }
}
if (-not $adminSess) {
  Remove-Item $faPath -Force -ErrorAction SilentlyContinue
  Write-Warning "Aputililla ei saatu kirjauduttua. Kirjaudu itse selaimessa aputililla:"
  Write-Host ("  osoite  : $base/Account/Login") -ForegroundColor Cyan
  Write-Host ("  tunnus  : $tempEmail") -ForegroundColor Cyan
  Write-Host ("  salasana: $tempPw") -ForegroundColor Cyan
  Write-Host ("  vaihda sen jalkeen: Hallinta > Kayttajat > Muokkaa ($email) > Salasana")
  exit 1
}
Write-Host "Apu-Johto-tili kunnossa." -ForegroundColor Green

# --- Salasanan vaihto sovelluksen omalla lomakkeella (muut kentat sailytetaan)
$resetOk = $false
try {
  $usersPage = Get-Html "$base/Admin/Users" $adminSess
  $editRel   = Find-EditUrl $usersPage.Content $email
  if (-not $editRel) { throw "Muokkauslinkkia ei loytynyt tunnukselle $email." }
  $editUrl = Resolve-Url $editRel
  $ef      = Get-Html $editUrl $adminSess
  $fm      = [regex]::Match($ef.Content, '<form\b[^>]*action="([^"]*)"')
  $postUrl = if ($fm.Success -and $fm.Groups[1].Value) { Resolve-Url ([Net.WebUtility]::HtmlDecode($fm.Groups[1].Value)) } else { $editUrl }
  $fields  = Get-FormFields $ef.Content
  if (-not $fields.Contains('Password')) { throw 'Lomakkeesta ei loytynyt Password-kenttaa.' }
  Write-Host ""
  Write-Host "Muutetaan vain salasanaa - muut kentat palautetaan lomakkeelta sailyttaen:"
  foreach ($k in $fields.Keys) {
    if ($k -eq 'Password') { Write-Host "  $k = (uusi salasana)" } else {
      $v = [string]$fields[$k]
      if ($v.Length -gt 40) { $v = $v.Substring(0, 40) + '...' }
      Write-Host ("  $k = $v")
    }
  }
  Write-Host ""
  $jatketaan = Read-Host "Vaihdetaanko ('$email') salasana nain? (k/n)"
  if ($jatketaan -notmatch '^[kK]') { throw 'Peruttu lomakevaiheessa.' }
  $fields['Password'] = $pw1
  $null = Post-Form $adminSess $postUrl $fields
  $resetOk = $true
} catch {
  Write-Warning ("Automaattinen vaihto ei onnistunut: " + $_.Exception.Message)
  Write-Host "Vaihda salasana itse selaimessa aputililla (tiedot alla). Muuta dataa ei ole muutettu." -ForegroundColor Yellow
  Write-Host ("  tunnus  : $tempEmail") -ForegroundColor Cyan
  Write-Host ("  salasana: $tempPw") -ForegroundColor Cyan
  Write-Host ("  polku   : $base/Admin/Users -> $email -> Muokkaa -> Salasana")
  Remove-Item $faPath -Force -ErrorAction SilentlyContinue
  exit 1
}

# --- Varmistus
if (Test-Logged $email $pw1) {
  Write-Host ""
  Write-Host "VALMIS! Salasana vaihdettu ja kirjautuminen varmistettiin onnistuneella kirjautumisella." -ForegroundColor Green
} else {
  Write-Warning "Suoraa kirjautumisvarmistusta ei saatu tehtya - kokeile kirjautumista selaimessa."
  Write-Host ("Jos uusi salasana ei kay: kirjaudu aputililla $tempEmail / (apusalasana ylla) ja vaihda kadalla.") -ForegroundColor Yellow
}

# --- Siivous: aputili pois aktiivista + first-admin.json pois
try {
  $users2 = Get-Html "$base/Admin/Users" $adminSess
  $tempRel = Find-EditUrl $users2.Content $tempEmail
  if ($tempRel) {
    $tf = Get-Html (Resolve-Url $tempRel) $adminSess
    $tm = [regex]::Match($tf.Content, '<form\b[^>]*action="([^"]*)"')
    $tUrl = if ($tm.Success -and $tm.Groups[1].Value) { Resolve-Url ([Net.WebUtility]::HtmlDecode($tm.Groups[1].Value)) } else { Resolve-Url $tempRel }
    $tFields = Get-FormFields $tf.Content
    if ($tFields.Contains('IsActive')) {
      $tFields['IsActive'] = 'false'
      $null = Post-Form $adminSess $tUrl $tFields
      Write-Host "Aputili deaktivoitu (poista se lopullisesti: Hallinta > Kayttajat)." -ForegroundColor DarkGray
    }
  }
} catch { Write-Host ("Aputilin deaktivointi ja tekematta: " + $_.Exception.Message) -ForegroundColor DarkGray }

if (Test-Path $faPath) {
  Remove-Item $faPath -Force
  Write-Host "first-admin.json poistettu." -ForegroundColor DarkGray
}

$av = Read-Host "Avataanko kirjautumissivu selaimessa? (k/o)"
if ($av -match '^[kK]') { Start-Process "$base/Account/Login" }