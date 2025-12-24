# OpenTTS - Startup Menu Mockup
## Haupt-Menü Design Specification

**Status:** Design Mockup
**Version:** 1.0
**Erstellt:** 2025-12-24

---

## 🎬 ÜBERSICHT

Das Startup-Menü ist der erste Eindruck des Spiels. Es soll:
- **Episch** wirken (Battle-Atmosphäre)
- **Professionell** aussehen (keine Amateur-Vibes)
- **Schnell** sein (< 1s Ladezeit)
- **Intuitiv** bedienbar sein

---

## 📐 LAYOUT (1920x1080 Reference)

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                                                                           ┃
┃  [Animated 3D Background: Slow rotating battle scene with particles]     ┃
┃                                                                           ┃
┃                    ╔═══════════════════════════════╗                      ┃
┃                    ║                               ║                      ┃
┃                    ║   ░█▀█░█▀█░█▀▀░█▀█░▀█▀░▀█▀░█▀▀   ║                      ┃
┃                    ║   ░█░█░█▀▀░█▀▀░█░█░░█░░░█░░▀▀█   ║                      ┃
┃                    ║   ░▀▀▀░▀░░░▀▀▀░▀░▀░░▀░░░▀░░▀▀▀   ║                      ┃
┃                    ║          ━━━━━━━━━━━━━━━        ║                      ┃
┃                    ║      TACTICAL TABLETOP          ║                      ┃
┃                    ║         SIMULATOR               ║                      ┃
┃                    ║                                 ║                      ┃
┃                    ╚═══════════════════════════════╝                      ┃
┃                                                                           ┃
┃                    ┌───────────────────────────────┐                      ┃
┃                    │                               │                      ┃
┃                    │   ▶  QUICK BATTLE      [>]   │ ← Glow on hover      ┃
┃                    │                               │                      ┃
┃                    ├───────────────────────────────┤                      ┃
┃                    │   ⚔  MULTIPLAYER       [>]   │                      ┃
┃                    ├───────────────────────────────┤                      ┃
┃                    │   📋  ARMY BUILDER     [>]   │                      ┃
┃                    ├───────────────────────────────┤                      ┃
┃                    │   💾  LOAD GAME        [>]   │                      ┃
┃                    ├───────────────────────────────┤                      ┃
┃                    │   ⚙  SETTINGS          [>]   │                      ┃
┃                    ├───────────────────────────────┤                      ┃
┃                    │   ℹ  ABOUT / CREDITS   [>]   │                      ┃
┃                    ├───────────────────────────────┤                      ┃
┃                    │   ❌  EXIT                    │                      ┃
┃                    │                               │                      ┃
┃                    └───────────────────────────────┘                      ┃
┃                                                                           ┃
┃  [v0.2.0-alpha]              [🌐 Community] [💬 Discord] [❓ Help]        ┃
┃                                                                           ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

## 🎨 DETAILLIERTE KOMPONENTEN

### 1. Animated 3D Background

**Szene:**
```
- Langsam rotierende 3D-Schlacht-Szene (5 Min/Rotation)
- 5-10 Miniaturen in dramatischer Pose
- Subtile Partikel (Funken, Staub)
- Volumetrischer Nebel für Tiefe
- Farb-Grading: Desaturiert mit Cyan-Tint
```

**Technische Details:**
- **Rendering:** Separate SubViewport (reduzierte Auflösung 1280x720 → hochskaliert)
- **Performance:** < 10% GPU-Last
- **Blur:** Leichter Gaussian Blur für "cinematischen" Look
- **Layering:** Hinter allen UI-Elementen

**Godot Implementation:**
```gdscript
# In Startup Scene
var bg_viewport = SubViewport.new()
bg_viewport.size = Vector2(1280, 720)
bg_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

# 3D Scene
var bg_scene = preload("res://scenes/menu_background.tscn").instantiate()
bg_viewport.add_child(bg_scene)

# Slow rotation
var pivot = bg_scene.get_node("Pivot")
var tween = create_tween().set_loops()
tween.tween_property(pivot, "rotation:y", TAU, 300.0)
```

---

### 2. Logo / Title Card

**Design:**
```
┌─────────────────────────────────┐
│   ░█▀█░█▀█░█▀▀░█▀█░▀█▀░▀█▀░█▀▀   │  ← ASCII Art Style
│   ░█░█░█▀▀░█▀▀░█░█░░█░░░█░░▀▀█   │
│   ░▀▀▀░▀░░░▀▀▀░▀░▀░░▀░░░▀░░▀▀▀   │
│          ━━━━━━━━━━━━━━━        │  ← Animated line
│      TACTICAL TABLETOP          │  ← Subtitle
│         SIMULATOR               │
└─────────────────────────────────┘
```

**Styling:**
- **Font:** "Orbitron Black" (900 weight)
- **Size:** 72px für "OPENTTS"
- **Color:** White (#ffffff) mit Cyan-Glow
- **Glow:** `text-shadow: 0 0 20px #00d9ff, 0 0 40px #00d9ff`
- **Subtitle Font:** "Rajdhani Medium"
- **Subtitle Size:** 24px
- **Subtitle Color:** #8b92a8 (Neutral)

**Animation:**
```
Beim Start:
1. Logo faded ein mit Scale (0.8 → 1.0) + Opacity (0 → 1) - 0.8s
2. Animated Line "zeichnet" sich (0 → 100% width) - 0.5s delay
3. Subtitle faded ein - 1.0s delay
```

---

### 3. Main Menu Buttons

**Container:**
```
Width:               400px
Margin Top:          48px (from logo)
Background:          Glassmorphic Panel
  - GLASS_PANEL_BG: rgba(20, 25, 35, 0.85)
  - Backdrop-filter: blur(20px)
  - Border: 1px solid rgba(255, 255, 255, 0.1)
  - Border Radius: 16px
  - Box Shadow: 0 8px 32px rgba(0, 0, 0, 0.4)
Padding:             24px
```

**Einzelne Buttons:**
```
Layout:              Vertical Stack, 8px gap
Height:              56px each
Padding:             16px 24px
Background:          transparent (default)
Border:              1px solid rgba(255, 255, 255, 0.05)
Border Radius:       8px
Font:                "Inter Semibold" 16px
Text Color:          #ffffff
Alignment:           Left

Icon:
  - Position: Left, 24px from edge
  - Size: 24x24px
  - Color: ACCENT_PRIMARY (#00d9ff)

Arrow:
  - Position: Right, 24px from edge
  - Size: 16x16px
  - Color: rgba(255, 255, 255, 0.3)

HOVER:
  - Background: linear-gradient(90deg,
                  rgba(0, 217, 255, 0.1) 0%,
                  transparent 100%)
  - Border Color: rgba(0, 217, 255, 0.3)
  - Transform: translateX(4px)
  - Transition: 0.2s ease-out
  - Arrow Color: ACCENT_PRIMARY

ACTIVE (pressed):
  - Transform: scale(0.98)
  - Background: rgba(0, 217, 255, 0.15)
```

**Spezielle Button-Highlights:**

*QUICK BATTLE (primär):*
- Icon hat Glow-Puls-Animation
- Starker Hover-Glow

*EXIT (destruktiv):*
- Text Color: #ff3366 (DANGER)
- Hover Background: rgba(255, 51, 102, 0.1)

**Button-Liste Details:**

1. **▶ QUICK BATTLE** - Startet sofort ein Solo-Spiel
2. **⚔ MULTIPLAYER** - Öffnet Multiplayer-Lobby
3. **📋 ARMY BUILDER** - Öffnet Army Builder (Phase 2)
4. **💾 LOAD GAME** - Öffnet Load-Dialog
5. **⚙ SETTINGS** - Öffnet Settings-Menü
6. **ℹ ABOUT / CREDITS** - Info-Screen
7. **❌ EXIT** - Beendet das Spiel

---

### 4. Bottom Bar (Social Links)

**Layout:**
```
Position:            Fixed bottom, 24px padding
Width:               Full width
Display:             Flex, space-between
Alignment:           Left: Version | Right: Links
```

**Version Badge (links):**
```
Text:                "v0.2.0-alpha"
Font:                "JetBrains Mono Regular" 12px
Color:               rgba(255, 255, 255, 0.4)
Background:          rgba(255, 255, 255, 0.05)
Padding:             6px 12px
Border Radius:       4px
```

**Social Links (rechts):**
```
Display:             Flex, 16px gap
Buttons:
  - Size: 36x36px
  - Border Radius: 8px
  - Background: rgba(255, 255, 255, 0.05)
  - Icon: 20x20px, NEUTRAL color

  HOVER:
    - Background: rgba(0, 217, 255, 0.1)
    - Icon Color: ACCENT_PRIMARY
    - Transform: translateY(-2px)

Links:
  - 🌐 Community (Website/Forum)
  - 💬 Discord
  - ❓ Help/Tutorial
```

---

## ✨ ANIMATIONEN & TRANSITIONS

### Startup-Animation Sequence

**Gesamt-Dauer: ~2.5 Sekunden**

```
Timeline:
0.0s: ▶ Background faded ein (0.5s)
0.3s: ▶ Logo erscheint mit Scale-Pop (0.8s)
1.1s: ▶ Logo-Line zeichnet sich (0.5s)
1.3s: ▶ Subtitle faded ein (0.3s)
1.5s: ▶ Menu-Panel faded ein (0.4s)
1.6s: ▶ Buttons erscheinen gestaffelt (je 0.1s delay)
2.2s: ▶ Bottom-Bar faded ein (0.3s)
```

**Skip-Option:**
- Beliebige Taste → Springt zu 2.5s
- Wird nach erstem Start gespeichert → Beim nächsten Mal nur 0.5s fade-in

### Menu-Navigation Transition

**Beim Klick auf Button:**
```
1. Button: Glow-Pulse (0.2s)
2. Alle anderen Buttons: Fade-out (0.2s)
3. Logo: Scale-out + Fade-out (0.3s)
4. Background: Blur-Increase + Darken (0.3s)
5. Neue Page: Slide-in from right (0.4s, 0.1s delay)
```

**Zurück zum Hauptmenü:**
```
1. Current Page: Slide-out to right (0.3s)
2. Background: Blur-decrease + Lighten (0.3s)
3. Logo: Scale-in + Fade-in (0.3s, 0.1s delay)
4. Menu: Fade-in (0.3s, 0.2s delay)
```

---

## 🎵 AUDIO

### Sound Effects

**Startup:**
- Dramatischer Orchestral-Hit beim Logo-Erscheinen
- Subtiler "Whoosh" für Menu-Panel

**Navigation:**
- Button Hover: Leiser "Bleep" (Sci-Fi Style)
- Button Click: Kräftiger "Confirm" Sound
- Exit Button: Warnung-Ton (tiefer)

**Background Music:**
- Epische Orchestral-Loop (3-5 Min)
- Subtil, nicht aufdringlich
- Volume: 60% default, einstellbar
- Fade-in beim Start (3s)

---

## 📱 RESPONSIVE BEHAVIOR

### 1920x1080 (Standard)
- Wie im Mockup

### 2560x1440 (1440p)
- UI Scale: 1.2x
- Logo: 86px
- Menu Width: 480px

### 3840x2160 (4K)
- UI Scale: 1.5x
- Logo: 108px
- Menu Width: 600px

### Smaller (< 1920)
- UI Scale: Proportional (min 0.8x)
- Menu kann schmaler werden (min 320px)
- Bottom-Bar Icons kleiner

---

## 🎮 KEYBOARD NAVIGATION

```
UP/DOWN:             Navigate menu items
ENTER:               Select
ESC:                 Exit/Back (mit Confirmation)
1-7:                 Direct shortcuts (1 = Quick Battle, etc.)
F11:                 Fullscreen toggle
```

**Visual Feedback:**
- Fokussierter Button hat animated Border (glow-pulse)
- Keyboard-Navigation Hint (klein, bottom): "Use ↑↓ Enter to navigate"

---

## 🔧 IMPLEMENTATION NOTES

### Godot Scene Structure
```
StartupMenu (Control)
├── BackgroundLayer (SubViewportContainer)
│   └── BackgroundViewport
│       └── BattleScene (Node3D)
├── OverlayLayer (Control)
│   ├── LogoContainer (VBoxContainer)
│   │   ├── LogoLabel (Label)
│   │   ├── AnimatedLine (ColorRect)
│   │   └── SubtitleLabel (Label)
│   ├── MenuPanel (PanelContainer)
│   │   └── MenuButtons (VBoxContainer)
│   │       ├── QuickBattleBtn (Button)
│   │       ├── MultiplayerBtn (Button)
│   │       ├── ArmyBuilderBtn (Button)
│   │       ├── LoadGameBtn (Button)
│   │       ├── SettingsBtn (Button)
│   │       ├── AboutBtn (Button)
│   │       └── ExitBtn (Button)
│   └── BottomBar (HBoxContainer)
│       ├── VersionLabel (Label)
│       └── SocialLinks (HBoxContainer)
└── AudioManager (Node)
    ├── BGM_Player (AudioStreamPlayer)
    └── SFX_Player (AudioStreamPlayer)
```

### Custom Theme
```gdscript
# In theme.tres
var theme = Theme.new()

# Button Style
var button_style = StyleBoxFlat.new()
button_style.bg_color = Color(0, 0, 0, 0)  # Transparent
button_style.border_color = Color(1, 1, 1, 0.05)
button_style.border_width_all = 1
button_style.corner_radius_all = 8
button_style.content_margin_left = 24
# ... etc
```

---

## 🎯 USER FLOW

```
Start Game
    ↓
[Logo Animation]
    ↓
Main Menu
    ├─→ Quick Battle → Game Setup → Load Game
    ├─→ Multiplayer → Lobby → Join/Host → Load Game
    ├─→ Army Builder → (Future)
    ├─→ Load Game → File Browser → Load Game
    ├─→ Settings → Settings Screen ←─┐
    ├─→ About → Info Screen           │
    └─→ Exit → Confirmation Dialog ───┘
```

---

## 📊 PERFORMANCE TARGETS

- **Load Time:** < 1 second
- **FPS:** 60+ (vsync) mit Animation
- **Memory:** < 200MB für Startup-Scene
- **GPU:** < 15% auf GTX 1660

---

## 🎨 VISUAL REFERENCES

### Inspiration Gallery
1. **Halo Infinite Menu** - Glassmorphic Panels, 3D Background
2. **Destiny 2 Tower** - Cinematic Background mit UI-Overlay
3. **Call of Duty Warzone Menu** - Clean, Tactical Feel
4. **Apex Legends Lobby** - Character Display, Modern UI

---

**Status:** Ready for Implementation
**Priority:** HIGH
**Estimated Dev Time:** 2-3 days
**Dependencies:** UI_DESIGN_SYSTEM.md, Custom Fonts, Audio Assets
