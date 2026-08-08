@echo off
setlocal
cd /d "%~dp0\.."
python "%~dp0backup_project.py" %*
if errorlevel 1 (
  echo.
  echo Backup failed.
  pause
  exit /b 1
)
echo.
pause
