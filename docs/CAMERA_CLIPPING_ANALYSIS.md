# Kamera-Clipping Problem - Analyse & Lösungsplan

## Problem-Beschreibung
Beim Zoomen tritt "Clipping" auf - Objekte werden durchsichtig/unsichtbar oder die Kamera geht durch Geometrie.

## Forschungsergebnisse

### 1. Arten von Clipping-Problemen

**A) Near-Plane Clipping** (häufigste Ursache)
- Objekte näher als `camera.near` werden komplett unsichtbar
- Symptom: Objekte "verschwinden" wenn Kamera zu nah kommt
- Ursache: Near-Plane schneidet Geometrie ab

**B) Physikalisches Clipping**
- Kamera geht durch Wände/Boden/Objekte
- Symptom: Man sieht "durch" Objekte hindurch oder ins Leere
- Ursache: Keine/fehlerhafte Kollisionserkennung

**C) Z-Fighting**
- Oberflächen flackern/flimmern
- Ursache: Depth-Buffer Präzisions-Probleme bei schlechtem near/far Verhältnis

### 2. Godot 4 Spezifika

**Reverse-Z (Godot 4.3+)**
- Automatisch aktiviert, verbessert Depth-Buffer Präzision massiv
- Quelle: [Introducing Reverse Z - Godot Engine](https://godotengine.org/article/introducing-reverse-z/)

**Near/Far Ratio Regel**
- Empfohlen: `far / near < 1000:1`
- Aktuell: `100 / 0.5 = 200:1` ✅ (gut!)
- Bei zu kleinem near: Z-Fighting
- Bei zu großem near: Objekte werden abgeschnitten
- Quelle: [Depth Buffer Precision - OpenGL Wiki](https://www.khronos.org/opengl/wiki/Depth_Buffer_Precision)

**SpringArm3D Probleme**
- Bekannte Bugs in Godot 4.x mit Clipping
- Nicht empfohlen für unseren Use-Case
- Quelle: [SpringArm3D clips through geometry - Issue #69771](https://github.com/godotengine/godot/issues/69771)

**Raycast-Kollision (Best Practice)**
- Empfohlene Methode für Third-Person/RTS Kameras
- Muss korrekt implementiert werden mit:
  - Collision Layers/Masks
  - Exclude-Liste
  - Sicherheitsmargin
- Quelle: [Crafting Dynamic Third-Person Camera - Wayline](https://www.wayline.io/blog/dynamic-third-person-camera-godot)

### 3. Mögliche Ursachen in unserem Code

#### A) Near-Plane zu groß (0.5)
```gdscript
# scenes/main.tscn:85
near = 0.5  # ← Könnte zu aggressiv sein!
```
**Problem:** Schneidet alles < 0.5 Einheiten ab
**Für Tabletop:** Miniatur mit 0.05m Höhe bei Nahaufnahme wird ab ~0.6m Kamera-Abstand abgeschnitten

#### B) Raycast-Implementierung fehlerhaft
```gdscript
# scripts/camera_controller.gd:100-101
var query = PhysicsRayQueryParameters3D.create(_target_position, desired_camera_pos)
query.exclude = []  # ← Keine Excludes!
```
**Probleme:**
1. Collision Layers nicht spezifiziert
2. Könnte eigene Kamera-Node treffen
3. Keine Filterung nach relevanten Objekten

#### C) Tisch-Kollision nicht bereit
```gdscript
# scripts/table.gd:58-64
func setup_table(size_feet: Vector2):
    var box_shape = BoxShape3D.new()
    collision_shape.shape = box_shape  # ← Wird dynamisch erstellt!
```
**Problem:** Raycast könnte laufen BEVOR die Tisch-Kollision erstellt wurde

#### D) Collision Layers nicht gesetzt
```gdscript
# Keine expliziten collision_layer Einstellungen für Kamera-Raycast
```

### 4. Nvidia Driver Bug (2025)
**Symptom:** Grafische Glitches in Vulkan-Apps
**Betroffen:** Nvidia 572.16+
**Fix:** Zu Direct3D 12 wechseln oder Driver 572.60+
**Quelle:** [Nvidia 572.16+ regression - Issue #102219](https://github.com/godotengine/godot/issues/102219)

## Diagnose-Plan

### Phase 1: Problem identifizieren (10 Min)
1. ✅ Debug-Output für Raycast hinzufügen
   - Wird Kollision erkannt?
   - Welches Objekt wird getroffen?
   - Welche Distanz wird berechnet?

2. ✅ Near-Plane Experiment
   - Test mit near = 0.05 (sehr klein)
   - Test mit near = 1.0 (sehr groß)
   - Vergleich: Wo tritt das Clipping auf?

3. ✅ Collision-Layer Prüfung
   - Welche Layer benutzt der Tisch?
   - Welche Layer benutzen Objekte?
   - Wird der Raycast überhaupt etwas treffen?

### Phase 2: Spezifische Tests (15 Min)
**Test A: Near-Plane Clipping**
```gdscript
# Setze near = 0.05, zoome nah ran
# Erwartung: Kein Clipping mehr ABER mögliches Z-Fighting
```

**Test B: Raycast Debug**
```gdscript
# Füge print() statements hinzu
# Zeige Kollisionspunkte visuell mit DebugDraw
```

**Test C: Collision Layers**
```gdscript
# Prüfe: collision_layer und collision_mask
# Setze explizite Layer für Kamera-Raycasts
```

## Lösungs-Strategien

### Strategie 1: Near-Plane Optimierung (EINFACH)
**Wenn:** Objekte werden einfach unsichtbar wenn nah

**Lösung:**
```gdscript
# Tabletop-optimierte Werte
near = 0.05  # 5cm - erlaubt sehr nahe Details
far = 100.0  # Bleibt
# Ratio: 2000:1 (noch OK für Reverse-Z in Godot 4.3)
```

**Pro:** ✅ Schnell, einfach
**Contra:** ⚠️ Leichtes Risiko für Z-Fighting

### Strategie 2: Raycast-Korrektur (MITTEL)
**Wenn:** Kamera geht durch Objekte

**Lösung:**
```gdscript
# Collision Layers definieren
const LAYER_WORLD = 1       # Tisch, Terrain
const LAYER_OBJECTS = 2     # Miniaturen, Gebäude
const LAYER_CAMERA = 4      # Kamera selbst

# Raycast nur gegen Welt und Objekte
query.collision_mask = LAYER_WORLD | LAYER_OBJECTS
query.exclude = [self]  # Kamera-Node ausschließen

# Margin dynamisch anpassen
var dynamic_margin = max(0.3, _current_zoom * 0.1)
```

**Pro:** ✅ Professionell, flexibel
**Contra:** ⚠️ Komplexer, braucht Layer-Setup

### Strategie 3: Hybrid-Ansatz (EMPFOHLEN)
**Kombination aus 1 + 2:**

1. **Near-Plane auf sweet spot**
   ```gdscript
   near = 0.1  # Kompromiss: nah genug, aber sicher
   ```

2. **Raycast mit Layers**
   ```gdscript
   # Nur relevante Kollisionen
   query.collision_mask = 1  # Layer 1 = Table + Walls
   ```

3. **Dynamischer Zoom-Stop**
   ```gdscript
   # Je näher, desto größerer Buffer
   var safe_distance = collision_distance - (0.2 + _current_zoom * 0.05)
   ```

4. **Visual Feedback**
   ```gdscript
   # Wenn Kamera stoppt, zeige warum (optional)
   if result:
       print("Camera blocked by: ", result.collider.name)
   ```

### Strategie 4: Alternative Kamera-Systeme (FALLBACK)
**Wenn nichts hilft:**

**Option A: Orthogonal-Kamera**
- Keine Perspektive = kein near-plane Problem
- Wie RTS-Klassiker (StarCraft, Age of Empires)

**Option B: Fixed Distance**
- Kein Zoom unter 2.0 Einheiten
- Einfach, aber limitiert

**Option C: Phantom Camera Plugin**
- Third-Party Lösung mit automatischem Collision Handling
- Quelle: [Phantom Camera Godot - Toxigon](https://toxigon.com/phantom-camera-godot)

## Implementierungs-Reihenfolge

### Schritt 1: Diagnose (JETZT)
```gdscript
# Debug-Version mit Logging
func _update_camera_transform() -> void:
    # ... existing code ...
    if result:
        print("COLLISION DETECTED:")
        print("  Object: ", result.collider.name)
        print("  Distance: ", _target_position.distance_to(result.position))
        print("  Camera zoom: ", _current_zoom)
        print("  Safe distance: ", safe_distance)
```

### Schritt 2: Quick Fix Test (5 Min)
```gdscript
# A) Near-Plane runter
near = 0.1  # Statt 0.5

# B) Collision Mask setzen
query.collision_mask = 1  # Nur Layer 1
```

### Schritt 3: Proper Fix (15 Min)
- Collision Layers im Projekt definieren
- Table.gd: `collision_layer = 1` explizit setzen
- Raycast mit korrektem Mask
- Dynamic margin basierend auf zoom

### Schritt 4: Polish (10 Min)
- Visual debugging (optional)
- Edge case handling
- Performance check

## Testing Checkliste

- [ ] Zoom nah an Tisch → Kein Clipping?
- [ ] Zoom nah an Miniatur → Kein Clipping?
- [ ] Zoom nah an Gebäude → Kein Clipping?
- [ ] Kamera rotieren while zoomed → Smooth?
- [ ] Performance OK? (FPS check)
- [ ] Verschiedene Tischgrößen testen
- [ ] Edge of table → Kein Clipping?

## Empfohlene Werte (Final)

```gdscript
# Camera3D
near = 0.1   # Kompromiss zwischen Präzision und Nähe
far = 100.0  # Für Tabletop ausreichend

# Camera Controller
min_zoom = 0.8           # Nah genug für Details
_collision_margin = 0.3  # Moderater Buffer
zoom_speed = 0.15        # Fein genug

# Raycast
collision_mask = 1       # Nur Tisch/Wände
exclude = [self]         # Kamera ignorieren
```

## Quellen
- [Introducing Reverse Z - Godot Engine](https://godotengine.org/article/introducing-reverse-z/)
- [Crafting Dynamic Third-Person Camera - Wayline](https://www.wayline.io/blog/dynamic-third-person-camera-godot)
- [Depth Buffer Precision - OpenGL Wiki](https://www.khronos.org/opengl/wiki/Depth_Buffer_Precision)
- [SpringArm3D clipping Issue #69771](https://github.com/godotengine/godot/issues/69771)
- [Camera clipping prevention - Godot Forum](https://forum.godotengine.org/t/how-can-i-prevent-a-third-person-camera-from-clipping-through-walls-or-seeing-through-them-when-its-close-to-a-surface/114198)
- [Nvidia 572.16+ regression Issue #102219](https://github.com/godotengine/godot/issues/102219)
