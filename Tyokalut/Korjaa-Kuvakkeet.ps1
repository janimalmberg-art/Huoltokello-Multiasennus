# ============================================================
# HUOLTOKELLO - Pikakuvakkeiden kuvakkeiden korjaus
#
# Korjaa jo asennetun ohjelman pikakuvakkeiden kuvakkeet ilman
# uudelleenasennusta:
#   - Huoltokello.lnk        -> huoltokello.ico (toimistotietokone + kello)
#   - Huoltokello-Ohjeet.lnk -> huoltokello-ohjeet.ico (lamppu)
# Paivittaa tyopoydan, kaynnistysvalikon ja (tarvittaessa) automaattisen
# kaynnistyksen pikakuvakkeet sekali tyhjentaa kuvakevalimuistin.
#
# Kaytto (asennuskansiossa tai asennuspaketin Tyokalut-kansiossa):
#   powershell -ExecutionPolicy Bypass -File Tyokalut\Korjaa-Kuvakkeet.ps1
# Vaihtoehtoisesti: -InstallDir "C:\oma\asennuskansio"
# ============================================================
param([string]$InstallDir)

$ErrorActionPreference = 'Stop'

# 1) Etsi asennuskansio (rekisteri -> oletusarvo)
if (-not $InstallDir) {
    try {
        $InstallDir = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Huoltokello' -ErrorAction Stop).InstallLocation
    } catch { $InstallDir = $null }
}
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Huoltokello' }
if (-not (Test-Path $InstallDir)) { throw ("Asennuskansiota ei loytynyt: " + $InstallDir) }
Write-Host ("Asennuskansio: " + $InstallDir)

$icoMain = Join-Path $InstallDir 'huoltokello.ico'
$icoOhje = Join-Path $InstallDir 'huoltokello-ohjeet.ico'

# 2) Jos asennuskansion kuvakkeet puuttuvat tai ovat vioittuneet,
#    korvaa ne asennuspaketin assets-kansiosta (skriptin ylakansion assets).
$assetsDir = Join-Path $PSScriptRoot '..\assets'
foreach ($pair in @(@($icoMain, 'huoltokello.ico'), @($icoOhje, 'huoltokello-ohjeet.ico'))) {
    $dest = $pair[0]
    $src  = Join-Path $assetsDir $pair[1]
    $broken = (-not (Test-Path $dest)) -or ((Get-Item $dest).Length -lt 1000)
    if ($broken -and (Test-Path $src)) {
        Copy-Item $src $dest -Force
        Write-Host ("Korvattu kuvake: " + $dest)
    }
}
if (-not (Test-Path $icoMain)) { throw ("Kuvaketta ei loytynyt: " + $icoMain) }
if (-not (Test-Path $icoOhje)) { $icoOhje = $icoMain }   # varasuunnitelma

# 3) Paivita pikakuvakkeet (tyopoyta, kaynnistysvalikko, automaattinen kaynnistys)
$wsh = New-Object -ComObject WScript.Shell
$desktop   = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$autostart = [Environment]::GetFolderPath('Startup')
$ohjeFile  = Join-Path $InstallDir 'Ohjeet\Kayttoonotto-Opas.html'
$launcher  = Join-Path $InstallDir 'Huoltokello.ps1'
$psExe     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$psArgs    = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $launcher

function Update-Shortcut([string]$Path, [string]$Target, [string]$Arguments, [string]$WorkingDir, [string]$Icon) {
    $isNew = -not (Test-Path $Path)
    $sc = $wsh.CreateShortcut($Path)
    if ($isNew -or -not $sc.TargetPath) {
        $sc.TargetPath = $Target
        if ($Arguments)  { $sc.Arguments = $Arguments }
        if ($WorkingDir) { $sc.WorkingDirectory = $WorkingDir }
    }
    $sc.IconLocation = $Icon
    $sc.Save()
    Write-Host ("Paivitetty: {0} -> kuvake {1}" -f $Path, $Icon)
    return 1
}

$fixed = 0
foreach ($p in @((Join-Path $desktop 'Huoltokello.lnk'), (Join-Path $startMenu 'Huoltokello.lnk'), (Join-Path $autostart 'Huoltokello.lnk'))) {
    if ((Test-Path $p) -or (Test-Path $launcher)) {
        $fixed += Update-Shortcut $p $psExe $psArgs $InstallDir "$icoMain,0"
    }
}
foreach ($p in @((Join-Path $desktop 'Huoltokello-Ohjeet.lnk'), (Join-Path $startMenu 'Huoltokello-Ohjeet.lnk'))) {
    if ((Test-Path $p) -or (Test-Path $ohjeFile)) {
        $fixed += Update-Shortcut $p $ohjeFile '' '' "$icoOhje,0"
    }
}

# 4) Rekisterin DisplayIcon (Sovellukset-lista) kuntoon
try {
    $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Huoltokello'
    if (Test-Path $reg) { Set-ItemProperty $reg -Name DisplayIcon -Value $icoMain }
} catch { }

# 5) Paivita Windowsin kuvakevalimuisti, etta muutos nakyy heti
try { Start-Process ie4uinit.exe -ArgumentList '-show' -WindowStyle Hidden -Wait } catch { }
try {
    Add-Type -Namespace Win32 -Name ShellNotify -MemberDefinition '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);'
    [Win32.ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)   # SHCNE_ASSOCCHANGED
} catch { }

Write-Host ("Valmis: {0} pikakuvaketta paivitettiin." -f $fixed)
Write-Host "Jos jokin kuvake nayttaa viela vanhalta, paina F5 tyopoydalla tai kirjaudu ulos ja takaisin."