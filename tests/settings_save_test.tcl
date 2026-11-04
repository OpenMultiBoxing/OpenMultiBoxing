# Saving settings: through a temporary file (a refused write keeps the previous file), errors reported once
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

set errors {}
proc OmbError {title msg} {global errors; lappend errors $title}
proc WobError {title msg} {global errors; lappend errors $title}
proc Debug {msg} {}

set dir [file join [file normalize $env(TEMP)] settings_save_test_[pid]]
file mkdir $dir
set path [file join $dir settings.tcl]
Check "saved" [WriteSettingsFile $path "array set settings \{\n\ta\t1\n\}\n"] 1
set f [open $path]; set got [read $f]; close $f
Check "content" $got "array set settings \{\n\ta\t1\n\}\n"
Check "no temporary file left" [file exists $path.tmp] 0

# a write that can't happen (a directory where the temporary file goes): previous file kept, one message
file mkdir $path.tmp
Check "refused" [WriteSettingsFile $path "array set settings \{\n\ta\t2\n\}\n"] 0
set f [open $path]; set got [read $f]; close $f
Check "previous kept" $got "array set settings \{\n\ta\t1\n\}\n"
Check "reported" [llength $errors] 1
Check "reported once" [WriteSettingsFile $path "x"] 0
Check "still one message" [llength $errors] 1
file delete -force $dir

# File > Open settings folder: the settings dir in File Explorer, else its path in the clipboard and a message
set app_dir [file join $env(TEMP) settings_folder_test]
# Tk 9.1 crashes on clipboard clear before the main window really exists (in the app it's shown by then)
update
rename twapi::shell_execute shell_execute_orig
proc twapi::shell_execute {args} {global opened; lappend opened $args}
set opened {}
set errors {}
OpenSettingsFolder
Check "folder opened" $opened [list [list -path [file nativename $app_dir]]]
Check "no folder error" [llength $errors] 0
proc twapi::shell_execute {args} {error "no such folder"}
OpenSettingsFolder
Check "folder error reported" [llength $errors] 1
Check "folder path in the clipboard" [clipboard get] [file nativename $app_dir]
clipboard clear
rename twapi::shell_execute {}
rename shell_execute_orig twapi::shell_execute

# Edit raw settings: a window shows which file is edited, its button reloads the settings and closes it
proc UpdateHandles {} {}
proc LoadSettings {} {global reloaded; incr reloaded}
set reloaded 0
set pf [file join $app_dir test.tcl]
ReloadReminder $pf
Check "reminder shown" [winfo exists .reloadReminder] 1
Check "reminder names the file" [expr {[string first [file nativename $pf] [.reloadReminder.l cget -text]] >= 0}] 1
ReloadReminder $pf
Check "reminder reused" [llength [winfo children .reloadReminder]] 3
.reloadReminder.reload invoke
Check "reloaded" $reloaded 1
Check "reminder closed" [winfo exists .reloadReminder] 0
