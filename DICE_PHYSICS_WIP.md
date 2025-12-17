# Dice Physics: Stabilization & Jitter Fixes - WIP

## Status: In Progress 🔧

Die Würfel-Physik wurde verbessert, aber es gibt noch Probleme mit dem Settling-Verhalten.

## Was wurde gemacht

### Fixes implementiert:

1. **Table Collision erweitert** (`scripts/table.gd`)
   - Kollisionsfläche 1m über Tischkanten hinaus erweitert
   - 50cm dick, Top bei y=0.01
   - Verhindert dass Würfel durch den Tisch fallen

2. **Debug-Logging hinzugefügt** (`scripts/object_manager.gd`)
   - Loggt Würfel-Position, Velocity, Sleep-Status alle 0.5s
   - Log-Datei: `user://dice_debug.log`
   - Console-Output bei Jitter-Detection

3. **Rescue-System** für gefallene Würfel
   - Würfel unter y=-0.5m werden zurück auf den Tisch teleportiert

4. **Auto-Stabilization**
   - Würfel werden eingefroren wenn: `lin_v < 0.15` UND `ang_v < 1.0`
   - Niedriger ang_v Threshold damit Würfel flach liegen bevor sie einfrieren

5. **Erhöhte Dämpfung** (letzter Commit)
   - `linear_damp`: 1.0 → 2.0
   - `angular_damp`: 1.5 → 4.0
   - Soll Rotation schneller abbremsen

## Aktuelles Problem

Würfel haben nach 2.5s Roll-Zeit noch zu hohe Winkelgeschwindigkeit (ang_v=7-15 statt <1.0).

- Mit altem ang_v Threshold (15.0): Würfel froren schief ein
- Mit neuem ang_v Threshold (1.0): Würfel werden nicht stabilisiert weil ang_v noch zu hoch

## Debug-Log Beispiel (vor Dämpfungs-Erhöhung)

```
[8.17] --- READING DICE RESULTS ---
  Dice_1: result=2 pos.y=0.0083 lin_v=0.0796 ang_v=7.21 sleeping=false
  Dice_2: result=1 pos.y=0.0074 lin_v=0.0724 ang_v=6.67 sleeping=false
  Dice_3: result=2 pos.y=0.0081 lin_v=0.0000 ang_v=0.00 sleeping=true  ← OK
  Dice_4: result=2 pos.y=0.0082 lin_v=0.0277 ang_v=2.72 sleeping=false
  Dice_5: result=5 pos.y=0.0066 lin_v=0.1007 ang_v=11.29 sleeping=false
```

## Nächste Schritte zum Testen

1. **Testen mit erhöhter Dämpfung** (aktueller Stand)
   - `angular_damp=4.0` sollte ang_v schneller unter 1.0 bringen

2. **Falls immer noch nicht funktioniert:**
   - Roll-Zeit von 2.5s auf 3.5s erhöhen (`roll_all_dice()` in object_manager.gd:518)
   - Initiale ang_v beim Roll reduzieren (aktuell ±25 rad/s, Zeile 506-508)
   - Progressive Stabilisierung: erst Rotation stoppen, dann Position

3. **Alternative Ansätze:**
   - Godot's eingebautes Sleep-System nutzen statt manueller Stabilisierung
   - Physics Material anpassen (mehr Friction)
   - `continuous_cd = true` für bessere Kollisionserkennung

## Relevante Dateien

| Datei | Beschreibung |
|-------|--------------|
| `scripts/object_manager.gd` | Würfel-Spawning, Physics, Debug-Logging, Stabilisierung |
| `scripts/table.gd` | Tisch-Kollision und Borders |
| `scripts/main.gd` | Spawn-Position |

## Wichtige Code-Stellen

### Stabilisierung (object_manager.gd:112-120)
```gdscript
# Auto-stabilize: force sleep if nearly settled
if lin_speed < 0.15 and ang_speed < 1.0:
    dice.linear_velocity = Vector3.ZERO
    dice.angular_velocity = Vector3.ZERO
    dice.sleeping = true
```

### Dämpfung (object_manager.gd:224-226)
```gdscript
dice.linear_damp = 2.0    # Increased for faster settling
dice.angular_damp = 4.0   # Increased to stop rotation faster
```

### Roll-Velocities (object_manager.gd:500-511)
```gdscript
var ang_v = Vector3(
    randf_range(-25, 25),     # Rotation beim Wurf
    randf_range(-25, 25),
    randf_range(-25, 25)
)
```

## Commits auf diesem Branch

| Commit | Beschreibung |
|--------|--------------|
| `528f3a8` | Increase dice damping for faster settling |
| `f3b0fbe` | Fix tilted dice by lowering angular velocity threshold |
| `65684b1` | Fix dice jitter with higher table collision and auto-stabilization |
| `d8656d7` | Fix operator precedence in timestamp calculation |
| `7dd5e0a` | Add debug logging for dice physics diagnostics |
| `48c1e86` | Fix table collision and improve dice rolling |
| `f78ed50` | Fix dice rolling - lift dice and increase velocity |

## Debug-Logging aktivieren/deaktivieren

In `scripts/object_manager.gd` Zeile 13:
```gdscript
@export var debug_dice_physics: bool = true  # Set to false to disable logging
```

Log-Datei Pfad (macOS):
```
/Users/[username]/Library/Application Support/Godot/app_userdata/OpenTTS/dice_debug.log
```
