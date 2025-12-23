# OpenTTS Alien Hives Pipeline - Status Dokumentation

## Projektziel
Automatisierte Generierung von 3D-Modellen (.glb) für das OpenTTS Tabletop-Simulator Projekt.
- **Workflow:** Gemini (Bildgenerierung) → TRELLIS.2 (3D-Konvertierung)
- **Armee:** "GF - Alien Hives v3.5.1" (35 Einheiten)

## Aktueller Stand

### Was funktioniert
- Pipeline-Script: `pipeline.py`
- Gemini API ist in Deutschland blockiert → **Manuelle Bildgenerierung im Browser** (aistudio.google.com)
- TRELLIS.2 über HuggingFace Space API funktioniert
- HuggingFace Pro Token für mehr GPU-Quota
- Qualitätseinstellungen (Resolution, Decimation, Texture Size) konfigurierbar

### Pipeline Nutzung
```bash
cd /home/user/openTTS/assets/miniatures/alien_hives

# Mit vorformatiertem Bild (schwarzer Hintergrund, quadratisch)
python pipeline.py --image unit.png --no-preprocess --resolution 1536 --decimation 500000 --texture-size 4096 --hf-token YOUR_TOKEN

# Mit weißem Hintergrund (automatisches Preprocessing)
python pipeline.py --image unit.png --resolution 1536 --decimation 500000 --texture-size 4096 --hf-token YOUR_TOKEN
```

### CLI Optionen
| Option | Beschreibung |
|--------|--------------|
| `--image` | Bild zu 3D konvertieren (mehrfach verwendbar) |
| `--no-preprocess` | Preprocessing überspringen (für vorformatierte Bilder) |
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
**Ursache:** Wasserzeichen-Entfernung malt schwarzes Quadrat das als Boden interpretiert wird
**Status:** OFFEN - Nächster Schritt: Intelligentere Wasserzeichen-Entfernung oder manuelles Cropping

### 4. Gemini Wasserzeichen wird zu 3D-Artefakt
**Ursache:** Kleiner Stern unten rechts im Gemini-Bild
**Aktueller Fix:** 200x200px Bereich wird schwarz/transparent gemacht
**Problem:** Dieser schwarze Bereich wird manchmal als Boden interpretiert
**Nächster Schritt:**
- Option A: Manuell Wasserzeichen in Preview/Photoshop entfernen vor Pipeline
- Option B: Intelligentere Erkennung (nur helle Pixel des Sterns entfernen, nicht ganzes Quadrat)

## Dateien

```
/home/user/openTTS/assets/miniatures/alien_hives/
├── pipeline.py           # Haupt-Pipeline Script
├── units.json            # Einheiten-Definitionen (35 Units)
├── GENERATION_WORKFLOW.md # Workflow-Dokumentation
├── PIPELINE_STATUS.md    # Diese Datei
├── images/               # Generierte Bilder
└── models/               # Generierte GLB-Dateien
```

## Git Branch
```
claude/openttts-unit-assets-sXFUW
```

## Nächste Schritte
1. **Wasserzeichen-Problem lösen:** Entweder intelligentere Entfernung oder manueller Workflow
2. **Batch-Generierung:** Alle 35 Einheiten durchgehen
3. **GLB-Nachbearbeitung:** Evtl. Blender-Script für automatisches Cleanup

## Dependencies
```bash
pip install gradio_client requests Pillow
```

## Wichtige Erkenntnisse
- TRELLIS Web-Interface macht Preprocessing (schwarzer BG, quadratisch, zentriert)
- Unsere API-Parameter stimmen mit Web-Defaults überein
- Random Seed ist wichtig (nicht seed=0)
- Gemini-Bilder mit weißem BG brauchen Preprocessing
- Gemini-Bilder mit schwarzem BG + quadratisch → `--no-preprocess`
