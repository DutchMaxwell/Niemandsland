# Plan: Unit-System und Radialmenü

**Erstellt:** 2026-01-05
**Status:** ✅ VOLLSTÄNDIG IMPLEMENTIERT
**Letzte Änderung:** 2026-01-05

## Implementierungsfortschritt

| Phase | Status | Dateien |
|-------|--------|---------|
| Phase 1: Model-Architektur | ✅ | model_instance.gd, game_unit.gd, equipment_distributor.gd |
| Phase 2: Unit-System | ✅ | unit_utils.gd, coherency_checker.gd, unit_marker.gd |
| Phase 3: Radialmenü | ✅ | radial_menu.gd, radial_menu_controller.gd, radial_menu.tscn |
| Phase 4: UI Dialoge | ✅ | wounds_dialog.gd, marker_dialog.gd, activation_tracker.gd, hero_attachment_dialog.gd |
| Phase 5: Erweitert | ✅ | coherency_visualizer.gd |
| Phase 6: Polish | ✅ | save_manager.gd (erweitert), network_manager.gd (erweitert) |

---

## 1. Problemstellung

Aktuell gibt es im Code verschiedene Objekttypen, aber keine einheitliche Definition von "Einheit". Bevor wir ein Radialmenü bauen können, müssen wir klar definieren:

1. **Was ist eine Einheit?** (vs. Terrain, Würfel, andere Objekte)
2. **Was ist ein Modell innerhalb einer Einheit?** (Leader, Specialist, etc.)
3. **Wie erkennen wir Einheiten automatisch?**
4. **Welche Aktionen sollen im Radialmenü verfügbar sein?**

### 1.1 Kernkonzept: Unit vs. Model

```
┌─────────────────────────────────────────────────────────┐
│                        UNIT                             │
│  "Saurian Warriors" (20 Modelle, 200pts)                │
│  Quality: 4+, Defense: 4+, Tough(3)                     │
├─────────────────────────────────────────────────────────┤
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐  ...   │
│  │ MODEL 1 │ │ MODEL 2 │ │ MODEL 3 │ │ MODEL 4 │        │
│  │ 3 Wunden│ │ 3 Wunden│ │ 3 Wunden│ │ 3 Wunden│        │
│  │ Banner  │ │ Primal  │ │ Primal  │ │ Primal  │        │
│  │ Primal  │ │ Fearless│ │ Fearless│ │ Fearless│        │
│  │ Fearless│ │         │ │         │ │         │        │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘        │
│       ↓           ↓           ↓           ↓             │
│    Node3D      Node3D      Node3D      Node3D           │
└─────────────────────────────────────────────────────────┘
```

**Wichtig:**
- Eine **Unit** ist die spielmechanische Einheit (teilt Q/D, aktiviert zusammen)
- Ein **Model** ist ein einzelnes 3D-Objekt auf dem Tisch
- Tough(X) → JEDES Model der Unit hat X Wunden
- Equipment ohne "Nx" Prefix → NUR EIN Model hat es (z.B. Banner)
- Equipment mit "20x" Prefix → ALLE 20 Models haben es

---

## 2. Aktueller Stand (Analyse)

### 2.1 Vorhandene Objektkategorien (via Godot Groups)

| Gruppe | Beschreibung | Hat Stats? | Ist Einheit? |
|--------|--------------|------------|--------------|
| `opr_unit` | OPR Army Forge Import | ✅ Ja | ✅ Ja |
| `wgs_unit` | WGS Import | ✅ Ja | ✅ Ja |
| `miniature` | Generische Miniatur | ❌ Nein | ⚠️ Unklar |
| `dice` | Würfel | ❌ Nein | ❌ Nein |
| `terrain` | Prozedurales Terrain | ❌ Nein | ❌ Nein |
| `terrain_piece` | TTS-Import Terrain | ❌ Nein | ❌ Nein |
| `custom_model` | Custom 3D Modelle | ❌ Nein | ⚠️ Unklar |
| `tts_import` | TTS Import (generisch) | ❌ Nein | ⚠️ Unklar |

### 2.2 Vorhandene Metadaten auf OPR-Einheiten

```gdscript
obj.get_meta("opr_unit")       # OPRUnit Objekt mit allen Stats
obj.get_meta("opr_player_id")  # Spieler-ID (1-4)
obj.get_meta("unit_suffix")    # Suffix für Duplikate
```

### 2.3 OPRUnit-Datenstruktur (bereits vorhanden)

```gdscript
class OPRUnit:
    name: String           # "Battle Brothers"
    size: int              # Anzahl Modelle
    quality: int           # Q-Wert (2-6)
    defense: int           # D-Wert (2-6)
    cost: int              # Punktekosten
    weapons: Array         # Waffen mit Range, Attacks, Rules
    special_rules: Array   # Spezialregeln (Strings wie "Tough(3)", "Primal")
    base_size_round: int   # Basengröße in mm
```

---

## 3. Army Forge API Analyse (Verifiziert)

### 3.1 API Datenstruktur (aus opr_api_client.gd)

Die TTS API (`/api/tts?id=XXX`) liefert **vollständig aufgelöste** Unit-Daten:

```json
{
  "listId": "xxx",
  "listName": "My Army",
  "gameSystem": "gf",
  "listPoints": 2000,
  "units": [
    {
      "id": "unit_123",
      "name": "Saurian Warriors",
      "customName": "",
      "size": 20,
      "cost": 200,
      "quality": 4,
      "defense": 4,
      "bases": { "round": "32", "square": "30" },
      "specialRules": [
        { "name": "Tough", "rating": 3 },
        { "name": "Primal" },
        { "name": "Fearless" }
      ],
      "loadout": [
        {
          "name": "Claws",
          "range": 0,
          "attacks": 2,
          "count": 20,
          "specialRules": []
        },
        {
          "name": "Banner",
          "attacks": 0
        }
      ]
    }
  ]
}
```

### 3.2 Wichtige API-Erkenntnisse

| Aspekt | API-Verhalten | Implikation |
|--------|---------------|-------------|
| **Tough(X)** | `{"name": "Tough", "rating": 3}` | Jedes Model hat 3 Wunden |
| **Weapon Count** | `"count": 20` | 20 Models haben diese Waffe |
| **Equipment** | `"attacks": 0` → kein Count | In `special_rules` Array |
| **Banner/etc.** | Keine Count-Info | Annahme: 1 Model hat es |
| **"Joined to:"** | Nicht in API! | Nur in Text-Export |

### 3.3 Was die API NICHT liefert

1. **Keine Modell-spezifische Zuweisung** - Wir wissen "Unit hat Banner", aber nicht "Model 3 hat Banner"
2. **Keine Hero-Attachment-Info** - "Joined to:" nur in Text-Export
3. **Keine expliziten Rollen** - Kein "Leader", "Specialist" Flag

### 3.4 Parsing-Regeln für Import

```gdscript
# Tough(X) → wounds_max für jedes Model
func _parse_tough(special_rules: Array) -> int:
    for rule in special_rules:
        if rule.begins_with("Tough("):
            var rating = rule.substr(6, rule.length() - 7)
            return rating.to_int()
    return 1  # Default: 1 Wunde

# Waffen mit count → auf N Models verteilen
func _distribute_weapons(weapons: Array, unit_size: int) -> void:
    for weapon in weapons:
        var count = weapon.count if weapon.count > 0 else 1
        # Verteile auf erste N Models
        for i in range(min(count, unit_size)):
            models[i].weapons.append(weapon)

# Equipment ohne attacks → Spezial-Equipment
func _identify_equipment(loadout: Array) -> Array:
    var equipment = []
    for item in loadout:
        if item.attacks == 0:
            equipment.append(item.name)
    return equipment
```

---

## 4. Model-Level Architektur (GENERISCH)

### 4.1 ModelInstance Klasse (Generisch)

**WICHTIG:** Keine hardcodierten Rollen! Alles kommt als Properties aus dem Import.

```gdscript
class_name ModelInstance
extends RefCounted

# Referenzen
var unit: Variant              # Parent Unit (OPRUnit, WGSUnit, etc.)
var node: Node3D               # 3D Modell auf dem Tisch
var model_index: int           # Position in Unit (0-based)

# GENERISCHE Properties (alles aus Import, keine Interpretation!)
var properties: Dictionary = {}
# Beispiel-Inhalt:
# {
#   "weapons": [OPRWeapon, OPRWeapon],      # Waffen DIESES Modells
#   "equipment": ["Banner"],                 # Equipment DIESES Modells (ohne Count)
#   "special_rules": ["Primal", "Fearless"], # Regeln DIESES Modells
#   "tough": 3,                              # Geparst aus "Tough(3)"
#   "hero": false,                           # Optional: Hero-Flag
#   "attached_to": null,                     # Optional: "Joined to:" Unit-Referenz
# }

# Zustand (Runtime) - NICHT aus Import
var wounds_current: int = 1
var wounds_max: int = 1          # Aus Tough(X) oder Default 1
var is_alive: bool = true
var markers: Array[String] = []  # Runtime-Marker: ["Activated", "Pinned"]

# ===== Helper Methoden (Query, keine Hardcoding) =====

func get_display_name() -> String:
    # Zeigt Equipment wenn vorhanden, sonst Model-Index
    var equip = properties.get("equipment", [])
    if not equip.is_empty():
        return equip[0]  # Erstes Equipment als Name
    return "Model %d" % (model_index + 1)

func has_property(key: String) -> bool:
    return properties.has(key)

func get_property(key: String, default: Variant = null) -> Variant:
    return properties.get(key, default)

func has_special_rule(rule: String) -> bool:
    var rules = properties.get("special_rules", [])
    for r in rules:
        if r.begins_with(rule):  # Matcht "Tough" auch für "Tough(3)"
            return true
    return false

func get_weapons() -> Array:
    return properties.get("weapons", [])

func get_equipment() -> Array:
    return properties.get("equipment", [])
```

### 4.2 GameUnit Wrapper Klasse (System-Agnostisch)

```gdscript
class_name GameUnit
extends RefCounted

# Die Unit-Daten (kann OPRUnit, WGSUnit, oder generisch sein)
var source_data: Variant       # Original-Daten vom Import
var source_type: String        # "opr", "wgs", "generic"

# Model-Level Daten
var models: Array[ModelInstance] = []

# Unit-Level Properties (aus Import extrahiert)
var unit_properties: Dictionary = {}
# Beispiel:
# {
#   "name": "Saurian Warriors",
#   "size": 20,
#   "quality": 4,
#   "defense": 4,
#   "cost": 200,
#   "special_rules": ["Tough(3)", "Primal", "Fearless"],
#   "attached_heroes": [],       # Units die "Joined to:" this sind
#   "attached_to": null,         # Unit zu der wir "Joined to:" sind
# }

# ===== Helper Methoden =====

func get_model(index: int) -> ModelInstance:
    if index >= 0 and index < models.size():
        return models[index]
    return null

func get_model_for_node(node: Node3D) -> ModelInstance:
    for model in models:
        if model.node == node:
            return model
    return null

func get_alive_models() -> Array[ModelInstance]:
    var alive: Array[ModelInstance] = []
    for model in models:
        if model.is_alive:
            alive.append(model)
    return alive

func get_models_with_property(key: String) -> Array[ModelInstance]:
    var result: Array[ModelInstance] = []
    for model in models:
        if model.has_property(key):
            result.append(model)
    return result

func get_models_with_equipment(equipment_name: String) -> Array[ModelInstance]:
    var result: Array[ModelInstance] = []
    for model in models:
        if equipment_name in model.get_equipment():
            result.append(model)
    return result
```

### 4.3 Automatische Equipment-Verteilung (Generisch)

Beim Import werden Waffen/Equipment basierend auf `count` Feld verteilt:

```gdscript
class_name EquipmentDistributor
extends RefCounted

## Verteilt Equipment aus API-Daten auf ModelInstances
## Keine hardcodierten Rollen - alles basiert auf count und attacks
static func distribute(game_unit: GameUnit, loadout: Array, special_rules: Array) -> void:
    var unit_size = game_unit.models.size()

    # Schritt 1: Wounds aus Tough(X) für ALLE Models
    var wounds = _parse_tough_rating(special_rules)
    for model in game_unit.models:
        model.wounds_max = wounds
        model.wounds_current = wounds
        model.properties["tough"] = wounds

    # Schritt 2: Special Rules auf ALLE Models kopieren
    # (API gibt unit-wide rules, nicht model-specific)
    for model in game_unit.models:
        model.properties["special_rules"] = special_rules.duplicate()

    # Schritt 3: Waffen verteilen basierend auf count
    for item in loadout:
        if item.attacks > 0:  # Ist eine Waffe
            var count = item.count if item.count > 0 else unit_size
            for i in range(min(count, unit_size)):
                var weapons = game_unit.models[i].properties.get("weapons", [])
                weapons.append(item)
                game_unit.models[i].properties["weapons"] = weapons
        else:
            # Equipment ohne attacks → erstes verfügbares Model
            var assigned = false
            for model in game_unit.models:
                var equip = model.properties.get("equipment", [])
                if equip.is_empty():  # Noch kein Special-Equipment
                    equip.append(item.name)
                    model.properties["equipment"] = equip
                    assigned = true
                    break
            if not assigned:
                # Fallback: erstes Model
                var equip = game_unit.models[0].properties.get("equipment", [])
                equip.append(item.name)
                game_unit.models[0].properties["equipment"] = equip

## Parsed Tough(X) aus special_rules Array
static func _parse_tough_rating(rules: Array) -> int:
    for rule in rules:
        if rule is String and rule.begins_with("Tough("):
            var rating_str = rule.substr(6, rule.length() - 7)
            return rating_str.to_int()
    return 1  # Default: 1 Wunde
```

### 4.4 Hero-Attachment (Manuell nach Import)

Heroes können manuell einer Unit zugewiesen werden:

```gdscript
## Prüft ob Unit ein Hero ist (hat "Hero" Special Rule)
static func is_hero(game_unit: GameUnit) -> bool:
    var rules = game_unit.unit_properties.get("special_rules", [])
    for rule in rules:
        if rule is String and rule == "Hero":
            return true
        elif rule is Dictionary and rule.get("name", "") == "Hero":
            return true
    return false

## Attached Hero zu einer Unit
static func attach_hero_to_unit(hero: GameUnit, target: GameUnit) -> void:
    # Hero merkt sich Ziel
    hero.unit_properties["attached_to"] = target

    # Target merkt sich Hero
    var heroes = target.unit_properties.get("attached_heroes", [])
    heroes.append(hero)
    target.unit_properties["attached_heroes"] = heroes

## Detach Hero
static func detach_hero(hero: GameUnit) -> void:
    var target = hero.unit_properties.get("attached_to", null)
    if target:
        var heroes = target.unit_properties.get("attached_heroes", [])
        heroes.erase(hero)
        target.unit_properties["attached_heroes"] = heroes
    hero.unit_properties["attached_to"] = null
```

**UI-Flow nach Import:**
```
┌─────────────────────────────────────────────────────────┐
│  HERO ATTACHMENT                                        │
│                                                         │
│  "Captain" has the Hero rule.                           │
│  Attach to a unit?                                      │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │ ○ Battle Brothers [5]                             │  │
│  │ ○ Assault Squad [10]                              │  │
│  │ ○ Heavy Support [3]                               │  │
│  │ ● (Independent - no attachment)                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  [Skip All]                              [Confirm]      │
└─────────────────────────────────────────────────────────┘
```

### 4.5 Manueller Equipment Override

User kann Equipment-Verteilung anpassen (via Radialmenü → "Edit Loadout"):

```gdscript
## Reassign equipment from one model to another
static func reassign_equipment(
    from_model: ModelInstance,
    to_model: ModelInstance,
    equipment_name: String
) -> void:
    # Entferne von aktuellem Träger
    var from_equip = from_model.properties.get("equipment", [])
    from_equip.erase(equipment_name)
    from_model.properties["equipment"] = from_equip

    # Füge zum neuen Träger hinzu
    var to_equip = to_model.properties.get("equipment", [])
    to_equip.append(equipment_name)
    to_model.properties["equipment"] = to_equip

## Reassign weapon
static func reassign_weapon(
    game_unit: GameUnit,
    weapon: Variant,
    to_model: ModelInstance
) -> void:
    # Finde aktuellen Träger
    for model in game_unit.models:
        var weapons = model.properties.get("weapons", [])
        if weapon in weapons:
            weapons.erase(weapon)
            model.properties["weapons"] = weapons
            break

    # Zum neuen Model hinzufügen
    var to_weapons = to_model.properties.get("weapons", [])
    to_weapons.append(weapon)
    to_model.properties["weapons"] = to_weapons
```

### 4.6 Metadaten auf Node3D

Jedes 3D-Modell speichert:

```gdscript
# Beim Spawnen
node.set_meta("model_instance", model_instance)  # NEU: ModelInstance
node.set_meta("game_unit", game_unit)            # NEU: GameUnit wrapper
node.set_meta("model_index", index)              # NEU: Index in Unit (0-based)
node.set_meta("player_id", player_id)            # Bestehend

# Legacy-Kompatibilität (optional)
node.set_meta("opr_unit", game_unit.source_data) # Falls source_type == "opr"

# Lookup Funktionen
func get_model_instance(node: Node3D) -> ModelInstance:
    return node.get_meta("model_instance", null)

func get_game_unit(node: Node3D) -> GameUnit:
    return node.get_meta("game_unit", null)
```

---

## 5. Einheiten-Kategorien

### 5.1 Kategorien definieren

Wir definieren drei Einheiten-Typen:

```gdscript
enum UnitType {
    NONE,           # Kein Unit (Terrain, Würfel, etc.)
    GAME_UNIT,      # OPR/WGS Unit mit vollständigen Stats
    PROXY_UNIT,     # Miniatur als Proxy für eine Einheit
    GENERIC_UNIT    # Generische Miniatur ohne Stats
}
```

### 5.2 Neue Gruppe: `unit`

**Alle Einheiten erhalten zusätzlich die Gruppe `unit`:**

```gdscript
# Bei OPR-Import:
model.add_to_group("unit")
model.add_to_group("opr_unit")

# Bei generischer Miniatur (optional aktivierbar):
miniature.add_to_group("unit")
miniature.add_to_group("miniature")
```

### 5.3 Unit Helper Script: `unit_utils.gd`

```gdscript
class_name UnitUtils
extends RefCounted

## Prüft ob ein Objekt eine Einheit ist
static func is_unit(obj: Node3D) -> bool:
    if not obj:
        return false
    return obj.is_in_group("unit") or \
           obj.is_in_group("opr_unit") or \
           obj.is_in_group("wgs_unit")

## Gibt den UnitType zurück
static func get_unit_type(obj: Node3D) -> int:
    if not obj:
        return UnitType.NONE
    if obj.is_in_group("opr_unit") or obj.is_in_group("wgs_unit"):
        return UnitType.GAME_UNIT
    if obj.has_meta("proxy_unit"):
        return UnitType.PROXY_UNIT
    if obj.is_in_group("miniature"):
        return UnitType.GENERIC_UNIT
    return UnitType.NONE

## Gibt Unit-Stats zurück (falls vorhanden)
static func get_unit_stats(obj: Node3D) -> Variant:
    if obj.is_in_group("opr_unit"):
        return obj.get_meta("opr_unit", null)
    elif obj.is_in_group("wgs_unit"):
        return obj.get_meta("wgs_unit", null)
    elif obj.has_meta("proxy_unit"):
        return obj.get_meta("proxy_unit")
    return null

## Gibt die Spieler-ID zurück (1-4, 0 = neutral)
static func get_player_id(obj: Node3D) -> int:
    return obj.get_meta("player_id", 0) if obj else 0

## Prüft ob Objekt Terrain ist
static func is_terrain(obj: Node3D) -> bool:
    return obj.is_in_group("terrain") or \
           obj.is_in_group("terrain_piece")

## Prüft ob Objekt ein Würfel ist
static func is_dice(obj: Node3D) -> bool:
    return obj.is_in_group("dice")

## Gibt alle Modelle einer Multi-Modell-Einheit zurück
static func get_unit_models(obj: Node3D) -> Array[Node3D]:
    # Für OPR: Lookup über OPRArmyManager
    # TODO: Implementation
    return [obj]
```

---

## 6. Radialmenü Design

### 6.1 Kontextabhängige Aktionen

Das Radialmenü zeigt unterschiedliche Aktionen basierend auf:
- **Objekttyp** (Unit, Terrain, Würfel)
- **Model-Rolle** (Leader, Specialist, Trooper)
- **Anzahl selektierter Objekte** (1, mehrere, gemischt)
- **Unit-Status** (aktiviert, verwundet, etc.)

### 6.2 Radialmenü für einzelnes Model

```
┌─────────────────────────────────────────────────────────┐
│     RADIAL MENU - "Battle Brothers" Model 4/5          │
│     Role: Heavy Weapons Specialist                      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│                    [Unit Stats]                         │
│                        ↑                                │
│    [Select Unit] ←    [●]    → [Model Wounds]           │
│                        ↓                                │
│                  [Delete Model]                         │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│  Model Info: Heavy Bolter (36", A3, AP1)                │
│  Status: Alive, 1/1 Wounds                              │
│                                                         │
│  Erweitert (Shift):                                     │
│  • Edit Loadout     • Roll Attack (this model)          │
│  • Add Marker       • Measure to Target                 │
└─────────────────────────────────────────────────────────┘
```

### 6.3 Radialmenü wenn ganze Unit selektiert

```
┌─────────────────────────────────────────────────────────┐
│     RADIAL MENU - "Battle Brothers" (5 Models)          │
│     All models selected                                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│                    [Unit Stats]                         │
│                        ↑                                │
│     [Activate] ←      [●]      → [Check Coherency]      │
│                        ↓                                │
│                  [Delete Unit]                          │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│  Unit: 5/5 Models alive                                 │
│  Status: Not Activated                                  │
│                                                         │
│  Erweitert (Shift):                                     │
│  • Roll All Attacks   • Formation (Line/Block)          │
│  • Add Unit Marker    • Lock/Unlock                     │
└─────────────────────────────────────────────────────────┘
```

### 6.4 Aktionen-Matrix (Model vs Unit)

| Aktion | 1 Model | Mehrere Models | Ganze Unit | Bedingung |
|--------|---------|----------------|------------|-----------|
| **Unit Stats** | ✅ | ✅ | ✅ | Zeigt Unit-Stats |
| **Model Stats** | ✅ | ❌ | ❌ | Zeigt Model-Loadout |
| **Select Unit** | ✅ | ✅ | ❌ | Selektiert alle Models |
| **Model Wounds** | ✅ | ❌ | ❌ | Wunden für dieses Model |
| **Activate** | ❌ | ❌ | ✅ | Aktiviert ganze Unit |
| **Delete Model** | ✅ | ✅ | ❌ | Entfernt Model(s) |
| **Delete Unit** | ❌ | ❌ | ✅ | Entfernt alle Models |
| **Roll Attack** | ✅ | ✅ | ✅ | Würfelt Angriffe |
| **Check Coherency** | ❌ | ❌ | ✅ | Prüft Kohärenz |
| **Edit Loadout** | ✅ | ❌ | ❌ | Waffen zuweisen |
| **Add Marker** | ✅ | ✅ | ✅ | Status-Marker |

### 6.5 Spezial-Warnungen

Bei kritischen Aktionen auf Leader/Specialists:

```
┌─────────────────────────────────────────────┐
│  ⚠️ WARNING                                 │
│                                             │
│  This is the LEADER of "Battle Brothers"   │
│                                             │
│  Deleting the leader may affect:            │
│  • Unit morale                              │
│  • Command abilities                        │
│                                             │
│  [Cancel]              [Delete Anyway]      │
└─────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────┐
│  ⚠️ WARNING                                 │
│                                             │
│  This model carries the MEDIC equipment     │
│                                             │
│  Reassign Medic to another model?           │
│                                             │
│  [Cancel]    [Reassign]    [Delete Anyway]  │
└─────────────────────────────────────────────┘
```

---

## 7. Implementierungsplan

### Phase 1: Generische Model-Architektur ✅ ABGESCHLOSSEN

**Neue Dateien:**
- [x] `scripts/model_instance.gd` - Generische Model-Daten mit Properties Dictionary
- [x] `scripts/game_unit.gd` - System-agnostischer Unit-Wrapper
- [x] `scripts/equipment_distributor.gd` - Automatische Equipment-Verteilung

**Änderungen an bestehenden Dateien:**
- [x] `scripts/opr_army_manager.gd` - GameUnit + ModelInstance beim Spawn erstellen

**Aufgaben:**
1. ✅ ModelInstance mit generischem `properties: Dictionary` erstellen
2. ✅ GameUnit Wrapper-Klasse erstellen
3. ✅ EquipmentDistributor basierend auf API `count` Feld
4. ✅ Tough(X) → wounds_max Parsing
5. ✅ Node3D Metadaten: `model_instance`, `game_unit`, `model_index`
6. ✅ Lookup-Funktionen: `get_model_for_node()`, `get_models_with_equipment()`

### Phase 2: Unit-System Foundation ✅ ABGESCHLOSSEN

**Dateien:**
- [x] `scripts/unit_utils.gd` - Neuer Helper mit generischen Queries
- [x] `scripts/coherency_checker.gd` - OPR Coherency-Prüfung
- [x] `scripts/unit_marker.gd` - Standard + Custom Marker

**Aufgaben:**
1. ✅ UnitUtils Klasse mit `is_unit()`, `get_game_unit()`, etc.
2. ✅ Bestehende OPR-Units um `unit` Gruppe erweitern
3. ✅ `expand_to_full_units()` Funktion
4. ✅ Coherency-Checker (1" Model-zu-Model, 9" Kette)
5. ✅ Marker-System mit Standard OPR Markern

### Phase 3: Radialmenü Grundstruktur ✅ ABGESCHLOSSEN

**Dateien:**
- [x] `scenes/radial_menu.tscn` - Neue Szene
- [x] `scripts/radial_menu.gd` - Menü-Logik mit Fitts's Law
- [x] `scripts/radial_menu_controller.gd` - Kontext-Erkennung und Aktions-Handler

**Aufgaben:**
1. ✅ Radialmenü UI erstellen (Pie-Menu mit Segmenten)
2. ✅ Animations-System (Open/Close mit Tween)
3. ✅ Kontext-Detection (1 Model vs. mehrere vs. ganze Unit)
4. ✅ Cancel-Zone in der Mitte
5. ✅ Keyboard-Navigation (1-8, ESC)

### Phase 4: Kontext-Aktionen ✅ ABGESCHLOSSEN

**Dateien:**
- [x] `scripts/wounds_dialog.gd` - Wunden-Anpassung
- [x] `scripts/marker_dialog.gd` - Marker hinzufügen/entfernen
- [x] `scripts/activation_tracker.gd` - Runden- und Aktivierungs-Tracking
- [x] `scripts/hero_attachment_dialog.gd` - Hero-Zuweisung nach Import

**Aufgaben:**
1. ✅ Wunden-Dialog (Model-Level, +/- Buttons, Heal/Kill)
2. ✅ Marker-Dialog (Standard + Custom Freetext)
3. ✅ Aktivierungs-Toggle (Unit-Level)
4. ✅ Activation Tracker Panel
5. ✅ Hero Attachment Dialog nach Import

### Phase 5: Erweiterte Aktionen ✅ ABGESCHLOSSEN

- [x] Kohärenz-Checker mit Visualisierung
- ~~Loadout Editor~~ (nicht benötigt)
- ~~Attack Roll Dialog~~ (nicht benötigt)
- ~~Dice Roller Integration~~ (nicht benötigt)

### Phase 6: Polish & Edge Cases ✅ ABGESCHLOSSEN

- [x] Save/Load mit Model-Level Daten (`save_manager.gd` erweitert)
- [x] Multiplayer Sync RPCs (`network_manager.gd` erweitert)
- [x] Visual Feedback für Coherency (`coherency_visualizer.gd`)
- ~~Equipment-Reassign bei Model Delete~~ (nicht benötigt)

---

## 8. UI/UX Spezifikation

### 8.1 Radialmenü Erscheinung

```
     [Stats]
       │
[Act]──●──[Wound]
       │
    [Delete]
```

- **Größe:** 200px Durchmesser
- **Segmente:** 4-8 (je nach Kontext)
- **Animation:** 150ms ease-out
- **Trigger:** Rechtsklick auf selektiertes Objekt
- **Schließen:** Klick außerhalb, ESC, oder Aktion ausführen

### 8.2 Farbschema (passend zu Kenney UI)

| Element | Farbe |
|---------|-------|
| Hintergrund | `Color(0.1, 0.1, 0.15, 0.95)` |
| Segment Normal | `Color(0.2, 0.25, 0.3, 1.0)` |
| Segment Hover | `Color(0.3, 0.5, 0.8, 1.0)` |
| Icon | `Color(0.9, 0.9, 0.95, 1.0)` |
| Text | `Color(1.0, 1.0, 1.0, 1.0)` |
| Disabled | `Color(0.5, 0.5, 0.5, 0.5)` |

### 8.3 Keyboard Shortcuts

| Taste | Aktion |
|-------|--------|
| `1-8` | Segment direkt auswählen |
| `ESC` | Menü schließen |
| `Enter` | Hovering Segment ausführen |
| `Tab` | Nächstes Segment |

### 8.4 UX Best Practices (Recherche-Ergebnis)

Basierend auf [Radial Menu UX Research](https://www.stirlingweir.com/radial-menus) und [Apex Legends Analysis](https://uxdesign.cc/the-power-of-the-radial-menu-a-love-letter-to-apex-legends-from-a-ux-designer-and-perpetual-noob-1bec9b05e805):

| Feature | Implementierung | Priorität |
|---------|-----------------|-----------|
| **Discoverability** | Tooltip "Right-click for menu" bei Hover | Hoch |
| **Gesture Support** | Swipe-Richtung = direkte Aktion (ohne Loslassen) | Mittel |
| **Muscle Memory** | Feste Positionen, nie umsortieren | Hoch |
| **Audio Feedback** | Hover-Sound, Select-Sound | Niedrig |
| **Cancel Zone** | Mauszeiger zurück zur Mitte = Abbruch | Hoch |
| **Nested Menus** | Sub-Menü für "Add Marker" | Mittel |

**Fitts's Law:** Alle Optionen gleich weit vom Zentrum → gleicher Aufwand für jede Aktion.

---

## 9. Coherency System (NEU)

### 9.1 OPR Coherency Regeln

Basierend auf [OPR Rules FAQ](https://wiki.onepagerules.com/index.php/Rules_FAQ):

| Regel | Wert | Beschreibung |
|-------|------|--------------|
| **Model-zu-Model** | 1" | Jedes Model max 1" von einem anderen Model entfernt |
| **Max Kettenlänge** | 9" | Gesamte Unit innerhalb 9" (6" bei Skirmish) |
| **Elevated** | 3" | Wenn auf unterschiedlichen Höhen und 1" nicht passt |

### 9.2 Coherency Checker

```gdscript
class_name CoherencyChecker
extends RefCounted

const COHERENCY_DISTANCE_INCHES := 1.0
const MAX_CHAIN_DISTANCE_INCHES := 9.0  # 6.0 for Skirmish
const ELEVATED_COHERENCY_INCHES := 3.0

## Prüft Coherency für eine Unit
## Returns: { "valid": bool, "issues": Array[CoherencyIssue] }
static func check_unit_coherency(game_unit: GameUnit) -> Dictionary:
    var issues: Array = []
    var models = game_unit.get_alive_models()

    if models.size() <= 1:
        return { "valid": true, "issues": [] }

    # Check 1: Jedes Model muss innerhalb 1" von einem anderen sein
    for model in models:
        var has_neighbor = false
        for other in models:
            if model == other:
                continue
            var dist = _distance_between_models(model, other)
            if dist <= COHERENCY_DISTANCE_INCHES:
                has_neighbor = true
                break
            # Elevated coherency check
            if _is_elevated_different(model, other) and dist <= ELEVATED_COHERENCY_INCHES:
                has_neighbor = true
                break

        if not has_neighbor:
            issues.append({
                "type": "isolated",
                "model": model,
                "message": "Model %d is out of coherency" % (model.model_index + 1)
            })

    # Check 2: Max Kettenlänge 9"
    var max_dist = _get_max_chain_distance(models)
    if max_dist > MAX_CHAIN_DISTANCE_INCHES:
        issues.append({
            "type": "chain_too_long",
            "distance": max_dist,
            "message": "Unit chain exceeds %.0f\" (%.1f\")" % [MAX_CHAIN_DISTANCE_INCHES, max_dist]
        })

    return { "valid": issues.is_empty(), "issues": issues }

## Visualisiert Coherency-Linien zwischen Models
static func visualize_coherency(game_unit: GameUnit, parent: Node3D) -> Node3D:
    # Erstellt temporäre Linien zwischen Models
    # Grün = OK, Rot = zu weit
    pass
```

### 9.3 Coherency UI

```
┌─────────────────────────────────────────────────────────┐
│  ⚠️ COHERENCY WARNING                                   │
│                                                         │
│  "Battle Brothers" has coherency issues:                │
│                                                         │
│  • Model 3 is isolated (nearest: 2.4")                  │
│  • Unit chain: 10.2" (max 9")                           │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │      ●───●───●                                  │    │
│  │              ╲                                  │    │
│  │               ⚠️●  ← Out of coherency           │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  [Fix Automatically]          [Ignore]     [Close]      │
└─────────────────────────────────────────────────────────┘
```

---

## 10. Activation System (NEU)

### 10.1 Unit Activation State

```gdscript
# In GameUnit:
var is_activated: bool = false      # Diese Runde aktiviert?
var activation_round: int = 0       # In welcher Runde aktiviert?

# In Main/GameManager:
var current_round: int = 1
var current_player: int = 1         # 1 oder 2

func activate_unit(game_unit: GameUnit) -> void:
    game_unit.is_activated = true
    game_unit.activation_round = current_round

    # Attached Heroes werden mit-aktiviert
    for hero in game_unit.unit_properties.get("attached_heroes", []):
        hero.is_activated = true
        hero.activation_round = current_round

func new_round() -> void:
    current_round += 1
    # Reset alle Units
    for unit in all_game_units:
        unit.is_activated = false
```

### 10.2 Activation Tracker UI

```
┌─────────────────────────────────────────────────────────┐
│  ROUND 2 - Player 1's Turn                              │
├─────────────────────────────────────────────────────────┤
│  Player 1 (Blue):                                       │
│  ✅ Battle Brothers [5]      100pts   (activated)       │
│  ⬜ Assault Squad [10]       150pts                     │
│  ✅ Captain → Brothers       80pts    (with unit)       │
│  ⬜ Heavy Support [3]        120pts                     │
│                                                         │
│  Player 2 (Red):                                        │
│  ✅ Ork Boyz [20]            180pts   (activated)       │
│  ⬜ Warboss                  100pts                     │
│  ⬜ Lootas [5]               75pts                      │
├─────────────────────────────────────────────────────────┤
│  [End Turn]                              [New Round]    │
└─────────────────────────────────────────────────────────┘
```

---

## 11. Marker System (NEU)

### 11.1 Standard OPR Marker

Basierend auf [OPR Official Tokens](https://www.myminifactory.com/object/3d-print-opr-play-tokens-ruler-136924):

| Marker | Icon | Farbe | Beschreibung |
|--------|------|-------|--------------|
| **Activated** | ✓ | Grau | Unit hat diese Runde aktiviert |
| **Shaken** | S | Gelb | -1 Q/D, halbe Bewegung, keine Objectives |
| **Fatigued** | ⚡ | Orange | Keine Impact-Attacken diese Runde |
| **Wound** | ❤️ | Rot | Verlorene Wunden (1, 3, 5) |
| **Pinned** | 📍 | Blau | Kann sich nicht bewegen |
| **Spell** | ✨ | Lila | Aktiver Zauber-Effekt |

### 11.2 Custom Marker (Freitext)

```gdscript
class_name UnitMarker
extends RefCounted

enum MarkerType {
    STANDARD,    # Vordefiniert (Activated, Shaken, etc.)
    CUSTOM       # Freitext
}

var type: MarkerType
var name: String           # "Shaken" oder custom "Blessed by Priest"
var icon: String           # Emoji oder Icon-Path
var color: Color           # Hintergrundfarbe
var tooltip: String        # Optionale Beschreibung
var expires_on_round: int  # 0 = permanent, >0 = verschwindet nach Runde X

static func create_custom(text: String, color: Color = Color.WHITE) -> UnitMarker:
    var marker = UnitMarker.new()
    marker.type = MarkerType.CUSTOM
    marker.name = text
    marker.icon = "📝"
    marker.color = color
    marker.expires_on_round = 0
    return marker
```

### 11.3 Marker UI (Add Marker Dialog)

```
┌─────────────────────────────────────────────────────────┐
│  ADD MARKER                                             │
├─────────────────────────────────────────────────────────┤
│  Standard Markers:                                      │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐               │
│  │  ✓  │ │  S  │ │  ⚡ │ │  📍 │ │  ✨ │               │
│  │ Act │ │Shake│ │Fatig│ │Pinnd│ │Spell│               │
│  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘               │
│                                                         │
│  Wounds: [-] 3 [+]                                      │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│  Custom Marker:                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Blessed by Priest                               │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  Color: [🔴] [🟡] [🟢] [🔵] [⚪]                         │
│                                                         │
│  [Cancel]                                   [Add]       │
└─────────────────────────────────────────────────────────┘
```

### 11.4 Marker Visualisierung auf Model

```
       📍 S ❤️3
         ↓
    ┌─────────┐
    │  Model  │
    │    ●    │
    └─────────┘
```

- Marker als kleine Icons über dem Model (Billboard)
- Klick auf Marker → Entfernen oder Details
- Mehrere Marker nebeneinander

### 11.5 Smart Token Placement (NEU - 2026-01-15)

**Problem:** Bei engen Formationen (Dreiecke, Klumpen) überlappen Tokens mit Modell-Bases.

**Lösung 1: Boundary Tokens (Unit-Wide)**
- **Maximum-Minimum-Distanz Algorithmus**: Für jeden Punkt auf der Boundary wird die minimale Distanz zu allen Modellen berechnet. Der Punkt mit der GRÖSSTEN minimalen Distanz wird gewählt.
- Tokens werden automatisch an der "freisten" Stelle positioniert
- Implementiert in `unit_boundary_visualizer.gd::_calculate_token_start_index()`

**Lösung 2: Model-Specific Tokens**
- **Auto-Flip**: Wenn Tokens auf der Standard-Seite (9 Uhr) mit anderen Modellen überlappen würden, werden sie automatisch auf die gegenüberliegende Seite (3 Uhr) verschoben
- Implementiert in `radial_menu_controller.gd::_get_best_token_side()`

### 11.6 Base Spacing (NEU - 2026-01-15)

**Problem:** Festes 40mm Spacing führt zu Überlappungen bei großen Bases.

**Lösung:** Konstanter Randabstand statt Mittelpunktsabstand
- **Formel:** `spacing = diameter + 8mm` (konstanter 8mm Randabstand)
- Gilt für: Spawn, Arrangement (1-9, A), Arrow-Formation
- Berechnet dynamisch basierend auf größter Base in der Selektion
- Implementiert in:
  - `object_manager.gd::_get_max_base_diameter()`
  - `object_manager.gd::arrange_selected_in_rows()`
  - `object_manager.gd::arrange_selected_arrow()`
  - `opr_army_manager.gd::_spawn_unit()`

---

## 12. Save/Load & Multiplayer (NEU)

### 12.1 Save Format Erweiterung

```gdscript
# In save_manager.gd - Erweiterung für GameUnit/ModelInstance

func _serialize_game_unit(game_unit: GameUnit) -> Dictionary:
    var data = {
        "source_type": game_unit.source_type,
        "unit_properties": game_unit.unit_properties.duplicate(true),
        "is_activated": game_unit.is_activated,
        "activation_round": game_unit.activation_round,
        "models": []
    }

    for model in game_unit.models:
        data.models.append(_serialize_model_instance(model))

    return data

func _serialize_model_instance(model: ModelInstance) -> Dictionary:
    return {
        "model_index": model.model_index,
        "properties": model.properties.duplicate(true),
        "wounds_current": model.wounds_current,
        "wounds_max": model.wounds_max,
        "is_alive": model.is_alive,
        "markers": model.markers.duplicate(),
        "node_transform": _serialize_transform(model.node.global_transform)
    }
```

### 12.2 Multiplayer Sync

```gdscript
# In network_manager.gd - Neue RPCs für Unit-State

@rpc("any_peer", "call_remote", "reliable")
func sync_unit_activation(unit_id: String, is_activated: bool, round: int) -> void:
    var unit = _find_unit_by_id(unit_id)
    if unit:
        unit.is_activated = is_activated
        unit.activation_round = round

@rpc("any_peer", "call_remote", "reliable")
func sync_model_wounds(unit_id: String, model_index: int, wounds: int, is_alive: bool) -> void:
    var unit = _find_unit_by_id(unit_id)
    if unit:
        var model = unit.get_model(model_index)
        if model:
            model.wounds_current = wounds
            model.is_alive = is_alive

@rpc("any_peer", "call_remote", "reliable")
func sync_model_marker(unit_id: String, model_index: int, marker_data: Dictionary, add: bool) -> void:
    var unit = _find_unit_by_id(unit_id)
    if unit:
        var model = unit.get_model(model_index)
        if model:
            if add:
                model.markers.append(marker_data.name)
            else:
                model.markers.erase(marker_data.name)

@rpc("any_peer", "call_remote", "reliable")
func sync_hero_attachment(hero_id: String, target_id: String) -> void:
    var hero = _find_unit_by_id(hero_id)
    var target = _find_unit_by_id(target_id) if not target_id.is_empty() else null
    if hero:
        if target:
            HeroAttachment.attach_hero_to_unit(hero, target)
        else:
            HeroAttachment.detach_hero(hero)
```

---

## 13. Offene Fragen (Aktualisiert)

### Entschieden ✅

1. **Multi-Modell-Einheiten:** ✅ ENTSCHIEDEN
   - Alle Modelle einzeln als Node3D, mit shared GameUnit-Reference
   - Jedes Model hat eigene `ModelInstance` mit generischen Properties

2. **Architektur:** ✅ ENTSCHIEDEN → Generisch
   - **KEINE hardcodierten Rollen** (kein LEADER, SPECIALIST enum)
   - **KEINE hardcodierten Equipment-Namen** (kein "Medic", "Banner" special case)
   - Alles kommt als `properties: Dictionary` aus dem Import
   - Flexible Abfragen via `has_property()`, `get_equipment()`, etc.

3. **Waffen-Verteilung:** ✅ ENTSCHIEDEN → Basierend auf API `count`
   - Automatische Verteilung basierend auf `weapon.count` Feld
   - Equipment ohne `attacks` → erstes verfügbares Model
   - Manueller Override via Radialmenü möglich

4. **Wunden-Tracking:** ✅ Pro Modell
   - Parsed aus `Tough(X)` → `wounds_max` für JEDES Model
   - Default: 1 Wunde wenn kein Tough

5. **API vs Text-Export:** ✅ ENTSCHIEDEN → API bevorzugt
   - Army Forge TTS API liefert vollständig aufgelöste Daten
   - Base Sizes nur in API verfügbar (kritisch für Spawning)

6. **Hero-Attachment ("Joined to:"):** ✅ ENTSCHIEDEN → Manuell via Radialmenü
   - API hat diese Info nicht, Text-Export schon - aber API hat mehr andere Infos
   - Nach Import: User wird bei Heroes gefragt "Attach to Unit?"
   - Einfacher Dialog mit Liste aller Units der gleichen Armee
   - Typischerweise nur 3-5 Heroes pro Armee → akzeptabler Aufwand

7. **Coherency System:** ✅ ENTSCHIEDEN → Implementieren
   - 1" Model-zu-Model, 9" max Kettenlänge (6" Skirmish)
   - 3" bei unterschiedlichen Höhen
   - Visueller Check via Radialmenü "Check Coherency"
   - Optional: "Fix Automatically" Button

8. **Activation System:** ✅ ENTSCHIEDEN → Implementieren
   - Unit-Level Activation Toggle
   - Attached Heroes werden mit-aktiviert
   - Activation Tracker Panel (optional)
   - Runden-Counter

9. **Marker System:** ✅ ENTSCHIEDEN → Standard + Custom
   - Standard OPR Marker: Activated, Shaken, Fatigued, Pinned, Wound, Spell
   - Custom Marker mit Freitext + Farbauswahl
   - Marker können ablaufen (nach Runde X)
   - Visualisierung als Billboard über Model

10. **Save/Load:** ✅ ENTSCHIEDEN → Implementieren
    - GameUnit + ModelInstance Serialisierung
    - Wounds, Markers, Activation-State speichern
    - Positions via Transform

11. **Multiplayer Sync:** ✅ ENTSCHIEDEN → Implementieren
    - RPCs für: Activation, Wounds, Markers, Hero-Attachment
    - Reliable mode für State-Changes

### Noch zu klären ❓

(Alle Fragen entschieden!)

---

## 14. Abhängigkeiten

- **Kenney UI Theme** - Für konsistentes Styling ✅ Vorhanden
- **OPRArmyManager** - Für Unit-Lookups ✅ Vorhanden
- **Object Manager** - Für Selection-Events ✅ Vorhanden

---

## 15. Risiken

| Risiko | Wahrscheinlichkeit | Mitigation |
|--------|-------------------|------------|
| Performance bei vielen Units | Niedrig | Lazy evaluation |
| UI Clipping am Bildschirmrand | Mittel | Automatische Neupositionierung |
| Touch-Support | Mittel | Long-press statt Rechtsklick |

---

## 16. Nächste Schritte

Nach Genehmigung dieses Plans:

1. [ ] **Phase 1 starten:** `model_instance.gd` mit generischem Properties-System
2. [ ] `game_unit.gd` als System-agnostischer Wrapper
3. [ ] `equipment_distributor.gd` basierend auf API `count`
4. [ ] Integration in `opr_army_manager.gd`
5. [ ] Unit-Detection testen mit verschiedenen Army-Imports
6. [ ] Radialmenü Prototyp bauen

---

*Erstellt von Claude*
*Version: v4 - Vollständig mit UX, Coherency, Activation, Markers, Save/Load, Multiplayer*
*Letzte Aktualisierung: 2026-01-05*
