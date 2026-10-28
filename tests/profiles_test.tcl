# Next/previous profile rotation
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

set loaded {}
proc LoadProfile {} {global settings loaded; lappend loaded $settings(profile)}

proc Switch {dir} {
    global loaded
    set loaded {}
    SwitchProfile $dir
    return $loaded
}

array set settings {profiles {Default A B C} profilesNotRotated {Default B} profile Default}
Check "rotated" [RotatedProfiles] {A C}
Check "next from outside the rotation" [Switch 1] A
Check "next" [Switch 1] C
Check "next wraps" [Switch 1] A
Check "previous wraps" [Switch -1] C
set settings(profile) Default
Check "previous from outside the rotation" [Switch -1] C
set settings(profilesNotRotated) {Default A B}
Check "only one in rotation" [Switch 1] {}
set settings(profilesNotRotated) {Default A B C}
Check "none in rotation" [Switch 1] {}
