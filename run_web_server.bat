@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   almenupro - Web Server (no Chrome debug)
echo   Open manually: http://127.0.0.1:8088
echo ============================================
echo.

taskkill /f /im dart.exe >nul 2>&1

C:\src\flutter\bin\flutter.bat run -d web-server ^
  --web-hostname=127.0.0.1 ^
  --web-port=8088

pause
