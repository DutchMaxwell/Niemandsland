# Plan: Unit-System und Radialmenü

**Erstellt:** 2026-01-05
**Status:** Entwurf zur Überprüfung

---

## 1. Problemstellung

Aktuell gibt es im Code verschiedene Objekttypen, aber keine einheitliche Definition von "Einheit". Bevor wir ein Radialmenü bauen können, müssen wir klar definieren:

1. **Was ist eine Einheit?** (vs. Terrain, Würfel, andere Objekte)
2. **Wie erkennen wir Einheiten automatisch?**
3. **Welche Aktionen sollen im Radialmenü verfügbar sein?**

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

## 3. Vorgeschlagene Lösung

### 3.1 Einheiten-Kategorien definieren

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

## 4. Radialmenü Design

### 4.1 Kontextabhängige Aktionen

Das Radialmenü zeigt unterschiedliche Aktionen basierend auf:
- **Objekttyp** (Unit, Terrain, Würfel)
- **Anzahl selektierter Objekte** (1, mehrere, gemischt)
- **Unit-Status** (aktiviert, verwundet, etc.)

### 4.2 Aktionen für Einheiten

```
┌─────────────────────────────────────────────┐
│           UNIT RADIAL MENU                  │
├─────────────────────────────────────────────┤
│                    [Stats]                  │
│                      ↑                      │
│     [Activate] ←   [●]   → [Wounds]         │
│                      ↓                      │
│                   [Delete]                  │
│                                             │
│  Erweitert (Shift):                         │
│  • Roll Attack    • Check Coherency         │
│  • Roll Defense   • Measure to Target       │
│  • Add Marker     • Lock/Unlock             │
└─────────────────────────────────────────────┘
```

### 4.3 Aktionen-Matrix

| Aktion | Einzeln | Mehrere | Bedingung |
|--------|---------|---------|-----------|
| **Stats anzeigen** | ✅ | ❌ | Nur GAME_UNIT |
| **Aktivieren/Deaktivieren** | ✅ | ✅ | Alle Units |
| **Wunden setzen** | ✅ | ❌ | Nur GAME_UNIT |
| **Löschen** | ✅ | ✅ | Alle |
| **Angriff würfeln** | ✅ | ✅ | Nur GAME_UNIT mit Waffen |
| **Verteidigung würfeln** | ✅ | ❌ | Nur GAME_UNIT |
| **Kohärenz prüfen** | ✅ | ✅ | Bei Multi-Modell Units |
| **Marker hinzufügen** | ✅ | ✅ | Alle Units |
| **Sperren/Entsperren** | ✅ | ✅ | Alle |
| **Messen zu Ziel** | ✅ | ❌ | Alle |

---

## 5. Implementierungsplan

### Phase 1: Unit-System Foundation (1-2 Tage)

**Dateien:**
- [ ] `scripts/unit_utils.gd` - Neuer Helper
- [ ] `scripts/object_manager.gd` - Anpassen für `unit` Gruppe
- [ ] `scripts/opr_army_manager.gd` - `unit` Gruppe hinzufügen

**Aufgaben:**
1. UnitUtils Klasse erstellen
2. Bestehende OPR-Units um `unit` Gruppe erweitern
3. Unit-Detection Funktionen testen

### Phase 2: Radialmenü Grundstruktur (2-3 Tage)

**Dateien:**
- [ ] `scenes/radial_menu.tscn` - Neue Szene
- [ ] `scripts/radial_menu.gd` - Menü-Logik
- [ ] `scripts/radial_menu_item.gd` - Einzelne Menü-Items

**Aufgaben:**
1. Radialmenü UI erstellen (8 Segmente)
2. Animations-System (Open/Close)
3. Hover-Feedback
4. Keyboard-Navigation (1-8)

### Phase 3: Kontext-Aktionen (2-3 Tage)

**Dateien:**
- [ ] `scripts/unit_actions.gd` - Aktions-Handler
- [ ] `scripts/object_manager.gd` - Integration

**Aufgaben:**
1. Stats-Popup (nutzt existierenden OPRStatsTooltip)
2. Aktivierungs-Toggle
3. Wunden-Dialog
4. Delete-Bestätigung
5. Integration in Object Manager (Rechtsklick)

### Phase 4: Erweiterte Aktionen (Optional, 2-3 Tage)

- [ ] Würfel-Integration (Attack/Defense Rolls)
- [ ] Kohärenz-Checker
- [ ] Marker-System
- [ ] Messen zu Ziel

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

## 7. Offene Fragen

1. **Proxy-System:** Sollen generische Miniaturen als "Proxy" für OPR-Einheiten markiert werden können?
   - Vorschlag: Ja, via Radialmenü → "Assign as Proxy" → Unit-Picker

2. **Multi-Modell-Einheiten:** Wie gruppieren wir Modelle einer Einheit?
   - Option A: Alle Modelle einzeln, aber mit shared Unit-Reference
   - Option B: Parent-Node für Einheit, Modelle als Children
   - **Empfehlung:** Option A (wie aktuell bei OPR)

3. **Wunden-Tracking:** Pro Modell oder pro Einheit?
   - Bei OPR: Pro Modell (jedes Modell hat eigene HP)
   - **Empfehlung:** Pro Modell mit visueller Anzeige

4. **Status-Marker:** Welche Marker standardmäßig?
   - Vorschlag: Aktiviert, Pinned, Shaken, Stunned, Custom

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
