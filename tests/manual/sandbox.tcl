# Put before the app's script (see soak.ps1, fg_test.ps1): real startup, but no hotkeys, no dialogs, no duplicate or
# "kill older instances" checks (so it can run next to your own OMB/WOB), output to sandbox.log next to the exe.
# Game windows ARE found and captured (soak.ps1 uses "Key test" windows).
if {[info commands ::sb_puts_orig] eq ""} {
    set sbLog [open [file join [file dirname [info nameofexecutable]] sandbox.log] w]
    fconfigure $sbLog -encoding utf-8 -buffering line
    rename ::puts ::sb_puts_orig
    rename twapi::find_windows twapi::sb_find_windows_orig
}
proc puts {args} {
    if {[llength $args] == 1 || ([llength $args] == 2 && [lindex $args 0] in {stdout stderr})} {
        ::sb_puts_orig $::sbLog "[clock format [clock seconds] -format %T] [lindex $args end]"
    } else {
        ::sb_puts_orig {*}$args
    }
}
proc bgerror {msg args} {
    puts "BGERROR: $msg\n$::errorInfo"
}
interp bgerror {} bgerror
proc tk_messageBox {args} {
    puts "MESSAGEBOX: $args"
    return no
}
proc ::tk::MessageBox {args} {
    puts "MESSAGEBOX (tk): $args"
    return no
}
# not your running OMB/WOB (duplicate check)
proc twapi::find_windows {args} {
    if {[string match "*Opensource MultiBoxing*" $args] || [string match "*WOB20*" $args]} {
        return {}
    }
    return [twapi::sb_find_windows_orig {*}$args]
}
proc twapi::get_process_ids {args} {return {}}
proc twapi::register_hotkey {args} {return 1}
proc twapi::unregister_hotkey {args} {}
set forceDebug 0
