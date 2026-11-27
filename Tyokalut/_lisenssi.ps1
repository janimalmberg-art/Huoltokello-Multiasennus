# =====================================================================
#  HUOLTOKELLO - LISENSSIJARJESTELMA (Tyokalut\_lisenssi.ps1)
# ---------------------------------------------------------------------
#  Sama lisenssisopimus kuin Huoltokello-Talouksen licenssi.py ja
#  kehittajan Lisenssityokalu.ps1:
#
#    Lisenssiavain   25 numeroa XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
#        D1 malli(1), D2-3 taso(01..04), D4-10 sarja, D11 kesto
#        (0=ikuinen, 1..9=vuotta), D12-20 satunnainen,
#        D21-25 tiiviste = HMAC-SHA256(SALT_AVAIN, D1..D20)[0:4] mod 100000
#    Konekoodi       12 hex (XXXX-XXXX-XXXX):
#        HMAC-SHA256(SALT_KONE, "MachineGuid|C: sarjanumero|KONEEN NIMI")[:12]
#    Aktivointikoodi 12 numeroa XXXXXX-XXXXXX:
#        HMAC-SHA256(SALT_AKTIV, konekoodi + '|' + avain)[0:6] mod 10^12
#        Koodi kelpaa VAIN siille koneelle, jolle kehittaja sen laskee -
#        samaa avainta ei voi kayttaa toisessa koneessa ilman uutta koodia.
#    Lisenssitila    yhteinen tiedosto %APPDATA%\Hk-Lisenssi\lisenssi.json
#        (Hk-Lisenssi\lisenssi.json - sama tiedosto talous-ohjelmalle;
#        testialojen ohitus: HK_LISENSSI_TIEDOSTO-ymparistomuuttuja),
#        varmiste HMAC-SHA256(SALT_TILA, "avain|taso|kesto|konekoodi|
#        aktivoitu|voimassa_paattyen")[0:32]
#
#  Tasot: 01 Yritys Pieni      1 serveri,   50 tyontekijaa, johto +5
#         02 Yritys            1 serveri,  300 tyontekijaa, johto +10
#         03 Yritys Suuri      1 serveri,  900 tyontekijaa, johto +20
#         04 Yritys Enterprise 5 serveria, 2000 tyontekijaa, johto +100
#
#  Ilman lisenssia ohjelma toimii 90 paivan kokeilujaksolla (_kokeilu.ps1).
#  Voimassa oleva lisenssi ohittaa kokeilujakson. Paattyneen kokeilujakson
#  ikkunassa voi NAMASTA syottaa lisenssiavaimen + aktivointikoodin.
#
#  Ajo: . .\_lisenssi.ps1   (dot-sourataan Kaynnista.ps1:sta / velhosta)
#  Testialoiset: HKKOKEILU_EI_IKKUNAA=1 ja HK_LISENSSI_TIEDOSTO-polku.
# =====================================================================

$script:HkLisSalat = @{
    Avain = 'Hk-Lisenssi-Avain-v1|2026|Malmberg'
    Aktiv = 'Hk-Lisenssi-Aktivointi-v1|2026|Malmberg'
    Kone  = 'Hk-Konetunnus-v1|2026'
    Tila  = 'Hk-Lisenssi-Tila-v1|2026'
}

$script:HkLisTasot = @{
    '01' = @{ Nimi = 'Huoltokello Yritys Pieni';      Serverit = 1; Tyontekijat = 50;   Johto = 5 }
    '02' = @{ Nimi = 'Huoltokello Yritys';            Serverit = 1; Tyontekijat = 300;  Johto = 10 }
    '03' = @{ Nimi = 'Huoltokello Yritys Suuri';      Serverit = 1; Tyontekijat = 900;  Johto = 20 }
    '04' = @{ Nimi = 'Huoltokello Yritys Enterprise'; Serverit = 5; Tyontekijat = 2000; Johto = 100 }
}

# ------------------------------------------------- apurit

function Get-HkLisHmac {
    param([Parameter(Mandatory)] [string]$Salt, [Parameter(Mandatory)] [string]$Data)
    $h = New-Object System.Security.Cryptography.HMACSHA256
    try {
        $h.Key = [System.Text.Encoding]::UTF8.GetBytes($Salt)
        return $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Data))
    }
    finally { $h.Dispose() }
}

function Get-HkLisIntTavuista {
    param([byte[]]$Tavut, [int]$Maara)
    $v = [long]0
    for ($i = 0; $i -lt $Maara; $i++) { $v = $v * 256 + [long]$Tavut[$i] }
    return $v
}

function Get-HkLisNumerot {
    param([string]$Teksti)
    return ($Teksti -replace '[^0-9]', '')
}

function Get-HkLisHex {
    param([string]$Teksti)
    return (($Teksti.ToUpperInvariant() -replace '[^0-9A-F]', ''))
}

function Get-HkLisNakymaAvain {
    param([string]$Avain)
    $d = Get-HkLisNumerot $Avain
    if ($d.Length -ne 25) { return $Avain }
    return ($d -replace '(.{5})(?=.)', '$1-')
}

function Get-HkLisNakymaKone {
    param([string]$Konekoodi)
    $d = Get-HkLisHex $Konekoodi
    if ($d.Length -ne 12) { return $Konekoodi }
    return ($d.Substring(0, 4) + '-' + $d.Substring(4, 4) + '-' + $d.Substring(8, 4))
}

function Get-HkLisNakymaKoodi {
    param([string]$Koodi)
    $d = Get-HkLisNumerot $Koodi
    if ($d.Length -ne 12) { return $Koodi }
    return ($d.Substring(0, 6) + '-' + $d.Substring(6, 6))
}

# ------------------------------------------------- konekoodi

function Get-HkLisKonePeruste {
    $guid = ''
    try {
        $r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop
        $guid = [string]$r.MachineGuid
    } catch { }
    $vol = ''
    try {
        $ci = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $vol = [string]$ci.VolumeSerialNumber
    } catch { }
    return ("$guid|$vol|" + ([string]$env:COMPUTERNAME).ToUpperInvariant())
}

function Get-HkLisKoneKoodi {
    param([string]$Peruste = '')
    if (-not $Peruste) { $Peruste = Get-HkLisKonePeruste }
    $t = Get-HkLisHmac -Salt $script:HkLisSalat.Kone -Data $Peruste
    $hex = [System.BitConverter]::ToString($t[0..5]) -replace '-', ''
    return $hex.ToUpperInvariant()
}

# ------------------------------------------------- avain + aktivointikoodi

function Test-HkLisAvain {
    param([Parameter(Mandatory)] [string]$Avain)
    $d = Get-HkLisNumerot $Avain
    if ($d.Length -ne 25) {
        return @{ Ok = $false; Virhe = 'Avaimen on oltava 25 numeroa: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.' }
    }
    if ($d.Substring(0, 1) -ne '1') {
        return @{ Ok = $false; Virhe = 'Tuntematon malli (ensimmainen numero ei ole 1).' }
    }
    $taso = $d.Substring(1, 2)
    if (-not $script:HkLisTasot.ContainsKey($taso)) {
        return @{ Ok = $false; Virhe = "Tuntematon taso: $taso. Kaytettavat: 01, 02, 03, 04." }
    }
    $kesto = 0
    if (-not [int]::TryParse($d.Substring(10, 1), [ref]$kesto)) {
        return @{ Ok = $false; Virhe = 'Kestokentta ei ole numero.' }
    }
    $t = Get-HkLisHmac -Salt $script:HkLisSalat.Avain -Data $d.Substring(0, 20)
    $v = (Get-HkLisIntTavuista $t 4) % 100000
    if (('{0:d5}' -f $v) -ne $d.Substring(20, 5)) {
        return @{ Ok = $false; Virhe = 'Avaimen tiiviste ei tasmaa: avainta ei ole jakannut Lisenssityokalu.' }
    }
    return @{ Ok = $true; Taso = $taso; Nimi = $script:HkLisTasot[$taso].Nimi; Kesto = $kesto;
              Sarja = $d.Substring(3, 7); Numero = $d }
}

function Get-HkLisAktivointiKoodi {
    param([Parameter(Mandatory)] [string]$Konekoodi, [Parameter(Mandatory)] [string]$Avain)
    $kk = Get-HkLisHex $Konekoodi
    $av = Get-HkLisNumerot $Avain
    $t = Get-HkLisHmac -Salt $script:HkLisSalat.Aktiv -Data ($kk + '|' + $av)
    $v = (Get-HkLisIntTavuista $t 6) % 1000000000000
    return ('{0:d12}' -f $v)
}

# ------------------------------------------------- lisenssitila

function Get-HkLisTilaPolku {
    if ($env:HK_LISENSSI_TIEDOSTO) { return $env:HK_LISENSSI_TIEDOSTO }
    $kansio = Join-Path $env:APPDATA 'Hk-Lisenssi'
    return (Join-Path $kansio 'lisenssi.json')
}

function Get-HkLisTilaVarmiste {
    param([string]$Numero, [string]$Taso, [int]$Kesto, [string]$Konekoodi, [string]$Aktivoitu, [string]$Paattyen)
    $rivi = "$Numero|$Taso|$Kesto|$Konekoodi|$Aktivoitu|$Paattyen"
    $t = Get-HkLisHmac -Salt $script:HkLisSalat.Tila -Data $rivi
    $hex = ([System.BitConverter]::ToString($t)) -replace '-', ''
    return $hex.Substring(0, 32).ToLowerInvariant()
}

function Save-HkLisTilaTiedosto {
    # Tallaan lisenssitilan (sama JSON, jota talous-ohjelma lukee).
    param([hashtable]$Tila)
    $polku = Get-HkLisTilaPolku
    $kansio = Split-Path -Parent $polku
    if (-not (Test-Path -LiteralPath $kansio)) { New-Item -ItemType Directory -Path $kansio -Force | Out-Null }
    $tmp = $polku + '.tmp'
    $obj = [pscustomobject]@{
        versio = $Tila.Versio; avain = $Tila.AvainNakyma; taso = $Tila.Taso; kesto = $Tila.Kesto
        konekoodi = $Tila.Konekoodi; aktivoitu = $Tila.Aktivoitu
        voimassa_paattyen = $Tila.Paattyen; tuote = $Tila.Tuote; ohjelmat = @('talous', 'multiasennus')
        varmiste = $Tila.Varmiste
    }
    $json = $obj | ConvertTo-Json
    [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $polku) { Remove-Item -LiteralPath $polku -Force }
    Move-Item -LiteralPath $tmp -Destination $polku -Force
}

function Register-HkLisAktivointi {
    # Aktivoi avain talle koneelle; palauttaa @{Ok; Virhe; Nimi; Taso; ...}
    param([Parameter(Mandatory)] [string]$Avain, [Parameter(Mandatory)] [string]$Koodi, [string]$KonekoodiOhitus = '')
    $t = Test-HkLisAvain -Avain $Avain
    if (-not $t.Ok) { return @{ Ok = $false; Virhe = $t.Virhe } }
    $kone = Get-HkLisHex $(if ($KonekoodiOhitus) { $KonekoodiOhitus } else { Get-HkLisKoneKoodi })
    $odotettu = Get-HkLisAktivointiKoodi -Konekoodi $kone -Avain $t.Numero
    if ((Get-HkLisNumerot $Koodi) -ne $odotettu) {
        return @{ Ok = $false; Virhe = ('Aktivointikoodi ei kelpaa talle koneelle ({0}). Tarkista konekoodi ja pyyda sille oma koodi kehittajalta.' -f (Get-HkLisNakymaKone $kone)) }
    }
    $aktivoitu = (Get-Date).ToString('yyyy-MM-dd')
    if ($t.Kesto -gt 0) {
        $paattyen = ([datetime]::ParseExact($aktivoitu, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture).AddDays(365 * $t.Kesto)).ToString('yyyy-MM-dd')
    } else {
        $paattyen = 'ikuinen'
    }
    $varmiste = Get-HkLisTilaVarmiste -Numero $t.Numero -Taso $t.Taso -Kesto $t.Kesto -Konekoodi $kone -Aktivoitu $aktivoitu -Paattyen $paattyen
    $tall = @{
        Versio = 1
        AvainNakyma = Get-HkLisNakymaAvain $t.Numero
        Taso = $t.Taso; Kesto = $t.Kesto; Konekoodi = $kone
        Aktivoitu = $aktivoitu; Paattyen = $paattyen; Tuote = 'molemmat'; Varmiste = $varmiste
    }
    try { Save-HkLisTilaTiedosto -Tila $tall }
    catch { return @{ Ok = $false; Virhe = ('Lisenssitiedoston tallennus epaonnistui: {0}' -f $_.Exception.Message) } }
    $ulos = @{ Ok = $true; Nimi = $t.Nimi; Taso = $t.Taso; Konekoodi = $kone }
    foreach ($k in $tall.Keys) { $ulos[$k] = $tall[$k] }
    return $ulos
}

function Get-HkLisTila {
    # Luo ja tarkistaa: @{Voimassa; Virhe; Nimi; ...}
    param([string]$Polku = '', [string]$KonekoodiOhitus = '')
    $polkuOikea = if ($Polku) { $Polku } else { Get-HkLisTilaPolku }
    $kone = Get-HkLisHex $(if ($KonekoodiOhitus) { $KonekoodiOhitus } else { Get-HkLisKoneKoodi })
    if (-not (Test-Path -LiteralPath $polkuOikea)) {
        return @{ Voimassa = $false; Virhe = 'Ei lisenssia (kokeilujakso).' }
    }
    $raw = $null
    try {
        $raw = Get-Content -LiteralPath $polkuOikea -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return @{ Voimassa = $false; Virhe = 'Lisenssitiedosto on vioittunut.' }
    }
    $kentat = @('avain', 'taso', 'kesto', 'konekoodi', 'aktivoitu', 'voimassa_paattyen')
    foreach ($k in $kentat) {
        if (-not $raw.PSObject.Properties[$k]) {
            return @{ Voimassa = $false; Virhe = ("Lisenssitiedostossa puuttuu kentta {0}." -f $k) }
        }
    }
    $numero = Get-HkLisNumerot ([string]$raw.avain)
    $varmisteO = Get-HkLisTilaVarmiste -Numero $numero -Taso ([string]$raw.taso) -Kesto ([int]$raw.kesto) `
        -Konekoodi ([string]$raw.konekoodi) -Aktivoitu ([string]$raw.aktivoitu) -Paattyen ([string]$raw.voimassa_paattyen)
    if ([string]$raw.varmiste -ne $varmisteO) {
        return @{ Voimassa = $false; Virhe = 'Lisenssitiedoston varmiste ei tasmaa (tiedostoa on muokattu).' }
    }
    $t = Test-HkLisAvain -Avain $numero
    if (-not $t.Ok) { return @{ Voimassa = $false; Virhe = $t.Virhe } }
    if ((Get-HkLisHex ([string]$raw.konekoodi)) -ne $kone) {
        return @{ Voimassa = $false; Virhe = 'Lisenssi on aktivoitu toiselle koneelle (konekoodi ei tasmaa).' }
    }
    if ([int]$raw.kesto -gt 0) {
        $paattyy = $null
        try {
            $paattyy = [datetime]::ParseExact(([string]$raw.voimassa_paattyen), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
            return @{ Voimassa = $false; Virhe = 'Voimassaolopaiva on virheellinen.' }
        }
        if ((Get-Date).Date -gt $paattyy) {
            return @{ Voimassa = $false; Virhe = ('Lisenssi vanhentui {0}.' -f $paattyy.ToString('yyyy-MM-dd')) }
        }
    }
    return @{ Voimassa = $true; Nimi = $t.Nimi; Taso = [string]$raw.taso; AvainNakyma = ([string]$raw.avain);
              Aktivoitu = ([string]$raw.aktivoitu); Paattyen = ([string]$raw.voimassa_paattyen); Konekoodi = ([string]$raw.konekoodi) }
}

function Test-HkLisVoimassa {
    param([string]$Polku = '')
    return ((Get-HkLisTila -Polku $Polku).Voimassa)
}

# ------------------------------------------------- ikkunat (WinForms)

function Show-HkLisAktivointiIkkuna {
    # Paattyneen kokeilujakson ikkuna + lisenssikentat + AKTIVOI-painike.
    # Palauttaa $true vain, jos aktivointi juuri nyt onnistui.
    param([string[]]$Rivit)
    if ($env:HKKOKEILU_EI_IKKUNAA) { return $false }
    $status = @{ Ok = $false }
    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        Add-Type -AssemblyName System.Drawing | Out-Null
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Huoltokello - kokeilujakso paattynyt'
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.MaximizeBox = $false
        $form.StartPosition = 'CenterScreen'
        $form.ClientSize = New-Object System.Drawing.Size(660, 520)
        $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

        $y = 14
        for ($i = 0; $i -lt $Rivit.Count; $i++) {
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $Rivit[$i]
            $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $lbl.SetBounds(20, $y, 620, 24)
            if ($i -eq 0) { $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold) }
            else { $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9.5) }
            $form.Controls.Add($lbl)
            $y += 26
        }

        # konekoodi-ruutu
        $lblKone = New-Object System.Windows.Forms.Label
        $lblKone.Text = ('Taman koneen konekoodi (laheta kehittajalle):')
        $lblKone.SetBounds(30, $y + 4, 420, 20)
        $txtKone = New-Object System.Windows.Forms.TextBox
        $txtKone.SetBounds(30, $y + 26, 200, 24)
        $txtKone.ReadOnly = $true
        $txtKone.TextAlign = 'Center'
        $txtKone.Text = (Get-HkLisNakymaKone (Get-HkLisKoneKoodi))
        $btnKone = New-Object System.Windows.Forms.Button
        $btnKone.Text = 'Kopioi konekoodi'
        $btnKone.SetBounds(240, $y + 25, 130, 26)
        $form.Controls.AddRange(@($lblKone, $txtKone, $btnKone))
        $btnKone.Add_Click({ Set-Clipboard -Value $txtKone.Text })

        $y += 66
        $lblAv = New-Object System.Windows.Forms.Label
        $lblAv.Text = 'Syota lisenssiavain:'
        $lblAv.SetBounds(30, $y, 140, 22)
        $txtAv = New-Object System.Windows.Forms.TextBox
        $txtAv.SetBounds(180, $y - 2, 250, 24)
        $form.Controls.AddRange(@($lblAv, $txtAv))

        $lblKo = New-Object System.Windows.Forms.Label
        $lblKo.Text = 'Syota aktivointikoodi:'
        $lblKo.SetBounds(30, $y + 32, 140, 22)
        $txtKo = New-Object System.Windows.Forms.TextBox
        $txtKo.SetBounds(180, $y + 30, 250, 24)
        $form.Controls.AddRange(@($lblKo, $txtKo))

        $lblVirhe = New-Object System.Windows.Forms.Label
        $lblVirhe.SetBounds(30, $y + 66, 600, 34)
        $lblVirhe.ForeColor = [System.Drawing.Color]::Firebrick
        $form.Controls.Add($lblVirhe)

        $btnAkt = New-Object System.Windows.Forms.Button
        $btnAkt.Text = 'Aktivointi'
        $btnAkt.SetBounds(30, $y + 104, 120, 30)
        $btnAkt.BackColor = [System.Drawing.Color]::FromArgb(29, 78, 216)
        $btnAkt.ForeColor = [System.Drawing.Color]::White
        $form.Controls.Add($btnAkt)
        $btnAkt.Add_Click({
            $lblVirhe.Text = ''
            $ulos = Register-HkLisAktivointi -Avain $txtAv.Text -Koodi $txtKo.Text
            if ($ulos.Ok) {
                $status.Ok = $true
                $lblVirhe.ForeColor = [System.Drawing.Color]::FromArgb(21, 128, 61)
                $lblVirhe.Text = ('Lisenssi aktivoitu: {0}. Kaynnista Huoltokello uudelleen.' -f $ulos.Nimi)
                $btnAkt.Text = 'Aktivoitu'
            } else {
                $lblVirhe.ForeColor = [System.Drawing.Color]::Firebrick
                $lblVirhe.Text = $ulos.Virhe
            }
        })

        $btnSulje = New-Object System.Windows.Forms.Button
        $btnSulje.Text = 'Sulje'
        $btnSulje.SetBounds(160, $y + 104, 100, 30)
        $btnSulje.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.Add($btnSulje)
        $form.AcceptButton = $btnAkt
        $form.CancelButton = $btnSulje
        [void]$form.ShowDialog()
        $form.Dispose()
    }
    catch {
        # Ikkunan nayttaminen ei saa estaa kaynnistyksen hallintaa
    }
    return $status.Ok
}

function Show-HkLisHallintaIkkuna {
    # Asetuksien lisenssidialogi: tila, konekoodi, aktivointi / paivitys.
    if ($env:HKKOKEILU_EI_IKKUNAA) { return $false }
    $status = @{ Ok = $false }
    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        Add-Type -AssemblyName System.Drawing | Out-Null
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Huoltokello - Lisenssin hallinta'
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.MaximizeBox = $false
        $form.StartPosition = 'CenterScreen'
        $form.ClientSize = New-Object System.Drawing.Size(660, 400)
        $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

        $tila = Get-HkLisTila
        if ($tila.Voimassa) {
            $tTeksti = ('Lisenssi voimassa: {0} (taso {1}) / aktivoitu {2} / vanhentuu {3}. Sama lisenssian kelpaa Huoltokello-Talous-ohjelmalle samassa koneessa.' -f $tila.Nimi, $tila.Taso, $tila.Aktivoitu, $tila.Paattyen)
        } elseif ($tila.Virhe) {
            $tTeksti = ('Ei voimassa olevaa lisenssia: {0}' -f $tila.Virhe)
        } else {
            $tTeksti = 'Ei voimassa olevaa lisenssia - ohjelma toimii 90 paivan kokeilujaksolla.'
        }

        $lblTila = New-Object System.Windows.Forms.Label
        $lblTila.Text = $tTeksti
        $lblTila.SetBounds(20, 14, 620, 40)
        $form.Controls.Add($lblTila)

        $lblKone = New-Object System.Windows.Forms.Label
        $lblKone.Text = 'Taman koneen konekoodi (laheta kehittajalle aktivointia / paivitysta varten):'
        $lblKone.SetBounds(20, 62, 600, 20)
        $txtKone = New-Object System.Windows.Forms.TextBox
        $txtKone.SetBounds(20, 84, 220, 24)
        $txtKone.ReadOnly = $true
        $txtKone.TextAlign = 'Center'
        $txtKone.Text = (Get-HkLisNakymaKone (Get-HkLisKoneKoodi))
        $btnKopKone = New-Object System.Windows.Forms.Button
        $btnKopKone.Text = 'Kopioi konekoodi'
        $btnKopKone.SetBounds(250, 83, 140, 26)
        $form.Controls.AddRange(@($lblKone, $txtKone, $btnKopKone))
        $btnKopKone.Add_Click({ Set-Clipboard -Value $txtKone.Text })

        $lblInfo = New-Object System.Windows.Forms.Label
        $lblInfo.Text = ('Voit paivittaa isompaan tasoon milloin tahansa (01 Pieni: 1 serveri/50 tk/johto +5, 02 Yritys: 1/300/+10, 03 Suuri: 1/900/+20, 04 Enterprise: 5 serveria/2000 tk/+100). Anna uusi avain + koodi alla - tiedot sailyvat.')
        $lblInfo.SetBounds(20, 122, 620, 40)
        $form.Controls.Add($lblInfo)

        $lblAv = New-Object System.Windows.Forms.Label
        $lblAv.Text = 'Uusi lisenssiavain:'
        $lblAv.SetBounds(20, 170, 130, 22)
        $txtAv = New-Object System.Windows.Forms.TextBox
        $txtAv.SetBounds(160, 168, 280, 24)
        $lblKo = New-Object System.Windows.Forms.Label
        $lblKo.Text = 'Aktivointikoodi:'
        $lblKo.SetBounds(20, 202, 130, 22)
        $txtKo = New-Object System.Windows.Forms.TextBox
        $txtKo.SetBounds(160, 200, 280, 24)
        $form.Controls.AddRange(@($lblAv, $txtAv, $lblKo, $txtKo))

        $lblViesti = New-Object System.Windows.Forms.Label
        $lblViesti.SetBounds(20, 238, 620, 34)
        $lblViesti.ForeColor = [System.Drawing.Color]::Firebrick
        $form.Controls.Add($lblViesti)

        $btnAkt = New-Object System.Windows.Forms.Button
        $btnAkt.Text = 'Aktivoi paivitys'
        $btnAkt.SetBounds(20, 284, 150, 32)
        $btnAkt.BackColor = [System.Drawing.Color]::FromArgb(29, 78, 216)
        $btnAkt.ForeColor = [System.Drawing.Color]::White
        $btnAkt.Add_Click({
            $lblViesti.Text = ''
            $ulos = Register-HkLisAktivointi -Avain $txtAv.Text -Koodi $txtKo.Text
            if ($ulos.Ok) {
                $status.Ok = $true
                $lblViesti.ForeColor = [System.Drawing.Color]::FromArgb(21, 128, 61)
                $lblViesti.Text = ('Lisenssi paivitetty: {0} (taso {1}).' -f $ulos.Nimi, $ulos.Taso)
            } else {
                $lblViesti.ForeColor = [System.Drawing.Color]::Firebrick
                $lblViesti.Text = $ulos.Virhe
            }
        })
        $btnSulje = New-Object System.Windows.Forms.Button
        $btnSulje.Text = 'Sulje'
        $btnSulje.SetBounds(560, 284, 80, 32)
        $btnSulje.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.AddRange(@($btnAkt, $btnSulje))
        $form.CancelButton = $btnSulje
        [void]$form.ShowDialog()
        $form.Dispose()
    }
    catch { }
    return $status.Ok
}

function Write-HkLisKonsoli {
    # Konsolirivi lisenssin tilasta (Kaynnista.ps1 ajon tuloste).
    $tila = Get-HkLisTila
    if ($tila.Voimassa) {
        Write-Host ('Lisenssi voimassa: {0} (taso {1}).' -f $tila.Nimi, $tila.Taso)
    } else {
        Write-Host 'Ei voimassa olevaa lisenssia - kaytossa 90 paivan kokeilujakso.'
    }
}




