# OpenTTS - Settings Menu Mockup
## Einstellungs-Menü Design Specification

**Status:** Design Mockup
**Version:** 1.0
**Erstellt:** 2025-12-24

---

## 🎯 ÜBERSICHT

Das Settings-Menü ist der zentrale Ort für:
- **Graphics/Display** - Auflösung, Rendering, Effekte
- **Audio** - Musik, SFX, Voice
- **Gameplay** - Keybinds, UI Scale, Accessibility
- **Network** - Multiplayer-Einstellungen

---

## 📐 LAYOUT (1920x1080)

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                          SETTINGS                                       ┃
┣━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃                 │                                                       ┃
┃  [🎨 Graphics]  │  ╔═══════════════════════════════════════════════╗   ┃
┃                 │  ║         GRAPHICS & DISPLAY                    ║   ┃
┃  [ Audio]       │  ╚═══════════════════════════════════════════════╝   ┃
┃                 │                                                       ┃
┃  [⌨ Gameplay]   │  Quality Preset:  [Ultra ▼]                          ┃
┃                 │                                                       ┃
┃  [🌐 Network]   │  Resolution:      [1920x1080 ▼]  [✓] Fullscreen     ┃
┃                 │                                                       ┃
┃  [ℹ About]      │  Rendering:       [Forward+ ▼]                       ┃
┃                 │                                                       ┃
┃                 │  ─────────────────────────────────────────────────   ┃
┃                 │                                                       ┃
┃                 │  🌟 Advanced Graphics                                 ┃
┃                 │                                                       ┃
┃                 │  Global Illumination (SDFGI):  [✓] Enabled           ┃
┃                 │  Screen Space Effects:         [✓] SSAO + SSIL       ┃
┃                 │  Reflections (SSR):            [✓] Enabled            ┃
┃                 │  Volumetric Fog:               [○] Disabled           ┃
┃                 │                                                       ┃
┃                 │  Shadow Quality:  [━━━━━━━━●─] Very High             ┃
┃                 │  Anti-Aliasing:   [MSAA 4x ▼]                        ┃
┃                 │  FSR Upscaling:   [━━━━●━━━━━] Balanced              ┃
┃                 │                                                       ┃
┃                 │  ─────────────────────────────────────────────────   ┃
┃                 │                                                       ┃
┃                 │  [Restore Defaults]            [Apply] [Cancel]       ┃
┃                 │                                                       ┃
┣━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃  [< Back]                                              [Save Changes]   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

## 🎨 KOMPONENTEN

### 1. Header

```
┌─────────────────────────────────────────────────────────────┐
│                       SETTINGS                              │
│          ━━━━━━━━━━━━━━━━━━━━━━━━                         │
└─────────────────────────────────────────────────────────────┘
```

**Styling:**
```
Height:              80px
Background:          GLASS_PANEL_BG
Border Bottom:       1px solid rgba(255, 255, 255, 0.1)
Padding:             24px

Title:
  Font: "Orbitron Bold" 32px
  Color: #ffffff
  Text Align: Center

Subtitle Line:
  Width: 200px
  Height: 2px
  Background: linear-gradient(90deg,
                transparent 0%,
                ACCENT_PRIMARY 50%,
                transparent 100%)
  Margin: 8px auto
```

---

### 2. Sidebar Navigation

**Layout:**
```
Width:               280px
Background:          rgba(10, 14, 23, 0.6)
Border Right:        1px solid rgba(255, 255, 255, 0.1)
Padding:             24px 16px
```

**Navigation Items:**
```
Height:              48px each
Margin Bottom:       8px
Padding:             12px 16px
Border Radius:       8px
Font:                Inter Medium 16px

Icon:                24x24px, left
Text:                Right of icon
Arrow:               > (right side, only for active)

NORMAL:
  Background:        transparent
  Text Color:        rgba(255, 255, 255, 0.7)
  Icon Color:        rgba(255, 255, 255, 0.5)

HOVER:
  Background:        rgba(255, 255, 255, 0.05)
  Text Color:        #ffffff
  Transform:         translateX(4px)

ACTIVE:
  Background:        linear-gradient(90deg,
                       rgba(0, 217, 255, 0.2) 0%,
                       rgba(0, 217, 255, 0.05) 100%)
  Border Left:       3px solid ACCENT_PRIMARY
  Text Color:        ACCENT_PRIMARY
  Icon Color:        ACCENT_PRIMARY
```

**Sidebar Items:**
1. 🎨 Graphics & Display
2. 🔊 Audio
3. ⌨️ Gameplay
4. 🌐 Network
5. ℹ️ About

---

### 3. Content Area (Graphics Tab)

#### Section: Quality Presets

```
┌─────────────────────────────────────────┐
│ Quality Preset:  [Ultra ▼]             │
│                                         │
│ ┌─────┬─────┬─────┬─────┬─────────┐   │
│ │Ultra│High │Med. │ Low │ Custom  │   │
│ └─────┴─────┴─────┴─────┴─────────┘   │
└─────────────────────────────────────────┘
```

**Preset Buttons:**
```
Layout:              Horizontal button group
Button Size:         100x80px each
Background:          rgba(255, 255, 255, 0.05)
Border:              1px solid rgba(255, 255, 255, 0.1)
Border Radius:       8px (outer: 12px for first/last)

Content:
  - Icon: Performance/Quality indicator
  - Title: "Ultra", "High", etc.
  - Subtitle: "4K, All Effects"

ACTIVE:
  - Background: linear-gradient(135deg,
                  rgba(0, 217, 255, 0.2) 0%,
                  rgba(123, 104, 238, 0.2) 100%)
  - Border: 2px solid ACCENT_PRIMARY
  - Box Shadow: 0 4px 16px rgba(0, 217, 255, 0.3)

HOVER (inactive):
  - Border: 1px solid rgba(0, 217, 255, 0.5)
  - Transform: translateY(-2px)
```

**Preset Specs Preview:**
```
Below buttons:
┌──────────────────────────────────────────────────┐
│ Resolution: 3840×2160 (4K Native)                │
│ Effects: SDFGI, SSAO, SSR, Volumetric Fog       │
│ Shadows: 4K, 4-Split                             │
│ Anti-Aliasing: MSAA 4x + TAA                     │
│ Target: 60 FPS on RTX 3070 / RX 6700 XT         │
└──────────────────────────────────────────────────┘

Font: Inter Regular 12px
Color: NEUTRAL
Background: rgba(255, 255, 255, 0.03)
Padding: 12px
Border Radius: 6px
```

---

#### Section: Display Settings

```
┌──────────────────────────────────────────┐
│ Resolution:    [1920x1080 ▼]            │
│ Display Mode:  [✓] Fullscreen           │
│                [○] Borderless Window    │
│                [○] Windowed              │
│                                          │
│ V-Sync:        [Adaptive ▼]             │
│ Frame Limit:   [━━━━━━━━●─] 144 FPS     │
└──────────────────────────────────────────┘
```

**Dropdown (Resolution):**
```
Width:               280px
Height:              40px
Background:          rgba(10, 14, 23, 0.8)
Border:              1px solid rgba(255, 255, 255, 0.1)
Border Radius:       8px
Padding:             10px 16px
Font:                Inter Medium 14px

Arrow:               ▼ (right, 16x16px)

Options (Common):
  - 3840×2160 (4K)
  - 2560×1440 (1440p)
  - 1920×1080 (1080p)
  - 1600×900
  - 1280×720 (720p)
  - Custom...

HOVER:
  Border: rgba(0, 217, 255, 0.5)

OPEN:
  Dropdown Panel:
    - Max Height: 300px
    - Scrollable
    - Background: rgba(10, 14, 23, 0.95) + blur(20px)
    - Each option: 40px height
    - Selected: ACCENT_PRIMARY background (20% opacity)
```

**Radio Buttons (Display Mode):**
```
Size:                20x20px circle
Border:              2px solid rgba(255, 255, 255, 0.3)
Background:          transparent

SELECTED:
  - Border: ACCENT_PRIMARY
  - Inner dot: 10x10px, ACCENT_PRIMARY
  - Glow: 0 0 8px rgba(0, 217, 255, 0.5)

Label:
  - Font: Inter Regular 14px
  - Color: #ffffff
  - Margin Left: 12px
```

---

#### Section: Advanced Graphics

```
┌─────────────────────────────────────────────────────┐
│ 🌟 Advanced Graphics                                │
│                                                     │
│ Global Illumination (SDFGI):  [✓] Enabled          │
│ ├─ Cascade Count:  [━━━●━━━━━] 4                   │
│ └─ Y-Scale:        [75% ▼]                         │
│                                                     │
│ Screen Space Effects:         [✓] SSAO + SSIL      │
│ ├─ Quality:        [High ▼]                        │
│ └─ Intensity:      [━━━━━●━━━] 0.8                 │
│                                                     │
│ Reflections (SSR):            [✓] Enabled           │
│ └─ Max Steps:      [━━━━━━●━━] 64                  │
│                                                     │
│ Volumetric Fog:               [○] Disabled          │
│   (⚠ Performance Impact: -20% FPS)                 │
│                                                     │
│ Shadow Quality:    [━━━━━━━━●─] Very High          │
│ ├─ Resolution:     [4096 ▼]                        │
│ ├─ Filter:         [PCF5 ▼]                        │
│ └─ Distance:       [━━━━━●━━━] 50m                 │
│                                                     │
│ Anti-Aliasing:     [MSAA 4x ▼]                     │
│                      + [✓] TAA (Temporal)          │
│                                                     │
│ FSR Upscaling:     [━━━━●━━━━━] Balanced           │
│ └─ Sharpness:      [━━━━━●━━━] 0.5                 │
└─────────────────────────────────────────────────────┘
```

**Expandable Section:**
```
Header:
  - Icon: 🌟 (24x24px, ACCENT_PRIMARY)
  - Title: "Advanced Graphics" (Inter Semibold 16px)
  - Toggle: ▼ / ▲ (right)

  Background: rgba(0, 217, 255, 0.05)
  Padding: 12px 16px
  Border Radius: 8px
  Cursor: pointer

  HOVER:
    Background: rgba(0, 217, 255, 0.1)

Content:
  - Padding: 16px
  - Background: rgba(255, 255, 255, 0.02)
  - Border Left: 2px solid rgba(0, 217, 255, 0.3)

  Animation: Slide-down (0.3s ease-out)
```

**Toggle Switch:**
```
Width:               48px
Height:              24px
Background:          rgba(255, 255, 255, 0.1) (OFF)
                     BUTTON_GRADIENT (ON)
Border Radius:       12px
Padding:             2px

Thumb:
  - Size: 20x20px
  - Background: #ffffff
  - Border Radius: 10px
  - Position: left (OFF), right (ON)
  - Transition: 0.2s ease-out

  HOVER:
    - Transform: scale(1.1)
```

**Slider:**
```
Width:               100%
Height:              40px total

Track:
  - Height: 4px
  - Background: rgba(255, 255, 255, 0.1)
  - Border Radius: 2px

Fill:
  - Background: BUTTON_GRADIENT
  - Border Radius: 2px

Thumb:
  - Size: 16x16px
  - Background: #ffffff
  - Border: 2px solid ACCENT_PRIMARY
  - Border Radius: 50%
  - Box Shadow: 0 2px 8px rgba(0, 0, 0, 0.3)

  HOVER:
    - Transform: scale(1.3)
    - Box Shadow: 0 0 12px rgba(0, 217, 255, 0.6)

Value Label:
  - Position: Right of slider
  - Font: JetBrains Mono 14px
  - Color: ACCENT_PRIMARY
  - Min Width: 60px
```

**Performance Warning:**
```
Icon:                ⚠ (16x16px, WARNING color)
Text:                "Performance Impact: -20% FPS"
Font:                Inter Regular 12px
Color:               WARNING (#ffaa00)
Background:          rgba(255, 170, 0, 0.1)
Padding:             4px 8px
Border Radius:       4px
Border Left:         2px solid WARNING
```

---

#### Section: Nested Options (Sub-Settings)

**Indentation für Abhängigkeiten:**
```
Parent Setting:
├─ Child Setting 1
├─ Child Setting 2
└─ Child Setting 3

Visual:
  - Indent: 24px
  - Connecting Line: 1px solid rgba(255, 255, 255, 0.1)
  - Font Size: -1px smaller than parent

Disabled wenn Parent OFF:
  - Opacity: 0.4
  - Cursor: not-allowed
  - Tooltip: "Enable [Parent] first"
```

---

### 4. Bottom Action Bar

```
┌────────────────────────────────────────────────────────┐
│ [< Back]                         [Save Changes]        │
└────────────────────────────────────────────────────────┘
```

**Styling:**
```
Height:              80px
Background:          GLASS_PANEL_BG
Border Top:          1px solid rgba(255, 255, 255, 0.1)
Padding:             0 24px
Display:             Flex, space-between
Align Items:         Center
```

**Buttons:**

*Back Button:*
```
Type:                Ghost Button
Width:               120px
Height:              44px
Icon:                < (left arrow)
Text:                "Back"
Font:                Inter Medium 14px

HOVER:
  Background:        rgba(255, 255, 255, 0.05)
```

*Save Changes Button:*
```
Type:                Primary Button
Width:               160px
Height:              44px
Background:          BUTTON_GRADIENT
Text:                "Save Changes"
Font:                Inter Semibold 14px

DISABLED (no changes):
  Opacity:           0.5
  Cursor:            not-allowed

HOVER:
  Transform:         scale(1.05)
  Box Shadow:        0 4px 16px rgba(0, 217, 255, 0.4)
```

---

## 🎵 AUDIO TAB

```
┌──────────────────────────────────────────┐
│ 🔊 AUDIO SETTINGS                        │
│                                          │
│ Master Volume:  [━━━━━━●━━] 70%         │
│                                          │
│ Music:          [━━━━━●━━━] 60%         │
│ Sound Effects:  [━━━━━━━●━] 80%         │
│ UI Sounds:      [━━━━●━━━━] 50%         │
│                                          │
│ [✓] Enable Menu Music                   │
│ [✓] Enable Battle Music                 │
│ [○] Mute When Unfocused                 │
│                                          │
│ ─────────────────────────────────────    │
│                                          │
│ 🎙️ Voice Chat (Multiplayer)             │
│                                          │
│ Input Device:   [Default Mic ▼]         │
│ Output Device:  [Default Speakers ▼]    │
│                                          │
│ Input Volume:   [━━━━━━●━━] 70%         │
│ [Test Microphone]                        │
└──────────────────────────────────────────┘
```

---

## ⌨️ GAMEPLAY TAB

```
┌──────────────────────────────────────────────┐
│ ⌨️ GAMEPLAY & CONTROLS                       │
│                                              │
│ UI Scale:         [━━━━━●━━━] 1.0x          │
│ Mouse Sensitivity:[━━━━━━●━━] 0.8           │
│                                              │
│ Camera:                                      │
│ ├─ Scroll Speed:  [━━━━━●━━━] 0.5           │
│ ├─ Zoom Speed:    [━━━━━━●━━] 0.7           │
│ └─ [✓] Invert Y-Axis                        │
│                                              │
│ ─────────────────────────────────────        │
│                                              │
│ 🎮 KEY BINDINGS                              │
│                                              │
│ ┌─────────────────────────┬─────────────┐   │
│ │ Action                  │ Key         │   │
│ ├─────────────────────────┼─────────────┤   │
│ │ Select/Drag             │ Left Click  │   │
│ │ Camera Rotate           │ Right Click │   │
│ │ Camera Pan              │ Middle Click│   │
│ │ Multi-Select            │ Alt + Click │   │
│ │ Measure                 │ R           │   │
│ │ Roll Dice               │ Space       │   │
│ │ Undo                    │ Ctrl+Z      │   │
│ │ Redo                    │ Ctrl+Y      │   │
│ └─────────────────────────┴─────────────┘   │
│                                              │
│ [Restore Defaults]                           │
│                                              │
│ ─────────────────────────────────────        │
│                                              │
│ ♿ ACCESSIBILITY                              │
│                                              │
│ Color Blind Mode: [None ▼]                  │
│ High Contrast:    [○] Disabled               │
│ Screen Reader:    [○] Disabled (Beta)        │
└──────────────────────────────────────────────┘
```

**Key Binding Table:**
```
Row Height:          40px
Font:                Inter Regular 14px
Border:              1px solid rgba(255, 255, 255, 0.05)

Columns:
  - Action: 60% width, left-aligned
  - Key: 40% width, right-aligned

Key Display:
  - Background: rgba(255, 255, 255, 0.1)
  - Padding: 6px 12px
  - Border Radius: 4px
  - Font: JetBrains Mono Medium 12px

HOVER (row):
  Background: rgba(255, 255, 255, 0.03)

CLICK (to rebind):
  - Modal appears: "Press any key..."
  - Listens for input
  - Validates (no conflicts)
  - Updates binding
```

---

## 🌐 NETWORK TAB

```
┌──────────────────────────────────────────┐
│ 🌐 NETWORK & MULTIPLAYER                 │
│                                          │
│ Player Name:   [DutchMaxwell___]         │
│                                          │
│ Default Port:  [7777_________]           │
│                                          │
│ Connection:                              │
│ ├─ Timeout:    [━━━━━●━━━] 30s          │
│ └─ [✓] Auto-Reconnect                   │
│                                          │
│ ─────────────────────────────────────    │
│                                          │
│ 🔒 PRIVACY                               │
│                                          │
│ [✓] Allow others to join my games       │
│ [○] Appear offline                      │
│ [✓] Share game stats                    │
│                                          │
│ ─────────────────────────────────────    │
│                                          │
│ 📊 NETWORK INFO                          │
│                                          │
│ Latency: 45ms  ●●●●○ Good               │
│ Packet Loss: 0.2%                        │
│ Connection: Stable                       │
│                                          │
│ [Run Network Test]                       │
└──────────────────────────────────────────┘
```

---

## ℹ️ ABOUT TAB

```
┌──────────────────────────────────────────┐
│ ℹ️ ABOUT OPENTTS                         │
│                                          │
│     ░█▀█░█▀█░█▀▀░█▀█░▀█▀░▀█▀░█▀▀         │
│     ░█░█░█▀▀░█▀▀░█░█░░█░░░█░░▀▀█         │
│     ░▀▀▀░▀░░░▀▀▀░▀░▀░░▀░░░▀░░▀▀▀         │
│                                          │
│ Version: v0.2.0-alpha                    │
│ Build: 2025-12-24 (7SMn2)                │
│                                          │
│ Open-Source Tabletop Simulator           │
│ für Wargaming                            │
│                                          │
│ ─────────────────────────────────────    │
│                                          │
│ 👥 CREDITS                               │
│                                          │
│ Lead Developer: DutchMaxwell             │
│ Engine: Godot 4.3                        │
│ License: MIT                             │
│                                          │
│ [View Full Credits]                      │
│ [Open Source Licenses]                   │
│                                          │
│ ─────────────────────────────────────    │
│                                          │
│ 🔗 LINKS                                 │
│                                          │
│ [🌐 Website] [💬 Discord]                │
│ [📖 Wiki] [🐛 Report Bug]                │
│ [❤️ Support Project]                    │
└──────────────────────────────────────────┘
```

---

## ✨ ANIMATIONS

### Tab Switch
```
Old Content:
  - Fade-out (0.2s)
  - Slide-left (0.2s, -50px)

New Content:
  - Fade-in (0.3s, delay 0.1s)
  - Slide-right (0.3s, from +50px)
```

### Setting Change
```
Toggle:
  - Thumb slide (0.2s ease-out)
  - Background color transition (0.3s)

Slider:
  - Smooth drag
  - Fill animates with value

Dropdown:
  - Scale-in from top (0.2s)
  - Each option fades in (staggered, 0.05s delay)
```

### Save Confirmation
```
Toast Notification:
  - Slide-in from top (0.3s)
  - "✓ Settings saved successfully!"
  - Auto-dismiss after 3s
```

---

## 🔔 CONFIRMATION DIALOGS

### Unsaved Changes Warning

```
┌──────────────────────────────────────┐
│ ⚠ UNSAVED CHANGES                   │
│                                      │
│ You have unsaved changes.            │
│ Do you want to save before leaving?  │
│                                      │
│ [Discard]  [Cancel]  [Save & Exit]  │
└──────────────────────────────────────┘

Modal:
  - Backdrop: rgba(0, 0, 0, 0.7) + blur(8px)
  - Size: 400x200px
  - Center screen
  - Scale-in animation (0.3s)
```

---

## 🎯 ACCESSIBILITY IN SETTINGS

### Keyboard Navigation
```
TAB:                 Next field
SHIFT+TAB:           Previous field
ARROW KEYS:          Adjust sliders
ENTER:               Toggle/Confirm
ESC:                 Close dropdown/Cancel
```

### Screen Reader Support
```
- All labels have ARIA descriptions
- Slider values announced on change
- Focus states clearly visible
- Logical tab order
```

---

## 🔧 IMPLEMENTATION NOTES

### Save System
```gdscript
# settings.cfg
[display]
resolution = "1920x1080"
fullscreen = true
vsync_mode = 1  # Adaptive

[graphics]
rendering_method = "forward_plus"
sdfgi_enabled = true
ssao_enabled = true
# ... etc

# Load on startup
func _load_settings():
    var config = ConfigFile.new()
    config.load("user://settings.cfg")
    # Apply settings...
```

### Performance Presets
```gdscript
const PRESETS = {
    "ultra": {
        "resolution": Vector2i(3840, 2160),
        "sdfgi": true,
        "ssao": true,
        "ssr": true,
        "volumetric_fog": true,
        "shadow_size": 4096,
        "msaa": 4,
        # ...
    },
    # ... other presets
}
```

---

**Status:** Ready for Implementation
**Priority:** HIGH (Graphics Tab), MEDIUM (Others)
**Estimated Dev Time:** 3-4 days
**Dependencies:** UI_DESIGN_SYSTEM.md
