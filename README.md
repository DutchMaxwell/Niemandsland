# OpenTTS - Open-Source Wargaming Tabletop Simulator

Ein Open-Source Tabletop-Simulator mit Fokus auf Wargaming-Spiele wie OnePageRules, historische Wargames und andere Miniaturenspiele.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Godot Engine](https://img.shields.io/badge/Godot-4.3+-blue.svg)](https://godotengine.org/)
[![Status](https://img.shields.io/badge/Status-Alpha-orange.svg)]()

---

## 🎮 Status: Milestone 2 (Alpha) in Arbeit

**Aktuelle Features:**

### ⚔️ Gameplay
- ✅ 3D Spieltisch (variable Größen: 4x4, 6x4, custom)
- ✅ Kamera-Steuerung (Orbit, Pan, Zoom mit Easing)
- ✅ Multi-Selection (Alt+Click, Box-Select)
- ✅ Arrangement-Funktionen (1-9 für Reihen, A für Pfeil-Formation)
- ✅ Copy/Paste (Ctrl+C/V/D) mit Cursor-Positionierung
- ✅ Würfel-System mit Physik (D4, D6, D8, D10, D12, D20, D100)
- ✅ Distanzmessung in Zoll

### 🗺️ Terrain & Map Layout
- ✅ **Map Layout Editor** - Top-down 3" Grid für Terrain-Planung
- ✅ **4 Terrain-Typen**: Ruins (Cover), Forest (Difficult+Cover), Container (Blocking), Dangerous (Minefields)
- ✅ **Deployment Zones**:
  - **Front-line (12")** - Standard OPR Free Rules Deployment
  - **Custom Polygon Zones** - Zeichne eigene Aufstellungszonen mit 1" Raster
  - **Symmetrisch/Asymmetrisch** - Punktsymmetrische oder individuelle Zonen
- ✅ **Objectives System** - Platzierung von bis zu 6 Zielpunkten (abwechselnd)
- ✅ **Auto-Generate** - Automatische Terrain-Generierung mit Symmetrie-Option
- ✅ **3D Overlay** - Terrain-Grid im 3D-Spiel visualisiert
- ✅ **Save/Load Layouts** - Terrain-Setups speichern und wiederverwenden

### 🌐 Multiplayer
- ✅ Multiplayer-Support (ENet-basiert)
- ✅ State-Sync beim Laden
- ✅ Getestet mit localhost

### 🤖 AI-System (OPR Solo & Co-Op Rules v3.5.0)
- ✅ **Battle Simulator** - Vollständige KI vs KI Kampfsimulation
- ✅ **Step-by-Step Visualisierung** - Jeder Kampfschritt mit Pause/Play/Speed-Control
- ✅ **OPR Decision Trees** - Alle 3 Entscheidungsbäume (Hybrid, Shooting, Melee)
- ✅ **Unit-Klassifizierung** - Automatisch basierend auf Waffen-Loadout
- ✅ **Target Priority System** - AP, Deadly, Takedown, Unstoppable Regeln
- ✅ **Morale System** - Vollständige Flucht-/Rout-Mechanik mit Consolidation Moves
- ✅ **Special Rules** - Ambush, Scout, Transport, Artillery, Caster, Flying, Strider

### 📦 Import/Export
- ✅ TTS Import (Online von Steam CDN + Local Cache)
- ✅ Custom 3D Models (glTF, STL, OBJ)
- ✅ Speichern/Laden (.otts Format)
- ✅ OPR Army Forge Integration
- ✅ Wargaming Simulator (WGS) Import/Export

### 🎨 Graphics & UI
- ✅ Theme-System (9 Kenney UI Themes)
- ✅ Lighting Presets (F1-F4: Default, Studio, Dramatic, Night)
- ✅ Graphics Quality Settings (Low, Medium, High, Ultra)
- ✅ Tron-Style Intro Animation
- ✅ High-Quality Shadows (8K, 16-bit)
- ✅ Post-Processing (SSAO, SSR, Glow)

### ⚡ Performance
- ✅ 1000+ Objekte flüssig darstellbar
- ✅ Optimierte Shadow Cascades
- ✅ Multi-Threading Support

---

## 🚀 Schnellstart

### Voraussetzungen
- [Godot 4.3+](https://godotengine.org/download) (Desktop-Version empfohlen)

### Installation
```bash
# Repository klonen
git clone https://github.com/DutchMaxwell/openTTS.git
cd openTTS

# Projekt in Godot öffnen
# Godot Editor starten → "Import" → project.godot auswählen

# Oder direkt mit Godot-CLI
godot --path . --editor
```

### Starten
1. F5 drücken oder "Run Project" im Editor
2. Genieße das Tron-Style Intro
3. Wähle "Quick Battle" für ein Schnellspiel

---

## 🎮 Steuerung

### Kamera
| Aktion | Eingabe |
|--------|---------|
| Kamera rotieren | Rechtsklick + Ziehen |
| Kamera schwenken | Mittelklick + Ziehen |
| Zoomen | Mausrad |
| Reset Kamera | Home |

### Objekte
| Aktion | Eingabe |
|--------|---------|
| Objekt auswählen | Linksklick |
| Multi-Select | Alt + Linksklick |
| Box-Select | Linksklick + Ziehen (auf Tisch) |
| Objekt ziehen | Linksklick + Ziehen |
| Objekt rotieren | R (während Auswahl) |
| Objekt löschen | Entf oder Backspace |
| Copy | Strg + C |
| Paste | Strg + V |
| Duplicate | Strg + D |

### Arrangement (Multi-Select)
| Taste | Funktion |
|-------|----------|
| 1-9 | Reihen-Formation (1 = 1 Reihe, 2 = 2 Reihen, etc.) |
| A | Pfeil-Formation |

### Würfeln
| Aktion | Eingabe |
|--------|---------|
| Würfel werfen | Leertaste |
| Würfel auswählen | Würfel-Menü (UI) |

### Lighting & UI
| Aktion | Eingabe |
|--------|---------|
| Default Lighting | F1 |
| Studio Lighting | F2 |
| Dramatic Lighting | F3 |
| Night Lighting | F4 |

---

## 📋 Features im Detail

### Map Layout Editor
Plane dein Spielfeld mit dem integrierten Map Layout Editor:
- **Top-Down Ansicht** mit 3" Grid (OPR-Standard)
- **4 Terrain-Typen**:
  - **Ruins**: Höhe 5, gibt Deckung, Wände unpassierbar
  - **Forest**: Höhe 5, schwieriges Gelände + Deckung
  - **Container**: Höhe 5, unpassierbar + blockiert Sichtlinien komplett
  - **Dangerous**: Offen, gefährlich (Minenfelder, Säure, Strahlung)
- **Symmetrie-Modus**: Automatisches Spiegeln über Tischmitte
- **Auto-Generate**: Zufällige faire Terrain-Layouts
- **OPR Guidelines**: Echtzeit-Feedback zu Terrain-Empfehlungen
- **3D Overlay**: Sieh das Grid direkt im 3D-Spiel

### Deployment Zones
Aufstellungszonen für beide Spieler:
- **Front-line (12")**: Standard-Aufstellung aus den OPR Free Rules - 12" von der langen Tischkante
- **Custom Polygon Zones**: Zeichne eigene Aufstellungszonen als Polygone
  - **1" Feines Raster**: Höhere Auflösung für präzise Platzierung
  - **Symmetrischer Modus**: Beide Zonen werden gleichzeitig punktsymmetrisch gezeichnet
  - **Asymmetrischer Modus**: Zuerst Spieler 1, dann Spieler 2 separat zeichnen
  - **Vertex-Marker**: Nummerierte Punkte zeigen die Polygon-Ecken
  - **Table Corner Snap Points**: Vertices snappen an Tischecken und Kanten
- **Hinweis**: Weitere Deployment-Typen (Ground War, Spearhead, etc.) können mit Custom Zones manuell nachgebaut werden

### Objectives
- **Bis zu 6 Zielpunkte** platzieren
- **Abwechselnde Platzierung** gemäß OPR-Regeln
- **40mm Marker** mit gelber Basis und schwarzem Rand

### TTS Import
Importiere 3D-Modelle direkt vom Tabletop Simulator Steam CDN:
- Online-Download mit automatischem Caching
- Unterstützte Formate: glTF, STL, OBJ
- Skalierung und Base-Support

### OPR Integration
- Import von Army Forge Listen
- Stats-Tooltips beim Hover über Einheiten
- Direkte API-Integration

### WGS Integration
- Import/Export von Wargaming Simulator Spielzuständen
- Koordinaten-Konvertierung
- Async-Play Support (geplant)

### Multiplayer
- Host/Join Funktionalität
- State-Synchronisation
- Speichern/Laden im Multiplayer

---

## 🏗️ Projektstruktur

```
openTTS/
├── scenes/          # Godot-Szenen
│   ├── main.tscn              # Hauptszene
│   └── startup_menu.tscn      # Startmenü
├── scripts/         # GDScript-Dateien
│   ├── main.gd                # Hauptszene-Controller
│   ├── camera_controller.gd   # Kamera-Steuerung
│   ├── table.gd               # Spieltisch
│   ├── object_manager.gd      # Objekt-Verwaltung
│   ├── selectable_object.gd   # Auswahl-Logik
│   ├── network_manager.gd     # Multiplayer
│   ├── save_manager.gd        # Speichern/Laden
│   ├── lighting_controller.gd # Beleuchtung
│   ├── theme_manager.gd       # UI-Themes
│   ├── tts_importer.gd        # TTS Import
│   ├── opr_api_client.gd      # OPR API
│   ├── wgs_client.gd          # WGS Integration
│   ├── ai_manager.gd          # AI-Gegner Controller
│   ├── ai_decision_tree.gd    # OPR Decision Trees
│   ├── ai_target_selector.gd  # Target Priorität
│   └── battle_simulator.gd    # KI vs KI Simulation
├── assets/          # Texturen, Modelle, Audio
├── addons/          # Godot Addons
│   └── dice_roller/           # Würfel-System
├── docs/            # Dokumentation
├── PLAN.md          # Entwicklungsplan
└── PROJECT_STATUS.md # Projekt-Status
```

---

## 🎯 Vision

OpenTTS soll eine freie Alternative zum kommerziellen Tabletop Simulator bieten, die speziell auf die Bedürfnisse von Wargamern zugeschnitten ist:

- **Desktop-First**: Beste Performance und Features
- **Wargaming-First Design**: Alle Features sind auf Miniaturenspiele optimiert
- **OnePageRules Integration**: Native Unterstützung für OPR-Spielsysteme
- **Mess-Tools**: Professionelle Werkzeuge für Distanzmessung, Sichtlinien und Templates
- **Army Builder**: Integrierter Import von Army Forge und Battlescribe
- **Open Source**: Vollständig quelloffen und Community-getrieben

---

## 📝 Geplante Features

Siehe [PLAN.md](./PLAN.md) für den vollständigen Entwicklungsplan.

### Milestone 2 (Alpha) - In Arbeit
- [x] Map Layout Editor mit Terrain-Typen
- [x] Deployment Zones (Front-line + Custom Polygon)
- [x] Objectives System mit abwechselnder Platzierung
- [x] 1" Grid für Custom Zone Editing
- [x] Deployment Zones im 3D-Spiel visualisiert
- [x] Phasen-Management System (Turn-Tracker, Aktivierung)
- [x] Wunden-Tracking pro Modell
- [x] **AI-System (OPR Solo & Co-Op Rules v3.5.0)**
- [x] **Battle Simulator** - Vollständige KI vs KI Kampfsimulation mit Step-by-Step Visualisierung
- [ ] **Terrain-Gameplay Integration** (PRIORITÄT):
  - [ ] Cover-System (Ruins, Forest geben Deckung)
  - [ ] Schwieriges Gelände (Movement-Modifikatoren)
  - [ ] LOS-Blocking (Container blockieren Sicht)
  - [ ] Dangerous Terrain (Schaden bei Betreten)
- [ ] Einheiten-Karten und erweiterte Stats

### Milestone 3 (Beta)
- [ ] Vollständige Multiplayer-Lobby
- [ ] Chat-System
- [ ] Voice-Chat (optional)
- [ ] Erweiterte OPR-Integration

---

## 💻 Technologie-Stack

- **Engine**: Godot 4.3+ (Open-Source)
- **Sprache**: GDScript
- **3D-Format**: glTF 2.0, STL, OBJ
- **Netzwerk**: ENet (Desktop)
- **Rendering**: Forward+ (Vulkan/OpenGL 4.6)
- **Plattformen**: Windows, Linux, macOS

---

## 🤝 Mitmachen

Beiträge sind willkommen!

### Development Setup
1. Fork das Repository
2. Erstelle einen Feature-Branch (`git checkout -b feature/amazing-feature`)
3. Committe deine Änderungen (`git commit -m 'Add amazing feature'`)
4. Push zum Branch (`git push origin feature/amazing-feature`)
5. Öffne einen Pull Request

### Dokumentation
- [Entwicklungsplan](./PLAN.md) - Roadmap & Features
- [Projekt-Status](./PROJECT_STATUS.md) - Aktueller Stand
- [WGS Integration](./docs/WGS_INTEGRATION.md) - Wargaming Simulator Integration
- [UI Design](./docs/UI_OVERHAUL_README.md) - UI/UX Mockups

### Community
- GitHub Issues für Bug-Reports & Feature-Requests
- Discord (coming soon)
- Forum (coming soon)

---

## 📊 System-Anforderungen

### Minimum (Low Preset)
- **OS**: Windows 10, Ubuntu 20.04, macOS 10.15+
- **CPU**: Intel i5-4460 / AMD FX-6300
- **RAM**: 8 GB
- **GPU**: GTX 960 / RX 560 (4GB VRAM)
- **Storage**: 2 GB

### Empfohlen (Medium Preset)
- **OS**: Windows 11, Ubuntu 22.04, macOS 12+
- **CPU**: Intel i5-8400 / AMD Ryzen 5 2600
- **RAM**: 16 GB
- **GPU**: GTX 1660 / RX 580 (6GB VRAM)
- **Storage**: 5 GB

### High-End (Ultra Preset)
- **CPU**: Intel i7-10700K / AMD Ryzen 7 5800X
- **RAM**: 32 GB
- **GPU**: RTX 3080 / RX 6800 XT (10GB VRAM)
- **Storage**: 10 GB (mit Mods)

---

## 📄 Lizenz

MIT License - Siehe [LICENSE](./LICENSE) für Details.

---

## 🙏 Credits

### Projekt
- **Entwicklung**: DutchMaxwell & Community
- **Engine**: Godot Engine Foundation

### Assets & Libraries
- **UI Themes**: Kenney.nl (CC0)
- **Dice Roller**: Godot Dice Roller Plugin (MIT)
- **Icons**: Lucide Icons (MIT)

Siehe [docs/ASSETS.md](./docs/ASSETS.md) für vollständige Asset-Attributionen.

---

## 📞 Kontakt

- **GitHub**: [DutchMaxwell/openTTS](https://github.com/DutchMaxwell/openTTS)
- **Issues**: [GitHub Issues](https://github.com/DutchMaxwell/openTTS/issues)

---

*Inspiriert von der Wargaming-Community, für die Wargaming-Community.*

**Version**: 0.2-alpha
**Status**: Active Development
**Letzte Aktualisierung**: 2026-01-13
