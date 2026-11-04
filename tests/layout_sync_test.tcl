# Main window <-> Window Layout: the layout's draft shows in the main window's fields and the other way around
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

proc UpdateHandles {} {}
proc UpdateForegroundMode {} {}
proc LayoutShowMirrors {} {}
proc Debug {msg} {}
wm withdraw .
# the main window's fields
set maxNumW 1
ttk::label .l2
ttk::button .b2
ttk::checkbutton .csop -variable stayOnTop -command MainStayOnTopToLayout
set stayOnTop 0
array set settings {numWindows 2 layoutAuto 1 mirrors {}
    1,posXY {0 0} 1,size {1920 1080} 1,stayOnTop 0 2,posXY {1920 0} 2,size {640 360} 2,stayOnTop 0}
set nextWindow 1
trace add variable nextWindow write updateIndex

# layout closed: the saved settings
set nextWindow 2
Check "saved size" $windowSize {640 360}
Check "saved position" $pos {1920 0}

# the Window Layout open: its windows from the settings
set scale 0.25
toplevel .layout
wm withdraw .layout
LayoutBindClose .layout
pack [canvas .layout.c]
LoadLayout
Check "same as saved before changes" $windowSize {640 360}

# moved in the layout (drag / arrow keys): the main window shows the draft
.layout.c move wow2 [expr {100*$scale}] [expr {40*$scale}]
LayoutToMain wow2
Check "draft position" $pos {2020 40}
Check "draft size" $windowSize {640 360}
Check "settings unchanged" $settings(2,posXY) {1920 0}
# clicking another window selects it
LayoutToMain wow1
Check "clicked window selected" $nextWindow 1
Check "its size" $windowSize {1920 1080}
# typing a window number: its draft
set nextWindow 2
Check "typed window draft" $pos {2020 40}

# typed in the main window (Enter / leaving the field): moved and resized in the layout
set windowSize "800 450"
set pos "1900 10"
MainToLayout
Check "layout preview" [SizeOfWindow wow2] {1900 10 800 450}
Check "layout text" [string match "*800 x 450*" [.layout.c itemcget "wow2&&wowText" -text]] 1
Check "auto layout off" $settings(layoutAuto) 0
Check "settings still unchanged" $settings(2,size) {640 360}
# not a number (still typing): nothing changes
set windowSize "80x"
MainToLayout
Check "partial input ignored" [SizeOfWindow wow2] {1900 10 800 450}
set windowSize "800 450"

# stay on top: main checkbox -> layout pin, layout pin -> main checkbox
.csop invoke
Check "pin from main checkbox" $sot(2) 1
Check "pinned text" [string match "*📌*" [.layout.c itemcget "wow2&&wowText" -text]] 1
set sot(1) 1
LayoutToMain wow1
Check "checkbox from layout pin" $stayOnTop 1
LayoutToMain wow2
.csop invoke
Check "unpinned from main checkbox" $sot(2) 0

# closed without Save and Apply: the saved values again
# (the layout's idle redraws first: in the app they're done long before it can be closed)
update idletasks
destroy .layout
update
Check "saved size after close" $windowSize {640 360}
Check "saved position after close" $pos {1920 0}
Check "saved stay on top after close" $stayOnTop 0
