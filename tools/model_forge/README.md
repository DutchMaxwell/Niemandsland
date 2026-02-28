# Model Forge - Automatisierte 3D-Modell-Pipeline

Automatisiert den gesamten Workflow von OPR-Armeeliste zu spielbereiten 3D-Modellen in OpenTTS.

## Workflow

```
OPR Share-Link -> Design Language -> Bilder generieren -> Review -> 3D konvertieren -> Export
```

## Quick Start

### macOS
```
Doppelklick auf "Start Model Forge.command"
```

### Windows
```
Doppelklick auf "Start Model Forge.bat"
```

### Manuell
```bash
cd tools/model_forge
python3 -m venv venv
source venv/bin/activate  # macOS/Linux
pip install -r requirements.txt
python app.py
```

Die Web-UI oeffnet sich automatisch im Browser unter `http://localhost:7860`.

## Tabs

| Tab | Funktion |
|-----|----------|
| **Armee laden** | OPR Share-Link eingeben, Design Language waehlen, Session starten |
| **Prompts** | Prompts fuer jede Einheit generieren und anpassen |
| **Bilder generieren** | Bilder via HF Spaces generieren, reviewen, genehmigen |
| **3D-Konvertierung** | Genehmigte Bilder zu GLB-Modellen konvertieren (TRELLIS) |
| **Export** | GLB-Dateien + units.json nach OpenTTS exportieren |
| **Einstellungen** | HuggingFace Token, Standard-Modell konfigurieren |

## Bildgenerierungs-Modelle

| Modell | Space | Beschreibung |
|--------|-------|-------------|
| **Nano Banana** | `multimodalart/nano-banana` | Standard, Gemini-Qualitaet |
| **Z-Image-Turbo** | `mrfakename/Z-Image-Turbo` | Schneller Fallback |
| **FLUX.1-schnell** | `black-forest-labs/FLUX.1-schnell` | Alternative |

## Design Languages

YAML-Dateien in `design_languages/` definieren die visuelle Identitaet pro Fraktion.

Neue Fraktion erstellen:
1. `_template.yaml` kopieren
2. Fraktion-spezifische Werte eintragen
3. Optional: Unit Overrides fuer individuelle Einheiten

Vorkonfiguriert: `alien_hives.yaml` (alle 35 Einheiten).

## Projektstruktur

```
tools/model_forge/
├── app.py                     # Gradio Web-UI
├── opr_client.py              # OPR API Client
├── prompt_engine.py           # Prompt-Generierung
├── image_generator.py         # HF Space Bildgenerierung
├── trellis_bridge.py          # Bridge zu trellis_core.py
├── pipeline_state.py          # Session-Management
├── exporter.py                # OpenTTS Export
├── design_languages/
│   ├── _template.yaml         # Vorlage
│   └── alien_hives.yaml       # Alien Hives Fraktion
├── tests/                     # pytest Tests
├── requirements.txt
├── Start Model Forge.command  # macOS Launcher
└── Start Model Forge.bat      # Windows Launcher
```

## Tests

```bash
source venv/bin/activate
python -m pytest tests/ -v
```

## Bekannte Limitierungen

- HuggingFace GPU-Quota: ~25 Min/Tag fuer TRELLIS (ca. 10-12 3D-Modelle)
- TRELLIS verarbeitet sequentiell (keine parallelen 3D-Konvertierungen)
- API-Signaturen der HF Spaces koennen sich aendern
