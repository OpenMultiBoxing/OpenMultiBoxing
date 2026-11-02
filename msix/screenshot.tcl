# Store/website screenshot (see screenshot.ps1): the app script is put between the "prefix" and "suffix" parts
# below. Prefix: sandbox, no capture/kill/hotkeys/dialogs, log to screenshot.log next to the exe.
# @@prefix
set shotLog [open [file join [file dirname [info nameofexecutable]] screenshot.log] w]
fconfigure $shotLog -encoding utf-8 -buffering line
rename ::puts ::shot_puts_orig
proc puts {args} {
    if {[llength $args] == 1 || ([llength $args] == 2 && [lindex $args 0] in {stdout stderr})} {
        ::shot_puts_orig $::shotLog [lindex $args end]
    } else {
        ::shot_puts_orig {*}$args
    }
}
proc bgerror {msg args} {
    puts "BGERROR: $msg\n$::errorInfo"
}
interp bgerror {} bgerror
proc tk_messageBox {args} {
    puts "MESSAGEBOX: $args"
    return no
}
proc ::tk::MessageBox {args} {
    puts "MESSAGEBOX (tk): $args"
    return no
}
rename twapi::find_windows twapi::shot_find_windows_orig
# no game windows or other copy found, only our own popup menus
proc twapi::find_windows {args} {
    if {[lrange $args 0 1] eq {-class #32768}} {
        return [twapi::shot_find_windows_orig {*}$args]
    }
    return {}
}
proc twapi::get_process_ids {args} {return {}}
proc twapi::register_hotkey {args} {return 1}
proc twapi::unregister_hotkey {args} {}
# @@suffix
# The windows of the Store screenshot (OMB: Mirrors, Window Layout, main, Overlay config; WOB: Window Layout, main,
# Overlay config with big 1 2 3 numbers) over a dark backdrop. Writes screenshot_rect.txt (physical pixels) for
# screenshot.ps1 to capture.
set shotDir [file dirname [info nameofexecutable]]
set shotWob [info exists ::wobDark]
set shotX0 60
set shotY0 60
proc ShotPlace {w x y} {
    global shotX0 shotY0
    wm geometry $w +[expr {$shotX0+$x}]+[expr {$shotY0+$y}]
}
proc ShotBox {ws} {
    set x1 99999; set y1 99999; set x2 0; set y2 0
    foreach w $ws {
        lassign [twapi::get_window_coordinates [list [expr {[wm frame $w]}] HWND]] a b c d
        set x1 [expr {min($x1,$a)}]; set y1 [expr {min($y1,$b)}]
        set x2 [expr {max($x2,$c)}]; set y2 [expr {max($y2,$d)}]
    }
    list $x1 $y1 $x2 $y2
}
proc ShotSize {w} {
    lassign [ShotBox $w] a b c d
    list [expr {$c-$a}] [expr {$d-$b}]
}
proc ShotArrange {} {
    global shotWob shotWs shotLw
    if {!$shotWob} {MirrorsDialog}
    WindowLayout
    OverlayConfig
    update
    lassign [ShotSize .layout] lw lh
    lassign [ShotSize .] mw mh
    set shotLw $lw
    set gap 30
    if {$shotWob} {
        ShotPlace .layout 0 200
        ShotPlace . [expr {$lw+$gap}] 40
        ShotPlace .overlayConfig [expr {$lw+$mw+2*$gap}] 170
        set shotWs {.layout . .overlayConfig}
    } else {
        lassign [ShotSize .mirrors] rw rh
        ShotPlace .mirrors [expr {$lw-$rw-40}] 20
        ShotPlace .layout 0 [expr {$rh+50}]
        ShotPlace . [expr {$lw+$gap}] 0
        ShotPlace .overlayConfig [expr {$lw+$mw+2*$gap}] 170
        set shotWs {.mirrors .layout . .overlayConfig}
    }
    update
    after 800 ShotBackdrop
}
proc ShotBackdrop {} {
    global shotWob shotWs shotLw shotX0 shotDir
    lassign [ShotBox $shotWs] x1 y1 x2 y2
    set m 40
    set bx [expr {$x1-$m}]; set by [expr {$y1-$m}]
    # WOB: room on the right for the 2 and 3
    set bw [expr {$x2-$x1+2*$m+($shotWob ? 170 : 0)}]; set bh [expr {$y2-$y1+2*$m}]
    toplevel .shotBg
    wm overrideredirect .shotBg 1
    canvas .shotBg.c -highlightthickness 0 -width $bw -height $bh -background #0b0b12
    pack .shotBg.c
    # dark purple to near black
    for {set i 0} {$i < $bh} {incr i 2} {
        set f [expr {double($i)/$bh}]
        set r [expr {int(0x2a*(1-$f)+0x0b*$f)}]; set g [expr {int(0x16*(1-$f)+0x0b*$f)}]
        set b [expr {int(0x4a*(1-$f)+0x14*$f)}]
        .shotBg.c create rectangle 0 $i $bw [expr {$i+2}] -fill [format #%02x%02x%02x $r $g $b] -width 0
    }
    if {$shotWob} {
        set font {Arial -130 bold}
        .shotBg.c create text [expr {$shotX0+$shotLw/3-$bx}] 15 -text 1 -anchor n -fill #2f6fd8 -font $font
        .shotBg.c create text [expr {$bw-30}] 15 -text 2 -anchor ne -fill #c8c8c8 -font $font
        .shotBg.c create text [expr {$bw-30}] [expr {$bh-15}] -text 3 -anchor se -fill #c8c8c8 -font $font
    }
    wm geometry .shotBg ${bw}x${bh}+$bx+$by
    wm attributes .shotBg -topmost 1
    update
    foreach w $shotWs {
        wm attributes $w -topmost 1
        raise $w
    }
    update
    after 1500 [list ShotReady "$bx $by $bw $bh"]
}
proc ShotReady {rect} {
    global shotDir
    set f [open $shotDir/screenshot_rect.tmp w]
    puts $f $rect
    close $f
    file rename -force $shotDir/screenshot_rect.tmp $shotDir/screenshot_rect.txt
}
after 2500 ShotArrange
