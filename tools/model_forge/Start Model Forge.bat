@echo off
REM =============================================================================
REM Model Forge Launcher - Windows
REM =============================================================================
REM Automatisches Setup: venv erstellen, Dependencies installieren, App starten.

cd /d "%~dp0"

set VENV_DIR=venv
set REQUIREMENTS=requirements.txt

echo ============================================
echo   Model Forge - Niemandsland 3D-Modell-Pipeline
echo ============================================
echo.

REM Python 3 pruefen
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo FEHLER: Python nicht gefunden.
    echo Bitte installiere Python 3: https://python.org/downloads
    pause
    exit /b 1
)

python --version

REM Virtual Environment erstellen (falls nicht vorhanden)
if not exist "%VENV_DIR%" (
    echo.
    echo Erstelle Virtual Environment...
    python -m venv %VENV_DIR%
    echo Virtual Environment erstellt.
)

REM Virtual Environment aktivieren
call %VENV_DIR%\Scripts\activate.bat

REM Dependencies installieren/aktualisieren
echo.
echo Pruefe Dependencies...
pip install --quiet --upgrade pip
pip install --quiet -r %REQUIREMENTS%
echo Dependencies installiert.

REM App starten
echo.
echo Starte Model Forge...
echo Browser oeffnet sich automatisch.
echo.
python app.py

pause
