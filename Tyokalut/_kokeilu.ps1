# =====================================================================
#  HUOLTOKELLO - KOKEILUVERSIO: 90 paivan kokeilujakson valvonta
# ---------------------------------------------------------------------
#  Tama tiedosto kuuluu rajoitettuun kokeiluversioon. Kokeilujakso
#  alkaa sovelluksen ensimmaisesta kaynnistyksesta ja kestaa 90 paivaa.
#  Alkupaiva tallennetaan asennuskansioon (AppData\Kokeilujakso.txt)
#  tarkisteella varustettuna. Kokeiluaikaa ei voi nollata poistamalla
#  eika muokkaamalla merkintaa: vioittunut merkinta estaa kaynnistyksen
#  (kokeiluaika ei ala alusta).
#
#  Kaynnistyksen yhteydessa paaohjelma kutsuu Test-HkKokeiluGatea.
#  Paattyneen kokeilujakson jalkeen kaynnistys estetaan ja kayttajalle
#  naytetaan ruudun keskella ikkuna, jossa kerrotaan kokeilujakson
#  paattymisesta ja kehittajan yhteystiedot:
#    Jani Malmberg (ohjelman kehittaja), jani.malmberg@gmail.com
#  Ohjelman tayden version ja lisenssit voi pyytaa sahkopostitse.
#
#  Automaattisia testioja varten ymparistomuuttuja
#  HKKOKEILU_EI_IKKUNAA=1 jattaa ikkunat nayttamatta.
# =====================================================================

$script:HkKokeiluPaivia       = 90
$script:HkKokeiluKehittaja    = 'Jani Malmberg (ohjelman kehittaja)'
$script:HkKokeiluSahkoposti   = 'jani.malmberg@gmail.com'
$script:HkKokeiluDirOverride  = ''

function Get-HkKokeiluTarkiste {
    param([string]$Alku)
    $suola = 'Hk-Multi-Kokeilujakso-v1|' + $Alku
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $tavut = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($suola))
        return ([System.BitConverter]::ToString($tavut) -replace '-', '').Substring(0, 32)
    }
    finally {
        $sha.Dispose()
    }
}

function Get-HkKokeiluMerkkiPolku {
    param([string]$InstallDir)
    return Join-Path $InstallDir 'AppData\Kokeilujakso.txt'
}

function Get-HkKokeiluTila {
    param([string]$InstallDir = '')

    if (-not $InstallDir) {
        if ($script:HkKokeiluDirOverride) {
            $InstallDir = $script:HkKokeiluDirOverride
        }
        elseif (Get-Command Get-HkInstallDir -ErrorAction SilentlyContinue) {
            try { $InstallDir = Get-HkInstallDir } catch { }
        }
        if (-not $InstallDir) { $InstallDir = Split-Path -Parent $PSScriptRoot }
    }

    $polku = Get-HkKokeiluMerkkiPolku -InstallDir $InstallDir
    $alku  = ''
    $rikki = $false

    if (Test-Path -LiteralPath $polku) {
        try {
            $sisalto = Get-Content -LiteralPath $polku -Raw -ErrorAction Stop
            if ($sisalto) { $sisalto = $sisalto.Trim() }
            $alkuAnnettu     = [regex]::Match($sisalto, 'alku=(\d{4}-\d{2}-\d{2})').Groups[1].Value
            $varmisteAnnettu = [regex]::Match($sisalto, 'varmiste=([0-9a-fA-F]{32})').Groups[1].Value
            if ($alkuAnnettu -and $varmisteAnnettu) {
                if ($varmisteAnnettu.ToLowerInvariant() -eq (Get-HkKokeiluTarkiste -Alku $alkuAnnettu)) {
                    $alku = $alkuAnnettu
                }
            }
            if ($alku) {
                try {
                    [void][datetime]::ParseExact($alku, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                }
                catch {
                    $rikki = $true
                    $alku  = ''
                }
            }
            else {
                $rikki = $true
            }
        }
        catch {
            $rikki = $true
        }
    }

    if ($rikki) {
        return @{
            InstallDir = $InstallDir
            Alku = ''
            PaiviaJaljella = 0
            Paattynyt = $true
            Uusi = $false
            Rikki = $true
        }
    }

    $uusi = $false
    if (-not $alku) {
        $alku = (Get-Date).ToString('yyyy-MM-dd')
        $uusi = $true
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $polku) | Out-Null
        $merkki = "kokeilujakso=90`r`nalku=$alku`r`nvarmiste=$(Get-HkKokeiluTarkiste -Alku $alku)"
        Set-Content -LiteralPath $polku -Value $merkki -Encoding ascii -ErrorAction SilentlyContinue
    }

    $tanaan = Get-Date
    $alkuPaiva = [datetime]::ParseExact($alku, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($alkuPaiva.Date -gt $tanaan.Date) {
        # Kello ajautunut taaksepain: kokeiluaika ei kaynnisty uudestaan,
        # kaytos on sama kuin laillisen alkupaivan tayttaessa 90 paivaa
        $jaljella = $script:HkKokeiluPaivia
    }
    else {
        $jaljella = $script:HkKokeiluPaivia - [int]($tanaan.Date - $alkuPaiva.Date).TotalDays
    }

    return @{
        InstallDir = $InstallDir
        Alku = $alku
        PaiviaJaljella = $jaljella
        Paattynyt = ($jaljella -le 0)
        Uusi = $uusi
        Rikki = $false
    }
}

function Show-HkKokeiluIkkuna {
    param([string]$Otsikko, [string[]]$Rivit)
    if ($env:HKKOKEILU_EI_IKKUNAA) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $Otsikko
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.ShowInTaskbar = $false
        $form.TopMost = $true
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 249)
        $form.ClientSize = New-Object System.Drawing.Size(520, (150 + (26 * $Rivit.Count)))
        $y = 18
        for ($i = 0; $i -lt $Rivit.Count; $i++) {
            if ([string]::IsNullOrWhiteSpace($Rivit[$i])) { $y += 10; continue }
            $label = New-Object System.Windows.Forms.Label
            $label.Text = $Rivit[$i]
            $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $label.SetBounds(20, $y, 480, 24)
            if ($i -eq 0) {
                $label.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
            }
            else {
                $label.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
            }
            $form.Controls.Add($label)
            $y += 26
        }
        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = 'OK'
        $ok.Size = New-Object System.Drawing.Size(120, 30)
        $ok.Location = New-Object System.Drawing.Point((([int]$form.ClientSize.Width / 2) - 60), ($form.ClientSize.Height - 42))
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Controls.Add($ok)
        $form.AcceptButton = $ok
        [void]$form.ShowDialog()
        $form.Dispose()
    }
    catch {
        # Ikkunan nayttaminen ei saa estaa kaynnistysta
    }
}

function Write-HkKokeiluKonsoli {
    param([string[]]$Rivit)
    Write-Host ''
    foreach ($rivi in $Rivit) {
        if ([string]::IsNullOrWhiteSpace($rivi)) { Write-Host '' }
        else { Write-Host $rivi }
    }
    Write-Host ''
}

function Get-HkKokeiluPaattynytRivit {
    param([hashtable]$Tila)
    $rivit = @()
    $rivit += 'HUOLTOKELLO - KOKEILUVERSIO (90 paivaa)'
    $rivit += ''
    $rivit += 'Kokeilujaksosi on paattynyt.'
    if ($Tila.Rikki) {
        $rivit += 'Kokeilujakson alkupaivamerkinta on vioittunut eika kokeilua voidaan jatkaa.'
    }
    else {
        $rivit += ('Kokeilujakso alkoi {0} eika ole enaa voimassa.' -f $Tila.Alku)
    }
    $rivit += 'Ohjelma ei kaynnisty kokeilujakson paatyttya.'
    $rivit += ''
    $rivit += ('Kehittaja: {0}' -f $script:HkKokeiluKehittaja)
    $rivit += ('Sahkoposti: {0}' -f $script:HkKokeiluSahkoposti)
    $rivit += ''
    $rivit += 'Ohjelman tayden version ja lisenssit voi pyytaa kehittajalta sahkopostitse.'
    $rivit += 'Paattymisikkunassa voi myos syottaa lisensiavaimen ja aktivointikoodin (Aktivointi-painike).'
    return $rivit
}

function Get-HkKokeiluTervetuloaRivit {
    param([hashtable]$Tila)
    $rivit = @()
    $rivit += 'HUOLTOKELLO - KOKEILUVERSIO (90 paivaa)'
    $rivit += ''
    $rivit += ('Tama kokeiluversio toimii {0} paivaa.' -f $script:HkKokeiluPaivia)
    $rivit += ('Kokeilujakso alkoi {0}.' -f $Tila.Alku)
    $rivit += ''
    $rivit += ('Kehittaja: {0}' -f $script:HkKokeiluKehittaja)
    $rivit += ('Sahkoposti: {0}' -f $script:HkKokeiluSahkoposti)
    $rivit += ''
    $rivit += 'Kokeilujakson paattymisesta ilmoitetaan erikseen ohjelman kaynnistyessa.'
    $rivit += 'Ohjelman tayden version ja lisenssit voi pyytaa kehittajalta sahkopostitse.'
    return $rivit
}

function Test-HkKokeiluGate {
    param([string]$InstallDir = '')

    # LISSENSI ensin: voimassa oleva lisenssi ohittaa 90 paivan kokeilujakson.
    if (Get-Command Test-HkLisVoimassa -ErrorAction SilentlyContinue) {
        $lisTila = Get-HkLisTila
        if ($lisTila.Voimassa) {
            Write-Host ('Huoltokello lisenssi: {0} (taso {1}).' -f $lisTila.Nimi, $lisTila.Taso)
            return $true
        }
    }

    $tila = Get-HkKokeiluTila -InstallDir $InstallDir

    if ($tila.Paattynyt) {
        $rivit = Get-HkKokeiluPaattynytRivit -Tila $tila
        Write-HkKokeiluKonsoli -Rivit $rivit
        # Paattyneen kokeilujakson ikkunassa voi syottaa lisensiavaimen +
        # aktivointikoodin (kehittajalta). Onnistuneen aktivoinnin jalkeen
        # kaynnistys jatkuu heti samaan sessioon.
        if (Get-Command Show-HkLisAktivointiIkkuna -ErrorAction SilentlyContinue) {
            if (Show-HkLisAktivointiIkkuna -Rivit $rivit) {
                $uudTila = Get-HkLisTila
                if ($uudTila.Voimassa) {
                    Write-Host ('Huoltokello lisenssi aktivoitu: {0} (taso {1}).' -f $uudTila.Nimi, $uudTila.Taso)
                    return $true
                }
            }
        }
        else {
            Show-HkKokeiluIkkuna -Otsikko 'Huoltokello - kokeilujakso paattynyt' -Rivit $rivit
        }
        return $false
    }

    if ($tila.Uusi) {
        $rivit = Get-HkKokeiluTervetuloaRivit -Tila $tila
        Write-HkKokeiluKonsoli -Rivit $rivit
        Show-HkKokeiluIkkuna -Otsikko 'Huoltokello - kokeilujakso alkoi' -Rivit $rivit
    }
    else {
        Write-Host ('Huoltokello KOKEILUVERSIO (90 paivaa): {0} paivaa jaljella.' -f $tila.PaiviaJaljella)
    }

    return $true
}
