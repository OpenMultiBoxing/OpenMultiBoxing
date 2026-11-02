# Light/dark appearance: ttk theme, classic widgets colors (explicit ones kept), back to the defaults
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

proc OverlayFontSizes {args} {global overlayStyles; incr overlayStyles}
set overlayStyles 0
set settings(overlayFontSize1) 48
AppearanceInit

toplevel .t
entry .t.e
listbox .t.lb
canvas .t.c
canvas .t.cx -background gray20
label .t.l
set defaults [list [.t.e cget -background] [.t.l cget -background] [.t.l cget -foreground]]
menu .mbar -type menubar
. configure -menu .mbar
foreach {name label} {file File help Help} {
    menu .mbar.$name -tearoff 0
    .mbar add cascade -label $label -menu .mbar.$name
}

# auto: the Windows app mode (registry), also before the settings are loaded
Check "windows mode is a boolean" [string is boolean -strict [WindowsAppsDark]] 1
rename WindowsAppsDark WindowsAppsDarkOrig
proc WindowsAppsDark {} {return 1}
Check "no setting yet: auto" [IsDark] 1
set settings(appearance) auto
proc WindowsAppsDark {} {return 0}
Check "auto light" [IsDark] 0
rename WindowsAppsDark {}
rename WindowsAppsDarkOrig WindowsAppsDark

set settings(appearance) dark
Check "dark" [IsDark] 1
ApplyAppearance
Check "dark theme" [ttk::style theme use] clam
Check "entry field color" [.t.e cget -background] $ombDark(field)
Check "listbox field color" [.t.lb cget -background] $ombDark(field)
Check "canvas field color" [.t.c cget -background] $ombDark(field)
Check "explicit color kept" [.t.cx cget -background] gray20
Check "label colors" [list [.t.l cget -background] [.t.l cget -foreground]] [list $ombDark(bg) $ombDark(fg)]
Check "label highlight" [.t.l cget -highlightbackground] $ombDark(bg)
Check "our styles again" $overlayStyles 1
Check "own menu bar" [list [. cget -menu] [winfo exists .darkMenuBar] [llength [winfo children .darkMenuBar]]] {{} 1 2}
set got {}
foreach mb [pack slaves .darkMenuBar] {
    lappend got [$mb cget -text] [$mb cget -menu]
}
Check "own menu bar menus" $got {File .mbar.file Help .mbar.help}
Check "alt key opens" [string match "*[lindex [pack slaves .darkMenuBar] end]*" [bind . <Alt-Key-h>]] 1
entry .t.e2
Check "new entry dark" [list [.t.e2 cget -background] [.t.e2 cget -highlightbackground]] \
    [list $ombDark(field) $ombDark(bg)]
ApplyAppearance
Check "unchanged: not again" $overlayStyles 1

set settings(appearance) light
Check "light" [IsDark] 0
ApplyAppearance
Check "light theme" [ttk::style theme use] vista
Check "native menu bar back" [list [. cget -menu] [winfo exists .darkMenuBar] [bind . <Alt-Key-h>]] {.mbar 0 {}}
Check "defaults back" [list [.t.e cget -background] [.t.l cget -background] [.t.l cget -foreground]] $defaults
Check "explicit color still kept" [.t.cx cget -background] gray20
entry .t.e3
Check "new entry default" [.t.e3 cget -background] [lindex $defaults 0]
Check "our styles for vista" $overlayStyles 2
destroy .t
