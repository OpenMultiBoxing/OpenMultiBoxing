# Focus follows mouse and the pause (mouse outside the game windows): Windows' setting goes off while paused,
# the checkbox (mouseFollow) keeps the user's choice, which applies again when the mouse is back in a game window
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

proc Debug {msg} {}
set ffm {}
proc SetFocusFollowMouse {v} {global ffm; lappend ffm $v}
proc SetMouseDelay {v} {global delays; lappend delays $v}
# what PeriodicChecks calls besides the pause
proc FirstFreeSlot {} {return ""}
proc CheckWindowsExist {} {}
proc IsOurs {w} {return 0}
proc OverlayToggle {} {}
proc OverlayUpdate {} {}
proc RRToggle {} {}
proc Focus {wh} {}
proc AddMouseToRRLabel {} {}
set pauseNow 0
proc ShouldPause {} {global pauseNow; list $pauseNow 0}

array set settings {autoCapture 0 mouseWatchInterval 0 mouseOutsideWindowsPauses 1 showOverlay 0
    mouseInsideGameWindowFocuses 0 mouseDelay 0 mouseFocusOffAtExit 0}
set hasRR 0
set hasBR 0
set rrOn 0
set mouseBroadcast 0
set networkPause 0
set lastFocusWindow 1
set isPaused 0
set pauseSchedule {}
set mouseDelay 300
set mouseFollow 1

set pauseNow 1
PeriodicChecks
Check "paused: Windows' setting off" $ffm 0
Check "paused: checkbox still on" $mouseFollow 1
Check "paused: user delay back" $delays 300

set ffm {}
set pauseNow 0
PeriodicChecks
Check "back in game: on again" $ffm 1

# unchecking while paused: stays off when back in game
set pauseNow 1
PeriodicChecks
set ffm {}
set mouseFollow 0
UpdateMouseFollow
Check "unchecked while paused" $ffm 0
set ffm {}
set pauseNow 0
PeriodicChecks
Check "stays off back in game" $ffm {}

# checking while paused: only applies once back in game
set pauseNow 1
PeriodicChecks
set ffm {}
set mouseFollow 1
UpdateMouseFollow
Check "checked while paused: not yet" $ffm 0
set ffm {}
set pauseNow 0
PeriodicChecks
Check "checked while paused: on back in game" $ffm 1

# not paused: checkbox applies right away
set ffm {}
set mouseFollow 0
UpdateMouseFollow
Check "unchecked in game" $ffm 0

# exit while paused, keeping it on at exit (mouseFocusOffAtExit 0)
set mouseFollow 1
set pauseNow 1
PeriodicChecks
set ffm {}
RevertMouseFollow
Check "kept on at exit" $ffm 1
set ffm {}
set mouseFollow 0
RevertMouseFollow
Check "off: nothing at exit" $ffm {}

# exit while broadcasting (which turned it off for now): on again
set pauseNow 0
PeriodicChecks
set hasRR 1
set rrOn 1
set rrMouse 1
set mouseFollow 0
set ffm {}
RevertMouseFollow
Check "broadcasting: on at exit" $ffm 1
# turned off by the user after broadcasting was turned off
set rrOn 0
set ffm {}
RevertMouseFollow
Check "not broadcasting: nothing at exit" $ffm {}
# exit while paused, broadcasting paused too (RRToggle turns rrOn off)
set rrOn 1
set pauseNow 1
PeriodicChecks
set rrOn 0
Check "paused broadcasting: rrMouse saved" [list $rrMouse $prevRRMouse $prevRR] {0 1 1}
set ffm {}
RevertMouseFollow
Check "paused broadcasting: on at exit" $ffm 1
