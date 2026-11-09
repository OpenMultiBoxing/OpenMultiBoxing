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
    rrExcludeWindows {} broadcastDelay 0 broadcastDelayModifiersFlush 0}
foreach i {1 2 3 4} {
    set slot2handle($i) w$i
    set slot2focus($i) f$i
}
set rrExcludes [list [expr {$RSHIFT}] [expr {$RCTRL}]]
RotateModifierUpdate
Check "rotate modifier" [list $rotateCode $rotateText] [list [expr {$RSHIFT}] "Right Shift"]
set rrLastFocus 1
# A is in the "all but these keys" list
ResetIgnoredKeys {65}
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
# keys not broadcast (A) still rotate
Check "A not broadcast" [list [Press 65] $broadcast] {{} {}}
set held([expr {$RSHIFT}]) 1
Step
Check "A rotates: focused window" [Press 65] {}
Check "A rotates: next" [Press 65] {{2 65 0} {2 65 1}}
Check "A: nothing broadcast" $broadcast {}
unset held([expr {$RSHIFT}])
Step
Check "A not broadcast after" [list [Press 65] $broadcast] {{} {}}

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

# with the broadcast delay: sent later, down and up
set settings(broadcastDelay) 50
set held([expr {$RSHIFT}]) 1
Step
Check "delayed: nothing yet" [Press 0x39] {}
Check "delayed: pending" [array size bcPending] 2
after 300 {set waited 1}
vwait waited
Check "delayed: sent" $posted {{3 57 0} {3 57 1}}
unset held([expr {$RSHIFT}])
Step
set settings(broadcastDelay) 0

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

# Rotate hotkeys / bar: every turn is sent (current window included), no delay, up on release
proc RotateBarRefresh {} {}
array set settings {rotateKey1 9 rotateName1 "War Stomp" hk,rotate1 Ctrl-Alt-F1 broadcastDelay 100}
array set rotNext {}
set focused 2
set posted {}
RotateBarPress 1
Check "bar: current window first, down now" $posted {{2 57 0}}
RotateBarRelease 1
Check "bar: up on release" $posted {{2 57 0} {2 57 1}}
set posted {}
RotateBarPress 1
RotateBarRelease 1
Check "bar: then next" $posted {{3 57 0} {3 57 1}}
set posted {}
set held(112) 1
RotateHotkey 1
RotateHotkey 1
Check "hotkey: next window, repeat ignored" $posted {{4 57 0}}
after 50 {set waited 1}
vwait waited
Check "hotkey: still held" $posted {{4 57 0}}
unset held(112)
after 50 {set waited 1}
vwait waited
Check "hotkey: up on release" $posted {{4 57 0} {4 57 1}}
set posted {}
RotateBarPress 1
RotateBarRelease 1
Check "wraps to 1" $posted {{1 57 0} {1 57 1}}
Check "key names" [list [RotateKeyCode 9] [RotateKeyCode f1] [RotateKeyCode NUMPAD1] [RotateKeyCode bogus]] {57 112 97 {}}

# Mouse over the bar's "Any key" area: keys rotate like with the modifier held
set settings(broadcastDelay) 0
unset held([expr {$RSHIFT}])
Step
array set rotNext {}
set broadcast {}
set rotHover 1
Check "hover: current window got it" [Press 0x39] {}
Check "hover: next" [Press 0x39] {{3 57 0} {3 57 1}}
Check "hover: not broadcast" $broadcast {}
set rotHover 0
Check "no hover: broadcast" [list [Press 0x39] $broadcast] {{} {{57 0} {57 1}}}
RotateBarReset 1
Check "bar right click resets" [array get rotNext 57] {}
