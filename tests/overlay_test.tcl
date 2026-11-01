# The X/Y of the overlay config move the indicators on window 1's overlay, RR/broadcast on or not
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

proc SaveSettings {} {global saved; incr saved}
set saved 0
toplevel .o1
ttk::label .o1.rr -text "x"
place .o1.rr -in .o1 -relx 0.5 -rely 0.7 -anchor c
array set settings {rrIndicator,x 0.2 rrIndicator,y 0.9}
OverlayIndicatorPlace
array set pi [place info .o1.rr]
Check "moved" [list $pi(-relx) $pi(-rely) $saved] {0.2 0.9 1}

set settings(rrIndicator,x) "abc"
OverlayIndicatorPlace
array set pi [place info .o1.rr]
Check "invalid value ignored, not saved" [list $pi(-relx) $pi(-rely) $saved] {0.2 0.9 1}
destroy .o1
