# Startup activation check (Tk 9 regression fixed in v11.0.3 / v4.14.3: the app went under the window it was started
# from): a launcher window, clicked for real so it's in front, starts the release exe (this repo's script, sandboxed by
# sandbox.tcl, the fixed screenshot settings); logs the foreground window and the stacking order every 100ms for 7s.
# Expected: the app's main window (or its clipboard window with -Clip) becomes the foreground one and stays above the
# launcher. Moves the mouse and shows windows for a few seconds. Same file in OpenMultiBoxing and WowOpenBox.
#   tests\manual\fg_test.ps1 -Exe OpenMultiBoxing-v11.0.3.exe [-Clip] [-Mirrored]
param(
    [Parameter(Mandatory)][string]$Exe,
    [switch]$Clip,
    [switch]$Mirrored
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
$Exe = (Resolve-Path $Exe).Path
if (Test-Path "$repo\OpenMultiBoxing.tcl") {
    $script = "$repo\OpenMultiBoxing.tcl"; $as = 'OpenMultiBoxing.tcl'; $settingsName = 'OpenMultiBoxingSettings.tcl'
    $mainTitle = 'OpenMultiBoxing - Opensource'
} else {
    $script = "$repo\WowOpenBox.tcl"; $as = 'WowOpenBox.tkapp'; $settingsName = 'wowopenboxSettings.tcl'
    $mainTitle = 'WOB2027'
}
$d = Join-Path ([IO.Path]::GetTempPath()) "omb_fgtest_$PID"
New-Item -ItemType Directory -Force $d | Out-Null
Copy-Item $Exe $d
$exeName = Split-Path $Exe -Leaf
(Get-Content "$repo\msix\screenshot_settings.tcl") -notmatch '^\s*layoutMirrored\s' -replace '^array set settings \{',
    "array set settings {`n`tlastUpdateChecked`t9999999999`n`tclipboardAtStart`t$([int]$Clip.IsPresent)`n`tlayoutMirrored`t$([int]$Mirrored.IsPresent)" |
    Set-Content -Encoding utf8 "$d\$settingsName"
$bytes = [IO.File]::ReadAllBytes($script)
$skip = if ($bytes[0] -eq 0xEF) { 3 } else { 0 }
$body = [Text.Encoding]::UTF8.GetString($bytes, $skip, $bytes.Length - $skip)
[IO.File]::WriteAllText("$d\$as", (Get-Content -Raw "$PSScriptRoot\sandbox.tcl") + "`n" + $body, (New-Object Text.UTF8Encoding $false))
Set-Content "$d\launcher.ps1" @"
Add-Type -AssemblyName System.Windows.Forms
`$f = New-Object Windows.Forms.Form; `$f.Text = 'FG Launcher'; `$f.Width = 900; `$f.Height = 700; `$f.StartPosition = 'Manual'; `$f.Left = 300; `$f.Top = 200
`$b = New-Object Windows.Forms.Button; `$b.Text = 'Start'; `$b.Dock = 'Fill'
`$b.Add_Click({ Start-Process '$d\$exeName' -WorkingDirectory '$d' })
`$f.Controls.Add(`$b); [Windows.Forms.Application]::Run(`$f)
"@
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class OmbFgTest {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P p, IntPtr l);
  public static string T(IntPtr h) { var s = new StringBuilder(200); GetWindowText(h, s, 200); return s.ToString(); }
  public static IntPtr Find(string title) { IntPtr r = IntPtr.Zero; EnumWindows((h,l)=>{ if (IsWindowVisible(h) && T(h) == title) { r = h; return false; } return true; }, IntPtr.Zero); return r; }
  public static string Order(string[] names) { var r = new List<string>();
    EnumWindows((h,l)=>{ if (IsWindowVisible(h)) { var t = T(h); foreach (var n in names) if (t.StartsWith(n)) { r.Add(n); break; } } return true; }, IntPtr.Zero);
    return string.Join(" > ", r); }
}
'@
# physical pixels
[OmbFgTest]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
$lp = Start-Process -PassThru powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "$d\launcher.ps1"
try {
    for ($i = 0; $i -lt 50 -and ($h = [OmbFgTest]::Find('FG Launcher')) -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 100 }
    $r = New-Object OmbFgTest+RECT
    [OmbFgTest]::GetWindowRect($h, [ref]$r) | Out-Null
    [OmbFgTest]::SetCursorPos([int](($r.L + $r.R) / 2), [int](($r.T + $r.B) / 2)) | Out-Null
    Start-Sleep -Milliseconds 200
    [OmbFgTest]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero); [OmbFgTest]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
    $names = @('FG Launcher', $mainTitle, 'OMB Secure Copy Paste', 'WOB/OMB Secure Copy Paste')
    $t0 = Get-Date; $prev = ''
    while (((Get-Date) - $t0).TotalSeconds -lt 7) {
        $line = "foreground '$([OmbFgTest]::T([OmbFgTest]::GetForegroundWindow()))', order: $([OmbFgTest]::Order($names))"
        if ($line -ne $prev) { "{0,5:N1}s {1}" -f ((Get-Date) - $t0).TotalSeconds, $line; $prev = $line }
        Start-Sleep -Milliseconds 100
    }
} finally {
    Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "$d\*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $lp.Id -Force -ErrorAction SilentlyContinue
}
Get-Content "$d\sandbox.log" -ErrorAction SilentlyContinue | Select-String 'BGERROR' | Select-Object -First 3
Start-Sleep -Milliseconds 500
Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
