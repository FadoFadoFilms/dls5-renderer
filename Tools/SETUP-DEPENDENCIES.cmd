@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Ensure-Windows-Dependencies.ps1" -InstallMissing -UpgradeFFmpeg -ForceUpgradeCheck
set "result=%errorlevel%"
echo.
if "%result%"=="0" (echo FadoEXR requirements are ready.) else (echo Setup could not finish. Read the dependency log above.)
pause
exit /b %result%
