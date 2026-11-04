@echo off
title MP Manager - Waveshare Modbus Relay

echo ============================================
echo   MP Manager - Avvio
echo ============================================
echo.

REM -- Verifica Python --
where python >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRORE] Python non trovato nel PATH.
    echo          Installa Python 3 da https://python.org e riprova.
    echo.
    pause
    exit /b 1
)

REM -- Verifica pyModbusTCP --
python -c "import pyModbusTCP" >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] pyModbusTCP non installato. Installazione in corso...
    pip install pyModbusTCP
    if %errorlevel% neq 0 (
        echo [ERRORE] Installazione pyModbusTCP fallita.
        echo          Prova manualmente: pip install pyModbusTCP
        echo.
        pause
        exit /b 1
    )
    echo [OK] pyModbusTCP installato.
    echo.
)

REM -- Verifica devices.json --
if not exist "%~dp0devices.json" (
    echo [INFO] devices.json non trovato.
    echo          Avvio wizard di configurazione guidata...
    echo.
    python "%~dp0setup_wizard.py"
    if not exist "%~dp0devices.json" (
        echo.
        echo [ERRORE] Configurazione non completata. devices.json mancante.
        echo.
        pause
        exit /b 1
    )
    echo.
)

REM -- Avvio app --
echo [OK] Avvio MP Manager...
echo.
python "%~dp0mp_manager_win.py"

if %errorlevel% neq 0 (
    echo.
    echo [ERRORE] L'app si e' chiusa con codice errore %errorlevel%.
    pause
)
