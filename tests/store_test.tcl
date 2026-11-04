# Microsoft Store install detection and its settings directory
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP)

set exeDir [file normalize [file join $env(TEMP) store_test_[pid]]]
file mkdir $exeDir
Check "not a store install" [StoreDataDir $exeDir] ""

close [open [file join $exeDir OpenMultiBoxing.store] w]
set dir [StoreDataDir $exeDir]
Check "store settings dir name" [file tail $dir] "OpenMultiBoxing"
Check "store settings dir in Documents" [file isdirectory [file dirname $dir]] 1
Check "store settings dir is the shell's Documents" [file dirname $dir] \
    [file normalize [twapi::get_shell_folder csidl_personal]]

# the package's Files\ copied to the settings dir: .bat only when missing, .txt when changed
proc WriteTestFile {path content} {set fd [open $path w]; puts -nonewline $fd $content; close $fd}
proc ReadTestFile {path} {set fd [open $path]; set c [read $fd]; close $fd; return $c}
set storeDir [file join $exeDir docs]
file mkdir [file join $exeDir Files] $storeDir
WriteTestFile [file join $exeDir Files launchwow.bat] "bat v1"
WriteTestFile [file join $exeDir Files LaunchWoW.txt] "txt v1"
StoreCopyFiles $exeDir $storeDir
Check "store bat copied" [ReadTestFile [file join $storeDir launchwow.bat]] "bat v1"
Check "store txt copied" [ReadTestFile [file join $storeDir LaunchWoW.txt]] "txt v1"
WriteTestFile [file join $storeDir launchwow.bat] "user edit"
WriteTestFile [file join $exeDir Files launchwow.bat] "bat v2"
WriteTestFile [file join $exeDir Files LaunchWoW.txt] "txt v2"
StoreCopyFiles $exeDir $storeDir
Check "store bat edit kept" [ReadTestFile [file join $storeDir launchwow.bat]] "user edit"
Check "store txt updated" [ReadTestFile [file join $storeDir LaunchWoW.txt]] "txt v2"
WriteTestFile [file join $exeDir Files LaunchWoW.txt] "txt v3"
StoreCopyFiles $exeDir $storeDir
Check "store txt same size updated" [ReadTestFile [file join $storeDir LaunchWoW.txt]] "txt v3"
StoreCopyFiles [file join $exeDir nofiles] $storeDir
Check "store no Files dir" [lsort [glob -tails -directory $storeDir *]] {LaunchWoW.txt launchwow.bat}
# a refused copy (Controlled folder access) is reported, once per session like the settings save errors
proc OmbMessage {args} {global copyErrors; lappend copyErrors $args}
set blocked [file join $exeDir Files launchwow.bat notadir]
StoreCopyFiles $exeDir $blocked
Check "store copy error reported" [llength $copyErrors] 1
Check "store copy error message" [string match "*Controlled folder access*" [lindex $copyErrors 0]] 1
StoreCopyFiles $exeDir $blocked
Check "store copy error shown once" [llength $copyErrors] 1
unset settingsSaveErrorShown

# no update check (nor network access) from the Store build
package require http
set inStore 1
proc OmbMessage {args} {global messages; lappend messages $args}
rename http::geturl http::geturl_orig
proc http::geturl {args} {error "network access"}
CheckForUpdates 1
Check "silent store update check" [info exists messages] 0
CheckForUpdates 0
Check "store update check message" [string match "*Microsoft Store*" [lindex $messages 0]] 1
# yes opens the Store page, so do the binary releases
proc StorePage {} {global storePage; incr storePage}
set storePage 0
proc OmbMessage {args} {return no}
CheckForUpdates 0
Check "store page not opened" $storePage 0
proc OmbMessage {args} {return yes}
CheckForUpdates 0
Check "store page opened" $storePage 1
Releases
Check "store page for releases" $storePage 2
rename http::geturl {}
rename http::geturl_orig http::geturl

file delete -force $exeDir
