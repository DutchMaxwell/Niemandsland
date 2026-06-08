# OnePageRules (OPR) Army Forge API - Detailed Research

**Creation date:** December 28, 2025
**Project context:** Integration into a Godot project (GDScript)

---

## Executive Summary

After comprehensive research, it was determined that **OnePageRules does not provide an officially documented, public API** for their Army Forge. However, several unofficial endpoints and data structures used by community tools were identified. Integration into a Godot project is possible, but it requires reverse engineering of the web app or the use of local data.

---

## 1. API availability and authentication

### 1.1 Official API
- **Status:** No official, documented API available
- **Documentation:** Not available
- **API key:** Not required (no public API)
- **Authentication:** Not documented

### 1.2 Army Forge Studio
- **URL:** https://army-forge-studio.onepagerules.com/
- **Access:** Patreon Tier 1 required to create your own armies
- **Public access:** All user-created armies are available for free

---

## 2. Identified endpoints

Based on the analysis of community tools and web traffic, the following endpoints were identified:

### 2.1 Army Books (PDF export)
```
https://army-forge-studio.onepagerules.com/api/army-books/{book-id}/pdf
```

**Examples:**
- `https://army-forge-studio.onepagerules.com/api/army-books/w70ha3o85pa7nigq~2/pdf` - GF Knight Brothers 3.4.4
- `https://army-forge-studio.onepagerules.com/api/army-books/78qp9l5alslt6yj8~2/pdf` - Battle Brothers 3.4.4
- `https://army-forge-studio.onepagerules.com/api/army-books/tOWt5fgqK2nfpoBN~4/pdf` - AoF Ratmen v3.4.1

**ID format:** Alphanumeric characters followed by `~` and version number

### 2.2 Share Links (Army Lists)
```
https://army-forge.onepagerules.com/share?id={list-id}&name={army-name}
```

**Parameters:**
- `id`: Unique identifier for the army list (e.g. `OLIsCH_xzKvU`)
- `name`: Name of the army (URL-encoded)

**Example:**
```
https://army-forge.onepagerules.com/share?id=OLIsCH_xzKvU&name=Wolf_Prime%20Brothers
```

### 2.3 Army Info
```
https://army-forge.onepagerules.com/armyInfo?gameSystem={system-id}&armyId={army-id}
```

**Parameters:**
- `gameSystem`: Game system ID (e.g. `2`)
- `armyId`: Unique army identifier (e.g. `RWvb-wUkrWS_hHBx`)

**Example:**
```
https://army-forge.onepagerules.com/armyInfo?gameSystem=2&armyId=RWvb-wUkrWS_hHBx
```

---

## 3. Data structure and format

### 3.1 JSON export
Army Forge supports exporting army lists as JSON:
- **Method:** "Share as File" in the Army Forge menu
- **Format:** JSON structure with unit data

### 3.2 Local data
The open-source project `opr-army-forge` (GitHub: RobMayer/opr-army-forge) contains:
- **Directory:** `public/definitions/`
- **Content:** JSON files with Army Books, Units, Special Rules
- **JSON Schema:** Present in the repository

### 3.3 Unit data structure
Typical unit properties:
- **Quality (Q):** e.g. `Q4+`, `Q3+`
- **Defense (D):** e.g. `D4+`, `D5+`
- **Points:** Point cost of the unit
- **Special Rules:** e.g. `Fearless`, `Furious`, `Hero`, `Tough(X)`
- **Weapons:** Weapons with attack values, AP (Armor Piercing), Range

**Example structure (hypothetical, based on community tools):**
```json
{
  "name": "Space Marine",
  "quality": "4+",
  "defense": "4+",
  "points": 100,
  "specialRules": ["Fearless", "Tough(3)"],
  "weapons": [
    {
      "name": "Bolter",
      "attacks": 2,
      "ap": 1,
      "range": 24,
      "specialRules": []
    }
  ]
}
```

---

## 4. Rate Limits

**Status:** No information available
- No official documentation on rate limits
- For unofficial use: recommended to proceed conservatively (max. 1-2 requests per second)
- Monitoring of HTTP status codes (429 = Too Many Requests) recommended

---

## 5. Community projects

### 5.1 opr-army-forge (GitHub: RobMayer/opr-army-forge)
- **Type:** Next.js web application
- **Features:** Local army builder without API dependencies
- **Data:** JSON files in the `public/definitions/` directory
- **License:** Open Source
- **URL:** https://github.com/RobMayer/opr-army-forge

### 5.2 Tombola's OPR AF to TTS (thomascgray/opr-af-to-tts)
- **Type:** Web tool for Tabletop Simulator integration
- **Features:** Import of Army Forge Share Links, export to TTS
- **Tech Stack:** Netlify Functions for list storage
- **URL:** https://opr-af-to-tts.netlify.app/
- **GitHub:** https://github.com/thomascgray/opr-af-to-tts

### 5.3 OPRDataCards (JackGruber/OPRDataCards)
- **Type:** PDF generator for datacards
- **Input:** JSON export from Army Forge
- **Features:** Image integration, custom datacards

---

## 6. Godot Integration - Implementation strategies

There are three primary approaches for integration into a Godot project:

### Strategy A: Local JSON data
**Recommended for:** Offline games, full control over the data

### Strategy B: HTTP requests to identified endpoints
**Recommended for:** Online features, up-to-date data

### Strategy C: Hybrid approach
**Recommended for:** Best balance between offline functionality and online updates

---

## 7. GDScript code examples

### 7.1 HTTPRequest setup for Army Forge

```gdscript
extends Node

# Konstanten für API-Endpunkte
const ARMY_FORGE_BASE_URL = "https://army-forge.onepagerules.com"
const ARMY_FORGE_STUDIO_API = "https://army-forge-studio.onepagerules.com/api"

# Node-Referenzen
var http_request: HTTPRequest

func _ready():
    # HTTPRequest Node erstellen
    http_request = HTTPRequest.new()
    add_child(http_request)

    # Signal verbinden
    http_request.connect("request_completed", self, "_on_request_completed")

    # Timeout setzen (empfohlen: 10 Sekunden)
    http_request.timeout = 10.0

func _on_request_completed(result, response_code, headers, body):
    if result != HTTPRequest.RESULT_SUCCESS:
        push_error("HTTP Request failed with result: " + str(result))
        return

    if response_code != 200:
        push_error("HTTP Response code: " + str(response_code))
        return

    # Erfolgreiche Response verarbeiten
    var json_result = JSON.parse(body.get_string_from_utf8())
    if json_result.error == OK:
        var data = json_result.result
        print("Data received: ", data)
    else:
        push_error("JSON Parse Error: " + str(json_result.error_string))
```

### 7.2 Share Link fetching

```gdscript
# Army List von Share Link abrufen
func fetch_army_list(share_id: String, army_name: String):
    var url = "%s/share?id=%s&name=%s" % [
        ARMY_FORGE_BASE_URL,
        share_id,
        army_name.percent_encode()
    ]

    print("Fetching army list from: ", url)
    var error = http_request.request(url)

    if error != OK:
        push_error("An error occurred while making the request: " + str(error))

# Beispielaufruf
func _on_button_pressed():
    fetch_army_list("OLIsCH_xzKvU", "Wolf Prime Brothers")
```

### 7.3 Army Book PDF download

```gdscript
# Army Book PDF herunterladen
func download_army_book_pdf(book_id: String):
    var url = "%s/army-books/%s/pdf" % [ARMY_FORGE_STUDIO_API, book_id]

    print("Downloading army book PDF from: ", url)
    var error = http_request.request(url)

    if error != OK:
        push_error("An error occurred while making the request: " + str(error))

func _on_pdf_request_completed(result, response_code, headers, body):
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
        # PDF als Datei speichern
        var file = File.new()
        var filename = "user://army_book_%d.pdf" % OS.get_unix_time()
        file.open(filename, File.WRITE)
        file.store_buffer(body)
        file.close()
        print("PDF saved to: ", filename)
```

### 7.4 Loading local JSON data

```gdscript
# Lokale Army Data aus JSON-Datei laden
func load_local_army_data(file_path: String):
    var file = File.new()

    if not file.file_exists(file_path):
        push_error("File does not exist: " + file_path)
        return null

    file.open(file_path, File.READ)
    var json_text = file.get_as_text()
    file.close()

    var json_result = JSON.parse(json_text)
    if json_result.error == OK:
        return json_result.result
    else:
        push_error("JSON Parse Error: " + json_result.error_string)
        return null

# Beispielaufruf
func _ready():
    var army_data = load_local_army_data("res://data/armies/grimdark_future.json")
    if army_data:
        print("Army data loaded successfully")
        process_army_data(army_data)
```

### 7.5 Complete Army Manager Class

```gdscript
extends Node
class_name ArmyForgeManager

# Signals
signal army_list_loaded(army_data)
signal army_book_downloaded(pdf_path)
signal request_failed(error_message)

# Konstanten
const ARMY_FORGE_BASE_URL = "https://army-forge.onepagerules.com"
const ARMY_FORGE_STUDIO_API = "https://army-forge-studio.onepagerules.com/api"
const CACHE_DIR = "user://cache/army_forge/"

# Node-Referenzen
var http_request: HTTPRequest
var current_request_type: String = ""

# Cache
var cached_armies = {}

func _ready():
    # Cache-Verzeichnis erstellen
    var dir = Directory.new()
    if not dir.dir_exists(CACHE_DIR):
        dir.make_dir_recursive(CACHE_DIR)

    # HTTPRequest einrichten
    setup_http_request()

func setup_http_request():
    http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.connect("request_completed", self, "_on_request_completed")
    http_request.timeout = 10.0

func fetch_army_list(share_id: String, army_name: String = ""):
    # Zuerst Cache prüfen
    if cached_armies.has(share_id):
        print("Loading army from cache: ", share_id)
        emit_signal("army_list_loaded", cached_armies[share_id])
        return

    # Von Web abrufen
    current_request_type = "army_list"
    var url = "%s/share?id=%s" % [ARMY_FORGE_BASE_URL, share_id]

    if army_name != "":
        url += "&name=%s" % army_name.percent_encode()

    print("Fetching army list: ", url)
    var error = http_request.request(url)

    if error != OK:
        emit_signal("request_failed", "Request error: " + str(error))

func download_army_book(book_id: String, save_locally: bool = true):
    current_request_type = "army_book_pdf"
    var url = "%s/army-books/%s/pdf" % [ARMY_FORGE_STUDIO_API, book_id]

    print("Downloading army book: ", url)
    var error = http_request.request(url)

    if error != OK:
        emit_signal("request_failed", "Request error: " + str(error))

func get_army_info(game_system_id: int, army_id: String):
    current_request_type = "army_info"
    var url = "%s/armyInfo?gameSystem=%d&armyId=%s" % [
        ARMY_FORGE_BASE_URL,
        game_system_id,
        army_id
    ]

    print("Fetching army info: ", url)
    var error = http_request.request(url)

    if error != OK:
        emit_signal("request_failed", "Request error: " + str(error))

func _on_request_completed(result, response_code, headers, body):
    if result != HTTPRequest.RESULT_SUCCESS:
        emit_signal("request_failed", "HTTP request failed: " + str(result))
        return

    if response_code != 200:
        emit_signal("request_failed", "HTTP response code: " + str(response_code))
        return

    match current_request_type:
        "army_list":
            _handle_army_list_response(body)
        "army_book_pdf":
            _handle_army_book_response(body)
        "army_info":
            _handle_army_info_response(body)

func _handle_army_list_response(body: PoolByteArray):
    var json_text = body.get_string_from_utf8()
    var json_result = JSON.parse(json_text)

    if json_result.error == OK:
        var army_data = json_result.result

        # In Cache speichern
        if army_data.has("id"):
            cached_armies[army_data["id"]] = army_data

        emit_signal("army_list_loaded", army_data)
    else:
        emit_signal("request_failed", "JSON parse error: " + json_result.error_string)

func _handle_army_book_response(body: PoolByteArray):
    # PDF speichern
    var filename = "%sarmy_book_%d.pdf" % [CACHE_DIR, OS.get_unix_time()]
    var file = File.new()
    file.open(filename, File.WRITE)
    file.store_buffer(body)
    file.close()

    print("Army book saved to: ", filename)
    emit_signal("army_book_downloaded", filename)

func _handle_army_info_response(body: PoolByteArray):
    var json_text = body.get_string_from_utf8()
    var json_result = JSON.parse(json_text)

    if json_result.error == OK:
        var army_info = json_result.result
        emit_signal("army_list_loaded", army_info)
    else:
        emit_signal("request_failed", "JSON parse error: " + json_result.error_string)

func load_local_definitions(definitions_path: String):
    """
    Lädt lokale Army Definitions aus dem opr-army-forge Repository
    """
    var dir = Directory.new()
    var files = []

    if dir.open(definitions_path) == OK:
        dir.list_dir_begin(true, true)
        var file_name = dir.get_next()

        while file_name != "":
            if file_name.ends_with(".json"):
                files.append(definitions_path + "/" + file_name)
            file_name = dir.get_next()

        dir.list_dir_end()

    # Alle JSON-Dateien laden
    var definitions = {}
    for file_path in files:
        var file = File.new()
        file.open(file_path, File.READ)
        var json_text = file.get_as_text()
        file.close()

        var json_result = JSON.parse(json_text)
        if json_result.error == OK:
            var file_name = file_path.get_file().get_basename()
            definitions[file_name] = json_result.result

    return definitions

func clear_cache():
    """
    Löscht den Cache
    """
    cached_armies.clear()

    var dir = Directory.new()
    if dir.open(CACHE_DIR) == OK:
        dir.list_dir_begin(true, true)
        var file_name = dir.get_next()

        while file_name != "":
            dir.remove(CACHE_DIR + file_name)
            file_name = dir.get_next()

        dir.list_dir_end()
```

### 7.6 Usage in a Scene

```gdscript
extends Control

onready var army_manager = $ArmyForgeManager
onready var status_label = $StatusLabel
onready var load_button = $LoadButton

func _ready():
    # Signals verbinden
    army_manager.connect("army_list_loaded", self, "_on_army_loaded")
    army_manager.connect("army_book_downloaded", self, "_on_book_downloaded")
    army_manager.connect("request_failed", self, "_on_request_failed")

    load_button.connect("pressed", self, "_on_load_button_pressed")

func _on_load_button_pressed():
    status_label.text = "Loading army..."
    # Army List abrufen
    army_manager.fetch_army_list("OLIsCH_xzKvU", "Wolf Prime Brothers")

func _on_army_loaded(army_data):
    status_label.text = "Army loaded successfully!"
    print("Army Name: ", army_data.get("name", "Unknown"))
    print("Points: ", army_data.get("points", 0))

    # Army-Daten verarbeiten
    display_army_units(army_data)

func _on_book_downloaded(pdf_path):
    status_label.text = "Army book downloaded to: " + pdf_path

func _on_request_failed(error_message):
    status_label.text = "Error: " + error_message
    push_error(error_message)

func display_army_units(army_data):
    if not army_data.has("units"):
        return

    for unit in army_data["units"]:
        print("Unit: %s | Q: %s | D: %s | Points: %d" % [
            unit.get("name", "Unknown"),
            unit.get("quality", "?"),
            unit.get("defense", "?"),
            unit.get("points", 0)
        ])
```

### 7.7 Data model classes

```gdscript
# ArmyUnit.gd
extends Resource
class_name ArmyUnit

export var unit_name: String
export var quality: String
export var defense: String
export var points: int
export var size: int = 1
export var special_rules: Array = []
export var weapons: Array = []

func from_dict(data: Dictionary) -> ArmyUnit:
    unit_name = data.get("name", "")
    quality = data.get("quality", "")
    defense = data.get("defense", "")
    points = data.get("points", 0)
    size = data.get("size", 1)
    special_rules = data.get("specialRules", [])

    if data.has("weapons"):
        for weapon_data in data["weapons"]:
            var weapon = ArmyWeapon.new()
            weapon.from_dict(weapon_data)
            weapons.append(weapon)

    return self

func to_dict() -> Dictionary:
    return {
        "name": unit_name,
        "quality": quality,
        "defense": defense,
        "points": points,
        "size": size,
        "specialRules": special_rules,
        "weapons": weapons.map(func(w): return w.to_dict())
    }

func get_total_points() -> int:
    return points * size
```

```gdscript
# ArmyWeapon.gd
extends Resource
class_name ArmyWeapon

export var weapon_name: String
export var attacks: int
export var armor_piercing: int = 0
export var range_value: int = 0
export var special_rules: Array = []

func from_dict(data: Dictionary) -> ArmyWeapon:
    weapon_name = data.get("name", "")
    attacks = data.get("attacks", 1)
    armor_piercing = data.get("ap", 0)
    range_value = data.get("range", 0)
    special_rules = data.get("specialRules", [])
    return self

func to_dict() -> Dictionary:
    return {
        "name": weapon_name,
        "attacks": attacks,
        "ap": armor_piercing,
        "range": range_value,
        "specialRules": special_rules
    }
```

```gdscript
# Army.gd
extends Resource
class_name Army

export var army_id: String
export var army_name: String
export var game_system: String
export var units: Array = []
export var points_limit: int = 0

func from_dict(data: Dictionary) -> Army:
    army_id = data.get("id", "")
    army_name = data.get("name", "")
    game_system = data.get("gameSystem", "")
    points_limit = data.get("pointsLimit", 0)

    if data.has("units"):
        for unit_data in data["units"]:
            var unit = ArmyUnit.new()
            unit.from_dict(unit_data)
            units.append(unit)

    return self

func get_total_points() -> int:
    var total = 0
    for unit in units:
        total += unit.get_total_points()
    return total

func is_valid() -> bool:
    return get_total_points() <= points_limit

func to_dict() -> Dictionary:
    return {
        "id": army_id,
        "name": army_name,
        "gameSystem": game_system,
        "pointsLimit": points_limit,
        "units": units.map(func(u): return u.to_dict())
    }
```

---

## 8. Best practices and recommendations

### 8.1 Error handling
```gdscript
func robust_http_request(url: String, max_retries: int = 3):
    var retries = 0

    while retries < max_retries:
        var error = http_request.request(url)

        if error == OK:
            return

        retries += 1
        yield(get_tree().create_timer(1.0), "timeout")  # 1 Sekunde warten

    emit_signal("request_failed", "Max retries exceeded")
```

### 8.2 Rate limiting
```gdscript
var last_request_time = 0
var min_request_interval = 1.0  # Mindestens 1 Sekunde zwischen Requests

func rate_limited_request(url: String):
    var current_time = OS.get_ticks_msec() / 1000.0
    var time_since_last = current_time - last_request_time

    if time_since_last < min_request_interval:
        yield(get_tree().create_timer(min_request_interval - time_since_last), "timeout")

    last_request_time = OS.get_ticks_msec() / 1000.0
    http_request.request(url)
```

### 8.3 Offline-first strategy
```gdscript
func fetch_army_with_fallback(army_id: String):
    # 1. Lokalen Cache prüfen
    if cached_armies.has(army_id):
        emit_signal("army_list_loaded", cached_armies[army_id])
        return

    # 2. Lokale Datei prüfen
    var local_path = "user://armies/%s.json" % army_id
    if File.new().file_exists(local_path):
        var army_data = load_local_army_data(local_path)
        if army_data:
            emit_signal("army_list_loaded", army_data)
            return

    # 3. Von Web abrufen
    fetch_army_list(army_id)
```

### 8.4 Android export note
```gdscript
# WICHTIG: Für Android-Export muss die INTERNET-Berechtigung aktiviert werden
# Project Settings -> Export -> Android -> Permissions -> Internet
```

---

## 9. Limitations and risks

### 9.1 No official API
- **Risk:** Endpoints can change without warning
- **Mitigation:** Versioning of your own integration, regular tests

### 9.2 Unknown rate limits
- **Risk:** Possible blocking when making too many requests
- **Mitigation:** Conservative request strategy (1-2 requests/second)

### 9.3 Data format changes
- **Risk:** The JSON structure can change
- **Mitigation:** Robust error handling, fallback values

### 9.4 Legal aspects
- **Note:** OnePageRules reserves all rights to their content
- **Recommendation:** Contact OPR for commercial use

---

## 10. Alternative approaches

### 10.1 Local copy of the opr-army-forge repository
**Advantages:**
- Full offline functionality
- No API dependencies
- Complete data structure available

**Disadvantages:**
- Manual updates required
- Larger project package

**Implementation:**
1. Clone `github.com/RobMayer/opr-army-forge`
2. Copy `public/definitions/` into your Godot project (`res://data/opr/`)
3. Load the JSON files with `load_local_definitions()`

### 10.2 Community tool integration
**Option:** Use `opr-af-to-tts` as middleware
- Parse Share Links with the tool
- Export JSON
- Import into Godot

### 10.3 Web scraping (NOT recommended)
**Warning:** Possibly violates the ToS
- Legally problematic
- Technically fragile
- Ethically questionable

---

## 11. Next steps

### For development:
1. ✅ Research complete
2. ⬜ Decision: Local data vs. HTTP requests
3. ⬜ Implementation of the base classes
4. ⬜ Testing with real data
5. ⬜ Error handling & edge cases
6. ⬜ UI integration

### Recommended approach:
**Hybrid solution:**
- Integrate a local copy of the definitions (from the GitHub repo)
- Implement optional online features (Share Links)
- Enable offline playability

---

## 12. Resources and links

### Official resources
- Army Forge: https://army-forge.onepagerules.com/
- Army Forge Studio: https://army-forge-studio.onepagerules.com/
- OnePageRules Website: https://www.onepagerules.com/
- OPR Forum: https://forum.onepagerules.com/

### Community projects
- GitHub - opr-army-forge: https://github.com/RobMayer/opr-army-forge
- GitHub - opr-af-to-tts: https://github.com/thomascgray/opr-af-to-tts
- OPR AF to TTS Tool: https://opr-af-to-tts.netlify.app/

### Godot documentation
- HTTPRequest Class: https://docs.godotengine.org/en/stable/classes/class_httprequest.html
- Making HTTP Requests: https://docs.godotengine.org/en/stable/tutorials/networking/http_request_class.html
- JSON Class: https://docs.godotengine.org/en/stable/classes/class_json.html

### Further reading
- OPR Community Wiki: https://wiki.onepagerules.com/
- OPR Discord: Available via the official website

---

## 13. Contact and support

**For API questions:**
- Contact OnePageRules directly via their website
- Use the OPR Discord for community support
- Open issues on GitHub for specific tool problems

**For this project:**
- See the project repository for issues and contributions

---

## Appendix A: Complete example project setup

### Directory structure
```
res://
├── scripts/
│   ├── army_forge/
│   │   ├── ArmyForgeManager.gd
│   │   ├── Army.gd
│   │   ├── ArmyUnit.gd
│   │   └── ArmyWeapon.gd
├── data/
│   ├── opr/
│   │   ├── definitions/
│   │   │   ├── grimdark_future.json
│   │   │   ├── age_of_fantasy.json
│   │   │   └── ...
│   └── cache/
└── scenes/
    ├── ArmyBuilder.tscn
    └── UnitCard.tscn
```

### Scene setup (ArmyBuilder.tscn)
```
ArmyBuilder (Control)
├── ArmyForgeManager (Node)
├── VBoxContainer
│   ├── HBoxContainer (Controls)
│   │   ├── LineEdit (ShareIDInput)
│   │   └── Button (LoadButton)
│   ├── Label (StatusLabel)
│   └── ScrollContainer
│       └── VBoxContainer (UnitsContainer)
```

---

## Appendix B: Common errors and solutions

### Error: "Connection failed"
**Cause:** No internet connection or server unreachable
**Solution:** Implement an offline fallback, check the connection before the request

### Error: "JSON Parse Error"
**Cause:** Unexpected data structure or empty response
**Solution:** Validate the response before parsing, use a try-catch-like structure

### Error: "HTTP 404"
**Cause:** Invalid army ID or changed endpoint
**Solution:** Validate IDs, implement versioning

### Error: "Android: Network blocked"
**Cause:** Missing INTERNET permission in the Android export
**Solution:** Enable in Project Settings -> Export -> Android -> Permissions

---

## Closing words

This research shows that integrating the OPR Army Forge data into a Godot project is **possible, but comes with limitations**. The combination of local data (from the open-source repository) and optional HTTP requests to identified endpoints offers the best balance between functionality and reliability.

**Key findings:**
1. No official API, but identifiable endpoints
2. Open-source data available (opr-army-forge repository)
3. Community tools demonstrate successful integration
4. Godot's HTTPRequest is well suited for the implementation
5. Hybrid approach (local + online) recommended

For questions or updates on this research, see the project repository.

---

**Document version:** 1.0
**Last update:** December 28, 2025
**Next review:** On API changes or community feedback
