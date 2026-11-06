# Mirrors and overlays follow the virtual desktop of their game window
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

proc Debug {msg} {}
wm geometry . 200x100+0+0
update
set ombWh [list [wm frame .] HWND]
# real DWM call (cffi binding): a shown window on this desktop isn't cloaked
Check "dwm binding" [MirrorInit] 1
Check "on this desktop" [OnOtherDesktop $ombWh] 0
Check "bad hwnd" [OnOtherDesktop {0x0 HWND}] 0

# window 2 and OMB on another desktop
set refreshed 0
set desktopAway {}
proc MirrorsRefreshAll {} {global refreshed; incr refreshed}
proc OverlayUpdate {} {}
array set slot2handle [list 1 {0x111 HWND} 2 {0x222 HWND} 10 {0x10 HWND}]
array set slot2position {1 1 2 2 10 3}
proc OnOtherDesktop {wh} {expr {[lindex $wh 0] in {0x222 0x10} || $wh eq $::ombWh}}
DesktopCheck
Check "away" $desktopAway {2 10 main}
Check "refreshed" $refreshed 1
DesktopCheck
Check "refreshed on change only" $refreshed 1
Check "away n" [OnOtherDesktopN 2] 1
Check "here n" [OnOtherDesktopN 1] 0

set settings(showOverlay) 1
Check "overlay here" [OverlayShown 1] 1
Check "overlay away" [OverlayShown 2] 0
Check "overlay without window follows ours" [OverlayShown 4] 0
set settings(showOverlay) 0
Check "overlay off" [OverlayShown 1] 0

# a mirror of a window on another desktop is hidden
set hidden {}
proc MirrorHide {i} {global hidden; lappend hidden $i}
toplevel .mirror0
set settings(mirrorsShown) 1
set settings(mirrors) [list [dict create source 2 area {0 0 1 1} geom {1 2 3 4} top 1]]
MirrorRefresh 0
Check "mirror hidden" $hidden 0
destroy .mirror0
