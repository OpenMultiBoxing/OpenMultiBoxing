# Put after the app's script (see soak.ps1): once the "Key test" windows are captured, swaps every 2s, typing every 2s
# (only when a captured window is in front), mouse moves over the mirrors every 1s (a click every 4th), mirrors rebuilt
# every minute, Window Layout opened every 5 min, appearance flipped every 10 min; with -Toggles also key/mouse
# broadcast and mirrors shown/hidden every 1-2.5s. Metrics every 30s to soak.csv; exits after soak_minutes.txt minutes.
set soakDir [file dirname [info nameofexecutable]]
set soakMinutes 40
catch {set soakMinutes [string trim [read [set f [open $soakDir/soak_minutes.txt]]]]; close $f}
set soakToggles [file exists $soakDir/soak_toggles.txt]
set soakStart [clock seconds]
set soakSwaps 0
set soakKeys 0
set soakMouse 0
package require cffi
cffi::Wrapper create ::soakUser32 [file join $env(windir) system32 user32.dll]
cffi::Wrapper create ::soakKernel32 [file join $env(windir) system32 kernel32.dll]
::soakKernel32 stdcall {GetCurrentProcess SoakCurrentProcess} ulonglong {}
::soakUser32 stdcall {GetGuiResources SoakGuiResources} ulong {h ulonglong flags ulong}
set soakCsv [open $soakDir/soak.csv w]
fconfigure $soakCsv -buffering line
sb_puts_orig $soakCsv "minutes,swaps,handles,privateKB,workingSetKB,gdi,user,afters,toplevels,images,globals,captured,keys,mouse"
proc SoakMetrics {} {
    global soakCsv soakStart soakSwaps maxNumW soakKeys soakMouse
    set i [twapi::get_process_info [pid] -handlecount -pagefilebytes -workingset]
    set h [SoakCurrentProcess]
    set tops 0
    foreach w [winfo children .] {
        if {[winfo toplevel $w] eq $w} {incr tops}
    }
    sb_puts_orig $soakCsv [join [list [format %.1f [expr {([clock seconds]-$soakStart)/60.0}]] $soakSwaps \
        [dict get $i -handlecount] [expr {[dict get $i -pagefilebytes]/1024}] [expr {[dict get $i -workingset]/1024}] \
        [SoakGuiResources $h 0] [SoakGuiResources $h 1] [llength [after info]] $tops [llength [image names]] \
        [llength [info globals]] [expr {$maxNumW-1}] $soakKeys $soakMouse] ,]
}
proc SoakEvery {ms script} {
    if {[catch {uplevel #0 $script} err]} {
        puts "SOAK ERROR $script: $err"
    }
    after $ms [list SoakEvery $ms $script]
}
proc SoakSwap {} {
    global soakSwaps
    SwapNextWindow
    incr soakSwaps
}
# Keys only when a captured game window is in front (never type into another app); not in WOB (it removes the input
# functions at startup, compliance)
proc SoakKeys {} {
    global soakKeys
    if {[info commands MouseBroadcast] eq ""} {
        return
    }
    if {[catch {twapi::get_foreground_window} fg] || $fg eq "" || [IsOurs $fg] < 3} {
        return
    }
    twapi::send_keys [lindex {abc xyz {hello } 123 {soak }} [expr {[incr soakKeys] % 5}]]
}
# Mouse over a random mirror (region ones and the mirrored layout's), a click every 4th time; not in WOB either
proc SoakMouse {} {
    global soakMouse
    if {[info commands MouseBroadcast] eq ""} {
        return
    }
    set ws {}
    foreach w [winfo children .] {
        if {[regexp {^\.l?mirror[0-9]+$} $w] && [winfo ismapped $w]} {
            lappend ws $w
        }
    }
    if {![llength $ws]} {
        return
    }
    set w [lindex $ws [expr {int(rand()*[llength $ws])}]]
    twapi::move_mouse [expr {[winfo rootx $w] + int(rand()*[winfo width $w])}] \
        [expr {[winfo rooty $w] + int(rand()*[winfo height $w])}]
    if {[incr soakMouse] % 4 == 0} {
        after 100 {twapi::click_mouse_button left}
    }
}
proc SoakLayout {} {
    WindowLayout
    after 5000 {catch {destroy .layout}}
}
proc SoakAppearance {} {
    global settings
    set settings(appearance) [expr {$settings(appearance) eq "dark" ? "light" : "dark"}]
    puts "SOAK appearance $settings(appearance)"
    ApplyAppearance
}
proc SoakToggle {what} {
    # key/mouse broadcast: OMB only (WOB has no MouseBroadcast, its RRToggle just says RR is gone)
    if {$what eq "RRToggle" && [info commands MouseBroadcast] eq ""} {
        return
    }
    if {[info commands $what] ne ""} {
        $what
    }
}
proc SoakCheckEnd {} {
    global soakStart soakMinutes
    if {[clock seconds] - $soakStart >= $soakMinutes*60} {
        SoakMetrics
        puts "SOAK done"
        exit 0
    }
}
after 20000 {
    puts "SOAK start, captured [expr {$maxNumW-1}]"
    set soakStart [clock seconds]
    SoakMetrics
    # key and mouse broadcast on (OMB; WOB has neither)
    SoakToggle RRToggle
    SoakToggle MouseBroadcast
    SoakEvery 2000 SoakSwap
    after 700 {SoakEvery 2000 SoakKeys}
    after 1300 {SoakEvery 1000 SoakMouse}
    after 1000 {SoakEvery 60000 MirrorsRebuild}
    after 1500 {SoakEvery 300000 SoakLayout}
    after 600000 {SoakEvery 600000 SoakAppearance}
    after 30000 {SoakEvery 30000 SoakMetrics}
    if {$soakToggles} {
        SoakEvery 1500 {SoakToggle RRToggle}
        after 300 {SoakEvery 2500 {SoakToggle MouseBroadcast}}
        after 600 {SoakEvery 1000 {SoakToggle MirrorsToggle}}
    }
    SoakEvery 10000 SoakCheckEnd
}
