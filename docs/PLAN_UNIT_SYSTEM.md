# Plan: Unit-System und Radialmenü

**Erstellt:** 2026-01-05
**Status:** Entwurf v3 - Generische Architektur (API-verifiziert)
**Letzte Änderung:** 2026-01-05

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

### 4.4 Manueller Override

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

### 4.5 Metadaten auf Node3D

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

### Phase 1: Generische Model-Architektur

**Neue Dateien:**
- [ ] `scripts/model_instance.gd` - Generische Model-Daten mit Properties Dictionary
- [ ] `scripts/game_unit.gd` - System-agnostischer Unit-Wrapper
- [ ] `scripts/equipment_distributor.gd` - Automatische Equipment-Verteilung

**Änderungen an bestehenden Dateien:**
- [ ] `scripts/opr_army_manager.gd` - GameUnit + ModelInstance beim Spawn erstellen
- [ ] `scripts/opr_api_client.gd` - Tough(X) Parsing verbessern

**Aufgaben:**
1. ModelInstance mit generischem `properties: Dictionary` erstellen
2. GameUnit Wrapper-Klasse erstellen
3. EquipmentDistributor basierend auf API `count` Feld
4. Tough(X) → wounds_max Parsing
5. Node3D Metadaten: `model_instance`, `game_unit`, `model_index`
6. Lookup-Funktionen: `get_model_for_node()`, `get_models_with_equipment()`

### Phase 2: Unit-System Foundation

**Dateien:**
- [ ] `scripts/unit_utils.gd` - Neuer Helper mit generischen Queries
- [ ] `scripts/object_manager.gd` - Anpassen für `unit` Gruppe

**Aufgaben:**
1. UnitUtils Klasse mit `is_unit()`, `get_game_unit()`, etc.
2. Bestehende OPR-Units um `unit` Gruppe erweitern
3. `select_all_unit_models()` Funktion
4. `get_models_with_property()` generische Suche

### Phase 3: Radialmenü Grundstruktur (2-3 Tage)

**Dateien:**
- [ ] `scenes/radial_menu.tscn` - Neue Szene
- [ ] `scripts/radial_menu.gd` - Menü-Logik
- [ ] `scripts/radial_menu_item.gd` - Einzelne Menü-Items

**Aufgaben:**
1. Radialmenü UI erstellen (6-8 Segmente)
2. Animations-System (Open/Close)
3. Kontext-Detection (1 Model vs. mehrere vs. ganze Unit)
4. Header mit Model/Unit Info
5. Keyboard-Navigation (1-8)

### Phase 4: Kontext-Aktionen (2-3 Tage)

**Dateien:**
- [ ] `scripts/unit_actions.gd` - Aktions-Handler
- [ ] `scripts/model_stats_popup.gd` - Model-spezifische Stats
- [ ] `scripts/loadout_editor.gd` - Waffen-Zuweisung Dialog

**Aufgaben:**
1. Unit Stats Popup (erweitert OPRStatsTooltip)
2. Model Stats Popup (zeigt Loadout)
3. Aktivierungs-Toggle (Unit-Level)
4. Wunden-Dialog (Model-Level)
5. Delete mit Warnings (Leader/Specialist)
6. "Select Unit" Aktion

### Phase 5: Erweiterte Aktionen (2-3 Tage)

- [ ] Loadout Editor (Waffen reassign)
- [ ] Kohärenz-Checker mit Visualisierung
- [ ] Attack Roll (pro Model oder Unit)
- [ ] Marker-System (Model + Unit Level)

### Phase 6: Polish & Edge Cases (1-2 Tage)

- [ ] Specialist-Reassign bei Delete
- [ ] Leader-Nachfolge Logik
- [ ] Save/Load mit Model-Level Daten
- [ ] Multiplayer Sync für ModelInstance

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

---

## 9. Offene Fragen (Aktualisiert)

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
   - Text-Export nur als Fallback (hat zusätzliche Infos wie "Joined to:")

### Noch zu klären ❓

6. **Hero-Attachment ("Joined to:"):**
   - Nur in Text-Export, nicht in API!
   - Option A: Text-Export parsen für diese Info
   - Option B: User manuell zuweisen via Radialmenü
   - Option C: Separate API-Call für Hero-Details

7. **Proxy-System:** Sollen generische Miniaturen als "Proxy" markiert werden können?
   - Vorschlag: Ja, via Radialmenü → "Assign Stats" → Unit-Picker

8. **Status-Marker:** Welche Marker standardmäßig?
   - Vorschlag: Dynamisch aus Spielsystem (keine hardcodierten Marker)
   - OPR: Activated, Stunned, Shaken, Fatigued
   - Custom Marker immer möglich

9. **Kohärenz-Distanz:** Welche Standard-Distanz?
   - OPR Standard: 1" zwischen Modellen
   - Konfigurierbar pro Spielsystem

---

## 10. Abhängigkeiten

- **Kenney UI Theme** - Für konsistentes Styling ✅ Vorhanden
- **OPRArmyManager** - Für Unit-Lookups ✅ Vorhanden
- **Object Manager** - Für Selection-Events ✅ Vorhanden

---

## 11. Risiken

| Risiko | Wahrscheinlichkeit | Mitigation |
|--------|-------------------|------------|
| Performance bei vielen Units | Niedrig | Lazy evaluation |
| UI Clipping am Bildschirmrand | Mittel | Automatische Neupositionierung |
| Touch-Support | Mittel | Long-press statt Rechtsklick |

---

## 12. Nächste Schritte

Nach Genehmigung dieses Plans:

1. [ ] **Phase 1 starten:** `model_instance.gd` mit generischem Properties-System
2. [ ] `game_unit.gd` als System-agnostischer Wrapper
3. [ ] `equipment_distributor.gd` basierend auf API `count`
4. [ ] Integration in `opr_army_manager.gd`
5. [ ] Unit-Detection testen mit verschiedenen Army-Imports
6. [ ] Radialmenü Prototyp bauen

---

*Erstellt von Claude*
*Version: v3 - Generische Architektur (API-verifiziert)*
*Letzte Aktualisierung: 2026-01-05*
