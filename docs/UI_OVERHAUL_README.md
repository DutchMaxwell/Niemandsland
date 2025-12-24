# 🎨 OpenTTS - UI & Graphics Overhaul
## Design Mockups & Implementation Guide

**Projekt:** OpenTTS - Open-Source Wargaming Tabletop Simulator
**Status:** Design Phase - Awaiting Approval
**Version:** 1.0
**Erstellt:** 2025-12-24

---

## 📋 ÜBERSICHT

Dieses Verzeichnis enthält alle Design-Dokumente für den kompletten grafischen und UI-Overhaul von openTTS. Das Ziel ist es, das Spiel von einem funktionalen Prototyp in ein state-of-the-art Tabletop-Erlebnis zu verwandeln.

---

## 📁 DOKUMENTE

### 1. **UI_DESIGN_SYSTEM.md** 🎨
**Zweck:** Zentrale Design-Language Definition

**Inhalt:**
- ✅ Farbpalette (Dark Theme mit Cyan-Akzenten)
- ✅ Typografie (Orbitron, Inter, JetBrains Mono)
- ✅ Spacing-System (8px Grid)
- ✅ UI-Komponenten (Buttons, Panels, Inputs, etc.)
- ✅ Glassmorphism-Styling
- ✅ Animationen & Transitions
- ✅ Accessibility-Richtlinien

**Für wen:** Designer, Frontend-Entwickler

---

### 2. **MOCKUP_STARTUP_MENU.md** 🚀
**Zweck:** Haupt-Menü Design Specification

**Inhalt:**
- ✅ Animated 3D Background (rotierender Battle-Scene)
- ✅ Glassmorphic Menu-Panel
- ✅ Logo-Design mit ASCII-Art
- ✅ Button-Layout & Styling
- ✅ Startup-Animation Sequence (2.5s)
- ✅ Social Links & Version Badge
- ✅ Audio-Integration (BGM + SFX)

**Highlights:**
- Dramatischer erster Eindruck
- Cinematic Background
- Smooth Transitions
- < 1s Ladezeit

**Für wen:** UI-Implementierung, 3D-Artists

---

### 3. **MOCKUP_INGAME_HUD.md** 🎮
**Zweck:** In-Game Interface Design

**Inhalt:**
- ✅ Minimalistisches HUD-Layout
- ✅ Top-Bar (Round, CP, Timer, FPS)
- ✅ Minimap (toggleable, 2D projection)
- ✅ Selected Unit Info (context-aware)
- ✅ Bottom Panel (3-Section: Units, Actions, Phases)
- ✅ Radial Context Menu
- ✅ Measurement Tools
- ✅ Notification System

**Design-Prinzipien:**
- Maximal freie Sicht aufs Spielfeld
- Context-aware (nur relevante Info zeigen)
- Glassmorphic, nicht ablenkend
- Schneller Zugriff (1-2 Klicks)

**Für wen:** Gameplay-Programmer, UI-Developer

---

### 4. **MOCKUP_SETTINGS_MENU.md** ⚙️
**Zweck:** Settings-Menü mit Grafik-Optionen

**Inhalt:**
- ✅ Sidebar-Navigation (Graphics, Audio, Gameplay, Network, About)
- ✅ Graphics-Tab:
  - Quality Presets (Ultra, High, Medium, Low, Custom)
  - Resolution & Display Mode
  - Advanced Graphics (SDFGI, SSAO, SSR, etc.)
  - FSR Upscaling
- ✅ Audio-Tab (Volume, Voice Chat)
- ✅ Gameplay-Tab (Keybindings, Accessibility)
- ✅ Network-Tab (Multiplayer-Settings)
- ✅ About-Tab (Credits, Links)

**Features:**
- Visueller Preset-Selector
- Expandable Advanced Settings
- Performance-Warnungen
- Save/Discard/Restore Defaults

**Für wen:** Settings-Integration, Graphics-Programmer

---

### 5. **GRAPHICS_UPGRADE_PLAN.md** 🌟
**Zweck:** Technische Spezifikation für Rendering-Upgrade

**Inhalt:**
- ✅ Forward+ Rendering (vs. GL Compatibility)
- ✅ SDFGI (Global Illumination - "Quasi-Raytracing")
- ✅ VoxelGI (optional, für Detail-Bereiche)
- ✅ Screen-Space Effects (SSAO, SSIL, SSR)
- ✅ Volumetric Fog (optional)
- ✅ Shadow Quality (4K Shadows, Soft Shadows)
- ✅ Tonemapping & Color Grading (ACES)
- ✅ Glow & Bloom
- ✅ Anti-Aliasing (MSAA + TAA)
- ✅ AMD FSR (Upscaling)
- ✅ PBR Materials (Physically Based Rendering)
- ✅ Team-Color Shader
- ✅ Performance Presets (4 Stufen)

**Performance Targets:**
- Ultra: 60 FPS @ 4K (RTX 3080)
- High: 90 FPS @ 1440p (RTX 3060)
- Medium: 120 FPS @ 1080p (GTX 1660)
- Low: 144 FPS @ 1080p (GTX 960)

**Für wen:** Graphics-Programmer, Rendering-Engineer

---

## 🎯 DESIGN-PHILOSOPHIE

### Visual Language: **"Militärisch-Futuristisch mit Glassmorphism"**

**Inspirationen:**
- Halo Infinite (Glassmorphic UI)
- Destiny 2 (Cinematic Backgrounds)
- Call of Duty Warzone (Tactical Feel)
- Apple Vision Pro (Modern, Clean)

**Kern-Prinzipien:**
1. **Klarheit:** Keine visuellen Spielereien auf Kosten der Usability
2. **Konsistenz:** Einheitliche Komponenten-Library
3. **Performance:** Schön, aber nicht auf Kosten der FPS
4. **Accessibility:** Colorblind-Modi, High-Contrast, Screen-Reader

---

## 🎨 FARBSCHEMA (Quick Reference)

```
PRIMARY:
  Background:     #0a0e17  (Tiefes Blauschwarz)
  Panels:         rgba(20, 25, 35, 0.85) + blur
  Accent:         #00d9ff  (Cyan)

SEMANTIC:
  Success:        #00ff88  (Neon-Grün)
  Warning:        #ffaa00  (Orange)
  Danger:         #ff3366  (Pink-Rot)
  Neutral:        #8b92a8  (Grau-Blau)
```

---

## 📐 TYPOGRAFIE (Quick Reference)

```
HEADINGS:
  Display:        "Orbitron" Black 72px
  H1:             "Orbitron" Bold 32px
  H2/H3:          "Rajdhani" Bold 24px/18px

BODY:
  Primary:        "Inter" Regular 16px
  Secondary:      "Inter" Regular 14px

MONOSPACE:
  Stats/Code:     "JetBrains Mono" Regular 14px
```

---

## ✨ KEY FEATURES

### UI-Features:
- 🎬 **Animated 3D Menu Background** - Dramatisch & modern
- 🔮 **Glassmorphism** - Frosted Glass Panels mit Blur
- 🎯 **Context-Aware HUD** - Zeigt nur relevante Info
- 🗺️ **Live Minimap** - 2D-Projektion des Spielfelds
- 🎭 **Radial Context Menu** - Schneller Zugriff
- 📊 **Progressive Disclosure** - Komplexität nur wenn nötig
- ♿ **Accessibility** - Colorblind, High-Contrast, Screen-Reader

### Grafik-Features:
- 🌟 **SDFGI Global Illumination** - Quasi-Raytracing
- 💎 **PBR Materials** - Realistische Materialien
- 🌊 **Screen-Space Reflections** - Glänzende Oberflächen
- 🌫️ **Volumetric Fog** - Atmosphärischer Nebel (optional)
- 🎨 **ACES Tonemapping** - Filmischer Look
- ⚡ **AMD FSR** - +30-60% Performance via Upscaling
- 🎮 **4 Quality Presets** - Von Low (GTX 960) bis Ultra (RTX 4090)

---

## 🚀 IMPLEMENTIERUNGS-PLAN

### Phase 1: Foundation (Week 1)
- [ ] UI Design System implementieren
- [ ] Custom Theme für Godot erstellen
- [ ] Font-Integration
- [ ] Glassmorphic Shader

### Phase 2: Startup Menu (Week 1)
- [ ] 3D Background Scene
- [ ] Menu-Layout & Buttons
- [ ] Animations & Transitions
- [ ] Audio-Integration

### Phase 3: Graphics Upgrade (Week 2)
- [ ] Forward+ Rendering aktivieren
- [ ] SDFGI Setup
- [ ] Post-Processing Stack
- [ ] Material-Upgrades

### Phase 4: In-Game HUD (Week 2-3)
- [ ] Top Bar
- [ ] Minimap
- [ ] Bottom Panel (3 Sections)
- [ ] Radial Menu
- [ ] Notifications

### Phase 5: Settings Menu (Week 3)
- [ ] Settings-Layout
- [ ] Graphics-Tab mit Presets
- [ ] Audio/Gameplay/Network Tabs
- [ ] Save/Load System

### Phase 6: Polish & Optimization (Week 4)
- [ ] Performance-Profiling
- [ ] Preset-Balancing
- [ ] Bug-Fixes
- [ ] Documentation

**Total: ~4 Wochen Entwicklungszeit**

---

## 📊 VORHER/NACHHER VERGLEICH

### VORHER (v0.1)
```
UI:
  - Basic Labels & Buttons
  - Kein Theme, Standard Godot UI
  - Fest 1920x1080
  - Minimale Visual Feedback

Graphics:
  - GL Compatibility (OpenGL 3.3)
  - Kein GI, kein SSAO/SSR
  - MSAA 2x (Aliasing sichtbar)
  - Basic ProceduralSky
  - Flache Beleuchtung
```

### NACHHER (v0.2 - Geplant)
```
UI:
  - Glassmorphic Design System
  - Animated Startup Menu
  - Context-Aware HUD
  - Radial Menus
  - Smooth Transitions
  - Scalable (720p - 4K)

Graphics:
  - Forward+ Rendering (Vulkan)
  - SDFGI Global Illumination
  - SSAO + SSIL + SSR
  - MSAA 4x + TAA
  - Volumetric Fog (optional)
  - PBR Materials
  - ACES Tonemapping
  - FSR Upscaling
  - 4 Quality Presets
```

**Visual Impact:** 📈 +300% (geschätzt)
**Performance:** ➡️ Gleich oder besser (dank FSR)

---

## 🎮 INTERAKTIVES MOCKUP

### Startup Menu Flow
```
[Start Game]
     ↓
[Logo Animation] (0.8s)
     ↓
[Menu Fade-in] (0.4s)
     ↓
┌─────────────────────┐
│  QUICK BATTLE   [>] │ ← HOVER: Glow + Slide
│  MULTIPLAYER    [>] │
│  ARMY BUILDER   [>] │
│  LOAD GAME      [>] │
│  SETTINGS       [>] │ ← CLICK
│  ABOUT          [>] │
│  EXIT               │
└─────────────────────┘
     ↓
[Transition] (0.3s)
     ↓
[Settings Menu]
```

### In-Game HUD States
```
STATE 1: Idle (Kein Selection)
  - Top Bar: Visible
  - Minimap: Visible (toggleable)
  - Bottom Panel: Collapsed (40px)
  - Selected Info: Hidden

STATE 2: Unit Selected
  - Top Bar: Visible
  - Minimap: Visible
  - Bottom Panel: Expanded (200px)
  - Selected Info: Visible (Center-Bottom)
  - Unit in Units-List: Highlighted

STATE 3: Action Active (Measuring)
  - Measure Tool: Active (Line + Label)
  - Quick Actions: "Measure" button highlighted
  - Other UI: Dimmed (20% opacity)
```

---

## 🛠️ TECHNISCHE REQUIREMENTS

### Godot Version
- **Minimum:** Godot 4.3
- **Empfohlen:** Godot 4.3+
- **Rendering:** Forward+ (Vulkan/OpenGL 4.6)

### System Requirements (Nach Upgrade)

**Minimum (Low Preset):**
- GPU: GTX 960 / RX 560 (4GB VRAM)
- CPU: Intel i5-4460 / AMD FX-6300
- RAM: 8 GB
- Target: 144 FPS @ 1080p

**Empfohlen (Medium Preset):**
- GPU: GTX 1660 / RX 580 (6GB VRAM)
- CPU: Intel i5-8400 / AMD Ryzen 5 2600
- RAM: 16 GB
- Target: 120 FPS @ 1080p

**High-End (Ultra Preset):**
- GPU: RTX 3080 / RX 6800 XT (10GB VRAM)
- CPU: Intel i7-10700K / AMD Ryzen 7 5800X
- RAM: 32 GB
- Target: 60 FPS @ 4K

### Assets Benötigt
- [ ] Fonts: Orbitron, Rajdhani, Inter, JetBrains Mono
- [ ] Icons: Lucide Icons Library (MIT)
- [ ] Audio: Menu BGM (Orchestral, 3-5 Min Loop)
- [ ] Audio: UI SFX (Hover, Click, Confirm, Error)
- [ ] Textures: Felt/Wood Normal Maps für Tisch
- [ ] 3D Models: 5-10 Miniaturen für Menu-Background

---

## 📝 NEXT STEPS

### Für Design-Review:
1. ✅ **Review Design Docs** - Alle 5 Dokumente durchlesen
2. 🤔 **Feedback geben** - Was gefällt, was ändern?
3. 🎨 **Prioritäten setzen** - Was zuerst implementieren?
4. 🔀 **Änderungen anfordern** - Anpassungen gewünscht?

### Für Implementation:
1. ⏳ **Nach Approval:** Branch erstellen (`feature/ui-graphics-overhaul`)
2. ⏳ **Phase 1 starten:** UI Design System
3. ⏳ **Iterativ entwickeln:** Wöchentliche Builds
4. ⏳ **Testing & Feedback:** Community-Testing

---

## 💬 FEEDBACK & FRAGEN

**Bevorzugte Methode:**
- GitHub Issues: `[UI Design] Your feedback here`
- Discord: #design-feedback
- Direkt im PR: Inline-Kommentare

**Wichtige Fragen:**
1. Ist der Stil zu "futuristisch" für ein Tabletop-Simulator?
2. Soll die Farbpalette anpassbar sein (Themes)?
3. Ist SDFGI zu Performance-intensiv? (Alternative: Nur SSIL)
4. Sollen wir VR-Support einplanen? (Beeinflusst HUD-Design)

---

## 📚 RESSOURCEN

### Design Inspiration
- [Halo Infinite Menu](https://www.youtube.com/watch?v=...)
- [Glassmorphism Guide](https://ui.glass/generator/)
- [PBR Texture Guide](https://www.pbrtextures.com/)

### Godot Docs
- [Forward+ Rendering](https://docs.godotengine.org/en/stable/tutorials/3d/introduction_to_3d.html#forward)
- [SDFGI Tutorial](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html)
- [Custom Themes](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html)

### Assets
- [Google Fonts](https://fonts.google.com/) - Orbitron, Rajdhani
- [Lucide Icons](https://lucide.dev/) - MIT License Icons
- [ambientCG](https://ambientcg.com/) - Free PBR Textures

---

## 📄 LIZENZ

Alle Design-Dokumente in diesem Verzeichnis sind Teil von openTTS und unterliegen der MIT-Lizenz.

**Contributors:**
- Design Lead: Claude AI (Mockups)
- Project Lead: DutchMaxwell

---

**Version:** 1.0
**Status:** 📋 Awaiting Approval
**Last Updated:** 2025-12-24

---

## ⏭️ WAS JETZT?

**Nächster Schritt:** Review der Mockups durch DutchMaxwell

**Optionen:**
1. ✅ **Approve** → Implementation starten
2. 🔄 **Request Changes** → Mockups anpassen
3. 🎨 **Iterate** → Mehr Visual Mockups (z.B. Figma Prototypes)
4. 🧪 **Prototype** → Kleiner Tech-Demo (nur Menu z.B.)

**Deine Entscheidung!** 🚀
