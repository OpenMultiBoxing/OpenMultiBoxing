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
