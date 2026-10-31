# Loading a profile file
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP) {set SETTINGS_*}

set app_dir [file normalize [file join $env(TEMP) profile_load_test_[pid]]]
file mkdir $app_dir
proc AfterSettings {} {}
proc ResetAll {} {}
proc MirrorsRebuild {} {}
set errors {}
proc WobError {args} {global errors; lappend errors $args}
proc OmbError {args} {global errors; lappend errors $args}

proc WriteProfile {name content} {
    global app_dir
    set f [open [ProfileFileName $name] w]
    puts $f $content
    close $f
}

WriteProfile Mirrored {array set settings {numWindows 3 layoutMirrored 1 mirrors {{source main area {0 0 1 1} geom {1 2 3 4} top 1}}}}
WriteProfile Old {array set settings {numWindows 2}}
WriteProfile Broken "array set settings \{"

array set settings {profile Mirrored mirrors {} layoutMirrored 0 numWindows 0}
LoadProfile
Check "mirrored loaded" $settings(layoutMirrored) 1
Check "mirrors loaded" [llength $settings(mirrors)] 1
Check "layout checkbox follows" $layoutMirrored 1

# saved before mirrors existed: not the previous profile's
set settings(profile) Old
LoadProfile
Check "old profile not mirrored" $settings(layoutMirrored) 0
Check "old profile no mirrors" $settings(mirrors) {}
Check "old profile loaded" $settings(numWindows) 2
Check "layout checkbox off" $layoutMirrored 0

set settings(profile) Mirrored
LoadProfile
set settings(profile) Broken
LoadProfile
Check "broken profile error" [llength $errors] 1
Check "broken profile keeps mirrors" [llength $settings(mirrors)] 1
Check "broken profile back to default" $settings(profile) Default

# the previous profile's mirrors are rebuilt before ResetAll refreshes them
set calls {}
proc ResetAll {} {global calls; lappend calls ResetAll}
proc MirrorsRebuild {} {global calls; lappend calls MirrorsRebuild}
wm withdraw .
label .logo
set settings(profile) Old
LoadProfile
Check "mirrors rebuilt before reset" $calls {MirrorsRebuild ResetAll}
destroy .logo

file delete -force $app_dir
