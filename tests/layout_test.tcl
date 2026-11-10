# Auto layout: small windows in the space the aspect ratio leaves free (#41), 2 big windows (#52);
# windows and mirrors past the number of windows not shown
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

proc Debug {msg} {}
proc updateIndex {args} {}
wm withdraw .
set scale 0.25
set stayOnTop 0
set mirrorEdit 0
toplevel .layout
wm withdraw .layout
pack [canvas .layout.c]
array set settings {numWindows 9 layoutAuto 1 layoutOneSize 0 layoutOneRowCol 0 layoutTwoBig 0 layoutStacked 0
    layoutTop 0 aspectRatio 4/3 mirrors {} mirrorsShown 1}
# one 4k monitor
array set monitorInfo {n 1 0,x1 0 0,y1 0 0,x2 3840 0,y2 2160 0,width 3840 0,height 2160 mlist {{0 8294400}}}

# the auto layout's windows: {x y w h} for 1..numWindows
proc CheckLayout {name expected} {
    ChangeLayout
    set l {}
    for {set i 1} {$i<=$::settings(numWindows)} {incr i} {
        lappend l [SizeOfWindow wow$i]
    }
    Check $name $l [list {*}$expected]
}

# 4:3 on 16:9: one more column of small windows instead of smaller ones
CheckLayout "4:3 9 windows" {{0 0 1920 1440} {1920 0 960 720} {1920 720 960 720} {0 1440 960 720} {960 1440 960 720}
    {1920 1440 960 720} {2880 0 960 720} {2880 720 960 720} {2880 1440 960 720}}
set settings(layoutTop) 1
CheckLayout "4:3 9 windows main at bottom" {{0 720 1920 1440} {0 0 960 720} {960 0 960 720} {1920 0 960 720}
    {1920 720 960 720} {1920 1440 960 720} {2880 0 960 720} {2880 720 960 720} {2880 1440 960 720}}
set settings(layoutTop) 0
# no free space: as before
set settings(aspectRatio) Any
CheckLayout "any 9 windows" {{0 0 3072 1728} {3072 0 768 432} {3072 432 768 432} {3072 864 768 432}
    {3072 1296 768 432} {0 1728 768 432} {768 1728 768 432} {1536 1728 768 432} {2304 1728 768 432}}

# 2 big windows side by side, the others below
set settings(layoutTwoBig) 1
set settings(numWindows) 5
CheckLayout "2 big" {{0 0 1920 1440} {1920 0 1920 1440} {0 1440 960 720} {960 1440 960 720} {1920 1440 960 720}}
set settings(layoutTop) 1
CheckLayout "2 big main at bottom" {{0 720 1920 1440} {1920 720 1920 1440} {0 0 960 720} {960 0 960 720}
    {1920 0 960 720}}
set settings(layoutTop) 0
set settings(numWindows) 7
set settings(layoutOneRowCol) 1
CheckLayout "2 big one row" {{0 0 1920 1542} {1920 0 1920 1542} {0 1542 768 617} {768 1542 768 617}
    {1536 1542 768 617} {2304 1542 768 617} {3072 1542 768 617}}
set settings(numWindows) 5
CheckLayout "2 big one row of 3" {{0 0 1920 1296} {1920 0 1920 1296} {0 1296 1280 864} {1280 1296 1280 864}
    {2560 1296 1280 864}}
set settings(layoutOneRowCol) 0
# Any: more rows rather than squarer big windows
set settings(numWindows) 12
CheckLayout "2 big 12 windows" {{0 0 1920 1440} {1920 0 1920 1440} {0 1440 480 360} {480 1440 480 360}
    {960 1440 480 360} {1440 1440 480 360} {1920 1440 480 360} {2400 1440 480 360} {2880 1440 480 360}
    {3360 1440 480 360} {0 1800 480 360} {480 1800 480 360}}

# 16:10ish monitor, Same: 6 windows fill the height, as with one row
array set monitorInfo {0,x2 3024 0,y2 1916 0,width 3024 0,height 1916}
set settings(aspectRatio) Same
set settings(numWindows) 6
set twoBig6 {{0 0 1512 1276} {1512 0 1512 1276} {0 1276 756 638} {756 1276 756 638} {1512 1276 756 638}
    {2268 1276 756 638}}
CheckLayout "2 big 6 windows 16:10" $twoBig6
set settings(layoutOneRowCol) 1
CheckLayout "2 big 6 windows 16:10 one row" $twoBig6
set settings(layoutOneRowCol) 0

# 2 monitors: the second big one the same size as the main one, with the small ones around it
array set monitorInfo {n 2 0,x1 0 0,y1 0 0,x2 1920 0,y2 1032 0,width 1920 0,height 1032
    1,x1 1920 1,y1 -540 1,x2 5760 1,y2 1620 1,width 3840 1,height 2160 mlist {{0 1981440} {1 8294400}}}
set settings(aspectRatio) Any
set settings(numWindows) 9
CheckLayout "2 big 2 monitors" {{0 0 1920 1032} {1920 -540 1920 1032} {3840 -540 960 516} {3840 -24 960 516}
    {1920 492 960 516} {2880 492 960 516} {3840 492 960 516} {4800 -540 960 516} {4800 -24 960 516}}
set settings(numWindows) 3
CheckLayout "2 big 2 monitors 3 windows" {{0 0 1920 1032} {1920 -540 1920 1032} {3840 -540 960 516}}
# no room around a main size one: both smaller
array set monitorInfo {1,x1 1920 1,y1 0 1,x2 3840 1,y2 1080 1,width 1920 1,height 1080 mlist {{0 1981440} {1 2073600}}}
set settings(numWindows) 5
CheckLayout "2 big 2 same monitors" {{0 0 1280 720} {1920 0 1280 720} {3200 0 640 360} {3200 360 640 360}
    {1920 720 640 360}}
# 3 monitors: alone on the 2 smallest ones, same size
array set monitorInfo {n 3 2,x1 3840 2,y1 0 2,x2 7680 2,y2 2160 2,width 3840 2,height 2160
    mlist {{0 1981440} {1 2073600} {2 8294400}} totalArea 12349440}
CheckLayout "2 big 3 monitors" {{0 0 1920 1032} {1920 0 1920 1032} {3840 0 1920 1080} {3840 1080 1920 1080}
    {5760 0 1920 1080}}

array set monitorInfo {n 1 0,x1 0 0,y1 0 0,x2 3840 0,y2 2160 0,width 3840 0,height 2160 mlist {{0 8294400}}}
set settings(numWindows) 12
ChangeLayout

# manual layout: fewer windows hides the others, more shows them back
set settings(layoutAuto) 0
set settings(numWindows) 3
ChangeLayout
Check "past N hidden" [.layout.c itemcget wow4&&wowWindow -state] hidden
Check "past N text hidden" [.layout.c itemcget wow12&&wowText -state] hidden
Check "up to N shown" [.layout.c itemcget wow3&&wowWindow -state] normal
set settings(numWindows) 12
ChangeLayout
Check "shown back" [.layout.c itemcget wow4&&wowWindow -state] normal
Check "same place" [SizeOfWindow wow4] {480 1440 480 360}
# not in this layout: from the saved one
.layout.c delete wow12
array set settings {12,posXY {100 200} 12,size {640 360}}
ChangeLayout
Check "saved one shown" [SizeOfWindow wow12] {100 200 640 360}

# mirrors of windows past N not shown, back when it's raised
set settings(mirrors) {{source 2 geom {0 0 400 300}} {source 5 geom {400 0 400 300}} {source main geom {800 0 400 300}}}
set settings(numWindows) 3
LayoutShowMirrors
Check "mirrors up to N and main" [list [llength [.layout.c find withtag mirrorShape0]] \
    [llength [.layout.c find withtag mirrorShape1]] [llength [.layout.c find withtag mirrorShape2]]] {2 0 2}
set settings(numWindows) 5
LayoutShowMirrors
Check "mirror back" [llength [.layout.c find withtag mirrorShape1]] 2
