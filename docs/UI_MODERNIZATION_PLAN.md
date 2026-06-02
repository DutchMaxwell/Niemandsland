# UI/UX Modernisierungsplan - OpenTTS

## Executive Summary

Das aktuelle UI nutzt **Kenney UI Assets** (Fantasy/SciFi Texturen), die zwar funktional sind, aber einen veralteten "2010er Game-UI" Look haben. Ziel ist ein **modernes, elegantes Design** im Stil von Premium-Apps wie Discord, Steam, oder Tabletop Simulator.

---

## 1. Analyse: Aktueller Zustand

### Probleme des aktuellen Designs

| Problem | Beschreibung |
|---------|-------------|
| **Texture-basierte Buttons** | Kenney-Buttons mit Bevel/Relief wirken altmodisch |
| **Inkonsistente Styling-Strategie** | Mix aus Theme-Generator und inline Overrides |
| **Fehlende visuelle Tiefe** | Keine modernen Effekte (Blur, Glassmorphism) |
| **Standard Godot Font** | Keine premium-wirkende Typografie |
| **Emojis als Icons** | Unicode-Emojis statt echte Icon-Sets |
| **Keine Mikro-Animationen** | Buttons/Panels haben keine Hover/Press-Animationen |

### Was funktioniert gut
- Farbschema-Wechsel (9 Themes)
- Responsive Layout mit Containern
- Radial-Menü ist innovativ
- Startup-Menü hat gutes Grund-Layout

---

## 2. Design-Richtung: "Dark Glassmorphism"

### Inspirationen
- **Discord** - Clean dark UI mit subtilen Hover-Effekten
- **Steam Big Picture** - Gaming-fokussiert aber modern
- **Figma** - Professionelle, minimalistisch
- **Valorant UI** - Glassmorphism im Gaming-Kontext

### Design-Prinzipien

```
┌─────────────────────────────────────────────────────────────┐
│  DARK GLASSMORPHISM DESIGN SYSTEM                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─ Background Layer ──────────────────────────────────┐   │
│  │  Dunkler Gradient mit subtilen Farbakzenten         │   │
│  │  (Deep Purple → Dark Blue → Black)                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─ Glass Panels ──────────────────────────────────────┐   │
│  │  Semi-transparent (15-25% opacity)                  │   │
│  │  Background Blur (8-16px)                           │   │
│  │  Subtle border (1px, 10% white)                     │   │
│  │  Soft shadow                                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─ Interactive Elements ──────────────────────────────┐   │
│  │  Hover: Glow + Scale (1.02)                         │   │
│  │  Press: Darken + Scale (0.98)                       │   │
│  │  Transitions: 150-200ms ease-out                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Farbpalette

### Primäre Dark Theme Palette

```gdscript
# Hintergründe
const BG_DARKEST = Color(0.06, 0.06, 0.10, 1.0)    # #0F0F1A - Tiefster Hintergrund
const BG_DARK = Color(0.09, 0.09, 0.14, 1.0)       # #171724 - Panels
const BG_MEDIUM = Color(0.12, 0.12, 0.18, 1.0)    # #1E1E2E - Erhöhte Elemente
const BG_LIGHT = Color(0.16, 0.16, 0.22, 1.0)     # #292938 - Hover-States

# Glass-Effekte
const GLASS_BG = Color(0.12, 0.12, 0.18, 0.7)     # Semi-transparent
const GLASS_BORDER = Color(1.0, 1.0, 1.0, 0.08)   # Subtle border
const GLASS_HIGHLIGHT = Color(1.0, 1.0, 1.0, 0.05) # Top highlight

# Akzentfarben
const ACCENT_PRIMARY = Color(0.35, 0.68, 1.0, 1.0)   # #5AADFF - Blau
const ACCENT_SUCCESS = Color(0.30, 0.85, 0.55, 1.0)  # #4DD98C - Grün
const ACCENT_WARNING = Color(1.0, 0.75, 0.30, 1.0)   # #FFBF4D - Orange
const ACCENT_DANGER = Color(1.0, 0.35, 0.45, 1.0)    # #FF5973 - Rot

# Text
const TEXT_PRIMARY = Color(0.95, 0.95, 0.97, 1.0)    # Fast weiß
const TEXT_SECONDARY = Color(0.65, 0.65, 0.72, 1.0)  # Gedimmt
const TEXT_MUTED = Color(0.45, 0.45, 0.52, 1.0)      # Sehr gedimmt
```

---

## 4. Komponenten-Design

### 4.1 Buttons

**Aktuell:** Texture-basierte Kenney Buttons mit Bevel
**Neu:** Flat/Gradient Buttons mit Glow-Effekten

```
┌────────────────────────────────────────┐
│  BUTTON STYLES                         │
├────────────────────────────────────────┤
│                                        │
│  [  PRIMARY BUTTON  ]  ← Gradient fill │
│   Accent color, subtle glow on hover   │
│                                        │
│  [  SECONDARY BUTTON  ]  ← Ghost style │
│   Border only, fill on hover           │
│                                        │
│  [  GHOST BUTTON  ]  ← Text only       │
│   No border, underline on hover        │
│                                        │
│  [  DANGER BUTTON  ]  ← Red variant    │
│   For destructive actions              │
│                                        │
└────────────────────────────────────────┘
```

### 4.2 Panels

**Aktuell:** Texture-basierte Panels mit Schrauben/Rahmen
**Neu:** Glassmorphism Panels mit Blur

```gdscript
# Modern Glass Panel Style
var glass_panel = StyleBoxFlat.new()
glass_panel.bg_color = Color(0.12, 0.12, 0.18, 0.75)
glass_panel.border_width_all = 1
glass_panel.border_color = Color(1, 1, 1, 0.08)
glass_panel.corner_radius_all = 12
glass_panel.shadow_size = 16
glass_panel.shadow_color = Color(0, 0, 0, 0.25)
glass_panel.shadow_offset = Vector2(0, 4)
```

### 4.3 Input Fields

```
┌─────────────────────────────────────────────────────┐
│  INPUT FIELD STATES                                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ Placeholder text...                    │ 🔍 │   │
│  └─────────────────────────────────────────────┘   │
│  Normal: Dark bg, subtle border                    │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ User input here                        │ 🔍 │   │
│  └─────────────────────────────────────────────┘   │
│  Focus: Accent border glow                         │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 5. Typografie

### Font-Empfehlungen (Open Source)

| Font | Verwendung | Lizenz |
|------|------------|--------|
| **Inter** | UI Text, Buttons, Labels | OFL |
| **JetBrains Mono** | Monospace, Stats, Zahlen | OFL |
| **Orbitron** | Headlines, Logo (Sci-Fi Stil) | OFL |

### Font-Hierarchie

```
Logo/Title:     Orbitron Bold, 48-64px
Heading 1:      Inter Bold, 24px
Heading 2:      Inter SemiBold, 18px
Body:           Inter Regular, 14px
Caption:        Inter Regular, 12px
Button:         Inter Medium, 14px (UPPERCASE optional)
Monospace:      JetBrains Mono, 13px
```

---

## 6. Icons

### Empfohlene Icon-Sets (Open Source)

1. **Lucide Icons** (https://lucide.dev)
   - MIT Lizenz
   - 1400+ Icons
   - Konsistenter Stil
   - SVG Format

2. **Phosphor Icons** (https://phosphoricons.com)
   - MIT Lizenz
   - 6000+ Icons
   - Mehrere Gewichte (thin, light, regular, bold, fill)

3. **Tabler Icons** (https://tabler.io/icons)
   - MIT Lizenz
   - 4500+ Icons
   - Stroke-basiert

### Icon-Konvertierung für Godot
```bash
# SVG zu PNG konvertieren (für Godot Textures)
# Empfohlene Größen: 16x16, 24x24, 32x32, 48x48
```

---

## 7. Implementierungsplan

### Phase 1: Foundation (Priorität: HOCH) — ✅ IMPLEMENTIERT

> **Status: umgesetzt und live.** Das Theme-System existiert als
> `scripts/glassmorphism_theme.gd` (Haupt-Theme-Generator: `_create_glass_style()`
> + StyleBoxFlat für Buttons/Panels/Labels/Inputs), wird über den
> `ThemeManager`-Autoload bereitgestellt und auf HUD, Startmenü, Dialoge und
> Panels angewandt (`main.gd`, `startup_menu.gd`, `lighting_panel.gd`).

#### 1.1 Theme-System
- [x] Haupt-Theme-Generator (`glassmorphism_theme.gd`) + `ThemeManager`-Autoload.
- [ ] *Optional/später:* Aufspaltung in `color_palette.gd` / `typography.gd` /
      `ui_animations.gd` (derzeit monolithisch, aber funktional vollständig).

#### 1.2 Fonts
- [x] **Inter** eingebunden (+ OFL-Lizenz beigelegt).
- [x] Monospace: **Source Code Pro** (statt JetBrains Mono; ebenfalls OFL).
- [x] Font-Setup inkl. MSDF + Mipmaps in `project.godot`.

#### 1.3 StyleBox-Definitionen
- [x] `StyleBoxFlat` für alle Komponenten (via `_create_glass_style`).
- [x] Konsistente Radien, Schatten, Borders.

### Phase 2: Core Components (Priorität: HOCH)

#### 2.1 Button-Komponente
```gdscript
# Neue Button-Klasse mit Animationen
class_name ModernButton extends Button

func _ready():
    mouse_entered.connect(_on_hover_start)
    mouse_exited.connect(_on_hover_end)

func _on_hover_start():
    var tween = create_tween()
    tween.tween_property(self, "scale", Vector2(1.02, 1.02), 0.15)
```

#### 2.2 Panel-Komponente mit Blur (Optional)
```gdscript
# Glass Panel mit BackBufferCopy für Blur
class_name GlassPanel extends PanelContainer

@export var blur_amount: float = 8.0
```

#### 2.3 Input-Komponenten
- [ ] Styled LineEdit
- [ ] Styled SpinBox
- [ ] Styled OptionButton/Dropdown

### Phase 3: Screen Redesigns (Priorität: MITTEL)

#### 3.1 Startup Menu Redesign
```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│                     ╔═══════════════════╗                   │
│                     ║     OPENTTS       ║                   │
│                     ║  ═══════════════  ║                   │
│                     ║  Tactical Tabletop║                   │
│                     ╚═══════════════════╝                   │
│                                                              │
│              ┌────────────────────────────┐                  │
│              │  ▶  START NEW BATTLE      │                  │
│              ├────────────────────────────┤                  │
│              │  💾 LOAD BATTLE           │                  │
│              ├────────────────────────────┤                  │
│              │  ❌  EXIT GAME            │                  │
│              └────────────────────────────┘                  │
│                                                              │
│  v0.3.0                              🌐  💬  ❓             │
└──────────────────────────────────────────────────────────────┘
```

#### 3.2 Main HUD Redesign
- Sidebar mit Glass-Effekt
- Floating Action Buttons
- Verbesserte Info-Tooltips

#### 3.3 Dialoge modernisieren
- Alle Popup-Dialoge
- File-Dialoge (soweit anpassbar)
- Settings-Fenster

### Phase 4: Polish & Effects (Priorität: NIEDRIG)

#### 4.1 Animationen
- [ ] Button hover/press Tweens
- [ ] Panel fade-in/slide-in
- [ ] Menu Transitionen

#### 4.2 Blur-Shader (Optional)
```glsl
// Gaussian Blur für Glass-Effekte
shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 2.0;

void fragment() {
    vec2 ps = SCREEN_PIXEL_SIZE * blur_amount;
    vec4 col = vec4(0.0);
    // 9-tap Gaussian blur
    col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(-ps.x, -ps.y)) * 0.0625;
    // ... weitere Samples
    COLOR = col;
}
```

#### 4.3 Sound-Feedback
- [ ] Subtle UI-Sounds (hover, click)
- [ ] Godot AudioStreamPlayer für Feedback

---

## 8. Ressourcen & Links

### Fonts (Download)
- Inter: https://rsms.me/inter/
- JetBrains Mono: https://www.jetbrains.com/lp/mono/
- Orbitron: https://fonts.google.com/specimen/Orbitron

### Icons (Download)
- Lucide: https://lucide.dev/icons
- Phosphor: https://phosphoricons.com
- Tabler: https://tabler.io/icons

### Referenzen
- [Godot UI Best Practices](https://docs.godotengine.org/en/stable/tutorials/ui/index.html)
- [Godot Theme System](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html)
- [Blur Shader Example](https://github.com/ttencate/blur_godot4)
- [Godot Shaders Collection](https://godotshaders.com/shader-tag/blur/)
- [Game UI Database](https://www.gameuidatabase.com/)

### Design Inspiration
- [Dribbble - Board Game UI](https://dribbble.com/tags/board_game_ui)
- [Dark Glassmorphism Trend](https://medium.com/@frameboxx81/dark-mode-and-glass-morphism-the-hottest-ui-trends-in-2025-864211446b54)

---

## 9. Migrationsstrategien

### Option A: Kompletter Rewrite (Empfohlen)
- Neues Theme-System von Grund auf
- Alle Scenes aktualisieren
- Kenney Assets entfernen
- **Aufwand:** Hoch, aber sauberes Ergebnis

### Option B: Inkrementelle Migration
- Neues Theme parallel zum alten
- Screen für Screen migrieren
- Kenney als Fallback behalten
- **Aufwand:** Mittel, aber potentiell inkonsistent

### Option C: Minimal Refresh
- Nur Farben und Fonts ändern
- Kenney Texturen behalten
- Kleine Anpassungen
- **Aufwand:** Niedrig, aber limitiertes Ergebnis

---

## 10. Nächste Schritte

1. **Entscheidung:** Welche Migrationsstrategie?
2. **Fonts:** Inter + JetBrains Mono herunterladen und integrieren
3. **Prototyp:** Startup-Menü als erstes mit neuem Design
4. **Icon-Set:** Lucide Icons als SVG/PNG importieren
5. **Iterieren:** User-Feedback einholen und anpassen

---

*Erstellt: Januar 2026*
*Status: ENTWURF - Bereit für Review*
