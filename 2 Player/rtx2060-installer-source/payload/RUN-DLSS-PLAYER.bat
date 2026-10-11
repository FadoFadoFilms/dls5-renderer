@echo off
setlocal
set "player=%~dp0upstream\DLSSVideoPlayer.exe"
if not exist "%player%" (
  echo DLSS Video Player is not installed yet.
  echo Run "Update Renderer" from the Start Menu to download the latest release.
  echo.
  pause
  exit /b 1
)
start "" "%player%"
