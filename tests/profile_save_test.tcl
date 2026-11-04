# Saving a profile: the base settings file is also the Default profile, only its shared settings change
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP) {set SETTINGS_*}

set app_dir [file normalize [file join $env(TEMP) profile_save_test_[pid]]]
file mkdir $app_dir
set SETTINGS_FILE [file join $app_dir $SETTINGS_BASE]
set isPaused 0
set prevOL 0
proc UpdateProfilesMenu {} {}
proc Debug {msg} {}

proc ReadSettings {path} {
    set f [open $path]
    set content [read $f]
    close $f
    return [lindex $content 3]
}

# on Default: everything in the base file
array set settings {profile Default profiles {Default} games {World of Warcraft} lastUpdateChecked 1
    profilesNotRotated {Default} numWindows 2 layout default}
SaveSettings
set base [ReadSettings $SETTINGS_FILE]
Check "default saved" [dict get $base numWindows] 2

# a new profile: its own file, the base file keeps Default's settings but gets the shared ones
set settings(profile) Raid
array set settings {numWindows 5 layout raid lastUpdateChecked 2 games {World of Warcraft Other}}
SaveSettings
set raid [ReadSettings [ProfileFileName Raid]]
Check "profile saved" [dict get $raid numWindows] 5
Check "profile file has no shared settings" [dict exists $raid profile] 0
set base [ReadSettings $SETTINGS_FILE]
Check "default kept" [dict get $base numWindows] 2
Check "default layout kept" [dict get $base layout] default
Check "current profile saved" [dict get $base profile] Raid
Check "profiles list saved" [dict get $base profiles] {Default Raid}
Check "games saved" [dict get $base games] {World of Warcraft Other}
Check "update check saved" [dict get $base lastUpdateChecked] 2

# a setting Default doesn't have yet (newer version): from the current settings
set settings(newSetting) 7
SaveSettings
Check "new setting filled in" [dict get [ReadSettings $SETTINGS_FILE] newSetting] 7
Check "default still kept" [dict get [ReadSettings $SETTINGS_FILE] numWindows] 2

# unreadable base file: everything, as before
set f [open $SETTINGS_FILE w]
puts $f "array set settings \{"
close $f
SaveSettings
Check "broken base replaced" [dict get [ReadSettings $SETTINGS_FILE] numWindows] 5

# back on Default: everything again
set settings(profile) Default
set settings(numWindows) 3
SaveSettings
Check "default saved again" [dict get [ReadSettings $SETTINGS_FILE] numWindows] 3
Check "raid untouched" [dict get [ReadSettings [ProfileFileName Raid]] numWindows] 5

file delete -force $app_dir
