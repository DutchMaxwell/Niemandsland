@echo off
title OpenTTS 3D Pipeline
cd /d "%~dp0"

echo.
echo ========================================
echo  OpenTTS 3D Pipeline - Trellis.2
echo ========================================
echo.

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo FEHLER: Python nicht gefunden!
    echo Bitte Python 3.10+ installieren: python.org
    pause
    exit /b 1
)

REM Check/install dependencies
echo Pruefe Abhaengigkeiten...
python -c "import gradio_client" >nul 2>&1
if errorlevel 1 (
    echo Installiere gradio_client...
    pip install gradio_client
)

python -c "import PIL" >nul 2>&1
if errorlevel 1 (
    echo Installiere Pillow...
    pip install Pillow
)

echo.
echo Starte GUI...
echo.

python trellis_gui.py

if errorlevel 1 (
    echo.
    echo Fehler beim Starten. Druecke eine Taste zum Beenden.
    pause
)
