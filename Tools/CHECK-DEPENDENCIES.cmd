@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Ensure-Windows-Dependencies.ps1" -CheckOnly
set "result=%errorlevel%"
echo.
if "%result%"=="0" (echo Required dependencies found.) else (echo Required dependencies missing or incompatible.)
pause
exit /b %result%
