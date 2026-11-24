# _lue-tunnukset.ps1 - lukee kayttajien sahkopostitunnukset Huoltokellon tietokannasta (VAIN LUETTAVA).
# Ajetaan pwsh:lla (PowerShell 7), koska Microsoft.Data.Sqlite ei lataudu Windows PowerShell 5.1:in:
#   pwsh -NoProfile -File _lue-tunnukset.ps1 -InstallDir "C:\Users\tunus\AppData\Local\Huoltokello"
param([Parameter(Mandatory = $true)][string]$InstallDir)
$ErrorActionPreference = 'Stop'
$db = Join-Path $InstallDir 'AppData\huoltokello.db'
if (-not (Test-Path $db)) { exit 2 }
$env:Path = "$InstallDir;$env:Path"
Add-Type -Path (Join-Path $InstallDir 'SQLitePCLRaw.core.dll')
Add-Type -Path (Join-Path $InstallDir 'SQLitePCLRaw.provider.e_sqlite3.dll')
try { Add-Type -Path (Join-Path $InstallDir 'SQLitePCLRaw.batteries_v2.dll') } catch { }
try { [SQLitePCL.Batteries_V2]::Init() } catch { try { [SQLitePCL.raw]::SetProvider() } catch { } }
Add-Type -Path (Join-Path $InstallDir 'Microsoft.Data.Sqlite.dll')
$c = New-Object 'Microsoft.Data.Sqlite.SqliteConnection' -ArgumentList "Data Source=$db;Mode=ReadOnly"
$c.Open()
$emails = New-Object 'System.Collections.Generic.HashSet[string]'
$cmd = $c.CreateCommand()
$cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table'"
$rd = $cmd.ExecuteReader()
$tables = @()
while ($rd.Read()) { $tables += [string]$rd[0] }
$rd.Dispose()
foreach ($t in ($tables | Where-Object { $_ -notlike 'sqlite_*' })) {
  try {
    $q = $c.CreateCommand()
    $q.CommandText = 'SELECT Email FROM "' + $t.Replace('"', '') + '" LIMIT 300'
    $er = $q.ExecuteReader()
    while ($er.Read()) { if ($er[0]) { [void]$emails.Add([string]$er[0]) } }
    $er.Dispose()
  } catch { } # taulussa ei Email-saraketta
}
$c.Dispose()
if ($emails.Count) { $emails | Sort-Object | ForEach-Object { Write-Output $_ } } else { exit 3 }