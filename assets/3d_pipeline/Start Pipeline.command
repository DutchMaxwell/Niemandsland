#!/bin/bash
# Niemandsland 3D Pipeline - macOS/Linux Starter

echo ""
echo "========================================"
echo " Niemandsland 3D Pipeline - Trellis.2"
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

# Virtual Environment erstellen/aktivieren
VENV_DIR="./venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "Erstelle Virtual Environment..."
    python3 -m venv "$VENV_DIR"
    echo "Virtual Environment erstellt."
    echo ""
fi

echo "Aktiviere Virtual Environment..."
source "$VENV_DIR/bin/activate"

# Abhaengigkeiten pruefen/installieren
echo "Pruefe Abhaengigkeiten..."

python -c "import gradio_client" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Installiere gradio_client..."
    pip install --upgrade pip
    pip install gradio_client
fi

python -c "import PIL" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Installiere Pillow..."
    pip install Pillow
fi

echo ""
echo "Starte GUI..."
echo ""

python trellis_gui.py

if [ $? -ne 0 ]; then
    echo ""
    echo "Fehler beim Starten."
    read -p "Druecke Enter zum Beenden..."
fi

deactivate 2>/dev/null
