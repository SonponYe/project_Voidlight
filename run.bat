@echo off
setlocal
set "GODOT_EXE=%~dp0godot\Godot.exe"

if not exist "%GODOT_EXE%" (
    echo Godot not found at "%GODOT_EXE%"
    echo.
    echo One-time setup:
    echo   1. Download the standard Godot 4.x build, not the .NET one, from godotengine.org/download
    echo   2. Rename the downloaded exe to Godot.exe
    echo   3. Put it in a "godot" folder right next to this run.bat
    echo.
    pause
    exit /b 1
)

"%GODOT_EXE%" --path "%~dp0."
