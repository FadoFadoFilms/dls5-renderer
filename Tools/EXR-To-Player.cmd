@echo off
setlocal
set "SHOT=%~1"
if "%SHOT%"=="" (
 echo Drag the captured shot folder onto this batch file or enter its path:
 set /p "SHOT=Shot folder: "
)
where python >nul 2>nul
if errorlevel 1 ( echo Python 3 is required on PATH & pause & exit /b 1 )
where ffmpeg >nul 2>nul
if errorlevel 1 ( echo FFmpeg is required on PATH & pause & exit /b 1 )
python "%~dp0exr_to_player.py" "%SHOT%" --fps 24
if errorlevel 1 ( echo Conversion failed; inspect error above. & pause & exit /b 1 )
echo Output in shot's Player_Input folder.
pause
