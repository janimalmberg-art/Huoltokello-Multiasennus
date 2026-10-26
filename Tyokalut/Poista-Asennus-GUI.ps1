# ============================================================
# HUOLTOKELLO - Graafinen asennuksen poisto (WPF / PowerShell 5.1)
#
# Poistaa Huoltokellon: sulkee sovelluksen, poistaa ajastuksen,
# pikakuvakkeet ja Sovellukset-listauksen. Varmuuskopioi datan
# tyopoydalle (valittavissa: poista data lopullisesti).
# Kaytto: Tyokalut\Poista-Asennus-GUI.ps1  (tai -Silent testaukseen)
# ============================================================
param(
    [switch]$Silent,
    [switch]$PoistaData,
    [string]$InstallDir
)
# Asennusvelho (tai kayttaja) voi osoittaa poistettavan kansion suoraan:
# pakettikansiosta kaynnistettyna skriptin oma sijainti EI ole asennuskansio.
if ($InstallDir) { $script:HkInstallDirOverride = $InstallDir.TrimEnd('\') }
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\_yhteinen.ps1"

$dir = Get-HkInstallDir
$port = Get-HkPort

function Invoke-HkUninstall {
    param([string]$Status)

    $desktop = [Environment]::GetFolderPath('Desktop')
    & $Status 'Suljetaan Huoltokello...'
    Stop-HkApp | Out-Null

    & $Status 'Poistetaan automaattinen kaynnistys...'
    schtasks /Delete /TN "Huoltokello" /F | Out-Null

    & $Status 'Poistetaan pikakuvakkeet...'
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    foreach ($lnk in @(
        (Join-Path $desktop 'Huoltokello.lnk'),
        (Join-Path $desktop 'Huoltokello-Ohjeet.lnk'),
        (Join-Path $startMenu 'Huoltokello.lnk'),
        (Join-Path $startMenu 'Huoltokello-Ohjeet.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Startup')) 'Huoltokello.lnk')
    )) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }

    & $Status 'Poistetaan Windowsin Sovellukset-listaus...'
    Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Huoltokello' -Recurse -Force -ErrorAction SilentlyContinue

    & $Status 'Poistetaan palomuurisaanto (vaatii yllapito-oikeudet)...'
    if ($Silent) {
        # Hiljainen ajo: ei UAC-ikkunaa (toimii jos korotettu, muuten saanto jaanyt)
        $null = Start-Process netsh -ArgumentList 'advfirewall firewall delete rule name=Huoltokello' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    } else {
        try { Start-Process netsh -ArgumentList 'advfirewall firewall delete rule name=Huoltokello' -Verb RunAs -Wait } catch { }
    }

    & $Status 'Valmistellaan tietojen kasittelya...'
    return $desktop
}

function Remove-HkData {
    param([string]$InstallDir, [switch]$DeleteData, [string]$Status)

    $appData = Join-Path $InstallDir 'AppData'
    if (-not (Test-Path $appData)) { return }
    if (-not $DeleteData) {
        & $Status 'Varmuuskopioidaan data tyopoydalle...'
        $dest = Join-Path ([Environment]::GetFolderPath('Desktop')) ("Huoltokello-data-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".zip")
        try { Compress-Archive -Path $appData -DestinationPath $dest -Force; $script:BackupPath = $dest }
        catch { $script:BackupPath = $null }
    }
    & $Status 'Poistetaan asennuskansio...'
    # Yritetaan muutaman kerran: juuri suljetun prosessin tiedostolukot
    # voivat vapautua viiveella.
    for ($yritys = 1; $yritys -le 3; $yritys++) {
        if (-not (Test-Path $InstallDir)) { break }
        if ($yritys -gt 1) { Start-Sleep -Seconds (2 * $yritys) }
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) {
            Get-ChildItem $InstallDir -Recurse -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------- Hiljainen ajo (testaus / edistyneet) ----------
if ($Silent) {
    $desktop = Invoke-HkUninstall -Status { param($m) Write-Host $m }
    Remove-HkData -InstallDir $dir -DeleteData:$PoistaData -Status { param($m) Write-Host $m }
    Write-Host ""
    Write-Host "Poisto valmis." -ForegroundColor Green
    if ($script:BackupPath) { Write-Host ("  Data varmuuskopioitu: " + $script:BackupPath) }
    exit 0
}

# ---------- Graafinen poisto ----------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Huoltokello - Poista asennus" Height="420" Width="560"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize">
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel>
      <TextBlock Text="🗑️ Poistetaanko Huoltokello?" FontSize="19" FontWeight="Bold" Margin="0,0,0,10"/>
      <TextBlock x:Name="lblInfo" TextWrapping="Wrap" FontSize="13" Margin="0,0,0,12"/>
      <CheckBox x:Name="chkDeleteData" FontSize="13" Margin="0,4,0,12"
                Content="Poista myös data LOPULLISESTI (tietokanta, liitteet — EI varmuuskopiota)"/>
      <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="#6B7280"
                 Text="Jos kohtaa ei valita, data varmuuskopioidaan automaattisesti työpöydälle zip-tiedostona ennen poistoa (Huoltokello-data-pvm.zip)."/>
      <TextBlock x:Name="lblStatus" TextWrapping="Wrap" FontSize="13" FontWeight="SemiBold" Margin="0,14,0,0"/>
      <ProgressBar x:Name="pb" Height="14" IsIndeterminate="True" Margin="0,10,0,0" Visibility="Collapsed"/>
    </StackPanel>
    <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="btnCancel" Content="Peruuta" Padding="18,7" Margin="0,0,8,0"/>
      <Button x:Name="btnOk" Content="Poista asennus" Padding="18,7" FontWeight="Bold"/>
    </StackPanel>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)
$c = @{}
foreach ($n in @('lblInfo','chkDeleteData','lblStatus','pb','btnCancel','btnOk')) { $c[$n] = $win.FindName($n) }
$c.lblInfo.Text = "Asennus: $dir`nPortti: $port`n`nSovellus suljetaan ja poistetaan täältä koneelta."
if (-not (Test-Path (Join-Path $dir 'KiinteistoHuolto.Web.exe'))) {
    $c.lblInfo.Text += "`n`nHuom: kansiosta ei löytynyt Huoltokellon ohjelmatiedostoja."
}

$win.Add_Closing({ if ($script:Busy) { $args[1].Cancel = $true } })
$c.btnCancel.Add_Click({ $win.Close() })
$c.btnOk.Add_Click({
    $script:Busy = $true
    $c.btnOk.IsEnabled = $false; $c.btnCancel.Content = 'Sulje'
    $c.pb.Visibility = 'Visible'
    $deleteData = [bool]$c.chkDeleteData.IsChecked
    foreach ($el in $win.FindName('chkDeleteData')) { $el.IsEnabled = $false }
    $status = { param($m) $c.lblStatus.Text = $m; [Windows.Forms.Application]::DoEvents() }
    $null = Invoke-HkUninstall -Status $status
    Remove-HkData -InstallDir $dir -DeleteData:$deleteData -Status $status
    $c.pb.Visibility = 'Collapsed'
    if (Test-Path $dir) {
        $c.lblStatus.Text = "Poisto valmis — osa tiedostoista oli käytössä ja jäi paikalleen: $dir"
    } else {
        $c.lblStatus.Text = "Poisto valmis. Tietokanta ja asennus poistettu."
        if ($script:BackupPath) { $c.lblStatus.Text += "`nVarmuuskopio: $($script:BackupPath)" }
    }
    $c.btnOk.Visibility = 'Collapsed'
    $script:Busy = $false
})

$win.ShowDialog() | Out-Null