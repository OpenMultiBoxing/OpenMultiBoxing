@echo off
REM    Starts several WoW windows at once, without Battle.net (you then log in
REM    each window). Each window gets its own WoW settings file (window size,
REM    graphics, remembered account name...). Read LaunchWoW.txt for details.
REM
REM    IMPORTANT, before the first use: start WoW normally (from Battle.net), set
REM    it up the way you want every window to start (Windowed mode, graphics,
REM    sound...) and exit it. The windows' settings start as a copy of that.
REM
REM    To change the values below: right click this file, Edit (or Edit in
REM    Notepad), change what's after the = signs, save. Lines starting with REM
REM    are just comments.
REM
REM How many WoW windows to start
set HOWMANY=5
REM Where WoW is installed, ending with the version you play (_retail_,
REM _classic_, _forever_...)
set WOWDIR=C:\Program Files (x86)\World of Warcraft\_retail_
REM The game program: Wow.exe (Retail, _forever_) or WowClassic.exe (Classic)
set BIN=Wow.exe
REM A name for this set of windows: use a different one in a copy of this file
REM for each team (different accounts)
set TEAM=WOB
echo Will launch %HOWMANY% %BIN% in WOWDIR=%WOWDIR%
FOR /L %%i IN (1,1,%HOWMANY%) DO (
    echo Launching #%%i
    IF NOT EXIST "%WOWDIR%\WTF\Config-%TEAM%%%i.wtf" copy "%WOWDIR%\WTF\Config.wtf" "%WOWDIR%\WTF\Config-%TEAM%%%i.wtf" >NUL
    start "" "%WOWDIR%\%BIN%" -config Config-%TEAM%%%i.wtf
    REM If your windows don't always come up in order (window 1 first...), use
    REM File menu "Close all games..." and run this again. If that doesn't help,
    REM remove the REM and the space in front of the next line: it waits 1
    REM second between windows.
    REM timeout /t 1 >NUL
)
