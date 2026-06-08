# Asset sources for Niemandsland

This document lists recommended open-source asset sources for the project.

## License priority

We prefer assets with the following licenses (in this order):
1. **CC0 (Public Domain)** - No restrictions, ideal
2. **CC-BY** - Attribution required
3. **MIT/Apache** - Software licenses, also usable for assets
4. **CC-BY-SA** - Attribution + Share-Alike

## Recommended sources

### 3D models

#### Kenney.nl (CC0)
- **URL**: https://kenney.nl/assets
- **License**: CC0 1.0 (Public Domain)
- **Relevant for**:
  - Dice Pack: https://kenney.nl/assets/dice-pack
  - Board Game Kit: https://kenney.nl/assets/board-game-kit
  - Furniture Kit (for tables): https://kenney.nl/assets/furniture-kit

#### Quaternius (CC0)
- **URL**: https://quaternius.com/
- **License**: CC0 1.0 (Public Domain)
- **Relevant for**:
  - Low-poly terrain
  - Environment objects
  - Medieval/Fantasy assets

#### OpenGameArt.org
- **URL**: https://opengameart.org/
- **License**: Varies (CC0, CC-BY, GPL)
- **Note**: Check the license per asset!
- **Search for**:
  - "tabletop"
  - "miniature"
  - "dice"
  - "terrain"

### Godot Asset Library

#### 3D dice — in-house implementation (MIT)
- In-house: `scripts/dice_tray.gd` + `scripts/dice_d6.gd` — physics-based D6 in
  a scaled SubViewport. Replaces the former AGPL third-party addon.

### Textures

#### Poly Haven (CC0)
- **URL**: https://polyhaven.com/
- **License**: CC0 1.0
- **Relevant for**:
  - Wood textures (tables)
  - Fabric/felt (game mats)
  - Stone/grass (terrain)

#### AmbientCG (CC0)
- **URL**: https://ambientcg.com/
- **License**: CC0 1.0
- **Relevant for**:
  - PBR materials
  - High-resolution textures

### 3D model marketplaces (with free assets)

#### Sketchfab (check the license!)
- **URL**: https://sketchfab.com/
- **Filter**: "Downloadable" + "CC0" or "CC-BY"
- **Format**: glTF 2.0 directly exportable
- **Example**: Rounded cube for the dice base

#### Turbosquid (Free Section)
- **URL**: https://www.turbosquid.com/Search/3D-Models/free
- **Note**: Check the license carefully!

### Audio

#### Freesound.org (license varies)
- **URL**: https://freesound.org/
- **Search for**:
  - "dice roll"
  - "wooden table"
  - "board game"

#### Kenney Audio (CC0)
- **URL**: https://kenney.nl/assets/category:Audio
- **License**: CC0 1.0

## Wargaming-specific sources

### STL to glTF conversion
Many wargaming models are available as STL. Conversion to glTF:
- Blender (free): Import STL → Export glTF
- Online: https://products.aspose.app/3d/conversion/stl-to-gltf

### Free miniature STLs
- **Thingiverse**: https://www.thingiverse.com/search?q=wargaming
- **MyMiniFactory**: https://www.myminifactory.com/search/?free=1&cat=59
- **Cults3D**: https://cults3d.com/en/search?q=wargaming

**Caution**: Check the license of each model! Many are for personal use only.

## Asset folder structure

```
assets/
├── models/
│   ├── dice/           # Würfel-Modelle
│   ├── miniatures/     # Spielfiguren
│   ├── terrain/        # Gelände-Objekte
│   └── tokens/         # Marker, Tokens
├── textures/
│   ├── tables/         # Tisch-/Matten-Texturen
│   └── materials/      # Allgemeine Materialien
└── audio/
    ├── dice/           # Würfel-Sounds
    └── ui/             # UI-Feedback-Sounds
```

## Import workflow

### glTF import into Godot
1. Copy the file into the corresponding `assets/` folder
2. Godot imports automatically
3. Check in the Import tab:
   - "Generate Collisions" for physical objects
   - "Loop" for animations if needed

### Texture import
1. Copy PNG/JPG into `assets/textures/`
2. Adjust the import settings:
   - "Filter": Set to "Nearest" for pixel art
   - "Mipmaps": Enable for 3D

## Used assets

| Asset | Source | License | Used for |
|-------|--------|--------|---------------|
| Kenney UI Pack(s) | [kenney.nl](https://kenney.nl) | CC0 | UI themes (`assets/kenney_ui/`, `ThemeManager`) |
| 3D dice (in-house D6) | project-internal | MIT | Dice (`scripts/dice_tray.gd`, `scripts/dice_d6.gd`) |
| gdUnit4 | [gdUnit4](https://github.com/MikeSchulze/gdUnit4) | MIT | Test framework (`addons/gdUnit4/`) |
| Miniature GLBs | Model Forge pipeline (AI-generated) | project-internal | `assets/miniatures/<faction>/` |
| `model-viewer` | [Google](https://modelviewer.dev) | Apache-2.0 | 3D preview in the Model Forge review UI |

## License notes

When using CC-BY assets, the following information must be documented:
- Author/creator
- Title of the work
- Source (URL)
- License with link

Example attribution:
```
"Dice Model" by [Autor] (https://example.com/asset)
Licensed under CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/)
```
