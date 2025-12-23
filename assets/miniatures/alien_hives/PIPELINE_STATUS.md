# OpenTTS Alien Hives Pipeline - Status Dokumentation

## Projektziel
Automatisierte Generierung von 3D-Modellen (.glb) für das OpenTTS Tabletop-Simulator Projekt.
- **Workflow:** Gemini (Bildgenerierung) → TRELLIS.2 (3D-Konvertierung)
- **Armee:** "GF - Alien Hives v3.5.1" (35 Einheiten)

## Aktueller Stand

### Was funktioniert
- ✅ **GUI-Pipeline:** `Start Pipeline.command` (Mac) / `Start Pipeline.bat` (Windows)
- ✅ Pipeline-Script: `pipeline.py` (CLI)
- ✅ Gemini Wasserzeichen-Entfernung (sampelt echte Hintergrundfarbe)
- ✅ TRELLIS.2 über HuggingFace Space API
- ✅ HuggingFace Pro Token für mehr GPU-Quota
- ✅ Batch-Verarbeitung mehrerer Bilder
- Gemini API ist in Deutschland blockiert → **Manuelle Bildgenerierung im Browser** (aistudio.google.com)

## Schnellstart (GUI)

### Mac
1. Doppelklick auf `Start Pipeline.command`
2. Beim ersten Start wird automatisch die virtuelle Umgebung erstellt
3. HuggingFace Token eingeben (einmalig, wird gespeichert)
4. Bilder auswählen → "Pipeline starten"

### Windows
1. Doppelklick auf `Start Pipeline.bat`
2. Beim ersten Start wird automatisch die virtuelle Umgebung erstellt
3. HuggingFace Token eingeben (einmalig, wird gespeichert)
4. Bilder auswählen → "Pipeline starten"

## CLI Nutzung (Fortgeschritten)
```bash
cd assets/miniatures/alien_hives
source venv/bin/activate  # Mac/Linux
# oder: venv\Scripts\activate  # Windows

# Einzelnes Bild (schwarzer Hintergrund)
python pipeline.py --image unit.png --no-preprocess --hf-token YOUR_TOKEN

# Mehrere Bilder
python pipeline.py --image bild1.png --image bild2.png --no-preprocess --hf-token YOUR_TOKEN

# Hohe Qualität
python pipeline.py --image unit.png --no-preprocess --resolution 1536 --decimation 500000 --texture-size 4096 --hf-token YOUR_TOKEN
```

### CLI Optionen
| Option | Beschreibung |
|--------|--------------|
| `--image` | Bild zu 3D konvertieren (mehrfach verwendbar) |
| `--no-preprocess` | Für Bilder mit schwarzem Hintergrund |
| `--resolution` | 512, 1024, 1536 (default: 1024) |
| `--decimation` | Mesh-Reduktion 100000-500000 (default: 300000) |
| `--texture-size` | Texturgröße 1024-4096 (default: 2048) |
| `--hf-token` | HuggingFace Pro Token |

## Optimaler Gemini Prompt

**WICHTIG:** Schwarzer Hintergrund + Quadratisches Format direkt in Gemini anfordern!

```
A [UNIT NAME] alien bio-organism, [DESCRIPTION].

COMPOSITION - CRITICAL:
- ONLY ONE single creature
- ONLY ONE viewing angle (3/4 isometric from front-left)
- NOT a character sheet, NOT a turnaround, NOT multiple views
- Single isolated render, centered in frame
- SQUARE FORMAT (1:1 aspect ratio)
- Figure fills 85% of the frame height

CREATURE DESIGN:
- [Detaillierte Beschreibung der Kreatur]
- Inspiration: HR Giger xenomorph, Starship Troopers bugs, Zerg from Starcraft
- Biomechanical exoskeleton with chitinous armor plates
- Color palette: deep crimson red carapace, bone white armor plates,
  dark red muscle tissue visible between plates
- Organic textures: chitin, muscle sinew, bone ridges

EXPLICITLY AVOID:
- Games Workshop / Tyranid specific designs
- Boneswords, lash whips, or GW-specific weapons
- Any copyrighted GW iconography

POSE:
- [Pose-Beschreibung]
- Dynamic but stable pose suitable for 3D figurine

TECHNICAL:
- NO base, NO ground, NO pedestal, NO shadow on floor
- Pure BLACK background (#000000)
- Full body visible from head to feet/claws
- Clean silhouette edges
- Optimized for AI 3D model reconstruction
```

## Bekannte Probleme & Lösungen

### 1. Modell zu schmal/flach
**Ursache:** Quellbild nicht im richtigen Format
**Lösung:** Quadratisches Bild mit 3/4-Ansicht, Figur füllt 85% der Höhe

### 2. Würfel/Box um das Modell
**Ursache:** Weißer Hintergrund wird als Geometrie interpretiert
**Lösung:** Schwarzen Hintergrund in Gemini anfordern, `--no-preprocess` verwenden

### 3. Boden-Artefakt unter dem Modell
**Ursache:** Alte Wasserzeichen-Entfernung malte schwarzes Quadrat das als Boden interpretiert wurde
**Status:** ✅ GELÖST - Intelligente Wasserzeichen-Entfernung implementiert

### 4. Gemini Wasserzeichen wird zu 3D-Artefakt
**Ursache:** Kleiner Stern unten rechts im Gemini-Bild
**Status:** ✅ GELÖST
**Lösung:**
- Sampelt echte Hintergrundfarbe aus dem Bild (nicht festes Schwarz)
- Übermalt Wasserzeichen mit der tatsächlichen Hintergrundfarbe
- Dynamischer Threshold basierend auf Hintergrund-Helligkeit
- Kein sichtbarer Unterschied mehr → kein 3D-Artefakt

## Dateien

```
assets/miniatures/alien_hives/
├── Start Pipeline.command  # 🖱️ Mac: Doppelklick zum Starten
├── Start Pipeline.bat      # 🖱️ Windows: Doppelklick zum Starten
├── pipeline_gui.py         # GUI-Version mit Batch-Verarbeitung
├── pipeline.py             # CLI-Version (Kommandozeile)
├── units.json              # Einheiten-Definitionen (35 Units)
├── GENERATION_WORKFLOW.md  # Workflow-Dokumentation
├── PIPELINE_STATUS.md      # Diese Datei
├── venv/                   # Virtuelle Python-Umgebung (automatisch erstellt)
├── images/                 # Generierte Bilder
└── models/                 # Generierte GLB-Dateien
```

## Git Branch
```
main
```

## Nächste Schritte
1. ~~**Wasserzeichen-Problem lösen:**~~ ✅ Intelligente Entfernung implementiert
2. ~~**GUI mit Batch-Verarbeitung:**~~ ✅ `Start Pipeline.command` / `.bat` erstellt
3. **Batch-Generierung:** Alle 35 Einheiten durchgehen
4. **GLB-Nachbearbeitung:** Evtl. Blender-Script für automatisches Cleanup

## Dependencies
```bash
pip install gradio_client requests Pillow
```

## GPU Quota (HuggingFace)

Die TRELLIS.2-Pipeline nutzt HuggingFace ZeroGPU. Bei PRO-Subscription:
- **25 Minuten** ZeroGPU-Zeit pro Tag
- Jede 3D-Generierung benötigt ~2 Minuten GPU-Zeit
- **Quota-Error?** Warte 30-60 Minuten - die Quota nutzt ein gleitendes Zeitfenster
- Die Billing-Seite (huggingface.co/pricing) zeigt verzögerte Daten

**Tipp:** Mit 25 Min. kannst du ca. 10-12 Modelle pro Tag generieren.

## Wichtige Erkenntnisse
- TRELLIS Web-Interface macht Preprocessing (schwarzer BG, quadratisch, zentriert)
- Unsere API-Parameter stimmen mit Web-Defaults überein
- Random Seed ist wichtig (nicht seed=0)
- Gemini-Bilder mit weißem BG brauchen Preprocessing
- Gemini-Bilder mit schwarzem BG + quadratisch → `--no-preprocess`
