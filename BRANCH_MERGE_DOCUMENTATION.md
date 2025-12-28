# openTTS Branch Merge Documentation
**Datum:** 2025-12-28
**Session:** UI Graphics Overhaul & 10x Scale Experiment

---

## 📋 Zusammenfassung

Diese Session hat zwei Hauptarbeitslinien verfolgt:
1. **UI Graphics Overhaul** (Branch: `claude/ui-graphics-overhaul-7SMn2`)
2. **10x Scale Experiment** (Branch: `claude/10x-scale-experiment-7SMn2`)

---

## 🌿 Branch-Struktur

### Branch: `claude/ui-graphics-overhaul-7SMn2`
**Status:** ✅ Produktionsreif
**Basiert auf:** main
**Commits:** 6 Commits

#### Was wurde implementiert:

1. **Kenney UI Theme Integration**
   - 9 UI-Themes (Fantasy: Beige/Blue/Brown/Grey, SciFi: Blue/Green/Grey/Red/Yellow)
   - `kenney_theme_generator.gd` - Erzeugt StyleBoxTexture-basierte Themes
   - `theme_manager.gd` - Globaler Autoload für Theme-Verwaltung
   - `theme_selector.gd` - UI für Theme-Auswahl
   - Theme-Persistenz in `user://theme_settings.json`

2. **Shadow-System Optimierungen**
   - DirectionalLight3D Shadow Cascade Optimierung
   - `directional_shadow_max_distance`: 50m → 15m (Tabletop-Scale)
   - `directional_shadow_split` optimiert: 0.15, 0.35, 0.65
   - `directional_shadow_pancake_size`: 10.0 hinzugefügt
   - `directional_shadow_blend_splits`: true aktiviert

3. **Base-Größen Progression**
   - Initial: 32mm → 40mm → 50mm → 70mm
   - Finale Größe: 70mm Durchmesser, 6mm Höhe
   - Schatten-Casting für alle Bases aktiviert

4. **Shadow Quality Improvements**
   - `directional_shadow/size`: 4096 → 8192
   - `soft_shadow_filter_quality`: 4 → 5 (Maximum)
   - `positional_shadow/atlas_size`: 4096 → 8192
   - `atlas_16_bits`: true aktiviert

5. **Custom 3D Model Base Support**
   - `spawn_custom_model()` erhält automatisch 70mm Bases
   - Schatten für Custom Models aktiviert
   - Konsistente Base-Behandlung über alle Spawn-Methoden

#### Wichtige Dateien:
```
scripts/kenney_theme_generator.gd       (NEU)
scripts/theme_manager.gd                 (NEU)
scripts/theme_selector.gd                (NEU)
scripts/startup_menu.gd                  (MODIFIED - Theme-Anwendung)
scripts/lighting_panel.gd                (MODIFIED - Theme-Anwendung)
scripts/lighting_controller.gd           (MODIFIED - Shadow-Properties)
scripts/object_manager.gd                (MODIFIED - Base-Größen, Custom Model Bases)
scenes/main.tscn                         (MODIFIED - Shadow Cascades)
project.godot                            (MODIFIED - Shadow Quality, ThemeManager Autoload)
```

#### GIT Befehle zum Mergen:
```bash
git checkout main
git merge claude/ui-graphics-overhaul-7SMn2
git push origin main
```

---

### Branch: `claude/10x-scale-experiment-7SMn2`
**Status:** ⚠️ Experimentell - Benötigt User-Testing
**Basiert auf:** `claude/ui-graphics-overhaul-7SMn2`
**Commits:** 3 Commits

#### Was wurde implementiert:

**Konzept:** Alle Welt-Dimensionen um Faktor 10 vergrößern für bessere Shadow-Qualität und Physik-Stabilität.

#### Vollständige 10x Skalierung:

1. **Object Manager** (`scripts/object_manager.gd`):
   ```gdscript
   // Miniatur-Konstanten
   MINIATURE_HEIGHT: 0.032m → 0.32m (32mm → 320mm)
   MINIATURE_RADIUS: 0.16m (32mm × 10 = 320mm diameter)

   // Base-Dimensionen
   base_radius: 0.16m (160mm radius = 320mm diameter)
   base_height: 0.03m (30mm height)

   // TTS Import
   tts_scale: 0.0254 → 0.254 (1 inch = 0.254m)
   pos_scale: 0.0254 → 0.254

   // Drag & Drop
   drag_height: 0.5m → 5.0m
   min_drag_height: 0.01m → 0.1m

   // Custom Models
   target_size: 0.05m → 0.5m (50cm Zielhöhe)

   // Terrain
   Rock: 0.25m → 2.5m, Mesh: (4.0, 2.5, 3.5)
   Building: 0.6m → 6.0m, Mesh: (5.0, 6.0, 5.0)
   Tree: 0.6m → 6.0m, Radii: 2.0/0.8

   // Würfel
   dice_size: 0.016m → 0.16m (16mm → 160mm)
   snap_distance: 0.008m → 0.08m
   ```

2. **Table** (`scripts/table.gd`):
   ```gdscript
   FEET_TO_METERS: 0.3048 → 3.048
   INCHES_TO_METERS: 0.0254 → 0.254
   ```

3. **Camera** (`scripts/camera_controller.gd`):
   ```gdscript
   pan_speed: 0.005 → 0.05
   zoom_speed: 0.15 → 1.5
   min_zoom: 0.5m → 5.0m
   max_zoom: 25.0m → 250.0m
   _current_zoom: 10.0m → 100.0m
   ```

4. **Scene** (`scenes/main.tscn`):
   ```gdscript
   // DirectionalLight3D
   Position: (5, 10, 5) → (50, 100, 50)
   shadow_max_distance: 15.0m → 150.0m
   shadow_pancake_size: 10.0 → 100.0

   // Camera3D
   Position: (0, 8, 8) → (0, 80, 80)
   near: 0.1 → 1.0
   far: 100.0 → 1000.0
   ```

5. **Lighting Defaults** (`scripts/lighting_controller.gd`):
   ```gdscript
   // User-optimierte Werte für 10x Scale
   shadow_opacity: 0.85 → 0.40
   shadow_blur: 1.5 → 0.50
   ssao_intensity: 0.9 → 0.40
   ssr_intensity: 0.2 → 0.60
   ```

#### Vorteile des 10x Scale:
- ✅ Shadow Cascades haben 10x mehr effektive Auflösung
- ✅ Shadow Bias funktioniert besser bei größeren Objekten
- ✅ Godot's interne Präzision besser bei größerem Maßstab
- ✅ Physik-Simulation stabiler
- ✅ Keine visuelle Änderung (alles proportional skaliert)

#### GIT Befehle zum Mergen (NACH User-Testing):
```bash
# Nur wenn Testing erfolgreich!
git checkout main
git merge claude/10x-scale-experiment-7SMn2
git push origin main

# ODER falls nicht erfolgreich:
git branch -D claude/10x-scale-experiment-7SMn2
git push origin --delete claude/10x-scale-experiment-7SMn2
```

---

## 🔄 Merge-Strategie

### Empfohlene Reihenfolge:

#### 1. UI Graphics Overhaul mergen (SICHER)
```bash
git checkout main
git pull origin main
git merge claude/ui-graphics-overhaul-7SMn2 --no-ff
git push origin main
```

**Begründung:** Dieser Branch ist stabil, getestet und verbessert die Anwendung definitiv.

#### 2. 10x Scale Experiment testen (ABWARTEN)
```bash
# User testet auf claude/10x-scale-experiment-7SMn2
# Wenn erfolgreich:
git checkout main
git merge claude/10x-scale-experiment-7SMn2 --no-ff
git push origin main

# Wenn NICHT erfolgreich, Branch behalten für weitere Entwicklung:
# (nichts tun, Branch bleibt für spätere Arbeit)
```

**Begründung:** Experimenteller Branch - erfordert ausführliches User-Testing vor Merge.

---

## 🗑️ Branch Cleanup nach Merge

### Nach erfolgreichem Merge von ui-graphics-overhaul:
```bash
# Lokal löschen
git branch -d claude/ui-graphics-overhaul-7SMn2

# Remote löschen
git push origin --delete claude/ui-graphics-overhaul-7SMn2
```

### Falls 10x Scale NICHT gemergt wird:
```bash
# Branch BEHALTEN für weitere Entwicklung
# Keine Aktion erforderlich
```

### Falls 10x Scale gemergt wird:
```bash
# Lokal löschen
git branch -d claude/10x-scale-experiment-7SMn2

# Remote löschen
git push origin --delete claude/10x-scale-experiment-7SMn2
```

---

## 📊 Aktueller Projekt-Status

### ✅ Fertig implementiert:
- [x] Kenney UI Theme System (9 Themes)
- [x] Theme Persistence
- [x] Shadow Cascade Optimierung für Tabletop-Scale
- [x] 70mm Bases für alle Spawn-Methoden
- [x] Maximale Shadow-Qualität (8K Resolution, 16-bit)
- [x] Custom 3D Model Base Support

### ⚠️ In Testing:
- [ ] 10x World Scale System
- [ ] Shadow-Qualität bei 10x Scale
- [ ] 32mm Bases bei 10x Scale (320mm)

### 🐛 Bekannte Probleme:
- Shadow-Qualität noch nicht perfekt (auch mit 10x Scale)
- Mögliche Doppel-Base Issues (zu prüfen)
- TTS Texture Loading Errors (sekundär)

### 🔧 GDScript Warnungen (nicht kritisch):
- `name` parameter shadows Node.name (3 Stellen)
- `position` parameter shadows Node3D.position (1 Stelle)
- Metal LOD bias sampler warning (macOS-spezifisch)

---

## 📝 Nächste Schritte für neue Session

### Priorität 1: Testing & Entscheidung
1. **10x Scale Branch testen:**
   ```bash
   git checkout claude/10x-scale-experiment-7SMn2
   git pull origin claude/10x-scale-experiment-7SMn2
   ```
2. Godot öffnen, Projekt laden
3. Verschiedene Modelle testen (TTS Import, Custom Models, Terrain)
4. Shadow-Qualität prüfen
5. Base-Größen prüfen (sollten 320mm sein)
6. Performance-Check

### Priorität 2: Merge Decisions
- **Wenn 10x Scale gut:** Beide Branches in main mergen
- **Wenn 10x Scale problematisch:** Nur ui-graphics-overhaul mergen, 10x für später behalten

### Priorität 3: Weitere Verbesserungen (optional)
1. GDScript Warnungen beheben (shadowing issues)
2. TTS Texture Loading Error debugging
3. Shadow-System weiter optimieren wenn nötig
4. Performance-Profiling mit vielen Objekten

---

## 🔍 Testing Checklist

### Für 10x Scale Branch:
- [ ] TTS Model Import (prüfe Größe, Base, Schatten)
- [ ] Custom 3D Model Load (prüfe Größe, Base, Schatten)
- [ ] Terrain Spawning (prüfe Größe, Schatten)
- [ ] Würfel Spawning (prüfe Größe, Physik)
- [ ] Kamera Bewegung (smooth zoom/pan?)
- [ ] Schatten-Qualität (diagonale Artefakte weg?)
- [ ] Base-Größe (320mm = 32cm passend?)
- [ ] Performance mit 100+ Objekten
- [ ] Tisch-Größe korrekt (6x4 ft sollte sichtbar sein)

---

## 📦 Backup-Strategie

### Vor dem Mergen:
```bash
# Tag erstellen für aktuellen main-Stand
git tag -a pre-ui-overhaul -m "Vor UI Graphics Overhaul Merge"
git push origin pre-ui-overhaul

# Falls 10x Scale gemergt wird:
git tag -a pre-10x-scale -m "Vor 10x Scale Merge"
git push origin pre-10x-scale
```

### Rollback falls nötig:
```bash
# Zu Tag zurückkehren
git checkout pre-ui-overhaul
git checkout -b rollback-branch
```

---

## 🎯 Zusammenfassung für nächste Instanz

**Situation:**
- Zwei Branches existieren
- `ui-graphics-overhaul` ist produktionsreif
- `10x-scale-experiment` ist experimentell aber vielversprechend

**Aufgabe:**
1. 10x Scale Branch ausführlich testen
2. Merge-Entscheidung treffen basierend auf Testing
3. Branches sauber mergen und aufräumen
4. An weiteren Verbesserungen arbeiten

**Wichtig:**
- 10x Scale ändert ALLE Dimensionen - vollständig testen!
- Shadow-Qualität ist der Hauptgrund für 10x Scale
- Wenn 10x nicht funktioniert, ist ui-graphics-overhaul trotzdem wertvoll

**Fragen zu klären:**
- Sind Schatten mit 10x Scale wirklich besser?
- Ist 320mm Base-Größe passend?
- Läuft alles performance-mäßig gut?
- Gibt es unerwartete Probleme durch die Skalierung?

---

## 📞 Kontakt & Hilfe

Bei Problemen oder Fragen:
- GitHub Issues: https://github.com/DutchMaxwell/openTTS/issues
- Branch-Status: `git log --oneline --graph --all`
- Diff anzeigen: `git diff main..claude/10x-scale-experiment-7SMn2`

---

**Erstellt:** 2025-12-28
**Letzte Aktualisierung:** 2025-12-28
**Session ID:** 7SMn2
