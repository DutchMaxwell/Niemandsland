# OpenTTS - In-Game HUD Mockup
## Spieloberfläche Design Specification

**Status:** Design Mockup
**Version:** 1.0
**Erstellt:** 2025-12-24

---

## 🎯 DESIGN-ZIELE

Das In-Game HUD soll:
- **Minimal** sein - maximale Sicht auf das Spielfeld
- **Kontextual** reagieren - nur relevante Info anzeigen
- **Glassmorphic** wirken - futuristisch aber nicht ablenkend
- **Schnell** zugänglich sein - wichtige Aktionen mit 1-2 Klicks

---

## 📐 LAYOUT (1920x1080 Reference)

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ ⚔ BATTLE  [◐ Round 3/5]  CP: 12  [⏱ 15:30]          [FPS: 60]  ⚙  ≡   ┃ ← Top Bar
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                                                                           ┃
┃  ┌────────┐                                                               ┃
┃  │ ▓▓▓░░  │                                                               ┃
┃  │ ░░▓▓▓  │◁ Minimap                                                      ┃
┃  │ ▓░░░▓  │  (Toggle)                                                     ┃
┃  └────────┘                                                               ┃
┃                                                                           ┃
┃                         🎮 3D VIEWPORT                                    ┃
┃                     [Spielfeld-Kamera]                                    ┃
┃                                                                           ┃
┃                                                                           ┃
┃                     ┌─────────────────────┐  ◁ Selected Unit Info        ┃
┃                     │ 🛡 TANK SQUADRON    │    (nur wenn selektiert)     ┃
┃                     │ HP: ████████░░ 8/10 │                              ┃
┃                     │ Move: 8"  Range: 24"│                              ┃
┃                     └─────────────────────┘                              ┃
┃                                                                           ┃
┣━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━┫
┃                   │                                     │              ┃
┃  UNITS [▼]        │      QUICK ACTIONS                  │   PHASES     ┃
┃  ┌──────────────┐ │                                     │   [▼]        ┃
┃  │ ● Tank x3    │ │  [📏 Measure] [🎲 Roll Dice]       │              ┃
┃  │ ○ Infantry   │ │  [⚡ Quick Move] [🎯 Template]      │  1. Movement ┃
┃  │ ○ Hero       │ │                                     │  2. Shooting ┃
┃  │ ○ Support    │ │  Selection: 1 unit                  │→ 3. Assault  ┃
┃  └──────────────┘ │  Distance: 12.5"                    │  4. End      ┃
┃                   │                                     │              ┃
┗━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━┛
```

---

## 🎨 KOMPONENTEN DETAILS

### 1. TOP BAR (Permanent, Glassmorphic)

**Layout:**
```
┌─────────────────────────────────────────────────────────────────────────┐
│ ⚔ BATTLE  [◐ Round 3/5]  CP: 12  [⏱ 15:30]      [FPS: 60]  ⚙  ≡       │
└─────────────────────────────────────────────────────────────────────────┘
```

**Styling:**
```
Height:              48px
Background:          rgba(10, 14, 23, 0.8) + blur(16px)
Border Bottom:       1px solid rgba(255, 255, 255, 0.1)
Padding:             0 24px
Display:             Flex, space-between
```

**Elemente (von links nach rechts):**

1. **Battle Icon + Title**
   ```
   Icon: ⚔ (24x24px, ACCENT_PRIMARY)
   Text: "BATTLE" (Rajdhani Bold 14px, #ffffff)
   ```

2. **Round Indicator**
   ```
   Icon: ◐ (20x20px, animated rotation 2s)
   Text: "Round 3/5" (Inter Medium 14px, NEUTRAL)
   Background: rgba(255, 255, 255, 0.05)
   Padding: 6px 12px
   Border Radius: 6px
   ```

3. **Command Points (CP)**
   ```
   Text: "CP: 12" (Inter Semibold 14px)
   Color: SUCCESS (#00ff88)
   Background: rgba(0, 255, 136, 0.1)
   Padding: 6px 12px
   Border Radius: 6px

   Animation: Pulse when CP changes
   ```

4. **Timer (Optional, für Timed Games)**
   ```
   Icon: ⏱ (20x20px)
   Text: "15:30" (JetBrains Mono 14px)
   Color: #ffffff (normal), WARNING (< 5 Min), DANGER (< 1 Min)
   Background: rgba(255, 255, 255, 0.05)
   Padding: 6px 12px
   Border Radius: 6px

   WARNING State: Pulse animation
   ```

5. **FPS Counter (Toggle in Settings)**
   ```
   Text: "FPS: 60" (JetBrains Mono 12px)
   Color: SUCCESS (>55), WARNING (30-55), DANGER (<30)
   ```

6. **Settings Button**
   ```
   Icon: ⚙ (24x24px)
   Background: transparent
   Hover: rgba(255, 255, 255, 0.1)
   Click: Öffnet Quick-Settings Dropdown
   ```

7. **Menu Button**
   ```
   Icon: ≡ (24x24px, Hamburger Menu)
   Background: transparent
   Hover: rgba(255, 255, 255, 0.1)
   Click: Öffnet Pause Menu
   ```

---

### 2. MINIMAP (Top-Left, Toggleable)

**Layout:**
```
┌─────────┐
│ ▓▓▓░░░  │
│ ░░▓▓▓░  │
│ ▓░░░▓░  │
│ ░▓▓░░▓  │
└─────────┘
```

**Styling:**
```
Size:                160x160px
Position:            Top-left, 16px margin
Background:          rgba(10, 14, 23, 0.9) + blur(12px)
Border:              1px solid rgba(255, 255, 255, 0.15)
Border Radius:       12px
Padding:             8px
```

**Minimap Details:**
```
Render:              2D Orthographic projection of table
Update:              Real-time (30fps)
Colors:
  - Table: #1f2937 (dark gray)
  - Player Units: ACCENT_PRIMARY (#00d9ff)
  - Enemy Units: DANGER (#ff3366)
  - Terrain: rgba(255, 255, 255, 0.3)
  - Camera View Cone: rgba(255, 255, 255, 0.2) outline

Interactions:
  - Click to pan camera
  - Scroll to zoom
  - Hover shows coordinates
  - Toggle: Press 'M' or click icon
```

**Toggle Button:**
```
Position:            Below minimap, same X
Size:                160x32px
Text:                "📍 MAP" / "📍 HIDE"
Font:                Inter Medium 12px
```

---

### 3. SELECTED UNIT INFO (Center-Bottom, Context-Aware)

**Nur sichtbar wenn Unit selektiert!**

```
┌────────────────────────────────┐
│ 🛡 TANK SQUADRON              │
│ HP: ████████░░ 8/10           │
│ Move: 8"  Range: 24"  AP: 2   │
│ [View Stats] [Orders ▼]       │
└────────────────────────────────┘
```

**Styling:**
```
Width:               400px
Position:            Center-bottom, 120px from bottom
Background:          GLASS_PANEL_LIGHT + blur(20px)
Border:              1px solid rgba(0, 217, 255, 0.3) ← Team-color
Border Radius:       12px
Padding:             16px
Box Shadow:          0 4px 16px rgba(0, 0, 0, 0.3)

Animation:
  - Slide-up from bottom (0.3s)
  - Fade-out when deselected (0.2s)
```

**Elemente:**

1. **Unit Name + Icon**
   ```
   Icon: Unit-Type Icon (32x32px, links)
   Name: "TANK SQUADRON" (Inter Semibold 16px, #ffffff)
   ```

2. **Health Bar**
   ```
   Width: 100%
   Height: 8px
   Background: rgba(255, 255, 255, 0.1)
   Fill: Gradient (SUCCESS → WARNING → DANGER based on %)
   Text: "8/10" (rechts, JetBrains Mono 12px)
   Border Radius: 4px

   Animation: Smooth fill transition (0.3s)
   Pulse when damaged (red glow)
   ```

3. **Stats Row**
   ```
   Display: Flex, space-between
   Font: Inter Medium 14px

   Move: "8\""  (Movement in inches)
   Range: "24\""  (Weapon range)
   AP: "2"  (Armor Piercing, etc.)

   Color: NEUTRAL (default), ACCENT_PRIMARY (when relevant)
   ```

4. **Action Buttons**
   ```
   [View Stats]: Opens detailed stat sheet
   [Orders ▼]: Dropdown for special orders

   Style: Ghost buttons (transparent, border on hover)
   Size: 32px height
   ```

---

### 4. BOTTOM PANEL (3-Section Layout)

**Layout:**
```
┌──────────┬────────────────────────────┬─────────────┐
│  UNITS   │     QUICK ACTIONS          │   PHASES    │
│  (Left)  │     (Center, wide)         │   (Right)   │
└──────────┴────────────────────────────┴─────────────┘
```

**Gesamtstyling:**
```
Height:              200px
Background:          GLASS_PANEL_BG + blur(20px)
Border Top:          1px solid rgba(255, 255, 255, 0.1)
Padding:             16px 24px

Visibility:
  - Default: Collapsed (nur 40px Tab-Bar sichtbar)
  - Expand: Klick auf Tab oder Hotkey (Tab-Taste)
  - Auto-hide: Nach 5s Inaktivität (Toggle in Settings)
```

---

#### 4A. UNITS PANEL (Left, 300px)

**Purpose:** Schneller Zugriff auf alle Units

```
┌───────────────────┐
│  UNITS [▼]        │
│  ┌──────────────┐ │
│  │ ● Tank x3    │ │ ← Selected
│  │ ○ Infantry   │ │
│  │ ○ Hero       │ │
│  │ ○ Support    │ │
│  │ ○ Artillery  │ │
│  └──────────────┘ │
│                   │
│  [+] Add Unit     │
└───────────────────┘
```

**Styling:**
```
Scrollable:          Yes (if > 8 units)
Max Height:          160px

Unit Item:
  - Height: 40px
  - Padding: 8px 12px
  - Background: transparent
  - Border Radius: 6px

  HOVER:
    - Background: rgba(255, 255, 255, 0.05)

  SELECTED:
    - Background: rgba(0, 217, 255, 0.15)
    - Border Left: 3px solid ACCENT_PRIMARY

  ACTIVATED (played this turn):
    - Checkmark icon ✓ (right)
    - Text Color: rgba(255, 255, 255, 0.5)
```

**Unit Item Details:**
```
● Tank x3          ← Indicator + Name + Count

Indicator:
  - ● (Filled): Not activated
  - ○ (Outline): Activated
  - ✕ (Red): Destroyed/Removed

Color: Team-color (Player = Cyan, Enemy = Red)
```

**Actions:**
```
Click: Select unit (camera pans to it)
Double-Click: Center camera on unit
Right-Click: Context menu (Delete, Duplicate, Lock, etc.)
```

---

#### 4B. QUICK ACTIONS PANEL (Center, flexible width)

**Purpose:** Häufigste Aktionen schnell zugänglich

```
┌─────────────────────────────────────────┐
│       QUICK ACTIONS                     │
│                                         │
│  [📏 Measure] [🎲 Roll Dice]           │
│  [⚡ Quick Move] [🎯 Template]         │
│                                         │
│  Selection: 1 unit                      │
│  Distance: 12.5" from objective         │
└─────────────────────────────────────────┘
```

**Action Buttons:**
```
Layout:              2x2 Grid, 12px gap
Button Size:         180x48px each
Background:          rgba(255, 255, 255, 0.05)
Border:              1px solid rgba(255, 255, 255, 0.1)
Border Radius:       8px
Font:                Inter Medium 14px

Icon:                24x24px, left aligned
Text:                Right of icon

HOVER:
  - Background: rgba(0, 217, 255, 0.1)
  - Border: 1px solid rgba(0, 217, 255, 0.3)
  - Transform: translateY(-2px)
  - Box Shadow: 0 4px 12px rgba(0, 217, 255, 0.2)

ACTIVE (Tool is active):
  - Background: rgba(0, 217, 255, 0.2)
  - Border: 2px solid ACCENT_PRIMARY
  - Pulsing glow
```

**Buttons:**
1. **📏 Measure** - Aktiviert Messwerkzeug
2. **🎲 Roll Dice** - Öffnet Dice Roller Panel
3. **⚡ Quick Move** - Bewegungsmodus (Snap to legal positions)
4. **🎯 Template** - Templates platzieren (Blast, Flame, etc.)

**Info Section (Below buttons):**
```
Font:                Inter Regular 12px
Color:               NEUTRAL

Dynamic Content:
  - "Selection: X units" oder "No selection"
  - "Distance: X.X\" from [target]" (wenn measuring)
  - "Phase: Movement" (current phase)
  - "Waiting for opponent..." (Multiplayer)
```

---

#### 4C. PHASES PANEL (Right, 250px)

**Purpose:** Spiel-Phasen Tracking

```
┌──────────────┐
│  PHASES [▼]  │
│              │
│  1. Movement │
│  2. Shooting │
│→ 3. Assault  │ ← Current
│  4. End      │
│              │
│ [Next Phase] │
└──────────────┘
```

**Styling:**
```
Phase Item:
  - Height: 36px
  - Padding: 8px 12px
  - Font: Inter Medium 14px

  COMPLETED:
    - Text Color: rgba(255, 255, 255, 0.4)
    - Checkmark ✓ (left)

  CURRENT:
    - Arrow → (left)
    - Text Color: ACCENT_PRIMARY
    - Background: rgba(0, 217, 255, 0.1)
    - Pulsing border (left, 3px)

  PENDING:
    - Text Color: rgba(255, 255, 255, 0.6)
```

**Next Phase Button:**
```
Width:               100%
Height:              44px
Margin Top:          12px
Background:          BUTTON_GRADIENT
Border Radius:       8px
Font:                Inter Semibold 14px
Text:                "Next Phase" oder "End Turn"

HOVER:
  - Transform: scale(1.05)
  - Box Shadow: 0 4px 16px rgba(0, 217, 255, 0.4)

When all phases done:
  - Text: "End Turn"
  - Icon: ➤ (animated)
```

---

## 🎮 RADIAL MENU (Context Menu)

**Trigger:** Rechtsklick auf Objekt

```
        [Rotate]
           │
    [Lock]─┼─[Delete]
           │
      [Duplicate]
```

**Styling:**
```
Size:                200x200px (circle)
Center:              Mouse position
Background:          radial-gradient(
                       rgba(10, 14, 23, 0.95) 0%,
                       rgba(10, 14, 23, 0.8) 100%
                     )
Backdrop Filter:     blur(16px)
Border:              2px solid rgba(255, 255, 255, 0.2)

Segments:            4-8 (depending on context)
Segment Hover:       Background: rgba(0, 217, 255, 0.2)

Animation:
  - Scale from 0 to 1 (0.2s, ease-out)
  - Rotate segments in (staggered)
```

---

## ✨ SPECIAL UI ELEMENTS

### 1. Measurement Line

**Wenn Measure-Tool aktiv:**
```
Visual:              Gestrichelte Linie (cyan, 2px)
Label:               Floating label at midpoint
                     "12.5\""
                     Background: rgba(10, 14, 23, 0.9)
                     Padding: 4px 8px
                     Border Radius: 4px
```

### 2. Selection Box (Box-Select)

```
Visual:              Dashed border (cyan, 2px)
Background:          rgba(0, 217, 255, 0.1)
```

### 3. Hover Highlight (Units)

```
Visual:              Rim glow around unit
Color:               ACCENT_PRIMARY
Intensity:           Pulsing (subtle)
```

### 4. Notification Toast

**Für wichtige Events:**
```
┌─────────────────────────────┐
│ ⚠ Enemy Unit Destroyed!    │
│ +50 VP                      │
└─────────────────────────────┘

Position:            Top-center, 80px from top
Width:               400px
Height:              Auto (min 60px)
Background:          GLASS_PANEL_BG
Border Left:         4px solid (SUCCESS/WARNING/DANGER)
Padding:             12px 16px
Font:                Inter Medium 14px

Animation:
  - Slide-down from top (0.3s)
  - Stay for 3s
  - Fade-out (0.5s)

Stack:               Max 3 visible, queue others
```

---

## 🎨 TRANSITIONS & ANIMATIONS

### Panel Expand/Collapse

**Bottom Panel:**
```
Collapsed:           40px height (only tabs visible)
Expanded:            200px height

Transition:          0.3s ease-out
Tab Icon:            Rotate 180° (▼ ↔ ▲)
```

### Unit Selection

```
Deselect Old:        Border fade-out (0.2s)
Select New:          Border scale-in + glow (0.3s)
Camera Pan:          Smooth lerp (1.0s, ease-in-out)
```

### Phase Change

```
Current Phase:       Pulse out (0.2s)
New Phase:           Pulse in + slide-right (0.3s)
Background:          Subtle color shift (0.5s)
```

---

## ⌨️ HOTKEYS

```
TAB:                 Toggle Bottom Panel
M:                   Toggle Minimap
SPACE:               Open Dice Roller
R:                   Activate Measure Tool
T:                   Activate Template Tool
1-9:                 Select Unit 1-9
F1:                  Toggle Help Overlay
F11:                 Toggle Fullscreen
ESC:                 Deselect / Cancel / Pause Menu
```

**Help Overlay (F1):**
- Semi-transparent overlay mit allen Hotkeys
- Glassmorphic panel, center-screen
- Close mit F1 oder ESC

---

## 📱 RESPONSIVE BEHAVIOR

### 1920x1080 (Standard)
- Wie im Mockup

### Higher Res (1440p, 4K)
- UI Scale proportional höher
- Bottom Panel kann breiter werden
- Mehr Units in Units Panel sichtbar

### Lower Res (< 1080p)
- Units Panel schmaler (240px)
- Quick Actions 2x2 Grid bleibt
- Phases Panel schmaler (200px)
- Font-Sizes minimal reduziert

---

## 🎯 ACCESSIBILITY

### Colorblind Modes
- Protanopia: Cyan → Yellow, Red → Blue
- Deuteranopia: Similar adjustments
- Tritanopia: Cyan → Magenta

### Screen Reader (Basic)
- Focus states klar definiert
- ARIA labels für wichtige Elemente

### High Contrast Mode
- Border widths erhöht (+1px)
- Transparency reduziert (×0.5)
- Shadows verstärkt

---

## 🔧 IMPLEMENTATION PRIORITY

**Phase 1 (MVP):**
1. Top Bar mit Round/CP
2. Bottom Panel (collapsed/expanded)
3. Selected Unit Info
4. Basic Radial Menu

**Phase 2:**
5. Minimap
6. Quick Actions
7. Phases Panel
8. Notification System

**Phase 3 (Polish):**
9. Animations
10. Transitions
11. Advanced Radial Menu
12. Accessibility features

---

**Status:** Ready for Implementation
**Dependencies:** UI_DESIGN_SYSTEM.md
**Estimated Dev Time:** 4-5 days
