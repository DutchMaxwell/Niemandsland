@echo off
REM OpenTTS 3D Pipeline - Windows Launcher
REM Doppelklick um die Pipeline zu starten

cd /d "%~dp0"

REM Prüfe ob venv existiert
if not exist "venv" (
    echo Erstelle virtuelle Umgebung...
    python -m venv venv
    call venv\Scripts\activate.bat
    pip install requests gradio_client Pillow
) else (
    call venv\Scripts\activate.bat
)

REM Starte GUI
python pipeline_gui.py
pause
