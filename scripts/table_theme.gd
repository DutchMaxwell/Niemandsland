class_name TableTheme
extends RefCounted
## A one-click table theme (S5, maintainer 05.10.): the biome, the mood and the free shelf pieces of a whole table,
## kept as data in res://assets/themes/<id>.json. Piece positions are inches from the table centre and the yaw is in
## degrees, the frame the save files use for free pieces.

const DIR := "res://assets/themes"
const IN2M := 0.0254

var id: String = ""
var label: String = ""
var table_feet := Vector2.ZERO
var biome: String = ""
var mood: String = ""
var pieces: Array[Dictionary] = []   # {prop_id, kind, position: Vector3 metres (y 0), yaw_deg}


static func load_theme(theme_id: String) -> TableTheme:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(theme_id + ".json")))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[Theme] cannot read theme '%s'" % theme_id)
		return null
	var t := TableTheme.new()
	t.id = theme_id
	t.label = str(data.get("label", theme_id))
	var feet: Array = data.get("table_feet", [0, 0])
	t.table_feet = Vector2(float(feet[0]), float(feet[1]))
	t.biome = str(data.get("biome", ""))
	t.mood = str(data.get("mood", ""))
	for p: Dictionary in data.get("pieces", []):
		t.pieces.append({"prop_id": str(p["prop_id"]), "kind": int(p["kind"]),
			"position": Vector3(float(p["x_in"]), 0.0, float(p["z_in"])) * IN2M, "yaw_deg": float(p["yaw_deg"])})
	return t


## The theme is laid out for one table size; on any other the entry stays greyed out (D11).
func fits(size_feet: Vector2) -> bool:
	return size_feet.is_equal_approx(table_feet)
