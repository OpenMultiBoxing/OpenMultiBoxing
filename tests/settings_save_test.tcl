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
