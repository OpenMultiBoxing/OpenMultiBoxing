#  WowOpenBox / OpenMultiboxing by MooreaTV <moorea@ymail.com> (c) 2020-2026 All rights reserved
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

proc Connect {} {
    global settings connectTo
    set t .connect
    set connectTo $settings(connectTo)
    EnableDisableWindows 0
    toplevel $t
    wm resizable $t 0 0
    wm title $t "OMB Connect..."
    ttk::label  $t.l -text "Connect to another OMB:"
    ttk::entry  $t.e -textvar connectTo
    $t.e selection range 0 end
    bind $t.e <Return> {set doneDialog 1}
    ttk::button $t.ok -text OK -command {set doneDialog 1}
    ttk::button $t.cancel -text Cancel -command "set connectTo {}; set doneDialog 1"
    bind $t.e <Escape> "$t.cancel invoke"
    grid $t.l - -sticky news -padx 4 -pady 4
    grid $t.e - -sticky news -padx 4 -pady 4
    grid $t.ok $t.cancel -padx 4 -pady 4
    focus $t.e
    UpdateHandles
    vwait doneDialog
    destroy $t
    EnableDisableWindows 1
    if {$connectTo!=""} {
        Debug "Connect dialog returned $connectTo"
        set settings(connectTo) $connectTo
        ConnectTo $connectTo
    } else {
        Debug "Connect cancelled"
    }
}

proc ConnectTo {destination} {
    global master masterHost settings
    if {[info exists master]} {
        Debug "Closing master socket $master"
        close $master
        unset master
    }
    set masterHost $destination
    if {[catch {set master [socket $destination $settings(listenPort)]} err]} {
        UpdateNetStatus
        OmbError "Connect error" "Couldn't connect to $destination:\n$err"
        return
    }
    fconfigure $master -blocking 0 -translation binary -encoding binary
    fileevent $master readable [list Master $master]
    Debug "Connected to $destination $master"
    UpdateNetStatus
}

# Network status line in the main window: pause checkbox when connected to a main OMB,
# otherwise a label (both in the same cell so the window height doesn't change)
proc UpdateNetStatus {} {
    global master masterHost socket clients settings
    if {![winfo exists .net]} {
        return
    }
    set remotes ""
    if {[info exists socket]} {
        set n 0
        if {[info exists clients]} {
            set n [llength $clients]
        }
        set remotes "Listening on $settings(listenPort): $n remote[expr {$n==1 ? "" : "s"}]"
    }
    if {[info exists master]} {
        set txt "Pause input from $masterHost"
        if {$remotes!=""} {
            append txt " ($remotes)"
        }
        .net.cb configure -text $txt
        grid remove .net.l
        grid .net.cb
        return
    }
    if {$remotes!=""} {
        set txt $remotes
    } elseif {[info exists masterHost]} {
        set txt "Not connected to $masterHost"
    } else {
        set txt "No remote connection"
    }
    .net.l configure -text $txt
    grid remove .net.cb
    grid .net.l
}

set networkPause 0

# {x1 y1 x2 y2} of the primary monitor (first one if none is flagged primary)
proc PrimaryMonitorExtent {} {
    set monitors [twapi::get_multiple_display_monitor_info]
    foreach monitor $monitors {
        if {[dict get $monitor -primary]} {
            return [dict get $monitor -extent]
        }
    }
    return [dict get [lindex $monitors 0] -extent]
}

proc Master {s} {
    global master slot2handle settings networkPause
    set l [gets $s data]
    if {$l <= 0} {
        if {[eof $s]} {
            Debug "Master socket $s closed"
            close $s
            unset master
            UpdateNetStatus
            OmbError "No connection" "Lost/Rejected connection to master OMB"
        }
        Debug "Master empty read"
        return
    }
    Debug "Master socket $s pause $networkPause got data: $data"
    if {$networkPause} {
        return
    }
    lassign $data cmd code
    # No captured window: full screen mode (global input), otherwise input goes to the windows
    set fullScreen [expr {[array size slot2handle]==0}]
    switch $cmd {
        "MOUSE" {
            set x $code
            set y [lindex $data 2]
            # empty button == move only
            set button [lindex $data 3]
            Debug "Master socket $s clicked $x $y $button"
            if {!$fullScreen} {
                set skip [RRExcludedWindows]
                set targets {}
                for {set i 1} {$i<=$settings(numWindows)} {incr i} {
                    if {[info exists slot2handle($i)] && [lsearch -exact $skip $i] < 0} {
                        lappend targets $i
                    }
                }
                # the mouse can only be in one place: moves only apply with a single target window
                if {$button=="" && [llength $targets]!=1} {
                    return
                }
                foreach i $targets {
                    CheckWindow [list ClickWindowRel $i $x $y $button] $i
                }
            } else {
                # scale to the primary monitor (monitorInfo is only set once Window Layout was opened)
                lassign [PrimaryMonitorExtent] lx ly x2 y2
                set lw [expr {$x2-$lx}]
                set lh [expr {$y2-$ly}]
                set xx [expr {round($lx+$x*$lw)}]
                set yy [expr {round($ly+$y*$lh)}]
                Debug "Will click '$button' at $xx $yy on primary monitor (${lw}x${lh}@$lx,$ly)"
                twapi::move_mouse $xx $yy
                if {$button!=""} {
                    twapi::click_mouse_button $button
                }
            }
        }
        "UP" {
            if {$fullScreen} {
                twapi::send_input [list [list "keyup" $code 0]]
            } else {
                BroadcastKeyToOther -1 $code 1
            }
        }
        "DOWN" {
            if {$fullScreen} {
                twapi::send_input [list [list "keydown" $code 0]]
            } else {
                BroadcastKeyToOther -1 $code 0
            }
        }
        default {
            Debug "Master socket $s unknown command $cmd"
            close $master
            unset master
            UpdateNetStatus
            OmbError "Unknown command" "Master socket $s unknown command $data"
        }
    }
}

proc SendToClients {data} {
    global clients
    foreach client $clients {
        if {[catch {puts -nonewline $client $data;flush $client} err]} {
            set peer [fconfigure $client -peername]
            close $client
            set clients [lsearch -exact -not -inline $clients $client]
            UpdateNetStatus
            OmbError "Error sending to client" "Error sending to client $peer\n$err\n\n[llength $clients] client(s) remaining."
        }
    }
}

# Remotes don't send anything: readable means they disconnected
proc ClientEvent {client} {
    global clients
    if {[catch {read $client}] || [eof $client]} {
        Debug "Client socket $client closed"
        close $client
        set clients [lsearch -exact -not -inline $clients $client]
        UpdateNetStatus
    }
}

proc CloseSocket {} {
    global socket
    if {[info exists socket]} {
        Debug "Closing listening socket $socket"
        close $socket
        unset socket
    }
}

proc NetworkSetup {} {
    global settings socket clients
    if {![info exists clients]} {
        set clients {}
    }
    CloseSocket
    if {!$settings(listen)} {
        foreach client $clients {
            Debug "Closing client socket $client"
            close $client
        }
        set clients {}
        UpdateNetStatus
        return
    }
    # (re)attach after a code update, clients accepted by an older version had no handler
    foreach client $clients {
        fileevent $client readable [list ClientEvent $client]
    }
    set port $settings(listenPort)
    if {[catch {set socket [socket -server NewConnection $port]} err]} {
        UpdateNetStatus
        OmbError "Listen error" "Couldn't listen on port $port:\n$err"
        return
    }
    UpdateNetStatus
}

proc NewConnection {channel clientaddr clientport} {
    global settings clients
    if {[OmbMessage -type yesno -icon question -title "Accept connection?" \
            -message "Connection from $clientaddr ($clientport)\n\nDo you want to accept it?"]=="no"} {
        Debug "Closing connection $channel from $clientaddr ($clientport)"
        close $channel
        return
    }
    fconfigure $channel -blocking 0 -translation binary -encoding binary
    fileevent $channel readable [list ClientEvent $channel]
    lappend clients $channel
    Debug "Added connection $channel from $clientaddr ($clientport) to clients list: $clients"
    UpdateNetStatus
}

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

# Adds and selects a new game window title (or * pattern)
proc AddGame {title} {
    global settings
    if {[lsearch -exact $settings(games) $title]==-1} {
        Debug "New game $title"
        # game entries come first in the menu, before the separator
        .mbar.game insert [llength $settings(games)] radiobutton -label $title -value $title -variable settings(game)
        lappend settings(games) $title
        set settings(game) $title
    }
}

proc UpdateGameMatches {args} {
    global gameTitle gameMatches
    if {$gameTitle==""} {
        set gameMatches ""
        return
    }
    set titles {}
    foreach w [GameFindWindows $gameTitle] {
        if {[IsOurs $w] || [catch {twapi::get_window_text $w} t]} {
            continue
        }
        lappend titles $t
    }
    set n [llength $titles]
    if {$n==0} {
        set gameMatches "No window currently matches"
        return
    }
    set gameMatches "Currently matches $n window(s):"
    foreach t [lrange $titles 0 2] {
        append gameMatches "\n    $t"
    }
    if {$n>3} {
        append gameMatches "\n    ..."
    }
}

proc AddGameDialog {} {
    global settings gameTitle gameMatches
    set t .addGame
    set gameTitle $settings(game)
    EnableDisableWindows 0
    toplevel $t
    wm resizable $t 0 0
    wm title $t "OMB Add Game Window Title..."
    ttk::label  $t.l -text "Game window title to find and capture:"
    ttk::entry  $t.e -textvar gameTitle -width 50
    ttk::label  $t.h -text "Exact title, use * to match any text\ne.g. \"Game version:*\" matches \"Game version:1.2.3\" and \"Game version:1.2.4\""
    ttk::label  $t.m -textvar gameMatches -justify left
    bind $t.e <Return> {set doneDialog 1}
    ttk::button $t.ok -text OK -command {set doneDialog 1}
    ttk::button $t.cancel -text Cancel -command "set gameTitle {}; set doneDialog 1"
    bind $t.e <Escape> "$t.cancel invoke"
    grid $t.l - -sticky nws -padx 4 -pady 4
    grid $t.e - -sticky news -padx 4 -pady 4
    grid $t.h - -sticky nws -padx 4 -pady 4
    grid $t.m - -sticky nws -padx 4 -pady 4
    grid $t.ok $t.cancel -padx 4 -pady 4
    UpdateGameMatches
    trace add variable gameTitle write UpdateGameMatches
    focus $t.e
    $t.e selection range 0 end
    UpdateHandles
    vwait doneDialog
    trace remove variable gameTitle write UpdateGameMatches
    destroy $t
    EnableDisableWindows 1
    set title [string trim $gameTitle]
    if {$title!=""} {
        Debug "Add game dialog returned $title"
        AddGame $title
        set settings(game) $title
        SaveSettings
    } else {
        Debug "Add game cancelled"
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
            UpdateProfilesMenu
        }
        set pMode 1
        set pf [ProfileFileName $p]
        set f [open $pf w+]
        fconfigure $f -encoding utf-8
        puts $f "array set settings {"
        foreach i [lsort [array names settings]] {
            if {$i=="profile" || $i=="profiles" || $i=="games" || $i=="lastUpdateChecked" || $i=="profilesNotRotated"} {
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
    global settings layoutMirrored
    set profile $settings(profile)
    set pf [ProfileFileName $profile]
    # profiles saved before mirrors existed don't have them: none rather than the previous profile's
    set prev [list mirrors $settings(mirrors) layoutMirrored $settings(layoutMirrored)]
    array set settings {mirrors {} layoutMirrored 0}
    if {[catch {source -encoding utf-8 $pf} err]} {
        array set settings $prev
        puts stderr "Error sourcing profile $pf\n$err"
        OmbError "OpenMultiBoxing profile error" \
            "Your $pf has an error: $err\nYou can remove it and use Refresh Profiles in the menu."
        set settings(profile) "Default"
        return
    }
    # Otherwise can be reset when switching from Profile N back to Default
    set settings(profile) $profile
    # the Window Layout checkbox, applied by its Save and Apply
    set layoutMirrored $settings(layoutMirrored)
    AfterSettings
    # before ResetAll: the previous profile's mirrors don't match the new settings(mirrors)
    # at startup that's done once the main window is shown (creating the mirrors would create it
    # hidden at the Windows default position, where it would go back when shown)
    if {[winfo exists .logo]} {
        MirrorsRebuild
    }
    ResetAll
}

# Profiles cycled through by the next/previous profile hotkeys
proc RotatedProfiles {} {
    global settings
    set l {}
    foreach p $settings(profiles) {
        if {[lsearch -exact $settings(profilesNotRotated) $p] == -1} {
            lappend l $p
        }
    }
    return $l
}

proc SwitchProfile {dir} {
    global settings
    set rot [RotatedProfiles]
    set n [llength $rot]
    if {$n == 0} {
        Debug "SwitchProfile: no profile in rotation"
        return
    }
    set i [lsearch -exact $rot $settings(profile)]
    if {$i == -1} {
        # current profile isn't in the rotation: go to its first (next) or last (previous) one
        set i [expr {$dir > 0 ? -1 : 0}]
    }
    set p [lindex $rot [expr {($i+$dir+$n)%$n}]]
    if {$p eq $settings(profile)} {
        Debug "SwitchProfile: $p is the only profile in rotation"
        return
    }
    Debug "Switching profile $settings(profile) -> $p"
    set settings(profile) $p
    LoadProfile
}

# Deferred as LoadProfile re-registers all hotkeys, including the one being handled
proc NextProfile {} {
    Defer 0 {SwitchProfile 1}
}

proc PreviousProfile {} {
    Defer 0 {SwitchProfile -1}
}

proc UpdateProfileRotation {} {
    global settings profileRotated
    set settings(profilesNotRotated) {}
    foreach p $settings(profiles) {
        if {!$profileRotated($p)} {
            lappend settings(profilesNotRotated) $p
        }
    }
    Debug "Profiles not rotated: $settings(profilesNotRotated)"
    SaveSettings
}

# Stays up (unlike a menu) so several profiles can be checked/unchecked
proc ProfileRotationDialog {} {
    global settings profileRotated
    set tw .profileRotation
    if {![winfo exists $tw]} {
        toplevel $tw
        wm title $tw "OMB Profiles in rotation"
        wm resizable $tw 0 0
        RememberGeometry $tw profileRotationGeometry
        grid [ttk::label $tw.l -text "Profiles cycled through by\n[HK nextProfile] (next) and [HK previousProfile] (previous):"] -padx 8 -pady 4 -sticky w
        grid [ttk::button $tw.close -text Close -command [list destroy $tw]] -row 2 -padx 8 -pady 6
        UpdateHandles
    }
    # (re)create the checkbuttons, the profiles list may have changed
    catch {destroy $tw.f}
    grid [ttk::frame $tw.f] -row 1 -padx 8 -sticky w
    array unset profileRotated
    set i 0
    foreach p $settings(profiles) {
        set profileRotated($p) [expr {[lsearch -exact $settings(profilesNotRotated) $p] == -1}]
        grid [ttk::checkbutton $tw.f.cb[incr i] -text $p -variable profileRotated($p) -command UpdateProfileRotation] -sticky w
    }
    wm state $tw normal
    raise $tw
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
    global allHotKeys hotkeyCombo hotkeyFailed
    Debug "Unregistering previous hotkeys"
    foreach hk $allHotKeys {
        twapi::unregister_hotkey $hk
    }
    set allHotKeys {}
    array unset hotkeyCombo *
    array unset hotkeyFailed *
}


proc IsInside {x y x1 y1 x2 y2} {
    expr {$x>=$x1 && $x<=$x2 && $y>=$y1 && $y<=$y2}
}

# Whether the top left corner of a saved WxH+X+Y geometry is on one of the current monitors
# (the monitors may have changed since; that's enough to drag it back, and some like them barely visible)
proc GeometryOnScreen {g} {
    if {![regexp {\+(-?\d+)\+(-?\d+)$} $g -> x y]} {
        return 0
    }
    foreach monitor [MonitorsInfo] {
        lassign [dict get $monitor -extent] x1 y1 x2 y2
        if {[IsInside $x $y $x1 $y1 $x2 $y2]} {
            return 1
        }
    }
    Debug "Saved geometry $g is off screen"
    return 0
}

# Puts toplevel tw back where it was (settings(key), with its size if withSize) unless that's off screen,
# and keeps settings(key) up to date. Returns 1 if restored
proc RememberGeometry {tw key {withSize 0}} {
    global settings
    set restored 0
    if {[info exists settings($key)] && [GeometryOnScreen $settings($key)]} {
        set g $settings($key)
        if {!$withSize} {
            regexp {[+-]-?\d+[+-]-?\d+$} $g g
        }
        set restored [expr {![catch {wm geometry $tw $g}]}]
    }
    bind $tw <Configure> [list RecordGeometry $tw $key %W]
    return $restored
}

proc RecordGeometry {tw key w} {
    global settings
    # also called for the widgets inside
    if {$w eq $tw} {
        set settings($key) [wm geometry $tw]
    }
}

proc AfterSettings {} {
    global settings maxNumW slot2handle
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
    # Removed custom rotation / direct focus keys settings
    foreach k {autoResetDirect rrKeyListCustom rrKeyListDirect rrCustomExcludeList} {
        unset -nocomplain settings($k)
    }
    RegisterAllHotkeys
    # Set mouse control to current values
    global mouseFollow mouseRaise mouseDelay
    set mouseFollow [GetFocusFollowMouse]
    # Delay to restore when turning focus follow mouse off: don't capture our own
    # settings(mouseDelay) as the user's (on reload or when left on by a previous run)
    set curDelay [GetMouseDelay]
    if {!$mouseFollow || (![info exists mouseDelay] && $curDelay != $settings(mouseDelay))} {
        set mouseDelay $curDelay
    }
    set mouseRaise [GetMouseRaise]
    LoadLayout
    Overlay
    RRExcludeUpdate
    Debug "Settings (re)Loaded."
}

proc RegisterAllHotkeys {} {
    global settings maxNumW slot2handle hotkeyList
    UnregisterHotkeys
    foreach {var msg callback} $hotkeyList {
        # Only take that hotkey from other apps when windows to skip are configured
        if {$var eq "hk,rrExcludeToggle" && ![llength $settings(rrExcludeWindows)]} {
            continue
        }
        RegisterHotkey $msg $var $callback
    }
    for {set n 1} {$n < $maxNumW} {incr n} {
        if {[info exists slot2handle($n)]} {
            RegisterPerWindowHotkey $n "OMB $n"
        }
    }
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
    catch UnstackWindows
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
        grid [ttk::label .logo -text $txt] -row 0 -column 0 -rowspan 3
    } else {
        grid [ttk::label .logo] -row 0 -column 0 -rowspan 3 -pady 6 -padx 12
        .logo configure -image $imgOMB70
        wm iconphoto . -default $imgOMB70
    }
    set labelW 18
    grid [ttk::button .bH -text "Help" -width $labelW -command Help]  -row 0 -column 1 -padx 4
    tooltip .bH "Opens online help page"
    grid [ttk::button .bwl -text "Window Layout" -width $labelW -command WindowLayout] -row 1 -column 1
    tooltip .bwl "View or change the Window Layout"
    grid [ttk::button .b1  -text "Edit Settings" -width $labelW -command EditSettings] -row 2 -column 1
    tooltip .b1 "Opens the editor to edit raw settings\nand reload them after save.\nHotkeys are changed with File > Hotkeys..."
    # label width - enough to fit "-9999 -9999"
    set width 10
    grid [frame .sep1 -relief groove -borderwidth 2 -width 2 -height 2] -sticky ew -padx 4 -pady 4 -columnspan 2
    grid [ttk::label .l2 -text "Next window :" -anchor e] [entry .e1 -textvariable nextWindow -width $width] -padx 4 -sticky ew
    bind .e1 <FocusIn> [list focusIn %W]
    grid [ttk::label .l3 -text "Resize to" -anchor e] [entry .e2 -textvariable windowSize -width $width] -padx 4 -sticky ew
    grid [ttk::label .l4 -text "Move to" -anchor e] [entry .e3 -textvariable pos -width $width] -padx 4 -sticky ew
    grid [ttk::checkbutton .csop -text "Wow window always on top" -variable stayOnTop] -columnspan 2
    grid [ttk::button .b2 -text " Capture " -command CaptureOrUpdate] -pady 5 -columnspan 2
    grid [listbox .lbw -height 6] -columnspan 2 -sticky ns
    bind .lbw <<ListboxSelect>> [list selectChanged %W]
    grid [ttk::checkbutton .cbCaptureFG -text "Capture using foreground window" -command UpdateForegroundMode -variable settings(captureForegroundWindow)] -columnspan 2
    UpdateForegroundMode
    grid [ttk::checkbutton .cboverlay -text "Show overlay" -variable settings(showOverlay) -command "OverlayUpdate; SaveSettings"] [ttk::button .cbocfg -text "Overlay config" -command OverlayConfig]
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
        grid [ttk::checkbutton .cbRR -variable rrOn -command RRUpdate] -padx 4 -columnspan 2 -sticky w
        grid [ttk::label .lrrK -text "$RRlabel to other windows all but these keys:"] -padx 4 -columnspan 2 -sticky w
        grid [entry .eRR -textvariable settings(rrKeyListExclude) -width $width] -columnspan 2 -padx 4 -sticky ew
        bind .eRR <Return> RRKeysListChange
        tooltip .eRR "Which keys are excluded from $rrlabel for all windows\nHit <Return> after change to take effect.\nSee help/FAQ for list."
        grid [ttk::label .lrrK2 -text "No $RRlabel when:"] -padx 4 -columnspan 2 -sticky w
        grid [entry .eRR2 -textvariable settings(rrModExcludeList) -width $width] -columnspan 2 -padx 4 -sticky ew
        tooltip .eRR2 "Which modifiers pause $rrlabel while held\nHit <Return> after change to take effect.\nSee help/FAQ for list."
        bind .eRR2 <Return> RRKeysListChange

        grid [ttk::label .lBMap -text "Key remapping (: separated list)"] -padx 4 -columnspan 2 -sticky w
        grid [entry .eBMap -textvariable settings(broadcastMap) -width $width] -columnspan 2 -padx 4 -sticky ew
        tooltip .eBMap "Key mapping from key pressed to key broadcast\nFor instance F:T will send T to other windows when F is pressed"
        bind .eBMap <Return> RRKeysListChange

        frame .rrX
        ttk::checkbutton .rrX.cb -variable settings(rrExcludeWindowsOn) -command "RRExcludeUpdate; SaveSettings"
        ttk::menubutton .rrX.mb -textvariable rrExcludeText -menu .rrX.mb.menu
        menu .rrX.mb.menu -tearoff 0 -postcommand RRExcludeMenu
        tooltip .rrX.mb "Select which window(s) don't get $rrlabel keys and mouse clicks\nThis follows the window (OMB number) when swapped"
        pack .rrX.cb -side left
        pack .rrX.mb -side left -fill x -expand 1 -padx {4 0}
        grid .rrX -padx 4 -columnspan 2 -sticky ew
        RRExcludeUpdate
    }

    grid [frame .sep2 -relief groove -borderwidth 2 -width 2 -height 2] -sticky ew -padx 4 -pady 4 -columnspan 2
    grid [ttk::label .l6 -text "🖰 Mouse settings:" -font "*-*-bold" -anchor sw] -padx 4 -columnspan 2 -sticky w
    grid [ttk::checkbutton .mf -text "Focus follows mouse" -variable mouseFollow -command UpdateMouseFollow] -padx 4 -columnspan 2 -sticky w
    grid [ttk::checkbutton .mbc -text "Broadcast mouse clicks" -variable mouseBroadcast] -padx 4 -columnspan 2 -sticky w
    grid [frame .sep3 -relief groove -borderwidth 2 -width 2 -height 2] -sticky ew -padx 4 -pady 4 -columnspan 2
    frame .net
    # initial texts so the heights below are measured with text
    ttk::checkbutton .net.cb -text "Pause input" -variable networkPause
    tooltip .net.cb "When checked, network commands coming from the main OMB are ignored"
    ttk::label .net.l -text "No remote connection"
    tooltip .net.l "Network status\nUse File>Connect to... on remote OMBs\nand Options>Listen for other OMB connections on the main one"
    grid .net.cb -row 0 -column 0 -sticky w
    grid .net.l -row 0 -column 0 -sticky w
    grid rowconfigure .net 0 -minsize [expr {max([winfo reqheight .net.cb], [winfo reqheight .net.l])}]
    grid .net -padx 4 -columnspan 2 -sticky ew
    UpdateNetStatus
    grid [ttk::label .l_bottom -textvariable bottomText -justify center -anchor c] -padx 2 -columnspan 2
    bind .l_bottom <ButtonPress> [list CheckForUpdates 0]
    tooltip .l_bottom "Click to check for update from $vers"
    grid rowconfigure . 9 -weight 1
    grid columnconfigure . 1 -weight 1
    UpdateHotkeyTexts
}

# Hotkey for display, e.g. [HK capture]
proc HK {name} {
    global settings
    HotkeyDisplay $settings(hk,$name)
}

# Texts showing hotkeys, updated when they change
proc UpdateHotkeyTexts {} {
    global settings RRlabel rrlabel
    tooltip .csop "Whether that window should be on top of others.\nThis can be changed at anytime for the current focused window\nusing the Hotkey: [HK stayOnTopToggle]"
    tooltip .b2 "Capture or update window\nHotkey: [HK capture]"
    tooltip .cbCaptureFG "Instead of capturing the game window by name\n($settings(game))\nif checked, capture the current foreground window\nFor this to work you must use the hotkey:\n[HK capture]\n\nUse the Game menu to turn this on"
    tooltip .cboverlay "Show/Hide the overlay info\nHotkey: [HK overlayToggle]"
    if {[winfo exists .cbRR]} {
        .cbRR configure -text "$RRlabel ([HK rrToggle])"
        tooltip .cbRR "Toggle $rrlabel mode\nAlso turns off mouse focus and restore as needed while on\nHotkey: [HK rrToggle]"
        .rrX.cb configure -text "Skip ([HK rrExcludeToggle]):"
        tooltip .rrX.cb "When checked, keys and mouse clicks are not $rrlabel to the selected windows\nUnchecked: $rrlabel to all windows\nOnly available once windows are selected\nHotkey: [HK rrExcludeToggle]"
    }
    tooltip .mf "Toggle focus follow mouse mode\nHotkey: [HK focusFollowMouse]"
    tooltip .mbc "Toggle mouse click broadcasting\nHotkey: [HK mouseBroadcast]"
    if {[winfo exists .mbar.file]} {
        .mbar.file entryconfigure "Reset all windows*" -label "Reset all windows ([HK resetAll])"
        UpdateProfilesMenu
    }
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
"Open MultiBoxing (OMB) $vers\n$extra\n\nFree, OpenSource, Safe, Rules compliant, Multiboxing Software\n\nLicensed under GPLv3 - No Warranty\nThe GNU General Public License does not permit incorporating this work into proprietary programs.\n\nhttps://openmultiboxing.org https://wowopenbox.org/\n\uA9 2020-2026 MooreaTv <moorea@ymail.com>"

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
    RememberGeometry $tw clipGeometry 1
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
    $m2 add command -label "Next profile ([HK nextProfile])" -command NextProfile
    $m2 add command -label "Previous profile ([HK previousProfile])" -command PreviousProfile
    $m2 add command -label "Profiles in rotation..." -command ProfileRotationDialog
    $m2 add separator
    $m2 add command -label "Refresh Profiles" -command RefreshProfiles
    if {[winfo exists .profileRotation]} {
        ProfileRotationDialog
    }
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
    $m1 add command -label "Connect to..." -command Connect
    $m1 add separator
    $m1 add command -label "New Profile..." -command NewProfile
    $m1 add command -label "Hotkeys..." -command HotkeysDialog
    $m1 add command -label "Edit raw settings..." -command EditSettings
    $m1 add command -label "Save settings" -command SaveSettings
    $m1 add command -label "Reload settings" -command LoadSettings
    $m1 add separator
    $m1 add command -label "Clipboard copy/paster..." -command ClipboardManager
    $m1 add command -label "Mirrors..." -command MirrorsDialog
    $m1 add separator
    $m1 add command -label "Reset all windows ([HK resetAll])" -command ResetAll
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
    $mG add command -label "Add game window title..." -command AddGameDialog
    $mG add checkbutton -label "Add (capture focused window mode)" -variable settings(captureForegroundWindow) -command UpdateForegroundMode

    set m2 .mbar.profile
    menu $m2 -tearoff 0
    .mbar add cascade -label Profile -menu $m2
    UpdateProfilesMenu

    set m3 .mbar.options
    menu $m3 -tearoff 0
    .mbar add cascade -label Option -menu $m3
    $m3 add checkbutton -label "Auto Capture Game windows" -variable settings(autoCapture)
    $m3 add checkbutton -label "Capture makes windows borderless" -variable settings(borderless)
    $m3 add checkbutton -label "Mouse auto foreground window" -variable mouseRaise -command UpdateMouseRaise
    $m3 add checkbutton -label "Turn off focus follow mouse on exit" -variable settings(mouseFocusOffAtExit)
    $m3 add checkbutton -label "Turn on focus follow mouse at startup" -variable settings(mouseFocusOnAtStart)
    $m3 add checkbutton -label "Auto open clipboard at startup" -variable settings(clipboardAtStart) -command {if {$settings(clipboardAtStart)} ClipboardManager}
    $m3 add checkbutton -label "Listen for other OMB connections" -variable settings(listen) -command NetworkSetup
    $m3 add separator
    $m3 add checkbutton -label "Swap hotkey also focuses" -variable settings(swapAlsoFocus)
    $m3 add checkbutton -label "Focus hotkey also foregrounds" -variable settings(focusAlsoFG)
    $m3 add checkbutton -label "Auto Kill \"$settings(autoKillName)\"" -variable settings(autoKillOn)
    $m3 add separator
    $m3 add radiobutton -label "Auto reset focus to main: Off" -value 0 -variable settings(autoResetFocusToMain)
    $m3 add radiobutton -label "Auto reset focus to main: after 0.5 sec" -value 0.5 -variable settings(autoResetFocusToMain)
    $m3 add radiobutton -label "Auto reset focus to main: after 1 sec" -value 1 -variable settings(autoResetFocusToMain)
    $m3 add radiobutton -label "Auto reset focus to main: after 2 sec" -value 2 -variable settings(autoResetFocusToMain)
    $m3 add radiobutton -label "Auto reset focus to main: after 3 sec" -value 3 -variable settings(autoResetFocusToMain)
    $m3 add checkbutton -label "Always focus (if mixing clicks and focus hotkeys)" -variable settings(rrAlwaysFocus)
    $m3 add checkbutton -label "Key broadcast: send modifiers only with a key" -variable settings(rrDeferModifiers)
    $m3 add separator
    $m3 add checkbutton -label "Mouse broadcast: message mode" -variable settings(mouseBroadcastUsePostMessage)
    # to remote OMBs and to the windows stacked under main in the mirrored layout
    $m3 add checkbutton -label "Mouse broadcast: track movement" -variable settings(mouseBroadcastNetTrack)
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
    global mouseBroadcast mouseFollow settings
    set mouseBroadcast [expr {1-$mouseBroadcast}]
    if {$mouseBroadcast} {
        if {$mouseFollow && $settings(mouseBroadcastUsePostMessage)} {
            # Turn off mouse focus
            FocusFollowMouseToggle
        }
    } else {
        if {!$mouseFollow && $settings(mouseBroadcastUsePostMessage)} {
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
    RememberGeometry $tw mouseTrackingGeometry
    grid [ttk::button $tw.bml -width 14 -text "Track mouse" -command StartStopMouseTrack] [entry $tw.emt -textvariable mouseCoords -width 14] -padx 4 -sticky w
    tooltip $tw.bml "Start/Stop mouse tracking\nHotkey: [HK mouseTrack]"
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

# Mouse broadcast main function
proc ClickWindowRel {n xp yp button} {
    global settings slot2position slot2handle
    set WM_LBUTTONDOWN 0x0201
    set WM_LBUTTONUP 0x0202
    set wParam 1
    if {$button=="right"} {
        set WM_LBUTTONDOWN 0x0204
        set WM_LBUTTONUP 0x0205
        set wParam 2
    }
    # where the window really is (under main in the mirrored layout)
    set p [RealPosition $slot2position($n)]
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
    if {$button==""} {
        # move only (remote mouse tracking)
        return
    }
    set w $slot2handle($n)
    after $settings(mouseBroadcastDelay)
    if {$p != $slot2position($n)} {
        # under main in the mirrored layout: the cursor is over main, so it doesn't get the mouse move
        # and a real click would go to main
        set WM_MOUSEMOVE 0x0200
        twapi::PostMessage $w $WM_MOUSEMOVE 0 $lword
        twapi::PostMessage $w $WM_LBUTTONDOWN $wParam $lword
        twapi::PostMessage $w $WM_LBUTTONUP 0 $lword
    } elseif {$settings(mouseBroadcastUsePostMessage)} {
        twapi::PostMessage $w $WM_LBUTTONDOWN $wParam $lword
        twapi::PostMessage $w $WM_LBUTTONUP 0 $lword
    } else {
        twapi::click_mouse_button $button
    }
    after $settings(mouseBroadcastDelay)
}

# Mirrored layout: mouse moves over window n (main) also go to the windows stacked under it
proc MirroredMouseMove {n xp yp} {
    global settings slot2handle slot2position
    set WM_MOUSEMOVE 0x0200
    lassign $settings(1,size) lw lh
    set lword [expr {(round($yp*$lh)<<16)+round($xp*$lw)}]
    set skip [RRExcludedWindows]
    foreach {i wh} [array get slot2handle] {
        if {$i==$n || $i in $skip || ![info exists slot2position($i)]
                || [RealPosition $slot2position($i)] == $slot2position($i)} {
            continue
        }
        catch {twapi::PostMessage $wh $WM_MOUSEMOVE 0 $lword}
    }
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
set lastMouseCoords {}

proc MouseBroadcastCheck {} {
    global mouseBeforeClick clickInProgress settings slot2position slot2handle isPaused clickButton clickWhen lastMouseCoords
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
    if {$settings(mouseBroadcastNetTrack) && $lMouse!=$lastMouseCoords} {
        set lastMouseCoords $lMouse
        # No button == move
        lassign $lMouse x y
        # copy-pasta from below...
        # Find window
        set w [twapi::get_window_at_location $x $y]
        set wType [IsOurs $w]
        #Debug "Window clicked is $w: $wType"
        # slot can be gone while its window is closing
        if {$wType>=3 && [info exists slot2position([expr {$wType-2}])]} {
            set n [expr {$wType-2}]
            set p [RealPosition $slot2position($n)]
            # scale
            lassign $settings($p,posXY) lx ly
            lassign $settings($p,size) lw lh
            set xp [expr {1.0*($x-$lx)/$lw}]
            set yp [expr {1.0*($y-$ly)/$lh}]
            Debug "Move on $n in position $p is rel x $xp rel y $yp"
            SendToClients "MOUSE $xp $yp\n"
            if {[LayoutMirrored]} {
                MirroredMouseMove $n $xp $yp
            }
        }
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
        if {$elapsed > $settings(mouseHoldCancel)} {
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
        if {![info exists slot2position($n)]} {
            return
        }
        set p [RealPosition $slot2position($n)]
        # scale
        lassign $settings($p,posXY) lx ly
        lassign $settings($p,size) lw lh
        set xp [expr {1.0*($x-$lx)/$lw}]
        set yp [expr {1.0*($y-$ly)/$lh}]
        Debug "Clicked on $n in position $p is rel x $xp rel y $yp - $clickButton"
        # iterate move to other windows applying scale
        SendToClients "MOUSE $xp $yp $clickButton\n"
        set skip [RRExcludedWindows]
        for {set i 1} {$i<=$settings(numWindows)} {incr i} {
            if {$i==$n || [lsearch -exact $skip $i] >= 0} {
                continue
            }
            if {[info exists slot2handle($i)]} {
                CheckWindow [list ClickWindowRel $i $xp $yp $clickButton] $i
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
         maxNumW pauseSchedule lastFocusWindow slot2handle mouseBroadcast prevNP networkPause
    after cancel $pauseSchedule
    set pauseSchedule {}
    set freeSlot [FirstFreeSlot]
    if {$settings(autoCapture) && $freeSlot ne ""} {
        set w [FindGameWindow $freeSlot]
        if {$w != ""} {
            AutoCapture $w
        }
    }
    if {$mouseBroadcast} {
        MouseBroadcastCheck
    }
    CheckWindowsExist
    # Learn the focus window of captured windows as they get activated (see RefreshFocusHandle)
    if {![catch {twapi::get_foreground_window} fg] && $fg != ""} {
        set n [expr {[IsOurs $fg]-2}]
        if {$n > 0} {
            RefreshFocusHandle $n
        }
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
            set prevNP $networkPause
            if {!$networkPause} {
                set networkPause 1
            }
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
            Debug "Restoring $prevRR $prevMF $prevOL $prevRRMouse $prevNP"
            set networkPause $prevNP
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

# Every 200ms or so, notices closed game windows (e.g. so their mirrors go away)
set lastWindowsCheck 0
proc CheckWindowsExist {} {
    global slot2handle lastWindowsCheck
    set now [clock milliseconds]
    if {$now-$lastWindowsCheck < 200} {
        return
    }
    set lastWindowsCheck $now
    foreach {n wh} [array get slot2handle] {
        if {![twapi::window_exists $wh]} {
            Debug "OMB $n window is gone"
            WindowLost $n
        }
    }
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
    WindowLost $n
}

proc WindowLost {n} {
    global slot2handle slot2position
    if {[info exists slot2handle($n)]} {
        set w slot2handle($n)
        unset slot2handle($n)
        UpdateHandles
    }
    # main gone in the mirrored layout (would show whichever window was under it): window 1,
    # that was swapped into the lost window's position, goes back to main
    if {$n != 1 && [info exists slot2position($n)] && $slot2position($n) == 1 && [info exists slot2handle(1)]
            && [LayoutMirrored]} {
        Debug "Main OMB $n lost, back to OMB 1"
        SetAsMain 1
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
    global slot2handle slot2position settings savedWindowStyle origTitle forgottenSlot
    if {![info exists slot2handle($n)]} {
        Debug "Nothing to forget for $n"
        return
    }
    set wh $slot2handle($n)
    set forgottenSlot($wh) $n
    if {$n != 1 && [info exists slot2position($n)] && $slot2position($n) == 1 && [info exists slot2handle(1)]
            && [LayoutMirrored]} {
        # main in the mirrored layout (it would stay on top of the others): window 1 goes back to main first
        SetAsMain 1
    }
    if {[info exists origTitle($wh)]} {
        set title $origTitle($wh)
        unset origTitle($wh)
    } else {
        # captured before an OMB restart: original title unknown
        set title [string map {* ""} $settings(game)]
    }
    catch {Rename $wh $title}
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

# Exact title match unless the pattern contains *, which then matches any text
# (only * is special, other glob characters are escaped)
proc GameFindWindows {pattern} {
    if {[string first "*" $pattern]==-1} {
        return [twapi::find_windows -match string -text $pattern -visible true]
    }
    set glob [string map {\\ \\\\ ? \\? [ \\[ ] \\]} $pattern]
    return [twapi::find_windows -match glob -text $glob -visible true]
}

# freeSlot: for auto capture into that window number, skips forgotten windows unless it's lower
# than the one they were forgotten from (Forget OMB 3 with 1 lost: it becomes OMB 1)
proc FindGameWindow {{freeSlot ""}} {
    global settings forgottenSlot
    set wList [GameFindWindows $settings(game)]
    set minTime 0
    set minW ""
    foreach w $wList {
        # a wide pattern could match our own UI or already captured windows
        if {[IsOurs $w]} {
            continue
        }
        if {$freeSlot ne "" && [info exists forgottenSlot($w)] && $freeSlot >= $forgottenSlot($w)} {
            continue
        }
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
    if {[LayoutMirrored]} {
        # all at the main position: whichever was on top (main when we exited) goes under OMB 1
        StackUnderMain
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
    set pf [ProfileFileName $settings(profile)]
    # #36 use the editor registered for the file type if any, else notepad
    if {[catch {twapi::shell_execute -verb edit -path $pf -noui 1} err]} {
        Debug "No edit verb for $pf: $err"
        if {[catch {twapi::shell_execute -path notepad.exe -params $pf} err]} {
            Debug "Notepad failed for $pf: $err"
            clipboard clear
            clipboard append $pf
            OmbError "OpenMultiBoxing editor error" \
                "Unable to open an editor ($err) for\n\n$pf\n\nThat path is now in the clipboard: open it with your\ntext editor and then click Reload Settings."
        }
    }
    .b1 configure -text "Reload Settings" -command LoadSettings
}

# Hotkeys
proc HandleHotKey {msg cb} {
    global hotkeyOk rrOn rrLastCode
    Debug "Hotkey ok=$hotkeyOk for $msg - $cb"
    if {$rrOn} {
        # Release the hotkey's modifiers already broadcast before focus changes
        # and mark the currently held keys as seen so the hotkey's key itself isn't broadcast
        ReleaseBroadcastKeys
        set rrLastCode [GetKeyboardState]
        # still held modifiers (e.g. Ctrl-~ Ctrl-~ 1) go with the next key
        PendHeldModifiers
    }
    if $hotkeyOk $cb
}

if {![info exists allHotKeys]} {
    set allHotKeys {}
}
# hotkeyCombo(modifiersMask,vk) -> hotkey description, so broadcasting can skip our own hotkeys
array set hotkeyCombo {}
# hotkeyFailed(settings key) -> description, for the hotkeys that couldn't be registered
array set hotkeyFailed {}

# Global hotkeys: settings key, description (also shown in the Hotkeys dialog) and command
# (per window ones are hk<n>,focus and hk<n>,swap, see RegisterPerWindowHotkey)
set hotkeyList {
    hk,capture "Capture" CaptureOrUpdate
    hk,focusNextWindow "Focus next window" FocusNextWindow
    hk,focusPreviousWindow "Focus previous window" FocusPreviousWindow
    hk,swapNextWindow "Swap next window" SwapNextWindow
    hk,swapPreviousWindow "Swap previous window" SwapPreviousWindow
    hk,focusMain "Focus main window" FocusMain
    hk,rrToggle "Broadcast toggle" RRToggle
    hk,rrExcludeToggle "Skip windows toggle" RRExcludeToggle
    hk,mouseBroadcast "Start/Stop mouse broadcasting" MouseBroadcast
    hk,focusFollowMouse "Focus follow mouse toggle" FocusFollowMouseToggle
    hk,stayOnTopToggle "Always on top toggle" StayOnTopToggle
    hk,overlayToggle "Overlay toggle" OverlayToggle
    hk,resetAll "Reset all windows to saved positions" ResetAll
    hk,nextProfile "Next profile" NextProfile
    hk,previousProfile "Previous profile" PreviousProfile
    hk,mouseTrack "Start/Stop mouse tracking" MouseTracking
    hk,mirrorsToggle "Show/hide mirrors" MirrorsToggle
    hk,mirrorsEdit "Mirrors edit mode toggle" MirrorsEditToggle
}

# Returns {modifiersMask vk} (MOD_ALT 1, MOD_CONTROL 2, MOD_SHIFT 4, MOD_WIN 8) for a hotkey
# like Ctrl-Shift-F1 or Ctrl-0xC0, or empty if not understood
proc HotkeyToModsVk {hk} {
    twapi::_init_vk_map
    set mods 0
    set parts [split $hk "-"]
    foreach m [lrange $parts 0 end-1] {
        switch -nocase -- $m {
            ctrl - control {set mods [expr {$mods|2}]}
            alt - menu {set mods [expr {$mods|1}]}
            shift {set mods [expr {$mods|4}]}
            win - lwin - rwin {set mods [expr {$mods|8}]}
            default {return}
        }
    }
    set k [lindex $parts end]
    # same order as twapi::register_hotkey: 1 is the key, not the code 1
    if {[string length $k] == 1} {
        lassign [twapi::VkKeyScan $k] x vk
    } elseif {[string is integer -strict $k]} {
        set vk [expr {$k}]
    } elseif {[info exists twapi::vk_map([string toupper $k])]} {
        set vk [expr [lindex $twapi::vk_map([string toupper $k]) 0]]
    } else {
        return
    }
    list $mods $vk
}

proc RegisterHotkey {msg var callback} {
    global settings allHotKeys hotkeyCombo hotkeyFailed
    set hk $settings($var)
    Debug "RegisterHotkey $hk $msg $var $callback"
    if {$hk == ""} {
        # #71 if hotkey is empty, skip it
        return
    }
    if {[catch {twapi::register_hotkey $hk [list HandleHotKey $msg $callback]} err]} {
        puts "hotkey error $hk for $msg: $err"
        set hotkeyFailed($var) $msg
        HotkeyConflict
    } else {
        lappend allHotKeys $err
        lassign [HotkeyToModsVk $hk] mods vk
        if {$vk != ""} {
            set hotkeyCombo($mods,$vk) $msg
        } else {
            Debug "Couldn't parse hotkey $hk for broadcast skipping"
        }
    }
}

# --- Hotkeys dialog: click a hotkey then press the new key combination, right click clears it

# Hotkey (as in settings and for twapi::register_hotkey) for a modifiers mask and virtual key code,
# e.g. Ctrl-Shift-F1, or Ctrl-0xC0 when the key has no name
proc HotkeyName {mods vk} {
    set vk [expr {$vk}]
    set name ""
    foreach {bit m} {2 Ctrl 4 Shift 1 Alt 8 Win} {
        if {$mods & $bit} {
            append name "$m-"
        }
    }
    set names {8 {BACKSPACE BACK} 9 TAB 13 {ENTER RETURN} 19 PAUSE 27 {ESC ESCAPE} 32 SPACE
        33 {PGUP PRIOR} 34 {PGDN NEXT} 35 END 36 HOME 37 LEFT 38 UP 39 RIGHT 40 DOWN 45 {INSERT INS}
        46 {DELETE DEL} 106 MULTIPLY 107 ADD 109 SUBTRACT 110 DECIMAL 111 DIVIDE 144 NUMLOCK 145 {SCROLL SCROLLLOCK}}
    set keys {}
    if {($vk >= 0x30 && $vk <= 0x39) || ($vk >= 0x41 && $vk <= 0x5A)} {
        set keys [list [format %c $vk]]
    } elseif {$vk >= 0x70 && $vk <= 0x87} {
        set keys [list F[expr {$vk - 0x6F}]]
    } elseif {$vk >= 0x60 && $vk <= 0x69} {
        set keys [list NUMPAD[expr {$vk - 0x60}]]
    } elseif {[dict exists $names $vk]} {
        set keys [dict get $names $vk]
    }
    # first name that parses back to the same key (layouts, twapi names)
    foreach k $keys {
        if {[HotkeyToModsVk $name$k] eq [list $mods $vk]} {
            return $name$k
        }
    }
    return [format "%s0x%02X" $name $vk]
}

# Hotkey as shown to users: Ctrl-0xC0 is Ctrl-~ (twapi only takes the code for punctuation keys)
proc HotkeyDisplay {hk} {
    if {![regexp {^(.*?)(0[xX][0-9a-fA-F]+)$} $hk all mods vk]} {
        return $hk
    }
    # character of that key in the current keyboard layout (MAPVK_VK_TO_CHAR), high bit is dead keys
    set c [expr {[twapi::MapVirtualKey $vk 2] & 0xFFFF}]
    if {$c <= 32} {
        return $hk
    }
    set c [format %c $c]
    if {$c eq "`"} {
        # the US keyboard "~ key"
        set c "~"
    }
    return $mods$c
}

proc HotkeyLabel {var} {
    global hotkeyList
    if {[regexp {^hk(\d+),(focus|swap)$} $var all n what]} {
        return "[string totitle $what] window $n"
    }
    foreach {v msg cb} $hotkeyList {
        if {$v eq $var} {
            return $msg
        }
    }
    return $var
}

# Shows the Hotkeys dialog (once, after the current registrations) when some couldn't be registered
set hotkeyConflictPending 0
proc HotkeyConflict {} {
    global hotkeyConflictPending
    if {!$hotkeyConflictPending} {
        set hotkeyConflictPending 1
        after idle {set hotkeyConflictPending 0; HotkeysDialog}
    }
}

# Settings key being captured, if any
set hotkeyCapture ""
# Hotkeys dialog message about the last change
set hotkeyNote ""
# Hotkeys before each change made since the dialog opened, for Undo
set hotkeyUndo {}
# Hotkeys defaults, for Restore defaults
array set hotkeyDefaults {}

proc HotkeysDialog {} {
    global hotkeyList hotkeyButtons maxNumW settings hotkeyUndo
    set tw .hotkeys
    if {![winfo exists $tw]} {
        toplevel $tw
        wm title $tw "OMB Hotkeys"
        wm resizable $tw 0 0
        RememberGeometry $tw hotkeysGeometry
        wm protocol $tw WM_DELETE_WINDOW {HotkeysDialogClose 1}
        ttk::style configure OmbHotkeyFailed.TButton -foreground red
        ttk::style configure OmbHotkeyCapture.TButton -font WOBBold
        array unset hotkeyButtons
        set hotkeyUndo {}
        bind $tw <Control-z> HotkeysUndo
        grid [ttk::label $tw.l -text "Click a hotkey then press the new key combination (Esc cancels), right click clears it."] \
            -columnspan 2 -padx 8 -pady 4 -sticky w
        grid [ttk::labelframe $tw.g -text "General"] [ttk::labelframe $tw.w -text "Windows"] -padx 8 -sticky nsew
        set row 0
        foreach {var msg cb} $hotkeyList {
            grid [ttk::label $tw.g.l$row -text $msg] [HotkeyButton $tw.g.b$row $var] -padx 4 -pady 1 -sticky w
            incr row
        }
        grid x [ttk::label $tw.w.hf -text "Focus"] [ttk::label $tw.w.hs -text "Swap"] -padx 4
        set num 12
        while {[info exists settings(hk[expr {$num+1}],focus)] || [info exists settings(hk[expr {$num+1}],swap)] || $num < $maxNumW-1} {
            incr num
        }
        for {set n 1} {$n <= $num} {incr n} {
            grid [ttk::label $tw.w.l$n -text "Window $n"] [HotkeyButton $tw.w.f$n hk$n,focus] [HotkeyButton $tw.w.s$n hk$n,swap] \
                -padx 4 -pady 1 -sticky w
        }
        grid [ttk::label $tw.status -foreground red -wraplength 700] -columnspan 2 -padx 8 -pady {4 0} -sticky ew
        # wrap at the window width (set by the hotkeys frames)
        bind $tw.status <Configure> {%W configure -wraplength %w}
        grid [ttk::frame $tw.b] -columnspan 2 -pady 6
        pack [ttk::button $tw.b.undo -text "Undo" -command HotkeysUndo] \
            [ttk::button $tw.b.def -text "Restore defaults" -command HotkeysDefaults] \
            [ttk::button $tw.b.close -text Close -command HotkeysDialogClose] -side left -padx 4
        tooltip $tw.b.undo "Undo the last change (Ctrl-Z)\nrepeat to go back to the hotkeys as they were when this window opened"
        UpdateHandles
    }
    HotkeysDialogRefresh
    wm state $tw normal
    raise $tw
}

proc HotkeyButton {b var} {
    global hotkeyButtons
    ttk::button $b -width -20 -command [list HotkeyCapture $var]
    bind $b <Button-3> [list HotkeySet $var ""]
    # while capturing, keys (Tab, Alt, Space...) don't do their usual thing
    bind $b <KeyPress> "if {\[HotkeyKey [list $var] %k\]} break"
    bind $b <KeyRelease> "if {\$hotkeyCapture eq {$var}} break"
    bind $b <FocusOut> [list HotkeyCaptureEnd $var]
    set hotkeyButtons($var) $b
    return $b
}

proc HotkeysDialogRefresh {} {
    global settings hotkeyButtons hotkeyFailed hotkeyCapture hotkeyNote hotkeyUndo
    if {![winfo exists .hotkeys]} {
        return
    }
    foreach var [array names hotkeyButtons] {
        set b $hotkeyButtons($var)
        set hk [HotkeyDisplay [expr {[info exists settings($var)] ? $settings($var) : ""}]]
        if {$var eq $hotkeyCapture} {
            $b configure -text "Press keys..." -style OmbHotkeyCapture.TButton
        } elseif {[info exists hotkeyFailed($var)]} {
            $b configure -text $hk -style OmbHotkeyFailed.TButton
        } else {
            $b configure -text $hk -style TButton
        }
    }
    set status $hotkeyNote
    set failed {}
    foreach var [lsort [array names hotkeyFailed]] {
        lappend failed "$hotkeyFailed($var) ([HotkeyDisplay $settings($var)])"
    }
    if {[llength $failed]} {
        lappend status "Hotkeys in red are already used by another application: [join $failed {, }]." \
            "Click them to pick different keys."
    }
    # (space: keeps the one line height when empty)
    .hotkeys.status configure -text [expr {[llength $status] ? [join $status "\n"] : " "}]
    .hotkeys.b.undo state [expr {[llength $hotkeyUndo] ? "!disabled" : "disabled"}]
}

proc HotkeyCapture {var} {
    global hotkeyCapture hotkeyOk hotkeyButtons hotkeyNote
    if {$hotkeyCapture eq $var} {
        # clicking again cancels
        HotkeyCaptureEnd
        return
    }
    if {$hotkeyCapture eq ""} {
        # so our current hotkeys reach the dialog instead of triggering
        UnregisterHotkeys
        set hotkeyOk 0
    }
    set hotkeyNote ""
    set hotkeyCapture $var
    focus $hotkeyButtons($var)
    HotkeysDialogRefresh
}

proc HotkeyCaptureEnd {{var ""}} {
    global hotkeyCapture hotkeyOk
    if {$hotkeyCapture eq "" || ($var ne "" && $var ne $hotkeyCapture)} {
        return
    }
    set hotkeyCapture ""
    set hotkeyOk 1
    RegisterAllHotkeys
    HotkeysDialogRefresh
}

# Returns 1 when the key was for the capture
proc HotkeyKey {var vk} {
    global hotkeyCapture
    if {$hotkeyCapture ne $var} {
        return 0
    }
    # modifiers alone: wait for the actual key
    if {$vk in {16 17 18 91 92 160 161 162 163 164 165}} {
        return 1
    }
    set mods [HeldModifiersMask]
    if {$vk == 0x1B && $mods == 0} {
        HotkeyCaptureEnd
        return 1
    }
    set hk [HotkeyName $mods $vk]
    Debug "Hotkey capture for $var: vk $vk mods $mods -> $hk"
    HotkeySet $var $hk
    return 1
}

proc HotkeySet {var hk} {
    global settings hotkeyCapture hotkeyNote
    set hotkeyNote {}
    set before [HotkeysSnapshot]
    set combo [HotkeyToModsVk $hk]
    if {$combo ne ""} {
        # like the WoW key bindings: taking a key unbinds it from the other hotkey
        foreach other [array names settings hk*,*] {
            if {$other ne $var && $settings($other) ne "" && [HotkeyToModsVk $settings($other)] eq $combo} {
                Debug "Hotkey $hk cleared from $other"
                set settings($other) ""
                lappend hotkeyNote "[HotkeyDisplay $hk] was used by [HotkeyLabel $other], now cleared."
            }
        }
    }
    Debug "Hotkey $var set to \"$hk\""
    set settings($var) $hk
    HotkeysUndoPush $before
    HotkeysChanged
}

# (can be undone so no confirmation)
proc HotkeysDefaults {} {
    global settings hotkeyDefaults hotkeyNote
    set before [HotkeysSnapshot]
    array unset settings hk*,*
    array set settings [array get hotkeyDefaults]
    set hotkeyNote {}
    HotkeysUndoPush $before
    HotkeysChanged
}

proc HotkeysSnapshot {} {
    global settings
    lsort -stride 2 [array get settings hk*,*]
}

proc HotkeysUndoPush {before} {
    global hotkeyUndo
    if {$before ne [HotkeysSnapshot]} {
        lappend hotkeyUndo $before
    }
}

proc HotkeysUndo {} {
    global settings hotkeyUndo hotkeyNote
    if {![llength $hotkeyUndo]} {
        return
    }
    array set before [lindex $hotkeyUndo end]
    set hotkeyUndo [lrange $hotkeyUndo 0 end-1]
    set changes {}
    foreach var [lsort -unique -dictionary [concat [array names settings hk*,*] [array names before]]] {
        set old [expr {[info exists before($var)] ? $before($var) : ""}]
        set cur [expr {[info exists settings($var)] ? $settings($var) : ""}]
        if {$old ne $cur} {
            lappend changes "[HotkeyLabel $var] back to [expr {$old eq "" ? "none" : [HotkeyDisplay $old]}]"
        }
    }
    Debug "Hotkeys undo: $changes"
    if {[llength $changes] > 3} {
        set hotkeyNote [list "Undone: [llength $changes] hotkeys restored."]
    } else {
        set hotkeyNote [list "Undone: [join $changes {, }]."]
    }
    array unset settings hk*,*
    array set settings [array get before]
    HotkeysChanged
}

proc HotkeysChanged {} {
    global hotkeyCapture
    SaveSettings
    UpdateHotkeyTexts
    if {$hotkeyCapture ne ""} {
        HotkeyCaptureEnd
    } else {
        RegisterAllHotkeys
        HotkeysDialogRefresh
    }
}

proc HotkeysDialogClose {{fromWm 0}} {
    global hotkeyCapture
    if {$fromWm && $hotkeyCapture ne ""} {
        # e.g. Alt-F4 being captured
        return
    }
    HotkeyCaptureEnd
    destroy .hotkeys
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
# focus window handle for each application window
array set slot2focus {}

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
    } elseif {$fg && $settings(focusAlsoFG)} {
        # activating it also gives it the keys, while set_focus waits for both games to handle
        # the focus change (100s of ms for one stacked under main in the mirrored layout)
        Debug "Making $n foreground"
        if {![Foreground $wh]} {
            Debug "Foreground of $n refused, setting focus"
            Focus $wh
        }
    } else {
        Focus $wh
    }
    if {$p != 1 && [LayoutMirrored]} {
        # keys go to that window but main stays visible (on top of it)
        LowerUnderMain $wh
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
    if {[RealPosition $lastFocusWindow] == $lastFocusWindow} {
        catch {SetStayOnTop $slot2handle($lastFocusWindow) $settings($lastFocusWindow,stayOnTop)}
    } else {
        # windows stacked under main: that's for their mirror
        MirrorsRefreshAll
    }
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

proc FocusNextWindow {} {
    global focusWindow maxNumW settings resetTaskId lastFocusWindow
    if {[info exists resetTaskId]} {
        after cancel $resetTaskId
        unset resetTaskId
    }
    if {$maxNumW<3} {
        return
    }
    # maxNumW is one more than number of windows
    set n [expr {$focusWindow % ($maxNumW-1) + 1}]
    Debug "FocusNextWindow: focusWindow $focusWindow maxNumW $maxNumW -> $n"
    if {$settings(rrAlwaysFocus) || $n!=$lastFocusWindow} {
        CheckWindow [list FocusN $n true 0] $n
    }
    # always update even if we were already on the spot (so we move out of it next)
    set focusWindow $n
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
    set rp [RealPosition $p]
    lassign $settings($rp,posXY) lx ly
    lassign $settings($rp,size) lw lh
    set lstayOnTop 0
    # in the mirrored layout, stay on top applies to the mirrors of the windows under main
    if {$rp == $p && [info exists settings($p,stayOnTop)]} {
        set lstayOnTop $settings($p,stayOnTop)
    }
    Debug "Update for $n in pos $p ($rp) : $lx,$ly ${lw}x$lh - $lstayOnTop"
    set raised [Update $wh $lx $ly $lw $lh $lstayOnTop]
    if {$p == 1 && [LayoutMirrored]} {
        RaiseMain
    }
    if {$settings(showOverlay) && [winfo exists .o$p]} {
        .o$p.l configure -text $n
        if {$p!=1 && $settings(overlayClickable)} {
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
    # swapped or resized
    MirrorsRefreshAll
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
    MirrorPickSwapped
    set swappedWindow $n
    if {$settings(swapAlsoFocus)} {
        CheckWindow [list FocusN $n true] $n
    } else {
        if {[LayoutMirrored]} {
            # raising main isn't allowed over another game's foreground window: lower the others
            StackUnderMain
        }
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
    # Probably should have a safer/cleaner way to find toplevel but this works for windows11 24h2 (0x1000c)
    # and earlier versions (0x10010).
    expr {$id==0x10010 || $id==0x1000c}
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
        if {$w in {.ctx .mirrorMenu}} {
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
        if {$w in {. .clip .newProfile .connect .profileRotation .hotkeys .mirrors}} {
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
    # windows captured or gone
    MirrorsRefreshAll
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

# window handle to title before capture, restored by Forget
array set origTitle {}

proc SaveOrigTitle {w} {
    global origTitle
    catch {set origTitle($w) [twapi::get_window_text $w]}
}

# Lowest window number of the layout without a captured window (never captured, lost or forgotten), "" if none
proc FirstFreeSlot {} {
    global settings slot2handle
    for {set n 1} {$n <= $settings(numWindows)} {incr n} {
        if {![info exists slot2handle($n)]} {
            return $n
        }
    }
    return ""
}

proc AutoCapture {w} {
    global nextWindow settings stayOnTop lastUpdate slot2handle autoCaptureErrorCount
    set n [FirstFreeSlot]
    if {$n eq ""} {
        return
    }
    set nextWindow $n
    set wname "OMB $nextWindow"
    SaveOrigTitle $w
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
        AddGame $wtitle
    } else {
        set w [FindGameWindow]
        if {$w eq ""} {
            OmbError "OpenMultiBoxing Error" "No $settings(game) window found"
            return
        }
    }
    set wname "OMB $nextWindow"
    SaveOrigTitle $w
    # We are resizing just after so no need to do it twice,
    # but otherwise it is needed for the inner size of wow to be correct
    if {$settings(borderless)} {
        BorderLess $w 0
    }
    Rename $w $wname
    PostCapture $w $wname
}

proc PostCapture {w wname} {
    global nextWindow stayOnTop lastUpdate settings
    # Need to really update if we captured/forgot before
    catch {unset lastUpdate($w)}
    if {[RealPosition $nextWindow] != $nextWindow && [ValidWindowSettingsN 1]} {
        # mirrored layout: under the main window
        Update $w {*}$settings(1,posXY) {*}$settings(1,size) 0
    } else {
        Update $w [GetX] [GetY] [GetWidth] [GetHeight] $stayOnTop
    }
    updateListBox $nextWindow $w $wname
    if {[LayoutMirrored]} {
        # the new window under main, or the others under it if it's main
        StackUnderMain
        MirrorsRefreshAll
    }
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

proc validHandle {w} {
    expr {$w != $twapi::null_hwin && $w != "0 HWND"}
}

# The focus handle may not be known yet at capture (window not active/ready yet, we then use the
# top level window): look again when that window is the active one (background threads have no focus).
# focusIsTop(slot) is the top level window handle when that's also its focus window (e.g. WoW): no need to look again.
proc RefreshFocusHandle {n} {
    global slot2focus slot2handle focusIsTop
    if {![info exists slot2handle($n)] || $slot2focus($n) ne $slot2handle($n)} {
        return
    }
    if {[info exists focusIsTop($n)] && $focusIsTop($n) eq $slot2handle($n)} {
        return
    }
    if {[catch {twapi::get_focus_window_for_thread [twapi::get_window_thread $slot2handle($n)]} fh]} {
        return
    }
    if {$fh eq $slot2focus($n)} {
        set focusIsTop($n) $fh
    } elseif {[validHandle $fh]} {
        Debug "Focus for $n is now $fh"
        set slot2focus($n) $fh
    }
}

# Bring w to the front and set slot2focus(n) to the window that gets its keyboard input
# (the top level window itself if the app has no focus window yet after a short wait)
proc FindFocusHandle {n w} {
    global slot2focus
    Foreground $w
    set tid [twapi::get_window_thread $w]
    # the app sets its focus window when processing the activation
    for {set i 0} {$i < 10} {incr i} {
        set focusHandle [twapi::get_focus_window_for_thread $tid]
        if {[validHandle $focusHandle]} {
            break
        }
        after 20
    }
    Debug "Focus for $n is $focusHandle, tid $tid (after $i tries)"
    if {[validHandle $focusHandle]} {
        set slot2focus($n) $focusHandle
    } else {
        set slot2focus($n) $w
    }
}

proc setFocusHandle {n} {
    global slot2handle
    if {![info exists slot2handle($n)]} {
        return
    }
    FindFocusHandle $n $slot2handle($n)
}

proc updateListBox {n w wname} {
    global ourWindowHandles slot2handle slot2position nextWindow maxNumW settings slot2focus forgottenSlot
    FindFocusHandle $n $w
    set slot2handle($n) $w
    unset -nocomplain forgottenSlot($w)
    # lost while swapped: the window that is in its position goes back to its own
    set m [SlotAtPosition $n]
    set slot2position($n) $n
    if {$m ne "" && $m != $n} {
        set slot2position($m) $m
        CheckWindow [list UpdateN $m] $m
    }
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
    global settings monitorInfo scale skipMonitorText layoutinfo layoutNumWindowsText scaleText snapMenuText numWindowsFloat \
        layoutMirrored
    set tw .layout
    # applied by Save and Apply
    set layoutMirrored $settings(layoutMirrored)
    if {[winfo exists $tw]} {
        wm state $tw normal
        raise $tw
        ChangeLayout
        return
    }
    UpdateExcluded
    toplevel $tw
    wm title $tw "OpenMultiBoxing Window Layout"
    RememberGeometry $tw layoutGeometry
    ttk::checkbutton $tw.cbA -variable settings(layoutAuto) -text "Auto" -command ChangeLayout
    tooltip $tw.cbA "Automatically regenerate the layout on any change\nwhen checked. Uncheck for manual layout"
    ttk::checkbutton $tw.cbT -variable settings(layoutTop) -text "Main at bottom" -command ChangeLayout
    tooltip $tw.cbT "Checked if you prefer the main window at the bottom instead of the top of the screen"
    set numWindowsFloat $settings(numWindows)
    ttk::scale $tw.s -variable numWindowsFloat -orien horizontal -from 0 -to $settings(layoutMaxWindows) -command ChangeNumWindow
    tooltip $tw.s "Select how many windows in your layout."
    ttk::checkbutton $tw.cb1 -variable settings(layoutOneSize) -text "Same size for all" -command ChangeLayout
    ttk::checkbutton $tw.cb2 -variable settings(layoutOneRowCol) -text "One row/col for small windows" -command ChangeLayout
    ttk::checkbutton $tw.cb3 -variable settings(layoutStacked) -text "All Stacked" -command LayoutStackedChanged
    ttk::checkbutton $tw.cb4 -variable layoutMirrored -text "Mirrored" -command LayoutMirroredChanged
    tooltip $tw.cb1 "Check or uncheck to redo the layout with\nwindows of the same size (fastest switch later)\nor not (1 big main window and smaller minions windows)"
    tooltip $tw.cb4 "All the game windows stacked under the main one,\nthe other positions show live mirrors of them:\nswaps are instant (no resizing). Click a mirror to make it main.\nFocus follows mouse only works for the main window."
    tooltip $tw.cb3 "All the windows at the same place, filling the biggest monitor:\nonly the one on top (main) is visible, swap to see another one\n(Mirrored also shows the others)"
    set layoutNumWindowsText "Layout for 99 windows"
    set width [expr {2+[string length $layoutNumWindowsText]}]
    UpdateLayoutNumWindows
    grid x x x $tw.cb2 - $tw.cb4 -padx 8 -sticky we
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
    ttk::radiobutton $tw.asrf.ar6 -value "Same" -text "Same" -variable settings(aspectRatio) -command ChangeLayout
    tooltip $tw.asrf.ar0 "Biggest windows that fit, whatever their aspect ratio\n(but not taller than wide: 5:4 for portrait spaces)"
    tooltip $tw.asrf.ar6 "Biggest small windows (as with Any),\nthen their aspect ratio for all windows\n(so swapping windows and mouse clicks match)"
    pack [ttk::label $tw.asrf.l2 -text "Aspect ratio:" -anchor w -justify left] $tw.asrf.ar0  $tw.asrf.ar1  $tw.asrf.ar2  $tw.asrf.ar3  $tw.asrf.ar4  $tw.asrf.ar5 $tw.asrf.ar6 -side left -expand 1
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

proc LayoutStackedChanged {} {
    global settings layoutMirrored
    if {$settings(layoutStacked)} {
        set layoutMirrored 0
    }
    ChangeLayout
}

proc LayoutMirroredChanged {} {
    global settings layoutMirrored
    if {!$layoutMirrored} {
        return
    }
    if {![MirrorCheckBinary]} {
        set layoutMirrored 0
        return
    }
    if {$settings(layoutStacked)} {
        set settings(layoutStacked) 0
        ChangeLayout
    }
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

# Testing aid, from the -debug console: pretend to have these monitors for the layout window, e.g.
#   FakeMonitors 4k 1440p* 4k:p
# Left to right, each WxH or a name below, * marks the primary (else the first one), :p portrait,
# :t / :b aligned on the top / bottom of the previous one (default centered).
# No argument goes back to the real monitors.
proc FakeMonitors {args} {
    global fakeMonitors
    set sizes {720p {1280 720} 1080p {1920 1080} 1200p {1920 1200} 1440p {2560 1440} 1600p {2560 1600}
        4k {3840 2160} 5k {5120 2880} uw {3440 1440} uw1080 {2560 1080} 5k2k {5120 2160} 32x9 {5120 1440}}
    unset -nocomplain fakeMonitors
    if {[llength $args]} {
        set mons {}
        set primary 0
        set i 0
        foreach spec $args {
            set flags [lassign [split $spec :] size]
            if {[regsub {\*$} $size {} size]} {
                set primary $i
            }
            if {[dict exists $sizes $size]} {
                lassign [dict get $sizes $size] w h
            } elseif {![regexp {^(\d+)x(\d+)$} $size -> w h]} {
                error "Unknown monitor '$size': use WxH or one of [dict keys $sizes]"
            }
            if {"p" in $flags} {
                lassign [list $h $w] w h
            }
            set x 0
            set y 0
            if {$i > 0} {
                lassign [lindex $mons end] px1 py1 x py2
                if {"t" in $flags} {
                    set y $py1
                } elseif {"b" in $flags} {
                    set y [expr {$py2-$h}]
                } else {
                    set y [expr {$py1+($py2-$py1-$h)/2}]
                }
            }
            lappend mons [list $x $y [expr {$x+$w}] [expr {$y+$h}]]
            incr i
        }
        # primary at 0,0 with a taskbar
        lassign [lindex $mons $primary] dx dy
        set fakeMonitors {}
        set i 0
        foreach m $mons {
            lassign $m x1 y1 x2 y2
            set extent [list [expr {$x1-$dx}] [expr {$y1-$dy}] [expr {$x2-$dx}] [expr {$y2-$dy}]]
            set workarea $extent
            if {$i == $primary} {
                lset workarea 3 [expr {[lindex $extent 3]-48}]
            }
            incr i
            lappend fakeMonitors [list -name "\\\\.\\DISPLAY$i" -extent $extent -workarea $workarea -primary [expr {$i-1 == $primary}]]
        }
    }
    if {![winfo exists .layout]} {
        WindowLayout
    }
    UpdateExcluded
}

proc MonitorsInfo {} {
    global fakeMonitors
    if {[info exists fakeMonitors]} {
        return $fakeMonitors
    }
    twapi::get_multiple_display_monitor_info
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
    set displayInfo [MonitorsInfo]
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
    global slot2handle slot2focus
    set WM_KEYDOWN 0x0100
    set WM_KEYUP 0x0101
    foreach {n w} [array get slot2handle] {
        set fh $slot2focus($n)
        Debug "Sending input key $keyCode to $n ($w $fh)"
        CheckWindow [list twapi::PostMessage $fh $WM_KEYDOWN $keyCode 1] $n
    }
    after $delayMs
    foreach {n w} [array get slot2handle] {
        set fh $slot2focus($n)
        twapi::PostMessage $fh $WM_KEYUP $keyCode 1
    }
    # could also use twapi::send_input but that changes fg/active window
}

# Post key down/up to the window in slot i and track which keys we left down in which window
proc PostKeyToSlot {i keyCode up} {
    global sentDown
    if {$up} {
        unset -nocomplain sentDown($i,$keyCode)
    } else {
        set sentDown($i,$keyCode) 1
    }
    PostKeyMessage $i $keyCode $up
}

proc PostKeyMessage {i keyCode up} {
    global slot2focus
    set ev [expr {0x0100+$up}]
    set lparam [expr {$up ? 0xC0000001 : 0}]
    CheckWindow [list twapi::PostMessage $slot2focus($i) $ev $keyCode $lparam] $i
}

# Same as PostKeyToSlot but, when settings(broadcastDelay) is set, posts after the window's lag
# (from RollBroadcastLags). Lags are only re-rolled when no keys are held or posts pending so
# the order of events within a window (modifiers before keys, down before up) is preserved.
# Most apps (but not WoW) take modifiers from the real keyboard state when processing the key, so with
# settings(broadcastDelayModifiersFlush) keys pressed with modifiers held (modsHeld) and their key up
# are sent now, after the window's pending posts.
# sentDown(slot,keyCode) is 2 for those (1 for delayed ones).
proc QueueKeyToSlot {i keyCode up modsHeld} {
    global settings sentDown bcLag bcLastT bcPending bcToken
    set base $settings(broadcastDelay)
    if {$base <= 0} {
        PostKeyToSlot $i $keyCode $up
        return
    }
    if {$up ? ([info exists sentDown($i,$keyCode)] && $sentDown($i,$keyCode) == 2) : $modsHeld} {
        FlushPendingKeys $i
        PostKeyToSlot $i $keyCode $up
        if {!$up} {
            set sentDown($i,$keyCode) 2
        }
        return
    }
    if {![info exists bcLag($i)]} {
        set bcLag($i) [expr {$base + int(rand()*2*$base)}]
    }
    if {$up} {
        unset -nocomplain sentDown($i,$keyCode)
    } else {
        set sentDown($i,$keyCode) 1
    }
    set now [clock milliseconds]
    set t [expr {$now + $bcLag($i)}]
    if {[info exists bcLastT($i)] && $bcLastT($i) > $t} {
        set t $bcLastT($i)
    }
    set bcLastT($i) $t
    set token [incr bcToken]
    Debug "Key $keyCode up=$up to $i in [expr {$t-$now}] ms"
    set bcPending($i,$token) [list [after [expr {$t-$now}] [list DelayedKeyPost $i $token]] $keyCode $up]
}

# Send the pending posts of slot i now, in order
proc FlushPendingKeys {i} {
    global bcPending sentDown
    foreach k [lsort -dictionary [array names bcPending $i,*]] {
        lassign $bcPending($k) id keyCode up
        after cancel $id
        unset bcPending($k)
        Debug "Flushing key $keyCode up=$up to $i"
        PostKeyMessage $i $keyCode $up
        if {!$up && [info exists sentDown($i,$keyCode)]} {
            set sentDown($i,$keyCode) 2
        }
    }
}

proc DelayedKeyPost {i token} {
    global bcPending slot2focus
    lassign $bcPending($i,$token) id keyCode up
    unset bcPending($i,$token)
    if {[info exists slot2focus($i)]} {
        PostKeyMessage $i $keyCode $up
    }
}

# Send key down to all windows except the one with the given slot number
# Key up goes to all windows that got the down, including the focused one,
# as focus may have changed in between (e.g. Ctrl-~ swap), otherwise the key stays stuck.
# Use up=1 for key up, up=0 for key down
proc BroadcastKeyToOther {n keyCode up} {
    global slot2handle broadcastMap sentDown settings bcPending
    # Remap key if needed
    if {[info exists broadcastMap($keyCode)]} {
        Debug "Remapping $keyCode to $broadcastMap($keyCode)"
        set keyCode $broadcastMap($keyCode)
    }
    if {!$up} {
        RefreshFocusHandle $n
    }
    set skip [RRExcludedWindows]
    set targets {}
    foreach {i w} [array get slot2handle] {
        if {$up} {
            if {![info exists sentDown($i,$keyCode)]} {
                continue
            }
        } elseif {$i==$n || [lsearch -exact $skip $i] >= 0} {
            continue
        }
        lappend targets $i
    }
    set modsHeld 0
    if {!$up && $settings(broadcastDelay) > 0} {
        if {[array size bcPending] == 0 && [array size sentDown] == 0} {
            RollBroadcastLags $targets
        }
        if {$settings(broadcastDelayModifiersFlush)} {
            set modsHeld [expr {[HeldModifiersMask] != 0}]
        }
    }
    foreach i $targets {
        QueueKeyToSlot $i $keyCode $up $modsHeld
    }
}

# Spread the windows over [base, 3x base]: random order, each window in its own equal slice,
# at a random point of the middle half of the slice, so they are at least base/count apart.
proc RollBroadcastLags {slots} {
    global settings bcLag
    set base $settings(broadcastDelay)
    set m [llength $slots]
    if {$m == 0} {
        return
    }
    set slice [expr {2.0*$base/$m}]
    set shuffled {}
    foreach i $slots {
        lappend shuffled [list [expr {rand()}] $i]
    }
    set k 0
    foreach e [lsort -real -index 0 $shuffled] {
        set bcLag([lindex $e 1]) [expr {$base + int(($k + 0.25 + 0.5*rand())*$slice)}]
        incr k
    }
}

# Send key up for all the keys we posted down and not up yet
# (before hotkeys change focus and when broadcasting is turned off/paused)
proc ReleaseBroadcastKeys {} {
    global sentDown slot2handle rrSentDown bcPending bcLastT
    # Drop delayed downs, send delayed ups now (sentDown no longer has them)
    foreach k [lsort -dictionary [array names bcPending]] {
        lassign $bcPending($k) id keyCode up
        after cancel $id
        lassign [split $k ","] i
        if {$up && [info exists slot2handle($i)]} {
            Debug "Releasing pending key $keyCode for $i"
            PostKeyMessage $i $keyCode 1
        }
    }
    array unset bcPending *
    array unset bcLastT *
    foreach k [array names sentDown] {
        lassign [split $k ","] i keyCode
        if {[info exists slot2handle($i)]} {
            Debug "Releasing key $keyCode for $i"
            PostKeyToSlot $i $keyCode 1
        }
    }
    array unset sentDown *
    foreach code [array names rrSentDown] {
        SendToClients "UP $code\n"
    }
    array unset rrSentDown *
}

# Unfortunatly this does not work (mouse coords are not used, it only clicks where the mouse really is)
proc BroadcastMouseClick {x y} {
    global slot2handle settings
    set WM_LBUTTONDOWN 0x0201
    set WM_LBUTTONUP 0x0202
    set WM_MOUSEMOVE 0x0200
    set WM_MOUSEACTIVATE 0x0021
    set HTCLIENT 1
    set lword [expr {($x<<16)+$y}]
    foreach {n w} [array get slot2handle] {
        Debug "Sending mouse click $x,$y $lword to $n ($w)"
#        twapi::PostMessage $w $WM_MOUSEACTIVATE [lindex $w 0] $HTCLIENT # doesn't help
        twapi::PostMessage $w $WM_MOUSEMOVE 0 $lword
        twapi::PostMessage $w $WM_LBUTTONDOWN 1 $lword
    }
    after $settings(mouseBroadcastDelay)
    foreach {n w} [array get slot2handle] {
        twapi::PostMessage $w $WM_LBUTTONUP 0 $lword
    }
}

# Doesn't work either...
proc BroadcastMouseClick2 {x y} {
    global slot2handle settings
    set WM_LBUTTONDOWN 0x0201
    set WM_LBUTTONUP 0x0202
    set WM_MOUSEMOVE 0x0200
    set SMTO_ABORTIFHUNG 0x0002
    set timeout 50
    set lword [expr {($x<<16)+$y}]
    foreach {n w} [array get slot2handle] {
        Debug "Sending mouse click $x,$y $lword to $n ($w) using SendMessageTimeout"
        twapi::SendMessageTimeout $w $WM_MOUSEMOVE 0 $lword $SMTO_ABORTIFHUNG $timeout
        twapi::SendMessageTimeout $w $WM_LBUTTONDOWN 1 $lword $SMTO_ABORTIFHUNG $timeout
    }
    after $settings(mouseBroadcastDelay)
    foreach {n w} [array get slot2handle] {
        twapi::SendMessageTimeout $w $WM_LBUTTONUP 0 $lword $SMTO_ABORTIFHUNG $timeout
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
    global rrCodes rrExcludes
    foreach code $rrExcludes {
        twapi::GetAsyncKeyState $code
    }
    foreach code $rrCodes {
        twapi::GetAsyncKeyState $code
    }
}

proc RRUpdate {} {
    global rrOn rrOnLabel settings hasRR hasBR mouseFollow rrMouse rrLastCode rrTaskId mouseBroadcast rrPendingMods
    Debug "RRupdate $rrOn"
    ReleaseBroadcastKeys
    array unset rrPendingMods *
    if {[info exists rrTaskId]} {
        after cancel $rrTaskId
        unset rrTaskId
    }
    set rrLastCode {}
    if {$rrOn && $hasRR} {
        set rrOnLabel [RRIndicatorLabel]
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
        if {[info exists rrMouse] && $rrMouse && (!$mouseBroadcast || !$settings(mouseBroadcastUsePostMessage))} {
            set mouseFollow 1
            UpdateMouseFollow
        }
    }
    AddMouseToRRLabel
    # read twice
    GetKeyboardState
    set rrLastCode [GetKeyboardState]
    if {$rrOn} {
        # e.g. pause/resume when a swap moves windows under the mouse
        PendHeldModifiers
    }
    Debug "Reset all Broadcasting key states"
}

proc KeyToKeyCode {k} {
    set len [string length $k]
    if {$len == 0} {
        # skip extra spaces
        return
    }
    if {$len == 1} {
        lassign [twapi::VkKeyScan $k] x code
    } elseif {![info exists twapi::vk_map($k)]} {
        OmbError "Invalid Broadcasting key" "$k isn't a valid key"
        return
    } else {
        set code [expr [lindex $twapi::vk_map($k) 0]]
    }
    Debug "RRkey $k -> 0x[format %x $code]"
    return [list $k $code]
}

proc RRkeyListToCodes {keyList} {
    set res {}
    set fixedList {}
    foreach k [split $keyList " "] {
        lassign [KeyToKeyCode $k] k code
        set len [string length $k]
        if {$len == 0} {
            # skip extra spaces and errors
            continue
        }
        lappend res $code
        lappend fixedList $k
    }
    return [list $res [join $fixedList " "]]
}

set rrCodes {}
set rrExcludes {}
array set broadcastMap {}
# sentDown(slot,keyCode) exists when we posted key down to that slot without the up yet
array set sentDown {}
# settings(broadcastDelay) state: bcLag(slot) current lag, bcLastT(slot) time of the last scheduled post,
# bcPending(slot,token) {afterId keyCode up} of posts not done yet
array set bcLag {}
array set bcLastT {}
array set bcPending {}
set bcToken 0
# rrSentDown(keyCode): broadcast down (to windows/clients) without up yet
array set rrSentDown {}
# rrPendingMods(keyCode): modifiers held but not broadcast until a non modifier key is pressed
array set rrPendingMods {}
# Slot of the game window that had focus at the last broadcast check
set rrLastFocus 0

proc RRKeysListChange {} {
    twapi::_init_vk_map
    global settings rrCodes rrExcludes broadcastMap
    # Split settings(broadcastMap) into pairs separated by :
    catch {unset broadcastMap}
    array set broadcastMap {}
    set okMapList {}
    foreach m [split $settings(broadcastMap) " "] {
        if {$m == ""} {
            continue
        }
        lassign [split $m ":"] in out
        if {$in == "" || $out == ""} {
            OmbError "Invalid key map" "$m isn't a colon separated pair"
            continue
        }
        lassign [KeyToKeyCode $in] in inCode
        lassign [KeyToKeyCode $out] out outCode
        if {$in == "" || $out == ""} {
            # Error already shown, if any
            continue
        }
        set broadcastMap($inCode) $outCode
        lappend okMapList [join [list $in $out] ":"]
    }
    # TODO: check for duplicates
    set settings(broadcastMap) [join $okMapList " "]
    lassign [RRkeyListToCodes $settings(rrKeyListExclude)] rrCodes settings(rrKeyListExclude)
    lassign [RRkeyListToCodes $settings(rrModExcludeList)] rrExcludes settings(rrModExcludeList)
    ResetIgnoredKeys $rrCodes
}

set rrLastCode {}

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

# Returns which game window has the keyboard focus
# returns <= 0 if not a game window
proc FocusIn {} {
    if {[catch {twapi::get_foreground_window} focus]} {
        Debug "FocusIn: failed to get foreground window: $focus"
        return 0
    }
    # somehow returns empty at times
    if {$focus == ""} {
        Debug "FocusIn: no foreground window"
        return 0
    }
    expr {[IsOurs $focus]-2}
}

# Main broadcast setup
proc RRCheck {} {
    global rrCodes rrExcludes rrLastCode rrTaskId settings maxNumW slot2position
    global rrPendingMods rrSentDown hotkeyCombo rrLastFocus broadcastMap
    set rrTaskId [after $settings(rrInterval) RRCheck]
    #Debug "RR Check..."
    set n [FocusIn]
    if {$n<=0} {
        #Debug "Mouse not in game window"
        set rrLastFocus 0
        return
    }
    if {$n != $rrLastFocus} {
        set rrLastFocus $n
        # The newly focused window missed the down of modifiers pressed before it got focus (e.g. Ctrl of Ctrl-~ swap)
        foreach code [HeldBroadcastModifiers] {
            Debug "Modifier $code held while focus changed to $n, sending it down there"
            set rcode $code
            if {[info exists broadcastMap($code)]} {
                set rcode $broadcastMap($code)
            }
            PostKeyToSlot $n $rcode 0
            set rrSentDown($code) 1
        }
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
        unset -nocomplain rrPendingMods($code)
        if {![info exists rrSentDown($code)]} {
            # deferred modifier, hotkey key, etc... that we never sent down
            Debug "Key $code now reset, wasn't broadcast"
            continue
        }
        Debug "Key $code now reset, sending up event to windows that got the down"
        BroadcastKeyEvent $n $code 1
    }
    # Process modifiers first so they are pending before a key pressed in the same check
    set mods {}
    set keys {}
    foreach code $newDown {
        if {[IsModifierKey $code]} {
            lappend mods $code
        } else {
            lappend keys $code
        }
    }
    foreach code $mods {
        if {$settings(rrDeferModifiers)} {
            Debug "Modifier $code now down, deferring until a key is pressed"
            set rrPendingMods($code) 1
            continue
        }
        Debug "Modifier $code now down, sending down event to all but slot $n"
        BroadcastKeyEvent $n $code 0
    }
    foreach code $keys {
        set mask [HeldModifiersMask]
        if {[info exists hotkeyCombo($mask,$code)]} {
            Debug "Key $code is our \"$hotkeyCombo($mask,$code)\" hotkey, not broadcasting"
            continue
        }
        if {[IsSystemCombo $mask $code]} {
            Debug "Key $code with modifiers $mask is a Windows shortcut, not broadcasting"
            continue
        }
        foreach mod [array names rrPendingMods] {
            Debug "Sending deferred modifier $mod down to all but slot $n"
            BroadcastKeyEvent $n $mod 0
        }
        array unset rrPendingMods *
        Debug "Key $code now down, sending down event to all but slot $n"
        BroadcastKeyEvent $n $code 0
    }
}

# Broadcast key down/up to the other windows and the network clients
proc BroadcastKeyEvent {n code up} {
    global rrSentDown
    BroadcastKeyToOther $n $code $up
    if {$up} {
        unset -nocomplain rrSentDown($code)
        SendToClients "UP $code\n"
    } else {
        set rrSentDown($code) 1
        SendToClients "DOWN $code\n"
    }
}

# L/R Shift, Ctrl, Alt and Windows keys
proc IsModifierKey {code} {
    expr {($code >= 0xA0 && $code <= 0xA5) || $code == 0x5B || $code == 0x5C}
}

# Currently held modifiers that are broadcast (not ignored nor pausing broadcast like RCONTROL by default)
proc HeldBroadcastModifiers {} {
    global ignoredKeyCode rrExcludes
    set res {}
    foreach code {0xA0 0xA1 0xA2 0xA3 0xA4 0xA5 0x5B 0x5C} {
        set code [expr {$code}]
        if {[info exists ignoredKeyCode($code)] || [lsearch -exact $rrExcludes $code] >= 0} {
            continue
        }
        if {[twapi::GetAsyncKeyState $code] & 0x8000} {
            lappend res $code
        }
    }
    return $res
}

# Held modifiers that the windows don't (or no longer) have: send them with the next broadcast key
proc PendHeldModifiers {} {
    global rrPendingMods
    foreach code [HeldBroadcastModifiers] {
        set rrPendingMods($code) 1
    }
}

# Windows' own shortcuts (Alt-Tab, Alt-Esc, Ctrl-Esc, Win-anything), not meant for the game windows
proc IsSystemCombo {mask code} {
    expr {($mask & 8) || (($mask & 1) && ($code == 0x09 || $code == 0x1B)) || ($mask == 2 && $code == 0x1B)}
}

# Currently held modifiers as RegisterHotKey's MOD_ALT 1 | MOD_CONTROL 2 | MOD_SHIFT 4 | MOD_WIN 8
proc HeldModifiersMask {} {
    set mask 0
    foreach {vk bit} {0x12 1 0x11 2 0x10 4 0x5B 8 0x5C 8} {
        # high bit is "currently down" (low bit is "pressed since last call")
        if {[twapi::GetAsyncKeyState $vk] & 0x8000} {
            set mask [expr {$mask | $bit}]
        }
    }
    return $mask
}

# --- Skip windows: windows (OMB numbers, so it follows them when swapped) that don't get broadcast keys/clicks

# Windows currently skipped by broadcasting (empty when not configured or toggled off)
proc RRExcludedWindows {} {
    global settings
    if {!$settings(rrExcludeWindowsOn)} {
        return {}
    }
    return $settings(rrExcludeWindows)
}

# Overlay broadcast indicator, e.g. "⟳ -4,5" when skipping windows 4 and 5
proc RRIndicatorLabel {} {
    global settings
    set label $settings(rrIndicator,label)
    set skip [RRExcludedWindows]
    if {[llength $skip]} {
        append label " -[join $skip ,]"
    }
    return $label
}

proc RRExcludeToggle {} {
    global settings
    set settings(rrExcludeWindowsOn) [expr {!$settings(rrExcludeWindowsOn)}]
    RRExcludeUpdate
    SaveSettings
}

# Sync the UI and overlay with the skip windows settings
proc RRExcludeUpdate {} {
    global settings rrExcludeText rrOn rrOnLabel
    set skip $settings(rrExcludeWindows)
    Debug "Skip windows: [join $skip ,] on=$settings(rrExcludeWindowsOn)"
    if {[llength $skip]} {
        set rrExcludeText [join $skip {, }]
        set state normal
    } else {
        set rrExcludeText "None"
        set state disabled
    }
    if {[winfo exists .rrX.cb]} {
        .rrX.cb configure -state $state
    }
    if {$rrOn} {
        set rrOnLabel [RRIndicatorLabel]
        AddMouseToRRLabel
    }
}

# (Re)build the menu each time it's opened, to match the current number of windows
proc RRExcludeMenu {} {
    global settings rrExcludeWin
    set m .rrX.mb.menu
    $m delete 0 end
    array unset rrExcludeWin *
    foreach i $settings(rrExcludeWindows) {
        set rrExcludeWin($i) 1
    }
    for {set i 1} {$i<=$settings(numWindows)} {incr i} {
        if {![info exists rrExcludeWin($i)]} {
            set rrExcludeWin($i) 0
        }
        $m add checkbutton -label "OMB $i" -variable rrExcludeWin($i) -command RRExcludeMenuChange
    }
}

proc RRExcludeMenuChange {} {
    global settings rrExcludeWin
    set had [llength $settings(rrExcludeWindows)]
    set l {}
    foreach i [lsort -integer [array names rrExcludeWin]] {
        if {$rrExcludeWin($i)} {
            lappend l $i
        }
    }
    set settings(rrExcludeWindows) $l
    if {!$had != ![llength $l]} {
        # first window(s) selected (or all removed): turn it on and (un)register its hotkey
        set settings(rrExcludeWindowsOn) 1
        RegisterAllHotkeys
    }
    RRExcludeUpdate
    SaveSettings
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
    RememberGeometry $tw overlayConfigGeometry
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

proc ResetOverlay {} {
    global settings
    for {set i 1} {$i<=$settings(layoutMaxWindows)} {incr i} {
        set t .o$i
        catch {destroy $t}
    }
    Overlay
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
    ResetOverlay
    CheckAutoKill
    Debug "All reset complete: lg $lastGood, fb $firstBad, mx $maxNumW, next $nextWindow"
}

proc SaveLayout {} {
    global settings slot2position scale sot layoutMirrored
    set c .layout.c
    set settings(layoutMirrored) $layoutMirrored
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
    if {[LayoutMirrored]} {
        # moving windows under main doesn't change their stacking order
        StackUnderMain
        RaiseMain
    }
    # mirrors of the new layout positions, or none
    MirrorsRefreshAll
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
    AutoLayout $n $layoutOneSize
    if {$settings(aspectRatio) == "Same" && $n > 0} {
        # redo the layout with the aspect ratio of the smallest window of the "Any" layout
        set minArea 0
        for {set i 1} {$i<=$n} {incr i} {
            lassign [$c coords "wow$i&&wowWindow"] x1 y1 x2 y2
            set area [expr {($x2-$x1)*($y2-$y1)}]
            if {$minArea == 0 || $area < $minArea} {
                set minArea $area
                set aspectRatio [expr {1.0*($x2-$x1)/($y2-$y1)}]
            }
        }
        Debug "Same aspect ratio for all: $aspectRatio"
        $c delete wowAll
        AutoLayout $n $layoutOneSize
    }
    $c scale wowAll 0 0 $scale $scale
    SetupMove
}

proc AutoLayout {n layoutOneSize} {
    global settings monitorInfo aspectRatio
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

# Window size for a xdiv x ydiv grid on a w x h monitor and how good it is:
# its area, not counting width past 21:9.
proc GridWindowSize {w h xdiv ydiv} {
    global aspectRatio
    set ww [expr {int($w/$xdiv)}]
    set wh [expr {int($h/$ydiv)}]
    lassign [ConstrainWindow 0 0 $ww $wh $aspectRatio] v1 v2 ww wh
    return [list $ww $wh [expr {min($ww, $wh*21./9.)*$wh}]]
}

proc CalcSize {monitor numWindows} {
    Debug "CalcSize $numWindows on monitor $monitor"
    global monitorInfo
    set w $monitorInfo($monitor,width)
    set h $monitorInfo($monitor,height)
    # most square grid unless another one gives bigger windows (e.g. 1 column on a portrait monitor)
    lassign [SplitForN $numWindows] xdiv ydiv
    lassign [GridWindowSize $w $h $xdiv $ydiv] ww wh score
    for {set x 1} {$x<=$numWindows} {incr x} {
        set y [expr {($numWindows+$x-1)/$x}]
        lassign [GridWindowSize $w $h $x $y] cw ch cscore
        if {$cscore > $score} {
            Debug "Better grid $x x $y: $cw x $ch instead of $xdiv x $ydiv: $ww x $wh"
            lassign [list $x $y $cw $ch $cscore] xdiv ydiv ww wh score
        }
    }
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
    global mouseFollow settings mouseDelay
    Debug "UpdateMouseFollow $mouseFollow $settings(mouseDelay)"
    SetFocusFollowMouse $mouseFollow
    if {$mouseFollow} {
        SetMouseDelay $settings(mouseDelay)
    } elseif {[info exists mouseDelay]} {
        SetMouseDelay $mouseDelay
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

#---- Mirrors: live, scaled copies of an area of a game window (DWM thumbnails)

# settings(mirrors) is a list of dicts:
#   source: "main" (whichever window is in position 1) or a window number
#   area: {x y w h} part of the source client area, as fractions of its size
#   geom: {x y w h} of the mirror on screen
#   top: stay on top
if {![info exists mirrorEdit]} {
    set mirrorEdit 0
}

# Returns 1 if the binary has cffi (needed to call the DWM functions)
proc MirrorInit {} {
    global env mirrorNoSupport
    if {[info commands ::DwmRegisterThumbnail] ne ""} {
        return 1
    }
    if {[info exists mirrorNoSupport]} {
        return 0
    }
    if {[catch {
        package require cffi
        cffi::Wrapper create ::ombDwmapi [file join $env(windir) system32 dwmapi.dll]
        cffi::Wrapper create ::ombUser32 [file join $env(windir) system32 user32.dll]
        cffi::Struct create ::OmbRECT {left long top long right long bottom long}
        cffi::Struct create ::OmbPOINT {x long y long}
        cffi::Struct create ::OmbDWM_THUMBNAIL_PROPERTIES {
            dwFlags ulong rcDestination struct.OmbRECT rcSource struct.OmbRECT
            opacity uchar fVisible int fSourceClientAreaOnly int
        }
        # HWND/HTHUMBNAIL as 64 bit ints (win64 binary)
        ::ombUser32 stdcall ClientToScreen int {hwnd ulonglong pt {struct.OmbPOINT inout}}
        ::ombDwmapi stdcall DwmUpdateThumbnailProperties long {thumb ulonglong props {struct.OmbDWM_THUMBNAIL_PROPERTIES byref}}
        ::ombDwmapi stdcall DwmUnregisterThumbnail long {thumb ulonglong}
        # last as it's the one checked above
        ::ombDwmapi stdcall DwmRegisterThumbnail long {dest ulonglong src ulonglong thumb {ulonglong out}}
    } err]} {
        Debug "No mirror support: $err"
        set mirrorNoSupport 1
        return 0
    }
    return 1
}

# Old binaries (before v10) can run this script after an update but lack cffi
proc MirrorCheckBinary {} {
    global oldVersion vers
    if {[MirrorInit]} {
        return 1
    }
    set binVers ""
    if {[info exists oldVersion] && $oldVersion ne $vers} {
        set binVers " ($oldVersion)"
    }
    set ans [OmbMessage -type yesno -icon warning -title "Outdated binary for Mirrors" \
        -message "Mirrors need the OpenMultiBoxing v10.0.0 or newer .exe (your .exe$binVers is older and lacks the needed component, only the script got updated).\n\nDownload and extract the latest OpenMultiBoxing zip (Help menu: Get the newest binary release).\n\nOpen the download page now?"]
    if {$ans eq "yes"} {
        Releases
    }
    return 0
}

# Window number currently in layout position p, "" if none
proc SlotAtPosition {p} {
    global slot2position
    foreach {n np} [array get slot2position] {
        if {$np == $p} {
            return $n
        }
    }
    return ""
}

# Window number for a mirror source
proc MirrorSourceSlot {source} {
    if {$source ne "main"} {
        return $source
    }
    set n [SlotAtPosition 1]
    if {$n eq ""} {
        return 1
    }
    return $n
}

# Mirrored layout: all the game windows stacked at the main position, the other positions
# show mirrors of them (swaps don't resize the windows)
proc LayoutMirrored {} {
    global settings mirroredExiting
    expr {$settings(layoutMirrored) && !$settings(layoutStacked) && ![info exists mirroredExiting] && [MirrorInit]}
}

# On exit the mirrors go away: the windows stacked under main go to their layout positions
# (the mirrored layout setting stays on, they get stacked again at the next start)
proc UnstackWindows {} {
    global slot2handle mirroredExiting
    if {![LayoutMirrored]} {
        return
    }
    set mirroredExiting 1
    foreach n [array names slot2handle] {
        CheckWindow [list UpdateN $n] $n
    }
}

# Layout position whose geometry the window in position p actually has
proc RealPosition {p} {
    if {$p != 1 && [LayoutMirrored]} {
        return 1
    }
    return $p
}

# Client size of window n: the layout size we give it (borderless, as for mouse broadcast scaling),
# rather than its current size which lags as windows are resized asynchronously
proc MirrorSourceSize {n} {
    global settings slot2position slot2handle
    if {[info exists slot2position($n)]} {
        set p [RealPosition $slot2position($n)]
        if {[info exists settings($p,size)]} {
            return $settings($p,size)
        }
    }
    twapi::get_window_client_area_size $slot2handle($n)
}

# {left top right bottom} of the biggest cw x ch aspect ratio area centered in w x h
proc MirrorFit {cw ch w h} {
    if {$w*$ch > $h*$cw} {
        # wider: bars on the sides
        set fw [expr {round(1.0*$h*$cw/$ch)}]
        set l [expr {($w-$fw)/2}]
        return [list $l 0 [expr {$l+$fw}] $h]
    }
    set fh [expr {round(1.0*$w*$ch/$cw)}]
    set t [expr {($h-$fh)/2}]
    list 0 $t $w [expr {$t+$fh}]
}

# {left top right bottom} in client pixels of an area given as fractions
proc MirrorSourceRect {area cw ch} {
    lassign $area fx fy fw fh
    list [expr {round($fx*$cw)}] [expr {round($fy*$ch)}] [expr {round(($fx+$fw)*$cw)}] [expr {round(($fy+$fh)*$ch)}]
}

# Edit mode border of about 2 pixels: crops kx/ky source pixels and the matching bx/by mirror pixels
# on each side so the zoom and the content position don't change. {kx ky bx by}
proc MirrorEditInset {sw sh w h} {
    set kx [expr {int(ceil(2.0*$sw/$w))}]
    set ky [expr {int(ceil(2.0*$sh/$h))}]
    if {2*$kx >= $sw || 2*$ky >= $sh} {
        return {0 0 0 0}
    }
    list $kx $ky [expr {round(1.0*$kx*$w/$sw)}] [expr {round(1.0*$ky*$h/$sh)}]
}

proc HwndInt {wh} {
    expr {[lindex $wh 0]}
}

proc MirrorSet {i key value} {
    global settings
    set m [lindex $settings(mirrors) $i]
    dict set m $key $value
    lset settings(mirrors) $i $m
}

proc MirrorSaveSoon {} {
    global mirrorSaveId
    after cancel $mirrorSaveId
    set mirrorSaveId [after 1000 SaveSettings]
}
set mirrorSaveId ""

proc MirrorDetach {i} {
    global mirrorThumb mirrorSrc mirrorLast
    if {[info exists mirrorThumb($i)]} {
        catch {DwmUnregisterThumbnail $mirrorThumb($i)}
        unset mirrorThumb($i)
    }
    unset -nocomplain mirrorSrc($i) mirrorLast($i)
}

proc MirrorHide {i} {
    MirrorDetach $i
    wm withdraw .mirror$i
}

# Clicks go through the mirror unless in edit mode; never takes focus nor shows in the taskbar
proc MirrorClickThrough {t on} {
    set wh [list [expr {[wm frame $t]}] HWND]
    lassign [twapi::get_window_style $wh] style exstyle
    # WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, WS_EX_TRANSPARENT (needs WS_EX_LAYERED, from -alpha)
    set ex [expr {($exstyle | 0x08000080) & ~0x20}]
    if {$on} {
        set ex [expr {$ex | 0x20}]
    }
    twapi::set_window_style $wh $style $ex
}

proc MirrorCreate {i} {
    global settings mirrorEdit
    set t .mirror$i
    set m [lindex $settings(mirrors) $i]
    lassign [dict get $m geom] x y w h
    if {![winfo exists $t]} {
        # background shows as a border in edit mode
        toplevel $t -background $settings(overlayFocusColor) -cursor fleur
        wm overrideredirect $t 1
        wm attributes $t -alpha 0.99
        bind $t <ButtonPress-1> [list MirrorDragStart $i %X %Y]
        bind $t <B1-Motion> [list MirrorDrag $i %X %Y]
        bind $t <Motion> [list MirrorCursor $i %x %y]
        bind $t <ButtonRelease-1> [list MirrorDragEnd $i]
        bind $t <MouseWheel> [list MirrorZoom $i %D]
        bind $t <ButtonPress-3> [list MirrorMenu $i %X %Y]
    }
    wm attributes $t -topmost [dict get $m top]
    wm geometry $t ${w}x$h+$x+$y
    update idletasks
    MirrorClickThrough $t [expr {!$mirrorEdit}]
}

# (Re)attach the mirror to its source window and update its areas
proc MirrorRefresh {i} {
    global settings slot2handle mirrorEdit
    set t .mirror$i
    # (an error here, through UpdateN, would make all the windows lost)
    if {![winfo exists $t] || $i >= [llength $settings(mirrors)]} {
        return
    }
    set m [lindex $settings(mirrors) $i]
    set n [MirrorSourceSlot [dict get $m source]]
    if {!$settings(mirrorsShown) || ![info exists slot2handle($n)]} {
        MirrorHide $i
        return
    }
    set wh $slot2handle($n)
    if {![twapi::window_exists $wh] || [catch {MirrorSourceSize $n} csize]} {
        Debug "Mirror $i source $n gone"
        MirrorHide $i
        return
    }
    lassign $csize cw ch
    if {[wm state $t] ne "normal"} {
        wm deiconify $t
        update idletasks
        MirrorClickThrough $t [expr {!$mirrorEdit}]
    }
    lassign [dict get $m geom] x y w h
    lassign [MirrorSourceRect [dict get $m area] $cw $ch] l tp r bt
    lassign {0 0 0 0} kx ky bx by
    if {$mirrorEdit} {
        lassign [MirrorEditInset [expr {$r-$l}] [expr {$bt-$tp}] $w $h] kx ky bx by
    }
    MirrorThumbnail $i $t $n \
        [list [expr {$l+$kx}] [expr {$tp+$ky}] [expr {$r-$kx}] [expr {$bt-$ky}]] \
        [list $bx $by [expr {$w-$bx}] [expr {$h-$by}]]
}

# Shows the src {left top right bottom} client area of window n in the dst area of toplevel t,
# for mirror i (an index in settings(mirrors), or L<position> for the mirrored layout ones)
proc MirrorThumbnail {i t n src dst} {
    global slot2handle mirrorThumb mirrorSrc mirrorLast
    set hwnd [HwndInt $slot2handle($n)]
    if {![info exists mirrorSrc($i)] || $mirrorSrc($i) != $hwnd} {
        MirrorDetach $i
        set hr [DwmRegisterThumbnail [expr {[wm frame $t]}] $hwnd thumb]
        if {$hr != 0} {
            Debug "Mirror $i DwmRegisterThumbnail error $hr"
            return
        }
        set mirrorThumb($i) $thumb
        set mirrorSrc($i) $hwnd
        Debug "Mirror $i now showing OMB $n"
    }
    # skip if unchanged
    set key [list $src $dst]
    if {[info exists mirrorLast($i)] && $mirrorLast($i) eq $key} {
        return
    }
    set mirrorLast($i) $key
    lassign $src sl st sr sb
    lassign $dst dl dt dr db
    set props [dict create dwFlags 0x1f \
        rcDestination [dict create left $dl top $dt right $dr bottom $db] \
        rcSource [dict create left $sl top $st right $sr bottom $sb] \
        opacity 255 fVisible 1 fSourceClientAreaOnly 1]
    DwmUpdateThumbnailProperties $mirrorThumb($i) $props
}

# Mirrors of the windows stacked under the main one, in their layout positions (2 and up)
proc LayoutMirrorsRefresh {} {
    global settings slot2handle
    set on [LayoutMirrored]
    foreach t [winfo children .] {
        if {[regexp {^\.lmirror(\d+)$} $t -> p] && (!$on || $p > $settings(numWindows))} {
            MirrorDetach L$p
            destroy $t
        }
    }
    if {!$on} {
        return
    }
    set created 0
    for {set p 2} {$p <= $settings(numWindows)} {incr p} {
        if {![ValidWindowSettingsN $p]} {
            continue
        }
        set t .lmirror$p
        lassign $settings($p,posXY) x y
        lassign $settings($p,size) w h
        set top 0
        if {[info exists settings($p,stayOnTop)]} {
            set top $settings($p,stayOnTop)
        }
        if {![winfo exists $t]} {
            toplevel $t -background black -cursor hand2
            wm overrideredirect $t 1
            wm attributes $t -alpha 0.99
            bind $t <ButtonPress-1> [list LayoutMirrorClick $p %x %y]
            wm geometry $t ${w}x$h+$x+$y
            update idletasks
            MirrorClickThrough $t 0
            set created 1
        }
        wm attributes $t -topmost $top
        if {[wm geometry $t] ne "${w}x$h+$x+$y"} {
            wm geometry $t ${w}x$h+$x+$y
        }
        set n [SlotAtPosition $p]
        if {$n eq "" || ![info exists slot2handle($n)] || ![twapi::window_exists $slot2handle($n)]
                || [catch {MirrorSourceSize $n} csize]} {
            MirrorDetach L$p
            wm withdraw $t
            continue
        }
        if {[wm state $t] ne "normal"} {
            wm deiconify $t
            update idletasks
            MirrorClickThrough $t 0
        }
        lassign $csize cw ch
        MirrorThumbnail L$p $t $n [list 0 0 $cw $ch] [MirrorFit $cw $ch $w $h]
    }
    if {$created} {
        UpdateHandles
    }
}

# Clicking a mirror of the mirrored layout makes that window the main one, with the mouse
# at the same place in it
proc LayoutMirrorClick {p x y} {
    global settings
    set n [SlotAtPosition $p]
    if {$n eq ""} {
        return
    }
    SetAsMain $n
    if {![ValidWindowSettingsN 1] || [catch {MirrorSourceSize $n} csize]} {
        return
    }
    lassign $settings(1,posXY) mx my
    lassign [MirrorToSource $x $y {*}$settings($p,size) {*}$csize] sx sy
    twapi::move_mouse [expr {$mx+$sx}] [expr {$my+$sy}]
}

# Source client coordinates of x,y in a w x h mirror of a whole cw x ch window (letterboxed)
proc MirrorToSource {x y w h cw ch} {
    lassign [MirrorFit $cw $ch $w $h] l t r b
    set fx [expr {min(1.0, max(0.0, 1.0*($x-$l)/($r-$l)))}]
    set fy [expr {min(1.0, max(0.0, 1.0*($y-$t)/($b-$t)))}]
    list [expr {min($cw-1, round($fx*$cw))}] [expr {min($ch-1, round($fy*$ch))}]
}

# In the mirrored layout, the main window goes on top of the ones stacked under it
proc RaiseMain {} {
    global slot2handle
    set n [SlotAtPosition 1]
    if {$n eq "" || ![info exists slot2handle($n)]} {
        return
    }
    # HWND_TOP, SWP_NOSIZE|SWP_NOMOVE|SWP_NOACTIVATE|SWP_NOOWNERZORDER|SWP_NOSENDCHANGING|SWP_ASYNCWINDOWPOS
    twapi::SetWindowPos $slot2handle($n) 0 0 0 0 0 0x4613
}

# Puts game window wh just under the main one (always allowed, unlike raising main above
# another process' foreground window)
proc LowerUnderMain {wh} {
    global slot2handle
    set n [SlotAtPosition 1]
    if {$n eq "" || ![info exists slot2handle($n)] || $slot2handle($n) eq $wh} {
        return
    }
    twapi::SetWindowPos $wh $slot2handle($n) 0 0 0 0 0x4613
}

proc StackUnderMain {} {
    global slot2handle
    foreach {n wh} [array get slot2handle] {
        LowerUnderMain $wh
    }
}

proc MirrorsRefreshAll {} {
    LayoutMirrorsRefresh
    if {[info commands ::DwmRegisterThumbnail] eq ""} {
        return
    }
    for {set i 0} {[winfo exists .mirror$i]} {incr i} {
        MirrorRefresh $i
    }
}

# Recreate all the mirrors from the settings (startup, profile change, deletion)
proc MirrorsRebuild {} {
    global settings
    for {set i 0} {[winfo exists .mirror$i]} {incr i} {
        MirrorDetach $i
        destroy .mirror$i
    }
    if {[llength $settings(mirrors)] == 0} {
        return
    }
    if {![MirrorInit]} {
        Debug "Mirrors configured but not supported by this binary"
        return
    }
    for {set i 0} {$i < [llength $settings(mirrors)]} {incr i} {
        MirrorCreate $i
        MirrorRefresh $i
    }
    UpdateHandles
}

proc MirrorsEdit {on} {
    global mirrorEdit
    set mirrorEdit $on
    for {set i 0} {[winfo exists .mirror$i]} {incr i} {
        if {[wm state .mirror$i] eq "normal"} {
            MirrorClickThrough .mirror$i [expr {!$on}]
        }
    }
    MirrorsRefreshAll
    if {!$on} {
        SaveSettings
    }
}

proc MirrorsEditToggle {} {
    global mirrorEdit
    MirrorsEdit [expr {!$mirrorEdit}]
}

proc MirrorsToggle {} {
    global settings
    set settings(mirrorsShown) [expr {!$settings(mirrorsShown)}]
    MirrorsRefreshAll
}

# Sides (some of l r t b) of a w x h mirror near local x,y
proc MirrorEdges {x y w h} {
    set e [expr {min(8, $w/4, $h/4)}]
    set edges ""
    if {$x < $e} {
        append edges l
    } elseif {$x >= $w-$e} {
        append edges r
    }
    if {$y < $e} {
        append edges t
    } elseif {$y >= $h-$e} {
        append edges b
    }
    return $edges
}

proc MirrorCursor {i x y} {
    global mirrorDrag
    if {$mirrorDrag ne ""} {
        return
    }
    set t .mirror$i
    switch [MirrorEdges $x $y [winfo width $t] [winfo height $t]] {
        l - r {set c size_we}
        t - b {set c size_ns}
        lt - rb {set c size_nw_se}
        rt - lb {set c size_ne_sw}
        default {set c fleur}
    }
    $t configure -cursor $c
}

# Moving dx,dy screen pixels the edges of a mirror: same zoom, the source area grows or shrinks
# by whole source pixels (no zoom wobble), within the cw x ch source window. Returns the new {geom area}
proc MirrorEdgeDrag {edges geom area cw ch dx dy} {
    lassign $geom x y w h
    lassign $area fx fy fw fh
    # mirror pixels per source pixel
    set zx [expr {$w/($fw*$cw)}]
    set zy [expr {$h/($fh*$ch)}]
    # in source pixels
    set dx [expr {round($dx/$zx)}]
    set dy [expr {round($dy/$zy)}]
    set minx [expr {int(ceil(16/$zx))}]
    set miny [expr {int(ceil(16/$zy))}]
    set sw [expr {round($fw*$cw)}]
    set sh [expr {round($fh*$ch)}]
    if {[string match *l* $edges]} {
        set dx [expr {max(-round($fx*$cw), min($dx, $sw-$minx))}]
        set fx [expr {$fx+1.0*$dx/$cw}]
        set fw [expr {$fw-1.0*$dx/$cw}]
        set x [expr {$x+$dx*$zx}]
    } elseif {[string match *r* $edges]} {
        set dx [expr {min(round((1-$fx-$fw)*$cw), max($dx, $minx-$sw))}]
        set fw [expr {$fw+1.0*$dx/$cw}]
    }
    if {[string match *t* $edges]} {
        set dy [expr {max(-round($fy*$ch), min($dy, $sh-$miny))}]
        set fy [expr {$fy+1.0*$dy/$ch}]
        set fh [expr {$fh-1.0*$dy/$ch}]
        set y [expr {$y+$dy*$zy}]
    } elseif {[string match *b* $edges]} {
        set dy [expr {min(round((1-$fy-$fh)*$ch), max($dy, $miny-$sh))}]
        set fh [expr {$fh+1.0*$dy/$ch}]
    }
    set w [expr {$fw*$cw*$zx}]
    set h [expr {$fh*$ch*$zy}]
    list [list [expr {round($x)}] [expr {round($y)}] [expr {round($w)}] [expr {round($h)}]] [list $fx $fy $fw $fh]
}

# Source area of mirror i in pixels {w h} (error if the source is gone)
proc MirrorSourcePixels {i} {
    global settings
    set m [lindex $settings(mirrors) $i]
    lassign [MirrorSourceRect [dict get $m area] {*}[MirrorSourceSize [MirrorSourceSlot [dict get $m source]]]] l t r b
    list [expr {$r-$l}] [expr {$b-$t}]
}

# Current zoom of mirror i, relative to the source window at its current size
proc MirrorZoomOf {i} {
    global settings
    lassign [MirrorSourcePixels $i] sw
    lassign [dict get [lindex $settings(mirrors) $i] geom] x y w
    expr {1.0*$w/$sw}
}

# Next (dir>0) or previous round zoom from z, for the edit mode mouse wheel only (mirrors can have any zoom)
proc MirrorNextZoom {z dir} {
    set mirrorZooms [list 0.1 0.2 0.25 [expr {1/3.}] 0.5 [expr {2/3.}] 0.75 1 1.25 1.5 1.75 2 2.5 3 3.5 4 5 6 8]
    if {$dir > 0} {
        foreach s $mirrorZooms {
            if {$s > $z*1.01} {
                return $s
            }
        }
        return [lindex $mirrorZooms end]
    }
    foreach s [lreverse $mirrorZooms] {
        if {$s < $z/1.01} {
            return $s
        }
    }
    return [lindex $mirrorZooms 0]
}

proc MirrorSetZoom {i z} {
    if {[catch {MirrorSourcePixels $i} spx]} {
        return
    }
    lassign $spx sw sh
    MirrorResize $i [expr {max(16, round($sw*$z))}] [expr {max(16, round($sh*$z))}]
}

# Drag from the middle moves the mirror, from a side changes the area
proc MirrorDragStart {i x y} {
    global mirrorDrag settings
    set t .mirror$i
    set m [lindex $settings(mirrors) $i]
    set edges [MirrorEdges [expr {$x-[winfo rootx $t]}] [expr {$y-[winfo rooty $t]}] [winfo width $t] [winfo height $t]]
    set csize {0 0}
    if {$edges ne "" && [catch {MirrorSourceSize [MirrorSourceSlot [dict get $m source]]} csize]} {
        set edges ""
    }
    set mirrorDrag [list $x $y [winfo rootx $t] [winfo rooty $t] $edges [dict get $m geom] [dict get $m area] {*}$csize]
}

proc MirrorDrag {i x y} {
    global mirrorDrag
    if {$mirrorDrag eq ""} {
        return
    }
    lassign $mirrorDrag mx my wx wy edges geom area cw ch
    if {$edges eq ""} {
        wm geometry .mirror$i +[expr {$wx+$x-$mx}]+[expr {$wy+$y-$my}]
        return
    }
    lassign [MirrorEdgeDrag $edges $geom $area $cw $ch [expr {$x-$mx}] [expr {$y-$my}]] ngeom narea
    MirrorSet $i geom $ngeom
    MirrorSet $i area $narea
    lassign $ngeom nx ny nw nh
    wm geometry .mirror$i ${nw}x$nh+$nx+$ny
    MirrorRefresh $i
}

proc MirrorDragEnd {i} {
    global settings mirrorDrag
    if {$mirrorDrag eq ""} {
        return
    }
    if {[lindex $mirrorDrag 4] eq ""} {
        lassign [dict get [lindex $settings(mirrors) $i] geom] x y w h
        MirrorSet $i geom [list [winfo rootx .mirror$i] [winfo rooty .mirror$i] $w $h]
    }
    set mirrorDrag ""
    MirrorSaveSoon
}
set mirrorDrag ""

proc MirrorResize {i w h} {
    global settings
    lassign [dict get [lindex $settings(mirrors) $i] geom] x y
    MirrorSet $i geom [list $x $y $w $h]
    wm geometry .mirror$i ${w}x$h
    MirrorRefresh $i
    MirrorSaveSoon
}

# Mouse wheel zoom, to the next/previous round zoom
proc MirrorZoom {i delta} {
    if {[catch {MirrorZoomOf $i} z]} {
        return
    }
    MirrorSetZoom $i [MirrorNextZoom $z $delta]
}

proc MirrorMenu {i x y} {
    global settings mirrorMenuSource mirrorMenuTop
    set mn .mirrorMenu
    destroy $mn
    menu $mn -tearoff 0
    set m [lindex $settings(mirrors) $i]
    set mirrorMenuSource [dict get $m source]
    set mirrorMenuTop [dict get $m top]
    $mn add command -label "Select area again..." -command [list MirrorSelect $i]
    set label Zoom
    if {![catch {MirrorZoomOf $i} z]} {
        # relative to the source as it currently is (smaller when in a small layout position)
        set label [format "Zoom (now %.2fx of OMB %s)" $z [MirrorSourceSlot $mirrorMenuSource]]
    }
    menu $mn.zoom -tearoff 0
    foreach z {0.5 1 1.5 2 3 4} {
        $mn.zoom add command -label "${z}x" -command [list MirrorSetZoom $i $z]
    }
    $mn add cascade -label $label -menu $mn.zoom
    $mn add checkbutton -label "Stay on top" -variable mirrorMenuTop -command [list MirrorChangeTop $i]
    $mn add separator
    $mn add radiobutton -label "Source: main window" -value main -variable mirrorMenuSource -command [list MirrorChangeSource $i]
    for {set n 1} {$n <= $settings(numWindows)} {incr n} {
        $mn add radiobutton -label "Source: OMB $n" -value $n -variable mirrorMenuSource -command [list MirrorChangeSource $i]
    }
    $mn add separator
    $mn add command -label "Delete" -command [list MirrorDelete $i]
    $mn add command -label "Done editing" -command {MirrorsEdit 0}
    tk_popup $mn $x $y
}

proc MirrorChangeSource {i} {
    global mirrorMenuSource
    MirrorSet $i source $mirrorMenuSource
    MirrorRefresh $i
    MirrorSaveSoon
}

proc MirrorChangeTop {i} {
    global mirrorMenuTop
    MirrorSet $i top $mirrorMenuTop
    wm attributes .mirror$i -topmost $mirrorMenuTop
    MirrorSaveSoon
}

proc MirrorDelete {i} {
    global settings
    set settings(mirrors) [lreplace $settings(mirrors) $i $i]
    MirrorsRebuild
    SaveSettings
}

# Semi transparent toplevel t over the client area of game window n, with a centered text.
# Returns the client area {x y w h} on screen
proc MirrorOverlay {t n cursor text} {
    global slot2handle
    set wh $slot2handle($n)
    set pt [dict create x 0 y 0]
    ClientToScreen [HwndInt $wh] pt
    lassign [twapi::get_window_client_area_size $wh] cw ch
    set x [dict get $pt x]
    set y [dict get $pt y]
    destroy $t
    toplevel $t -cursor $cursor
    wm overrideredirect $t 1
    wm attributes $t -topmost 1 -alpha 0.4
    wm geometry $t ${cw}x$ch+$x+$y
    canvas $t.c -background gray20 -highlightthickness 0
    pack $t.c -fill both -expand 1
    $t.c create text [expr {$cw/2}] [expr {$ch/2}] -fill white -font WOBBold -justify center -text $text -tags label
    list $x $y $cw $ch
}

proc MirrorPickClose {} {
    foreach t [winfo children .] {
        if {[string match .mirrorPick* $t]} {
            destroy $t
        }
    }
}

# Windows all at the main position (only the one on top can be picked)
proc MirrorPickStacked {} {
    global settings
    expr {$settings(layoutStacked) || [LayoutMirrored]}
}

proc MirrorPickText {n} {
    set s "OMB $n\nClick to mirror an area of this window"
    if {[MirrorPickStacked]} {
        append s "\n(swap first to mirror another one)"
    }
    append s "\n(Escape to cancel)"
}

# Step 1 of adding a mirror: an overlay on each game window, click one to then select its area
proc MirrorPick {} {
    global slot2handle
    if {![MirrorCheckBinary]} {
        return
    }
    MirrorPickClose
    set t ""
    foreach n [array names slot2handle] {
        if {![MirrorPickStacked]} {
            set t .mirrorPick$n
        } elseif {$n eq [SlotAtPosition 1]} {
            set t .mirrorPickMain
        } else {
            continue
        }
        if {[catch {MirrorOverlay $t $n hand2 [MirrorPickText $n]} err]} {
            Debug "Mirror pick OMB $n: $err"
            destroy $t
            continue
        }
        bind $t.c <ButtonRelease-1> "MirrorPickClose; MirrorSelect {} $n"
        bind $t <Escape> MirrorPickClose
    }
    update
    if {[winfo exists $t]} {
        focus -force $t.c
    } else {
        OmbError "No window to mirror" "No OMB window could be found, there is nothing to mirror"
    }
}

# Stacked windows: the pick overlay is for the window now on top
proc MirrorPickSwapped {} {
    set t .mirrorPickMain
    set n [SlotAtPosition 1]
    if {![winfo exists $t] || $n eq ""} {
        return
    }
    $t.c itemconfigure label -text [MirrorPickText $n]
    bind $t.c <ButtonRelease-1> "MirrorPickClose; MirrorSelect {} $n"
    raise $t
}

# Transparent overlay on the source window to drag the area to mirror. i is the mirror to change,
# empty to add a new one of window n
proc MirrorSelect {i {n ""}} {
    global settings slot2handle mirrorSelect
    if {![MirrorCheckBinary]} {
        return
    }
    if {$i eq ""} {
        # new mirrors stay on the window they were taken from (right click to follow main instead)
        set source $n
    } else {
        set source [dict get [lindex $settings(mirrors) $i] source]
        set n [MirrorSourceSlot $source]
    }
    if {![info exists slot2handle($n)]} {
        OmbError "No window to mirror" "OMB $n isn't captured, there is nothing to mirror"
        return
    }
    set t .mirrorSel
    if {[catch {MirrorOverlay $t $n crosshair "Drag a rectangle around the area of OMB $n to mirror\n(Escape to cancel)"} rect]} {
        destroy $t
        OmbError "No window to mirror" "OMB $n can't be found: $rect"
        return
    }
    set mirrorSelect [list $i $source {*}$rect]
    bind $t.c <ButtonPress-1> {
        set mirrorSelStart [list %x %y]
        .mirrorSel.c delete sel
        .mirrorSel.c create rectangle %x %y %x %y -outline red -width 2 -tags sel
    }
    bind $t.c <B1-Motion> {.mirrorSel.c coords sel {*}$mirrorSelStart %x %y}
    bind $t.c <ButtonRelease-1> {MirrorSelectDone {*}$mirrorSelStart %x %y}
    bind $t <Escape> {destroy .mirrorSel}
    update
    focus -force $t.c
}

proc MirrorSelectDone {x1 y1 x2 y2} {
    global settings mirrorSelect
    set w [expr {abs($x2-$x1)}]
    set h [expr {abs($y2-$y1)}]
    if {$w < 4 || $h < 4} {
        return
    }
    destroy .mirrorSel
    lassign $mirrorSelect i source sx sy cw ch
    set l [expr {min($x1,$x2)}]
    set t [expr {min($y1,$y2)}]
    set area [list [expr {1.0*$l/$cw}] [expr {1.0*$t/$ch}] [expr {1.0*$w/$cw}] [expr {1.0*$h/$ch}]]
    Debug "Mirror $i of $source area $area"
    if {$i eq ""} {
        # 1:1, shifted from the source area so it's visible, to be moved in edit mode
        lappend settings(mirrors) [dict create source $source area $area \
            geom [list [expr {$sx+$l+30}] [expr {$sy+$t+30}] $w $h] top 1]
        set settings(mirrorsShown) 1
        MirrorsRebuild
        MirrorsEdit 1
    } else {
        # keep the width, new aspect ratio
        MirrorSet $i area $area
        lassign [dict get [lindex $settings(mirrors) $i] geom] x y mw
        MirrorResize $i $mw [expr {max(16, round(1.0*$mw*$h/$w))}]
    }
    SaveSettings
}

proc MirrorsDialog {} {
    global settings mirrorEdit
    if {![MirrorCheckBinary]} {
        return
    }
    set tw .mirrors
    if {![winfo exists $tw]} {
        toplevel $tw
        wm title $tw "OMB Mirrors"
        wm resizable $tw 0 0
        RememberGeometry $tw mirrorsGeometry
        wm protocol $tw WM_DELETE_WINDOW MirrorsDialogClose
        set help "Mirrors are live copies of an area of a game window, e.g. the minimap.\n"
        append help "They show the window they were taken from, wherever it is\n"
        append help "(or whichever window is main: right click, Source: main window).\n"
        append help "While this window is open (edit mode), drag mirrors to move them,\n"
        append help "drag their sides to extend or shrink the mirrored area,\n"
        append help "use the mouse wheel to zoom and right click for options.\n"
        append help "Otherwise mirrors let mouse clicks through."
        grid [ttk::label $tw.l -justify left -text $help] -padx 8 -pady 6 -sticky w
        grid [ttk::button $tw.add -text "Add a mirror: click a window, then drag the area to mirror..." -command MirrorPick] -padx 8 -pady 4 -sticky we
        grid [ttk::checkbutton $tw.edit -text "Edit mode" -variable mirrorEdit -command {MirrorsEdit $mirrorEdit}] -padx 8 -sticky w
        grid [ttk::checkbutton $tw.shown -text "Show mirrors" -variable settings(mirrorsShown) -command "MirrorsRefreshAll; SaveSettings"] -padx 8 -sticky w
        grid [ttk::button $tw.close -text Close -command MirrorsDialogClose] -padx 8 -pady 6
        UpdateHandles
    }
    wm state $tw normal
    raise $tw
    MirrorsEdit 1
}

proc MirrorsDialogClose {} {
    destroy .mirrors
    MirrorsEdit 0
}

#---- settings and initial setup

# default hotkeys (change/add more in you OpenMultiBoxingSettings.tcl)
for {set i 1} {$i<=12} {incr i} {
    set settings(hk$i,focus) "Ctrl-F$i"
    set settings(hk$i,swap) "Ctrl-Shift-F$i"
}

array set settings {
    hk,capture "Ctrl-Shift-C"
    hk,mouseTrack "Ctrl-Shift-Alt-M"
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
    layoutMirrored 0
    layoutScale "1/6"
    layoutSnap 4
    layoutMaxWindows 32
    layoutAuto 1
    layoutTop 0
    showOverlay 1
    overlayFocusColor "#0080ff"
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
    profilesNotRotated {"Default"}
    hk,nextProfile "Ctrl-Shift-L"
    hk,previousProfile "Ctrl-Shift-Alt-L"
    borderless 1
    rrKeyListExclude "W A S D"
    rrModExcludeList "RCONTROL RSHIFT RALT"
    rrInterval 5
    rrAlwaysFocus 1
    autoResetFocusToMain 1
    hk,rrToggle "Ctrl-Shift-R"
    hk,rrExcludeToggle "Ctrl-Shift-E"
    rrExcludeWindows {}
    rrExcludeWindowsOn 1
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
    hk,mouseBroadcast "Ctrl-Shift-M"
    mouseBroadcastDelay 30
    mouseHoldCancel 500
    mouseBroadcastUsePostMessage 1
    mouseBroadcastNetTrack 1
    rrDeferModifiers 1
    broadcastDelay 0
    broadcastDelayModifiersFlush 0
    connectTo ""
    listenPort 4464
    listen 0
    mirrors {}
    mirrorsShown 1
    hk,mirrorsToggle ""
    hk,mirrorsEdit ""
}

set settings(mouseInsideGameWindowFocuses) [expr {$hasRR||$hasBR}]
array set hotkeyDefaults [array get settings hk*,*]


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

set savedWindowList {}
if {$isUpdate} {
    # Recreate the menu and main window so new/changed UI elements show up without a restart,
    # keeping the captured windows list
    Debug "Rebuilding menu and main window after update"
    if {[winfo exists .lbw]} {
        set savedWindowList [.lbw get 0 end]
    }
    . configure -menu {}
    catch {destroy .mbar}
    foreach w [grid slaves .] {
        destroy $w
    }
}

MenuSetup

# Make it so the code can be reloaded without errors
if {![winfo exists .logo]} {
    if {[lsearch -exact [font names] WOBBold] < 0} {
        font create WOBBold {*}[font actual [::ttk::style lookup TButton -font]]
        font configure WOBBold -weight bold
    }
    UISetup
    if {[llength $savedWindowList]} {
        .lbw insert end {*}$savedWindowList
    }
    set mouseTrackOn ""
    updateIndex
    # Save settings once
    SaveSettings
}

# First launch: wide enough for the menu bar to fit on one line (can still be made narrower)
proc FitMenuBar {} {
    update idletasks
    # Windows menu bar items are their label plus about one character and a pixel on each side
    set pad [expr {2*[font measure TkMenuFont 0]+2}]
    set w $pad
    for {set i 0} {$i <= [.mbar index end]} {incr i} {
        if {[.mbar type $i] eq "cascade"} {
            set w [expr {$w + [font measure TkMenuFont [.mbar entrycget $i -label]] + $pad}]
        }
    }
    if {$w > [winfo reqwidth .]} {
        Debug "Widening main window from [winfo reqwidth .] to $w for the menu bar"
        wm geometry . ${w}x[winfo reqheight .]
    }
}

# --- main / tweak me ---
puts "OpenMultiBoxing $vers started..."
Defer 100 FindExisting
set bottomText "OpenMultiBoxing $vers"
wm state . normal
if {![RememberGeometry . mainWindowGeometry 1]} {
    FitMenuBar
}
# -debug console position (in its own interpreter)
if {$forceDebug && ![catch {console eval {winfo exists .}}]} {
    if {[info exists settings(consoleGeometry)] && [GeometryOnScreen $settings(consoleGeometry)]} {
        catch {console eval [list wm geometry . $settings(consoleGeometry)]}
    }
    catch {console eval {bind . <Configure> {consoleinterp eval [list set settings(consoleGeometry) [wm geometry .]]}}}
}

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
Defer 400 MirrorsRebuild

# For now not using cffi as it doesn't read full keyboard state anyway
#Defer 300 CheckBinary

Defer 500 NetworkSetup
