# OpenTTS - Projekt Status
**Stand:** 2026-01-06
**Version:** 0.2-alpha
**Branch:** `main` (alle Feature-Branches gemerged)

---

## 🎯 Übersicht

OpenTTS ist ein Open-Source Tabletop-Simulator mit Fokus auf Wargaming-Spiele wie OnePageRules, historische Wargames und andere Miniaturenspiele.

**Status:** Milestone 2 (Alpha) in aktiver Entwicklung

---

## ✅ Implementierte Features

### Core-Features (Milestone 1 - Abgeschlossen)
- ✅ **3D Spieltisch** - Variable Größen (4x4, 6x4, custom)
- ✅ **Kamera-Steuerung** - Orbit, Pan, Zoom mit Easing
- ✅ **Objekt-Management** - Spawn, Move, Rotate, Delete
- ✅ **Multi-Selection** - Alt+Click, Box-Select
- ✅ **Arrangement-Funktionen** - 1-9 für Reihen, A für Pfeil-Formation
- ✅ **Copy/Paste** - Ctrl+C/V/D mit Cursor-Positionierung
- ✅ **Performance** - 1000+ Objekte flüssig

### Import/Export
- ✅ **TTS Import** - Online von Steam CDN + Local Cache
- ✅ **Custom Models** - glTF, STL, OBJ Support
- ✅ **Speichern/Laden** - .otts Format mit Multiplayer-Sync

### Multiplayer (Milestone 1)
- ✅ **Netzwerk-Grundlagen** - ENet-basiert
- ✅ **State-Sync** - Objekte, Terrain, Spielstand
- ✅ **Multiplayer-Laden** - Clients erhalten Spielstand beim Laden

### Wargaming-Features
- ✅ **Würfel-System** - D4, D6, D8, D10, D12, D20, D100
- ✅ **Distanzmessung** - In Zoll
- ✅ **Terrain-Library** - Felsen, Gebäude, Bäume

### Terrain & Map Layout System (NEU!)
- ✅ **Map Layout Editor** - Top-down 3" Grid für Terrain-Planung
- ✅ **Terrain-Typen mit Eigenschaften**:
  - Ruins (Height 5, Cover, Impassable Walls)
  - Forest (Height 5, Difficult + Cover)
  - Container (Height 5, Impassable + Blocking)
  - Dangerous (Minefields/Acid/Radiation)
- ✅ **Deployment Zones** - Standard 6"/9", Diagonal, Hammer & Anvil
- ✅ **Objectives System** - Platzierung und Visualisierung von Zielpunkten
- ✅ **Auto-Generate Terrain** - Automatische Terrain-Generierung mit Symmetrie
- ✅ **3D Overlay Visualisierung** - Terrain-Grid im 3D-Spiel sichtbar
- ✅ **Save/Load Layouts** - Terrain-Setups speichern und laden
- ✅ **Table Background Texture** - Standard-Untergrund für den Spieltisch

### Deployment & Terrain Gameplay (NEU!)
- ✅ **Deployment Zones im 3D-Spiel** - Front-line (12") Visualisierung
- ✅ **Deployment Mode** - Zone Compliance Checking für Einheiten
- ✅ **Terrain Hints** - Anzeige für Difficult und Dangerous Terrain
- ✅ **LOS-Blocking Check** - Prüfung ob Terrain Sichtlinien blockiert
- ✅ **Scout/Ambush Units Panel** - UI-Panel für Scout/Ambush Einheiten

### OPR Integration
- ✅ **OPR API Client** - Army Forge API Integration
- ✅ **Stats Tooltips** - Unit-Statistiken beim Hover
- ✅ **Import Dialog** - Army Forge Listen importieren

### WGS Integration
- ✅ **WGS Client** - Parser für Wargaming Simulator Format
- ✅ **Import/Export** - Spielzustände austauschen
- ✅ **Koordinaten-Konvertierung** - WGS ↔ OpenTTS

### UI & Graphics (Milestone 2 - In Arbeit)
- ✅ **Theme-System** - 9 Kenney UI Themes (Fantasy + SciFi)
- ✅ **Theme Persistence** - Theme-Auswahl wird gespeichert
- ✅ **Lighting-System** - 4 Presets (F1-F4: Default, Studio, Dramatic, Night)
- ✅ **Graphics Settings** - Quality Selector (Low, Medium, High, Ultra)
- ✅ **Tron-Style Intro** - Animierte Intro-Sequenz mit Grid und Camera-Zoom
- ✅ **Startup Menu** - Glassmorphic Design

### Rendering & Graphics
- ✅ **Shadow Quality** - 8K Shadows, 16-bit Atlas
- ✅ **Shadow Cascades** - Optimiert für Tabletop-Scale
- ✅ **Soft Shadows** - Quality Level 5 (Maximum)
- ✅ **SSAO** - Screen-Space Ambient Occlusion
- ✅ **SSR** - Screen-Space Reflections
- ✅ **Glow & Bloom** - Post-Processing
- ✅ **Two-Sided Lighting Shader** - Korrekte Beleuchtung für Terrain-Modelle (NEU!)
- ✅ **Ring Overlay Highlight** - Ersetzt material-basierte Hervorhebung (NEU!)
- ✅ **Auto-Flip Inverted Normals** - Automatische Korrektur für Terrain-Modelle (NEU!)
- ✅ **Image Format Detection** - Magic Bytes statt Dateiendung (NEU!)

### Content Creation Tools (NEU!)
- ✅ **Miniature Pipeline** - Gemini → TRELLIS.2 Workflow
- ✅ **GUI Batch Processor** - Tkinter-basierte Batch-Konvertierung
- ✅ **Intelligente Watermark Removal** - Automatische Background-Sampling
- ✅ **Preprocessing Pipeline** - White Background Removal + Upload zu HuggingFace

---

## 📋 In Arbeit (Milestone 2)

### Deployment Zones (Teilweise implementiert)
- ✅ **Front-line (12")** - Implementiert und visualisiert
- [ ] **Corner Deployment** - Noch nicht implementiert
- [ ] **Dawn Assault** - Noch nicht implementiert
- [ ] **Pitched Battle** - Noch nicht implementiert
- [ ] **Meeting Engagement** - Noch nicht implementiert

### Terrain-Gameplay Integration
- ✅ **LOS-Blocking Check** - Funktion implementiert (is_terrain_los_blocking)
- ✅ **Terrain Hints** - Anzeige für Difficult/Dangerous Terrain
- [ ] **Cover-System** - Gameplay-Mechanik für Deckung (Würfelmodifikatoren)
- [ ] **Schwieriges Gelände** - Movement-Modifikatoren anwenden
- [ ] **Dangerous Terrain** - Schaden bei Betreten
- [ ] **Terrain-Höhen** - Height 5 Objekte für Sichtlinien-Berechnung

### Gameplay-Features
- [ ] Einheiten-Karten und erweiterte Stats im 3D-Spiel
- [ ] Erweiterte Würfel-Optionen (Modifikatoren, Rerolls)
- [x] **Phasen-Management System** - Turn-Tracker mit Runden und Aktivierungen (activation_tracker.gd)
- [x] **Wunden-Tracking pro Modell** - wounds_dialog.gd mit +/- Buttons
- [x] **Status-Marker** - Standard OPR + Custom Freetext (marker_dialog.gd, unit_marker.gd)

### UI-Verbesserungen
- [ ] In-Game HUD Overhaul
- [x] **Radial Context Menu** - radial_menu.gd mit Kontext-Erkennung
- [ ] Minimap mit Terrain-Overlay
- [ ] Multiplayer Lobby UI
- [ ] Load Game Dialog

### Unit-System (NEU!)
- [x] **Model-Level Architektur** - ModelInstance mit generischem Properties-Dictionary
- [x] **GameUnit Wrapper** - System-agnostisch (OPR, WGS, generisch)
- [x] **Equipment-Verteilung** - Automatisch basierend auf API-Count
- [x] **Coherency-System** - 1" Model-zu-Model, 9" Kette, visuelle Darstellung
- [x] **Hero-Attachment** - Manueller Dialog nach Import
- [x] **Multiplayer Sync** - RPCs für Wounds, Markers, Activation, Hero-Attachment
- [x] **Save/Load Integration** - GameUnit-Serialisierung mit Model-Positionen

### AI-System (NEU!) - OPR Solo & Co-Op Rules v3.5.0
- [x] **Unit-Klassifizierung** - Hybrid/Shooting/Melee basierend auf Waffen
- [x] **Decision Trees** - Alle 3 Entscheidungsbäume aus OPR-Regeln
- [x] **Target Selector** - Prioritätsregeln für AP, Deadly, Takedown, Unstoppable
- [x] **Aktivierungsreihenfolge** - Sektions-basiert (D3 für Sektion)
- [x] **Special Rules** - Ambush, Scout, Transport, Artillery, Caster, Flying, Strider
- [x] **Objective Placement** - 6-Quadrat-Grid, zufällige Platzierung
- [x] **Challenge Bonus** - Optional +1 Hit/Defense basierend auf Objectives
- [ ] **Kampf-Integration** - Würfelsystem für AI-Angriffe
- [ ] **Terrain-Integration** - Vollständige Cover/Difficult/Dangerous Logik

---

## 🏗️ Technologie-Stack

| Komponente | Technologie |
|------------|-------------|
| **Engine** | Godot 4.3+ |
| **Sprache** | GDScript |
| **Netzwerk** | ENet (Desktop) |
| **3D-Format** | glTF 2.0, STL, OBJ |
| **Plattformen** | Windows, Linux, macOS |
| **Rendering** | Forward+ (Vulkan) |

---

## 📁 Projektstruktur

```
openTTS/
├── scenes/                  # Godot-Szenen
│   ├── main.tscn           # Hauptszene
│   ├── startup_menu.tscn   # Startmenü
│   ├── map_layout.tscn     # Map Layout Editor
│   ├── radial_menu.tscn    # NEU: Radial Context Menu
│   └── opr_stats_tooltip.tscn
├── scripts/                 # GDScript-Dateien
│   ├── main.gd             # Hauptszene-Controller
│   ├── camera_controller.gd
│   ├── table.gd
│   ├── object_manager.gd
│   ├── selectable_object.gd
│   ├── map_layout.gd       # Map Layout Editor (852 Zeilen)
│   ├── map_layout_grid.gd  # Grid Rendering (272 Zeilen)
│   ├── terrain_overlay.gd  # 3D Overlay (150 Zeilen)
│   ├── network_manager.gd  # Mit GameUnit Sync RPCs
│   ├── save_manager.gd     # Mit GameUnit Serialisierung
│   ├── lighting_controller.gd
│   ├── theme_manager.gd
│   ├── tts_importer.gd
│   ├── opr_api_client.gd
│   ├── opr_army_manager.gd # Mit GameUnit Integration
│   ├── wgs_client.gd
│   ├── model_instance.gd   # NEU: Model-Level Daten
│   ├── game_unit.gd        # NEU: System-agnostischer Unit-Wrapper
│   ├── equipment_distributor.gd  # NEU: Waffen-Verteilung
│   ├── unit_utils.gd       # NEU: Unit-Erkennung Helpers
│   ├── coherency_checker.gd     # NEU: Coherency-Validierung
│   ├── coherency_visualizer.gd  # NEU: Visuelle Coherency-Linien
│   ├── unit_marker.gd      # NEU: Standard + Custom Marker
│   ├── radial_menu.gd      # NEU: Pie-Menu UI
│   ├── radial_menu_controller.gd  # NEU: Kontext-Handler
│   ├── wounds_dialog.gd    # NEU: Wunden-Tracking Dialog
│   ├── marker_dialog.gd    # NEU: Marker-Verwaltung Dialog
│   ├── activation_tracker.gd    # NEU: Runden/Aktivierungs-Panel
│   ├── hero_attachment_dialog.gd  # NEU: Hero-Zuweisung
│   ├── ai_manager.gd            # NEU: AI-Gegner Controller
│   ├── ai_unit_classifier.gd    # NEU: Hybrid/Shooting/Melee
│   ├── ai_decision_tree.gd      # NEU: OPR Decision Trees
│   ├── ai_context.gd            # NEU: AI Game State
│   ├── ai_target_selector.gd    # NEU: Target Priorität
│   ├── ai_special_rules.gd      # NEU: Special Rules Handler
│   ├── ai_objective_setup.gd    # NEU: Objective Placement
│   └── ...
├── assets/                  # Texturen, Modelle, Audio
│   ├── miniatures/
│   │   └── alien_hives/    # Pipeline mit GUI (NEU!)
│   │       ├── pipeline_gui.py
│   │       ├── batch_convert.py
│   │       └── Start Pipeline.bat/.command
│   ├── kenney_ui/          # Kenney UI Assets (NEU!)
│   └── textures/
├── addons/                  # Godot Addons
│   └── dice_roller/
├── docs/                    # Dokumentation
│   ├── ASSETS.md
│   ├── DICE_PHYSICS_WIP.md
│   ├── OPR_API_Research_Report.md
│   └── README.md           # Docs Index (NEU!)
├── examples/                # Beispiel-Dateien (NEU!)
│   ├── README.md
│   └── Custodian Brothers.json
├── serve_web.py            # Python Server für Web Export (NEU!)
├── README.md               # Projekt-Readme
├── PLAN.md                 # Entwicklungsplan
└── PROJECT_STATUS.md       # Dieser Status-Bericht
```

---

## 🚀 Nächste Schritte (Priorität)

### Kurzfristig (Diese Woche)
1. ✅ **Deployment Zones (Front-line)** - Im 3D-Spiel visualisiert
2. ✅ **Deployment Mode** - Zone Compliance Checking implementiert
3. ✅ **Terrain Hints** - Anzeige für Difficult/Dangerous Terrain
4. **Weitere Deployment Zones** - Corner, Dawn Assault, Pitched Battle, Meeting Engagement
5. **Cover-System** - Gameplay-Mechanik für Würfelmodifikatoren

### Mittelfristig (Diesen Monat)
1. **Terrain-Gameplay Mechaniken** - Cover-Würfel, Movement-Modifikatoren, Dangerous-Schaden
2. **Einheiten-Karten** - Erweiterte Stats-Anzeige im 3D-Spiel
3. **Phasen-Management** - Turn-Tracker, Aktivierungs-System
4. **Wunden-Tracking** - HP-Anzeige pro Modell

### Langfristig (Milestone 3)
1. **Lobby-System** - Multiplayer-Lobby mit Raum-Browser
2. **Chat-System** - Text-Chat mit Würfel-Notation
3. **Voice-Chat** - Integration (optional)
4. **Kampagnen-System** - Persistente Kampagnen mit Progression

---

## 📊 Performance-Metriken

| Szenario | Target | Aktuell |
|----------|--------|---------|
| 200 Objekte | 60 FPS | ✅ 60+ FPS |
| 1000 Objekte | 30 FPS | ✅ 45+ FPS |
| Multiplayer (2 Spieler) | < 100ms Latenz | ✅ ~50ms |
| Ladezeit Standard-Spiel | < 5s | ✅ ~2s |

---

## 🐛 Bekannte Issues

### Kritisch
- Keine kritischen Issues bekannt

### Medium
- [ ] Würfel-Physik kann manchmal jittern (siehe docs/DICE_PHYSICS_WIP.md)
- [ ] TTS Texture Loading Errors (sekundär)

### Low
- [ ] GDScript Warnungen (parameter shadowing)
- [ ] Metal LOD bias sampler warning (macOS-spezifisch)

---

## 📝 Dokumentation

### Haupt-Dokumentation
- `README.md` - Schnellstart & Übersicht
- `PLAN.md` - Detaillierter Entwicklungsplan
- `PROJECT_STATUS.md` - Dieser Status-Bericht

### Technische Dokumentation
- `docs/WGS_INTEGRATION.md` - Wargaming Simulator Integration
- `docs/UI_OVERHAUL_README.md` - UI Design & Mockups
- `docs/GRAPHICS_UPGRADE_PLAN.md` - Rendering-Upgrade Plan
- `docs/UI_DESIGN_SYSTEM.md` - UI Design-System
- `docs/DICE_PHYSICS_WIP.md` - Würfel-Physik (WIP)
- `docs/ASSETS.md` - Asset-Quellen & Lizenzen
- `docs/OPR_API_Research_Report.md` - OPR API Recherche

---

## 🤝 Entwicklung

### Aktive Branches
- `main` - Stabile Version mit allen Features

### Recent Commits (2026-01-06)
- `b97ff8b` - Merge: Fix Godot filesystem warning PR
- `fe4c68c` - fix: Correct VIEW vector direction in shader
- `f460b50` - fix: Improve shader to handle all inverted normal cases
- `80c18c4` - fix: Add two-sided lighting shader for terrain models
- `0af9f06` - fix: Use original OBJ normals instead of recalculating
- `e54ad6e` - fix: Improve normal calculation and silence metadata warnings
- `12e5b3a` - fix: Auto-flip inverted normals for terrain models
- `5f0be30` - fix: Detect image format from magic bytes, not file extension
- `b5f0eb9` - fix: Recalculate normals for terrain models to fix lighting
- `d3bcdc4` - fix: Replace material-based highlight with ring overlay

---

## 📄 Lizenz

MIT License - Siehe [LICENSE](./LICENSE) für Details.

---

**Status:** ✅ Alpha-Version funktionsfähig, aktive Entwicklung
**Contributors:** DutchMaxwell, Community
**Letzte Aktualisierung:** 2026-01-06
