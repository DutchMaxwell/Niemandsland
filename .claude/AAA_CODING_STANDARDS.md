# OpenTTS - AAA Coding Standards

**Version:** 1.0
**Stand:** 2026-01-06
**Maxime:** AAA-Titel Ambition - Keine Kompromisse bei Qualität

---

## 1. QUALITÄTS-PRINZIPIEN

### 1.1 Zero-Tolerance Policy

| Regel | Beschreibung |
|-------|--------------|
| **KEINE Warnungen** | Code muss warning-free kompilieren |
| **KEINE Magic Numbers** | Alle Konstanten benannt und dokumentiert |
| **KEINE TODO-Kommentare** | Entweder implementieren oder Issue erstellen |
| **KEINE Stub-Funktionen** | Jede Funktion muss vollständig sein |
| **KEINE Dead Code** | Unused Signals, Variablen, Funktionen entfernen |

### 1.2 Defensive Programming (MANDATORY)

```gdscript
# RICHTIG: Immer null-checks vor Verwendung
func process_unit(unit: GameUnit) -> void:
    if unit == null:
        push_error("process_unit: unit is null (caller bug)")
        return

    if unit.models.is_empty():
        return  # Silent return für erwartete Fälle

    for model in unit.models:
        if model == null or not model.is_alive:
            continue
        # ... processing

# FALSCH: Keine Validierung
func process_unit(unit: GameUnit) -> void:
    for model in unit.models:  # Crash wenn unit null!
        # ...
```

### 1.3 Error Handling Hierarchy

```
push_error()   → Programmierfehler (Bugs im Code)
               → Sollte NIEMALS im normalen Betrieb auftreten

Silent return  → Erwartete Edge Cases
               → z.B. leere Arrays, zerstörte Einheiten

Assertion      → Invarianten in Development
               → assert(condition, "description")
```

---

## 2. EINHEITEN-STANDARD (KRITISCH!)

### 2.1 Einheiten-Konvention

| Kontext | Einheit | Beispiel |
|---------|---------|----------|
| **API/Regelwerk** | ZOLL (inches) | `movement: 6.0` = 6" |
| **Godot intern** | METER | `position.x = 0.1524` = 6" |
| **Miniatur-Basen** | MILLIMETER | `base_size: 25` = 25mm |

### 2.2 Konvertierungs-Konstanten

```gdscript
# In jeder Datei die Einheiten verwendet:
const INCHES_TO_METERS := 0.0254
const METERS_TO_INCHES := 39.3701
const MM_TO_METERS := 0.001

# Funktionen für Klarheit:
static func inches_to_meters(inches: float) -> float:
    return inches * INCHES_TO_METERS

static func meters_to_inches(meters: float) -> float:
    return meters * METERS_TO_INCHES
```

### 2.3 Parameter-Dokumentation

```gdscript
## Findet Deckung in der Nähe einer Position.
## @param pos: Aktuelle Position (METER, Godot World Space)
## @param threat_pos: Bedrohungsposition (METER, Godot World Space)
## @param max_distance_inches: Suchradius in ZOLL (Standard: 6")
## @return: Beste Deckungsposition (METER, Godot World Space)
static func find_cover_near(
    pos: Vector3,
    threat_pos: Vector3,
    max_distance_inches: float = 6.0
) -> Vector3:
```

---

## 3. PERFORMANCE-STANDARDS

### 3.1 Target Metrics

| Szenario | Minimum | Target |
|----------|---------|--------|
| 200 Einheiten, keine AI | 60 FPS | 120 FPS |
| 200 Einheiten, mit AI | 30 FPS | 60 FPS |
| AI-Entscheidung | < 16ms | < 8ms |
| Pathfinding (single) | < 5ms | < 2ms |

### 3.2 Optimierungs-Regeln

```gdscript
# RICHTIG: Early exit, minimale Iterationen
static func find_nearest_enemy(pos: Vector3, enemies: Array[GameUnit]) -> GameUnit:
    var nearest: GameUnit = null
    var min_dist_sq := INF  # Squared distance (keine sqrt!)

    for enemy in enemies:
        if enemy.is_destroyed():
            continue

        var dist_sq := pos.distance_squared_to(enemy.get_position())
        if dist_sq < min_dist_sq:
            min_dist_sq = dist_sq
            nearest = enemy

    return nearest

# FALSCH: Unnötige sqrt() Aufrufe
static func find_nearest_enemy(pos: Vector3, enemies: Array[GameUnit]) -> GameUnit:
    enemies.sort_custom(func(a, b):
        return pos.distance_to(a.get_position()) < pos.distance_to(b.get_position())
    )
    return enemies[0]  # Sort ist O(n log n), wir brauchen nur O(n)!
```

### 3.3 Memory Management

- **Keine Allokationen in _process()**: Arrays vorher erstellen
- **Object Pooling**: Für häufig erstellte Objekte (Projektile, Marker)
- **Weak References**: Für optionale Referenzen (terrain_overlay)

---

## 4. OPR REGELWERK-KONFORMITÄT

### 4.1 Regel-Referenzen

Jede Spielmechanik MUSS auf OPR-Regel verweisen:

```gdscript
## Dangerous Terrain Test per OPR v3.5.1:
## "Models must roll one die, and on a result of 1 they take one wound."
## Ein Würfel pro Model, bei 1 = eine Wunde.
static func take_dangerous_terrain_test(model: ModelInstance) -> int:
    var roll := randi() % 6 + 1
    if roll == 1:
        return 1  # Eine Wunde
    return 0
```

### 4.2 Konstanten für Regeln

```gdscript
# OPR v3.5.1 Konstanten
const OPR_DIFFICULT_TERRAIN_MAX_MOVEMENT_INCHES := 6.0
const OPR_STANDARD_COHERENCY_INCHES := 1.0
const OPR_ELEVATED_COHERENCY_INCHES := 3.0
const OPR_CHARGE_BONUS_INCHES := 3.0
const OPR_WEAPON_RANGE_SHORT_INCHES := 12.0
const OPR_WEAPON_RANGE_LONG_INCHES := 24.0
```

---

## 5. CODE-STRUKTUR

### 5.1 Datei-Organisation

```gdscript
# ==============================================================================
# DATEINAME.gd
# Kurze Beschreibung der Verantwortung
# ==============================================================================

class_name ClassName
extends BaseClass

# ==============================================================================
# CONSTANTS
# ==============================================================================

const CONSTANT_NAME := value

# ==============================================================================
# SIGNALS
# ==============================================================================

signal signal_name(param: Type)

# ==============================================================================
# EXPORTED VARIABLES
# ==============================================================================

@export var exported_var: Type

# ==============================================================================
# PRIVATE VARIABLES
# ==============================================================================

var _private_var: Type

# ==============================================================================
# LIFECYCLE METHODS
# ==============================================================================

func _ready() -> void:
    pass

func _process(delta: float) -> void:
    pass

# ==============================================================================
# PUBLIC METHODS
# ==============================================================================

func public_method() -> void:
    pass

# ==============================================================================
# PRIVATE METHODS
# ==============================================================================

func _private_method() -> void:
    pass
```

### 5.2 Klassen-Design

```gdscript
# Immutable Result Objects (statt Dictionaries)
class CombatResult:
    var attacker: GameUnit
    var defender: GameUnit
    var attacker_casualties: Array[ModelInstance] = []
    var defender_casualties: Array[ModelInstance] = []
    var attacker_wounds: int = 0
    var defender_wounds: int = 0
    var winner: GameUnit = null
    var is_melee: bool = false
```

---

## 6. TESTING & VALIDATION

### 6.1 Assertions in Development

```gdscript
func resolve_combat(attacker: GameUnit, defender: GameUnit) -> CombatResult:
    assert(attacker != null, "resolve_combat: attacker is null")
    assert(defender != null, "resolve_combat: defender is null")
    assert(not attacker.is_destroyed(), "resolve_combat: attacker is destroyed")
    # ... implementation
```

### 6.2 Logging Standards

```gdscript
# Für Debug-Zwecke (kann deaktiviert werden)
func _log(message: String) -> void:
    if _debug_enabled:
        print("[%s] %s" % [get_class(), message])

# Für permanentes Logging
func _log_combat(attacker: GameUnit, defender: GameUnit, result: CombatResult) -> void:
    print("[COMBAT] %s vs %s: %d casualties" % [
        attacker.get_name(),
        defender.get_name(),
        result.defender_casualties.size()
    ])
```

---

## 7. GIT CONVENTIONS

### 7.1 Commit Messages

```
feat: Add feature X
fix: Fix bug in Y
refactor: Improve Z without changing behavior
docs: Update documentation
perf: Performance improvement
test: Add tests
chore: Maintenance tasks
```

### 7.2 Branch Naming

```
feature/descriptive-name
fix/issue-description
refactor/component-name
```

---

## 8. REVIEW CHECKLIST

Vor jedem Merge MUSS geprüft werden:

- [ ] Keine Warnungen beim Kompilieren
- [ ] Alle Funktionen dokumentiert (## Kommentare)
- [ ] Einheiten klar angegeben (ZOLL/METER/MM)
- [ ] Null-Checks für alle externen Referenzen
- [ ] Division by Zero geschützt
- [ ] Magic Numbers durch Konstanten ersetzt
- [ ] OPR-Regel-Referenz bei Spielmechaniken
- [ ] Performance: Keine unnötigen Iterationen
- [ ] Dead Code entfernt
- [ ] Edge Cases behandelt

---

## 9. ARCHITEKTUR-PRINZIPIEN

### 9.1 Single Responsibility

Jede Klasse hat EINE Verantwortung:

| Klasse | Verantwortung |
|--------|---------------|
| `ObjectManager` | Tisch-Objekte spawnen/selektieren/draggen |
| `CoherencyChecker` | OPR-Kohärenz prüfen (reine Logik, keine Darstellung) |
| `CoherencyVisualizer` | Kohärenz visuell anzeigen |
| `GameUnit` | Modelle + Zustand einer Einheit halten |
| `NetworkManager` | Multiplayer-Sync / RPCs |
| `SaveManager` | `.otts`-Serialisierung |

### 9.2 Data Flow (Beispiel: OPR-Import → Tisch)

```
OPRApiClient (Armee von Army Forge holen)
    ↓
OPRArmyManager (Units spawnen, GLBs auf Base skalieren)
    ↓
GameUnit / ModelInstance (Unit- und Modell-Zustand)
    ↓
NetworkManager (zu Peers syncen)  ·  SaveManager (.otts speichern)
```

---

## 10. FORBIDDEN PATTERNS

### 10.1 NIEMALS verwenden:

```gdscript
# VERBOTEN: Dynamische Typisierung ohne Validierung
var data = get_data()  # Was ist data?
data.something()       # Crash wenn null oder falscher Typ!

# VERBOTEN: Magic Numbers
if distance < 6.0:     # Was bedeutet 6.0?

# VERBOTEN: Leere catch-all
match action:
    _:
        pass           # Versteckt Bugs!

# VERBOTEN: String-basierte Typen
if type == "melee":    # Typos werden nicht erkannt!
```

### 10.2 IMMER verwenden:

```gdscript
# RICHTIG: Typisierung
var data: GameUnit = get_data()
if data != null:
    data.something()

# RICHTIG: Benannte Konstanten
const MAX_CHARGE_RANGE_INCHES := 6.0
if distance < MAX_CHARGE_RANGE_INCHES:

# RICHTIG: Exhaustive match mit Warnung
match action:
    Action.MOVE:
        # ...
    Action.SHOOT:
        # ...
    _:
        push_error("Unhandled action: %s" % action)

# RICHTIG: Enums
enum ActionType { MOVE, SHOOT, CHARGE, MELEE }
if action == ActionType.MELEE:
```

---

**Diese Standards sind VERBINDLICH für alle Beiträge zum OpenTTS-Projekt.**

**Ziel: AAA-Qualität - Stabiler, performanter, regelkonformer Wargaming-Simulator.**
