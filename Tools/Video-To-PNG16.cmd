@echo off
setlocal
set "INPUT=%~1"
if "%INPUT%"=="" (
  echo Paste the path of the DLSS player's exported lossless video:
  set /p "INPUT=File: "
)
if not exist "%INPUT%" (
  echo Missing input: %INPUT%
  pause
  exit /b 1
)
where ffmpeg >nul 2>nul
if errorlevel 1 (
  echo FFmpeg not found on PATH. Install FFmpeg first.
  pause
  exit /b 1
)
for %%A in ("%INPUT%") do set "OUT=%%~dpnA_frames"
if exist "%OUT%" (
  echo Refusing to overwrite existing output folder: %OUT%
  pause
  exit /b 1
)
mkdir "%OUT%" || exit /b 1
rem Convert Rec.709 display transfer to sRGB for Unity TextureImporter sRGBTexture=true.
rem This does NOT recover HDR or scene-linear values lost in the player.
ffmpeg -hide_banner -i "%INPUT%" -map 0:v:0 -fps_mode passthrough -vf "format=gbrp16le,zscale=transferin=bt709:primariesin=bt709:matrixin=gbr:transfer=iec61966-2-1:primaries=bt709:matrix=gbr:range=full,format=rgb48be" -start_number 0 "%OUT%\frame_%%06d.png"
if errorlevel 1 (
  echo FFmpeg failed. Check input codec, permissions, and free disk space.
  pause
  exit /b 1
)
echo Converted to %OUT%
pause
