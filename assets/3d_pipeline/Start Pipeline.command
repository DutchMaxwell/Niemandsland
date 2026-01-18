#!/bin/bash
# OpenTTS 3D Pipeline - macOS/Linux Starter

echo ""
echo "========================================"
echo " OpenTTS 3D Pipeline - Trellis.2"
echo "========================================"
echo ""

# Wechsel zum Skript-Verzeichnis
cd "$(dirname "$0")"

# Python pruefen
if ! command -v python3 &> /dev/null; then
    echo "FEHLER: Python3 nicht gefunden!"
    echo "Bitte Python 3.10+ installieren"
    read -p "Druecke Enter zum Beenden..."
    exit 1
fi

# Abhaengigkeiten pruefen/installieren
echo "Pruefe Abhaengigkeiten..."

python3 -c "import gradio_client" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Installiere gradio_client..."
    pip3 install gradio_client
fi

python3 -c "import PIL" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Installiere Pillow..."
    pip3 install Pillow
fi

echo ""
echo "Starte GUI..."
echo ""

python3 trellis_gui.py

if [ $? -ne 0 ]; then
    echo ""
    echo "Fehler beim Starten."
    read -p "Druecke Enter zum Beenden..."
fi
