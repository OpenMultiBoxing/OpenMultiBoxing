# Soak test (memory / handles / GDI / USER objects over time) of a release exe, e.g. after a Tcl/Tk, twapi or cffi
# update: 5 "Key test" windows captured by the real app (this repo's script, sandboxed by sandbox.tcl), mirrored layout
# with 4 mirrors, then swaps, typing, mouse moves and clicks (not in WOB: it sends no input), mirror rebuilds...
# (soak.tcl). TAKES OVER THE SCREEN (focus changes every 2s, the mouse moves every second): run it when away, closing
# the app window ends it early.
# Results: soak.csv (a line every 30s: flat handles/privateKB/gdi/user = no leak) and sandbox.log in the work folder.
# Compare with the previous release exe (same -Minutes). Same file in OpenMultiBoxing and WowOpenBox.
#   tests\manual\soak.ps1 -Exe OpenMultiBoxing-v11.0.3.exe [-Minutes 40] [-Toggles]
# -Toggles: also turns key/mouse broadcast on and off and shows/hides the mirrors every 1-2.5s (3 minutes is enough).
param(
    [Parameter(Mandatory)][string]$Exe,
    [int]$Minutes = 40,
    [switch]$Toggles,
    [string]$WorkDir
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
$Exe = (Resolve-Path $Exe).Path
if (Test-Path "$repo\OpenMultiBoxing.tcl") {
    $script = "$repo\OpenMultiBoxing.tcl"; $as = 'OpenMultiBoxing.tcl'; $settingsName = 'OpenMultiBoxingSettings.tcl'
} else {
    $script = "$repo\WowOpenBox.tcl"; $as = 'WowOpenBox.tkapp'; $settingsName = 'wowopenboxSettings.tcl'
}
if (-not $WorkDir) { $WorkDir = Join-Path ([IO.Path]::GetTempPath()) "omb_soak_$(Get-Date -Format yyyyMMdd_HHmmss)" }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Copy-Item $Exe $WorkDir
Set-Content "$WorkDir\soak_minutes.txt" $Minutes
if ($Toggles) { Set-Content "$WorkDir\soak_toggles.txt" 1 }
# fixed 5 window layout (the screenshot one), "Key test" windows, mirrored layout with 4 mirrors
$mirrors = '{source main area {0.0 0.0 0.3 0.3} geom {2050 1330 220 180} top 1 clicks 1} ' +
    '{source 2 area {0.1 0.1 0.4 0.4} geom {2290 1330 220 180} top 1 clicks 1} ' +
    '{source 3 area {0.5 0.5 0.3 0.3} geom {2530 1330 220 180} top 1 clicks 1} ' +
    '{source 4 area {0.2 0.6 0.5 0.3} geom {2770 1330 220 180} top 1 clicks 1}'
(Get-Content "$repo\msix\screenshot_settings.tcl") -notmatch '^\s*(mirrors|layoutMirrored)\s' -replace '^array set settings \{',
    "array set settings {`n`tappearance`tdark`n`tgame`t{Key test}`n`tautoCapture`t1`n`tautoKillOn`t0`n`tlastUpdateChecked`t9999999999`n`tlayoutMirrored`t1`n`tmirrors`t{$mirrors}" |
    Set-Content -Encoding utf8 "$WorkDir\$settingsName"
$bytes = [IO.File]::ReadAllBytes($script)
$skip = if ($bytes[0] -eq 0xEF) { 3 } else { 0 }
$body = [Text.Encoding]::UTF8.GetString($bytes, $skip, $bytes.Length - $skip)
[IO.File]::WriteAllText("$WorkDir\$as", (Get-Content -Raw "$PSScriptRoot\sandbox.tcl") + "`n" + $body + "`n" +
    (Get-Content -Raw "$PSScriptRoot\soak.tcl"), (New-Object Text.UTF8Encoding $false))
# 5 simple text windows, all titled "Key test" (WOB matches the exact title)
$form = @'
Add-Type -AssemblyName System.Windows.Forms
$f = New-Object Windows.Forms.Form; $f.Text = 'Key test'; $f.Width = 500; $f.Height = 300
$b = New-Object Windows.Forms.TextBox; $b.Multiline = $true; $b.Dock = 'Fill'
$f.Controls.Add($b); [Windows.Forms.Application]::Run($f)
'@
Set-Content "$WorkDir\keytest.ps1" $form
$forms = 1..5 | ForEach-Object {
    Start-Process -PassThru conhost -ArgumentList '--headless', 'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "$WorkDir\keytest.ps1"
}
Start-Sleep -Seconds 3
$p = Start-Process -PassThru (Join-Path $WorkDir (Split-Path $Exe -Leaf)) -WorkingDirectory $WorkDir
"Soak of $(Split-Path $Exe -Leaf) for $Minutes min in $WorkDir"
try {
    $p.WaitForExit(($Minutes + 5) * 60 * 1000) | Out-Null
} finally {
    Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "$WorkDir\*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$WorkDir\keytest.ps1*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
Get-Content "$WorkDir\soak.csv" -ErrorAction SilentlyContinue | Select-Object -First 2
Get-Content "$WorkDir\soak.csv" -ErrorAction SilentlyContinue | Select-Object -Last 2
Get-Content "$WorkDir\sandbox.log" -ErrorAction SilentlyContinue | Select-String -Pattern 'BGERROR|MESSAGEBOX|SOAK' | Select-Object -First 20
