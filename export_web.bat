@echo off
setlocal
set "GODOT_EXE=%~dp0godot\Godot.exe"
set "OUT=%~dp0builds\web\index.html"

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

if not exist "%~dp0builds\web" mkdir "%~dp0builds\web"
"%GODOT_EXE%" --headless --path "%~dp0." --export-release "Web" "%OUT%"
if errorlevel 1 (
    echo.
    echo Export failed -- read the messages above.
    pause
    exit /b 1
)
echo.
echo Done: %OUT%
echo A browser can't open this straight from the folder -- it needs a web server. Easiest:
echo   cd builds\web
echo   python -m http.server 8000
echo then open http://localhost:8000 in the browser. Browsers can only JOIN; the host must be the desktop build.
pause
