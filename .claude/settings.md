# OpenTTS - Projektanweisungen für Claude

## Allgemeine Regeln

1. **Immer zuerst recherchieren**: Bei jedem Problem erst nach dokumentierten Lösungen suchen (Web, Godot-Forum, GitHub Issues), bevor eigene Lösungen implementiert werden.

2. **Godot 4.x Best Practices**: Das Projekt verwendet Godot 4.5+ mit Jolt Physics. Bei Physics-Problemen immer Jolt-spezifische Dokumentation konsultieren.

3. **Sprache**: Der Benutzer kommuniziert auf Deutsch. Antworten auf Deutsch.

## Technische Details

- **Engine**: Godot 4.5.1
- **Physics**: Jolt Physics (aktiviert in Project Settings)
- **Plattform**: macOS (Apple M1)

## WICHTIG: Skalierung

Das Projekt verwendet **Realwelt-Maßstab**:
- 1 Godot-Einheit = 1 Meter
- Tisch: 4x4 feet = 1.22m x 1.22m
- Würfel: 16mm = 0.016m

**PROBLEM**: Jolt Physics empfiehlt Objekte zwischen 0.1m - 10m.
Unsere 16mm Würfel (0.016m) sind **6x zu klein** für stabile Physik!

**LÖSUNG**:
- Für Würfeln: Dice Roller Plugin verwenden (eigene Skalierung in SubViewport)
- Tabletop-Würfel nur für Display, nicht für Physics-Würfeln

## Bekannte Lösungen

| Problem | Lösung |
|---------|--------|
| Würfel-Jitter | Jolt Physics + Dice Roller Plugin |
| Kleine RigidBody instabil | Plugin mit eigener Skalierung verwenden |
| SubViewport zeigt in Hauptszene | `viewport.own_world_3d = true` setzen |

## Wichtige Dateien

- `scripts/object_manager.gd` - Würfel-Logik, Physics
- `scripts/table.gd` - Tisch-Kollision
- `addons/dice_roller/` - Dice Roller Plugin
- `DICE_PHYSICS_WIP.md` - Dokumentation der Physics-Arbeit
