@echo off
chcp 65001 >nul 2>&1
title MP Manager — Setup Wizard

echo ============================================
echo   MP Manager - Setup Wizard
echo   Configurazione devices.json
echo ============================================
echo.

where python >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRORE] Python non trovato nel PATH.
    pause
    exit /b 1
)

python "%~dp0setup_wizard.py"
echo.
pause
