# Radial Menu AAA Overhaul Plan

## Mission Statement
**"Wir bauen das GTA des digitalen Wargamings!"**

Alles was wir tun obliegt dieser Maxime. Kein TuxRacer-Level - nur AAA Blockbuster Gaming Qualität.

---

## Aktuelle Probleme

### Kritisch
1. **Kamera funktioniert nicht mehr** - `_unhandled_input` blockiert alles
2. **Rechtsklick ist schlechtes UX** - Konflikte mit Kamera-Rotation
3. **Features nicht implementiert** - 90% sind nur `print()` Statements

### Design
4. **Hässliches Design** - Emojis statt echte Icons, keine Labels sichtbar
5. **Keine Tooltips** - Man weiß nicht was die Buttons tun
6. **Keine Animationen** - Statisch und langweilig
7. **Keine Sound-Effekte** - Kein Feedback

---

## AAA Lösung

### Phase 1: Grundfunktionalität reparieren

#### 1.1 Kamera-Fix
- [ ] `camera_controller.gd` zurück zu `_input()`
- [ ] Stattdessen: Check ob Radialmenü offen ist bevor Rotation startet

#### 1.2 Long-Press Trigger
- [ ] Linke Maustaste gedrückt halten (0.5s) öffnet Menü
- [ ] Visuelles Feedback: Kreis füllt sich während des Haltens
- [ ] Abbrechen durch Loslassen vor 0.5s
- [ ] Rechtsklick schließt Menü (nicht öffnen!)

#### 1.3 Menü-Optionen reduzieren
Weniger ist mehr. Nur was wirklich gebraucht wird:

**Für einzelnes Model:**
- Stats (öffnet Tooltip)
- Wounds +/- (direkt im Menü)
- Remove (Model entfernen/tot markieren)

**Für ganze Unit:**
- Stats (öffnet Tooltip)
- Activate/Deactivate (Toggle)
- Coherency Check (visuell)
- Remove Unit

---

### Phase 2: AAA Visuelles Design

#### 2.1 Modernes Radial Menu
```
         [Icon]
        [Label]
    ╭─────────────╮
   /               \
  │    [CENTER]     │   ← Einheit-Name + Preview
   \               /
    ╰─────────────╯
        [Label]
         [Icon]
```

#### 2.2 Design-Elemente
- [ ] **Glasmorphism-Effekt** - Halbtransparenter Blur-Hintergrund
- [ ] **Echte Icons** - Keine Emojis, eigene SVG/PNG Icons
- [ ] **Labels unter Icons** - Immer sichtbar, nicht nur Emoji
- [ ] **Hover-Effekt** - Segment leuchtet auf, Label wird größer
- [ ] **Selection-Ring** - Animierter Ring um aktives Segment

#### 2.3 Animationen
- [ ] **Öffnen**: Segments "explodieren" vom Zentrum (0.15s ease-out-back)
- [ ] **Schließen**: Segments "implodieren" zum Zentrum (0.1s ease-in)
- [ ] **Hover**: Sanftes Pulsieren des Segments
- [ ] **Select**: Flash-Effekt + Scale-Punch

#### 2.4 Farben (Dark Theme)
```gdscript
const COLOR_BG = Color(0.1, 0.1, 0.12, 0.95)        # Fast schwarz
const COLOR_SEGMENT = Color(0.15, 0.17, 0.2, 0.9)   # Dunkelgrau
const COLOR_HOVER = Color(0.2, 0.5, 0.9, 0.9)       # Blau
const COLOR_ACTIVE = Color(0.3, 0.8, 0.4, 0.9)      # Grün
const COLOR_DANGER = Color(0.9, 0.3, 0.3, 0.9)      # Rot (Delete)
const COLOR_TEXT = Color(1.0, 1.0, 1.0, 1.0)        # Weiß
```

---

### Phase 3: Features implementieren

#### 3.1 Unit Stats
- [ ] Zeigt `OPRStatsTooltip` neben dem Model
- [ ] Tooltip bleibt offen bis Klick woanders
- [ ] Zeigt: Name, Q, D, Waffen, Regeln, Punkte

#### 3.2 Wounds System
- [ ] +/- Buttons direkt im Segment
- [ ] Oder: Sub-Menü mit Zahlen 0-10
- [ ] Visuelles Feedback auf Model (Damage-Marker)
- [ ] Model wird halbtransparent bei 0 Wounds

#### 3.3 Activation Toggle
- [ ] Grüner Haken = aktiviert
- [ ] Roter X = deaktiviert
- [ ] Model bekommt visuellen "Activated" Ring

#### 3.4 Coherency Check
- [ ] Zeigt Linien zwischen Models
- [ ] Grün = OK, Rot = zu weit
- [ ] Pulsierender Effekt für problematische Models
- [ ] Auto-Hide nach 3 Sekunden

#### 3.5 Remove/Delete
- [ ] Bestätigungs-Popup für Unit-Delete
- [ ] Model-Remove: Fade-out Animation
- [ ] Sound-Effekt

---

### Phase 4: Sound Design

#### 4.1 UI Sounds
- [ ] Menu Open: Soft "woosh"
- [ ] Menu Close: Reverse "woosh"
- [ ] Hover: Subtle "tick"
- [ ] Select: Satisfying "click"
- [ ] Delete: Warning "thunk"

---

### Phase 5: Polish

#### 5.1 Keyboard Shortcuts
- [ ] 1-6 für schnelle Auswahl
- [ ] ESC zum Schließen
- [ ] Shortcuts im Label anzeigen

#### 5.2 Touch Support (Future)
- [ ] Größere Hit-Areas
- [ ] Swipe-Gesten

#### 5.3 Accessibility
- [ ] High-Contrast Mode
- [ ] Größere Schrift Option

---

## Implementierungs-Reihenfolge

1. **JETZT**: Kamera-Fix + Long-Press Trigger
2. **DANN**: Reduziertes Menü mit funktionierenden Features
3. **DANACH**: Visuelles Redesign
4. **SPÄTER**: Sound + Polish

---

## Dateien die geändert werden müssen

| Datei | Änderung |
|-------|----------|
| `camera_controller.gd` | Zurück zu `_input()`, Radialmenü-Check |
| `object_manager.gd` | Long-Press statt Right-Click |
| `radial_menu.gd` | Komplettes visuelles Redesign |
| `radial_menu_controller.gd` | Features implementieren |
| `main.gd` | Event-Handling anpassen |
| `opr_stats_tooltip.gd` | Integration mit Radialmenü |

---

## Definition of Done

- [ ] Kamera funktioniert wieder (Rechtsklick = Rotation)
- [ ] Long-Press öffnet Menü
- [ ] Alle Menü-Optionen funktionieren
- [ ] Modernes, AAA-würdiges Design
- [ ] Smooth Animationen
- [ ] Keine Bugs, keine Glitches
- [ ] **Sieht aus wie ein 60€ Spiel, nicht wie Freeware**
