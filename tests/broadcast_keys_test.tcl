# Key broadcasting: keys let go while a pausing modifier (Right Ctrl) is held still go up in the other windows
# and to the remote OMBs; ups from the main OMB still apply while "Pause input" is on, and on disconnect
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)
array set netDown {}
array set rrSentDown {}
array set rrPendingMods {}
set rotateCode {}

proc Debug {msg} {}
array set held {}
proc twapi::GetAsyncKeyState {code} {global held; expr {[info exists held($code)] ? 0x8000 : 0}}
set sent {}
proc BroadcastKeyToOther {n code up} {global sent; lappend sent [list $code $up]}
proc SendToClients {data} {}
proc FocusIn {} {return 1}

set SHIFT 0xA0
set RCTRL 0xA3
array set settings {rrInterval 1000000 rrDeferModifiers 0}
set rrExcludes [expr {$RCTRL}]
set rrLastFocus 1
ResetIgnoredKeys {}
set rrLastCode [GetKeyboardState]

proc Step {} {RRCheck; global rrTaskId; after cancel $rrTaskId}

set held([expr {$SHIFT}]) 1
Step
Check "shift down broadcast" $sent [list [list [expr {$SHIFT}] 0]]
set sent {}
set held([expr {$RCTRL}]) 1
Step
Check "right ctrl not broadcast" $sent {}
unset held([expr {$SHIFT}])
Step
Check "shift up while right ctrl held" $sent [list [list [expr {$SHIFT}] 1]]
set sent {}
set held(0x41) 1
Step
Check "key pressed while right ctrl held: not broadcast" $sent {}
unset held([expr {$RCTRL}])
unset held(0x41)
Step
Check "nothing more after" $sent {}

# Remote OMB, no captured window: keys pressed for real, released when paused or disconnected
set inputs {}
proc twapi::send_input {l} {global inputs; lappend inputs {*}$l}
proc ReleaseBroadcastKeys {} {}
proc UpdateNetStatus {} {}
proc OmbError {args} {}
set networkPause 0
set lines {}
proc gets {s var} {
    global lines
    upvar $var data
    if {![llength $lines]} {
        return -1
    }
    set data [lindex $lines 0]
    set lines [lrange $lines 1 end]
    string length $data
}
proc eof {s} {return 1}
proc close {s} {}
set master sock
set lines {"DOWN 160"}
Master sock
set networkPause 1
set lines {"DOWN 65" "UP 160"}
Master sock
Master sock
Check "paused: up still applies" $inputs {{keydown 160 0} {keyup 160 0}}
set networkPause 0
set inputs {}
set lines {"DOWN 162"}
Master sock
set lines {}
Master sock
Check "disconnect releases" $inputs {{keydown 162 0} {keyup 162 0}}
Check "disconnected" [info exists master] 0
