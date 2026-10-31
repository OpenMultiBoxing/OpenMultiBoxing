# Capture helpers
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

set settings(numWindows) 3
array set slot2handle {}
Check "none captured" [FirstFreeSlot] 1
array set slot2handle {1 {0x1 HWND} 2 {0x2 HWND} 3 {0x3 HWND}}
Check "all captured" [FirstFreeSlot] ""
unset slot2handle(1)
Check "lost 1" [FirstFreeSlot] 1
array set slot2handle {1 {0x1 HWND}}
unset slot2handle(2)
Check "lost 2" [FirstFreeSlot] 2

# Forgotten windows are only auto captured into a lower number than the one they had;
# otherwise the first started game window
set gameWindows {{0xa HWND} {0xb HWND}}
array set startTime {0xa 200 0xb 100}
proc twapi::find_windows {args} {global gameWindows; return $gameWindows}
proc twapi::get_window_process {w} {lindex $w 0}
proc twapi::get_process_info {pid args} {global startTime; list -name wow.exe -createtime $startTime($pid)}
proc IsOurs {w} {return 0}
array set settings {game "World of Warcraft" dontCaptureList {}}
Check "first started" [FindGameWindow 1] {0xb HWND}
set wb {0xb HWND}
set forgottenSlot($wb) 2
Check "forgotten skipped" [FindGameWindow 2] {0xa HWND}
Check "forgotten skipped for higher" [FindGameWindow 3] {0xa HWND}
Check "forgotten into lower" [FindGameWindow 1] {0xb HWND}
Check "manual capture takes it" [FindGameWindow] {0xb HWND}
set gameWindows {{0xb HWND}}
Check "only forgotten" [FindGameWindow 2] ""

# List box and lost/forgotten windows
listbox .lbw
ttk::button .b2
foreach i {1 2 3} {.lbw insert end " WoW $i "}
proc UpdateHandles {} {}
proc UpdateForegroundMode {} {}
proc RegisterPerWindowHotkey {args} {}
proc FindFocusHandle {args} {}
proc Rename {args} {}
set updated {}
proc UpdateN {n} {global updated; lappend updated $n}
set mainSet {}
proc SetAsMain {n} {global mainSet; lappend mainSet $n}
set mirrored 0
proc LayoutMirrored {} {global mirrored; return $mirrored}

# 3 swapped into main then lost: back to its own position when it comes back
array set slot2handle {1 {0x1 HWND} 2 {0x2 HWND} 3 {0x3 HWND}}
array set slot2position {1 3 2 2 3 1}
WindowLost 3
Check "lost" [info exists slot2handle(3)] 0
Check "lost shown" [string match "*3 (lost)*" [.lbw get 2]] 1
Check "not mirrored: main stays" $mainSet {}
set maxNumW 4
set nextWindow 3
updateListBox 3 {0x3b HWND} "WoW 3"
Check "recaptured 3 position" $slot2position(3) 3
Check "1 back to its position" $slot2position(1) 1
Check "1 moved" $updated 1

# mirrored layout: losing the main (swapped in) window brings 1 back as main
set mirrored 1
array set slot2position {1 3 2 2 3 1}
WindowLost 3
Check "mirrored main lost" $mainSet 1
set mainSet {}
WindowLost 2
Check "mirrored other lost" $mainSet {}

# forgetting it too (it would stay on top of the stack), before it's forgotten
array set slot2handle {1 {0x1 HWND} 2 {0x2 HWND} 3 {0x3 HWND}}
array set slot2position {1 3 2 2 3 1}
array unset forgottenSlot
proc SetAsMain {n} {global mainSet slot2handle; lappend mainSet [list $n [info exists slot2handle(3)]]}
Forget 3
Check "mirrored main forgotten" $mainSet {{1 1}}
Check "forgotten slot" [array get forgottenSlot] {{0x3 HWND} 3}
Check "forgotten shown" [string match "*3 (removed)*" [.lbw get 2]] 1
set mainSet {}
set mirrored 0
array set slot2handle {3 {0x3 HWND}}
array set slot2position {1 3 2 2 3 1}
Forget 3
Check "not mirrored forget" $mainSet {}

# windows found at startup: in the mirrored layout, the one left on top goes under window 1
proc twapi::find_windows {args} {
    if {[regexp {\^(?:OMB|WoW) (\d+)\$} [dict get $args -text] -> n] && $n <= 2} {
        return [list [list 0x$n HWND]]
    }
}
proc updateListBox {n w wname} {global slot2handle slot2position; set slot2handle($n) $w; set slot2position($n) $n}
proc CheckAutoKill {} {}
proc StackUnderMain {} {global stacked; incr stacked}
array unset slot2handle
array unset slot2position
array set settings {numWindows 2}
set stacked 0
set mirrored 1
FindExisting
Check "found windows" [lsort [array names slot2handle]] {1 2}
Check "mirrored startup stacks under main" $stacked 1
set stacked 0
set mirrored 0
FindExisting
Check "regular startup doesn't stack" $stacked 0
