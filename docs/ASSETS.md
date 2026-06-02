# Asset-Quellen für OpenTTS

Dieses Dokument listet empfohlene Open-Source Asset-Quellen für das Projekt.

## Lizenz-Priorität

Wir bevorzugen Assets mit folgenden Lizenzen (in dieser Reihenfolge):
1. **CC0 (Public Domain)** - Keine Einschränkungen, ideal
2. **CC-BY** - Attribution erforderlich
3. **MIT/Apache** - Software-Lizenzen, auch für Assets nutzbar
4. **CC-BY-SA** - Attribution + Share-Alike

## Empfohlene Quellen

### 3D-Modelle

#### Kenney.nl (CC0)
- **URL**: https://kenney.nl/assets
- **Lizenz**: CC0 1.0 (Public Domain)
- **Relevant für**:
  - Dice Pack: https://kenney.nl/assets/dice-pack
  - Board Game Kit: https://kenney.nl/assets/board-game-kit
  - Furniture Kit (für Tische): https://kenney.nl/assets/furniture-kit

#### Quaternius (CC0)
- **URL**: https://quaternius.com/
- **Lizenz**: CC0 1.0 (Public Domain)
- **Relevant für**:
  - Low-Poly Gelände
  - Umgebungsobjekte
  - Medieval/Fantasy Assets

#### OpenGameArt.org
- **URL**: https://opengameart.org/
- **Lizenz**: Variiert (CC0, CC-BY, GPL)
- **Hinweis**: Lizenz pro Asset prüfen!
- **Suche nach**:
  - "tabletop"
  - "miniature"
  - "dice"
  - "terrain"

### Godot Asset Library

#### 3D-Würfel — eigene Implementierung (MIT)
- In-house: `scripts/dice_tray.gd` + `scripts/dice_d6.gd` — physikbasierte W6 in
  einem skalierten SubViewport. Ersetzt den früheren AGPL-Fremd-Addon.

### Texturen

#### Poly Haven (CC0)
- **URL**: https://polyhaven.com/
- **Lizenz**: CC0 1.0
- **Relevant für**:
  - Holztexturen (Tische)
  - Stoff/Filz (Spielmatten)
  - Stein/Gras (Gelände)

#### AmbientCG (CC0)
- **URL**: https://ambientcg.com/
- **Lizenz**: CC0 1.0
- **Relevant für**:
  - PBR-Materialien
  - Hochauflösende Texturen

### 3D-Modell-Marktplätze (mit freien Assets)

#### Sketchfab (Lizenz beachten!)
- **URL**: https://sketchfab.com/
- **Filter**: "Downloadable" + "CC0" oder "CC-BY"
- **Format**: glTF 2.0 direkt exportierbar
- **Beispiel**: Rounded Cube für Würfel-Basis

#### Turbosquid (Free Section)
- **URL**: https://www.turbosquid.com/Search/3D-Models/free
- **Hinweis**: Lizenz genau prüfen!

### Audio

#### Freesound.org (Lizenz variiert)
- **URL**: https://freesound.org/
- **Suche nach**:
  - "dice roll"
  - "wooden table"
  - "board game"

#### Kenney Audio (CC0)
- **URL**: https://kenney.nl/assets/category:Audio
- **Lizenz**: CC0 1.0

## Wargaming-spezifische Quellen

### STL zu glTF Konvertierung
Viele Wargaming-Modelle sind als STL verfügbar. Konvertierung zu glTF:
- Blender (kostenlos): Import STL → Export glTF
- Online: https://products.aspose.app/3d/conversion/stl-to-gltf

### Freie Miniatur-STLs
- **Thingiverse**: https://www.thingiverse.com/search?q=wargaming
- **MyMiniFactory**: https://www.myminifactory.com/search/?free=1&cat=59
- **Cults3D**: https://cults3d.com/en/search?q=wargaming

**Achtung**: Lizenz jedes Modells prüfen! Viele sind nur für persönliche Nutzung.

## Asset-Ordnerstruktur

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

## Import-Workflow

### glTF-Import in Godot
1. Datei in entsprechenden `assets/`-Ordner kopieren
2. Godot importiert automatisch
3. In Import-Tab prüfen:
   - "Generate Collisions" für physikalische Objekte
   - "Loop" für Animationen falls nötig

### Textur-Import
1. PNG/JPG in `assets/textures/` kopieren
2. Import-Einstellungen anpassen:
   - "Filter": Für Pixel-Art auf "Nearest" stellen
   - "Mipmaps": Für 3D aktivieren

## Verwendete Assets

| Asset | Quelle | Lizenz | Verwendet für |
|-------|--------|--------|---------------|
| Kenney UI Pack(s) | [kenney.nl](https://kenney.nl) | CC0 | UI-Themes (`assets/kenney_ui/`, `ThemeManager`) |
| 3D-Würfel (eigene W6) | projekt-intern | MIT | Würfel (`scripts/dice_tray.gd`, `scripts/dice_d6.gd`) |
| gdUnit4 | [gdUnit4](https://github.com/MikeSchulze/gdUnit4) | MIT | Test-Framework (`addons/gdUnit4/`) |
| Miniatur-GLBs | Model-Forge-Pipeline (KI-generiert) | projekt-intern | `assets/miniatures/<faction>/` |
| `model-viewer` | [Google](https://modelviewer.dev) | Apache-2.0 | 3D-Vorschau in der Model-Forge-Review-UI |

## Lizenz-Hinweise

Bei Verwendung von CC-BY Assets müssen folgende Informationen dokumentiert werden:
- Autor/Ersteller
- Titel des Werks
- Quelle (URL)
- Lizenz mit Link

Beispiel Attribution:
```
"Dice Model" by [Autor] (https://example.com/asset)
Licensed under CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/)
```
