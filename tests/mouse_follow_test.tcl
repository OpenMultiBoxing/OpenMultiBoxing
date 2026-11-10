# Focus follows mouse: Windows' own setting from before is left alone until the checkbox/hotkey turns ours on,
# then restored when ours is off, while paused (mouse outside the game windows) and at exit; the checkbox
# (mouseFollow) keeps the user's choice, which applies again when the mouse is back in a game window
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

proc Debug {msg} {}
set ffm {}
set delays {}
proc SetFocusFollowMouse {v} {global ffm; lappend ffm $v}
proc SetMouseDelay {v} {global delays; lappend delays $v}
set winFfm 0
set winDelay 0
proc GetFocusFollowMouse {} {global winFfm; set winFfm}
proc GetMouseDelay {} {global winDelay; set winDelay}
proc Reset {} {
    global ffm delays
    set ffm {}
    set delays {}
}
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
    mouseInsideGameWindowFocuses 0 mouseDelay 0 mouseFocusOffAtExit 1}
set hasRR 0
set hasBR 0
set rrOn 0
set mouseBroadcast 0
set networkPause 0
set lastFocusWindow 1

# Exit before the startup read Windows' setting (another copy running): nothing changed, no error
RevertMouseFollow
Check "exit before start" [list $ffm $delays] {{} {}}
set isPaused 0
set pauseSchedule {}

# the user's own setting (on, 200 ms), never turned on by us: untouched
set winFfm 1
set winDelay 200
InitMouseFollow
Check "own setting: checkbox off" $mouseFollow 0
Check "own setting: saved" $mouseOrig {1 200}
set pauseNow 1
PeriodicChecks
set pauseNow 0
PeriodicChecks
UpdateMouseFollow
RevertMouseFollow
Check "own setting: untouched" [list $ffm $delays] {{} {}}
# reloads and profile switches keep it
set winDelay 0
InitMouseFollow
Check "init again: still saved" $mouseOrig {1 200}

# turned on: ours, then the user's back while paused
set mouseFollow 1
UpdateMouseFollow
Check "on: ours" [list $ffm $delays] {1 0}
Reset
set pauseNow 1
PeriodicChecks
Check "paused: user's setting back" [list $ffm $delays] {1 200}
Check "paused: checkbox still on" $mouseFollow 1
Reset
set pauseNow 0
PeriodicChecks
Check "back in game: ours again" [list $ffm $delays] {1 0}

# unchecking while paused: stays the user's when back in game
set pauseNow 1
PeriodicChecks
Reset
set mouseFollow 0
UpdateMouseFollow
Check "unchecked while paused" [list $ffm $delays] {1 200}
Reset
set pauseNow 0
PeriodicChecks
Check "stays the user's back in game" $ffm {}

# checking while paused: only applies once back in game
set pauseNow 1
PeriodicChecks
Reset
set mouseFollow 1
UpdateMouseFollow
Check "checked while paused: not yet" [list $ffm $delays] {1 200}
Reset
set pauseNow 0
PeriodicChecks
Check "checked while paused: on back in game" [list $ffm $delays] {1 0}

# not paused: checkbox applies right away
Reset
set mouseFollow 0
UpdateMouseFollow
Check "unchecked in game" [list $ffm $delays] {1 200}

# exit restores the user's setting, even when on
set mouseFollow 1
UpdateMouseFollow
Reset
RevertMouseFollow
Check "restored at exit" [list $ffm $delays] {1 200}

# exit while paused, keeping it on at exit (mouseFocusOffAtExit 0)
set settings(mouseFocusOffAtExit) 0
set pauseNow 1
PeriodicChecks
Reset
RevertMouseFollow
Check "kept on at exit" [list $ffm $delays] {1 0}
Reset
set mouseFollow 0
RevertMouseFollow
Check "off: user's at exit" [list $ffm $delays] {1 200}

# broadcasting leaves it alone (the real RRUpdate), also paused and back in game
set pauseNow 0
PeriodicChecks
set mouseFollow 1
UpdateMouseFollow
proc RRToggle {} {global rrOn; set rrOn [expr {!$rrOn}]; RRUpdate}
proc ReleaseBroadcastKeys {} {}
proc RRIndicatorLabel {} {return B}
proc RRKeysListChange {} {}
proc RRreadAllKeys {} {}
proc GetKeyboardState {} {}
proc PendHeldModifiers {} {}
set settings(rrInterval) 100000
set hasRR 1
Reset
RRToggle
Check "broadcasting: untouched" [list $mouseFollow $ffm $delays] {1 {} {}}
set pauseNow 1
PeriodicChecks
Check "paused broadcasting: user's" [list $rrOn $mouseFollow $ffm $delays] {0 1 1 200}
Reset
set pauseNow 0
PeriodicChecks
Check "back in game: broadcasting and ours" [list $rrOn $mouseFollow $ffm $delays] {1 1 1 0}
Reset
RevertMouseFollow
Check "broadcasting: kept on at exit" $ffm 1
RRToggle
Check "broadcasting off: untouched" $mouseFollow 1
set hasRR 0
set mouseFollow 0

# started while kept on by a previous run (on with our delay): restoring turns it off
set pauseNow 0
PeriodicChecks
unset mouseOrig mouseFollow
set winFfm 1
set winDelay 0
InitMouseFollow
Check "left on: checkbox on" $mouseFollow 1
set settings(mouseFocusOffAtExit) 1
Reset
RevertMouseFollow
Check "left on: off at exit" [list $ffm $delays] {0 500}
Reset
set mouseFollow 0
UpdateMouseFollow
Check "left on: unchecking turns off" [list $ffm $delays] {0 500}

# off at start: turned on then off restores off with the user's delay
unset mouseOrig mouseFollow
set winFfm 0
set winDelay 0
InitMouseFollow
Check "off with 0 delay: checkbox off" $mouseFollow 0
set mouseFollow 1
UpdateMouseFollow
Reset
set mouseFollow 0
UpdateMouseFollow
Check "off with 0 delay: back off" [list $ffm $delays] {0 0}

# reload from an older version (mouseFollow and mouseDelay set, no mouseOrig)
unset mouseOrig
set mouseFollow 1
set mouseDelay 300
InitMouseFollow
Reset
RevertMouseFollow
Check "older version: off with its delay" [list $ffm $delays] {0 300}
