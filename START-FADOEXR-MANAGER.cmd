@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
    py -3 "Manager\fadoexr_manager.py" %*
    goto :exit
)
where python >nul 2>nul
if not errorlevel 1 (
    python "Manager\fadoexr_manager.py" %*
    goto :exit
)
echo Python 3 was not found. Install Python 3 with Tkinter enabled and try again.
:exit
if errorlevel 1 pause
