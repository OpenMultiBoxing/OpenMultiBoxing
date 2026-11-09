# Rotation: keys pressed with the rotate modifier (Right Shift) held go to the focused window (for real),
# then to one window per press (not skipped ones), per key; swaps start again; Right Shift isn't broadcast
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)
array set netDown {}
array set rrSentDown {}
array set rrPendingMods {}
array set sentDown {}
array set bcPending {}
array set bcLastT {}
array set hotkeyCombo {}
array set broadcastMap {}
array set rotNext {}
array set rotDown {}
set rotateCode {}

proc Debug {msg} {}
array set held {}
proc twapi::GetAsyncKeyState {code} {global held; expr {[info exists held($code)] ? 0x8000 : 0}}
set broadcast {}
proc BroadcastKeyToOther {n code up} {global broadcast; lappend broadcast [list $code $up]}
proc SendToClients {data} {}
set focused 1
proc FocusIn {} {global focused; return $focused}
set posted {}
proc PostKeyMessage {i code up} {global posted; lappend posted [list $i $code $up]}

set RSHIFT 0xA1
set RCTRL 0xA3
array set settings {rrInterval 1000000 rrDeferModifiers 1 rotateModifier RSHIFT rrExcludeWindowsOn 1
    rrExcludeWindows {}}
foreach i {1 2 3 4} {
    set slot2handle($i) w$i
    set slot2focus($i) f$i
}
set rrExcludes [list [expr {$RSHIFT}] [expr {$RCTRL}]]
RotateModifierUpdate
Check "rotate modifier" [list $rotateCode $rotateText] [list [expr {$RSHIFT}] "Right Shift"]
set rrLastFocus 1
ResetIgnoredKeys {}
set rrLastCode [GetKeyboardState]

proc Step {} {RRCheck; global rrTaskId; after cancel $rrTaskId}
proc Press {code} {
    global held posted
    set posted {}
    set held([expr {$code}]) 1
    Step
    unset held([expr {$code}])
    Step
    return $posted
}

set held([expr {$RSHIFT}]) 1
Step
Check "1st press: focused window got it" [Press 0x39] {}
Check "2nd press: next window" [Press 0x39] {{2 57 0} {2 57 1}}
Check "other key: own rotation" [Press 0x38] {}
Check "3rd press" [Press 0x39] {{3 57 0} {3 57 1}}
set settings(rrExcludeWindows) {4}
Check "skip windows left out, back to 1 (focused)" [Press 0x39] {}
Check "then 2" [Press 0x39] {{2 57 0} {2 57 1}}
Check "8 next" [Press 0x38] {{2 56 0} {2 56 1}}
set settings(rrExcludeWindows) {}
Check "nothing broadcast" $broadcast {}
# key up after the modifier is let go still goes to the window that got the down
set posted {}
set held(57) 1
Step
unset held([expr {$RSHIFT}])
Step
unset held(57)
Step
Check "up after modifier released" $posted {{3 57 0} {3 57 1}}
Check "still nothing broadcast" $broadcast {}
Check "normal broadcast without modifier" [Press 0x39] {}
Check "broadcast" $broadcast {{57 0} {57 1}}
set broadcast {}

# swap: starts again at the focused window
set held([expr {$RSHIFT}]) 1
Step
RotationsReset
set focused 2
Check "after swap: focused window" [Press 0x39] {}
Check "after swap: next" [Press 0x39] {{3 57 0} {3 57 1}}
# broadcasting turned on again (same modifier): turns kept
RotateModifierUpdate
# another pausing modifier held: no rotation
set held([expr {$RCTRL}]) 1
Step
Check "paused by right ctrl" [Press 0x39] {}
unset held([expr {$RCTRL}])
Step
Check "then 4" [Press 0x39] {{4 57 0} {4 57 1}}
Check "wraps to 1" [Press 0x39] {{1 57 0} {1 57 1}}
Check "focused (2) got it" [Press 0x39] {}
Check "no broadcast while rotating" $broadcast {}
unset held([expr {$RSHIFT}])
Step

# no rotate modifier: Right Shift just pauses as before
set settings(rotateModifier) ""
RotateModifierUpdate
Check "off" [list $rotateCode $rotateText] {{} None}
set held([expr {$RSHIFT}]) 1
Step
Check "off: nothing posted" [Press 0x39] {}
Check "off: nothing posted 2" [Press 0x39] {}
Check "off: nothing broadcast" $broadcast {}

# Rotate button: click, press then release Right Ctrl (Tk gives the generic Ctrl code), Esc cancels,
# right click clears
proc SaveSettings {} {}
set rotateCapture 0
ttk::button .rotb -textvariable rotateText -command RotateCaptureStart
RotateCaptureStart
Check "capturing" $rotateText "Press Shift, Ctrl or Alt"
set held([expr {$RCTRL}]) 1
Check "press taken" [RotateCaptureKey 17 0] 1
unset held([expr {$RCTRL}])
RotateCaptureKey 17 1
Check "set to right ctrl" [list $settings(rotateModifier) $rotateText $rotateCode $rotateCapture] \
    [list RCONTROL "Right Ctrl" [expr {$RCTRL}] 0]
Check "not capturing: keys not taken" [RotateCaptureKey 16 0] 0
RotateCaptureStart
RotateCaptureKey 0x1B 0
RotateCaptureKey 0x1B 1
Check "esc cancels" [list $settings(rotateModifier) $rotateText $rotateCapture] {RCONTROL {Right Ctrl} 0}
RotateClear
Check "cleared" [list $settings(rotateModifier) $rotateText $rotateCode] {{} None {}}
update idletasks
destroy .rotb
