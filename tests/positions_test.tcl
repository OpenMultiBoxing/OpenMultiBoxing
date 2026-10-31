# Remembered window positions
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

wm withdraw .
set settings(layoutGeometry) 500x300+700+400
toplevel .w
pack [frame .w.f -width 200 -height 100]
Check "restored" [RememberGeometry .w layoutGeometry] 1
update
after 300
update
Check "position restored" [regexp {\+700\+400$} [wm geometry .w]] 1
Check "size not restored" [string match 500x300* [wm geometry .w]] 0
wm geometry .w +650+420
update
after 300
update
Check "new position recorded" [regexp {\+650\+420$} $settings(layoutGeometry)] 1
destroy .w

set settings(clipGeometry) 410x170+300+200
toplevel .w
Check "restored with size" [RememberGeometry .w clipGeometry 1] 1
update
after 300
update
Check "size restored" [wm geometry .w] 410x170+300+200
destroy .w

# the top left corner must be on one of the monitors
set fakeMonitors [list [list -extent {0 0 1920 1080}] [list -extent {1920 0 3840 1080}]]
Check "on screen" [GeometryOnScreen 300x900+100+50] 1
Check "on the second monitor" [GeometryOnScreen 300x900+2000+50] 1
Check "barely visible" [GeometryOnScreen 300x900+3830+1070] 1
Check "right of the monitors" [GeometryOnScreen 400x100+3900+50] 0
Check "left of the monitors" [GeometryOnScreen 300x200+-500+10] 0
Check "below the monitors" [GeometryOnScreen 300x200+10+1200] 0
Check "not a geometry" [GeometryOnScreen 300x200] 0
set settings(mirrorsGeometry) 300x200+-500+10
toplevel .w
Check "off screen not restored" [RememberGeometry .w mirrorsGeometry] 0
destroy .w
unset fakeMonitors
