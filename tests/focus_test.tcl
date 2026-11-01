# Giving the keys to a window: foreground when allowed, set_focus otherwise;
# set_focus first with focus follows mouse (or Windows moves the cursor)
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

set hasRR 0
set mouseFollow 0
array set settings {focusAlsoFG 1 showOverlay 0 layoutMirrored 0 layoutStacked 0}
array set slot2handle {1 {0x1 HWND} 2 {0x2 HWND}}
array set slot2position {1 1 2 2}
set lastFocusWindow 1
set calls {}
set fgOk 1
proc Foreground {wh} {global calls fgOk; lappend calls [list Foreground $wh]; return $fgOk}
proc Focus {wh} {global calls; lappend calls [list Focus $wh]}

FocusNinternal 2 1
Check "foreground only" $calls {{Foreground {0x2 HWND}}}

set calls {}
set fgOk 0
FocusNinternal 2 1
Check "focus when foreground refused" $calls {{Foreground {0x2 HWND}} {Focus {0x2 HWND}}}

set calls {}
set fgOk 1
set mouseFollow 1
FocusNinternal 2 1
Check "focus then foreground with focus follows mouse" $calls {{Focus {0x2 HWND}} {Foreground {0x2 HWND}}}

set mouseFollow 0

set calls {}
FocusNinternal 2 0
Check "focus only without fg" $calls {{Focus {0x2 HWND}}}

set calls {}
set settings(focusAlsoFG) 0
FocusNinternal 2 1
Check "focus only without focusAlsoFG" $calls {{Focus {0x2 HWND}}}
