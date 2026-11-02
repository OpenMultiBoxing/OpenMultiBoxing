# Store/website screenshot of a release exe: the app (this repo's script, sandboxed: no capture, hotkeys or dialogs)
# with screenshot_settings.tcl, its windows arranged as in the Store listing over a dark backdrop (screenshot.tcl),
# captured from the screen (it shows on top for a few seconds). Same file in OpenMultiBoxing and WowOpenBox.
#   msix\screenshot.ps1 -Exe OpenMultiBoxing-v11.0.1.exe [-Appearance dark|light] [-Out shot.png]
param(
    [Parameter(Mandatory)][string]$Exe,
    [ValidateSet('dark', 'light')][string]$Appearance = 'dark',
    [string]$Out
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$Exe = (Resolve-Path $Exe).Path
if (Test-Path "$repo\OpenMultiBoxing.tcl") {
    $app = 'OpenMultiBoxing'; $script = "$repo\OpenMultiBoxing.tcl"; $as = 'OpenMultiBoxing.tcl'; $settings = 'OpenMultiBoxingSettings.tcl'
} else {
    $app = 'WowOpenBox'; $script = "$repo\WowOpenBox.tcl"; $as = 'WowOpenBox.tkapp'; $settings = 'wowopenboxSettings.tcl'
}
$version = (Get-Item $Exe).VersionInfo.ProductVersion
if (-not $Out) { $Out = "screenshot-$app-$version-$Appearance.png" }
$Out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)

$dir = Join-Path ([IO.Path]::GetTempPath()) "omb_screenshot_$PID"
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item $Exe $dir
$exeCopy = Join-Path $dir (Split-Path $Exe -Leaf)
(Get-Content "$PSScriptRoot\screenshot_settings.tcl") -replace '^array set settings \{', "array set settings {`n`tappearance`t$Appearance" |
    Set-Content -Encoding utf8 (Join-Path $dir $settings)
# the exe runs a script found next to it (as for updates): prefix + this repo's script (with the exe's version) + suffix
$parts = (Get-Content -Raw "$PSScriptRoot\screenshot.tcl") -split '(?m)^# @@(?:prefix|suffix)\r?$'
$bytes = [IO.File]::ReadAllBytes($script)
$skip = if ($bytes[0] -eq 0xEF) { 3 } else { 0 }
$body = [Text.Encoding]::UTF8.GetString($bytes, $skip, $bytes.Length - $skip) -replace '(?m)^set vers "dev"', "set vers `"$version`""
[IO.File]::WriteAllText((Join-Path $dir $as), $parts[1] + $body + $parts[2], (New-Object Text.UTF8Encoding $false))

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ShotDpi {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
}
'@
# physical pixels, like the app's coordinates
[ShotDpi]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
Add-Type -AssemblyName System.Drawing
$rectFile = Join-Path $dir screenshot_rect.txt
$p = Start-Process -PassThru $exeCopy -WorkingDirectory $dir
try {
    for ($i = 0; $i -lt 300 -and -not (Test-Path $rectFile); $i++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $rectFile)) { throw "no screenshot from the app, see $dir\screenshot.log" }
    [int]$x, [int]$y, [int]$w, [int]$h = (Get-Content $rectFile).Split(' ')
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size)
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    "$Out ($w x $h)"
} finally {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit(5000) | Out-Null
}
Get-Content "$dir\screenshot.log" | Select-String -Pattern 'BGERROR' | Select-Object -First 5
Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
