# Fixed spots: each window keeps its own area (window n in area n+1), area 1 is the main one's
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

proc Debug {msg} {}
proc CheckWindow {cmd n} {uplevel #0 $cmd}
set moves {}
proc Update {wh x y w h top} {global moves; lappend moves [list $wh $x $y]; return 0}
proc MirrorsRefreshAll {} {}
proc LayoutMirrored {} {return 0}
wm withdraw .
# 4 areas for 3 windows
array set settings {numWindows 4 layoutFixedSpots 1 layoutStacked 0 showOverlay 0
    1,posXY {0 0} 1,size {1000 800} 2,posXY {1000 0} 2,size {200 100}
    3,posXY {1000 100} 3,size {200 100} 4,posXY {1000 200} 4,size {200 100}}
array set slot2handle {1 w1 2 w2 3 w3}

proc Positions {} {
    global slot2position
    list $slot2position(1) $slot2position(2) $slot2position(3)
}

Check "fixed spots" [FixedSpots] 1
Check "home" [list [HomePosition 1] [HomePosition 3]] {2 4}
Check "owners" [list [PositionOwner 1] [PositionOwner 2] [PositionOwner 4]] {{} 1 3}
Check "first free slot: 3 windows for 4 areas" [FirstFreeSlot] ""
unset slot2handle(3)
Check "first free slot" [FirstFreeSlot] 3
set slot2handle(3) w3

ResetPositions
Check "reset: 1 main, the others in their own area" [Positions] {1 3 4}
Check "window 1 moved to main" [lsearch -inline -index 0 $moves w1] {w1 0 0}
SetAsMainInt 3
Check "3 main, 1 back to its own area, 2 stays" [Positions] {2 3 1}
set moves {}
SetAsMainInt 2
Check "2 main, 3 back to its own area" [Positions] {2 1 4}
Check "only 2 windows moved" [lsort $moves] {{w2 0 0} {w3 1000 200}}
Check "main" [SlotAtPosition 1] 2
SetAsMainInt 1
Check "back to the start" [Positions] {1 3 4}

# mirrored layout: area p always mirrors its own window
Check "mirror of 1's area" [LayoutMirrorSource 2] 1
Check "mirror of 3's area" [LayoutMirrorSource 4] 3

# a window without an area (layout too small) is left alone
set slot2handle(4) w4
set moves {}
UpdateN 4
Check "no area, not moved" $moves {}
unset slot2handle(4)

# capture: the first window goes to the main area, the others to their own
array unset slot2position
array set slot2handle {}
listbox .lbw
ttk::button .b2
proc UpdateHandles {} {}
proc UpdateForegroundMode {} {}
proc RegisterPerWindowHotkey {args} {}
proc FindFocusHandle {args} {}
proc Overlay {} {}
set maxNumW 4
set nextWindow 1
updateListBox 1 w1 "OMB 1"
updateListBox 2 w2 "OMB 2"
Check "captured: 1 main, 2 in its own area" [list $slot2position(1) $slot2position(2)] {1 3}
# (manual and auto capture) moved there, not to its own area
array unset slot2position
array unset slot2handle
.lbw delete 0 end
set maxNumW 1
set nextWindow 1
set moves {}
PostCapture w1 "OMB 1"
Check "first capture moved to main" $moves {{w1 0 0}}
set moves {}
PostCapture w2 "OMB 2"
Check "second capture moved to its own area" $moves {{w2 1000 100}}

# labels and main window <-> layout area
# (OMB N, WOB WoW N)
set app [expr {[string match *WowOpenBox* $env(OMB_TEST_APP)] ? "WoW" : "OMB"}]
Check "labels" [list [AreaLabel 1] [AreaLabel 2] [AreaLabel 4]] [list Main "$app 1" "$app 3"]
Check "window 3's area" [WindowArea 3] 4
set nextWindow 1
LayoutToMain wow1
Check "main area: no window selected" $nextWindow 1
LayoutToMain wow4
Check "area 4 is window 3's" $nextWindow 3

# off: windows exchange their areas as before
set settings(layoutFixedSpots) 0
array set slot2handle {1 w1 2 w2 3 w3}
ResetPositions
Check "not fixed: own areas" [Positions] {1 2 3}
SetAsMainInt 3
Check "not fixed: 1 and 3 exchanged" [Positions] {3 2 1}
Check "not fixed labels" [AreaLabel 1] "$app 1"
