# OpenTTS - Open-Source Wargaming Tabletop Simulator

## Projektübersicht

Ein Open-Source Tabletop-Simulator mit starkem Fokus auf Wargaming-Spiele (OnePageRules, Warhammer-Alternativen, historische Wargames). Inspiriert vom kommerziellen Tabletop Simulator, aber spezialisiert auf die Bedürfnisse von Miniaturenspielern.

---

## Phase 1: Technologie-Stack & Grundarchitektur

### 1.1 Technologie-Entscheidungen

| Komponente | Empfehlung | Begründung |
|------------|------------|------------|
| **Game Engine** | Godot 4.x | Open-Source, 3D-fähig, gute Performance, C#/GDScript |
| **Programmiersprache** | C# + GDScript | C# für komplexe Logik, GDScript für schnelles Prototyping |
| **Netzwerk** | Godot High-Level Multiplayer + WebRTC | P2P für geringe Latenz, optional dedizierte Server |
| **Datenformat** | JSON + SQLite | Portabel, leicht editierbar, gut für Modding |
| **3D-Modelle** | glTF 2.0 | Offener Standard, breite Tool-Unterstützung |
| **UI Framework** | Godot Control Nodes | Native Integration |
| **Build System** | Godot Export + GitHub Actions | Cross-Platform Builds |

### 1.2 Ordnerstruktur

```
openTTS/
├── src/
│   ├── core/                    # Kern-Engine
│   │   ├── physics/             # Physik-Simulation
│   │   ├── rendering/           # Rendering-Pipeline
│   │   ├── input/               # Input-Handling
│   │   └── networking/          # Multiplayer-Logik
│   ├── game/                    # Spiellogik
│   │   ├── objects/             # Spielobjekte (Miniaturen, Gelände, etc.)
│   │   ├── rules/               # Regelsystem-Engine
│   │   ├── measurement/         # Mess-Tools
│   │   └── dice/                # Würfelsystem
│   ├── ui/                      # Benutzeroberfläche
│   │   ├── hud/                 # In-Game HUD
│   │   ├── menus/               # Menüs
│   │   ├── army_builder/        # Armeebau-Tool
│   │   └── lobby/               # Multiplayer-Lobby
│   ├── data/                    # Daten-Management
│   │   ├── models/              # 3D-Modell-Loader
│   │   ├── armies/              # Armee-Daten
│   │   └── games/               # Spielsystem-Definitionen
│   └── modding/                 # Modding-API
├── assets/
│   ├── models/                  # Standard 3D-Modelle
│   ├── textures/                # Texturen
│   ├── ui/                      # UI-Assets
│   └── audio/                   # Sound-Effekte
├── data/
│   ├── game_systems/            # Spielsystem-Definitionen (OPR, etc.)
│   ├── default_armies/          # Beispiel-Armeen
│   └── terrain/                 # Gelände-Presets
├── docs/                        # Dokumentation
├── mods/                        # Community-Mods Ordner
└── tests/                       # Unit & Integration Tests
```

---

## Phase 2: Core Engine Features

### 2.1 3D-Spieltisch-System

**Priorität: KRITISCH**

- [ ] Konfigurierbarer Spieltisch (verschiedene Größen: 4x4, 4x6, 6x4 Fuß etc.)
- [ ] Spielmatten-System mit austauschbaren Texturen
- [ ] Grid-Overlay (optional, für Regelwerke die es benötigen)
- [ ] Höhenstufen-Unterstützung für mehrstöckiges Gelände
- [ ] Kamera-System mit freier 3D-Navigation
- [ ] Verschiedene Kamera-Modi (Orbit, First-Person, Top-Down)

### 2.2 Objekt-Manipulation

**Priorität: KRITISCH**

- [ ] Drag & Drop für alle Objekte
- [ ] Rotation (frei + Snap-to-Grid)
- [ ] Skalierung von Objekten
- [ ] Gruppen-Selektion und -Bewegung
- [ ] Formation-Tools (Reihe, Block, Keil)
- [ ] Undo/Redo-System
- [ ] Copy/Paste von Objekten
- [ ] Objekt-Locking (verhindert versehentliches Bewegen)

### 2.3 Physik-System

**Priorität: HOCH**

- [ ] Realistische Würfelphysik
- [ ] Kollisionserkennung für Miniaturen
- [ ] "Sticky" Bases (Miniaturen bleiben auf Gelände stehen)
- [ ] Optionale Physik-Deaktivierung für Performance
- [ ] Scatter-Mechanik für Templates

---

## Phase 3: Wargaming-Spezifische Features

### 3.1 Mess-System

**Priorität: KRITISCH**

- [ ] Lineal-Tool mit Zoll/cm Umschaltung
- [ ] Bewegungs-Templates (Kreise, Kegel, Linien)
- [ ] Reichweiten-Anzeige von Einheiten (Aura-Darstellung)
- [ ] Sichtlinien-Prüfung (Line of Sight)
- [ ] Kohärenz-Checker für Einheiten
- [ ] Bewegungspfad-Anzeige mit Distanz
- [ ] Mess-Historie (letzte Messungen sichtbar halten)

### 3.2 Würfelsystem

**Priorität: KRITISCH**

- [ ] Standard-Würfel: D4, D6, D8, D10, D12, D20, D100
- [ ] Würfel-Pools mit automatischer Auswertung
- [ ] Konfigurierbarer Würfelturm/Würfelbereich
- [ ] Würfel-Makros für häufige Würfe
- [ ] Würfel-Historie mit Export
- [ ] Würfel-Modifikatoren (Rerolls, +X, etc.)
- [ ] Spezialwürfel (Scatter-Würfel, Hit/Miss-Würfel)
- [ ] Würfel-Farbkodierung nach Spieler

### 3.3 Einheiten-Management

**Priorität: KRITISCH**

- [ ] Einheiten-Karten mit Stats (importierbar aus OPR Army Forge etc.)
- [ ] Wunden-Tracking pro Modell
- [ ] Status-Marker (Aktiviert, Pinned, etc.)
- [ ] Einheiten-Aktivierungs-Tracker
- [ ] Befehls-/Strategiepunkte-Counter
- [ ] Quick-Reference für Einheiten-Regeln

### 3.4 Gelände-System

**Priorität: HOCH**

- [ ] Gelände-Bibliothek mit Kategorien
- [ ] Gelände-Eigenschaften (Deckung, Schwieriges Gelände, Blockierend)
- [ ] Schnelles Terrain-Setup mit Presets
- [ ] Gelände-Höhen-Stufen
- [ ] Zerstörbares Gelände (optional)
- [ ] Terrain-Randomizer

### 3.5 Spiel-Phasen-Management

**Priorität: HOCH**

- [ ] Konfigurierbarer Phasen-Tracker
- [ ] Automatische Phasen-Übergänge
- [ ] Runden-Counter
- [ ] Timer-Funktion (Chess Clock Style)
- [ ] Turn-Notification-System

---

## Phase 4: Army Builder Integration

### 4.1 Datenformat für Spielsysteme

**Priorität: HOCH**

```json
{
  "game_system": {
    "id": "opr_grimdark_future",
    "name": "Grimdark Future",
    "version": "2.50",
    "publisher": "OnePageRules",
    "base_rules": {
      "activation": "alternating",
      "phases": ["Movement", "Shooting", "Assault"],
      "coherency_distance": 1,
      "unit_size_rules": {...}
    },
    "factions": [...],
    "special_rules": [...],
    "weapons": [...],
    "equipment": [...]
  }
}
```

### 4.2 Army Builder Features

- [ ] Import von OPR Army Forge Listen (JSON/PDF-Parser)
- [ ] Import von Battlescribe-Listen (.ros, .rosz)
- [ ] Manueller Army Builder im Tool
- [ ] Punkte-Kalkulation
- [ ] Legality-Check für Turniere
- [ ] Armee-Sharing zwischen Spielern
- [ ] QR-Code Export für Armeelisten

### 4.3 Einheiten-Datenbank

- [ ] Community-gepflegte Datenbank
- [ ] Automatische Updates
- [ ] Offline-Modus
- [ ] Eigene Einheiten erstellen
- [ ] Proxying-System (Modell A zeigt Stats von B)

---

## Phase 5: Multiplayer & Netzwerk

### 5.1 Netzwerk-Architektur

**Priorität: KRITISCH**

```
┌─────────────────────────────────────────────────────────┐
│                    Netzwerk-Modi                        │
├─────────────────┬───────────────────┬──────────────────┤
│   Peer-to-Peer  │  Dedicated Server │   Hybrid-Modus   │
├─────────────────┼───────────────────┼──────────────────┤
│ - Direkte       │ - Zentrale        │ - P2P für Spiel  │
│   Verbindung    │   Authorität      │ - Server für     │
│ - Geringe       │ - Bessere Anti-   │   Matchmaking    │
│   Latenz        │   Cheat Maßnahmen │                  │
│ - Kein Server   │ - Persistente     │                  │
│   nötig         │   Spielstände     │                  │
└─────────────────┴───────────────────┴──────────────────┘
```

### 5.2 Multiplayer Features

- [ ] Lobby-System mit Spiel-Browser
- [ ] Passwort-geschützte Räume
- [ ] Zuschauer-Modus
- [ ] Voice-Chat Integration (optional)
- [ ] Text-Chat mit Würfel-Notation Support
- [ ] Spieler-Berechtigungen (Host-Kontrolle)
- [ ] Reconnect-Funktion
- [ ] Spielstand speichern/laden im Multiplayer
- [ ] Asynchroner Spielmodus (Play-by-Email Style)

### 5.3 Synchronisation

- [ ] State-Synchronisation für alle Objekte
- [ ] Konflikt-Resolution
- [ ] Lag-Kompensation
- [ ] Bandwidth-Optimierung

---

## Phase 6: Benutzeroberfläche

### 6.1 Haupt-HUD

```
┌────────────────────────────────────────────────────────────┐
│ [Spieler 1: 1500pts]          Runde 3/5         [Timer]    │
├────────────────────────────────────────────────────────────┤
│                                                            │
│                      3D SPIELFELD                          │
│                                                            │
│                                                            │
├──────────────┬─────────────────────────┬──────────────────┤
│ [Einheiten]  │     [Aktions-Leiste]    │  [Chat/Log]      │
│ - Unit 1 ✓   │  [Messen][Würfeln][...]  │  > Rolled 3D6   │
│ - Unit 2     │                         │    Result: 12    │
│ - Unit 3     │                         │                  │
└──────────────┴─────────────────────────┴──────────────────┘
```

### 6.2 UI-Komponenten

- [ ] Kontextsensitives Radialmenü
- [ ] Einheiten-Sidebar mit Schnellzugriff
- [ ] Minimierbare Panels
- [ ] Keyboard-Shortcuts (konfigurierbar)
- [ ] Touch-Support für Tablets
- [ ] Dark/Light Theme
- [ ] UI-Skalierung

### 6.3 Accessibility

- [ ] Farbenblind-Modi
- [ ] Skalierbare Schriftgrößen
- [ ] Screen-Reader Unterstützung (grundlegend)
- [ ] Vereinfachter Modus

---

## Phase 7: Modding & Erweiterbarkeit

### 7.1 Modding-API

**Priorität: HOCH**

- [ ] Lua/GDScript Scripting für Mods
- [ ] Asset-Import (3D-Modelle, Texturen)
- [ ] Regelsystem-Plugins
- [ ] UI-Erweiterungen
- [ ] Workshop-ähnliches System

### 7.2 Content-Erstellung

- [ ] In-Game Gelände-Editor
- [ ] Szenario-Editor
- [ ] Kampagnen-Editor
- [ ] Custom Token/Marker Creator

### 7.3 Community-Features

- [ ] Mod-Repository (Self-Hosted oder GitHub-basiert)
- [ ] Mod-Versionierung
- [ ] Automatische Mod-Downloads in Lobbys
- [ ] Mod-Bewertungssystem

---

## Phase 8: Spielsystem-Integrationen

### 8.1 Primäre Unterstützung (OnePageRules)

**Priorität: KRITISCH**

- [ ] Grimdark Future
- [ ] Age of Fantasy
- [ ] Grimdark Future: Firefight
- [ ] Age of Fantasy: Skirmish
- [ ] Warfleets: FTL

**Features:**
- [ ] Direkte Army Forge API Integration
- [ ] Automatische Regel-Updates
- [ ] Offizielle Tokens/Marker

### 8.2 Sekundäre Unterstützung

- [ ] Generisches Wargaming-Framework
- [ ] Historische Systeme (Bolt Action-kompatibel)
- [ ] Skirmish-Systeme (Necromunda-Style)
- [ ] Mass Battle Systeme

### 8.3 System-Agnostische Features

- [ ] Custom Regelsystem-Builder
- [ ] Regel-Scripting für Automatisierung
- [ ] Scenario-Objectives mit Logik

---

## Phase 9: Zusätzliche Features

### 9.1 Kampagnen-System

- [ ] Persistente Kampagnen
- [ ] Einheiten-Fortschritt
- [ ] Karten-basierte Kampagnen
- [ ] Narrative Kampagnen mit Events

### 9.2 Turnier-Features

- [ ] Paarungssystem
- [ ] Timer-Enforcement
- [ ] Ergebnis-Tracking
- [ ] Export für Turnier-Software

### 9.3 Streaming/Recording

- [ ] OBS-Integration
- [ ] Replay-System
- [ ] Highlight-Kamera
- [ ] Streaming-freundliche UI-Optionen

### 9.4 Mobile Companion App

- [ ] Army-Referenz
- [ ] Würfel-App
- [ ] Remote-Würfeln für den Simulator
- [ ] Push-Notifications

---

## Phase 10: Entwicklungs-Roadmap

### Milestone 1: MVP (Minimum Viable Product)
**Ziel: Spielbarer Prototyp**

1. [ ] Godot-Projekt Setup
2. [ ] Basis-Spieltisch mit Kamera
3. [ ] Einfaches Objekt-System (Spawn, Move, Rotate)
4. [ ] Würfel-System (D6 Pool)
5. [ ] Basis-Messwerkzeug
6. [ ] Lokaler 2-Spieler Hotseat-Modus

### Milestone 2: Alpha
**Ziel: Vollständiges Einzelspieler-Erlebnis**

7. [ ] Erweitertes Objekt-Management
8. [ ] Gelände-System
9. [ ] Einheiten-Karten und Stats
10. [ ] Vollständiges Würfel-System
11. [ ] Speichern/Laden
12. [ ] Basic UI-Overhaul

### Milestone 3: Beta
**Ziel: Multiplayer-fähig**

13. [ ] Netzwerk-Grundlagen
14. [ ] Lobby-System
15. [ ] State-Synchronisation
16. [ ] Chat-System
17. [ ] Erste OPR-Integration (Army Forge Import)

### Milestone 4: Release Candidate
**Ziel: Community-Ready**

18. [ ] Modding-API v1
19. [ ] Vollständige OPR-Unterstützung
20. [ ] Polish & Bug-Fixing
21. [ ] Dokumentation
22. [ ] Community-Infrastruktur

### Milestone 5: Version 1.0
**Ziel: Stabiler Release**

23. [ ] Performance-Optimierung
24. [ ] Plattform-Builds (Windows, Linux, Mac)
25. [ ] Tutorial-System
26. [ ] Feedback-Integration

---

## Technische Spezifikationen

### Minimum Systemanforderungen

| Komponente | Minimum | Empfohlen |
|------------|---------|-----------|
| OS | Windows 10, Ubuntu 20.04 | Windows 11, Ubuntu 22.04 |
| CPU | Intel i5-4460 / AMD FX-6300 | Intel i5-8400 / AMD Ryzen 5 2600 |
| RAM | 8 GB | 16 GB |
| GPU | GTX 960 / RX 560 | GTX 1660 / RX 5600 |
| Storage | 2 GB | 10 GB (mit Mods) |
| Network | 5 Mbps | 20 Mbps |

### Performance-Ziele

- 60 FPS bei 200 Miniaturen auf dem Tisch
- < 100ms Netzwerk-Latenz Toleranz
- < 5 Sekunden Ladezeit für Standard-Spiele
- < 500 MB RAM für Basis-Spiel

---

## Lizenz & Community

### Lizenz-Empfehlung

**MIT License** oder **Apache 2.0**
- Erlaubt kommerzielle Nutzung von Mods
- Fördert Community-Beiträge
- Klare Rechtslage

### Community-Struktur

- GitHub für Code & Issues
- Discord für Community
- Wiki für Dokumentation
- Regelmäßige Community-Calls

---

## Nächste Schritte

1. **Repository einrichten**
   - README.md erstellen
   - Contributing Guidelines
   - Code of Conduct
   - Issue Templates

2. **Godot-Projekt initialisieren**
   - Projektstruktur anlegen
   - Basis-Szenen erstellen
   - CI/CD Pipeline

3. **Prototyp Phase starten**
   - Spieltisch implementieren
   - Erste Objekte
   - Kamera-System

---

## Ressourcen & Referenzen

### Ähnliche Projekte (Inspiration)

- [Tabletop Simulator](https://store.steampowered.com/app/286160/) - Kommerzielles Referenzprodukt
- [Virtual Tabletop](https://github.com/nicepkg/vtt) - Open-Source Inspiration
- [Tabletop Playground](https://tabletop-playground.com/) - Modernes TTS-Alternative

### Wargaming-Ressourcen

- [OnePageRules](https://onepagerules.com/) - Primäres Spielsystem
- [Army Forge](https://army-forge.onepagerules.com/) - Army Builder API
- [Battlescribe](https://battlescribe.net/) - Import-Format Referenz

### Godot-Ressourcen

- [Godot Docs](https://docs.godotengine.org/)
- [Godot Multiplayer Tutorial](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)

---

*Dokument erstellt: 2025-12-17*
*Version: 1.0*
*Status: Initialer Entwurf - Bereit für Review*
