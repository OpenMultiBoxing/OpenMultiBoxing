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
