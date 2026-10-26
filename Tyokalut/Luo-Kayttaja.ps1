# Ohjattu kayttajatilien luonti sovelluksen kautta (vaatii Johto-tilin kirjautumisen).
# Kayttaa sovelluksen omaa Hallinta > Kayttajat -lomaketta, joten salasanat hasheutuvat
# oikein eika tietokantaan kosketa suoraan.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_yhteinen.ps1"

$port = Get-HkPort
$base = "http://127.0.0.1:$port"

if (-not (Test-HkHealth -Port $port)) {
    Write-Host "Kaynnistetaan Huoltokello..."
    Start-HkApp -NoBrowser
    if (-not (Wait-HkHealth -Port $port -Seconds 90)) { throw "Huoltokello ei kayntynyt - aja ensin Tyokalut\Kaynnista.ps1" }
}

Write-Host ""
Write-Host "=== HUOLTOKELLO - Ohjattu kayttajien luonti ===" -ForegroundColor Cyan
Write-Host "Kirjaudu ensin olemassa olevalla Johto-roolin tililla"
Write-Host "(asennuksessa luotu yllapitajatili kay)."
Write-Host ""

$adminEmail = (Read-Host "Johto-tilin sahkoposti").Trim()
$adminPw = ConvertTo-PlainText (Read-Host "Salasana" -AsSecureString)

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
try {
    $loginPage = Invoke-WebRequest "$base/Account/Login" -WebSession $session -UseBasicParsing -TimeoutSec 10
} catch { throw "Sovellus ei vastannut: $base" }
$token = [regex]::Match($loginPage.Content, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"').Groups[1].Value
if (-not $token) { throw "Kirjautumissivulta ei loytynyt tietoturvatahdetta." }

$null = Invoke-WebRequest "$base/Account/Login" -Method Post -WebSession $session -UseBasicParsing -TimeoutSec 15 `
    -Body @{ Email = $adminEmail; Password = $adminPw; RememberMe = 'false'; __RequestVerificationToken = $token }

# Tarkista kirjautuminen: Johto paasee Hallinta/Kayttajat-sivulle
try {
    $null = Invoke-WebRequest "$base/Admin/Users" -WebSession $session -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 5
    $authed = $true
} catch { $authed = $false }
if (-not $authed) {
    Write-Host "Kirjautuminen epaonnistui tai tili ei ole Johto-roolissa." -ForegroundColor Red
    exit 1
}
Write-Host "Kirjautuminen OK." -ForegroundColor Green

$created = 0
while ($true) {
    Write-Host ""
    Write-Host "--- Uusi kayttaja (Enter = lopeta) ---" -ForegroundColor Cyan

    $name = (Read-Host "Koko nimi").Trim()
    if (-not $name) { break }

    do {
        $email = (Read-Host "Sahkoposti (tunnus)").Trim()
        if ($email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Write-Host "  Kelvoton sahkopostiosoite." -ForegroundColor Yellow; $email = '' }
    } while (-not $email)

    $title = (Read-Host "Tehtavanimike (valinnainen)").Trim()

    Write-Host "Rooli: [1] Tyontekija  [2] Tyonjohto  [3] Johto"
    $roleSel = Read-Host "Valitse (1-3, Enter = 1)"
    $role = switch ($roleSel) { '2' { 'Työnjohto' } '3' { 'Johto' } default { 'Työntekijä' } }

    while ($true) {
        $pw = ConvertTo-PlainText (Read-Host "Salasana (min 8 merkkiä, suuraakkonen ja numero)" -AsSecureString)
        $err = Test-HkPassword $pw
        if ($err) { Write-Host "  $err" -ForegroundColor Yellow; continue }
        break
    }

    # Hae lomake + token
    $form = Invoke-WebRequest "$base/Admin/UserForm" -WebSession $session -UseBasicParsing -TimeoutSec 10
    $t2 = [regex]::Match($form.Content, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"').Groups[1].Value

    $null = Invoke-WebRequest "$base/Admin/UserForm" -Method Post -WebSession $session -UseBasicParsing -TimeoutSec 15 `
        -Body @{
            IsNew = 'true'; FullName = $name; Email = $email; Title = $title
            Role = $role; WorkerGroupId = ''; IsActive = 'true'
            Password = $pw; __RequestVerificationToken = $t2
        }

    # Varmistus
    $usersPage = Invoke-WebRequest "$base/Admin/Users" -WebSession $session -UseBasicParsing -TimeoutSec 10
    if ($usersPage.Content -match [regex]::Escape($email)) {
        Write-Host "KAYTTAJA LUOTU: $name ($email, $role)" -ForegroundColor Green
        $created++
    } else {
        Write-Host "Kayttajaa ei havaittu listassa - tarkista Hallinta > Kayttajat selaimessa." -ForegroundColor Yellow
    }

    $again = Read-Host "Lisataanko viela toinen kayttaja? (k/o)"
    if ($again -notmatch '^[kK]') { break }
}

Write-Host ""
if ($created -gt 0) { Write-Host "Valmis - luotiin $created kayttajaa." -ForegroundColor Green }
else { Write-Host "Kayttajia ei luotu." }
$open = Read-Host "Avataanko Hallinta > Kayttajat selaimessa? (k/o)"
if ($open -match '^[kK]') { Start-Process "$base/Admin/Users" }