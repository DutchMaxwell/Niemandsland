# Model Forge - Automatisierte 3D-Modell-Pipeline

Automatisiert den gesamten Workflow von OPR-Armeeliste zu spielbereiten 3D-Modellen in OpenTTS. Unterstuetzt alle 38 Grimdark Future Fraktionen mit 854 Einheiten und echten OPR v3.5.2 Spielwerten.

## Workflow

```
OPR Share-Link oder Design Language
        |
        v
  PromptEngine (Einheitsdaten + Fraktions-Aesthetik)
        |
        v
  Image-Generierung (HuggingFace Spaces)
        |
        v
  Review & Genehmigung
        |
        v
  3D-Konvertierung (TRELLIS)
        |
        v
  GLB Export nach OpenTTS
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
| **Armee laden** | OPR Share-Link eingeben oder Design Language waehlen, Session starten |
| **Prompts** | Prompts fuer jede Einheit generieren und anpassen |
| **Bilder generieren** | Bilder via HF Spaces generieren, reviewen, genehmigen |
| **3D-Konvertierung** | Genehmigte Bilder zu GLB-Modellen konvertieren (TRELLIS) |
| **Export** | GLB-Dateien + units.json nach OpenTTS exportieren |
| **Einstellungen** | HuggingFace Token, Standard-Modell konfigurieren |

## Design Languages

YAML-Dateien in `design_languages/` definieren die visuelle Identitaet und Spielwerte pro Fraktion.

**38 Fraktionen vorkonfiguriert** mit insgesamt **854 Einheiten**, jeweils mit:
- Aesthetik (Genre, Stil, Inspiration, explizit zu Vermeidendes)
- Farbschema (Primary, Secondary, Accent)
- Materialien und Kreaturtyp
- Prompt-Template fuer Bildgenerierung
- Unit Overrides mit individuellen Posen, Details und Spielwerten

### game_stats (OPR v3.5.2)

Jeder Unit Override enthaelt echte Spielwerte aus den offiziellen OPR-PDFs:

```yaml
unit_overrides:
  hive_warriors:
    extra_details: "chitinous armor, insectoid features"
    pose: "swarming forward aggressively"
    game_stats:
      quality: 4       # Wuerfelwert fuer Treffer (2-6)
      defense: 4       # Wuerfelwert fuer Rettung (2-6)
      cost: 100        # Punktekosten (20-750)
      size: 5          # Modelle pro Einheit (1-10)
      base: 25         # Rund in mm, oder "60x35" fuer oval
      rules:
        - "Fearless"
      weapons:
        - name: "Razor Claws"
          range: 0      # 0 = Nahkampf
          attacks: 2
          rules: ["AP(1)"]
```

### Neue Fraktion erstellen

1. `_template.yaml` kopieren
2. Fraktions-Aesthetik und Farben eintragen
3. Unit Overrides mit Posen und game_stats hinzufuegen

## Zwei Betriebsmodi

### 1. Army Forge Modus
OPR Share-Link eingeben. Einheitsdaten kommen von der Army Forge API, Design Language liefert die visuelle Identitaet.

### 2. Design Language Only Modus
Ohne Army Forge. `create_army_from_design_language()` erzeugt eine vollstaendige OPRArmy direkt aus den unit_overrides und game_stats der YAML-Datei.

## Bildgenerierungs-Modelle

| Modell | Space | Beschreibung |
|--------|-------|-------------|
| **Nano Banana** | `multimodalart/nano-banana` | Standard, Gemini-Qualitaet |
| **Z-Image-Turbo** | `mrfakename/Z-Image-Turbo` | Schneller Fallback |
| **FLUX.1-schnell** | `black-forest-labs/FLUX.1-schnell` | Alternative |

## Projektstruktur

```
tools/model_forge/
├── app.py                      # Gradio Web-UI (Tabs, Session, Pipeline)
├── batch_generate.py           # Headless Bulk-CLI fuer alle Fraktionen
├── opr_client.py               # OPR API Client + Datenklassen (OPRWeapon, OPRUnit, OPRArmy)
├── prompt_engine.py            # DesignLanguage, PromptEngine, IP-Compliance-Block
├── image_generator.py          # Gemini/HF Bildgenerierung mit Reference-Pinning
├── quality_gate.py             # Vision-LLM Quality-Check (technisch + GW-IP)
├── hero_workflow.py            # Hero-Mini-Auswahl + Reference-Image-Persistenz
├── trellis_bridge.py           # Bridge zu trellis_core.py (3D-Generierung)
├── glb_optimizer.py            # Mesh-Decimation + Texture-Resize fuer GLBs
├── reprocess_existing.py       # Einmal-Skript: existierende GLBs nach-optimieren
├── pipeline_state.py           # Session-Management und Pipeline State
├── exporter.py                 # GLB-Export nach OpenTTS (mit Auto-Optimierung)
├── __init__.py
├── bin/
│   └── gltfpack-linux          # Mesh-Optimizer-Binary (Meshoptimizer v1.1)
├── design_languages/           # 38 Fraktions-YAMLs + Template
│   ├── _template.yaml          # Vorlage fuer neue Fraktionen
│   ├── alien_hives.yaml        # 41 Einheiten
│   └── ... (37 weitere)        # 855 Einheiten insgesamt
├── requirements.txt            # Python Dependencies
├── Start Model Forge.command   # macOS Launcher
└── Start Model Forge.bat       # Windows Launcher
```

## Bulk-Generierung (Headless)

Fuer die Bulk-Generierung aller Fraktionen ohne Gradio-UI:

```bash
# Eine Fraktion verarbeiten (mit Hero-First, Quality-Gate, GLB-Optimierung)
python batch_generate.py --faction alien_hives

# Alle 38 Fraktionen abarbeiten (laeuft Tage wegen HF-Quota)
python batch_generate.py --all

# Tests ohne 3D (nur Bilder, schneller fuer Quality-Tests)
python batch_generate.py --faction alien_hives --skip-trellis

# Mehr Re-Rolls bei schwierigen Fraktionen
python batch_generate.py --faction wormhole_daemons_of_war --max-attempts 5
```

Voraussetzungen:
- `.gemini_key` mit Google Gemini API Key (fuer Image-Gen + Quality-Gate)
- `.hf_token` mit HuggingFace Token (fuer TRELLIS-Space)
- `.trellis_space` mit Space-ID (z.B. `DutchyMaxwell/TRELLIS-2`)

Workflow je Fraktion:
1. Hero-Mini bestimmen (Heuristik oder `aesthetic.hero_unit_key` in YAML)
2. Hero generieren (mit Quality-Gate-Loop bis PASS), als `_reference.webp` persistieren
3. Restliche Units mit Reference-Pinning generieren
4. Quality-Gate-Check (technisch + GW-IP) je Bild → bei FAIL Re-Roll
5. TRELLIS 3D
6. GLB optimieren (Mesh-Decimation + 1024^2 Textur)
7. Export nach `assets/miniatures/{faction}/glb/{NN}_{Name}.glb`

Resume-Logic: bereits vorhandene GLBs werden uebersprungen. Sessions liegen unter `state/{faction}_{timestamp}/`.

## IP-Compliance

Jeder generierte Prompt enthaelt automatisch den `IP_COMPLIANCE_BLOCK` aus `prompt_engine.py`,
der konkrete GW-Designs ausschliesst (Aquila, Skull-Cog, Custodes-Helme etc.).
Zusaetzlich prueft `quality_gate.py` jedes erzeugte Bild via Gemini Vision auf:
- technische Kriterien (single mini, no base, white bg)
- GW-IP-Verletzungen (mit konkreter Liste verbotener Symbole)

Ein Bild mit `ip_concerns != []` schlaegt fehl und wird re-gerollt. Manuelle Review
des Logs empfohlen, falls eine Fraktion auffaellig viele IP-Flags produziert.

## Hero-First Style-Konsistenz

Damit alle Minis einer Fraktion zusammenpassen, wird eine "Hero-Mini" zuerst generiert
und als visuelle Reference (`assets/miniatures/{faction}/_reference.webp`) gespeichert.
Alle weiteren Image-Calls bekommen dieses Bild als Style-Anker mit (Gemini Nano Banana
unterstuetzt das nativ ueber `contents=[image, prompt]`). Ergebnis: konsistenter
Render-Look, gleiche Beleuchtung, gleiche Farb-Behandlung quer ueber die ganze Fraktion.

Hero-Auswahl-Heuristik (in `hero_workflow.py`):
1. `aesthetic.hero_unit_key` aus YAML (manueller Override)
2. Hero-Infanterie: size=1, base ≤ 40mm, max cost, keine Vehicle-Regeln
3. Monster-Hero: size=1, base ≤ 50mm, max cost
4. Globaler Fallback: max cost

## Tests

```bash
source venv/bin/activate
python -m pytest tests/ -v
```

## Bekannte Limitierungen

- HuggingFace GPU-Quota: ~25 Min/Tag fuer TRELLIS (ca. 10-12 3D-Modelle)
- TRELLIS verarbeitet sequentiell (keine parallelen 3D-Konvertierungen)
- API-Signaturen der HF Spaces koennen sich aendern
- Keine automatisierten Tests fuer die Pipeline-Module vorhanden
