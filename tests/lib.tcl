# Test helpers, sourced by the *_test.tcl files

# Defines the procs of an OMB/WOB .tcl (and the top level commands matching one of the patterns)
# without running the app
proc LoadProcs {file {patterns {}}} {
    set f [open $file]
    fconfigure $f -encoding utf-8
    set cmd ""
    while {[gets $f line] >= 0} {
        append cmd $line "\n"
        if {![info complete $cmd]} {
            continue
        }
        set trimmed [string trim $cmd]
        if {[string match "proc *" $trimmed]} {
            uplevel #0 $cmd
        } else {
            foreach p $patterns {
                if {[string match $p $trimmed]} {
                    uplevel #0 $cmd
                    break
                }
            }
        }
        set cmd ""
    }
    close $f
}

proc Check {name got expected} {
    global testFailures
    if {$got eq $expected} {
        puts "ok   $name"
    } else {
        puts "FAIL $name: got \"$got\" expected \"$expected\""
        incr testFailures
    }
}

set forceDebug 0
array set settings {DEBUG 0}
