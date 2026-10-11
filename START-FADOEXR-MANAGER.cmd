@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0Tools\Ensure-Windows-Dependencies.ps1" (
  echo Missing Tools\Ensure-Windows-Dependencies.ps1. Please update the complete repository.
  pause
  exit /b 1
)
rem Side-by-side Python 3.13; auto-install missing tools with winget.
rem Check a winget-managed FFmpeg for updates at most once every 7 days.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Ensure-Windows-Dependencies.ps1" -InstallMissing -UpgradeFFmpeg -LaunchManager
if errorlevel 1 (
  echo.
  echo FadoEXR could not start. See the dependency log printed above.
  echo You can run Tools\CHECK-DEPENDENCIES.cmd or Tools\SETUP-DEPENDENCIES.cmd.
  pause
  exit /b 1
)
exit /b 0
