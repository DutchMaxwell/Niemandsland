# Niemandsland — Coding Standards

**Version:** 2.0
**Updated:** 2026-06-17
**Maxim:** AAA-level ambition — no compromises on stability, performance, or
rules-fidelity.

> Niemandsland is a **tool for human players, not an automated game**. There is no
> combat/damage resolution and no AI opponent (an earlier AI + battle simulator was
> removed and will not return). The guiding principle is **"show, don't decide"**: we
> measure, visualise and synchronise — the players apply the rules. These standards
> exist to keep that tool stable, fast and faithful to OnePageRules.

All code, comments, identifiers, commit messages and docs are written in **English** so
the project stays usable internationally.

---

## 1. Quality principles

### 1.1 Zero-tolerance policy

| Rule | Description |
|------|-------------|
| **No warnings** | Code must compile warning-free. |
| **No magic numbers** | Every constant is named and documented. |
| **No TODO comments** | Either implement it, or open an issue. |
| **No stub functions** | Every function is complete. |
| **No dead code** | Remove unused signals, variables and functions. |

### 1.2 Defensive programming (mandatory)

Validate external references before use; early-return on expected-empty cases.

```gdscript
# RIGHT: null-check the caller's argument, early-return on expected-empty,
# skip invalid elements. Mirrors GameUnit.get_alive_count() (game_unit.gd).
func count_alive(unit: GameUnit) -> int:
    if unit == null:
        push_error("count_alive: unit is null (caller bug)")
        return 0
    if unit.models.is_empty():
        return 0  # expected edge case — silent
    var alive := 0
    for model in unit.models:
        if model == null or not model.is_alive:
            continue
        alive += 1
    return alive

# WRONG: no validation — crashes when unit is null or a model was freed.
func count_alive(unit: GameUnit) -> int:
    var alive := 0
    for model in unit.models:
        if model.is_alive:
            alive += 1
    return alive
```

The same discipline applies to engine calls that can fail. Real example from
`save_manager.gd`:

```gdscript
var file := FileAccess.open(path, FileAccess.WRITE)
if not file:
    var err := FileAccess.get_open_error()
    push_error("Failed to open save file: %s (error %d)" % [path, err])
    return err
```

### 1.3 Error-handling hierarchy

```
push_error()   -> programmer error (a bug in the code)
               -> must NEVER fire in normal operation

silent return  -> expected edge cases
               -> e.g. empty arrays, destroyed units, missing optional node

assert()       -> invariants during development
               -> assert(condition, "description")
```

---

## 2. Units & scale (critical)

Niemandsland mixes three measurement systems. Getting this wrong is the single most
common source of bugs.

### 2.1 Unit convention

| Context | Unit | Example |
|---------|------|---------|
| **API / rules** | inches | `movement: 6.0` = 6″ |
| **Godot world** | metres | `position.x = 0.1524` = 6″ |
| **Miniature bases** | millimetres | `base_size: 25` = 25 mm |

1 Godot unit = 1 metre. A 4×4 ft table is 1.22 m.

### 2.2 Conversions

```gdscript
# inches -> meters:  value * INCHES_TO_METERS
# meters -> inches:  value / INCHES_TO_METERS   (see coherency_checker._distance_between_models)
# millimetres -> meters (base sizes):  value * 0.001   (see OPRUnit.get_base_radius_meters)
const INCHES_TO_METERS: float = 0.0254   # opr_army_manager.gd, coherency_checker.gd, table.gd, ...
```

Real mm→m conversion (`opr_api_client.gd`, `OPRUnit`):

```gdscript
## Get base radius in meters (for 3D spawning)
func get_base_radius_meters() -> float:
    return (base_size_round / 2.0) * 0.001  # mm to meters
```

### 2.3 Always document the unit of a numeric parameter

```gdscript
## Largest base dimension (mm) for a model, growing the unit base for tough models.
## @param unit_base_long_mm: the unit's base long edge (MILLIMETRES)
## @param model_tough: the model's Tough(X) value (0/1 = normal infantry)
## @return: base long edge in MILLIMETRES
static func model_base_long_mm(unit_base_long_mm: int, model_tough: int) -> int:
    return maxi(unit_base_long_mm, OPRApiClient._base_size_from_tough(model_tough))
```

---

## 3. Performance

Niemandsland must stay smooth with a full two-army game on the table (dozens to a few
hundred models) plus terrain, scatter and a live multiplayer session.

### 3.1 Rules of thumb

- **No allocations in `_process`/`_physics_process`.** Build arrays and meshes up front;
  rebuild only on a real change (resize / biome / quality), never per frame.
- **`MultiMesh` for repeated geometry.** Grass tufts and rubble are one `MultiMesh` each,
  gated by the graphics quality preset — not thousands of nodes.
- **Object pooling** for short-lived, frequently spawned objects.
- **Prefer `distance_squared_to`** when you only need to *compare* distances. Use
  `distance_to` (which calls `sqrt`) only when you need the actual value — e.g.
  `coherency_checker` reports edge-to-edge inches, so it legitimately must.

### 3.2 MultiMesh instead of many nodes

Real example — `grass_field.gd` builds one `MultiMesh`, only on rebuild (resize / biome /
quality change), and caches the tuft mesh between rebuilds:

```gdscript
var grass := MultiMesh.new()
grass.transform_format = MultiMesh.TRANSFORM_3D
grass.use_colors = true
grass.mesh = mesh                 # cached in _tuft_mesh_cache, reused across rebuilds
grass.instance_count = count
# ... set_instance_transform / set_instance_color per blade ...
multimesh = grass
```

Rubble scatter (`terrain_overlay.gd`) follows the same pattern.

### 3.3 Object pooling

Real example — `audio_manager.gd` reuses a fixed ring of players instead of allocating
per sound:

```gdscript
const SFX_POOL_SIZE: int = 8
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0
# ...
var player := _sfx_pool[_sfx_pool_index]
player.stream = stream
player.play()
_sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE
```

---

## 4. OPR rules fidelity

### 4.1 Every game-rule value cites its OPR source

We **display and measure** rules; we do not auto-resolve them. Any constant or measure
that encodes a rule carries a comment pointing at the exact OnePageRules source, so it can
be verified and updated when OPR changes.

Real example — `coherency_checker.gd`:

```gdscript
## Maximum chain distance for Skirmish mode (Grimdark Future: Firefight /
## Age of Fantasy: Skirmish). Verified: GF: Firefight Beginner's Guide v3.5.1, p.7
## ("within 6" of all other models").
const SKIRMISH_CHAIN_DISTANCE_INCHES := 6.0
```

Real example — `equipment_distributor.gd`:

```gdscript
# OPR Core Rules — Tough(X): "models with this rule are only killed once they have
# taken X or more wounds." Tough is a PER-MODEL stat, not a unit-wide one.
```

### 4.2 Named constants for rules

Real example — `coherency_checker.gd`:

```gdscript
const COHERENCY_DISTANCE_INCHES := 1.0      # standard coherency
const ELEVATED_COHERENCY_INCHES := 3.0      # across different elevation
const MAX_CHAIN_DISTANCE_INCHES := 9.0      # standard game spread
const SKIRMISH_CHAIN_DISTANCE_INCHES := 6.0 # Firefight / Skirmish spread
```

---

## 5. Code structure

### 5.1 File organisation

Sections are separated by compact `# ===== Title =====` headers (five equals, the title
in Title Case). Real ordering, e.g. `game_unit.gd`: source data → model-level data →
unit-level properties → state → access methods → … → serialization.

```gdscript
class_name ClassName
extends BaseClass

# ===== Constants =====

const CONSTANT_NAME := value

# ===== Signals =====

signal something_happened(param: Type)

# ===== Exported Variables =====

@export var exported_var: Type

# ===== Private Variables =====

var _private_var: Type

# ===== Lifecycle =====

func _ready() -> void:
    pass

# ===== Public Methods =====

func public_method() -> void:
    pass

# ===== Private Methods =====

func _private_method() -> void:
    pass
```

For a major top-level boundary, a full-width rule comment
(`# ===========…`, ~79 chars) is also used (see `network_manager.gd`).

### 5.2 Prefer typed data objects over loose dictionaries

A small class with named, typed fields beats passing dictionaries around. Real example —
`CoherencyResult` (`coherency_checker.gd`):

```gdscript
class CoherencyResult:
    var valid: bool = true
    var issues: Array = []  # issue dictionaries: {type, model, message, ...}

    func add_issue(type: IssueType, model: ModelInstance, message: String, extra: Dictionary = {}) -> void:
        var issue := {"type": type, "model": model, "message": message}
        issue.merge(extra)
        issues.append(issue)
        valid = false
```

Another example — `LosRules.Blocker` (`los_rules.gd`):

```gdscript
class Blocker:
    var pos: Vector2
    var radius: float
    var height: int
    var unit_key: int

    func _init(p_pos: Vector2, p_radius: float, p_height: int, p_unit_key: int) -> void:
        pos = p_pos
        radius = p_radius
        height = p_height
        unit_key = p_unit_key
```

---

## 6. Testing & validation

### 6.1 Assertions for development invariants

```gdscript
static func model_base_long_mm(unit_base_long_mm: int, model_tough: int) -> int:
    assert(unit_base_long_mm > 0, "model_base_long_mm: base must be positive")
    assert(model_tough >= 0, "model_base_long_mm: tough must be >= 0")
    return maxi(unit_base_long_mm, OPRApiClient._base_size_from_tough(model_tough))
```

### 6.2 Logging conventions

Informational logs use a bracketed tag: `print("[Tag] …")`. Real tags in use include
`[Boot]`, `[Network]`, `[Relay]`, `[StateSync]`, `[ArmySync]`, `[TerrainSync]`,
`[Presence]`, `[Tokens]`.

```gdscript
print("[Boot] Niemandsland %s build %s" % [version, build_hash])
print("[Relay] WebSocket closed: code=%d reason='%s'" % [code, reason])
print("[StateSync] Sending state to peer %d: %d objects, %d game_units" % [peer_id, obj_count, unit_count])
```

Errors and warnings use `push_error` / `push_warning`, prefixed with the class name
(no bracket):

```gdscript
push_error("OPRArmyManager: No object_manager set")
push_warning("AudioManager: Bus not found: %s" % bus_name)
```

### 6.3 Automated tests

gdUnit4 suites live in `test/`; the relay has its own pytest suite in `relay/`. Before a
merge, **the import must be parse-error-free and the full suite green**. See
[`DEVELOPMENT.md`](DEVELOPMENT.md) for the headless commands.

---

## 7. Git conventions

### 7.1 Commit messages — conventional commits

```
feat:     a new feature
fix:      a bug fix
refactor: behaviour-preserving restructuring
docs:     documentation only
perf:     a performance improvement
test:     tests only
chore:    maintenance
```

### 7.2 Branch naming

```
feat/descriptive-name
fix/issue-description
refactor/component-name
```

Branch off `main`, keep commits conventional, and open a PR with green CI. See
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).

---

## 8. Review checklist

Before every merge:

- [ ] No compiler warnings
- [ ] Public functions documented (`##` doc comments)
- [ ] Units stated where numeric (inches / metres / mm)
- [ ] Null-checks on all external references; division-by-zero guarded
- [ ] No magic numbers — named constants
- [ ] Rule logic cites its OPR source
- [ ] No allocations in `_process`; no needless iteration
- [ ] Dead code removed; edge cases handled
- [ ] Import parse-clean and the gdUnit4 suite green

---

## 9. Architecture principles

### 9.1 Single responsibility

| Class | Responsibility |
|-------|----------------|
| `ObjectManager` | Spawn / select / drag table objects |
| `CoherencyChecker` | Check OPR coherency (pure logic, no rendering) |
| `CoherencyVisualizer` | Render coherency state on the table |
| `GameUnit` | Hold a unit's models + state |
| `ModelInstance` | Hold a single model's wounds / state |
| `OPRArmyManager` | Spawn imported units, scale GLBs onto bases |
| `NetworkManager` | Multiplayer sync / RPCs |
| `SaveManager` | `.nml` serialisation |

### 9.2 Data flow (OPR import → table)

```
OPRApiClient        (fetch the army from Army Forge)
    -> OPRArmyManager   (spawn units, scale GLBs onto bases)
    -> GameUnit / ModelInstance   (unit + per-model state)
    -> NetworkManager (sync to peers)  ·  SaveManager (.nml)
```

---

## 10. Forbidden patterns

### 10.1 Never

```gdscript
# FORBIDDEN: dynamic typing without validation
var data = get_data()   # what is data?
data.something()        # crash if null or wrong type

# FORBIDDEN: magic numbers
if distance < 6.0:      # 6.0 what? inches? metres?

# FORBIDDEN: catch-all that hides bugs
match terrain_type:
    _:
        pass            # silently swallows unhandled cases

# FORBIDDEN: string-based states (typos are not caught)
if terrain == "forest":
```

### 10.2 Always

```gdscript
# RIGHT: explicit typing + null-check
var data: GameUnit = get_data()
if data != null:
    data.something()

# RIGHT: named constant with its unit
const MAX_CHARGE_RANGE_INCHES := 12.0
if distance_inches < MAX_CHARGE_RANGE_INCHES:

# RIGHT: enums over strings (real example, map_layout.gd)
enum TerrainType { NONE, RUINS, FOREST, CONTAINER, DANGEROUS }

# RIGHT: exhaustive match, loud on the unexpected
match terrain_type:
    TerrainType.RUINS:
        pass
    TerrainType.FOREST:
        pass
    _:
        push_error("Unhandled terrain type: %s" % terrain_type)
```

---

**These standards are binding for all contributions to Niemandsland.**

**Goal: a stable, performant, rules-faithful wargaming simulator.**
