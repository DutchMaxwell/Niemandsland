#!/bin/bash
# =============================================================================
# Model Forge Launcher - macOS
# =============================================================================
# Automatisches Setup: venv erstellen, Dependencies installieren, App starten.

set -e

# Zum Skript-Verzeichnis wechseln
cd "$(dirname "$0")"

VENV_DIR="venv"
REQUIREMENTS="requirements.txt"

echo "============================================"
echo "  Model Forge - Niemandsland 3D-Modell-Pipeline"
echo "============================================"
echo ""

# Python 3 pruefen
if ! command -v python3 &> /dev/null; then
    echo "FEHLER: Python 3 nicht gefunden."
    echo "Bitte installiere Python 3: brew install python3"
    read -p "Druecke Enter zum Beenden..."
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1)
echo "Python: $PYTHON_VERSION"

# Virtual Environment erstellen (falls nicht vorhanden)
if [ ! -d "$VENV_DIR" ]; then
    echo ""
    echo "Erstelle Virtual Environment..."
    python3 -m venv "$VENV_DIR"
    echo "Virtual Environment erstellt."
fi

# Virtual Environment aktivieren
source "$VENV_DIR/bin/activate"

# Dependencies installieren/aktualisieren
echo ""
echo "Pruefe Dependencies..."
pip install --quiet --upgrade pip
pip install --quiet -r "$REQUIREMENTS"
echo "Dependencies installiert."

# App starten
echo ""
echo "Starte Model Forge..."
echo "Browser oeffnet sich automatisch."
echo ""
python app.py

# Warten falls Fehler
read -p "Druecke Enter zum Beenden..."
