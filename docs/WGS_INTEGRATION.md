# WGS (Wargaming Simulator) Integration

This documentation describes the integration between Niemandsland and the Wargaming Simulator (WGS) by Udo's 3dWorld.

## Overview

The integration makes it possible to exchange game states between the web-based WGS (asynchronous play) and Niemandsland (desktop direct play).

### Supported features

- **Import**: Load WGS game states into Niemandsland
- **Export**: Export a Niemandsland game state as WGS format
- **Server sync**: Direct query from the WGS server (implemented in `wgs_game_manager.gd`; not yet wired into the import dialog UI)
- **Tooltips**: Unit statistics are shown on hover

## WGS data format

### Game-state file (`{gameID}.txt`)

The file starts with two lines for the table size, followed by the unit lines:

```
72                    ← Table width in inches (here: 6 feet)
48                    ← Table depth in inches (here: 4 feet)
{size},{x},{y},{color},{angle},{imageId},{name}
{size},{x},{y},{color},{angle},{imageId},{name}
...
```

Each unit line has the format:
```
{size},{x},{y},{color},{angle},{imageId},{name}
```

#### Fields

| Field | Type | Description |
|------|-----|--------------|
| size | float/string | Base size in inches, or multibase format |
| x | float | X position in inches |
| y | float | Y position in inches |
| color | string | CSS color name (e.g. "BlanchedAlmond", "blue") |
| angle | float | Rotation in radians |
| imageId | int | Custom image ID (-1 = none) |
| name | string | Unit name and statistics |

#### Multibase format

For units with multiple models:
```
{width}x{depth}x{columns}x{rows}x{modelCount}
```

Example: `2.362204724409449x1x1x1x3` = 3 models on a 60mm base

#### Escape sequences in the name field

- `NEWLINE` → line break
- `BIGNEWLINE` → double line break
- `COMMA` → comma (since comma is used as a separator)

### Example line

```
0.984251968503937,13.5,1.5,BlanchedAlmond,-1.5707963,4,Bot Infantry Squad [3]NEWLINEQ5+ D5+ | 40ptsNEWLINENEWLINE3x CCW (A1)NEWLINERifle (24"COMMA A1)
```

## API reference

### WGSClient

Parser and exporter for the WGS format.

```gdscript
# Import from file
var game = wgs_client.import_from_file("path/to/game.txt")

# Import from text
var game = wgs_client.import_from_text(content, "game_id")

# Export as text
var text = wgs_client.export_to_text(game)

# Create action strings
var move_action = wgs_client.create_move_action(game_id, moves)
var add_action = wgs_client.create_add_action(game_id, unit)
var remove_action = wgs_client.create_remove_action(game_id, [0, 1, 2])
var dice_action = wgs_client.create_dice_action(game_id, 6, "d6")
```

### WGSGameManager

Manages WGS games and spawns units.

```gdscript
# Import and spawn
wgs_game_manager.import_from_file("path/to/game.txt")
var models = wgs_game_manager.spawn_game(offset)

# Export
var text = wgs_game_manager.export_current_state()

# Generate movement action
var action = wgs_game_manager.generate_move_action()

# Unit lookup
var unit = wgs_game_manager.get_unit_for_model(model)
var models = wgs_game_manager.get_models_for_unit(unit)
```

### WGSImportDialog

UI dialog for the import.

```gdscript
# Signal: a game was imported
wgs_import_dialog.game_imported.connect(func(game):
    print("Imported: ", game.game_id)
)

# Open dialog
wgs_import_dialog.popup_centered()
```

## WGS action codes

| Code | Action | Parameters |
|------|--------|-----------|
| 2 | Add (with image) | size,x,y,color,imageId,name |
| 3 | Move | [index,x,y,angle]... |
| 4 | Remove | [index]... |
| 6 | Edit | index,newText |
| 7 | Dice | count,type(d6/d8) |
| 8 | Chat | text |
| 9 | Rotate | [index,angle]... |
| 11 | Add (without image) | size,x,y,color,imageId,name |

## Coordinate system

### WGS
- Origin: Top-Left (0,0)
- Unit: inches
- Y axis: positive downward

### Niemandsland
- Origin: table center
- Unit: meters
- Z axis: depth (corresponds to WGS Y)

### Conversion
```gdscript
const INCH_TO_METER = 0.0254

# WGS → Niemandsland
var pos_3d = Vector3(
    wgs_x * INCH_TO_METER - table_width/2,
    0,
    wgs_y * INCH_TO_METER - table_depth/2
)

# Niemandsland → WGS
var wgs_pos = Vector2(
    (pos_3d.x + table_width/2) / INCH_TO_METER,
    (pos_3d.z + table_depth/2) / INCH_TO_METER
)
```

## Server integration (future)

The `WGSGameManager` class already contains the basics for HTTP-based synchronization:

```gdscript
# Fetch game state from the server
wgs_game_manager.fetch_game_from_server("MyGameID")

# Signals
wgs_game_manager.sync_started.connect(...)
wgs_game_manager.sync_completed.connect(...)
wgs_game_manager.sync_error.connect(...)
```

To send moves to the WGS server, a POST request must be sent to the PHP script:

```
POST https://udos3dworld.com/WargamingSimulator/DoAction.php

Form-Data:
- ActionString: "{gameID},{action},{...params}"
- PlayerName: "PlayerName"
- MainImageSizeValue: "1"
- NotesText: ""
- StdColSend: "BlanchedAlmond"
```

## CSS colors

Supported color names (not exhaustive):

| Name | Hex |
|------|-----|
| blanchedalmond | #FFEBCD |
| blue | #0000FF |
| red | #FF0000 |
| green | #008000 |
| yellow | #FFFF00 |
| orange | #FFA500 |
| purple | #800080 |
| gray/grey | #808080 |

## Files

- `scripts/wgs_client.gd` - Parser and exporter
- `scripts/wgs_game_manager.gd` - Game manager
- `scripts/wgs_import_dialog.gd` - Import dialog
