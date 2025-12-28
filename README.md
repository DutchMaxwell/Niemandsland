# OpenTTS - Open-Source Wargaming Tabletop Simulator

Ein Open-Source Tabletop-Simulator mit Fokus auf Wargaming-Spiele wie OnePageRules, historische Wargames und andere Miniaturenspiele.

## Status: Milestone 1 ✅ abgeschlossen, Milestone 2 (Alpha) in Arbeit

**Aktuelle Features:**

- 3D Spieltisch (variable Größen: 4x4, 6x4, custom)
- Kamera-Steuerung (Orbit, Pan, Zoom)
- TTS Import (Online von Steam CDN + Local Cache)
- Multi-Selection (Alt+Click, Box-Select)
- Arrangement-Funktionen (1-9 für Reihen, A für Pfeil-Formation)
- Copy/Paste (Ctrl+C/V/D) mit Cursor-Positionierung
- Speichern/Laden von Spielständen (.otts Format)
- Würfel-System mit Physik-Simulation (Dice Roller Plugin)
- Distanzmessung in Zoll
- Multiplayer (getestet mit localhost, inkl. State-Sync beim Laden)
- Performance: 1000+ Objekte flüssig

## Schnellstart

### Desktop-Version (Empfohlen)
**Hinweis:** Browser-Version ist zurückgestellt. Desktop-First ist die aktuelle Entwicklungsstrategie.
1. [Godot 4.3+](https://godotengine.org/download) herunterladen
2. Repository klonen: `git clone https://github.com/DutchMaxwell/openTTS.git`
3. Projekt in Godot öffnen
4. F5 drücken zum Starten

## Steuerung

| Aktion | Eingabe |
|--------|---------|
| Kamera rotieren | Rechtsklick + Ziehen |
| Kamera schwenken | Mittelklick + Ziehen |
| Zoomen | Mausrad |
| Objekt auswählen/ziehen | Linksklick |
| Objekt rotieren | R |
| Würfel werfen | Leertaste |

## Projektstruktur

```
openTTS/
├── scenes/          # Godot-Szenen
├── scripts/         # GDScript-Dateien
│   ├── main.gd              # Hauptszene-Controller
│   ├── camera_controller.gd # Kamera-Steuerung
│   ├── table.gd             # Spieltisch
│   ├── object_manager.gd    # Objekt-Verwaltung
│   └── selectable_object.gd # Auswahl-Logik
├── assets/          # Texturen, Modelle, Audio
├── PLAN.md          # Detaillierter Entwicklungsplan
└── project.godot    # Godot-Projektdatei
```

## Vision

OpenTTS soll eine freie Alternative zum kommerziellen Tabletop Simulator bieten, die speziell auf die Bedürfnisse von Wargamern zugeschnitten ist:

- **Browser-First**: Spielbar ohne Installation
- **Wargaming-First Design**: Alle Features sind auf Miniaturenspiele optimiert
- **OnePageRules Integration**: Native Unterstützung für OPR-Spielsysteme
- **Mess-Tools**: Professionelle Werkzeuge für Distanzmessung, Sichtlinien und Templates
- **Army Builder**: Integrierter Import von Army Forge und Battlescribe
- **Open Source**: Vollständig quelloffen und Community-getrieben

## Geplante Features

Siehe [PLAN.md](./PLAN.md) für den vollständigen Entwicklungsplan.

### Nächste Schritte (Milestone 2: Alpha)
- [ ] Gelände-System mit Eigenschaften (Deckung, Schwieriges Gelände)
- [ ] Einheiten-Karten und Stats
- [x] ~~Speichern/Laden von Tisch-Setups~~
- [ ] Erweiterte Würfel-Optionen (Modifikatoren, mehr Typen)
- [ ] UI-Überarbeitung

## Technologie-Stack

- **Engine**: Godot 4.3+ (Open-Source)
- **Sprache**: GDScript
- **3D-Format**: glTF 2.0
- **Netzwerk**: ENet (Desktop) + WebRTC (Web)
- **Plattformen**: Windows, Linux, macOS, **Web**

## Mitmachen

Beiträge sind willkommen!

1. Lies den [PLAN.md](./PLAN.md) für einen Überblick
2. Fork das Repository
3. Erstelle einen Feature-Branch
4. Pull Request erstellen

## Lizenz

MIT License - Siehe [LICENSE](./LICENSE) für Details.

---

*Inspiriert von der Wargaming-Community, für die Wargaming-Community.*
