# WGS (Wargaming Simulator) Integration

Diese Dokumentation beschreibt die Integration zwischen OpenTTS und dem Wargaming Simulator (WGS) von Udo's 3dWorld.

## Übersicht

Die Integration ermöglicht es, Spielzustände zwischen dem webbasierten WGS (asynchrones Spiel) und OpenTTS (Desktop-Direktspiel) auszutauschen.

### Unterstützte Funktionen

- **Import**: WGS-Spielzustände in OpenTTS laden
- **Export**: OpenTTS-Spielzustand als WGS-Format exportieren
- **Server-Sync**: Direkte Abfrage vom WGS-Server (geplant)
- **Tooltips**: Unit-Statistiken werden beim Hover angezeigt

## WGS Datenformat

### Spielzustand-Datei (`{gameID}.txt`)

Jede Zeile repräsentiert eine Einheit im Format:
```
{size},{x},{y},{color},{angle},{imageId},{name}
```

#### Felder

| Feld | Typ | Beschreibung |
|------|-----|--------------|
| size | float/string | Basisgröße in Zoll, oder Multibase-Format |
| x | float | X-Position in Zoll |
| y | float | Y-Position in Zoll |
| color | string | CSS-Farbname (z.B. "BlanchedAlmond", "blue") |
| angle | float | Rotation in Radiant |
| imageId | int | Custom-Bild-ID (-1 = keins) |
| name | string | Einheiten-Name und Statistiken |

#### Multibase-Format

Für Einheiten mit mehreren Modellen:
```
{width}x{depth}x{columns}x{rows}x{modelCount}
```

Beispiel: `2.362204724409449x1x1x1x3` = 3 Modelle auf einer 60mm Basis

#### Escape-Sequenzen im Name-Feld

- `NEWLINE` → Zeilenumbruch
- `BIGNEWLINE` → Doppelter Zeilenumbruch
- `COMMA` → Komma (da Komma als Trenner verwendet wird)

### Beispiel-Zeile

```
0.984251968503937,13.5,1.5,BlanchedAlmond,-1.5707963,4,Bot Infantry Squad [3]NEWLINEQ5+ D5+ | 40ptsNEWLINENEWLINE3x CCW (A1)NEWLINERifle (24"COMMA A1)
```

## API-Referenz

### WGSClient

Parser und Exporter für das WGS-Format.

```gdscript
# Import aus Datei
var game = wgs_client.import_from_file("path/to/game.txt")

# Import aus Text
var game = wgs_client.import_from_text(content, "game_id")

# Export als Text
var text = wgs_client.export_to_text(game)

# Aktionsstrings erstellen
var move_action = wgs_client.create_move_action(game_id, moves)
var add_action = wgs_client.create_add_action(game_id, unit)
var remove_action = wgs_client.create_remove_action(game_id, [0, 1, 2])
var dice_action = wgs_client.create_dice_action(game_id, 6, "d6")
```

### WGSGameManager

Verwaltet WGS-Spiele und spawnt Einheiten.

```gdscript
# Import und Spawnen
wgs_game_manager.import_from_file("path/to/game.txt")
var models = wgs_game_manager.spawn_game(offset)

# Export
var text = wgs_game_manager.export_current_state()

# Bewegungs-Aktion generieren
var action = wgs_game_manager.generate_move_action()

# Unit-Lookup
var unit = wgs_game_manager.get_unit_for_model(model)
var models = wgs_game_manager.get_models_for_unit(unit)
```

### WGSImportDialog

UI-Dialog für den Import.

```gdscript
# Signal: Spiel wurde importiert
wgs_import_dialog.game_imported.connect(func(game):
    print("Imported: ", game.game_id)
)

# Dialog öffnen
wgs_import_dialog.popup_centered()
```

## WGS Action-Codes

| Code | Aktion | Parameter |
|------|--------|-----------|
| 2 | Add (mit Bild) | size,x,y,color,imageId,name |
| 3 | Move | [index,x,y,angle]... |
| 4 | Remove | [index]... |
| 6 | Edit | index,newText |
| 7 | Dice | anzahl,typ(d6/d8) |
| 8 | Chat | text |
| 9 | Rotate | [index,angle]... |
| 11 | Add (ohne Bild) | size,x,y,color,imageId,name |

## Koordinatensystem

### WGS
- Origin: Top-Left (0,0)
- Einheit: Zoll
- Y-Achse: Nach unten positiv

### OpenTTS
- Origin: Tischmitte
- Einheit: Meter
- Z-Achse: Tiefe (entspricht WGS Y)

### Konvertierung
```gdscript
const INCH_TO_METER = 0.0254

# WGS → OpenTTS
var pos_3d = Vector3(
    wgs_x * INCH_TO_METER - table_width/2,
    0,
    wgs_y * INCH_TO_METER - table_depth/2
)

# OpenTTS → WGS
var wgs_pos = Vector2(
    (pos_3d.x + table_width/2) / INCH_TO_METER,
    (pos_3d.z + table_depth/2) / INCH_TO_METER
)
```

## Server-Integration (Zukunft)

Die Klasse `WGSGameManager` enthält bereits Grundlagen für die HTTP-basierte Synchronisation:

```gdscript
# Spielzustand vom Server abrufen
wgs_game_manager.fetch_game_from_server("MyGameID")

# Signale
wgs_game_manager.sync_started.connect(...)
wgs_game_manager.sync_completed.connect(...)
wgs_game_manager.sync_error.connect(...)
```

Um Züge an den WGS-Server zu senden, muss ein POST-Request an das PHP-Skript gesendet werden:

```
POST https://udos3dworld.com/WargamingSimulator/DoAction.php

Form-Data:
- ActionString: "{gameID},{action},{...params}"
- PlayerName: "Spielername"
- MainImageSizeValue: "1"
- NotesText: ""
- StdColSend: "BlanchedAlmond"
```

## CSS-Farben

Unterstützte Farbnamen (nicht vollständig):

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

## Dateien

- `scripts/wgs_client.gd` - Parser und Exporter
- `scripts/wgs_game_manager.gd` - Spiel-Manager
- `scripts/wgs_import_dialog.gd` - Import-Dialog
