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

# Versuche GUI zu starten, bei Fehler nutze Terminal-Version
python3 -c "import tkinter" 2>/dev/null
if [ $? -eq 0 ]; then
    python3 pipeline_gui.py
else
    echo "=============================================="
    echo "Tkinter nicht verfügbar - nutze Terminal-Modus"
    echo "=============================================="
    echo ""
    python3 batch_convert.py
fi
