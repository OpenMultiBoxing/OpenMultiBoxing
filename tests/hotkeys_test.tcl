# Hotkey names and the Hotkeys dialog
source [file join [file dirname [info script]] lib.tcl]
LoadProcs $env(OMB_TEST_APP) {
    "set hotkeyList *" "set hotkeyCapture *" "set hotkeyNote *" "set hotkeyConflictPending *"
    "array set hotkeyFailed *" "array set hotkeyDefaults *" "array set settings *" "for {set i 1} {$i<=12}*"
}

# --- names

foreach {mods vk expected} {
    2 0x71 Ctrl-F2
    6 0x43 Ctrl-Shift-C
    2 0xC0 Ctrl-0xC0
    7 0x60 Ctrl-Shift-Alt-NUMPAD0
    0 0x21 PGUP
    2 0x31 Ctrl-1
    8 0x41 Win-A
    3 0x2E Ctrl-Alt-DELETE
    4 0x0D Shift-ENTER
} {
    set hk [HotkeyName $mods $vk]
    Check "HotkeyName $mods $vk" $hk $expected
    # what twapi::register_hotkey will use
    Check "twapi parses $hk" [lmap x [twapi::_hotkeysyms_to_vk $hk] {expr {$x}}] [list $mods [expr {$vk}]]
}

foreach {hk expected} {
    Ctrl-1 {2 49}
    Ctrl-Shift-0xC0 {6 192}
    Ctrl-Shift-Alt-L {7 76}
} {
    Check "HotkeyToModsVk $hk" [HotkeyToModsVk $hk] $expected
}

foreach {hk expected} {
    Ctrl-0xC0 Ctrl-~
    Ctrl-Shift-0xC0 Ctrl-Shift-~
    Ctrl-0xBD Ctrl--
    Ctrl-F2 Ctrl-F2
    "" ""
} {
    Check "HotkeyDisplay $hk" [HotkeyDisplay $hk] $expected
}

Check "HotkeyLabel hk3,swap" [HotkeyLabel hk3,swap] "Swap window 3"
Check "HotkeyLabel hk,capture" [HotkeyLabel hk,capture] "Capture"

# --- dialog

set maxNumW 1
set hotkeyOk 1
set allHotKeys {}
set testMods 0
set registered 0
proc HeldModifiersMask {} {global testMods; return $testMods}
proc RegisterAllHotkeys {} {global registered; incr registered}
proc SaveSettings {} {}
proc UpdateHotkeyTexts {} {}
proc UpdateHandles {} {}
proc OmbMessage {args} {return yes}
font create WOBBold {*}[font actual [::ttk::style lookup TButton -font]] -weight bold

proc Key {var vk {mods 0}} {
    global testMods hotkeyButtons
    set testMods $mods
    event generate $hotkeyButtons($var) <KeyPress> -keycode $vk
    update
}

HotkeysDialog
update
set statusHeight [winfo reqheight .hotkeys.status]
Check "window 12 row" [$hotkeyButtons(hk12,swap) cget -text] Ctrl-Shift-F12
Check "no window 13 row" [winfo exists .hotkeys.w.s13] 0
Check "~ shown" [$hotkeyButtons(hk,swapNextWindow) cget -text] "Ctrl-~"

$hotkeyButtons(hk1,focus) invoke
focus -force $hotkeyButtons(hk1,focus)
update
Check "capturing" $hotkeyCapture hk1,focus
Check "capture text" [$hotkeyButtons(hk1,focus) cget -text] "Press keys..."
Key hk1,focus 0x11 2
Check "modifier alone keeps capturing" $hotkeyCapture hk1,focus
Key hk1,focus 0x71 2
Check "captured" $settings(hk1,focus) Ctrl-F2
Check "duplicate cleared" $settings(hk2,focus) ""
Check "capture ended" $hotkeyCapture ""
Check "hotkeys registered again" $registered 1
Check "note" [.hotkeys.status cget -text] "Ctrl-F2 was used by Focus window 2, now cleared."
update
Check "status stays one line" [winfo reqheight .hotkeys.status] $statusHeight

$hotkeyButtons(hk,capture) invoke
Key hk,capture 0x1B
Check "Esc cancels" $settings(hk,capture) Ctrl-Shift-C
Check "Esc ends capture" $hotkeyCapture ""

event generate $hotkeyButtons(hk,capture) <Button-3>
update
Check "right click clears" $settings(hk,capture) ""

set settings(hk,focusMain) Ctrl-Shift-W
set hotkeyFailed(hk,focusMain) "Focus main window"
HotkeysDialogRefresh
Check "failed in red" [string match *HotkeyFailed.TButton [$hotkeyButtons(hk,focusMain) cget -style]] 1
Check "failed listed" [string match "*Focus main window (Ctrl-Shift-W)*" [.hotkeys.status cget -text]] 1
array unset hotkeyFailed

Check "undo steps" [llength $hotkeyUndo] 2
Check "undo enabled" [.hotkeys.b.undo instate disabled] 0
HotkeysUndo
Check "undo right click" $settings(hk,capture) Ctrl-Shift-C
Check "undo note" [.hotkeys.status cget -text] "Undone: Capture back to Ctrl-Shift-C."
event generate .hotkeys <Control-z>
update
Check "ctrl-z undo hk1" $settings(hk1,focus) Ctrl-F1
Check "ctrl-z undo hk2" $settings(hk2,focus) Ctrl-F2
Check "undo note both" [.hotkeys.status cget -text] "Undone: Focus window 1 back to Ctrl-F1, Focus window 2 back to Ctrl-F2."
update
Check "long note stays one line" [winfo reqheight .hotkeys.status] $statusHeight
Check "note wraps at window width" [.hotkeys.status cget -wraplength] [winfo width .hotkeys.status]
Check "undo disabled at start" [.hotkeys.b.undo instate disabled] 1
HotkeysUndo
Check "nothing to undo" $settings(hk1,focus) Ctrl-F1

event generate $hotkeyButtons(hk,capture) <Button-3>
update
Check "clear undoable" [llength $hotkeyUndo] 1
event generate $hotkeyButtons(hk,capture) <Button-3>
update
Check "no-op change not undoable" [llength $hotkeyUndo] 1
set settings(hk13,focus) Ctrl-Alt-1
HotkeysDefaults
Check "defaults capture" $settings(hk,capture) Ctrl-Shift-C
Check "defaults hk13" [info exists settings(hk13,focus)] 0
HotkeysUndo
Check "undo defaults hk13" $settings(hk13,focus) Ctrl-Alt-1
Check "undo defaults capture" $settings(hk,capture) ""

HotkeysDialogClose
Check "closed" [winfo exists .hotkeys] 0
