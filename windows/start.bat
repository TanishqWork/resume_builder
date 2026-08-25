@echo off
REM Double-click launcher for start.ps1.
REM -ExecutionPolicy Bypass applies to THIS process only - it changes nothing
REM system-wide, so no admin rights and no policy change are needed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
echo.
pause
