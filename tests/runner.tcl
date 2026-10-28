# Copied as OpenMultiBoxing.tcl next to a copy of an OMB binary, which then sources it instead of its
# built-in code (after its own package requires: Tk, twapi, tooltip...). Runs $env(OMB_TEST_SCRIPT),
# output goes to $env(OMB_TEST_OUT) as the binary has no stdout.
rename ::puts ::tcl::puts_orig
# the app's procs (loaded by tests) redefine exit
rename ::exit ::tcl::exit_orig
set testOut [open $env(OMB_TEST_OUT) w]
fconfigure $testOut -encoding utf-8
proc puts {args} {
    global testOut
    if {[llength $args] == 1 || ([llength $args] == 2 && [lindex $args 0] in {stdout stderr})} {
        ::tcl::puts_orig $testOut [lindex $args end]
        flush $testOut
    } else {
        ::tcl::puts_orig {*}$args
    }
}
set testFailures 0
if {[catch {source -encoding utf-8 $env(OMB_TEST_SCRIPT)} err]} {
    puts "FAIL: error $err\n$errorInfo"
    incr testFailures
}
puts "[file tail $env(OMB_TEST_SCRIPT)]: [expr {$testFailures ? "$testFailures FAILED" : "OK"}]"
flush $testOut
::tcl::exit_orig [expr {$testFailures > 0}]
