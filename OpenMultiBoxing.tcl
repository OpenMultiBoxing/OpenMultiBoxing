#  WowOpenBox / OpenMultiboxing by MooreaTV <moorea@ymail.com> (c) 2020-2023 All rights reserved
#  Open Source Software licensed under GPLv3 - No Warranty
#  (contact the author if you need a different license)
#
#  The GNU General Public License does not permit incorporating this work
#  into proprietary programs.
#
#  Releases detail/changes are on https://github.com/OpenMultiBoxing/OpenMultiBoxing/releases
#
package require Tk
package require twapi
package require http
package require twapi_crypto
http::register https 443 ::twapi::tls_socket
package require tooltip
package require tkdnd
namespace import tooltip::tooltip
# tkk native
ttk::style theme use winnative
# handle updates from wrong/old binary
#catch {
#    package require cffi
#    cffi::Wrapper create user32 [file join $env(windir) system32 user32.dll]
#    user32 function GetKeyboardState int {state {uchar[256] out}}
#}

# start not showing top level for error dialogs
wm state . withdrawn
# Update in progress detected
array set updateCheck {}
catch {array set updateCheck [info frame -1]}
if {[info exists updateCheck(proc)] && $updateCheck(proc)=="::CheckForUpdates"} {
    puts stderr "Update detected!"
    set isUpdate 1
    # keep oldVersion as the binary/bootstrap's version even in update
    if {![info exists oldVersion]} {
        set oldVersion $vers
    }
    set previousVersion $vers
    # cancel all background tasks
    after cancel [after info]
} else {
    set isUpdate 0
    if {[info exists vers] && ![info exists oldVersion]} {
        set oldVersion $vers
    }
}


set vers "dev"

proc Debug {msg} {
    global settings forceDebug
    if {$forceDebug || $settings(DEBUG)} {
        puts "DEBUG $msg"
    }
}


proc EnableDisableWindows {enable} {
    if {$enable} {
        catch {tk busy forget .layout}
        catch {tk busy forget .overlayConfig}
        catch {tk busy forget .}
    } else {
        catch {tk busy hold .}
        catch {tk busy hold .overlayConfig}
        catch {tk busy hold .layout}
        update
    }
}


proc OmbMessage {args} {
    global hotkeyOk
    set hotkeyOk 0
    Debug "OMB message $args"
    EnableDisableWindows 0
    set ret [tk_messageBox {*}$args]
    EnableDisableWindows 1
    set hotkeyOk 1
    return $ret
}

proc OmbError {title msg} {
    puts stderr "Error $title: $msg"
    OmbMessage -type ok -icon error -title $title -message $msg
}

set SETTINGS_PREFIX "OpenMultiBoxingSettings"
set SETTINGS_SUFFIX ".tcl"
set SETTINGS_BASE "$SETTINGS_PREFIX$SETTINGS_SUFFIX"

# From version 7.0.0 we support basic key broadcasting instead of Round Robin keys
# Many function and variables have "RR" in the name but actually now are about broadcasting.
# I started with supporting both (see the RRlabel variable) but it was getting quite messy bunch
# of if all over so I decided to drop RR (it's there in WOB and previous versions too)
# and update the RR code to use broadcasting instead. It does mean some options probably don't make
# sense anymore and need further cleanup.
# Note that PostMessage for key broadcasting, unlike RR has the nice benefit of not needing the special
# _RR binary wrapper so that's one less "configuration" to worry about.

set rrOn 0
# Unlike for RoundRobin to work, we don't need the special binary wrapper so Broadcasting is supported by default
set hasRR 1
set hasBR 1

proc HasArg {argName} {
    global argv
    expr {[lsearch $argv $argName]!=-1}
}

if {![info exists wobInitDone]} {
    set wobInitDone 1
    set forceDebug 0
    array set settings {DEBUG 0}
    if {[HasArg "-debug"]} {
        set forceDebug 1
        catch {console show}
        Debug "OMB $vers called with -debug"
    }
    if {[HasArg "-profile"]} {
        set initProfile [lindex $argv end]
        Debug "OMB requested profile '$initProfile'"
    }
    # Settings and updated code directory
    # -- App utils - save settings
    set script_path [file normalize [info script]]
    set app_dir [file dirname $script_path]
    set img_dir [file dirname $script_path]
    set script_name [file tail $script_path]
    Debug "Original app_dir: $app_dir (script [info script])"
    # Normalize appdir in case we're inside the binary
    set inExe [regsub -nocase {/[^/]+\.exe/app$} $app_dir {} app_dir]
    Debug "Post exe detection app_dir: $app_dir"
    set SETTINGS_FILE [file join $app_dir $SETTINGS_BASE]
    set update_path [file join $app_dir $script_name]
    Debug "Base settings: $SETTINGS_FILE"
    if {$inExe} {
        # We're inside the exe, check for updated code
        Debug "In EXE, checking for code outside: $update_path"
        if {[file readable $update_path]} {
            if {[catch {source -encoding utf-8 $update_path} err]} {
                OmbError "OMB error: update file error" \
                 "Please delete [file nativename $update_path] and restart\n\n$err\n$errorInfo"
                exit 1
            } else {
                Debug "Control passed to local file $update_path"
                return
            }
        }
    }
}

proc CheckForUpdates {silent} {
    global vers update_path settings errorInfo
    set url "https://api.github.com/repos/OpenMultiBoxing/OpenMultiBoxing/releases/latest"
    if {[catch {set token [http::geturl $url]} err]} {
        OmbError "OpenMultiBoxing network error" "Url fetch error $err"
        return
    }
    set settings(lastUpdateChecked) [clock seconds]
    SaveSettings
    set body [http::data $token]
    if {[string match "*/tag/$vers\",*" $body]} {
        if {$silent} {
            Debug "Already running latest $vers"
            return
        }
        OmbMessage -type ok -icon info -title "Already uptodate" \
            -message "You're already running the latest version $vers"
        return
    }
    if {![regexp {browser_download_url":"(https://github\.com/OpenMultiBoxing/OpenMultiBoxing/releases/download/[^"]+\.tcl)"} $body all updateUrl]} {
        Debug "--- Update not found in $url ---\n$body\n--- end of $url ---"
        OmbError "Update Error" "Couldn't find update in latest release - please report as a bug"
        return
    }
    set name ""
    set description ""
    regexp {"name":"(.*?)",} $body all name
    regexp "\"body\":\"(.*?)\"(,|\})" $body all description
    regsub -all {\\r} $description "" description
    regsub -all {\\n} $description "\n" description
    set description [string trimright $description]
    Debug "Found update $updateUrl : $name ($description)"
    if {![regexp {/(v[^/]+)/} $updateUrl all newVersion]} {
        OmbError "Update Error" "Couldn't find version in update url: $updateUrl\nPlease report this bug!"
        return
    }
    set doUpdate [OmbMessage -type yesno -icon question -title "Update Available" \
            -message "$newVersion is available:\n\n$name\n\n$description\n\nDo you want to install it?"]
    Debug "Do update is $doUpdate"
    if {$doUpdate=="no"} {
        return
    }
    if {[catch {set token [http::geturl $updateUrl]} err]} {
        OmbError "Update error" "Update fetch error for\n$updateUrl\n$err"
        return
    }
    set ncode [http::ncode $token]
    if {$ncode == 301 || $ncode == 302} {
        upvar #0 $token state
        array set meta $state(meta)
        set location "not-found!"
        if {[info exists meta(Location)]} {
            set location $meta(Location)
        }
        if {[info exists meta(location)]} {
            set location $meta(location)
        }
        Debug "Got a redirect $ncode: $location"
        if {[catch {set token [http::geturl $location]} err]} {
            OmbError "Update error" "Update fetch error for redirected\n$location\n$err"
            return
        }
        set ncode [http::ncode $token]
    }
    if {$ncode != 200} {
        OmbError "Update error" "Update error code $ncode for\n$updateUrl"
        return
    }
    set body [http::data $token]
    set backup_path ${update_path}.$vers.bak
    # delete older backups
    catch {file delete {*}[glob ${update_path}.*.bak]}
    # can error when in exe...
    catch {file rename -force $update_path $backup_path}
    set f [open $update_path w+]
    fconfigure $f -translation binary
    puts -nonewline $f $body
    close $f
    Debug "Updated $update_path"
    OmbMessage -type ok -icon info -title "Download complete" \
            -message "Backed up previous version as $backup_path - ready to restart with $newVersion"
    if {[catch {uplevel #0 [list source -encoding utf-8 $update_path]} err]} {
       OmbError "Update error" "Error in new downloaded script:\n$err\n$errorInfo\n\nPlease screenshot this and report this bug!"
       return
    }
    Debug "Control passed successfully to updated file $newVersion"
}


# -- UI

proc NewProfile {} {
    global settings profileName
    set t .newProfile
    set profileName {}
    EnableDisableWindows 0
    toplevel $t
    wm resizable $t 0 0
    wm title $t "OMB New Profile Name..."
    ttk::label  $t.l -text "Save settings as new Profile named:"
    ttk::entry  $t.e -textvar profileName
    bind $t.e <Return> {set doneDialog 1}
    ttk::button $t.ok -text OK -command {set doneDialog 1}
    ttk::button $t.cancel -text Cancel -command "set profileName {}; set doneDialog 1"
    bind $t.e <Escape> "$t.cancel invoke"
    grid $t.l - -sticky news -padx 4 -pady 4
    grid $t.e - -sticky news -padx 4 -pady 4
    grid $t.ok $t.cancel -padx 4 -pady 4
    focus $t.e
    UpdateHandles
    vwait doneDialog
    destroy $t
    EnableDisableWindows 1
    if {$profileName!=""} {
        Debug "New profile dialog returned $profileName"
        set settings(profile) $profileName
        SaveSettings
    } else {
        Debug "New profile cancelled"
    }
}

proc ProfileFileName {profile} {
    global app_dir SETTINGS_PREFIX SETTINGS_SUFFIX
    set p $profile
    if {$p=="Default"} {
        set p ""
    }
    set path [file join $app_dir "$SETTINGS_PREFIX$p$SETTINGS_SUFFIX"]
    Debug "For profile $profile path: $path"
    return $path
}

proc RefreshProfiles {} {
    global app_dir SETTINGS_PREFIX SETTINGS_SUFFIX settings
    set settings(profiles) [list "Default"]
    foreach fn [glob [file join $app_dir "${SETTINGS_PREFIX}*${SETTINGS_SUFFIX}"]] {
        # suffix starts with a . so \ it
        set p ""
        regexp "^.*${SETTINGS_PREFIX}(.*)\\${SETTINGS_SUFFIX}$" $fn all p
        Debug "Found file $fn -> $p"
        if {$p==""} {
            continue
        }
        lappend settings(profiles) $p
    }
    if {[lsearch -exact $settings(profiles) $settings(profile)] == -1} {
        OmbError "Profile error" "Profile $settings(profile) not found; resetting to Default"
        set settings(profile) "Default"
    }
    UpdateProfilesMenu
    LoadProfile
}

proc SaveSettings {args} {
    global SETTINGS_FILE settings app_dir isPaused prevOL
    if {$isPaused && $prevOL} {
        set settings(showOverlay) 1
    }
    set p $settings(profile)
    if {$p!="Default"} {
        Debug "SaveSettings for profile $p"
        if {[lsearch $settings(profiles) $p]==-1} {
            Debug "New profile $p"
            lappend settings(profiles) $p
            .mbar.profile insert 1 radiobutton -label $p -variable settings(profile) -command LoadProfile
        }
        set pMode 1
        set pf [ProfileFileName $p]
        set f [open $pf w+]
        fconfigure $f -encoding utf-8
        puts $f "array set settings {"
        foreach i [lsort [array names settings]] {
            if {$i=="profile" || $i=="profiles" || $i=="games" || $i=="lastUpdateChecked"} {
                continue
            }
            #  Debug "saving $i \"$settings($i)\""
            puts $f "\t$i\t[list $settings($i)]"
        }
        puts $f "}"
        close $f
    }
    Debug "SaveSettings base $SETTINGS_FILE (from cb $args)"
    if {[catch {open $SETTINGS_FILE w+} f]} {
        OmbError "Error saving settings" \
            "Unable to save settings: $f\n\nPlease do not put OpenMultiBoxing*.exe\nin a system/special/protected folder\nput them on your Desktop instead for instance."
        return
    }
    fconfigure $f -encoding utf-8
    puts $f "array set settings {"
    foreach i [lsort [array names settings]] {
        #  Debug "saving $i \"$settings($i)\""
        puts $f "\t$i\t[list $settings($i)]"
    }
    puts $f "}"
    close $f
}

proc LoadProfile {} {
    global settings
    set profile $settings(profile)
    set pf [ProfileFileName $profile]
    if {[catch {source -encoding utf-8 $pf} err]} {
        puts stderr "Error sourcing profile $pf\n$err"
        OmbError "OpenMultiBoxing profile error" \
            "Your $pf has an error: $err\nYou can remove it and use Refresh Profiles in the menu."
        set settings(profile) "Default"
        return
    }
    # Otherwise can be reset when switching from Profile N back to Default
    set settings(profile) $profile
    AfterSettings
    ResetAll
}

proc LoadSettings {} {
    global SETTINGS_FILE settings app_dir
    if {[winfo exists .b1]} {
        .b1 configure -text "Edit Settings" -command EditSettings
    }
    if {[file exists $SETTINGS_FILE]} {
        if {[catch {source -encoding utf-8 $SETTINGS_FILE} err]} {
            puts stderr "Could not source $SETTINGS_FILE\n$err"
            OmbError "OpenMultiBoxing settings error" \
                "Your $SETTINGS_FILE has an error: $err"
        } else {
            if {$settings(profile)!="Default"} {
                LoadProfile
            }
        }
    }
    AfterSettings
}

proc UnregisterHotkeys {} {
    global allHotKeys
    Debug "Unregistering previous hotkeys"
    foreach hk $allHotKeys {
        twapi::unregister_hotkey $hk
    }
}


proc IsInside {x y x1 y1 x2 y2} {
    expr {$x>=$x1 && $x<=$x2 && $y>=$y1 && $y<=$y2}
}

proc Offscreen {x y} {
    global displayInfo
    if {![info exists displayInfo]} {
        # only extract it the first time
        set displayInfo [twapi::get_multiple_display_monitor_info]
        Debug "displayInfo = $displayInfo"
    }
    set i 0
    foreach monitor $displayInfo {
        incr i 1
        array set info $monitor
        lassign $info(-extent) x1 y1 x2 y2
        Debug "Monitor $i Extent   $x1,$y1  - $x2,$y2"
        if {[IsInside $x $y $x1 $y1 $x2 $y2]} {
            return false
        }
    }
    return true
}

proc OffscreenGeometryCheck {} {
    global settings
    foreach k {mainWindowGeometry clipGeometry} {
        if {![info exists settings($k)]} {
            continue
        }
        regexp {\+(.*?)\+(.*?)$} $settings($k) all x y
        Debug "geometry for $k is at $x,$y"
        if {[Offscreen $x $y]} {
            Debug "unsetting offscreen geometry $k"
            unset settings($k)
        }
    }
}

proc AfterSettings {} {
    global settings maxNumW slot2handle
    # Handle off screen/geometry change
    OffscreenGeometryCheck
    if {$settings(hk,swapNextWindow)=="Binding for next window swap is set on 'hk1,swap'"} {
        set settings(hk,swapNextWindow) "Ctrl-0xC0"
    }
    if {$settings(rrInterval) == 50} {
        set settings(rrInterval) 5
    }
    set toAdd "SndVol.exe"
    if {[lsearch -exact $settings(dontCaptureList) $toAdd]==-1} {
        lappend settings(dontCaptureList) $toAdd
    }
    if {[info exists settings(overlayBig)]} {
        if {!$settings(overlayBig)}	{
            set settings(overlayFontSize2) $settings(overlayFontSize1)
        }
        unset settings(overlayBig)
    }
    UnregisterHotkeys
    RegisterHotkey "Capture" hk,capture CaptureOrUpdate
    RegisterHotkey "Start/Stop mouse tracking" hk,mouseTrack MouseTracking
    RegisterHotkey "Focus next window" hk,focusNextWindow FocusNextWindow
    RegisterHotkey "Focus previous window" hk,focusPreviousWindow FocusPreviousWindow
    RegisterHotkey "Swap next window" hk,swapNextWindow SwapNextWindow
    RegisterHotkey "Swap previous window" hk,swapPreviousWindow SwapPreviousWindow
    RegisterHotkey "Focus follow mouse toggle" hk,focusFollowMouse FocusFollowMouseToggle
    RegisterHotkey "Always on top toggle" hk,stayOnTopToggle StayOnTopToggle
    RegisterHotkey "Overlay toggle" hk,overlayToggle OverlayToggle
    RegisterHotkey "RoundRobin toggle" hk,rrToggle RRToggle
    RegisterHotkey "Focus main window" hk,focusMain FocusMain
    RegisterHotkey "Reset all windows to saved positions" hk,resetAll ResetAll
    RegisterHotkey "Start/Stop mouse broadcasting" hk,mouseBroadcast MouseBroadcast
    for {set n 1} {$n < $maxNumW} {incr n} {
        if {[info exists slot2handle($n)]} {
            RegisterPerWindowHotkey $n "OMB $n"
        }
    }
    # Set mouse control to current values
    global mouseFollow mouseRaise mouseDelay
    set mouseDelay [GetMouseDelay]
    set mouseFollow [GetFocusFollowMouse]
    set mouseRaise [GetMouseRaise]
    LoadLayout
    Overlay
    RRCustomMenu
    Debug "Settings (re)Loaded."
}

set prevMF 0

proc RevertMouseFollow {} {
    global mouseDelay settings prevMF mouseFollow
    if {!$settings(mouseFocusOffAtExit)} {
        if {$prevMF} {
            Debug "Keeping mouse focus mode on on exit"
            set mouseFollow 1
            UpdateMouseFollow
        }
        return
    }
    if {![info exists mouseDelay]} {
        set mouseDelay 200
    }
    Debug "restoring mouse delay $mouseDelay"
    SetMouseDelay $mouseDelay
    SetFocusFollowMouse 0
}

catch {rename exit _real_exit}
wm protocol . WM_DELETE_WINDOW exit

proc exit {{status 0}} {
    Debug "Exit $status called"
    catch {destroy .clip}
    after cancel [after info]
    RevertMouseFollow
    update
    after cancel [after info]
    _real_exit $status
}

proc FocusFollowMouseToggle {} {
    Debug "Follow mouse toggle requested"
    .mf configure -state enabled
    .mf invoke
}

proc updateIndex {args} {
    global nextWindow maxNumW pos windowSize stayOnTop settings slot2handle
    Debug "nextWindow is $nextWindow - args $args"
    if {[info exists settings($nextWindow,size)]} {
        set windowSize $settings($nextWindow,size)
        set pos $settings($nextWindow,posXY)
        if {[info exists settings($nextWindow,stayOnTop)]} {
            set stayOnTop $settings($nextWindow,stayOnTop)
        }
    }
    .csop configure -text "Wow window $nextWindow always on top"
    if {$nextWindow<$maxNumW} {
        .l2 configure -text "Selected :"
    } else {
        .l2 configure -text "Next window :"
    }
    if {[info exists slot2handle($nextWindow)]} {
        .b2 configure -text " Update " -state enabled
    } else {
        .b2 configure -text " Capture "
        UpdateForegroundMode
    }
}

proc GetLogo {} {
    global imgOMB70 vers inExe img_dir
    if {[catch {set imgOMB70 [image create photo -file [file join $img_dir "OpenMultiBoxing70.png"]]} err]} {
        Debug "Didn't get logos: $err - falling back to https download"
    } else {
        Debug "In exe omb logo loaded"
        return ""
    }
    if {[catch {set token [http::geturl "https://openmultiboxing.org/OpenMultiBoxing70.png?v=$vers"]} err]} {
        OmbError "OpenMultiBoxing network error" "Url fetch error $err"
        return $err
    }
    set body [http::data $token]
    if {[catch {set imgOMB70 [image create photo -data $body]} err]} {
        OmbError "Open Multi Boxing logo error" "Logo error $err -:- $body"
        return "Invalid data $err $body"
    }
    return ""
}

set ourTitle "OpenMultiBoxing - Opensource MultiBoxing"

proc UISetup {} {
    global imgOMB70 vers stayOnTop pos windowSize settings \
         mouseFollow mouseRaise mouseDelay ourTitle bottomText \
         rrOn hasRR hasBR RRlabel rrlabel mouseBroadcast
    wm title . $ourTitle
    # Get logo
    set err [GetLogo]
    if {$err != ""} {
        set txt "Opensource\nMulti\nBoxing"
        grid [ttk::label .logo -text $txt] -rowspan 3
    } else {
        grid [ttk::label .logo] -rowspan 3 -pady 6 -padx 12
        .logo configure -image $imgOMB70
        wm iconphoto . -default $imgOMB70
    }
    set labelW 18
    grid [ttk::button .bH -text "Help" -width $labelW -command Help]  -row 0 -column 1 -padx 4
    tooltip .bH "Opens online help page"
    grid [ttk::button .bwl -text "Window Layout" -width $labelW -command WindowLayout] -row 1 -column 1
    tooltip .bwl "View or change the Window Layout"
    grid [ttk::button .b1  -text "Edit Settings" -width $labelW -command EditSettings] -row 2 -column 1
    tooltip .b1 "Opens the editor to edit settings\nand reload them after save.\nLet's you change hotkeys like:\nSwap next window: $settings(hk1,swap)\nFocus next window: $settings(hk,focusNextWindow)\netc... See Help for details."
    # label width - enough to fit "-9999 -9999"
    set width 10
    grid [frame .sep1 -relief groove -borderwidth 2 -width 2 -height 2] -sticky ew -padx 4 -pady 4 -columnspan 2
    grid [ttk::label .l2 -text "Next window :" -anchor e] [entry .e1 -textvariable nextWindow -width $width] -padx 4 -sticky ew
    bind .e1 <FocusIn> [list focusIn %W]
    grid [ttk::label .l3 -text "Resize to" -anchor e] [entry .e2 -textvariable windowSize -width $width] -padx 4 -sticky ew
    grid [ttk::label .l4 -text "Move to" -anchor e] [entry .e3 -textvariable pos -width $width] -padx 4 -sticky ew
    grid [ttk::checkbutton .csop -text "Wow window always on top" -variable stayOnTop] -columnspan 2
    tooltip .csop "Whether that window should be on top of others.\nThis can be changed at anytime for the current focused window\nusing the Hotkey: $settings(hk,stayOnTopToggle)"
    grid [ttk::button .b2 -text " Capture " -command CaptureOrUpdate] -pady 5 -columnspan 2
    tooltip .b2 "Capture or update window\nHotkey: $settings(hk,capture)"
    grid [listbox .lbw -height 6] -columnspan 2 -sticky ns
    bind .lbw <<ListboxSelect>> [list selectChanged %W]
    grid [ttk::checkbutton .cbCaptureFG -text "Capture using foreground window" -command UpdateForegroundMode -variable settings(captureForegroundWindow)] -columnspan 2
    tooltip .cbCaptureFG "Instead of capturing the game window by name\n($settings(game))\nif checked, capture the current foreground window\nFor this to work you must use the hotkey:\n$settings(hk,capture)\n\nUse the Game menu to turn this on"
    UpdateForegroundMode
    grid [ttk::checkbutton .cboverlay -text "Show overlay" -variable settings(showOverlay) -command "OverlayUpdate; SaveSettings"] [ttk::button .cbocfg -text "Overlay config" -command OverlayConfig]
    tooltip .cboverlay "Show/Hide the overlay info\nHotkey: $settings(hk,overlayToggle)"
    tooltip .cbocfg "Opens the overlay config which let's you configure\nborder, color, positions, etc... for the overlay"

    if {$hasRR||$hasBR} {
        set RRlabel "Round robin"
        set rrlabel "round robin"
        if {$hasBR} {
            set RRlabel "Broadcast"
            set rrlabel "broadcast"
        }
        grid [frame .sepRR -relief groove -borderwidth 2 -width 2 -height 2] -sticky ew -padx 4 -pady 4 -columnspan 2
        grid [ttk::label .lRR -text "⟳ $RRlabel settings:" -font "*-*-bold" -anchor sw] -padx 4 -columnspan 2 -sticky w
        grid [ttk::checkbutton .cbRR -text "$RRlabel ($settings(hk,rrToggle))" -variable rrOn -command RRUpdate] -padx 4 -columnspan 2 -sticky w
        tooltip .cbRR "Toggle $rrlabel mode\nAlso turns off mouse focus and restore as needed while on\nHotkey: $settings(hk,rrToggle)"
        grid [ttk::label .lrrK -text "$RRlabel to other windows all but these keys:"] -padx 4 -columnspan 2 -sticky w
        grid [entry .eRR -textvariable settings(rrKeyListExclude) -width $width] -columnspan 2 -padx 4 -sticky ew
        bind .eRR <Return> RRKeysListChange
        tooltip .eRR "Which keys are excluded from $rrlabel for all windows\nHit <Return> after change to take effect.\nSee help/FAQ for list."
        grid [ttk::label .lrrK2 -text "No $RRlabel when:"] -padx 4 -columnspan 2 -sticky w
        grid [entry .eRR2 -textvariable settings(rrModExcludeList) -width $width] -columnspan 2 -padx 4 -sticky ew
        tooltip .eRR2 "Which modifiers pause $rrlabel while held\nHit <Return> after change to take effect.\nSee help/FAQ for list."
        bind .eRR2 <Return> RRKeysListChange
        set rrC .rrC
        frame $rrC
        ttk::menubutton $rrC.rrMenuB -text "Skips" -menu $rrC.rrMenuB.menu
        menu $rrC.rrMenuB.menu -tearoff 0
        RRCustomMenu
        tooltip $rrC.rrMenuB "Select which window(s) are excluded from custom rotation"
        pack [ttk::label $rrC.lrrK3 -text "Custom rotation keys:" -anchor w] $rrC.rrMenuB -anchor w -side left -expand 1
        # grid $rrC -padx 4 -columnspan 2 -sticky ew
        # grid [entry .eRR3 -textvariable settings(rrKeyListCustom) -width $width] -columnspan 2 -padx 4 -sticky ew
        # tooltip .eRR3 "Which keys trigger custom rotation $rrlabel\nHit <Return> after change to take effect.\nSee help/FAQ for list."
        # bind .eRR3 <Return> RRKeysListChange
        # grid [ttk::label .lrrD -text "Direct focus keys (Main, WOB1...N):"] -padx 4 -columnspan 2 -sticky w
        # grid [entry .eRR4 -textvariable settings(rrKeyListDirect) -width $width] -columnspan 2 -padx 4 -sticky ew
        # tooltip .eRR4 "Which key will switch focus asap directly to Main, WOB1, WOB2,...\nFirst key will focus main, 2nd key will focus WOB1, 3rd key will focus WOB2,...\nTo skip a slot position use .*\nRemember this is in addition to the focus hotkeys.\nHit <Return> after change to take effect.\nSee help/FAQ for list."
        # bind .eRR4 <Return> RRKeysListChange
    }

    grid [frame .sep2 -relief groove -borderwidth 2 -width 2 -height 2] -sticky ew -padx 4 -pady 4 -columnspan 2
    grid [ttk::label .l6 -text "🖰 Mouse settings:" -font "*-*-bold" -anchor sw] -padx 4 -columnspan 2 -sticky w
    grid [ttk::checkbutton .mf -text "Focus follows mouse" -variable mouseFollow -command UpdateMouseFollow] -padx 4 -columnspan 2 -sticky w
    tooltip .mf "Toggle focus follow mouse mode\nHotkey: $settings(hk,focusFollowMouse)"
    grid [ttk::checkbutton .mbc -text "Broadcast mouse clicks" -variable mouseBroadcast] -padx 4 -columnspan 2 -sticky w
    tooltip .mbc "Toggle mouse click broadcasting\nHotkey: $settings(hk,mouseBroadcast)"
    grid [ttk::label .l_bottom -textvariable bottomText -justify center -anchor c] -padx 2 -columnspan 2
    bind .l_bottom <ButtonPress> [list CheckForUpdates 0]
    tooltip .l_bottom "Click to check for update from $vers"
    grid rowconfigure . 9 -weight 1
    grid columnconfigure . 1 -weight 1
}

proc UpdateForegroundMode {} {
    global settings
    if {$settings(captureForegroundWindow)} {
        .cbCaptureFG configure -state enabled
        if {[string match "*Capture*" [.b2 configure -text]]} {
            .b2 configure -state disabled
        }
    } else {
        .b2 configure -state enabled
        .cbCaptureFG configure -state disabled
    }
}

proc About {} {
    global vers hasRR hasBR inExe oldVersion
    if {$hasRR||$hasBR} {
        set extra "(with optional Broadcasting)"
    }
    if {$inExe && [info exists oldVersion] && $oldVersion !=$vers} {
        set extra "Binary version $oldVersion\n$extra"
    }
    OmbMessage -type ok -icon info -title "About OpenMultiBoxing" \
            -message \
"Open MultiBoxing (OMB) $vers\n$extra\n\nFree, OpenSource, Safe, Rules compliant, Multiboxing Software\n\nLicensed under GPLv3 - No Warranty\nThe GNU General Public License does not permit incorporating this work into proprietary programs.\n\nhttps://openmultiboxing.org https://wowopenbox.org/\n\uA9 2020-2021 MooreaTv <moorea@ymail.com>"

}

#### Start of clipboard management ####
# A bit more secure than notepad clipboard copy/paste option

set clipboardValue {}

proc ClearClipboard {} {
    global clipboardValue
    Debug "Clearing clipboard!"
    set clipboardValue {}
    clipboard clear
    clipboard append -- ""
}

proc SetClipboard {} {
    global clipboardValue
    clipboard clear
    clipboard append -- $clipboardValue
}

proc BroadcastClipboard {} {
    global clipboardValue
    BroadcastText "$clipboardValue" 1
    ClearClipboard
    twapi::set_foreground_window [twapi::tkpath_to_hwnd .clip]
}

proc ClipboardManager {} {
    global clipboardValue rrOn hasRR hasBR settings
    set tw .clip
    if {[winfo exists $tw]} {
        wm state $tw normal
        raise $tw
        return
    }
    toplevel $tw
    wm title $tw "OMB Secure Copy Paste"
    grid [ttk::label $tw.la -text "Secure text"] [entry $tw.e  -show "*" -textvariable clipboardValue -width 14] -padx 4 -sticky ew
    grid [ttk::button $tw.broadcast -width 14 -text "Broadcast" -command BroadcastClipboard] - -padx 4 -sticky ew
    grid [ttk::button $tw.copy -width 14 -text "Copy" -command SetClipboard] [ttk::button $tw.clear -width 14 -text "Clear" -command ClearClipboard] -padx 4 -sticky ew
    tooltip $tw.copy "Copy hidden text"
    tooltip $tw.clear "Clear clipboard and hidden text"
    bind $tw.clear <Destroy> ClearClipboard
    grid [ttk::label $tw.help -text "Type in the entry box, only *s will show,\nType <Return> for broadcast or\nClick Copy, then Ctrl-V as many times to paste,\nClose this popup or click Clear to erase."] -padx 4 -pady 6 -columnspan 2
    UpdateHandles
    focus $tw.e
    bind $tw.e <Return> BroadcastClipboard
    if {[info exists settings(clipGeometry)]} {
        catch {wm geometry .clip $settings(clipGeometry)}
    }
    bind .clip <Configure> {set settings(clipGeometry) [wm geometry .clip]}
}

#### end of clipboard management ####

proc CloseAllGames {{andExit 0}} {
    global slot2handle slot2position nextWindow maxNumW
    set extraMsg ""
    if {$andExit} {
        set extraMsg " and Exit OMB"
    }
    set r [OmbMessage -type yesno -title "Close All$extraMsg?" -icon warning -default no\
        -message "Are you sure you want to (force) close all the game windows$extraMsg?\n\nYou will lose all unsaved progress!"]
    if {$r!="yes"} {
        Debug "Close All not confirmed"
        return
    }
    Debug "Close all confirmed"
    foreach {n w} [array get slot2handle] {
        catch {twapi::close_window $w}
    }
    if {$andExit} {
        exit 0
    }
    # reset for recapture
    array unset slot2handle
    array unset slot2position
    .lbw delete 0 end
    set nextWindow 1
    set maxNumW 1
}

proc UpdateProfilesMenu {} {
    global settings
    set m2 .mbar.profile
    $m2 delete 0 end
    foreach p $settings(profiles) {
        $m2 add radiobutton -label $p -variable settings(profile) -command LoadProfile
    }
    $m2 add separator
    $m2 add command -label "Refresh Profiles" -command RefreshProfiles
}

proc MenuSetup {} {
    global vers settings hasRR hasBR mouseRaise
    if {[winfo exists .mbar]} {
        return
    }

    menu .mbar -type menubar
    . configure -menu .mbar

    set m1 .mbar.file
    menu $m1 -tearoff 0
    .mbar add cascade -label File -menu $m1
    $m1 add command -label "New Profile..." -command NewProfile
    $m1 add command -label "Edit raw settings..." -command EditSettings
    $m1 add command -label "Save settings" -command SaveSettings
    $m1 add command -label "Reload settings" -command LoadSettings
    $m1 add separator
    $m1 add command -label "Clipboard copy/paster..." -command ClipboardManager
    $m1 add separator
    $m1 add command -label "Reset all windows ($settings(hk,resetAll))" -command ResetAll
    $m1 add separator
    $m1 add command -label "Close all games..." -command CloseAllGames
    $m1 add command -label "Close all games and Exit..." -command "CloseAllGames 1"
    $m1 add separator
    $m1 add command -label "Save and Exit" -command "SaveSettings; exit 0"
    $m1 add command -label "Exit" -command "exit 0"

    set mG .mbar.game
    menu $mG -tearoff 0
    .mbar add cascade -label Game -menu $mG
    foreach g $settings(games) {
        $mG add radiobutton -label $g -value $g -variable settings(game)
    }
    $mG add separator
    $mG add checkbutton -label "Add (capture focused window mode)" -variable settings(captureForegroundWindow) -command UpdateForegroundMode

    set m2 .mbar.profile
    menu $m2 -tearoff 0
    .mbar add cascade -label Profile -menu $m2
    UpdateProfilesMenu

    set m3 .mbar.options
    menu $m3 -tearoff 0
    .mbar add cascade -label Option -menu $m3
    $m3 add checkbutton -label "Swap hotkey also focuses" -variable settings(swapAlsoFocus)
    $m3 add checkbutton -label "Focus hotkey also foregrounds" -variable settings(focusAlsoFG)
    $m3 add checkbutton -label "Auto Capture Game windows" -variable settings(autoCapture)
    $m3 add checkbutton -label "Capture makes windows borderless" -variable settings(borderless)
    $m3 add checkbutton -label "Auto Kill \"$settings(autoKillName)\"" -variable settings(autoKillOn)
    $m3 add checkbutton -label "Mouse auto foreground window" -variable mouseRaise -command UpdateMouseRaise
    $m3 add checkbutton -label "Turn off focus follow mouse on exit" -variable settings(mouseFocusOffAtExit)
    $m3 add checkbutton -label "Turn on focus follow mouse at startup" -variable settings(mouseFocusOnAtStart)
    $m3 add checkbutton -label "Auto open clipboard at startup" -variable settings(clipboardAtStart) -command {if {$settings(clipboardAtStart)} ClipboardManager}
    $m3 add separator
    $m3 add radiobutton -label "Auto reset focus to main: Off" -value 0 -variable settings(autoResetFocusToMain)
    $m3 add radiobutton -label "Auto reset focus to main: after 0.5 sec" -value 0.5 -variable settings(autoResetFocusToMain)
    $m3 add radiobutton -label "Auto reset focus to main: after 1 sec" -value 1 -variable settings(autoResetFocusToMain)
    $m3 add radiobutton -label "Auto reset focus to main: after 2 sec" -value 2 -variable settings(autoResetFocusToMain)
    $m3 add radiobutton -label "Auto reset focus to main: after 3 sec" -value 3 -variable settings(autoResetFocusToMain)
    $m3 add checkbutton -label "Auto reset after direct BR keys" -variable settings(autoResetDirect)
    $m3 add checkbutton -label "Always focus (if mixing click and RR)" -variable settings(rrAlwaysFocus)
    $m3 add separator
    $m3 add checkbutton -label "Pause when mouse is outside windows" -variable settings(mouseOutsideWindowsPauses)
    $m3 add checkbutton -label "Focus back when mouse in game window" -variable settings(mouseInsideGameWindowFocuses)

    menu .mbar.help -tearoff 0
    .mbar add cascade -label Help -menu .mbar.help
    .mbar.help add command -label "Online help..." -command Help
    .mbar.help add separator
    .mbar.help add command -label "Track mouse..." -command MouseTracking
    .mbar.help add separator
    .mbar.help add command -label "Get the newest binary release..." -command Releases
    .mbar.help add command -label "Check for update" -command [list CheckForUpdates 0]
    .mbar.help add command -label About -command About
 }

proc MouseBroadcast {} {
    global mouseBroadcast mouseFollow rrOn
    set mouseBroadcast [expr {1-$mouseBroadcast}]
    if {$mouseBroadcast} {
        if {$mouseFollow} {
            # Turn off mouse focus
            FocusFollowMouseToggle
        }
    } else {
        if {!$mouseFollow && !$rrOn} {
            # Turn (back) on mouse focus
            FocusFollowMouseToggle
        }
    }
    AddMouseToRRLabel
}

proc MouseTracking {} {
    global settings mouseArea mouseCoords mouseLocalCoords
    set tw .mouseTracking
    if {[winfo exists $tw]} {
        wm state $tw normal
        raise $tw
        StartStopMouseTrack
        return
    }
    toplevel $tw
    wm title $tw "OMB Mouse Tracking"
    grid [ttk::button $tw.bml -width 14 -text "Track mouse" -command StartStopMouseTrack] [entry $tw.emt -textvariable mouseCoords -width 14] -padx 4 -sticky w
    tooltip $tw.bml "Start/Stop mouse tracking\nHotkey: $settings(hk,mouseTrack)"
    grid [ttk::label $tw.la -text "Coords in area"] [entry $tw.ema -textvariable mouseArea -width 14] -padx 4 -sticky w
    grid [ttk::label $tw.lcl -text "Relative Coords"] [entry $tw.eml -textvariable mouseLocalCoords -width 14] -padx 4 -sticky w
    UpdateHandles
    StartStopMouseTrack
}


proc CheckAutoKill {} {
    global settings
    if {!$settings(autoKillOn)} {
        Debug "Auto kill is off"
        return
    }
    foreach p [twapi::get_process_ids -name $settings(autoKillName)] {
        set path [twapi::get_process_path $p]
        Debug "Killing $settings(autoKillName): $p ($path)"
        set newPath $path.bak
        if {[file exists $path]} {
            if {[catch {file rename -force $path $newPath} err]} {
                OmbError "AutoKill rename error" "$err"
            }
            Debug "Renamed $path to $newPath"
        }
        Debug "Result: [twapi::end_process $p -wait 200 -force -exitcode -1]"
        # We could also delete it but... lets not for now
        #if {[file exists $newPath]} {
        #    file delete $newPath
        #    Debug "Deleted $newPath"
        #}
    }
}

proc ValidWindowSettingsN {n} {
    global settings
    expr {[info exists settings($n,posXY)]&&[info exists settings($n,size)]}
}

proc IsIn {x y n} {
    global settings
    if {![ValidWindowSettingsN $n]} {
        return false
    }
    lassign $settings($n,posXY) wx1 wy1
    lassign $settings($n,size) ww wh
    set wx2 [expr {$wx1+$ww}]
    set wy2 [expr {$wy1+$wh}]
    expr {$x>=$wx1 && $x<=$wx2 && $y>=$wy1 && $y <=$wy2}
}

proc CoordsIn {mouseCoords} {
    global settings
    lassign $mouseCoords x y
    for {set n 1} {$n<=$settings(numWindows)} {incr n 1} {
        if {[IsIn $x $y $n]} {
            return $n
        }
    }
    return 0
}

proc MouseIsIn {} {
    if {[catch {twapi::get_mouse_location} coords]} {
        # expected in lock screen etc
        #Debug "Can't get mouse coords: $coords"
        return 0
    }
    CoordsIn $coords
}

proc ShouldPause {} {
    if {[catch {twapi::get_mouse_location} coords]} {
        # expected in lock screen etc
        #Debug "Can't get mouse coords: $coords"
        return 1
    }
    lassign $coords x y
    set w [twapi::get_window_at_location $x $y]
    set isOurs [IsOurs $w]
    #Debug "For $x $y : $w : $isOurs"
    list [expr {$isOurs<2}] $isOurs
}


proc MouseArea {mouseCoords} {
    global settings
    set n [CoordsIn $mouseCoords]
    if {$n} {
        return [list "Window $n" [AbsoluteMouseCoordsToRelative $n $mouseCoords]]
    } else {
        return [list "Not in 1-$settings(numWindows)" ""]
    }
}

proc ClickWindowRel {n xp yp button} {
    global settings slot2position slot2handle
    set WM_LBUTTONDOWN 0x0201
    set WM_LBUTTONUP 0x0202
    if {$button=="right"} {
        set WM_LBUTTONDOWN 0x0204
        set WM_LBUTTONUP 0x0205
    }
    set p $slot2position($n)
    # scale
    lassign $settings($p,posXY) lx ly
    lassign $settings($p,size) lw lh
    set x [expr {round($xp*$lw)}]
    set y [expr {round($yp*$lh)}]
    set lword [expr {($y<<16)+$x}]
    set x [expr {$lx+$x}]
    set y [expr {$ly+$y}]
    Debug "Will click at $x $y for $n"
    twapi::move_mouse $x $y
    set w $slot2handle($n)
    after $settings(mouseBroadcastDelay)
    twapi::PostMessage $w $WM_LBUTTONDOWN 1 $lword
    twapi::PostMessage $w $WM_LBUTTONUP 1 $lword
    after $settings(mouseBroadcastDelay)
    # twapi::click_mouse_button $button
}

proc AbsoluteMouseCoordsToRelative {n mouseCoords} {
    global settings slot2position
    set p $slot2position($n)
    lassign $mouseCoords x y
    # offset
    lassign $settings($p,posXY) lx ly
    set xp [expr {$x-$lx}]
    set yp [expr {$y-$ly}]
    return [list $xp $yp]
}

set clickInProgress ""
set mouseBeforeClick ""
set clickButton ""
set clickWhen 0
proc MouseBroadcastCheck {} {
    global mouseBeforeClick clickInProgress settings slot2position slot2handle isPaused clickButton clickWhen
    set VK_LBUTTON 0x01
    set VK_RBUTTON 0x02
    set W_KEY 0x57
    if {$isPaused || [twapi::GetAsyncKeyState $W_KEY]>1} {
        set clickInProgress ""
        set clickButton ""
        return
    }
    if {[catch {twapi::get_mouse_location} lMouse]} {
        # access denied while in lock screen etc
        return
    }
    set stateL [twapi::GetAsyncKeyState $VK_LBUTTON]
    set stateR [twapi::GetAsyncKeyState $VK_RBUTTON]
    if {$stateL && $stateR} {
        # both buttons down
        # Debug "Both buttons down, no click broadcast"
        set clickButton "both"
        set clickInProgress ""
        return
    }
    set state [expr {$stateL|$stateR}]
    if {$clickButton=="both"} {
        Debug "Released button(s) after both were down, no click broadcast $stateL $stateR"
        set clickInProgress ""
        if {$state==0} {
            set clickButton ""
        }
        return
    }
    if {$stateR} {
        set clickButton "right"
    } elseif {$stateL} {
        set clickButton "left"
    }
    if {$clickInProgress!="" && $state==0} {
        set elapsed [expr {[clock milliseconds]-$clickWhen}]
        set saveMousePos $lMouse
        Debug "MOUSE_CLICK_RELEASE $clickButton $clickInProgress vs $saveMousePos after $elapsed ms"
        if {$elapsed > 500} {
            set clickInProgress ""
            set clickButton ""
            return
        }
        # return to the click pos and not current pos which seems to glitch at times
        set saveMousePos $clickInProgress
        lassign $clickInProgress x y
        set clickInProgress ""
        # Find window
        set w [twapi::get_window_at_location $x $y]
        set wType [IsOurs $w]
        #Debug "Window clicked is $w: $wType"
        if {$wType<3} {
            return
        }
        set n [expr {$wType-2}]
        set p $slot2position($n)
        # scale
        lassign $settings($p,posXY) lx ly
        lassign $settings($p,size) lw lh
        set xp [expr {1.0*($x-$lx)/$lw}]
        set yp [expr {1.0*($y-$ly)/$lh}]
        Debug "Clicked on $n in position $p is rel x $xp rel y $yp - $clickButton"
        # iterate move to other windows applying scale
        for {set i 1} {$i<=$settings(numWindows)} {incr i} {
            if {$i==$n} {
                continue
            }
            if {[info exists slot2handle($i)]} {
                ClickWindowRel $i $xp $yp $clickButton
            }
        }
        # bring back
        after $settings(mouseBroadcastDelay)
        twapi::move_mouse {*}$saveMousePos
        Foreground $w
    } elseif {$state > 1 && $clickInProgress==""} {
        set clickInProgress $mouseBeforeClick
        set clickWhen [clock milliseconds]
        Debug "VK $clickButton [format %x $state] $clickInProgress"
    }
    set mouseBeforeClick $lMouse
}

set isPaused 0
set pauseSchedule {}

proc PeriodicChecks {} {
    global settings isPaused prevRR prevMF prevOL prevRRMouse hasRR hasBR rrOn rrMouse mouseFollow\
         maxNumW pauseSchedule lastFocusWindow slot2handle mouseBroadcast
    after cancel $pauseSchedule
    set pauseSchedule {}
    if {$settings(autoCapture) && ($maxNumW<=$settings(numWindows))} {
        set w [FindGameWindow]
        if {$w != ""} {
            AutoCapture $w
        }
    }
    if {$mouseBroadcast} {
        MouseBroadcastCheck
    }
    if {$settings(mouseWatchInterval)} {
        set pauseSchedule [after $settings(mouseWatchInterval) PeriodicChecks]
    }
    if {!$settings(mouseOutsideWindowsPauses)} {
        return
    }
    lassign [ShouldPause] shouldPause isOurs
    if {$shouldPause != $isPaused} {
        Debug "Change of window from $isPaused to $shouldPause"
        if {$shouldPause} {
            set prevRR 0
            set prevMF 0
            set prevOL 0
            set prevRRMouse 0
            if {$mouseFollow} {
                set mouseFollow 0
                UpdateMouseFollow
                set prevMF 1
            }
            if {[info exists rrMouse] && $rrMouse} {
                set prevRRMouse 1
                set rrMouse 0
            }
            if {$hasRR && $rrOn} {
                RRToggle
                set prevRR 1
            }
            if {$settings(showOverlay)} {
                OverlayToggle
                set prevOL 1
            }
            # can't seem to raise our own window...
        } else {
            Debug "Restoring $prevRR $prevMF $prevOL $prevRRMouse"
            if {$prevRR && !$rrOn} {
                RRToggle
            }
            if {$prevRRMouse} {
                set rrMouse 1
            }
            if {$prevMF} {
                set mouseFollow 1
                UpdateMouseFollow
                set prevMF 0
            }
            if {$prevOL} {
                set settings(showOverlay) 1
                OverlayUpdate
            }
            if {$isOurs>=3 && $settings(mouseInsideGameWindowFocuses)} {
                Debug "Focusing back $lastFocusWindow"
                catch {Focus $slot2handle($lastFocusWindow)}
            }
        }
    }
    set isPaused $shouldPause
}

proc mouseTrack {} {
    global mouseTrackOn mouseCoords mouseArea mouseLocalCoords
    catch {twapi::get_mouse_location} mouseCoords
    lassign [MouseArea $mouseCoords] mouseArea mouseLocalCoords
    set mouseTrackOn [after 100 mouseTrack]
}

# hey when you take this code, please be nice and add:
# I got this from MooreaTv at https://openmultiboxing.org/
proc BorderLess {w resize} {
    global savedWindowStyle
    set stL [twapi::get_window_style $w]
    if {![info exist savedWindowStyle($w)]} {
        # Used to restore style in Forget
        set savedWindowStyle($w) $stL
    }
    lassign $stL style exstyle
    # style &
    # ~(WS_CAPTION | WS_THICKFRAME)
    #   0x00C00000L  0x00040000L
    # exstyle &
    # ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE)
    #    0x00000001L          0x00000100L         0x00000200L       0x00020000L
    lassign [twapi::get_window_client_area_size $w] w1 h1
    Debug "Client area : $w1 x $h1"
    lassign [twapi::get_window_coordinates $w] x1 y1 x2 y2
    set w2 [expr {$x2-$x1}]
    set h2 [expr {$y2-$y1}]
    Debug "Size $x1 $y1 $x2 $y2 -> $w2 x $h2"
    twapi::set_window_style $w [expr {$style & ~ 0xc40000}] [expr {$exstyle & ~ 0x20301}]
    if {$resize} {
        twapi::resize_window $w $w1 $h1
        twapi::resize_window $w $w2 $h2
    }
}

proc StartStopMouseTrack {} {
    global mouseTrackOn
    if {$mouseTrackOn != ""} {
        Debug "Stopping mouse tracking"
        . configure -cursor arrow
        after cancel $mouseTrackOn
        set mouseTrackOn ""
        .mouseTracking.bml configure -text "Track mouse"
    } else {
        Debug "Starting mouse tracking"
        . configure -cursor crosshair
        mouseTrack
        .mouseTracking.bml configure -text "Stop tracking"
    }
}

proc focusIn {w args} {
    global nextWindow maxNumW
    Debug "got focusIn $w $args"
    if {[.lbw curselection]==""} {
        # only reset if there was a selection otherwise changing windows
        # top window clears it
        return
    }
    .lbw selection clear 0 end
    selectChanged .lbw "from focus $w"
    set nextWindow $maxNumW
}

proc CheckWindow {cmd n} {
    global slot2handle slot2position settings
    if {![catch $cmd err]} {
        Debug "Ok $cmd for $n"
        return
    }
    Debug "Error processing $cmd for $n: $err"
    if {[info exists slot2handle($n)]} {
        set w slot2handle($n)
        unset slot2handle($n)
        UpdateHandles
    }
    .b2 configure -text " Capture "
    UpdateForegroundMode
    set n0 [expr {$n-1}]
    .lbw delete $n0
    .lbw insert $n0 " OMB $n (lost)"
}

proc selectChanged {w args} {
    global nextWindow maxNumW slot2handle
    set sel [$w curselection]
    Debug "got selectChanged $w $args: $sel - nextWindow $nextWindow max $maxNumW"
    if {$sel == "" } {
        bind $w <3> {}
        return
    }
    set nextWindow [expr {$sel+1}]
    bind $w <3> [list ContextMenu $nextWindow %X %Y]
    if {![info exists slot2handle($nextWindow)]} {
        Debug "Not (yet/anymore) a window $nextWindow"
        #.b2 configure -text " Capture "
        return
    }
    # Not foreground, just focus
    CheckWindow [list FocusN $nextWindow false] $nextWindow
    set n0 [expr {$nextWindow-1}]
    .lbw see $n0
    .lbw selection set $n0
}

proc ContextMenu {n x y} {
    Debug "In context for $n"
    catch {destroy .ctx}
    menu .ctx -tearoff 0
    .ctx add command -label "Forget OMB $n..." -command [list Forget $n]
    tk_popup .ctx $x $y
}

proc Forget {n} {
    global slot2handle slot2position settings savedWindowStyle
    if {![info exists slot2handle($n)]} {
        Debug "Nothing to forget for $n"
        return
    }
    set wh $slot2handle($n)
    catch {Rename $wh $settings(game)}
    unset slot2handle($n)
    UpdateHandles
    .b2 configure -text " Capture "
    UpdateForegroundMode
    set n0 [expr {$n-1}]
    .lbw delete $n0
    .lbw insert $n0 " OMB $n (removed)"
    if {[info exists savedWindowStyle($wh)]} {
        # this would require a resize as well for the game to pickup the change
        # but this is "forget" so... that's enough we get back a title and resize
        # if the user which to move the window out of omb
        lassign $savedWindowStyle($wh) st exst
        catch {twapi::set_window_style $wh $st $exst}
    }
}

# --- utilities ---

proc GetHeight {} {
    global windowSize
    regsub -all {[^-0-9]+} $windowSize " " windowSize
    lindex $windowSize 1
}
proc GetWidth {} {
    global windowSize
    regsub -all {[^-0-9]+} $windowSize " " windowSize
    lindex $windowSize 0
}

proc GetX {} {
    global pos
    regsub -all {[^-0-9]+} $pos " " pos
    lindex $pos 0
}

proc GetY {} {
    global pos
    regsub -all {[^-0-9]+} $pos " " pos
    lindex $pos 1
}

# --- Windows API: https://twapi.magicsplat.com/v4.4/ui.html

proc FindGameWindow {} {
    global settings
    # consider doing exact match with ^ $ or...
    set wList [twapi::find_windows -match string -text "$settings(game)" -visible true]
    set minTime 0
    set minW ""
    foreach w $wList {
        if {[catch {twapi::get_window_process $w} pid]} {
            Debug "Api error for get_window_process $w: $pid"
            continue
        }
        set info [twapi::get_process_info $pid -name -createtime]
        set exe [lindex $info 1]
        set time [lindex $info 3]
        Debug "Game $w pid $w exe $exe time $time"
        if {[lsearch -exact $settings(dontCaptureList) $exe]!=-1} {
            Debug "Not capturing $exe $w found in $settings(dontCaptureList)"
            continue
        }
        if {$minTime==0 || $time<$minTime} {
            set minTime $time
            set minW $w
        }
    }
    if {$minW != ""} {
        Debug "Found first started w $minW : $minTime"
    }
    return $minW
}

#proc Resize {w width height} {
#    Debug "Resizing $w to $width x $height"
#    twapi::resize_window $w $width $height
#}

proc Rename {w name} {
    twapi::set_window_text $w $name
}

#proc Move {w x y} {
#    Debug "Moving $w to $x , $y"
#    twapi::move_window $w $x $y
#}

proc MoveAndResize {w x y width height} {
    # Exact best flags to be determined but this seems a first optimization
    twapi::SetWindowPos $w 0 $x $y $width $height 0x6604
}

proc FindExisting {} {
    global settings SETTINGS_BASE nextWindow
    # do +1 just in case there is one more than last save
    set firstMissing 0
    for {set n 1} {$n<=$settings(numWindows)+1} {incr n 1} {
        set wname "OMB $n"
        set wl [twapi::find_windows -match regexp -text "^$wname\$" -visible true]
        if {$wl eq {}} {
            if {!$firstMissing} {
                set firstMissing $n
            }
            Debug "OMB $n not found, skipping"
            continue
        }
        lassign $wl w
        Debug "found OMB $n! : $wl : $w"
        if {$settings(numWindows)==0} {
            OmbError "OpenMultiBoxing missing settings error" \
                "You have existing OMB 1... window(s) but empty settings, please copy your settings file ($SETTINGS_BASE) from your old location (or exit Wow 1)"
            exit 1
        }
        updateListBox $n $w $wname
        UpdateN $n
    }
    if {$firstMissing} {
        set nextWindow $firstMissing
    }
    CheckAutoKill
}

array set lastSOT {}

proc SetStayOnTop {wh top} {
    global settings lastSOT
    if {[info exists lastSOT($wh)] && $lastSOT($wh)==$top} {
        Debug "Same StayOnTop $top for $wh, skipping."
        return 0
    }
    set lastSOT($wh) $top
    if {$top} {
        Debug "Setting stay on top for $wh"
        twapi::set_window_zorder $wh toplayer
        return 1
    } else {
        Debug "Clearing stay on top for $wh"
        twapi::set_window_zorder $wh bottomlayer
        return 0
    }
}

array set lastUpdate {}

proc Update {wh x y w h top} {
    global lastUpdate
    set ret 0
    # Clear stay on top first
    if {$top==0} {
        SetStayOnTop $wh 0
    }
    if {[info exists lastUpdate($wh)]} {
        set lu $lastUpdate($wh)
    } else {
        set lu {}
    }
    set new [list $x $y $w $h $top]
    if {$lu != $new} {
        MoveAndResize $wh $x $y $w $h
    }
    set lastUpdate($wh) $new
    # Return if we raised that window (for overlay)
    # Set stay on top last
    if {$top} {
        set ret [SetStayOnTop $wh 1]
    }
    return $ret
}

proc Focus {wh} {
    twapi::set_focus $wh
}

proc Foreground {wh} {
    twapi::set_foreground_window $wh
}

proc Help {} {
    global vers
    twapi::shell_execute -path https://OpenMultiBoxing.org/help?v=$vers
}

proc Releases {} {
    global vers
    twapi::shell_execute -path https://github.com/OpenMultiBoxing/OpenMultiBoxing/releases?v=$vers
}

proc EditSettings {} {
    global settings
    Debug "Edit settings requested, first saving and then opening editor"
    SaveSettings
    twapi::shell_execute -path notepad.exe -params [ProfileFileName $settings(profile)]
    .b1 configure -text "Reload Settings" -command LoadSettings
}

# Hotkeys
proc HandleHotKey {msg cb} {
    global hotkeyOk
    Debug "Hotkey ok=$hotkeyOk for $msg - $cb"
    if $hotkeyOk $cb
}

if {![info exists allHotKeys]} {
    set allHotKeys {}
}

proc RegisterHotkey {msg var callback} {
    global settings allHotKeys
    set hk $settings($var)
    Debug "RegisterHotkey $hk $msg $var $callback"
    if {$hk == ""} {
        # #71 if hotkey is empty, skip it
        return
    }
    if {[catch {twapi::register_hotkey $hk [list HandleHotKey $msg $callback]} err]} {
        puts "hotkey error $hk for $msg: $err"
        OmbError "OpenMultiBoxing HotKey error" \
         "Conflict for hotkey for $msg, change $var in settings to use something different than $hk"
    }
    lappend allHotKeys $err
}

proc FindOtherCopy {} {
    global ourTitle
    set wobTitle "WoW Open Box - Opensource MultiBoxing"
    set wList [twapi::find_windows -match regexp -text "^($ourTitle|$wobTitle)\$"]
    foreach w $wList {
        UpdateOurWindowHandles
        if {![IsOurs $w]} {
            catch {twapi::flash_window $w -count 3} err
            puts "Found another window of ours. Flashed it. $err"
            OmbError "OpenMultiBoxing duplicate error" \
                 "Another copy of OpenMultiBoxing is running, please exit it before starting a new one (or hotkeys will conflict)."
            catch {Foreground $w; Focus $w; twapi::flash_window $w -count 3} err
            puts "Bring other window in focus. $err"
            exit 1
        }
    }
    # Check for processes too (Issue #131)
    set pList [twapi::get_process_ids -glob -name "OpenMultiBoxing-v*.exe"]
    set ll [llength $pList]
    if {$ll>1} {
        set r [OmbMessage -type yesno -title "Kill older instances" -icon warning -default yes\
        -message "Found $ll copies of OMB process, want to kill them to avoid hotkey binding errors?"]
        if {$r=="yes"} {
            Debug "Kill extra confirmed"
            set ours [twapi::get_current_process_id]
            foreach p $pList {
                if {$p==$ours} {
                    Debug "Not killing ourselves ($p)"
                } else {
                    Debug "Killing $p: [twapi::end_process $p -wait 200 -force -exitcode -1]"
                }
            }
        }
    }
}
# ---

# wow windows handles for each slot (slot#)
array set slot2handle {}
# wow windows handle slots - on screen/current position
array set slot2position {}

proc FocusN {n fg {update 1}} {
    global slot2handle slot2position focusWindow lastFocusWindow settings hasRR hasBR
    if {[info exists slot2handle($n)]} {
        FocusNinternal $n $fg
    } else {
        Debug "FocusN $n called but no such window"
    }
    set lastFocusWindow $n
    if {$update} {
        set focusWindow $n
    }
}

proc FocusNinternal {n fg} {
    global slot2handle slot2position lastFocusWindow settings hasRR hasBR
    set wh $slot2handle($n)
    set p $slot2position($n)
    Debug "FocusN $n called, at position $p - fg is $fg"
    if {$hasRR} {
        Foreground $wh
    } else {
        Focus $wh
        if {$fg && $settings(focusAlsoFG)} {
            Debug "Also making $n foreground"
            Foreground $wh
        }
    }
    if {$settings(showOverlay)} {
        windowIndicatorN $lastFocusWindow configure -foreground white
        if {[winfo exists .o$p]} {
            .o$p.l configure -foreground $settings(overlayFocusColor)
        }
    }
}

# Focus whichever window is in location/spot 1
proc FocusMain {} {
    global slot2position
    # either 1 or the window currently swapped to 1
    if {[info exists slot2position(1)]} {
        FocusN $slot2position(1) true
    }
}

proc StayOnTopToggle {} {
    global lastFocusWindow settings slot2handle
    set settings($lastFocusWindow,stayOnTop) [expr {!$settings($lastFocusWindow,stayOnTop)}]
    catch {SetStayOnTop $slot2handle($lastFocusWindow) $settings($lastFocusWindow,stayOnTop)}
    Debug "StayOnTopToggle $lastFocusWindow now $settings($lastFocusWindow,stayOnTop)"
}

proc SwapNextWindow {} {
    global swappedWindow maxNumW
    # maxNumW is one more than number of windows
    # we want 2,3,4,...N,1,2,3..N,1... cycle
    if {$maxNumW<3} {
        Debug "Not enough windows to swap"
        return
    }
    set n [expr {$swappedWindow % ($maxNumW-1) + 1}]
    Debug "SwapNextWindow: swappedWindow $swappedWindow maxNumW $maxNumW -> $n"
    SetAsMain $n
}

proc SwapPreviousWindow {} {
    global swappedWindow maxNumW
    # maxNumW is one more than number of windows
    set n [expr {($swappedWindow+$maxNumW-3) % ($maxNumW-1) + 1}]
    Debug "SwapPreviousWindow: swappedWindow $swappedWindow maxNumW $maxNumW -> $n"
    SetAsMain $n
}

proc NextCustomWindow {} {
    global customWindow maxNumW rrCustom slot2position
    if {![info exists rrCustom(0)]} {
        # updgrade without menu setup
        OmbError "Restart needed" "You just upgraded but need to restart OMB! No state will be lost if you do! Thanks!"
    }
    set mainSlot $slot2position(1)
    set mainCheck $mainSlot
    if {!$rrCustom(0)} {
        set mainCheck 0
    }
    set n $customWindow
    # Avoid infinite loop trying to find impossible next custom window
    set excl 0
    for {set i 1} {$i<$maxNumW} {incr i} {
        set n [expr {$n % ($maxNumW-1) + 1}]
        incr excl $rrCustom($n)
        # check for main
        if {$n==$mainCheck} {
            continue
        }
        # Ok to use if Main isn't skipped and this is Main currently
        if {!$rrCustom($n) || (!$mainCheck && $mainSlot==$n)} {
            Debug "Next custom window is $n because $rrCustom($n) $mainCheck $mainSlot"
            set customWindow $n
            return $n
        }
    }
    # only complain if it would never work; not if say main is excluded; only Omb2 is allowed yet
    # wob2 is the one in main
    Debug "Nothing found $excl $maxNumW staying on $customWindow"
    if {$excl==$maxNumW-1} {
        OmbError "Custom Broadcasting Error" "Invalid Custom Rotation, All windows are disabled!"
    }
    return $customWindow
}

proc FocusNextWindow {{custom 0}} {
    global focusWindow customWindow maxNumW settings resetTaskId lastFocusWindow
    if {[info exists resetTaskId]} {
        after cancel $resetTaskId
        unset resetTaskId
    }
    if {$maxNumW<3} {
        return
    }
    if {$custom} {
        set n [NextCustomWindow]
    } else {
        # maxNumW is one more than number of windows
        set n [expr {$focusWindow % ($maxNumW-1) + 1}]
    }
    Debug "FocusNextWindow: custom $custom, focusWindow $focusWindow maxNumW $maxNumW -> $n"
    if {$settings(rrAlwaysFocus) || $n!=$lastFocusWindow} {
        # Don't update here as it could be custom
        CheckWindow [list FocusN $n true 0] $n
    }
    if {!$custom} {
        # always update even if we were already on the spot (so we move out of it next)
        set focusWindow $n
    }
    if {$settings(autoResetFocusToMain)>0} {
        set resetTaskId [after [expr {round(1000.*$settings(autoResetFocusToMain))}] FocusMain]
    }
}

proc FocusPreviousWindow {} {
    global focusWindow maxNumW
    set n [expr {($focusWindow+$maxNumW-3) % ($maxNumW-1) + 1}]
    Debug "FocusPreviousWindow: focusWindow $focusWindow maxNumW $maxNumW -> $n"
    CheckWindow [list FocusN $n true] $n
}

proc UpdateN {n} {
    global slot2handle slot2position settings
    if {![info exists slot2handle($n)]} {
        Debug "Can't update non existent window $n"
        return
    }
    if {![info exists settings($n,posXY)]} {
        Debug "Can't update window $n without settings"
        return
    }
    # local/temp only
    set wh $slot2handle($n)
    set p $slot2position($n)
    lassign $settings($p,posXY) lx ly
    lassign $settings($p,size) lw lh
    set lstayOnTop 0
    if {[info exists settings($p,stayOnTop)]} {
        set lstayOnTop $settings($p,stayOnTop)
    }
    Debug "Update for $n in pos $p : $lx,$ly ${lw}x$lh - $lstayOnTop"
    set raised [Update $wh $lx $ly $lw $lh $lstayOnTop]
    if {$settings(showOverlay) && [winfo exists .o$p]} {
        .o$p.l configure -text $n
        if {$p!=1} {
            bind .o$p.l <ButtonPress> [list SetAsMain $n]
        }
        if {$raised} {
            Debug "OVERLAY raising $p"
            # hacky/shouldn't be necessary/doesn't seem to work 100%
            after 100 "
                Debug \"changing zorder for $p\"
                raise .o$p
            "
            #twapi::set_window_zorder [list [twapi::tkpath_to_hwnd .o$p]] toplayer
        }
    }
}

proc windowIndicatorN {n args} {
    global slot2position
    if {![info exists slot2position($n)]} {
        return
    }
    set p $slot2position($n)
    if {![winfo exists .o$p.l]} {
        return
    }
    .o$p.l {*}$args
}

proc SetAsMain {n} {
    global settings lastFocusWindow swappedWindow
    windowIndicatorN $lastFocusWindow configure -foreground white
    SetAsMainInt $n
    set swappedWindow $n
    if {$settings(swapAlsoFocus)} {
        CheckWindow [list FocusN $n true] $n
    } else {
        windowIndicatorN $lastFocusWindow configure -foreground $settings(overlayFocusColor)
    }
}

proc SetAsMainInt {n} {
    global slot2handle slot2position settings
    if {![info exists slot2handle($n)]} {
        Debug "SetAsMain $n doesn't exist"
        return
    }
    set p $slot2position($n)
    if {$p==1} {
        Debug "SetAsMain $n already in slot 1"
        return
    }
    if {![info exists slot2position(1)]} {
        Debug "SetAsMain $n no WOB1 to swap with"
        return
    }
    set p1 $slot2position(1)
    Debug "SetAsMain $n called currently was in $p, s1 is in $p1"
    if {$slot2position($p1)!=1} {
        OmbError "Bug?" "Unexpected s1 is in $p1 but $p1 is in $slot2position($p1)"
        return
    }
    set slot2position($n) 1
    set slot2position(1) $n
    if {$p1!=1} {
        # Move back whoever was in 1
        set slot2position($p1) $p1
        CheckWindow [list UpdateN $p1] $p1
    }
    # Move 1 to n'th slot
    CheckWindow [list UpdateN 1] 1
    # Move n to 1
    if {$n != 1} {
        CheckWindow [list UpdateN $n] $n
    }
}

proc IsDesktop {w} {
    lassign $w id
    expr {$id==0x10010}
}

proc TopLevelWindow {w} {
    set n 0
    #Debug "Calling TopLevelWindow $w"
    while 1 {
        set parent [twapi::get_parent_window $w]
        if {$parent == "" || $parent == $w || [IsDesktop $parent]} {
            return $w
        }
        #Debug "Finding Toplevel $w recursing to $parent"
        set w $parent
        incr n
        if {$n>20} {
            error "Unexpected to take over 20 parent to find toplevel for $w, $parent"
        }
    }
    #Debug "Done -> $w (parent $parent)"
    return $w
}


proc Defer {time cmd} {
    after idle [list after $time $cmd]
}

# All our windows (to not capture and to handle pause/overlay hide)
array set ourWindowHandles {}
# value is 3+ for game window (2+windowId)
# 2 for UI like overlay and wizard and overlay config
# 1 for main UI (no RR/overlay)
# non existant/0 is other windows
# so anything <= 1 should not show overlay, do RR,...

proc UpdateHandles {} {
    after idle UpdateOurWindowHandles
}

# first defer is 100ms (2x mouse interval)
set handleRetryCount 2
set handleErrorShown 0

proc UpdateOurWindowHandles {} {
    global ourWindowHandles slot2handle settings handleRetryCount handleErrorShown vers
    array unset ourWindowHandles
    array set topw {}
    foreach w [winfo children .] {
        set topw([winfo toplevel $w]) 1
    }
    array set wid {}
    set notReady 0
    foreach w [array names topw] {
        set wh [twapi::tkpath_to_hwnd $w]
        set tl [TopLevelWindow $wh]
        if {$w==".ctx"} {
            Debug "Ignoring $w $wh $tl"
            continue
        }
        if {$tl==$wh} {
            # not ready
            set notReady 1
            set notReadyCause "$w $wh $tl"
        }
        Debug "$w -> $wh -> $tl"
        set val 2
        if {$w=="." || $w==".clip" || $w==".newProfile"} {
            Debug "Found $w to pause"
            set val 1
        }
        set ourWindowHandles($tl) $val
    }
    foreach {n wh} [array get slot2handle] {
        set ourWindowHandles($wh) [expr {$n+2}]
    }
    Debug "Done refreshing window ids - retry #$handleRetryCount $notReady"
    if {$notReady} {
        if {$handleRetryCount<=92} {
            Defer [expr {$handleRetryCount*$settings(mouseWatchInterval)}] UpdateOurWindowHandles
            incr handleRetryCount 10
            return
        }
        if {$handleErrorShown} {
            Debug "Already shown error $handleRetryCount: $notReadyCause"
        } else {
            set handleErrorShown 1
            OmbError "UpdateHandles Error" "Unable to complete updates after $handleRetryCount.\n\nPlease screenshot this and report this bug.\n\nCode: $notReadyCause\n\n$vers"
        }
    }
    set handleRetryCount 2
}

# 0 for not ours, 1 and 2 for our UI, 3+ for game windows
proc IsOurs {w} {
    global ourWindowHandles
    if {[IsDesktop $w]} {
        return 0
    }
    set tl [TopLevelWindow $w]
    if {[info exists ourWindowHandles($tl)]} {
        return $ourWindowHandles($tl)
    }
    return 0
}

# TODO: count errors and stop instead of spinning after a while

set autoCaptureErrorCount 0

proc AutoCapture {w} {
    global nextWindow settings stayOnTop lastUpdate slot2handle autoCaptureErrorCount
    for {} {[info exists slot2handle($nextWindow)]} {incr nextWindow} {
        Debug "Skipping existing nextwindow $nextWindow"
    }
    set wname "OMB $nextWindow"
    if {[catch {
        if {$settings(borderless)} {
            BorderLess $w 0
        }
        Rename $w $wname
    } err]} {
        set eMsg "Auto capture error: $err for $w - will try later (#$autoCaptureErrorCount)"
        Debug $eMsg
        puts stderr $eMsg
        if {$err=="Access is denied."} {
            incr autoCaptureErrorCount
            # allow some retries before giving up
            if {$autoCaptureErrorCount > 20} {
                OmbError "Auto Capture Error" "Access Denied - You should not run $settings(game) as Administrator; it prevents window control from OMB. Please restart your game windows as non admin. See FAQ."
                set autoCaptureErrorCount 0
            }
        }
        return
    } else {
        set autoCaptureErrorCount 0
    }
    PostCapture $w $wname
}

proc Capture {} {
    global nextWindow settings stayOnTop lastUpdate
    if {$settings(captureForegroundWindow)} {
        set w [twapi::get_foreground_window]
        if {[IsDesktop $w]} {
            Debug "Not capturing desktop window"
            return
        }
        if {[IsOurs $w]} {
            OmbError "OpenMultiBoxing Error" "Can't capture foreground window: it's (already) ours!"
            return
        }
        set wtitle [twapi::get_window_text $w]
        Debug "Capturing \"$wtitle\""
        if {[lsearch -exact $settings(games) $wtitle]==-1} {
            Debug "New game $wtitle"
            lappend settings(games) $wtitle
            .mbar.game insert [expr {[.mbar.game index end]-1}] checkbutton -label $wtitle -variable settings(game)
            set settings(game) $wtitle
        }
    } else {
        set w [FindGameWindow]
        if {$w eq ""} {
            OmbError "OpenMultiBoxing Error" "No $settings(game) window found"
            return
        }
    }
    set wname "OMB $nextWindow"
    # We are resizing just after so no need to do it twice,
    # but otherwise it is needed for the inner size of wow to be correct
    if {$settings(borderless)} {
        BorderLess $w 0
    }
    Rename $w $wname
    PostCapture $w $wname
}

proc PostCapture {w wname} {
    global nextWindow stayOnTop lastUpdate
    # Need to really update if we captured/forgot before
    catch {unset lastUpdate($w)}
    Update $w [GetX] [GetY] [GetWidth] [GetHeight] $stayOnTop
    updateListBox $nextWindow $w $wname
}

proc RegisterPerWindowHotkey {n wname} {
    global settings
    if {[info exists settings(hk$n,focus)]} {
        Debug "Setting focus hotkey for $n / $wname: $settings(hk$n,focus)"
        RegisterHotkey "Focus window $n" hk$n,focus [list FocusN $n true]
    } else {
        Debug "No focus hotkey found or set for $n / $wname"
    }
    if {[info exists settings(hk$n,swap)]} {
        Debug "Setting swap hotkey for $n / $wname: $settings(hk$n,swap)"
        RegisterHotkey "Swap window $n" hk$n,swap [list SetAsMain $n]
    } else {
        Debug "No focus hotkey found or set for $n / $wname"
    }
}

proc updateListBox {n w wname} {
    global ourWindowHandles slot2handle slot2position nextWindow maxNumW settings
    set slot2handle($n) $w
    set slot2position($n) $n
    set ourWindowHandles($w) [expr 2+$n]
    RegisterPerWindowHotkey $n $wname
    # 0 based index
    set n0 [expr {$n-1}]
    Debug "n is $n nextWindow is $nextWindow maxNumW is $maxNumW"
    if {$n<$maxNumW} {
        .lbw delete $n0
        .lbw insert $n0 " $wname "
        .lbw see $n0
        .lbw selection set $n0
        # todo: handle update/capture in one place
        .b2 configure -text " Update " -state enabled
        return
    }
    # jump by more than 1
    for {set i $maxNumW} {$i < $n} {incr i} {
        .lbw insert end " OMB $i (not present)"
    }
    .lbw insert $n0 " $wname "
    if {$n>$settings(numWindows)} {
        set settings(numWindows) $n
        Overlay
    }
    RRCustomMenu
    set nextWindow [expr {$n+1}]
    set maxNumW $nextWindow
}

proc CaptureOrUpdate {} {
    global nextWindow slot2handle settings stayOnTop
    Debug "Capturing/updating $nextWindow"
    set settings($nextWindow,posXY) "[GetX] [GetY]"
    set settings($nextWindow,size) "[GetWidth] [GetHeight]"
    set settings($nextWindow,stayOnTop) $stayOnTop
    if {![info exists slot2handle($nextWindow)]} {
        Capture
    } else {
        UpdateN $nextWindow
    }
    SaveSettings
    CheckAutoKill
}

proc UpdateExcluded {} {
    global skipMonitorText settings
    set v $settings(ignoreMonitorIdx)
    if {$v==0} {
        set txt "None"
    } else {
        set txt "$v"
    }
    set skipMonitorText "Excluding: $txt"
    if {[SetUpMonitors]} {
        ChangeLayout
    }
}

proc UpdateLayoutNumWindows {} {
    global settings layoutNumWindowsText
    set layoutNumWindowsText "Layout for $settings(numWindows) windows"
}

proc ChangeNumWindow {v} {
    global settings
    set n [expr round($v)]
    if {$n == $settings(numWindows)} {
        return
    }
    set settings(numWindows) $n
    ChangeLayout
}

proc WindowLayout {} {
    global settings monitorInfo scale skipMonitorText layoutinfo layoutNumWindowsText scaleText snapMenuText numWindowsFloat
    set tw .layout
    if {[winfo exists $tw]} {
        wm state $tw normal
        raise $tw
        ChangeLayout
        return
    }
    UpdateExcluded
    toplevel $tw
    wm title $tw "OpenMultiBoxing Window Layout"
    ttk::checkbutton $tw.cbA -variable settings(layoutAuto) -text "Auto" -command ChangeLayout
    tooltip $tw.cbA "Automatically regenerate the layout on any change\nwhen checked. Uncheck for manual layout"
    ttk::checkbutton $tw.cbT -variable settings(layoutTop) -text "Main at bottom" -command ChangeLayout
    tooltip $tw.cbT "Checked if you prefer the main window at the bottom instead of the top of the screen"
    set numWindowsFloat $settings(numWindows)
    ttk::scale $tw.s -variable numWindowsFloat -orien horizontal -from 0 -to $settings(layoutMaxWindows) -command ChangeNumWindow
    tooltip $tw.s "Select how many windows in your layout."
    ttk::checkbutton $tw.cb1 -variable settings(layoutOneSize) -text "Same size for all" -command ChangeLayout
    ttk::checkbutton $tw.cb2 -variable settings(layoutOneRowCol) -text "One row/col for small windows" -command ChangeLayout
    ttk::checkbutton $tw.cb3 -variable settings(layoutStacked) -text "All Stacked" -command ChangeLayout
    tooltip $tw.cb1 "Check or uncheck to redo the layout with\nwindows of the same size (fastest switch later)\nor not (1 big main window and smaller minions windows)"
    set layoutNumWindowsText "Layout for 99 windows"
    set width [expr {2+[string length $layoutNumWindowsText]}]
    UpdateLayoutNumWindows
    grid x x x x $tw.cb2 - x -padx 8 -sticky we
    grid $tw.cbA -column 0 -row 0 -sticky {}
    grid [ttk::label $tw.l1 -textvariable layoutNumWindowsText -width $width -anchor c -justify center] $tw.s - $tw.cb1  $tw.cbT $tw.cb3 -sticky we -padx 8
    tooltip $tw.l1 "After automatic layout,\ndrag any window to adjust as necessary,\nuse arrow keys for fine pixel adjustment.\nClick on text to toggle stay on top... etc..."
    frame $tw.asrf
    ttk::radiobutton $tw.asrf.ar0 -value "Any" -text "Any" -variable settings(aspectRatio) -command ChangeLayout
    ttk::radiobutton $tw.asrf.ar1 -value "5/4" -text "5:4" -variable settings(aspectRatio) -command ChangeLayout
    ttk::radiobutton $tw.asrf.ar2 -value "4/3" -text "4:3" -variable settings(aspectRatio) -command ChangeLayout
    ttk::radiobutton $tw.asrf.ar3 -value "16/10" -text "16:10" -variable settings(aspectRatio) -command ChangeLayout
    ttk::radiobutton $tw.asrf.ar4 -value "16/9" -text "16:9" -variable settings(aspectRatio) -command ChangeLayout
    ttk::radiobutton $tw.asrf.ar5 -value "21/9" -text "21:9" -variable settings(aspectRatio) -command ChangeLayout
    pack [ttk::label $tw.asrf.l2 -text "Aspect ratio:" -anchor w -justify left] $tw.asrf.ar0  $tw.asrf.ar1  $tw.asrf.ar2  $tw.asrf.ar3  $tw.asrf.ar4  $tw.asrf.ar5 -side left -expand 1
    grid $tw.asrf -padx 3 -pady 6 -columnspan 6 -sticky we
    grid [canvas $tw.c -relief ridge -bd 2] -columnspan 6 -padx 5
    grid [ttk::label $tw.linfo -textvariable layoutinfo] -columnspan 6
    ttk::menubutton $tw.monIdx -textvariable skipMonitorText -menu $tw.monIdx.menu
    tooltip $tw.monIdx "Select the monitor(s) to exclude from the automatic layout."
    menu $tw.monIdx.menu -tearoff 0
    set scaleText "Scale: $settings(layoutScale)"
    ttk::menubutton $tw.scaleMenu -textvariable scaleText -menu $tw.scaleMenu.menu
    tooltip $tw.scaleMenu "Pick the scaling down for this visualization (zoom in/out).\nAlso affects the grid."
    menu $tw.scaleMenu.menu -tearoff 0
    foreach scaleLabel {1/16 1/10 1/8 1/6 1/5 1/4 1/3 1/2} {
        $tw.scaleMenu.menu add radiobutton -variable settings(layoutScale) -label $scaleLabel -value $scaleLabel -command UpdateExcluded
    }
    set snapMenuText "Snap to: None"
    ttk::menubutton $tw.snapMenu -textvariable snapMenuText -width [string length $snapMenuText] -menu $tw.snapMenu.menu
    if {$settings(layoutSnap) != 1} {
        set snapMenuText "Snap to: $settings(layoutSnap)"
    }
    tooltip $tw.snapMenu "When releasing manual mouse drag of windows,\nthe top left corner will be rounded to the nearest\nmultiple of this / scale."

    menu $tw.snapMenu.menu -tearoff 0
    foreach snapLabel {None 2 4 5 8 10 16 20 24 32 50 64 100} {
        set v $snapLabel
        if {$snapLabel == "None"} {
            set v 1
        }
        $tw.snapMenu.menu add radiobutton -variable settings(layoutSnap) -label $snapLabel -value $v -command [list set snapMenuText "Snap to: $snapLabel"]
    }
    ttk::style configure OmbBoldButton.TButton -font WOBBold
    grid $tw.monIdx $tw.scaleMenu \
        [ttk::checkbutton $tw.ctaskbar -text "Avoid\ntaskbar area" -variable settings(avoidTaskbar) -command UpdateExcluded] \
        [ttk::checkbutton $tw.cstayontop -text "Default to\nStay on top" -variable stayOnTop] \
        $tw.snapMenu \
        [ttk::button $tw.bsave -text " Save and Apply " -command SaveLayout -style OmbBoldButton.TButton] -sticky ns -padx 4 -pady 4
    tooltip $tw.bsave "Saves the currently shown layout into permanent settings\nand apply it to any captured WoW windows.\nClose the window without clicking to keep your previous Layout."
    tooltip  $tw.cstayontop "Whether newly laid out window will have\nStay On Top set or not as starting value."
    grid rowconfigure $tw 3 -weight 1
    for {set i 0} {$i<6} {incr i} {
        grid columnconfigure $tw $i -weight 1
    }
    SetUpMonitors
}

proc AddRemoveExcluded {i} {
    global settings
    Debug "updating exclude for $i : $settings(ignoreMonitorIdx)"
    if {$settings(ignoreMonitorIdx) == "0"} {
        set settings(ignoreMonitorIdx) $i
    } elseif {$settings(ignoreMonitorIdx) == "$i"} {
        set settings(ignoreMonitorIdx) 0
    } else {
        set l [split $settings(ignoreMonitorIdx) ,]
        set idx [lsearch -exact $l $i]
        if {$idx == -1} {
            lappend l $i
        } else {
            set l [lreplace $l $idx $idx]
        }
        set settings(ignoreMonitorIdx) [join [lsort -integer $l] ,]
        Debug "updating exclude res $settings(ignoreMonitorIdx)"
    }
    UpdateExcluded
}

proc SetUpMonitors {} {
    global settings monitorInfo scale skipMonitorText ignoreMonitorIdx scaleText
    set tw .layout
    InitAspectRatio
    if {![winfo exists $tw.c]} {
        return 0
    }
    destroy $tw.c
    grid [canvas $tw.c -relief ridge -bd 2] -row 3 -columnspan 6 -padx 5
    set displayInfo [twapi::get_multiple_display_monitor_info]
    Debug "displayInfo = $displayInfo"
    set n 0
    set i 0
    set colors {navyblue purple darkgreen grey brown black}
    $tw.monIdx.menu delete 0 99
    $tw.monIdx.menu add checkbutton -label "None" -command "set settings(ignoreMonitorIdx) 0; UpdateExcluded" -variable ignoreMonitorIdx(0)
    set ignoreMonitorIdx(0) 1
    set totalArea 0
    set mlist {}
    foreach monitor $displayInfo {
        incr i 1
        $tw.monIdx.menu add checkbutton -label "Display $i"  -command [list AddRemoveExcluded $i] -variable ignoreMonitorIdx($i)
        if {[lsearch -exact [split $settings(ignoreMonitorIdx) ","] $i] != -1} {
            set ignoreMonitorIdx($i) 1
            set ignoreMonitorIdx(0) 0
            Debug "Ignoring monitor $i"
            continue
        }
        set ignoreMonitorIdx($i) 0
        array set info $monitor
        lassign $info(-workarea) x1 y1 x2 y2
        lassign $info(-extent) xx1 yy1 xx2 yy2
        Debug "Workarea $x1,$y1  - $x2,$y2"
        Debug "Extent   $xx1,$yy1  - $xx2,$yy2"
        if {!$settings(avoidTaskbar)} {
            set x1 $xx1
            set y1 $yy1
            set x2 $xx2
            set y2 $yy2
        }
        set monitorInfo($n,x1) $x1
        set monitorInfo($n,y1) $y1
        set monitorInfo($n,x2) $x2
        set monitorInfo($n,y2) $y2
        set width [expr {$x2-$xx1}]
        set height  [expr {$y2-$yy1}]
        set monitorInfo($n,width) $width
        set monitorInfo($n,height) $height
        set area [expr $width*$height]
        set monitorInfo($n,area) $area
        lappend mlist [list $n $area]
        incr totalArea $area
        if {$n==0} {
            set minX $xx1
            set maxX $xx2
            set minY $yy1
            set maxY $yy2
            set minHeight $height
            set minWidth $width
        } else {
            set minX [expr min($minX,$xx1)]
            set maxX [expr max($maxX,$xx2)]
            set minY [expr min($minY,$yy1)]
            set maxY [expr max($maxY,$yy2)]
            set minHeight [expr min($minHeight, $height)]
            set minWidth [expr min($minWidth, $width)]
        }
        $tw.c create rectangle $xx1 $yy1 $xx2 $yy2 -fill [lindex $colors $n] -tag display
        incr n 1
        $tw.c create text $xx2 $yy2 -fill white -text "Display $i " -anchor se -tag display
        Debug "Area $x1,$y1 - $x2,$y2"
    }
    set monitorInfo(n) $n
    # in case all monitors have been skipped
    if {$n == 0} {
        $tw.c create text 0 0 -text "\n   All your monitors are excluded,\n   you need to leave at least 1." -tag wowAll -anchor nw
        return 0
    }
    set monitorInfo(mlist) [lsort -integer -index 1 $mlist]
    set monitorInfo(totalArea) $totalArea
    set monitorInfo(minHeight) $minHeight
    set monitorInfo(minWidth) $minWidth
    parray monitorInfo
    Debug "bbox 1 [$tw.c bbox all]"
    set scale [expr "1.0*$settings(layoutScale)"]
    if {$scale > 0.5} {
        set scale 0.5
    } elseif {$scale < 1./32.} {
        set scale 1./32.
    }
    set scaleText "Scale: $settings(layoutScale)"
    Debug "scale $settings(layoutScale) -> $scale"
    $tw.c scale all 0 0 $scale $scale
    Debug "bbox 2 [$tw.c bbox all]"
    set width [expr $maxX-$minX]
    set height [expr $maxY-$minY]
    $tw.c configure -width [expr {$width*$scale+8}] -height [expr {$height*$scale+8}] \
        -scrollregion [list [expr {$minX*$scale-4}] [expr {$minY*$scale-4}] [expr {$maxX*$scale}] [expr {$maxY*$scale}]]
    Debug "xview [$tw.c xview]"
    Debug "yview [$tw.c xview]"
    Debug "$minX,$minY - $maxX,$maxY - $width x $height"
    LoadLayout
    return $n
}

proc ConstrainWindow {x1 y1 x2 y2 aspectRatio} {
    set w [expr {$x2-$x1}]
    set h [expr {$y2-$y1}]
    if {$aspectRatio == 0} {
        # 'Any' aspect ratio still means not taller than square, if so use 5:4
        if {$w>$h} {
            return [list $x1 $y1 $x2 $y2]
        }
        set aspectRatio [expr {5./4.}]
    }
    set hA [expr {round($w/$aspectRatio)}]
    set wA [expr {round($h*$aspectRatio)}]
    Debug "x1 $x1 x2 $x2 y1 $y1 y2 $y2 : $w x $h -> $w x $hA or $wA x $h ($aspectRatio)"
    if {$h == $hA} {
        return [list $x1 $y1 $x2 $y2]
    }
    if {$h > $hA} {
        if {$y1 < 0} {
            return [list $x1 [expr {$y2-$hA}] $x2 $y2]
        }
        return [list $x1 $y1 $x2 [expr $y1+$hA]]
    }
    # shrink width
    if {$x1 < 0} {
        return [list [expr {$x2-$wA}] $y1 $x2 $y2]
    }
    return [list $x1 $y1 [expr $x1+$wA] $y2]
}

proc SetWindowOnCanvas {id x1 y1 x2 y2} {
    global sot stayOnTop settings
    set c .layout.c
    set tag "wow$id"
    $c delete $tag
    set tags [list $tag "wowAll"]
    set txtTags $tags
    lappend txtTags "wowText"
    lappend tags "wowWindow"
    set w [expr {$x2-$x1}]
    set h [expr {$y2-$y1}]
    $c create rectangle $x1 $y1 $x2 $y2 -fill #ffd633 -tags $tags
    set pin ""
    set hasPin $stayOnTop
    if {[info exists settings($id,stayOnTop)]} {
        set hasPin $settings($id,stayOnTop)
    }
    if {$hasPin} {
        set pin "📌"
        set sot($id) 1
        after idle "$c raise $tag; $c itemconfigure $tag&&wowWindow -fill #ffcc00"
    } else {
        set sot($id) 0
        after idle "$c itemconfigure $tag&&wowWindow -fill #ffd633"
    }
    $c create text $x1 $y1 -text "\n   ${pin}OMB $id${pin}\n   $w x $h" -anchor "nw" -tags $txtTags
    Debug "Window $id $x1,$y1 $x2,$y2 ($tags)"
}

proc UpdateWindowText {tag w h} {
    global sot
    set c .layout.c
    set t [$c find withtag "$tag&&wowText"]
    regsub {^wow} $tag {} id
    set pin ""
    if {$sot($id)} {
        set pin "📌"
        after idle "$c raise $tag; $c itemconfigure $tag&&wowWindow -fill #ffcc00"
    } else {
        after idle "$c itemconfigure $tag&&wowWindow -fill #ffd633"
    }
    $c itemconfigure $t -text "\n   ${pin}OMB $id${pin}\n   $w x $h"
}

proc LoadLayout {} {
    global settings scale
    set c .layout.c
    if {![winfo exists $c]} {
        # called from LoadSettings for instance but layout window is not up
        return
    }
    UpdateLayoutNumWindows
    $c delete wowAll
    set n $settings(numWindows)
    if {$n==0 || $n==""} {
        set n 999
    }
    foreach k [array names settings "*,posXY"] {
        set i [lindex [split $k ","] 0]
        lassign $settings($k) x1 y1
        lassign $settings($i,size) w h
        Debug "Found settings for OMB $i $x1 , $y1  $w x $h"
        if {$i>$n} {
            continue
        }
        SetWindowOnCanvas $i $x1 $y1 [expr {$x1+$w}] [expr {$y1+$h}]
    }
    $c scale wowAll 0 0 $scale $scale
    SetupMove
}

proc SizeOfWindow {tag} {
    global scale
    set c .layout.c
    set r [lindex [$c find withtag $tag] 0]
    if {$r == ""} {
        Debug "$tag not found"
        return {}
    }
    lassign [$c coords $r] x1 y1 x2 y2
    set w  [expr {round(($x2-$x1)/$scale)}]
    set h  [expr {round(($y2-$y1)/$scale)}]
    set x1 [expr {round($x1/$scale)}]
    set x2 [expr {round($x2/$scale)}]
    set y1 [expr {round($y1/$scale)}]
    set y2 [expr {round($y2/$scale)}]
    Debug "$tag found [$c coords $r] for saving -> $x1, $y1 - $x2, $y2 -> $w x $h"
    return [list $x1 $y1 $w $h]
}

# --- start of broadcasting ---
# (not to be used for world of warcraft)

proc BroadcastKeys {keySequence} {
    global settings slot2handle
    foreach {n w} [array get slot2handle] {
        Debug "Sending key sequence $keySequence to $n ($w)"
        twapi::set_foreground_window $w
        twapi::send_keys $keySequence
    }
}

proc BroadcastText {text {addEnterKey 0}} {
    global settings slot2handle
    set first 1
    foreach {n w} [array get slot2handle] {
        Debug "Sending text to $n ($w)"
        if {![twapi::set_foreground_window $w]} {
            Debug "Failed to set fg for $n ($w)"
            continue
        }
        if {$first} {
            # first one is slow to switch somehow
            after 50
            twapi::set_foreground_window $w
            after 50
            set first 0
        }
        twapi::send_input_text $text
        if {$addEnterKey} {
            twapi::send_input {{key 13 0}}
        }
    }
}

# For instance this sends Up arrow for 0.5s to windows without change to which is fg/active:
# BroadcastKey 0x26 500

proc BroadcastKey {keyCode {delayMs 100}} {
    global slot2handle
    set WM_KEYDOWN 0x0100
    set WM_KEYUP 0x0101
    foreach {n w} [array get slot2handle] {
        Debug "Sending input key $keyCode to $n ($w)"
        twapi::PostMessage $w $WM_KEYDOWN $keyCode 1
    }
    after $delayMs
    foreach {n w} [array get slot2handle] {
        twapi::PostMessage $w $WM_KEYUP $keyCode 1
    }
    # could also use twapi::send_input but that changes fg/active window
}

# Send key to all windows except the one with the given slot number
# Use up=1 for key up, up=0 for key down
proc BroadcastKeyToOther {n keyCode up} {
    global slot2handle
    set ev [expr {0x0100+$up}]
    set lparam 0
    if {$up} {
        set lparam 0xC0000001
    }
    foreach {i w} [array get slot2handle] {
        if {$i==$n} {
            continue
        }
        twapi::PostMessage $w $ev $keyCode $lparam
    }
}

# Unfortunatly this does not work (mouse coords are not used, it only clicks where the mouse really is)
proc BroadcastMouseClick {x y} {
    global slot2handle settings
    set WM_LBUTTONDOWN 0x0201
    set WM_LBUTTONUP 0x0202
    set WM_MOUSEMOVE 0x0200
    set lword [expr {($x<<16)+$y}]
    foreach {n w} [array get slot2handle] {
        Debug "Sending mouse click $x,$y $lword to $n ($w)"
        twapi::PostMessage $w $WM_MOUSEMOVE 1 $lword
        twapi::PostMessage $w $WM_LBUTTONDOWN 1 $lword
    }
    after $settings(mouseBroadcastDelay)
    foreach {n w} [array get slot2handle] {
        twapi::PostMessage $w $WM_LBUTTONUP 1 $lword
    }
}

# --- start of RR, now Broadcasting ---

# returns 1 if the binary has the needed cffi support
proc CheckBinary {} {
    global vers
    if {![namespace exists "cffi"]} {
        OmbError "Outdated binary for Broadcasting"\
            "To use broadcasting, you must download a more recent\nOMB .exe: get and extract OpenMultiboxing-${vers}.zip\n\nVisit https://OpenMultiBoxing.org click \"Get the Software\""
        return 0
    }
    return 1
}

proc RRToggle {} {
    global rrOn hasRR hasBR vers
    set rrOn [expr {!$rrOn}]
    RRUpdate
}

# Read/reset all keys so we don't pile up keydown when Broadcasting is off
proc RRreadAllKeys {} {
    global rrCodes rrExcludes rrCodesCustom rrCodesDirect
    foreach code $rrExcludes {
        twapi::GetAsyncKeyState $code
    }
    foreach code $rrCodes {
        twapi::GetAsyncKeyState $code
    }
    foreach code $rrCodesCustom {
        twapi::GetAsyncKeyState $code
    }
    foreach code $rrCodesDirect {
        twapi::GetAsyncKeyState $code
    }
}

proc RRUpdate {} {
    global rrOn rrOnLabel settings hasRR hasBR mouseFollow rrMouse rrLastCode rrTaskId mouseBroadcast
    Debug "RRupdate $rrOn"
    if {[info exists rrTaskId]} {
        after cancel $rrTaskId
        unset rrTaskId
    }
    set rrLastCode {}
    if {$rrOn && $hasRR} {
        set rrOnLabel $settings(rrIndicator,label)
        RRKeysListChange
        RRreadAllKeys
        set rrMouse $mouseFollow
        if {$mouseFollow} {
            set mouseFollow 0
            UpdateMouseFollow
            .mf configure -state disabled
        }
        set rrTaskId [after $settings(rrInterval) RRCheck]
        if {[winfo exists .o1.rr]} {
            place configure .o1.rr -relx $settings(rrIndicator,x) -rely $settings(rrIndicator,y)
        }
    } else {
        set rrOnLabel ""
        .mf configure -state enabled
        if {[info exists rrMouse] && $rrMouse && !$mouseBroadcast} {
            set mouseFollow 1
            UpdateMouseFollow
        }
    }
    AddMouseToRRLabel
    # read twice
    GetKeyboardState
    set rrLastCode [GetKeyboardState]
    Debug "Reset all Broadcasting key states"
}

proc RRkeyListToCodes {keyList {noneKeyPattern ""}} {
    twapi::_init_vk_map
    set res {}
    set fixedList {}
    foreach k [split $keyList " "] {
        set len [string length $k]
        if {$len == 0} {
            # skip extra spaces
            continue
        }
        if {$len == 1} {
            lassign [twapi::VkKeyScan $k] x code
        } else {
            if {$noneKeyPattern!="" && [string match $noneKeyPattern $k]} {
                # only for direct we need to skip some positions
                set code 0
            } elseif {![info exists twapi::vk_map($k)]} {
                OmbError "Invalid Broadcasting key" "$k isn't a valid key"
                continue
            } else {
                set code [expr [lindex $twapi::vk_map($k) 0]]
            }
        }
        Debug "RRkey $k -> 0x[format %x $code]"
        lappend res $code
        lappend fixedList $k
    }
    return [list $res [join $fixedList " "]]
}

set rrCodes {}
set rrExcludes {}
set rrExcludes {}
set rrCodesCustom {}
set rrCodesDirect {}
proc RRKeysListChange {} {
    global settings rrCodes rrExcludes rrCodesCustom rrCodesDirect
    lassign [RRkeyListToCodes $settings(rrKeyListExclude)] rrCodes settings(rrKeyListExclude)
    #lassign [RRkeyListToCodes $settings(rrKeyListCustom)] rrCodesCustom settings(rrKeyListCustom)
    #lassign [RRkeyListToCodes $settings(rrKeyListDirect) ".*"] rrCodesDirect settings(rrKeyListDirect)
    lassign [RRkeyListToCodes $settings(rrModExcludeList)] rrExcludes settings(rrModExcludeList)
    ResetIgnoredKeys $rrCodes
}

set rrLastCode {}
set rrLastCustom 0

proc ResetIgnoredKeys {codes} {
    global ignoredKeyCode
    catch {unset ignoredKeyCode}
    array set ignoredKeyCode {}
    for {set i 0} {$i <= 7} {incr i} {
        set ignoredKeyCode($i) 1
    }
    # Ignore the non specific shift, ctrl, alt (instead we use lalt/ralt etc)
    foreach code {16 17 18} {
        set ignoredKeyCode($code) 1
    }
    foreach code $codes {
        set ignoredKeyCode($code) 1
    }
    Debug "ResetIgnoredKeys [array names ignoredKeyCode]"
}

proc GetKeyboardState {} {
    global ignoredKeyCode
    set res {}
    for {set i 0} {$i <= 254} {incr i} {
        if {[info exists ignoredKeyCode($i)]} {
            lappend res 0
        } else {
            lappend res [expr {[twapi::GetAsyncKeyState $i]>0}]
        }
    }
    return $res
}

# Compare old and new state and return the list of keys that changed
proc DeltaKeyboardState {oldState newState} {
    set resUp {}
    set resDown {}
    for {set i 0} {$i<[llength $oldState]} {incr i} {
        set old [lindex $oldState $i]
        set new [lindex $newState $i]
        if {$old!=$new} {
            Debug "Key 0x[format %02x $i] changed from [format %x $old] to [format %x $new]"
            if {$old==0} {
                lappend resDown [expr $i]
            } else {
                lappend resUp $i
            }
        }
    }
    return [list $resUp $resDown]
}


proc RRCheck {} {
    global rrCodes rrCodesCustom rrCodesDirect rrExcludes rrLastCode rrLastCustom rrTaskId settings maxNumW
    set rrTaskId [after $settings(rrInterval) RRCheck]
    #Debug "RR Check..."
    set n 1
    if {![MouseIsIn]==$n} {
        #Debug "Mouse not in $n"
        return
    }
    foreach code $rrExcludes {
        set state [twapi::GetAsyncKeyState $code]
        if {$state != 0} {
            # modifier held; return
            set rrLastCode [GetKeyboardState]
            return
        }
    }
    # current state
    set curState [GetKeyboardState]
    lassign [DeltaKeyboardState $rrLastCode $curState] newUp newDown
    #Debug "RRCheck: newUp $newUp newDown $newDown"
    set rrLastCode $curState
    foreach code $newUp {
        Debug "Key $code now reset, sending up event"
        BroadcastKeyToOther $n $code 1
    }
    foreach code $newDown {
        Debug "Key $code now down, sending down event"
        BroadcastKeyToOther $n $code 0
    }


    # direct on key down
    # set i 0
    # foreach code $rrCodesDirect {
    #     # Allow "NONE"
    #     if {$code != 0} {
    #         set state [twapi::GetAsyncKeyState $code]
    #         if {$state != 0} {
    #             FocusDirect [expr {$i%($settings(numWindows)+1)}]
    #             break
    #         }
    #     }
    #     incr i
    # }
    # # custom rotation, keyUp normal mode
    # foreach code $rrCodesCustom {
    #     set state [twapi::GetAsyncKeyState $code]
    #     if {$state != 0} {
    #         set rrLastCode $code
    #         set rrLastCustom 1
    #         return
    #     }
    # }
}

proc FocusDirect {n} {
    global lastFocusWindow slot2position resetTaskId settings
    # Like in FocusNextWindow - cancel auto reset
    if {[info exists resetTaskId]} {
        after cancel $resetTaskId
        unset resetTaskId
    }
    # Like FocusMain
    if {$n==0} {
        if {![info exists slot2position(1)]} {
            return
        }
        set n $slot2position(1)
    }
    if {$settings(rrAlwaysFocus) || $n!=$lastFocusWindow} {
        CheckWindow [list FocusN $n true 0] $n
    }
    if {$settings(autoResetFocusToMain)>0 && $settings(autoResetDirect)} {
        set resetTaskId [after [expr {round(1000.*$settings(autoResetFocusToMain))}] FocusMain]
    }
}

proc RRCustomToArray {} {
    global settings rrCustom
    catch {unset rrCustom}
    array set rrCustom {}
    #foreach w $settings(rrCustomExcludeList) {
    #    set rrCustom($w) 1
    #}
}

proc RRCustomUpdateSettings {} {
    global settings rrCustom
    set settings(rrCustomExcludeList) {}
    foreach {k v} [array get rrCustom] {
        if {$v} {
            lappend settings(rrCustomExcludeList) $k
        }
    }
}

proc RRCustomMenu {} {
    global settings rrCustom hasRR hasBR
    if {!$hasRR&&!$hasBR} {
        return
    }
    RRCustomToArray
    set m .rrC.rrMenuB.menu
    if {![winfo exists $m]} {
        return
    }
    $m delete 0 99
    $m add checkbutton -label "Main" -variable rrCustom(0) -command RRCustomUpdateSettings
    for {set i 1} {$i<=$settings(numWindows)} {incr i} {
        $m add checkbutton -label "OMB $i" -variable rrCustom($i) -command RRCustomUpdateSettings
    }
}

# --- end of Broadcasting ---

proc OverlayToggle {} {
    global settings
    set settings(showOverlay) [expr {!$settings(showOverlay)}]
    OverlayUpdate
}

proc OverlayUpdate {} {
    global settings lastFocusWindow slot2position
    set on $settings(showOverlay)
    set lastOverlay $settings(numWindows)
    set plfw $lastFocusWindow
    if {[info exists slot2position($lastFocusWindow)]} {
        set plfw $slot2position($lastFocusWindow)
        Debug "Will show focus on area $plfw for $lastFocusWindow"
    }
    if {$settings(layoutStacked)} {
        set lastOverlay 1
    }
    for {set i 1} {$i<=$lastOverlay} {incr i} {
        set t .o$i
        if {![winfo exists $t]} {
            Debug "Overlay for $i doesn't exist..."
            return
        }
        if {$on} {
            if {$i==$plfw} {
                Debug "Highlight on $i"
                $t.l configure -foreground $settings(overlayFocusColor)
            } else {
                $t.l configure -foreground white
            }
            wm state $t normal
        } else {
            wm state $t withdrawn
            $t.l configure -foreground white
        }
    }
}

proc OverlayConfig {} {
    global settings hasRR hasBR RRlabel
    set tw .overlayConfig
    set settings(showOverlay) 1
    OverlayUpdate
    if {[winfo exists $tw]} {
        wm state $tw normal
        raise $tw
        return
    }
    toplevel $tw
    wm title $tw "OpenMultiBoxing Overlay Configuration"
    grid [ttk::label $tw.l1 -text "Pick the location of the window number overlay:"] -columnspan 3
    grid [ttk::button $tw.b1 -text "\u2b76" -command "OverlayAnchor nw"] [ttk::button $tw.b2 -text "\u2b71" -command "OverlayAnchor n"] [ttk::button $tw.b3 -text "\u2b77" -command "OverlayAnchor ne"]
    grid [ttk::button $tw.b4 -text "\u2b70" -command "OverlayAnchor w"] [ttk::button $tw.b5 -text "\uB7" -command "OverlayAnchor c"] [ttk::button $tw.b6 -text "\u2b72" -command "OverlayAnchor e"]
    grid [ttk::button $tw.b7 -text "\u2b79" -command "OverlayAnchor sw"] [ttk::button $tw.b8 -text "\u2b73" -command "OverlayAnchor s"] [ttk::button $tw.b9 -text "\u2b78" -command "OverlayAnchor se"]
    for {set i 0} {$i<3} {incr i} {
        grid rowconfigure $tw [expr {$i+1}] -weight 1
        grid columnconfigure $tw $i -weight 1
    }
    grid [ttk::label $tw.l2 -text "Overlay transparency:"] -columnspan 3
    grid [ttk::scale $tw.str  -variable settings(overlayAlpha) -command "OverlayTransparency"] -sticky ew -padx 4 -pady 4 -columnspan 3
    grid [button $tw.color -text "Change Focus Color" -bg $settings(overlayFocusColor) -command OverlayChangeFocusColor] -padx 8 -pady 4 -columnspan 3
    grid [ttk::checkbutton $tw.border -text "Overlay border" -variable settings(overlayShowBorder) -command "Overlay; SaveSettings"] -padx 8 -pady 2 -columnspan 3
    grid [ttk::label $tw.lf1 -text "Window 1 font size:"] -columnspan 3
    grid [ttk::scale $tw.sf1 -from 8. -to 128. -variable settings(overlayFontSize1) -command OverlayFontSizes] -sticky ew -padx 4 -pady 4 -columnspan 3
    grid [ttk::label $tw.lf2 -text "Window 2+ font size:"] -columnspan 3
    grid [ttk::scale $tw.sf2 -from 8. -to 128. -variable settings(overlayFontSize2) -command OverlayFontSizes] -sticky ew -padx 4 -pady 4 -columnspan 3

    grid [ttk::checkbutton $tw.clickable -text "Clickable overlay" -variable settings(overlayClickable) -command "Overlay; SaveSettings"] -padx 8 -pady 2 -columnspan 3
    grid [ttk::checkbutton $tw.bigAll -text "Click to swap all area on windows 2+" -variable settings(overlayAllClickable) -command "Overlay; SaveSettings"] -padx 8 -pady 2 -columnspan 3
    if {$hasRR||$hasBR} {
        grid [ttk::label $tw.lr1 -text "$RRlabel indicator:" -font "*-*-bold" -anchor w] -columnspan 3 -sticky ew -padx 6
        grid [ttk::label $tw.lr2 -text "Label:" -anchor e] [entry $tw.re1 -width 5 -textvariable settings(rrIndicator,label)] -sticky ew -padx 6
        bind $tw.re1 <Return> "RRUpdate; SaveSettings"
        tooltip $tw.re1 "What is shown when Broadcasting is on"
    }
    grid [ttk::label $tw.lm1 -text "Mouse Broadcast indicator:" -font "*-*-bold" -anchor w] -columnspan 3 -sticky ew -padx 6
    grid [ttk::label $tw.lm2 -text "Label:" -anchor e] [entry $tw.me1 -width 5 -textvariable settings(mfIndicator,label)] -sticky ew -padx 6
    tooltip $tw.me1 "What is shown when Focus Follow Mouse is on"
    bind $tw.me1 <Return> "AddMouseToRRLabel; SaveSettings"
    if {$hasRR||$hasBR} {
        grid [ttk::label $tw.lp1 -text "⟳ and 🖰 indicators position:" -font "*-*-bold" -anchor w] -columnspan 3 -sticky ew -padx 6
    }
    grid [ttk::label $tw.lr3 -text "X:" -anchor e] [entry $tw.re2 -width 5 -textvariable settings(rrIndicator,x)] -sticky ew -padx 6
    bind $tw.re2 <Return> "RRUpdate; SaveSettings"
    tooltip $tw.re2 "Relative horizontal position: 0 is left 1 is right, 0.5 is center"
    grid [ttk::label $tw.lr4 -text "Y:" -anchor e] [entry $tw.re3 -width 5 -textvariable settings(rrIndicator,y)] -sticky ew -padx 6
    bind $tw.re3 <Return> "RRUpdate; SaveSettings"
    tooltip $tw.re3 "Relative vertical position: 0 is top 1 is bottom, 0.5 is center"
    grid [ttk::label $tw.lr5 -text "(Hit <Return> to update)" -anchor n] -pady 6 -columnspan 3
    UpdateHandles
}

proc OverlayChangeFocusColor {} {
    global settings lastFocusWindow
    set color [tk_chooseColor -initialcolor gray -title "Choose overlay focus color"]
    if {$color == ""} {
        return
    }
    set settings(overlayFocusColor) $color
    .overlayConfig.color configure -bg $color
    windowIndicatorN $lastFocusWindow configure -foreground $color
    set f .o1.rr
    if {[winfo exist $f]} {
        $f configure -foreground $color
    }
    SaveSettings
}

proc OverlayTransparency {alpha} {
    set i 1
    while {[winfo exists .o$i]} {
        wm attributes .o$i -alpha $alpha
        incr i
    }
}

proc OverlayFontSizes {args} {
    global settings
    set transparentcolor #606060
    set overlayFontSize1 [expr {round($settings(overlayFontSize1))}]
    set overlayFontSize2 [expr {round($settings(overlayFontSize2))}]
    ttk::style configure OmbOverlayText.Label -font "Arial $overlayFontSize1 bold" -foreground white -background $transparentcolor
    ttk::style configure OmbOverlayTextBig.Label -font "Arial $overlayFontSize2 bold" -foreground white -background $transparentcolor
    ttk::style configure OmbOverlayTextBigFull.Label -font "Arial $overlayFontSize2 bold" -foreground white -background black
    return $transparentcolor
}

proc OverlayAnchor {anchor} {
    global settings
    set settings(overlayAnchor) $anchor
    set i 1
    while {[winfo exists .o$i.l]} {
        .o$i.l configure -anchor $anchor
        incr i
    }
    SaveSettings
}

# Wip (aka not working!)
proc SetClickThrough {t} {
    set wh [twapi::tkpath_to_hwnd $t]
    lassign [twapi::get_window_style $wh] style exstyle
    Debug "$t : $wh : [format "%x %x" $style $exstyle]"
    set nex [expr {0x08000000|0x00080000|0x00000008|0x00000020}]
    Debug "$t : $wh : [twapi::get_window_style $wh] -> [format %x $nex]"
    twapi::set_window_style $wh $style $nex
    lassign [twapi::get_window_style $wh] style exstyle
    Debug "$t : $wh : [format "%x %x" $style $exstyle]"
    Debug "$t : $wh : [twapi::get_window_style $wh]"
}

set rrOnLabel ""
proc Overlay {} {
    global settings rrOnLabel
    set transparentcolor [OverlayFontSizes]
    set on $settings(showOverlay)
    set lastOverlay $settings(numWindows)
    if {$settings(layoutStacked)} {
        set lastOverlay 1
    }
    set relief flat
    if {$settings(overlayShowBorder)} {
        set relief ridge
    }
    for {set i 1} {$i<=$lastOverlay} {incr i} {
        if {![info exists settings($i,posXY)]} {
            Debug "Numwindows $settings(numWindows) is higher than configured windows... error for $i"
            return
        }
        set t .o$i
        if {![winfo exists $t]} {
            toplevel $t -bd 2 -relief $relief
            wm overrideredirect $t 1
            wm attributes $t -alpha $settings(overlayAlpha) -topmost 1 -transparentcolor $transparentcolor
            $t configure -bg $transparentcolor
            ttk::label $t.l -text "$i" -style OmbOverlayText.Label -anchor $settings(overlayAnchor)
            if {$i==1} {
                ttk::label $t.rr -text "" -textvariable rrOnLabel -foreground $settings(overlayFocusColor) \
                    -style OmbOverlayText.Label -justify center -anchor c
                place $t.rr -in $t -relx $settings(rrIndicator,x) -rely $settings(rrIndicator,y) -anchor c
            }
            pack $t.l -fill both -expand 1
        } else {
            $t configure -relief $relief
        }
        if {$settings(overlayClickable)} {
            if {$i==1} {
                bind $t.l <ButtonPress> SwapNextWindow
                bind $t.rr <ButtonPress> RRToggle
            } else {
                bind $t.l <ButtonPress> [list SetAsMain $i]
            }
        } else {
            if {$i==1} {
                bind $t.l <ButtonPress> {}
                bind $t.rr <ButtonPress> {}
            } else {
                bind $t.l <ButtonPress> {}
            }
        }
        if {$i!=1} {
            if {$settings(overlayAllClickable)} {
                $t.l configure -style OmbOverlayTextBigFull.Label
            } else {
                $t.l configure -style OmbOverlayTextBig.Label
            }
        }
        lassign $settings($i,posXY) x y
        lassign $settings($i,size) w h
        if {$on} {
            wm state $t normal
        } else {
            wm state $t withdrawn
        }
        wm geometry $t ${w}x$h+$x+$y
    }
    while {[winfo exists .o$i]} {
        wm state .o$i withdrawn
        incr i
    }
    UpdateHandles
}

proc ResetAll {} {
    global settings lastUpdate lastSOT slot2position slot2handle maxNumW nextWindow
    array unset lastUpdate
    array unset lastSOT
    Debug "Reset all called!"
    set lastGood 0
    set firstBad 0
    for {set i $settings(numWindows)} {$i>=1} {incr i -1} {
        # reset initial position
        set slot2position($i) $i
        CheckWindow [list UpdateN $i] $i
        if {[info exists slot2handle($i)]} {
            Foreground $slot2handle($i)
            Debug "W $i is ok - last good $lastGood"
            if {$lastGood == 0} {
                set lastGood $i
            }
        } else {
            set firstBad $i
        }
    }
    SetAsMain 1
    if {[winfo exist .lbw]} {
        .lbw delete $lastGood end
    }
    set maxNumW [expr {$lastGood+1}]
    if {$firstBad} {
        set nextWindow $firstBad
    } else {
        set nextWindow $maxNumW
    }
    UpdateHandles
    CheckAutoKill
    Debug "All reset complete: lg $lastGood, fb $firstBad, mx $maxNumW, next $nextWindow"
}

proc SaveLayout {} {
    global settings slot2position scale sot
    set c .layout.c
    for {set i 1} {$i<=$settings(numWindows)} {incr i} {
        set coords [SizeOfWindow "wow$i"]
        if {$coords == ""} {
            Debug "$i not found while saving"
            continue
        }
        lassign $coords x1 y1 w h
        set settings($i,posXY) "$x1 $y1"
        set settings($i,size) "$w $h"
        set settings($i,stayOnTop) $sot($i)
        # reset initial position
        set slot2position($i) $i
        CheckWindow [list UpdateN $i] $i
        Debug "Sot for $i is $settings($i,stayOnTop) $sot($i)"
    }
    SaveSettings
    Overlay
    updateIndex
}

proc InitAspectRatio {} {
    global settings aspectRatio
    set aspectRatio 0
    catch {set aspectRatio [expr 1.0*$settings(aspectRatio)]}
    Debug "Aspect ratio $settings(aspectRatio) = $aspectRatio"
}

proc ChangeLayout {args} {
    global settings monitorInfo scale aspectRatio sot stayOnTop
    InitAspectRatio
    set layoutOneSize $settings(layoutOneSize)
    set n [expr round($settings(numWindows))]
    set settings(numWindows) $n
    RRCustomMenu
    UpdateLayoutNumWindows
    set c .layout.c
    if {![winfo exists $c]} {
        return
    }
    if {!$settings(layoutAuto)} {
        return
    }
    $c delete wowAll
    Debug "*** ChangeLayout $args for $n - onesize $layoutOneSize"
    if {$settings(layoutStacked)} {
        # biggest monitor
        set mIdx [lindex [lindex $monitorInfo(mlist) end] 0]
        set x1 $monitorInfo($mIdx,x1)
        set y1 $monitorInfo($mIdx,y1)
        set x2 $monitorInfo($mIdx,x2)
        set y2 $monitorInfo($mIdx,y2)
        lassign [ConstrainWindow $x1 $y1 $x2 $y2 $aspectRatio] x1 y1 x2 y2
        Debug "Stacked layout on $mIdx $x1 $y1 $x2 $y2"
        for {set i 1} {$i<=$n} {incr i} {
            SetWindowOnCanvas $i $x1 $y1 $x2 $y2
        }
    } elseif {$n<=$monitorInfo(n)} {
        Debug "One Wow per monitor"
        for {set i 0} {$i<$n} {incr i} {
            set x1 $monitorInfo($i,x1)
            set y1 $monitorInfo($i,y1)
            set x2 $monitorInfo($i,x2)
            set y2 $monitorInfo($i,y2)
            if {$layoutOneSize} {
                # prioritize closer to 0,0
                if {$x1<0} {
                    set x1 [expr {$x2-$monitorInfo(minWidth)}]
                } else {
                    set x2 [expr {$x1+$monitorInfo(minWidth)}]
                }
                if {$y1<0} {
                    set y1 [expr {$y2-$monitorInfo(minHeight)}]
                } else {
                    set y2 [expr {$y1+$monitorInfo(minHeight)}]
                }
            }
            lassign [ConstrainWindow $x1 $y1 $x2 $y2 $aspectRatio] x1 y1 x2 y2
            set id [expr {$i+1}]
            SetWindowOnCanvas $id $x1 $y1 $x2 $y2
        }
    } elseif {$monitorInfo(n)==1} {
        # Single monitor
        LayoutOneMonitor 0 1 $n $layoutOneSize 0 0 0 0
    } else {
        # assign windows in proportion of monitor surface
        set mlist $monitorInfo(mlist)
        lassign [lindex $mlist 0] s sArea
        if {!$layoutOneSize} {
            LayoutOneMonitorVariable $s 1 1
            LayoutMonitors [lrange $mlist 1 end] [expr {$monitorInfo(totalArea)-$sArea}] 2 [expr {$n-1}]
        } else {
            LayoutMonitors $mlist $monitorInfo(totalArea) 1 $n
        }
    }
    $c scale wowAll 0 0 $scale $scale
    SetupMove
}

proc LayoutMonitors {mlist totalArea startAt n args} {
    if {[llength $mlist]==0} {
        return $args
    }
    # split windows based on area
    lassign [lindex $mlist 0] s sArea
    set n1 [expr {int(floor(1.0*$n*$sArea/$totalArea))}]
    if {$n1==0} {
        set n1 1
    }
    set n2 [expr {$n-$n1}]
    Debug "Out of $n windows, putting $n1 on $s and rest $n2 on rest (bigger)"

    lassign [CalcSize $s $n1] w1 h1
    if {[llength $args]} {
        lassign $args w2 h2
        set ww [expr {min($w1,$w2)}]
        set wh [expr {min($h1,$h2)}]
    } else {
        set ww $w1
        set wh $h1
    }
    lassign [LayoutMonitors [lrange $mlist 1 end] [expr {$totalArea-$sArea}] [expr {$startAt+$n1}] [expr {$n-$n1}] $ww $wh] ww wh
    LayoutOneMonitorOneSize $s $startAt $n1 $ww $wh 0 0
    return [list $ww $wh]
}

proc LayoutOneMonitor {monitor startAt numWindows sameSize w h maxW maxH} {
    if {$sameSize} {
        LayoutOneMonitorOneSize $monitor $startAt $numWindows $w $h $maxW $maxH
    } else {
        LayoutOneMonitorVariable $monitor $startAt $numWindows
    }
}

proc SplitForN {n} {
    set sq [expr {sqrt($n)}]
    set ysplit [expr {int(floor($sq))}]
    set xsplit [expr {int(ceil($sq))}]
    Debug "I: $n -> $sq ->   $xsplit x $ysplit"
    while 1 {
        set m [expr {$xsplit*$ysplit}]
        if {$m>=$n} {
            Debug "F: $n -> $m ->   $xsplit x $ysplit"
            return [list $xsplit $ysplit]
        }
        incr ysplit 1
    }
}

proc CalcSize {monitor numWindows} {
    Debug "CalcSize $numWindows on monitor $monitor"
    global monitorInfo aspectRatio
    set w $monitorInfo($monitor,width)
    set h $monitorInfo($monitor,height)
    lassign [SplitForN $numWindows] xdiv ydiv
    set ww [expr {int($w/$xdiv)}]
    set wh [expr {int($h/$ydiv)}]
    lassign [ConstrainWindow 0 0 $ww $wh $aspectRatio] v1 v2 ww wh
    return [list $ww $wh $xdiv $ydiv]
}

proc LayoutOneMonitorOneSize {monitor startAt numWindows ww wh maxW maxH} {
    Debug "LayoutOneMonitorOneSize $ww x $wh for $numWindows starting at $startAt on monitor $monitor"
    global monitorInfo settings
    set x1 $monitorInfo($monitor,x1)
    set y1 $monitorInfo($monitor,y1)
    set x2 $monitorInfo($monitor,x2)
    set y2 $monitorInfo($monitor,y2)
    lassign [CalcSize $monitor $numWindows] w h xdiv ydiv
    if {$ww == 0} {
        set ww $w
        if {$maxW>0 && $ww>$maxW} {
            set ww $maxW
        }
    }
    if {$wh == 0} {
        set wh $h
        if {$maxH>0 && $wh>$maxH} {
            set wh $maxH
        }
    }
    Debug "Using windows of size $ww x $wh  ($xdiv x $ydiv grid for $numWindows) monitor $monitor: ($x1,$y1) $w x $h"
    for {set x 1} {$x<=$xdiv} {incr x} {
        for {set y 1} {$y<=$ydiv} {incr y} {
            if {$x1<0} {
                set xx [expr {$x2-$x*$ww}]
            } else {
                set xx [expr {$x1+($x-1)*$ww}]
            }
            if {$y1<0 || $settings(layoutTop)} {
                set yy [expr {$y2-$y*$wh}]
            } else {
                set yy [expr {$y1+($y-1)*$wh}]
            }
            SetWindowOnCanvas $startAt $xx $yy [expr {$xx+$ww}] [expr {$yy+$wh}]
            incr startAt 1
            incr numWindows -1
            if {$numWindows == 0} {
                return [list $ww $wh]
            }
        }
    }
    return [list $ww $wh]
}


proc LayoutOneMonitorVariable  {monitor startAt numWindows} {
    global monitorInfo aspectRatio settings
    # B window being a multiple of same size S window:
    #   BBBBS
    #   BBBBS
    #   BBBBS
    #   BBBBS
    #   SSSSC  ex is 8-9 boxing 1 big 4*2+1 small
    # Small ones making inverted L around big one
    # when small are 1/C size we can make up to  2*C+1 (corner)
    # so for N windows
    # C = (n-2)/2
    # n=3 is special with
    # BB
    # BB
    # SS
    if {$numWindows<=2} {
        LayoutOneMonitorOneSize $monitor $startAt $numWindows 0 0 0 0
        return
    }
    set c [expr {ceil(1.0*($numWindows-2)/2)}]
    if {$c<2} {
        set c 2
    }
    Debug "Will cut in $c to fit $numWindows"
    set x1 $monitorInfo($monitor,x1)
    set y1 $monitorInfo($monitor,y1)
    set x2 $monitorInfo($monitor,x2)
    set y2 $monitorInfo($monitor,y2)
    set mw $monitorInfo($monitor,width)
    set mh $monitorInfo($monitor,height)
    if {$settings(layoutOneRowCol)} {
        # another special case for 3, 4 and 5 and more
        #    BBB
        #    BBB
        #    BBB
        #    sss
        set c [expr {$numWindows-1}]
        # if aspect ratio is ok to be wider or equal to screen's
        if {$aspectRatio==0 || $aspectRatio>=1.0*$mw/$mh} {
            # very wide, row below
            set bw $mw
            set bh [expr {1.0*$mh*$c/($c+1)}]
            Debug "Wide ar $aspectRatio vs screen [expr 1.0*$mw/$mh]: using full width,c $c height $bh"
        } else {
            # aspect ratio is set, row to the side
            set bh $mh
            set bw [expr {1.0*$mw*$c/($c+1)}]
            Debug "Not ultra wide: Using full height,c $c width $bw"
        }
    } else {
        set bw [expr {1.0*$mw*$c/($c+1)}]
        set bh [expr {1.0*$mh*$c/($c+1)}]
    }
    # bh/bw will be int after aspect ratio and multiple of small pass
    Debug "monitor $mw x $mh -> $bw x $bh"
    lassign [ConstrainWindow 0 0 $bw $bh $aspectRatio] v1 v2 bw bh
    # Make sure big size is divisable by sw exactly
    set sw [expr {int($bw/$c)}]
    set sh [expr {int($bh/$c)}]
    set bw [expr {int($sw*$c)}]
    set bh [expr {int($sh*$c)}]
    Debug "Using $bw x $bh for big window"
    set xw1 [expr {$x1+$bw}]
    set yy1 $y1
    if {$settings(layoutTop)} {
        set yy1 [expr {$y1+$sh}]
    }
    SetWindowOnCanvas $startAt $x1 $yy1 $xw1 [expr {$yy1+$bh}]
    incr numWindows -1
    incr startAt 1
    set savedStart $startAt
    set lastWin [expr ($startAt+$numWindows)]
    if {$settings(layoutTop) && !$settings(layoutOneRowCol) && $numWindows>$c} {
        set startAt [expr round($startAt+$c+$numWindows%2)]
        if {$startAt+$c>$lastWin} {
            set startAt [expr round($lastWin-$c)]
        }
        Debug "C is $c : changed startAt to $startAt, last win $lastWin"
    }
    set xw2 [expr {$xw1+$sw}]
    for {set i 0} {$xw2<=$x2 && $i<$c} {incr i 1} {
        set yw1 [expr {$yy1+$i*$sh}]
        set yw2 [expr {$yw1+$sh}]
        SetWindowOnCanvas $startAt $xw1 $yw1 $xw2 $yw2
        incr startAt 1
        incr numWindows -1
    }
    if {$settings(layoutTop)} {
        set yw1 $y1
        if {!$settings(layoutOneRowCol)} {
            set startAt $savedStart
            Debug "Restore startAt to $savedStart"
        }
    } else {
        set yw1 [expr {$y1+$bh}]
    }
    set yw2 [expr {$yw1+$sh}]
    set xw1 $x1
    for {} {$numWindows>0} {incr numWindows -1} {
        set xw2 [expr {$xw1+$sw}]
        SetWindowOnCanvas $startAt $xw1 $yw1 $xw2 $yw2
        set xw1 $xw2
        incr startAt 1
    }
}

proc UpdateLayoutInfo {tag} {
    global layoutinfo sot
    lassign [SizeOfWindow $tag] x1 y1 w h
    regsub {^wow} $tag {} id
    set x ""
    if {$sot($id)} {
        set x ", On top"
    }
    set layoutinfo "OMB $id: Top Left ($x1 , $y1) Size $w x $h$x"
}

# -- move/resize windows in layout
proc SetupMove {} {
    set c .layout.c
    $c bind wowText <Button-1> {
        set selectedWindow [%W find withtag current]
        set allTags [%W gettags $selectedWindow]
        set selectedTag [lindex $allTags 0]
        regsub {^wow} $selectedTag {} id
        # toggle pin
        set sot($id) [expr {1-$sot($id)}]
        lassign [SizeOfWindow $selectedTag] x1 y1 w h
        UpdateWindowText $selectedTag $w $h
    }
    $c bind wowWindow||wowText||wowResize <ButtonPress-1> {
        set selectedWindow [%W find withtag current]
        set allTags [%W gettags $selectedWindow]
        set selectedTag [lindex $allTags 0]
        lassign [SizeOfWindow $selectedTag] x1 y1 w h
        UpdateLayoutInfo $selectedTag
        set dragMode move
        if {[lsearch -exact $allTags wowResize]!=-1} {
            set dragMode resize
        }
        Debug "Clicked on %W $selectedWindow : $allTags : $selectedTag"
        set atx %x
        set aty %y
    }
    $c bind wowWindow <ButtonRelease-1> {
        set snap $settings(layoutSnap)
        Debug "Released: $snap"
        if {$snap >= 2} {
            lassign [%W coords $selectedRectWindow] x1 y1 x2 y2
            set nx1 [expr {$snap*round(1.0*$x1/$snap)}]
            set ny1 [expr {$snap*round(1.0*$y1/$snap)}]
            Debug "snap to $nx1 $ny1 (from $x1 $y1)"
            %W move $selectedTag [expr {$nx1-$x1}] [expr {$ny1-$y1}]
            UpdateLayoutInfo $selectedTag
        }
    }
    $c bind wowWindow <B1-Motion> {
        set changed_x [expr %x - $atx]
        set changed_y [expr %y - $aty]
        Debug "moving $selectedWindow $changed_x $changed_y"
        %W move $selectedTag $changed_x $changed_y
        set atx %x
        set aty %y
        set settings(layoutAuto) 0
        UpdateLayoutInfo $selectedTag
    }
    $c bind wowResize <B1-Motion> {
        global layoutinfo
        set changed_x [expr %x - $atx]
        set changed_y [expr %y - $aty]
        # resize
        Debug "Resizing $selectedWindow $changed_x $changed_y $aspectRatio"
        set selectedRectWindow [%W find withtag "$selectedTag&&wowWindow"]
        lassign [%W coords $selectedRectWindow] x1 y1 x2 y2
        set w [expr {$x2-$x1}]
        set h [expr {$y2-$y1}]
        set nw [expr {$w+$changed_x}]
        if {$nw < 356*$scale} {
            set nw [expr {356*$scale}]
        }
        set nh [expr {$h+$changed_y}]
        if {$nh < 200*$scale} {
            set nh [expr {200*$scale}]
        }
        lassign [ConstrainWindow 0 0 [expr {$nw/$scale}] [expr {$nh/$scale}] $aspectRatio] v1 v2 w h
        Debug "Resize $selectedTag : $selectedWindow : $selectedRectWindow | $x1 , $y1 ; $w x $h"
        set nx2 [expr {$x1+$w*$scale}]
        set ny2 [expr {$y1+$h*$scale}]
        set atx [expr {$atx+$nx2-$x2}]
        set aty [expr {$aty+$ny2-$y2}]
        %W coords $selectedRectWindow $x1 $y1 $nx2 $ny2
        %W coords $selectedTag&&wowR1 [expr {$nx2-18}] [expr {$ny2-18}] [expr {$nx2-2}] [expr {$ny2-2}]
        %W coords $selectedTag&&wowR2 [expr {$nx2-14}] [expr {$ny2-14}] [expr {$nx2-2}] [expr {$ny2-2}]
        lassign [SizeOfWindow $selectedTag] x1 y1 w h
        set settings(layoutAuto) 0
        UpdateWindowText $selectedTag $w $h
        UpdateLayoutInfo $selectedTag
    }
    global lastResize
    set lastResize ""
    $c bind wowWindow||wowText||wowResize <Enter> {
        set selectedWindow [%W find withtag current]
        set selectedTag [lindex [%W gettags $selectedWindow] 0]
        Debug "Entered %W $selectedWindow $selectedTag - last $lastResize"
        if {$lastResize != $selectedTag} {
            %W delete wowResize
            set lastResize $selectedTag
            set layoutinfo ""
            set selectedRectWindow [%W find withtag "$selectedTag&&wowWindow"]
            lassign [%W coords $selectedTag] x1 y1 x2 y2
            Debug "coords for small resize $x2 $y2"
            set x2 [expr {round($x2)}]
            set y2 [expr {round($y2)}]
            %W create rectangle [expr {$x2-18}] [expr {$y2-18}] [expr {$x2-2}] [expr {$y2-2}] -fill orange -tags [list  $selectedTag "wowAll" "wowResize" "wowR1"]
            %W create rectangle [expr {$x2-14}] [expr {$y2-14}] [expr {$x2-2}] [expr {$y2-2}] -fill darkorange -tags [list  $selectedTag "wowAll" "wowResize" "wowR2"]
        }
        UpdateLayoutInfo $selectedTag
    }
    $c bind display <Enter> {
        set layoutinfo ""
        set selectedTag ""
        if {$lastResize != ""} {
            set lastResize ""
            %W delete wowResize
        }
    }
    bind $c <Enter> {
        Debug "entering canvas %W"
        catch {focus %W}
    }
    bind $c <Leave> {
        set lastResize ""
        set selectedTag ""
        catch {%W delete wowResize}
        set layoutinfo ""
    }
    bind $c <Left> {
        Debug "Left for $selectedTag"
        if {$selectedTag != ""} {
            %W move $selectedTag -$scale 0
            UpdateLayoutInfo $selectedTag
        }
    }
    bind $c <Right> {
        Debug "Right for $selectedTag"
        if {$selectedTag != ""} {
            %W move $selectedTag $scale 0
            UpdateLayoutInfo $selectedTag
        }
    }
    bind $c <Up> {
        Debug "Up for $selectedTag"
        if {$selectedTag != ""} {
            %W move $selectedTag 0 -$scale
            UpdateLayoutInfo $selectedTag
        }
    }
    bind $c <Down> {
        Debug "Down for $selectedTag"
        if {$selectedTag != ""} {
            %W move $selectedTag 0 $scale
            UpdateLayoutInfo $selectedTag
        }
    }
    UpdateHandles
}


# --- Mouse follow focus and raise control

proc GetMouseDelay {} {
    twapi::get_system_parameters_info SPI_GETACTIVEWNDTRKTIMEOUT
}

proc SetMouseDelay {v} {
    twapi::set_system_parameters_info SPI_SETACTIVEWNDTRKTIMEOUT $v
}

proc GetFocusFollowMouse {} {
    twapi::get_system_parameters_info SPI_GETACTIVEWINDOWTRACKING
}

proc SetFocusFollowMouse {v} {
    twapi::set_system_parameters_info SPI_SETACTIVEWINDOWTRACKING $v
}

proc GetMouseRaise {} {
    twapi::get_system_parameters_info SPI_GETACTIVEWNDTRKZORDER
}

proc SetMouseRaise {v} {
    twapi::set_system_parameters_info SPI_SETACTIVEWNDTRKZORDER $v
}

# -- sync with widget values

proc AddMouseToRRLabel {} {
    global settings mouseBroadcast rrOnLabel
    set left [lindex [split $rrOnLabel \n] 0]
    if {$mouseBroadcast} {
        set rrOnLabel "$left\n$settings(mfIndicator,label)"
    } else {
        set rrOnLabel "$left"
    }
}

proc UpdateMouseFollow {} {
    global mouseFollow settings
    Debug "UpdateMouseFollow $mouseFollow $settings(mouseDelay)"
    SetFocusFollowMouse $mouseFollow
    if {$mouseFollow} {
        SetMouseDelay $settings(mouseDelay)
    }
}

proc UpdateMouseRaise {} {
    global mouseRaise
    SetMouseRaise $mouseRaise
}

proc UpdateMouseDelay {} {
    global mouseDelay
    SetMouseDelay $mouseDelay
}

#---- settings and initial setup

# default hotkeys (change/add more in you OpenMultiBoxingSettings.tcl)
for {set i 1} {$i<=10} {incr i} {
    set settings(hk$i,focus) "Ctrl-F$i"
    set settings(hk$i,swap) "Ctrl-Shift-F$i"
}

array set settings {
    hk,capture "Ctrl-Shift-C"
    hk,mouseTrack "Ctrl-Shift-M"
    hk,focusNextWindow "Ctrl-Shift-N"
    hk,focusPreviousWindow "Ctrl-Shift-P"
    hk,swapPreviousWindow "Ctrl-Shift-0xC0"
    hk,swapNextWindow "Ctrl-0xC0"
    hk,focusFollowMouse "Ctrl-Shift-F"
    hk,stayOnTopToggle "Ctrl-Shift-T"
    hk,overlayToggle "Ctrl-Shift-O"
    DEBUG 0
    focusAlsoFG 1
    swapAlsoFocus 1
    numWindows 0
    aspectRatio "Any"
    ignoreMonitorIdx 0
    avoidTaskbar 1
    layoutOneSize 1
    layoutOneRowCol 0
    layoutStacked 0
    layoutScale "1/6"
    layoutSnap 4
    layoutMaxWindows 32
    layoutAuto 1
    layoutTop 0
    showOverlay 1
    overlayFocusColor "#ff0080"
    overlayAlpha 0.7
    overlayAnchor n
    overlayShowBorder 1
    overlayClickable 1
    overlayAllClickable 0
    overlayFontSize1 48
    overlayFontSize2 48
    game "World of Warcraft"
    games {"World of Warcraft" "Overwatch" "EVE" "Star Wars\u2122: The Old Republic\u2122"}
    captureForegroundWindow 0
    lastUpdateChecked 0
    profile "Default"
    profiles {"Default"}
    borderless 1
    rrKeyListExclude "W A S D"
    rrModExcludeList "RCONTROL RSHIFT RALT"
    rrInterval 5
    rrAlwaysFocus 1
    autoResetFocusToMain 1
    autoResetDirect 0
    hk,rrToggle "Ctrl-Shift-R"
    hk,focusMain "Ctrl-Shift-W"
    hk,resetAll "Ctrl-Shift-Alt-R"
    rrIndicator,x 0.5
    rrIndicator,y 0.7
    rrIndicator,label ⟳
    mfIndicator,label 🐭
    autoKillName "WowVoiceProxy.exe"
    autoKillOn 1
    mouseDelay 0
    mouseFocusOffAtExit 1
    mouseFocusOnAtStart 0
    mouseWatchInterval 50
    mouseOutsideWindowsPauses 1
    autoCapture 1
    clipboardAtStart 0
    dontCaptureList {explorer.exe SndVol.exe}
    hk,mouseBroadcast "Ctrl-M"
    mouseBroadcastDelay 30
}
#   rrKeyListAll ". F B T I \[ \] SPACE 1 2 3 4 5 6 7 8 9 0 - = UP LEFT RIGHT DOWN"
#   rrKeyListCustom ". [ ] F11"
#   rrKeyListDirect ".m .1 .2 .3 ..."
#   rrCustomExcludeList 0

set settings(mouseInsideGameWindowFocuses) [expr {$hasRR||$hasBR}]


# globals
FindOtherCopy
if {![info exists pos]} {
    # position of the next move window
    set pos "0 0"
    # size to set
    set windowSize "1920 1080"
    # stay on top
    set stayOnTop 0
    # "next" window/slot #, start from slot 1
    set nextWindow 1
    # max ever set in list box
    set maxNumW 1
    # currently focused windows for normal rotation
    set focusWindow 1
    # custom rotation focused window
    set customWindow 1
    # Actual last focused window (at least as far as OMB is concerned)
    set lastFocusWindow 1
    # last swapped window
    set swappedWindow 1
    # hotkey ok
    set hotkeyOk 1
    # mouse click broadcasting
    set mouseBroadcast 0
}

if {![info exists lastFocusWindow]} {
    set lastFocusWindow $focusWindow
}

LoadSettings
if {[info exists initProfile]} {
    Debug "Loading cmd line initProfile $initProfile"
    set settings(profile) $initProfile
    unset initProfile
    LoadProfile
}


# -- get/save sequence
trace add variable nextWindow write updateIndex

# wip for layouts
#Debug "desktop workarea [twapi::get_desktop_workarea]"
#Debug "display monitors [twapi::get_display_monitors -activeonly]"
#Debug "display info [twapi::get_multiple_display_monitor_info]"

MenuSetup

# Make it so the code can be reloaded without errors
if {![winfo exists .logo]} {
    font create WOBBold {*}[font actual [::ttk::style lookup TButton -font]]
    font configure WOBBold -weight bold
    UISetup
    set mouseTrackOn ""
    updateIndex
    # Save settings once
    SaveSettings
}

# --- main / tweak me ---
puts "OpenMultiBoxing $vers started..."
Defer 100 FindExisting
set bottomText "OpenMultiBoxing $vers"
wm state . normal
if {[info exists settings(mainWindowGeometry)]} {
    catch {wm geometry . $settings(mainWindowGeometry)}
}
bind . <Configure> {set settings(mainWindowGeometry) [wm geometry .]}

Defer 150 {raise .}
if {$settings(numWindows)==0} {
    Debug "No layout setup, opening layout"
    Defer 250 {.bwl invoke}
}

if {$isUpdate} {
    # Do update stuff
    Debug "Update detected ($oldVersion to $previousVersion to $vers)"
    set isUpdate 0
    set mouseBroadcast 0
} else {
    if {[expr {([clock seconds]-$settings(lastUpdateChecked))>2*24*3600}]} {
        Debug "Last update check $settings(lastUpdateChecked) - checking for updates in 1s"
        Defer 1000 {CheckForUpdates 1}
    }
}

# startup auto mouse ove
if {$settings(mouseFocusOnAtStart)} {
    set mouseFollow 1
    UpdateMouseFollow
}
if {$settings(clipboardAtStart)} {
    Defer 200 ClipboardManager
}
# Mouse tracking/auto pause and auto capture
Defer 350 PeriodicChecks

# For now not using cffi as it doesn't read full keyboard state anyway
#Defer 300 CheckBinary
