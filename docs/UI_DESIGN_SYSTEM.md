# OpenTTS - UI Design System
## Visual Language & Design Tokens

**Design Philosophy:** Militärisch-Futuristisch mit Glassmorphism
**Inspiration:** Halo Infinite UI + Apple Vision Pro + Tactical Displays

---

## 🎨 COLOR PALETTE

### Primary Colors
```
BACKGROUND_DARK:     #0a0e17  // Tiefes Blauschwarz - Haupthintergrund
BACKGROUND_MEDIUM:   #141923  // Dunkelgrau-Blau - Panels
BACKGROUND_LIGHT:    #1f2937  // Helleres Grau - Hover States

ACCENT_PRIMARY:      #00d9ff  // Cyan - Hauptakzent, wichtige Aktionen
ACCENT_SECONDARY:    #7b68ee  // Medium Slate Blue - Sekundäre Highlights

SUCCESS:             #00ff88  // Neon-Grün - Erfolg, Ready States
WARNING:             #ffaa00  // Orange - Warnungen
DANGER:              #ff3366  // Pink-Rot - Fehler, Destructive Actions
NEUTRAL:             #8b92a8  // Grau-Blau - Deaktivierte Elemente
```

### Glassmorphism Colors
```
GLASS_PANEL_BG:      rgba(20, 25, 35, 0.85)  // Hauptpanels
GLASS_PANEL_LIGHT:   rgba(40, 48, 65, 0.75)  // Hellere Panels
GLASS_BORDER:        rgba(255, 255, 255, 0.1) // Subtile Borders
GLASS_GLOW:          rgba(0, 217, 255, 0.15)  // Glow-Effekt
```

### Gradient Presets
```
HEADER_GRADIENT:     linear-gradient(135deg, #141923 0%, #0a0e17 100%)
BUTTON_GRADIENT:     linear-gradient(135deg, #00d9ff 0%, #7b68ee 100%)
DANGER_GRADIENT:     linear-gradient(135deg, #ff3366 0%, #ff6b9d 100%)
```

---

## 📝 TYPOGRAPHY

### Font Families
```
PRIMARY_HEADING:     "Orbitron", sans-serif      // Futuristisch, für Titel
SECONDARY_HEADING:   "Rajdhani", sans-serif      // Semi-Futuristisch, für Subtitel
BODY_TEXT:           "Inter", sans-serif         // Lesbar, für Fließtext
MONO:                "JetBrains Mono", monospace // Für Stats, Code
```

### Font Sizes (in px)
```
DISPLAY_LARGE:       72px   // Haupttitel (Startup Screen)
DISPLAY_MEDIUM:      48px   // Sektions-Überschriften
HEADING_1:           32px   // Panel-Titel
HEADING_2:           24px   // Sub-Panel Titel
HEADING_3:           18px   // Kleine Überschriften
BODY_LARGE:          16px   // Standard UI-Text
BODY_MEDIUM:         14px   // Kleinerer Body-Text
BODY_SMALL:          12px   // Labels, Hinweise
CAPTION:             10px   // Timestamps, Meta-Info
```

### Font Weights
```
LIGHT:               300
REGULAR:             400
MEDIUM:              500
SEMIBOLD:            600
BOLD:                700
BLACK:               900    // Nur für DISPLAY
```

---

## 🔲 SPACING SYSTEM

### Base Unit: 8px
```
SPACE_XXS:           4px    // Sehr eng (innerhalb von Komponenten)
SPACE_XS:            8px    // Eng (zwischen verwandten Elementen)
SPACE_SM:            16px   // Standard (zwischen Elementen)
SPACE_MD:            24px   // Medium (zwischen Gruppen)
SPACE_LG:            32px   // Groß (zwischen Sektionen)
SPACE_XL:            48px   // Sehr groß (Hauptabstände)
SPACE_XXL:           64px   // Extra groß (Screen-Padding)
```

---

## 🎭 UI COMPONENTS

### 1. Buttons

#### Primary Button (Call-to-Action)
```
Background:          BUTTON_GRADIENT
Padding:             16px 32px
Border Radius:       8px
Border:              1px solid rgba(255, 255, 255, 0.2)
Font:                BODY_LARGE, SEMIBOLD
Text Color:          #ffffff
Shadow:              0 4px 12px rgba(0, 217, 255, 0.3)

HOVER:
  Transform:         scale(1.05)
  Shadow:            0 6px 20px rgba(0, 217, 255, 0.5)
  Transition:        0.2s ease-out

ACTIVE:
  Transform:         scale(0.98)

DISABLED:
  Background:        NEUTRAL
  Opacity:           0.5
  Cursor:            not-allowed
```

#### Secondary Button
```
Background:          transparent
Padding:             16px 32px
Border Radius:       8px
Border:              2px solid ACCENT_PRIMARY
Font:                BODY_LARGE, MEDIUM
Text Color:          ACCENT_PRIMARY

HOVER:
  Background:        rgba(0, 217, 255, 0.1)
  Border Color:      lighten(ACCENT_PRIMARY, 20%)
```

#### Ghost Button
```
Background:          transparent
Padding:             12px 24px
Font:                BODY_MEDIUM, REGULAR
Text Color:          NEUTRAL
Border:              none

HOVER:
  Text Color:        #ffffff
  Background:        rgba(255, 255, 255, 0.05)
```

### 2. Panels (Glassmorphic)

#### Main Panel
```
Background:          GLASS_PANEL_BG
Backdrop Filter:     blur(20px) saturate(150%)
Border:              1px solid GLASS_BORDER
Border Radius:       16px
Box Shadow:          0 8px 32px rgba(0, 0, 0, 0.4)
Padding:             SPACE_LG
```

#### Floating Panel (HUD Elements)
```
Background:          GLASS_PANEL_LIGHT
Backdrop Filter:     blur(16px) saturate(120%)
Border:              1px solid rgba(255, 255, 255, 0.15)
Border Radius:       12px
Box Shadow:          0 4px 16px rgba(0, 0, 0, 0.3)
Padding:             SPACE_MD
```

### 3. Input Fields

#### Text Input
```
Background:          rgba(10, 14, 23, 0.6)
Padding:             12px 16px
Border Radius:       8px
Border:              1px solid rgba(255, 255, 255, 0.1)
Font:                BODY_MEDIUM, REGULAR
Text Color:          #ffffff
Placeholder Color:   rgba(255, 255, 255, 0.4)

FOCUS:
  Border Color:      ACCENT_PRIMARY
  Box Shadow:        0 0 0 3px rgba(0, 217, 255, 0.2)
```

#### Slider
```
Track Height:        4px
Track Background:    rgba(255, 255, 255, 0.1)
Fill Background:     BUTTON_GRADIENT
Thumb Size:          16px
Thumb Background:    #ffffff
Thumb Shadow:        0 2px 8px rgba(0, 0, 0, 0.3)

HOVER (Thumb):
  Transform:         scale(1.2)
```

### 4. Progress Bars

#### Health/Status Bar
```
Height:              8px
Background:          rgba(255, 255, 255, 0.1)
Border Radius:       4px
Fill:                linear-gradient(90deg, SUCCESS 0%, #00cc77 100%)
Animation:           Smooth fill transition (0.3s ease-out)

DANGER (< 30%):
  Fill:              DANGER_GRADIENT
  Pulse Animation:   Subtle glow pulse (2s infinite)
```

### 5. Tooltips

```
Background:          rgba(10, 14, 23, 0.95)
Backdrop Filter:     blur(12px)
Padding:             8px 12px
Border Radius:       6px
Border:              1px solid rgba(255, 255, 255, 0.2)
Font:                BODY_SMALL, REGULAR
Text Color:          #ffffff
Arrow:               8px triangle, matching background

Animation:           Fade-in 0.15s, slight slide from direction
Max Width:           250px
```

### 6. Modals/Dialogs

```
Backdrop:            rgba(0, 0, 0, 0.7) + blur(8px)
Panel Background:    GLASS_PANEL_BG
Border:              1px solid rgba(255, 255, 255, 0.15)
Border Radius:       20px
Box Shadow:          0 20px 60px rgba(0, 0, 0, 0.6)
Padding:             SPACE_XL
Max Width:           600px

Animation:
  - Backdrop fade-in (0.2s)
  - Panel scale + fade (0.3s ease-out, slight overshoot)
```

---

## ✨ ANIMATIONS & TRANSITIONS

### Standard Timing Functions
```
EASE_OUT:            cubic-bezier(0.25, 0.46, 0.45, 0.94)
EASE_IN_OUT:         cubic-bezier(0.42, 0, 0.58, 1)
BOUNCE:              cubic-bezier(0.68, -0.55, 0.265, 1.55)
```

### Transition Durations
```
INSTANT:             0.1s   // Hover feedback
FAST:                0.2s   // Button clicks
NORMAL:              0.3s   // Panel transitions
SLOW:                0.5s   // Page transitions
CINEMATIC:           0.8s   // Dramatic effects
```

### Standard Animations

#### Fade In
```
From:  opacity: 0
To:    opacity: 1
Duration: 0.3s
Easing: EASE_OUT
```

#### Slide In From Right
```
From:  transform: translateX(100px), opacity: 0
To:    transform: translateX(0), opacity: 1
Duration: 0.3s
Easing: EASE_OUT
```

#### Scale Pop
```
From:  transform: scale(0.8), opacity: 0
To:    transform: scale(1), opacity: 1
Duration: 0.3s
Easing: BOUNCE
```

#### Glow Pulse (Looping)
```
0%:    box-shadow: 0 0 0 rgba(0, 217, 255, 0)
50%:   box-shadow: 0 0 20px rgba(0, 217, 255, 0.6)
100%:  box-shadow: 0 0 0 rgba(0, 217, 255, 0)
Duration: 2s
Easing: ease-in-out
Iteration: infinite
```

---

## 🎯 ICONS

### Style
- **Type:** Line icons (2px stroke)
- **Size Grid:** 16px, 24px, 32px, 48px
- **Color:** Inherit from parent or ACCENT_PRIMARY
- **Recommended Library:** Lucide Icons / Heroicons

### Common Icons
```
⚔  Battle/Combat
🎯 Target/Aim
📊 Stats
⚙  Settings
💾 Save
📂 Load
🌐 Network/Multiplayer
🎲 Dice
📏 Measure
👥 Team/Units
🏆 Victory
⏱  Timer
🔊 Audio
🎨 Graphics
```

---

## 📱 RESPONSIVE BREAKPOINTS

```
MOBILE:              < 768px   // Tablets (portrait)
TABLET:              768px - 1023px
DESKTOP:             1024px - 1919px
DESKTOP_LARGE:       1920px - 2559px
4K:                  >= 2560px
```

### Scaling Rules
- **UI Scale Factor:** Adjustable 0.8x - 1.5x
- **Minimum Text Size:** 12px (readable at 1080p from 50cm)
- **Touch Targets:** Minimum 44x44px für Touch-Devices

---

## 🎮 SPECIAL EFFECTS

### Glassmorphic Backdrop
```gdscript
# Godot Implementation Hint
var panel_material = StyleBoxFlat.new()
panel_material.bg_color = Color(0.078, 0.098, 0.137, 0.85)
panel_material.border_color = Color(1, 1, 1, 0.1)
panel_material.corner_radius_all = 16
panel_material.shadow_size = 8
panel_material.shadow_color = Color(0, 0, 0, 0.4)

# For blur: Use BackBufferCopy + shader
```

### Neon Glow Text
```
Text Shadow:
  0 0 10px ACCENT_PRIMARY,
  0 0 20px ACCENT_PRIMARY,
  0 0 30px ACCENT_PRIMARY
```

### Scan Line Effect (Retro-Futuristic)
```
Background:          linear-gradient(
                       0deg,
                       transparent 50%,
                       rgba(255, 255, 255, 0.02) 50%
                     )
Background Size:     100% 4px
Animation:           translateY 10s linear infinite
```

---

## 🎨 THEME VARIANTS

### Default (Dark)
- Background: BACKGROUND_DARK
- Accent: ACCENT_PRIMARY (Cyan)

### Alternative: "Crimson War"
- Background: #17090a (Dunkles Rot-Schwarz)
- Accent: #ff3366 (Pink-Rot)

### Alternative: "Emerald Command"
- Background: #0a1709 (Dunkles Grün-Schwarz)
- Accent: #00ff88 (Neon-Grün)

---

## 📐 GRID SYSTEM

```
Container Max Width: 1600px (centered)
Columns:            12
Gutter:             SPACE_MD (24px)
Margin:             SPACE_XL (48px) on desktop
                    SPACE_MD (24px) on mobile
```

---

**Version:** 1.0
**Last Updated:** 2025-12-24
**Status:** Mockup Phase
