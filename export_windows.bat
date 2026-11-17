@echo off
setlocal
set "GODOT_EXE=%~dp0godot\Godot.exe"
set "OUT=%~dp0builds\windows\Akira.exe"

if not exist "%GODOT_EXE%" (
    echo Godot not found at "%GODOT_EXE%" -- see run.bat for the one-time setup.
    pause
    exit /b 1
)

if not exist "%APPDATA%\Godot\export_templates" (
    echo Export templates are not installed yet.
    echo.
    echo One-time setup, inside the Godot editor:
    echo   Editor menu ^> Manage Export Templates ^> Download and Install
    echo.
    pause
    exit /b 1
)

if not exist "%~dp0builds\windows" mkdir "%~dp0builds\windows"
"%GODOT_EXE%" --headless --path "%~dp0." --export-release "Windows Desktop" "%OUT%"
if errorlevel 1 (
    echo.
    echo Export failed -- read the messages above.
    pause
    exit /b 1
)
echo.
echo Done: %OUT%
echo Run two copies to test online on one PC: Host in one, Join 127.0.0.1 in the other.
pause
