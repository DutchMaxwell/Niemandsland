# OpenTTS - Projekt Status
**Stand:** 2026-01-01
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

### Content Creation Tools (NEU!)
- ✅ **Miniature Pipeline** - Gemini → TRELLIS.2 Workflow
- ✅ **GUI Batch Processor** - Tkinter-basierte Batch-Konvertierung
- ✅ **Intelligente Watermark Removal** - Automatische Background-Sampling
- ✅ **Preprocessing Pipeline** - White Background Removal + Upload zu HuggingFace

---

## 📋 In Arbeit (Milestone 2)

### Terrain-Gameplay Integration (PRIORITÄT!)
- [ ] **Deployment Zones im 3D-Spiel** - Sichtbare Zonen beim Spielstart
- [ ] **Cover-System** - Deckung durch Terrain (Ruins, Forest)
- [ ] **Schwieriges Gelände** - Movement-Modifikatoren (Forest)
- [ ] **LOS-Blocking** - Container blockieren Sichtlinien komplett
- [ ] **Dangerous Terrain** - Schaden bei Betreten (Minefields, Acid)
- [ ] **Terrain-Höhen** - Height 5 Objekte für Sichtlinien

### Gameplay-Features
- [ ] Einheiten-Karten und erweiterte Stats
- [ ] Erweiterte Würfel-Optionen (Modifikatoren, mehr Typen)
- [ ] Phasen-Management System (Turn-Tracker, Aktivierung)
- [ ] Wunden-Tracking pro Modell
- [ ] Status-Marker (Aktiviert, Pinned, etc.)

### UI-Verbesserungen
- [ ] In-Game HUD Overhaul
- [ ] Radial Context Menu
- [ ] Minimap mit Terrain-Overlay
- [ ] Erweiterte Settings-Menü-Integration

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
│   ├── map_layout.tscn     # Map Layout Editor (NEU!)
│   └── opr_stats_tooltip.tscn
├── scripts/                 # GDScript-Dateien
│   ├── main.gd             # Hauptszene-Controller
│   ├── camera_controller.gd
│   ├── table.gd
│   ├── object_manager.gd
│   ├── selectable_object.gd
│   ├── map_layout.gd       # Map Layout Editor (NEU! 852 Zeilen)
│   ├── map_layout_grid.gd  # Grid Rendering (NEU! 272 Zeilen)
│   ├── terrain_overlay.gd  # 3D Overlay (NEU! 150 Zeilen)
│   ├── network_manager.gd
│   ├── save_manager.gd
│   ├── lighting_controller.gd
│   ├── theme_manager.gd
│   ├── tts_importer.gd
│   ├── opr_api_client.gd
│   ├── wgs_client.gd
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
1. ✅ **Dokumentation aktualisieren** - PROJECT_STATUS.md, README.md, PLAN.md
2. **Deployment Zones ins 3D-Spiel** - Visualisierung beim Spielstart
3. **Cover-System implementieren** - Terrain gibt Deckung (Ruins, Forest)
4. **Schwieriges Gelände** - Movement-Modifikatoren aktivieren

### Mittelfristig (Diesen Monat)
1. **Terrain-Gameplay Features** - LOS-Blocking, Dangerous Terrain, Höhen
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
- `claude/merge-branches-to-main-8aVWC` - Alle Feature-Branches gemerged (aktuell)

### Recent Merges (2026-01-01)
- `74ef811` - Merge: Comprehensive cleanup and documentation update
- `24b65bc` - Merge: Fix watermark removal and add batch processing GUI
- `49de9dd` - Merge: Add Kenney UI assets (SciFi and Fantasy themes)
- `4b1d9b2` - Merge: Complete terrain editor with deployment zones, objectives, and auto-generate
- `5079956` - Merge: Add table background and terrain features from set-default-background

---

## 📄 Lizenz

MIT License - Siehe [LICENSE](./LICENSE) für Details.

---

**Status:** ✅ Alpha-Version funktionsfähig, aktive Entwicklung
**Contributors:** DutchMaxwell, Community
**Letzte Aktualisierung:** 2026-01-01
