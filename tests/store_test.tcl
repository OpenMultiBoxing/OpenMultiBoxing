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
rename http::geturl {}
rename http::geturl_orig http::geturl

file delete -force $exeDir
