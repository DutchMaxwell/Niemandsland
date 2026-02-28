# OpenTTS - Claude Code Projektanweisungen

## Sprache

Antworte immer auf Deutsch.

## Projekt-Überblick

OpenTTS ist ein **Tabletop-Wargaming-Simulator** (v0.2.0-alpha) für OnePageRules, historische Wargames und Miniaturenspiele.

- **Engine**: Godot 4.5.1 (Forward Plus Rendering)
- **Sprache**: GDScript
- **Physics**: Jolt Physics
- **Plattform**: macOS (Apple M1), Windows, Linux
- **Testing**: gdUnit4

## Architektur

```
openTTS/
├── scripts/           # Kernlogik (~46 Scripts)
├── scenes/            # Hauptszenen (startup_menu, main, map_layout)
├── addons/            # dice_roller (Custom), gdUnit4 (Tests)
├── tools/             # Externe Tools
│   └── model_forge/   # 3D-Modell-Pipeline (Python/Gradio)
├── assets/            # Modelle, Texturen, Audio
└── docs/              # Projektdokumentation
```

### Zentrale Scripts

| Script | Verantwortung |
|--------|---------------|
| `main.gd` | Master-Controller, initialisiert alle Subsysteme |
| `network_manager.gd` | Multiplayer (ENet), State-Sync, RPC |
| `object_manager.gd` | 3D-Objekte spawnen, selektieren, draggen |
| `camera_controller.gd` | Orbit-, Pan-, Zoom-Kamera |
| `table.gd` | Spieltisch-State und -Größe |
| `save_manager.gd` | Save/Load im .otts-Format |
| `game_unit.gd` | Unit-Datenmodell (RefCounted) |
| `model_instance.gd` | Einzelne Miniatur (RefCounted) |
| `opr_api_client.gd` | OnePageRules Army Forge API |
| `ai_manager.gd` | KI-Gegner-Steuerung |
| `tts_importer.gd` | Tabletop Simulator Import |

### Autoloads

- `GraphicsSettings` — Qualitäts-Presets
- `ThemeManager` — Kenney UI Themes

### Architektur-Muster

- **Signal-basierte Kommunikation** zwischen Systemen
- **RefCounted Data Models** (GameUnit, ModelInstance) für Serialisierung
- **ENet Networking** mit Custom Relay Peer und RPC-Sync
- **OPR-First Design** — Tiefe Integration mit OnePageRules-Regelwerk

## Skalierung (KRITISCH)

- 1 Godot-Einheit = 1 Meter
- Tisch: 4x4 feet = 1.22m x 1.22m
- Miniaturen: 16mm = 0.016m
- Jolt Physics empfiehlt 0.1m–10m — kleine Objekte sind problematisch
- Für Würfel-Physik: Dice Roller Plugin mit eigener Skalierung in SubViewport

## Einheiten-Konvention

| Kontext | Einheit | Beispiel |
|---------|---------|----------|
| API/Regelwerk | ZOLL (inches) | `movement: 6.0` = 6" |
| Godot intern | METER | `position.x = 0.1524` = 6" |
| Miniatur-Basen | MILLIMETER | `base_size: 25` = 25mm |

Konvertierung: `INCHES_TO_METERS := 0.0254`, `MM_TO_METERS := 0.001`

## Coding Standards

Detaillierte Standards: `.claude/AAA_CODING_STANDARDS.md`

Die wichtigsten Regeln:

- **Keine Warnungen**, keine Magic Numbers, keine TODO-Kommentare, kein Dead Code
- **Defensive Programming**: Immer null-checks, Early Returns für Edge Cases
- **Typisierung**: Immer explizite Typen, keine dynamische Typisierung ohne Validierung
- **Enums statt Strings** für Typen und States
- **Performance**: `distance_squared_to()` statt `distance_to()`, keine Allokationen in `_process()`
- **OPR-Regel-Referenzen**: Jede Spielmechanik muss auf OPR-Regel verweisen

## Datei-Struktur in GDScript

```
Constants → Signals → @export Vars → Private Vars → _ready/_process → Public Methods → Private Methods
```

Sektionen mit `# ===` Kommentarblöcken trennen.

## Git-Konventionen

```
feat: Add feature X
fix: Fix bug in Y
refactor: Improve Z without changing behavior
docs: Update documentation
perf: Performance improvement
```

## Workflow-Regeln

1. **Immer zuerst recherchieren**: Bei Problemen erst dokumentierte Lösungen suchen, bevor eigene implementiert werden
2. **Nie committen ohne Aufforderung**
3. Bei Physics-Problemen: Jolt-spezifische Dokumentation konsultieren

## Model Forge (3D-Modell-Pipeline)

- **Pfad**: `tools/model_forge/`
- **Python venv**: `tools/model_forge/venv/` (PyMuPDF, Gradio, etc.)
- **Design Languages**: `tools/model_forge/design_languages/*.yaml` (38 Fraktionen)
- **Prompt Engine**: Generiert Bild-Prompts aus OPR-Einheitsdaten + Design Language
- **game_stats**: Echte OPR-Spielwerte pro Unit (Quality, Defense, Cost, Weapons, Rules)
- **Datenfluss**: YAML -> DesignLanguage -> OPRArmy -> PromptEngine -> Image -> Trellis 3D -> GLB

## Weiterführende Dokumentation

- `.claude/AAA_CODING_STANDARDS.md` — Vollständige Coding Standards
- `docs/PROJECT_STATUS.md` — Aktueller Feature-Status
- `docs/PLAN.md` — Roadmap & Milestones
- `docs/PLAN_UNIT_SYSTEM.md` — Unit-Datenmodell-Design
- `docs/PLAN_AI_SYSTEM.md` — KI-Entscheidungsbaum
