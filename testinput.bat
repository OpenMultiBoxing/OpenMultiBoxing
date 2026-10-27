@echo off
rem Opens 3 "Key test" text windows to try key broadcasting without a game (headless conhost: no console windows)
rem In OMB: add "Key test*" as a game window title, capture, click once in each window, turn broadcast on, type.
for /l %%i in (1,1,3) do start "" conhost --headless powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0testinput.ps1"
