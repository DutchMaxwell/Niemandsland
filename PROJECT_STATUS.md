# OpenTTS - Projekt Status
**Stand:** 2026-01-01
**Version:** 0.2-alpha
**Branch:** `claude/cleanup-and-docs-0Ri4c`

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

---

## 📋 In Arbeit (Milestone 2)

### UI-Verbesserungen
- [ ] Erweiterte Settings-Menü-Integration
- [ ] In-Game HUD Overhaul
- [ ] Radial Context Menu
- [ ] Minimap

### Gameplay-Features
- [ ] Gelände-System mit Eigenschaften (Deckung, Schwieriges Gelände)
- [ ] Einheiten-Karten und erweiterte Stats
- [ ] Erweiterte Würfel-Optionen (Modifikatoren, mehr Typen)
- [ ] Phasen-Management System

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
│   └── opr_stats_tooltip.tscn
├── scripts/                 # GDScript-Dateien
│   ├── main.gd             # Hauptszene-Controller
│   ├── camera_controller.gd
│   ├── table.gd
│   ├── object_manager.gd
│   ├── selectable_object.gd
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
│   └── textures/
├── addons/                  # Godot Addons
│   └── dice_roller/
├── docs/                    # Dokumentation
│   ├── WGS_INTEGRATION.md
│   ├── UI_OVERHAUL_README.md
│   ├── GRAPHICS_UPGRADE_PLAN.md
│   └── ...
├── README.md               # Projekt-Readme
├── PLAN.md                 # Entwicklungsplan
└── PROJECT_STATUS.md       # Dieser Status-Bericht
```

---

## 🚀 Nächste Schritte (Priorität)

### Kurzfristig (Diese Woche)
1. **Dokumentation aufräumen** - Veraltete Docs entfernen/aktualisieren
2. **UI Polish** - Settings-Menü vollständig integrieren
3. **Testing** - Graphics Quality Presets testen

### Mittelfristig (Diesen Monat)
1. **Gelände-System** - Eigenschaften (Deckung, Schwieriges Gelände)
2. **Einheiten-Karten** - Erweiterte Stats-Anzeige
3. **Phasen-Management** - Turn-basiertes Spiel unterstützen

### Langfristig (Milestone 3)
1. **Lobby-System** - Multiplayer-Lobby mit Raum-Browser
2. **Chat-System** - Text-Chat mit Würfel-Notation
3. **Voice-Chat** - Integration (optional)

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
- `main` - Stabile Version
- `claude/cleanup-and-docs-0Ri4c` - Dokumentation & Cleanup (aktuell)

### Recent Commits
- `f268955` - Standard Untergrund
- `3a830bc` - Merge: Wargaming Integration
- `83235ec` - Graphics Settings Autoload
- `595e0d0` - Graphics Quality Selector
- `1a09ced` - Camera Easing Improvements
- `1f1546f` - Graphics Quality Improvements
- `61a1e7b` - Tron-Style Intro

---

## 📄 Lizenz

MIT License - Siehe [LICENSE](./LICENSE) für Details.

---

**Status:** ✅ Alpha-Version funktionsfähig, aktive Entwicklung
**Contributors:** DutchMaxwell, Community
**Letzte Aktualisierung:** 2026-01-01
