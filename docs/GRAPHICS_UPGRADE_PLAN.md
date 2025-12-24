# OpenTTS - Graphics Upgrade Plan
## Rendering Pipeline & Visual Effects Overhaul

**Status:** Technical Design Document
**Version:** 1.0
**Erstellt:** 2025-12-24

---

## 🎯 ZIELE

1. **State-of-the-Art Grafik** - Modernes, AAA-ähnliches Rendering
2. **Quasi-Raytracing** - SDFGI + VoxelGI für realistische Beleuchtung
3. **Skalierbar** - Von Low-End (GTX 960) bis High-End (RTX 4090)
4. **Performance** - Stabile 60 FPS @ 1080p Medium auf GTX 1660

---

## 🔄 AKTUELL vs. UPGRADE

### Aktueller Stand (project.godot)
```ini
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=2
textures/vram_compression/import_etc2_astc=true

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
```

**Probleme:**
- GL Compatibility = Alte OpenGL 3.3 Pipeline
- Keine modernen Features (GI, SSR, SDFGI)
- Nur MSAA 2x (Aliasing sichtbar)
- Fixed Resolution

---

### Nach Upgrade
```ini
[rendering]
renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=4
anti_aliasing/quality/use_taa=true
textures/vram_compression/import_s3tc_bptc=true
environment/ssao/quality=3
environment/ssil/quality=3
environment/ssr/quality=2
environment/sdfgi/enabled=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=3

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/mode=4  # Exclusive Fullscreen
window/size/resizable=true
window/vsync/vsync_mode=1  # Adaptive
```

---

## 🎨 RENDERING PIPELINE UPGRADE

### 1. Forward+ Rendering

**Was ist Forward+?**
- Moderner Forward-Renderer mit Tile-Based Lighting
- Unterstützt hunderte dynamische Lichter
- Basis für SDFGI und andere moderne Features

**Aktivierung:**
```gdscript
# In project.godot
[rendering]
renderer/rendering_method="forward_plus"

# Fallback für Low-End / Mobile
renderer/rendering_method.mobile="mobile"
```

**Vorteile:**
- ✅ SDFGI (Global Illumination)
- ✅ VoxelGI (Voxel-based GI)
- ✅ Clustered Lights (viele dynamische Lichter)
- ✅ Bessere Schatten
- ✅ Screen-Space Effects (SSAO, SSIL, SSR)

**Performance Impact:**
- +10-15% GPU-Last vs. GL Compatibility
- Aber: Viel bessere visuelle Qualität

---

### 2. Global Illumination (SDFGI)

**Was ist SDFGI?**
- Signed Distance Field Global Illumination
- "Quasi-Raytracing" ohne RT-Hardware
- Realistische indirekte Beleuchtung

**Setup in main.tscn:**
```gdscript
# WorldEnvironment
var env = Environment.new()

# SDFGI aktivieren
env.sdfgi_enabled = true
env.sdfgi_use_occlusion = true
env.sdfgi_read_sky_light = true
env.sdfgi_bounce_feedback = 0.5

# Cascades (mehr = größere Reichweite, langsamer)
env.sdfgi_cascades = 4  # Ultra: 6, High: 4, Medium: 2

# Probe-Spacing
env.sdfgi_min_cell_size = 0.2  # 20cm Zellen

# Y-Scale (optimiert für Tabletop)
env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
```

**Visueller Effekt:**
```
Vorher (ohne GI):
  - Flache Beleuchtung
  - Schatten = Schwarz
  - Keine Farbbluten

Nachher (mit SDFGI):
  - Realistische indirekte Beleuchtung
  - Farbige Reflexionen (roter Panzer reflektiert rotes Licht)
  - Weiche Schatten mit Farbbluten
  - Gelände wirft farbige Schatten
```

**Performance:**
- Ultra (6 Cascades): -25% FPS
- High (4 Cascades): -15% FPS
- Medium (2 Cascades): -8% FPS

---

### 3. VoxelGI (Optional, für Detail-Bereiche)

**Wann nutzen?**
- In kritischen Bereichen (z.B. Spawn-Zone)
- Für statische Szenen (Campaign-Maps)
- Kombiniert mit SDFGI für maximale Qualität

**Setup:**
```gdscript
# VoxelGI Node
var voxel_gi = VoxelGI.new()
voxel_gi.size = Vector3(10, 5, 10)  # 10x10m Bereich, 5m Höhe
voxel_gi.subdiv = VoxelGI.SUBDIV_256  # Auflösung

# Bake GI
voxel_gi.bake()
```

**Verwendung:**
- Nur für spezielle Szenarien
- Nicht für den gesamten Spieltisch (zu aufwändig)

---

### 4. Screen-Space Effects

#### 4A. SSAO (Screen Space Ambient Occlusion)

**Effekt:** Realistische Kontaktschatten in Ecken/Vertiefungen

```gdscript
env.ssao_enabled = true
env.ssao_radius = 2.0
env.ssao_intensity = 1.5
env.ssao_power = 2.0
env.ssao_detail = 0.5
env.ssao_horizon = 0.15
env.ssao_sharpness = 0.9
env.ssao_light_affect = 0.5
env.ssao_ao_channel_affect = 0.0
```

**Quality Settings:**
```gdscript
# project.godot
[rendering]
environment/ssao/quality=3  # 0=Low, 3=Ultra
environment/ssao/half_size=false  # true für Performance
environment/ssao/adaptive_target=0.5
environment/ssao/blur_passes=4  # Ultra: 4, Low: 1
```

**Performance Impact:** -5% FPS

---

#### 4B. SSIL (Screen Space Indirect Lighting)

**Effekt:** Indirekte Beleuchtung via Screen-Space (schneller als SDFGI)

```gdscript
env.ssil_enabled = true
env.ssil_radius = 5.0
env.ssil_intensity = 1.0
env.ssil_sharpness = 0.98
env.ssil_normal_rejection = 1.0
```

**Quality Settings:**
```gdscript
[rendering]
environment/ssil/quality=3  # 0=Low, 3=Ultra
environment/ssil/half_size=false
environment/ssil/adaptive_target=0.5
```

**Performance Impact:** -8% FPS

**Kombination:**
- SDFGI (global) + SSIL (detail) = Beste Qualität
- Nur SSIL = Guter Kompromiss (kein SDFGI nötig)

---

#### 4C. SSR (Screen Space Reflections)

**Effekt:** Reflexionen auf glänzenden Oberflächen (Tisch, Basen)

```gdscript
env.ssr_enabled = true
env.ssr_max_steps = 64  # Ultra: 128, Low: 32
env.ssr_fade_in = 0.15
env.ssr_fade_out = 2.0
env.ssr_depth_tolerance = 0.2
```

**Quality Settings:**
```gdscript
[rendering]
environment/ssr/quality=2  # 0=Low, 2=High
```

**Verwendung:**
- Glänzender Spieltisch (PBR Material mit low roughness)
- Metallische Miniaturen-Basen
- Wasser/Glatte Gelände-Oberflächen

**Performance Impact:** -6% FPS

---

### 5. Volumetric Fog (Optional)

**Effekt:** Atmosphärischer Nebel mit Lichtstreuung

```gdscript
env.volumetric_fog_enabled = true
env.volumetric_fog_density = 0.01  # Sehr subtil
env.volumetric_fog_albedo = Color(0.9, 0.9, 1.0)  # Leichter Blau-Tint
env.volumetric_fog_emission = Color(0, 0, 0)
env.volumetric_fog_emission_energy = 0.0
env.volumetric_fog_gi_inject = 0.5  # Fog reagiert auf GI!
env.volumetric_fog_anisotropy = 0.1
env.volumetric_fog_length = 64.0
env.volumetric_fog_detail_spread = 2.0
env.volumetric_fog_ambient_inject = 0.5
```

**Wann nutzen?**
- Atmosphärische Battles
- Sci-Fi/Fantasy-Settings
- Cinematische Screenshots

**Performance Impact:** -12% FPS ❗

**Recommendation:** Optional, standardmäßig AUS

---

### 6. Schatten-Qualität

#### DirectionalLight3D (Sonne/Haupt-Licht)

```gdscript
var sun = DirectionalLight3D.new()

# Basis
sun.light_color = Color(1.0, 0.98, 0.95)  # Warmes Sonnenlicht
sun.light_energy = 1.2
sun.light_indirect_energy = 1.0  # Für GI

# Schatten
sun.shadow_enabled = true
sun.shadow_opacity = 0.85  # Nicht komplett schwarz
sun.shadow_blur = 2.0  # Soft Shadows!

# Directional Shadow Mode
sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
sun.directional_shadow_split_1 = 0.1
sun.directional_shadow_split_2 = 0.2
sun.directional_shadow_split_3 = 0.5
sun.directional_shadow_blend_splits = true
sun.directional_shadow_max_distance = 50.0

# Shadow Fade
sun.directional_shadow_fade_start = 0.8
```

**Shadow Quality Settings:**
```gdscript
# project.godot
[rendering]
lights_and_shadows/directional_shadow/size=4096  # Ultra: 8192, Low: 1024
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=3  # 0-5
lights_and_shadows/positional_shadow/soft_shadow_filter_quality=3
lights_and_shadows/positional_shadow/atlas_size=4096
```

**Shadow Splits Explained:**
```
Split 1 (0-10%):   Nah bei Kamera - Höchste Auflösung
Split 2 (10-20%):  Mittlere Distanz
Split 3 (20-50%):  Weiter weg
Split 4 (50-100%): Fernste Distanz - Niedrigste Auflösung
```

---

### 7. Tonemapping & Color Grading

```gdscript
# Tonemapping (wichtig für HDR → SDR)
env.tonemap_mode = Environment.TONE_MAPPER_ACES  # Filmischer Look
env.tonemap_exposure = 1.2
env.tonemap_white = 8.0  # Highlight Clipping

# Oder: TONE_MAPPER_FILMIC (weniger gesättigt)
# env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

# Color Adjustments
env.adjustment_enabled = true
env.adjustment_brightness = 1.05
env.adjustment_contrast = 1.1
env.adjustment_saturation = 1.05

# Optional: Color Correction LUT (3D Lookup Table)
# var lut = load("res://assets/luts/cinematic_lut.png")
# env.adjustment_color_correction = lut
```

---

### 8. Glow & Bloom

```gdscript
env.glow_enabled = true
env.glow_intensity = 0.8
env.glow_strength = 1.0
env.glow_bloom = 0.3  # Bloom-Stärke
env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

# Levels (welche Mip-Maps nutzen)
env.glow_levels/1 = 0.0
env.glow_levels/2 = 1.0
env.glow_levels/3 = 1.0
env.glow_levels/4 = 0.5
env.glow_levels/5 = 0.0
env.glow_levels/6 = 0.0
env.glow_levels/7 = 0.0

# HDR
env.glow_hdr_threshold = 1.0
env.glow_hdr_scale = 2.0
```

**Verwendung:**
- Leuchtendes UI
- Muzzle Flashes (zukünftig)
- Magische Effekte
- Team-Color-Glow auf Basen

---

### 9. Anti-Aliasing

#### MSAA (Multi-Sample Anti-Aliasing)
```gdscript
# project.godot
[rendering]
anti_aliasing/quality/msaa_3d=4  # 1=2x, 2=4x, 3=8x

# MSAA Screen Space
anti_aliasing/quality/screen_space_aa=1  # 1=FXAA, 2=TAA
```

**MSAA Levels:**
- **Disabled:** Aliasing sichtbar
- **2x:** Minimal, schnell
- **4x:** Gut (Empfohlen für Medium/High)
- **8x:** Sehr gut, aber teuer (-10% FPS)

#### TAA (Temporal Anti-Aliasing)
```gdscript
anti_aliasing/quality/use_taa=true
```

**Vorteile:**
- Smoothere Kanten als MSAA
- Funktioniert mit transparenten Objekten
- Reduziert Shimmer bei Bewegung

**Nachteil:**
- Leichtes Ghosting bei schneller Kamerabewegung

**Empfehlung:** TAA + MSAA 4x für beste Qualität

---

### 10. AMD FSR (FidelityFX Super Resolution)

**Was ist FSR?**
- Upscaling-Technologie (rendert in niedrigerer Auflösung, skaliert hoch)
- +30-50% Performance bei minimaler Qualitätseinbuße

**Aktivierung:**
```gdscript
# project.godot
[rendering]
scaling_3d/mode=1  # 1=FSR, 0=Bilinear
scaling_3d/scale=0.77  # Renderauflösung-Faktor
scaling_3d/fsr_sharpness=0.5  # 0.0-2.0

# Alternative: Bilinear (einfacher)
# scaling_3d/mode=0
```

**FSR Modi:**
| Mode         | Scale Factor | Resolution (von 1080p) | Performance Gain |
|--------------|--------------|------------------------|------------------|
| **Native**   | 1.0          | 1920×1080              | -                |
| **Quality**  | 0.77         | 1477×831               | +30%             |
| **Balanced** | 0.67         | 1286×723               | +45%             |
| **Perf.**    | 0.59         | 1133×637               | +60%             |
| **Ultra**    | 0.50         | 960×540                | +100% ⚠️          |

**User Settings:**
```gdscript
# Einstellbar über Slider im Settings-Menü
get_viewport().scaling_3d_scale = 0.77  # FSR Balanced
```

---

## 🎨 MATERIAL UPGRADES

### PBR-Workflow

**Standard Material Setup:**
```gdscript
var material = StandardMaterial3D.new()

# Albedo (Base Color)
material.albedo_color = Color(0.8, 0.8, 0.8)
material.albedo_texture = load("res://textures/wood_albedo.png")

# Metallic
material.metallic = 0.0  # 0=Nicht-Metall, 1=Metall
material.metallic_texture = load("res://textures/wood_metallic.png")
material.metallic_specular = 0.5

# Roughness
material.roughness = 0.7  # 0=Glatt/Glänzend, 1=Rau/Matt
material.roughness_texture = load("res://textures/wood_roughness.png")

# Normal Map (für Details)
material.normal_enabled = true
material.normal_texture = load("res://textures/wood_normal.png")
material.normal_scale = 1.0

# Ambient Occlusion
material.ao_enabled = true
material.ao_texture = load("res://textures/wood_ao.png")
material.ao_light_affect = 0.5

# Emission (für leuchtende Elemente)
material.emission_enabled = false
material.emission = Color(0, 0, 0)
material.emission_energy_multiplier = 1.0
```

---

### Material-Beispiele

#### 1. Spieltisch (Holz/Stoff)
```gdscript
var table_mat = StandardMaterial3D.new()
table_mat.albedo_color = Color(0.25, 0.3, 0.25)  # Dunkelgrünes Filz
table_mat.metallic = 0.0
table_mat.roughness = 0.8
table_mat.normal_enabled = true
table_mat.normal_texture = load("res://assets/textures/felt_normal.png")
```

#### 2. Miniatur-Base (Metallisch mit Team-Color)
```gdscript
var base_mat = StandardMaterial3D.new()
base_mat.albedo_color = Color(0.1, 0.1, 0.1)
base_mat.metallic = 0.9  # Sehr metallisch
base_mat.roughness = 0.3  # Leicht glänzend

# Rim-Lighting für Team-Color
base_mat.rim_enabled = true
base_mat.rim = 0.5
base_mat.rim_tint = 0.5
base_mat.rim_color = Color(0, 0.85, 1.0)  # Cyan = Player 1

# Anisotropic für gebürstetes Metall
base_mat.anisotropy_enabled = true
base_mat.anisotropy = 0.3
```

#### 3. Gelände (Stein/Beton)
```gdscript
var terrain_mat = StandardMaterial3D.new()
terrain_mat.albedo_texture = load("res://assets/textures/concrete_albedo.png")
terrain_mat.metallic = 0.0
terrain_mat.roughness_texture = load("res://assets/textures/concrete_roughness.png")
terrain_mat.normal_enabled = true
terrain_mat.normal_texture = load("res://assets/textures/concrete_normal.png")
terrain_mat.normal_scale = 1.5  # Stärkere Bumps
terrain_mat.uv1_triplanar = true  # Auto-UV für komplexe Formen
```

---

### Shader für Team-Colors

**Custom Shader (team_color.gdshader):**
```glsl
shader_type spatial;

uniform vec4 team_color : source_color = vec4(0.0, 0.85, 1.0, 1.0);
uniform float team_color_intensity : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D albedo_texture;
uniform float metallic : hint_range(0.0, 1.0) = 0.8;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec4 albedo = texture(albedo_texture, UV);

    // Rim-Lighting mit Team-Color
    float rim = 1.0 - dot(NORMAL, VIEW);
    rim = pow(rim, 3.0);

    vec3 emission = team_color.rgb * rim * team_color_intensity;

    ALBEDO = albedo.rgb;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    EMISSION = emission;
}
```

**Usage:**
```gdscript
var shader_mat = ShaderMaterial.new()
shader_mat.shader = load("res://shaders/team_color.gdshader")
shader_mat.set_shader_parameter("team_color", Color(0, 0.85, 1.0))  # Cyan
shader_mat.set_shader_parameter("team_color_intensity", 0.7)
```

---

## 🎬 POST-PROCESSING STACK

**Finale Environment-Konfiguration (Ultra Preset):**

```gdscript
extends Node3D

func setup_ultra_graphics():
    var world_env = $WorldEnvironment
    var env = Environment.new()

    # === SKY ===
    var sky_material = ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color(0.4, 0.6, 0.8)
    sky_material.sky_horizon_color = Color(0.7, 0.8, 0.9)
    sky_material.ground_bottom_color = Color(0.2, 0.2, 0.2)
    sky_material.ground_horizon_color = Color(0.5, 0.5, 0.5)

    var sky = Sky.new()
    sky.sky_material = sky_material

    env.background_mode = Environment.BG_SKY
    env.sky = sky

    # === AMBIENT LIGHT ===
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.5

    # === TONEMAPPING ===
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = 1.2
    env.tonemap_white = 8.0

    # === SDFGI (Global Illumination) ===
    env.sdfgi_enabled = true
    env.sdfgi_use_occlusion = true
    env.sdfgi_read_sky_light = true
    env.sdfgi_bounce_feedback = 0.5
    env.sdfgi_cascades = 6  # Ultra
    env.sdfgi_min_cell_size = 0.2
    env.sdfgi_cascade0_distance = 12.8
    env.sdfgi_max_distance = 204.8
    env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
    env.sdfgi_energy = 1.0

    # === SSAO ===
    env.ssao_enabled = true
    env.ssao_radius = 2.0
    env.ssao_intensity = 1.5
    env.ssao_power = 2.0
    env.ssao_detail = 0.5
    env.ssao_horizon = 0.15
    env.ssao_sharpness = 0.9

    # === SSIL ===
    env.ssil_enabled = true
    env.ssil_radius = 5.0
    env.ssil_intensity = 1.0
    env.ssil_sharpness = 0.98
    env.ssil_normal_rejection = 1.0

    # === SSR ===
    env.ssr_enabled = true
    env.ssr_max_steps = 128  # Ultra
    env.ssr_fade_in = 0.15
    env.ssr_fade_out = 2.0
    env.ssr_depth_tolerance = 0.2

    # === GLOW ===
    env.glow_enabled = true
    env.glow_intensity = 0.8
    env.glow_strength = 1.0
    env.glow_bloom = 0.3
    env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
    env.glow_levels/2 = 1.0
    env.glow_levels/3 = 1.0
    env.glow_levels/4 = 0.5
    env.glow_hdr_threshold = 1.0
    env.glow_hdr_scale = 2.0

    # === VOLUMETRIC FOG (Optional) ===
    env.volumetric_fog_enabled = false  # Standard: AUS
    # env.volumetric_fog_density = 0.01
    # env.volumetric_fog_albedo = Color(0.9, 0.9, 1.0)
    # env.volumetric_fog_gi_inject = 0.5

    # === COLOR ADJUSTMENTS ===
    env.adjustment_enabled = true
    env.adjustment_brightness = 1.05
    env.adjustment_contrast = 1.1
    env.adjustment_saturation = 1.05

    world_env.environment = env
```

---

## 📊 PERFORMANCE PRESETS

### Ultra (4K, All Effects)
```ini
Resolution: 3840×2160
FSR: Disabled (Native)
SDFGI: 6 Cascades
SSAO/SSIL/SSR: Max Quality
Shadows: 8192px, PCF5
MSAA: 8x + TAA
Volumetric Fog: Enabled

Target: 60 FPS on RTX 3080 / RX 6800 XT
```

### High (1440p)
```ini
Resolution: 2560×1440
FSR: Quality (0.77)
SDFGI: 4 Cascades
SSAO/SSIL/SSR: High Quality
Shadows: 4096px, PCF3
MSAA: 4x + TAA
Volumetric Fog: Disabled

Target: 90 FPS on RTX 3060 / RX 6600 XT
```

### Medium (1080p) - **Empfohlen**
```ini
Resolution: 1920×1080
FSR: Balanced (0.67)
SDFGI: Disabled, SSIL only
SSAO: Medium
SSR: Disabled
Shadows: 2048px, PCF1
MSAA: 2x + TAA
Volumetric Fog: Disabled

Target: 120 FPS on GTX 1660 / RX 580
```

### Low (1080p, Minimum)
```ini
Resolution: 1920×1080
FSR: Performance (0.59)
SDFGI/SSIL/SSR: All Disabled
SSAO: Low
Shadows: 1024px, No Filter
MSAA: Disabled, FXAA only
Volumetric Fog: Disabled

Target: 144 FPS on GTX 960 / RX 560
```

---

## 🚀 IMPLEMENTATION ROADMAP

### Phase 1: Rendering Pipeline (2-3 Tage)
- [ ] project.godot auf Forward+ umstellen
- [ ] SDFGI in main.tscn einrichten
- [ ] DirectionalLight3D optimieren
- [ ] Quality Presets implementieren

### Phase 2: Post-Processing (1-2 Tage)
- [ ] SSAO/SSIL/SSR konfigurieren
- [ ] Tonemapping & Color Grading
- [ ] Glow & Bloom
- [ ] Anti-Aliasing (TAA + MSAA)

### Phase 3: Materials (2 Tage)
- [ ] PBR-Materials für Tisch
- [ ] Team-Color-Shader
- [ ] Gelände-Materials
- [ ] Texture-Import optimieren

### Phase 4: Resolution Scaling (1 Tag)
- [ ] FSR implementieren
- [ ] Settings-Integration
- [ ] User-Presets speichern/laden

### Phase 5: Optimization (2 Tage)
- [ ] Performance-Profiling
- [ ] LOD-System für Miniaturen
- [ ] Culling optimieren
- [ ] Preset-Balancing

---

## 🎯 SUCCESS METRICS

**Visuell:**
- ✅ Realistische indirekte Beleuchtung (SDFGI)
- ✅ Weiche, detaillierte Schatten
- ✅ Glänzende Oberflächen mit Reflexionen
- ✅ Minimales Aliasing (glatte Kanten)

**Performance:**
- ✅ 60 FPS @ 1080p Medium (GTX 1660)
- ✅ 90 FPS @ 1440p High (RTX 3060)
- ✅ 144 FPS @ 1080p Low (GTX 960)

**Skalierbarkeit:**
- ✅ 5 Quality Presets (Ultra → Low)
- ✅ FSR-Upscaling funktioniert
- ✅ Alle Settings persistent gespeichert

---

**Status:** Ready for Implementation
**Priority:** VERY HIGH
**Estimated Total Time:** 8-10 days
**Dependencies:** Godot 4.3+, OpenGL 4.6 / Vulkan
