@echo off
setlocal
cd /d "%~dp0"
echo.
echo ================================================================
echo  RTX 2060 - Download / Update DLSS 5 Video Player
 echo ================================================================
echo  Official upstream: github.com/2600th/dlss5-video-player
 echo  This includes the modified, unsigned community neural runtime.
echo  Download may be 400 MB or more, depending on the latest release.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Download-Latest-Renderer.ps1"
set "status=%ERRORLEVEL%"
echo.
if not "%status%"=="0" (
  echo UPDATE FAILED ^(code %status%^). See update-logs in the install folder.
) else (
  echo Ready. You can launch DLSS Player or Run Probe Only.
)
echo.
pause
exit /b %status%
