#!/bin/bash
# OpenTTS 3D Pipeline - Mac Launcher
# Doppelklick um die Pipeline zu starten

cd "$(dirname "$0")"

# Prüfe ob venv existiert
if [ ! -d "venv" ]; then
    echo "Erstelle virtuelle Umgebung..."
    python3 -m venv venv
    source venv/bin/activate
    pip install requests gradio_client Pillow
else
    source venv/bin/activate
fi

# Starte GUI
python3 pipeline_gui.py
