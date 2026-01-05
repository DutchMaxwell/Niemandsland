# Plan: Unit-System und Radialmenü

**Erstellt:** 2026-01-05
**Status:** Entwurf v2 - Mit Model-Level Architektur
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
│  "Battle Brothers" (5 Modelle, 100pts)                  │
│  Quality: 4+, Defense: 4+                               │
├─────────────────────────────────────────────────────────┤
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│  │ MODEL 1 │ │ MODEL 2 │ │ MODEL 3 │ │ MODEL 4 │ │ MODEL 5 │
│  │ Sergeant│ │ Trooper │ │ Trooper │ │ Heavy   │ │ Medic   │
│  │ Leader  │ │         │ │         │ │Specialist│ │Specialist│
│  │ Pistol  │ │ Rifle   │ │ Rifle   │ │ H.Bolter│ │ Rifle   │
│  │ CCW     │ │         │ │         │ │         │ │ MedicKit│
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
│       ↓           ↓           ↓           ↓           ↓
│    Node3D      Node3D      Node3D      Node3D      Node3D
│   (auf Tisch) (auf Tisch) (auf Tisch) (auf Tisch) (auf Tisch)
└─────────────────────────────────────────────────────────┘
```

**Wichtig:**
- Eine **Unit** ist die spielmechanische Einheit (teilt Q/D, aktiviert zusammen)
- Ein **Model** ist ein einzelnes 3D-Objekt auf dem Tisch
- Models können unterschiedliche Ausrüstung/Rollen haben (Leader, Specialist)

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
    special_rules: Array   # Spezialregeln
    base_size_round: int   # Basengröße in mm
```

---

## 3. Model-Level Architektur (NEU)

### 3.1 ModelInstance Klasse

Jedes einzelne Modell auf dem Tisch erhält eine `ModelInstance`-Referenz:

```gdscript
class_name ModelInstance
extends RefCounted

# Referenzen
var unit: OPRUnit              # Parent Unit
var node: Node3D               # 3D Modell auf dem Tisch
var model_index: int           # Position in Unit (0-4)

# Model-spezifische Ausrüstung
var weapons: Array[OPRWeapon]  # Waffen DIESES Modells
var equipment: Array[String]   # Equipment DIESES Modells
var special_rules: Array[String]  # Model-spezifische Regeln

# Rollen
enum ModelRole { TROOPER, LEADER, SPECIALIST }
var role: ModelRole = ModelRole.TROOPER
var specialist_type: String = ""  # "Medic", "Radio", "Banner", "Heavy"

# Zustand (Runtime)
var wounds_current: int = 1
var wounds_max: int = 1
var is_alive: bool = true
var status_markers: Array[String] = []  # ["Activated", "Pinned"]

# Helper
func get_display_name() -> String:
    if role == ModelRole.LEADER:
        return "Leader"
    elif role == ModelRole.SPECIALIST:
        return specialist_type
    return "Trooper"

func is_leader() -> bool:
    return role == ModelRole.LEADER

func is_specialist() -> bool:
    return role == ModelRole.SPECIALIST
```

### 3.2 Erweiterte OPRUnit Struktur

```gdscript
class OPRUnit:
    # Bestehende Felder (Unit-Level)
    name: String
    size: int
    quality: int
    defense: int
    cost: int

    # NEU: Model-Level Daten
    var models: Array[ModelInstance] = []

    # Bestehende Felder werden zu "Pool" (für Verteilung)
    var weapons_pool: Array[OPRWeapon]    # Alle Waffen der Unit
    var equipment_pool: Array[String]      # Alle Equipment Items

    # Helper Methoden
    func get_model(index: int) -> ModelInstance
    func get_leader() -> ModelInstance
    func get_specialists() -> Array[ModelInstance]
    func get_alive_models() -> Array[ModelInstance]
    func get_model_for_node(node: Node3D) -> ModelInstance
```

### 3.3 Automatische Waffen-Verteilung (Option C)

Beim Import werden Waffen/Equipment automatisch auf Modelle verteilt:

```gdscript
func distribute_equipment_to_models(unit: OPRUnit) -> void:
    # Schritt 1: Leader identifizieren und ausstatten
    var leader = unit.models[0]
    leader.role = ModelRole.LEADER
    _assign_leader_weapons(leader, unit.weapons_pool)

    # Schritt 2: Spezialisten identifizieren
    for equipment in unit.equipment_pool:
        if equipment in ["Medic", "Radio", "Banner"]:
            var model = _find_unassigned_model(unit)
            model.role = ModelRole.SPECIALIST
            model.specialist_type = equipment
            model.equipment.append(equipment)

    # Schritt 3: Heavy Weapons verteilen
    for weapon in unit.weapons_pool:
        if _is_heavy_weapon(weapon):
            var model = _find_unassigned_model(unit)
            model.role = ModelRole.SPECIALIST
            model.specialist_type = "Heavy"
            model.weapons.append(weapon)

    # Schritt 4: Standard-Waffen an restliche Modelle
    var standard_weapon = _get_standard_weapon(unit.weapons_pool)
    for model in unit.models:
        if model.weapons.is_empty():
            model.weapons.append(standard_weapon)

func _is_heavy_weapon(weapon: OPRWeapon) -> bool:
    # Heavy Weapons haben oft spezielle Regeln oder hohe AP
    return "Heavy" in weapon.special_rules or \
           "Blast" in weapon.special_rules or \
           weapon.name.contains("Heavy")
```

### 3.4 Manueller Override

User kann Equipment-Verteilung anpassen:

```gdscript
# Via Radialmenü → "Edit Model Loadout"
func reassign_weapon(model: ModelInstance, weapon: OPRWeapon) -> void:
    # Waffe von aktuellem Träger entfernen
    var current_carrier = _find_weapon_carrier(weapon)
    if current_carrier:
        current_carrier.weapons.erase(weapon)

    # Waffe diesem Modell zuweisen
    model.weapons.append(weapon)

    # Event für UI-Update
    model_loadout_changed.emit(model)
```

### 3.5 Metadaten auf Node3D

Jedes 3D-Modell speichert:

```gdscript
# Beim Spawnen
node.set_meta("model_instance", model_instance)  # NEU
node.set_meta("opr_unit", unit)                  # Bestehend
node.set_meta("model_index", index)              # NEU
node.set_meta("player_id", player_id)

# Lookup
func get_model_instance(node: Node3D) -> ModelInstance:
    return node.get_meta("model_instance", null)
```

---

## 4. Einheiten-Kategorien

### 4.1 Kategorien definieren

Wir definieren drei Einheiten-Typen:

```gdscript
enum UnitType {
    NONE,           # Kein Unit (Terrain, Würfel, etc.)
    GAME_UNIT,      # OPR/WGS Unit mit vollständigen Stats
    PROXY_UNIT,     # Miniatur als Proxy für eine Einheit
    GENERIC_UNIT    # Generische Miniatur ohne Stats
}
```

### 3.2 Neue Gruppe: `unit`

**Alle Einheiten erhalten zusätzlich die Gruppe `unit`:**

```gdscript
# Bei OPR-Import:
model.add_to_group("unit")
model.add_to_group("opr_unit")

# Bei generischer Miniatur (optional aktivierbar):
miniature.add_to_group("unit")
miniature.add_to_group("miniature")
```

### 3.3 Unit Helper Script: `unit_utils.gd`

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

### Phase 1: Model-Level Architektur (2-3 Tage)

**Dateien:**
- [ ] `scripts/model_instance.gd` - Neue Klasse für Model-Daten
- [ ] `scripts/opr_api_client.gd` - OPRUnit erweitern mit models Array
- [ ] `scripts/opr_army_manager.gd` - ModelInstance beim Spawn erstellen
- [ ] `scripts/equipment_distributor.gd` - Automatische Waffen-Verteilung

**Aufgaben:**
1. ModelInstance Klasse erstellen
2. OPRUnit um `models: Array[ModelInstance]` erweitern
3. Equipment-Verteilungslogik implementieren
4. Node3D Metadaten erweitern (`model_instance`, `model_index`)
5. Lookup-Funktionen: `get_model_for_node()`, `get_all_unit_models()`

### Phase 2: Unit-System Foundation (1-2 Tage)

**Dateien:**
- [ ] `scripts/unit_utils.gd` - Neuer Helper
- [ ] `scripts/object_manager.gd` - Anpassen für `unit` Gruppe

**Aufgaben:**
1. UnitUtils Klasse erstellen
2. Bestehende OPR-Units um `unit` Gruppe erweitern
3. `select_all_unit_models()` Funktion
4. Unit-Detection Funktionen testen

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

## 6. UI/UX Spezifikation

### 6.1 Radialmenü Erscheinung

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

### 6.2 Farbschema (passend zu Kenney UI)

| Element | Farbe |
|---------|-------|
| Hintergrund | `Color(0.1, 0.1, 0.15, 0.95)` |
| Segment Normal | `Color(0.2, 0.25, 0.3, 1.0)` |
| Segment Hover | `Color(0.3, 0.5, 0.8, 1.0)` |
| Icon | `Color(0.9, 0.9, 0.95, 1.0)` |
| Text | `Color(1.0, 1.0, 1.0, 1.0)` |
| Disabled | `Color(0.5, 0.5, 0.5, 0.5)` |

### 6.3 Keyboard Shortcuts

| Taste | Aktion |
|-------|--------|
| `1-8` | Segment direkt auswählen |
| `ESC` | Menü schließen |
| `Enter` | Hovering Segment ausführen |
| `Tab` | Nächstes Segment |

---

## 10. Offene Fragen (Aktualisiert)

### Entschieden ✅

1. **Multi-Modell-Einheiten:** ✅ ENTSCHIEDEN
   - Alle Modelle einzeln als Node3D, mit shared Unit-Reference
   - Jedes Model hat eigene `ModelInstance` mit Loadout

2. **Waffen-Verteilung:** ✅ ENTSCHIEDEN → Option C
   - Automatische Verteilung beim Import
   - Manueller Override via "Edit Loadout" im Radialmenü

3. **Wunden-Tracking:** ✅ Pro Modell
   - Jedes Model hat `wounds_current` und `wounds_max`
   - Heroes haben oft mehrere Wounds

### Noch zu klären ❓

4. **Proxy-System:** Sollen generische Miniaturen als "Proxy" für OPR-Einheiten markiert werden können?
   - Vorschlag: Ja, via Radialmenü → "Assign as Proxy" → Unit-Picker

5. **Status-Marker:** Welche Marker standardmäßig?
   - Vorschlag: Activated, Pinned, Shaken, Stunned, Fatigued, Custom

6. **Leader-Nachfolge:** Was passiert wenn Leader stirbt?
   - Option A: Nächstes Model wird automatisch Leader
   - Option B: User wählt neuen Leader
   - Option C: Kein neuer Leader (Unit ohne Leader-Bonus)

7. **Kohärenz-Distanz:** Welche Standard-Distanz?
   - OPR Standard: 1" zwischen Modellen
   - Konfigurierbar pro Spielsystem?

---

## 8. Abhängigkeiten

- **Kenney UI Theme** - Für konsistentes Styling ✅ Vorhanden
- **OPRArmyManager** - Für Unit-Lookups ✅ Vorhanden
- **Object Manager** - Für Selection-Events ✅ Vorhanden

---

## 9. Risiken

| Risiko | Wahrscheinlichkeit | Mitigation |
|--------|-------------------|------------|
| Performance bei vielen Units | Niedrig | Lazy evaluation |
| UI Clipping am Bildschirmrand | Mittel | Automatische Neupositionierung |
| Touch-Support | Mittel | Long-press statt Rechtsklick |

---

## 10. Nächste Schritte

Nach Genehmigung dieses Plans:

1. [ ] **Phase 1 starten:** `unit_utils.gd` erstellen
2. [ ] Bestehende Units mit `unit` Gruppe taggen
3. [ ] Unit-Detection testen
4. [ ] Radialmenü Prototyp bauen

---

*Erstellt von Claude*
*Letzte Aktualisierung: 2026-01-05*
