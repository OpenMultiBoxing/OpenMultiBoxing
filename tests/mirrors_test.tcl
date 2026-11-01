# Mirrors helpers
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

array set slot2position {1 1 2 2 3 3}
Check "main is 1" [MirrorSourceSlot main] 1
array set slot2position {1 3 2 2 3 1}
Check "main after swap" [MirrorSourceSlot main] 3
Check "fixed source" [MirrorSourceSlot 2] 2

Check "full area" [MirrorSourceRect {0 0 1 1} 1008 654] {0 0 1008 654}
Check "top right quarter" [MirrorSourceRect {0.5 0 0.5 0.5} 1000 600] {500 0 1000 300}
Check "rounding" [MirrorSourceRect {0.1 0.1 0.2 0.2} 1008 654] {101 65 302 196}

Check "hwnd" [HwndInt {0x1b0452 HWND}] 1770578

set settings(mirrors) [list [dict create source main area {0 0 1 1} geom {1 2 3 4} top 1] \
    [dict create source 2 area {0 0 1 1} geom {5 6 7 8} top 0]]
MirrorSet 1 top 1
Check "set top" [dict get [lindex $settings(mirrors) 1] top] 1
Check "other unchanged" [dict get [lindex $settings(mirrors) 0] geom] {1 2 3 4}

Check "edges middle" [MirrorEdges 50 50 100 100] ""
Check "edges right" [MirrorEdges 95 50 100 100] r
Check "edges top left" [MirrorEdges 2 3 100 100] lt
Check "edges small" [MirrorEdges 6 10 20 20] ""

# 2x zoom of a 100x50 area at 100,50 of a 1000x500 window
set g {10 20 200 100}
set a {0.1 0.1 0.1 0.1}
proc Round4 {l} {lmap v $l {expr {round($v*10000)/10000.}}}
lassign [MirrorEdgeDrag r $g $a 1000 500 20 0] ng na
Check "drag right geom" $ng {10 20 220 100}
Check "drag right area" [Round4 $na] {0.1 0.1 0.11 0.1}
lassign [MirrorEdgeDrag lt $g $a 1000 500 -20 10] ng na
Check "drag top left geom" $ng {-10 30 220 90}
Check "drag top left area" [Round4 $na] {0.09 0.11 0.11 0.09}
lassign [MirrorEdgeDrag l $g $a 1000 500 -5000 0] ng na
Check "drag left clamped" [Round4 $na] {0.0 0.1 0.2 0.1}
Check "drag left clamped geom" $ng {-190 20 400 100}
lassign [MirrorEdgeDrag b $g $a 1000 500 0 -500] ng na
Check "drag shrink min" $ng {10 20 200 16}
# odd mouse moves snap to whole source pixels (2 mirror pixels at 2x)
lassign [MirrorEdgeDrag r $g $a 1000 500 3 0] ng na
Check "drag snaps" $ng {10 20 204 100}

Check "next zoom" [MirrorNextZoom 1.997 1] 2.5
Check "next zoom from near 2" [MirrorNextZoom 1.9 1] 2
Check "prev zoom" [MirrorNextZoom 2 -1] 1.75
Check "prev zoom from odd" [MirrorNextZoom 1.6 -1] 1.5
Check "zoom max" [MirrorNextZoom 8 1] 8
Check "zoom min" [MirrorNextZoom 0.1 -1] 0.1
Check "third" [expr {round(300*[MirrorNextZoom 0.3 1])}] 100

Check "inset 2x" [MirrorEditInset 100 50 200 100] {1 1 2 2}
Check "inset 1:1" [MirrorEditInset 100 50 100 50] {2 2 2 2}
Check "inset 3x" [MirrorEditInset 100 50 300 150] {1 1 3 3}
Check "inset tiny" [MirrorEditInset 4 4 4 4] {0 0 0 0}

# source size is the layout size of the slot's position
array set slot2position {1 3 2 2 3 1}
array set settings {1,size {1008 654} 3,size {336 218} layoutMirrored 0 layoutStacked 0}
Check "main size" [MirrorSourceSize 3] {1008 654}
Check "small size" [MirrorSourceSize 1] {336 218}

Check "slot at position" [SlotAtPosition 3] 1
Check "no slot at position" [SlotAtPosition 4] ""
Check "real position" [RealPosition 3] 3

# mirrored layout: all windows really are at the main position
proc MirrorInit {} {return 1}
set settings(layoutMirrored) 1
Check "mirrored real position" [RealPosition 3] 1
Check "mirrored main position" [RealPosition 1] 1
Check "mirrored small size" [MirrorSourceSize 1] {1008 654}
set settings(layoutStacked) 1
Check "stacked wins" [RealPosition 3] 3
set settings(layoutStacked) 0
set mirroredExiting 1
Check "unstacked on exit" [RealPosition 3] 3
unset mirroredExiting

# a mirror left from a profile with more of them (refreshed before the rebuild)
toplevel .mirror1
set settings(mirrors) [list [dict create source main area {0 0 1 1} geom {1 2 3 4} top 1]]
Check "extra mirror ignored" [catch {MirrorRefresh 1} err] 0
destroy .mirror1

# picking the window to mirror in the mirrored layout: only the one on top
proc MirrorCheckBinary {} {return 1}
proc MirrorOverlay {t n cursor text} {
    toplevel $t
    canvas $t.c
    $t.c create text 0 0 -text $text -tags label
}
array set slot2position {1 3 2 2 3 1}
array set slot2handle {1 {0x1 HWND} 2 {0x2 HWND} 3 {0x3 HWND}}
MirrorPick
Check "pick only main" [lsort [lsearch -all -inline [winfo children .] .mirrorPick*]] .mirrorPickMain
Check "pick main label" [lindex [split [.mirrorPickMain.c itemcget label -text] \n] 0] "OMB 3"
array set slot2position {1 2 2 1 3 3}
MirrorPickSwapped
Check "pick label after swap" [lindex [split [.mirrorPickMain.c itemcget label -text] \n] 0] "OMB 2"
Check "pick click after swap" [bind .mirrorPickMain.c <ButtonRelease-1>] "MirrorPickClose; MirrorSelect {} 2"
MirrorPickClose
array unset slot2handle

Check "fit same ratio" [MirrorFit 1600 900 320 180] {0 0 320 180}
Check "fit wider spot" [MirrorFit 1600 900 400 180] {40 0 360 180}
Check "fit taller spot" [MirrorFit 1600 900 320 240] {0 30 320 210}

Check "to source middle" [MirrorToSource 160 90 320 180 1600 900] {800 450}
Check "to source letterboxed" [MirrorToSource 40 90 400 180 1600 900] {0 450}
Check "to source in the bar" [MirrorToSource 5 300 400 180 1600 900] {0 899}

# 2x mirror of the 200x100 area at 1400,0 (e.g. a minimap)
Check "to area origin" [MirrorToSourceArea 0 0 400 200 1400 0 1600 100] {1400 0}
Check "to area middle" [MirrorToSourceArea 200 100 400 200 1400 0 1600 100] {1500 50}
Check "to area clamped" [MirrorToSourceArea 400 200 400 200 1400 0 1600 100] {1599 99}

# clicks setting: missing in older settings means pass through
set settings(mirrors) [list [dict create source 1 area {0 0 1 1} geom {0 0 10 10} top 1] \
    [dict create source 1 area {0 0 1 1} geom {0 0 10 10} top 1 clicks 1]]
set mirrorEdit 0
Check "clicks default" [list [MirrorClicks 0] [MirrorPassThrough 0]] {0 1}
Check "clicks on" [list [MirrorClicks 1] [MirrorPassThrough 1]] {1 0}
Check "key state none" [MirrorKeyState 0] 0
Check "key state left+shift" [MirrorKeyState [expr {0x100|0x1}]] 5
Check "key state right+middle+control" [MirrorKeyState [expr {0x400|0x200|0x4}]] [expr {0x02|0x10|0x08}]
Check "middle button messages" [MirrorButtonMessages 2] {0x0207 0x0208 0x10}
Check "other button ignored" [MirrorButtonMessages 4] ""
set mirrorEdit 1
Check "edit mode not pass through" [MirrorPassThrough 0] 0
set mirrorEdit 0
set settings(mirrors) {}
