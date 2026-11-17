@echo off
setlocal
set "GODOT_EXE=%~dp0godot\Godot.exe"

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

if not exist "%~dp0builds\server" mkdir "%~dp0builds\server"
echo Exporting the dedicated server for Linux (x86_64 and arm64)...
"%GODOT_EXE%" --headless --path "%~dp0." --export-release "Linux Server (x86_64)" "%~dp0builds\server\akira_server.x86_64"
"%GODOT_EXE%" --headless --path "%~dp0." --export-release "Linux Server (arm64)" "%~dp0builds\server\akira_server.arm64"
echo.
echo Done: builds\server\
echo Copy the file matching your server's CPU to it, then run:
echo   chmod +x akira_server.x86_64
echo   ./akira_server.x86_64 --headless -- --server --port=9050
pause
