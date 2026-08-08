@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   almenupro - Flutter Web (Release)
echo   avoids Chrome debug connection timeout
echo ============================================
echo.

REM Stop stale Dart/Flutter processes
taskkill /f /im dart.exe >nul 2>&1

set CHROME_PROFILE=%TEMP%\flutter_chrome_almenupro
if not exist "%CHROME_PROFILE%" mkdir "%CHROME_PROFILE%"

echo Starting on Chrome (release mode)...
echo URL will be: http://127.0.0.1:8090
echo.

C:\src\flutter\bin\flutter.bat run -d chrome --release ^
  --web-hostname=127.0.0.1 ^
  --web-port=8090 ^
  --web-browser-flag="--disable-extensions" ^
  --web-browser-flag="--user-data-dir=%CHROME_PROFILE%"

pause
