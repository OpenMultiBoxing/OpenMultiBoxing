@echo off
REM    Launches HOWMANY copies of WoW directly (without the Battle.net launcher,
REM    which is the recommended way as it avoids typing passwords), each with its
REM    own config file WTF\Config-<TEAM><number>.wtf (window size, account name,
REM    graphics...). See LaunchWoW.txt for how it works.
REM
REM    IMPORTANT: the first time, each window's config is a copy of your current
REM    WTF\Config.wtf, so first set up your basic settings in WoW (windowed mode,
REM    graphics, sound...) launched normally, exit it, then run this.
REM
REM    Right click, Edit, to change the variables to match your setup.
REM
REM How many wow to launch?
set HOWMANY=5
REM Where to find and which wow (_retail_, _classic_, _forever_,...)
set WOWDIR=C:\Program Files (x86)\World of Warcraft\_retail_
REM Exe name: Wow.exe or WowClassic.exe
set BIN=Wow.exe
REM Suffix, change if you want different team profiles
set TEAM=WOB
echo Will launch %HOWMANY% %BIN% in WOWDIR=%WOWDIR%
FOR /L %%i IN (1,1,%HOWMANY%) DO (
    echo Launching #%%i
    IF NOT EXIST "%WOWDIR%\WTF\Config-%TEAM%%%i.wtf" copy "%WOWDIR%\WTF\Config.wtf" "%WOWDIR%\WTF\Config-%TEAM%%%i.wtf" >NUL
    start "" "%WOWDIR%\%BIN%" -config Config-%TEAM%%%i.wtf
    REM If your windows don't always come up in order (window 1 first...), which
    REM sometimes happens because of caching or a slow first start: File menu
    REM "Close All Games" and run this again. If that doesn't help, un comment
    REM (remove the REM in front of) the next line, to wait 1 second between windows:
    REM timeout /t 1 >NUL
)
