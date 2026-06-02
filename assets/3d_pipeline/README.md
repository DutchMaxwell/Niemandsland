# Niemandsland 3D Pipeline

Konvertiert Bilder zu 3D-Modellen mit Microsoft TRELLIS.2.

## Schnellstart

### Windows
Doppelklick auf `Start Pipeline.bat`

### macOS / Linux
```bash
./Start\ Pipeline.command
```

Oder direkt:
```bash
python3 trellis_gui.py
```

## Voraussetzungen

- Python 3.10+
- HuggingFace Account (kostenlos): https://huggingface.co/join
- HuggingFace Token: https://huggingface.co/settings/tokens

### Abhaengigkeiten

Werden automatisch installiert beim Start, oder manuell:

```bash
pip install gradio_client Pillow
```

## Verwendung

1. **Token eingeben**: HuggingFace Token von huggingface.co/settings/tokens
2. **Bilder-Ordner waehlen**: Ordner mit PNG/JPG/WEBP Bildern
3. **Output-Ordner waehlen**: Wo die GLB-Dateien gespeichert werden
4. **Konvertierung starten**: Klick und warten (1-3 Min pro Bild)

## Qualitaet

Immer Maximum:
- **Aufloesung**: 1536px (hoechste)
- **Polygone**: 500.000 (maximales Detail)
- **Texturen**: 4096px (4K)

## Tipps fuer beste Ergebnisse

- **Hintergrund**: Weiss oder schwarz, einfarbig
- **Motiv**: Ein einzelnes Objekt, zentriert
- **Ansicht**: 3/4 isometrisch (schraeg von vorne)
- **Format**: PNG bevorzugt, mindestens 512x512px

## Dateien

```
3d_pipeline/
├── trellis_gui.py          # GUI-Anwendung
├── trellis_core.py         # Kernfunktionen
├── Start Pipeline.bat      # Windows Starter
├── Start Pipeline.command  # macOS/Linux Starter
├── .hf_token               # Gespeicherter Token (automatisch)
└── README.md               # Diese Datei
```

## HuggingFace Quota

- **Kostenlos**: ~5 Modelle pro Tag
- **Pro** ($9/Monat): ~25 Minuten GPU = ~10-12 Modelle pro Tag

Bei Quota-Ueberschreitung warten oder spaeter fortsetzen.
