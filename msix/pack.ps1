# Microsoft Store package of an OMB exe:
#   msix\pack.ps1 -Exe OpenMultiBoxing-v1.2.3.exe -Version v1.2.3 -Out OpenMultiBoxing-v1.2.3.msix [-Dir layout_dir]
# -Dir keeps the package layout there (to test it: Add-AppxPackage -Register <dir>\AppxManifest.xml, which needs
# Windows' developer mode). Unsigned: the Store signs what's uploaded.
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Out,
    [string]$Dir = (Join-Path ([IO.Path]::GetTempPath()) "ombmsix_$PID")
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^v?(\d+)\.(\d+)\.(\d+)') { throw "Version $Version isn't vX.Y.Z" }
# The Store requires the last number to be 0
$pkgVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3]).0"
if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir }
New-Item -ItemType Directory $Dir | Out-Null
Copy-Item $Exe (Join-Path $Dir OpenMultiBoxing.exe)
Set-Content (Join-Path $Dir OpenMultiBoxing.store) 'Microsoft Store install: settings in Documents\OpenMultiBoxing'
Copy-Item -Recurse (Join-Path $PSScriptRoot Assets) (Join-Path $Dir Assets)
$manifest = (Get-Content (Join-Path $PSScriptRoot AppxManifest.xml) -Raw).Replace('Version="0.0.0.0"', "Version=""$pkgVersion""")
Set-Content (Join-Path $Dir AppxManifest.xml) $manifest -NoNewline
$makeappx = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\makeappx.exe' | Sort-Object FullName |
    Select-Object -Last 1
# resources.pri, for Windows to use the Square44x44Logo.targetsize-*_altform-unplated icons: without them the taskbar
# draws the icon on a plate of the accent color
$makepri = Join-Path $makeappx.DirectoryName makepri.exe
$priconfig = Join-Path ([IO.Path]::GetTempPath()) "priconfig_$PID.xml"
& $makepri createconfig /o /cf $priconfig /dq en-US /pv 10.0.0
if ($LASTEXITCODE) { throw "makepri createconfig failed ($LASTEXITCODE)" }
& $makepri new /o /pr $Dir /cf $priconfig /mn (Join-Path $Dir AppxManifest.xml) /of (Join-Path $Dir resources.pri)
if ($LASTEXITCODE) { throw "makepri new failed ($LASTEXITCODE)" }
Remove-Item $priconfig
& $makeappx.FullName pack /o /d $Dir /p $Out
if ($LASTEXITCODE) { throw "makeappx failed ($LASTEXITCODE)" }
"Packaged $Out ($pkgVersion)"
