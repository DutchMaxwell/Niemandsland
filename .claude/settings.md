# OpenTTS - Projektanweisungen für Claude

## Allgemeine Regeln

1. **Immer zuerst recherchieren**: Bei jedem Problem erst nach dokumentierten Lösungen suchen (Web, Godot-Forum, GitHub Issues), bevor eigene Lösungen implementiert werden.

2. **Godot 4.x Best Practices**: Das Projekt verwendet Godot 4.5+ mit Jolt Physics. Bei Physics-Problemen immer Jolt-spezifische Dokumentation konsultieren.

3. **Sprache**: Der Benutzer kommuniziert auf Deutsch. Antworten auf Deutsch.

## Technische Details

- **Engine**: Godot 4.5.1
- **Physics**: Jolt Physics (aktiviert in Project Settings)
- **Plattform**: macOS (Apple M1)

## Bekannte Lösungen

| Problem | Lösung |
|---------|--------|
| Würfel-Jitter | Jolt Physics verwenden statt Standard-Physik |
| Kleine RigidBody instabil | Jolt Physics oder Objekte skalieren (0.1-10m) |

## Wichtige Dateien

- `scripts/object_manager.gd` - Würfel-Logik, Physics
- `scripts/table.gd` - Tisch-Kollision
- `DICE_PHYSICS_WIP.md` - Dokumentation der Physics-Arbeit
