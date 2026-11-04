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
proc AfterSettings {} {}
proc ResetAll {} {}
proc MirrorsRebuild {} {}

proc ReadFile {path} {
    set f [open $path]
    set content [read $f]
    close $f
    return $content
}
proc ReadSettings {path} {
    return [lindex [ReadFile $path] 3]
}
proc WriteFile {path content} {
    set f [open $path w]
    puts -nonewline $f $content
    close $f
}

# on Default (no profiles used): everything in the base file, same format as always
array unset settings
array set settings {profile Default profiles {Default} games {World of Warcraft} lastUpdateChecked 1
    profilesNotRotated {Default} numWindows 2 layout default mirrors {} layoutMirrored 0}
SaveSettings
Check "default only format" [ReadFile $SETTINGS_FILE] "array set settings \{\n\tgames\t\{World of Warcraft\}\n\tlastUpdateChecked\t1\n\tlayout\tdefault\n\tlayoutMirrored\t0\n\tmirrors\t\{\}\n\tnumWindows\t2\n\tprofile\tDefault\n\tprofiles\tDefault\n\tprofilesNotRotated\tDefault\n\}\n"

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

# restart: the last profile is loaded, then Default has its own settings
array unset settings
array set settings {mirrors {} layoutMirrored 0}
LoadSettings
Check "restart in last profile" $settings(profile) Raid
Check "restart profile settings" $settings(numWindows) 5
Check "restart profiles list" $settings(profiles) {Default Raid}
set settings(profile) Default
LoadProfile
Check "switched to default" $settings(profile) Default
Check "default settings loaded" $settings(numWindows) 2
Check "default layout loaded" $settings(layout) default
set settings(profile) Raid
LoadProfile
Check "back to raid" $settings(numWindows) 5

# a new profile made from another one (File > New Profile... while on Raid): a copy of Raid, Default kept
set settings(profile) Dungeon
SaveSettings
Check "new profile from raid" [dict get [ReadSettings [ProfileFileName Dungeon]] numWindows] 5
Check "new profile listed" [dict get [ReadSettings $SETTINGS_FILE] profiles] {Default Raid Dungeon}
Check "new profile current" [dict get [ReadSettings $SETTINGS_FILE] profile] Dungeon
Check "default kept after new profile" [dict get [ReadSettings $SETTINGS_FILE] numWindows] 2
set settings(profile) Raid
SaveSettings

# a base file edited by hand (a comment): still read like LoadSettings does
WriteFile $SETTINGS_FILE "# my settings\narray set settings \{\n\tnumWindows\t4\n\tprofile\tRaid\n\}\n"
SaveSettings
Check "edited default kept" [dict get [ReadSettings $SETTINGS_FILE] numWindows] 4

# unreadable base file: everything, as before
WriteFile $SETTINGS_FILE "array set settings \{\n"
SaveSettings
Check "broken base replaced" [dict get [ReadSettings $SETTINGS_FILE] numWindows] 5
# missing base file too
file delete $SETTINGS_FILE
SaveSettings
Check "missing base written" [dict get [ReadSettings $SETTINGS_FILE] numWindows] 5

# back on Default: everything again
set settings(profile) Default
set settings(numWindows) 3
SaveSettings
Check "default saved again" [dict get [ReadSettings $SETTINGS_FILE] numWindows] 3
Check "raid untouched" [dict get [ReadSettings [ProfileFileName Raid]] numWindows] 5

file delete -force $app_dir
