@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
  echo.
  echo Drag a video file onto RUN-DROP-VIDEO-HERE.bat
  echo or double-click it and choose a video from the file picker.
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RTX2060-DLSS5-Offline-Test.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RTX2060-DLSS5-Offline-Test.ps1" -InputVideo "%~f1"
)
echo.
echo Test finished. See the results folder for REPORT.md and logs.
pause
