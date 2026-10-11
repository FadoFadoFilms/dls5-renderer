@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RTX2060-DLSS5-Offline-Test.ps1" -ProbeOnly
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RTX2060-DLSS5-Offline-Test.ps1" -InputVideo "%~f1" -ProbeOnly
)
echo.
echo Probe finished. See the results folder for REPORT.md and logs.
pause
