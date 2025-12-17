extends Node3D
## Mixin script for selectable objects
## Provides selection highlight functionality

var _is_selected: bool = false


func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_highlight()


func is_selected() -> bool:
	return _is_selected


func _update_highlight() -> void:
	var material = get_meta("model_material") if has_meta("model_material") else null
	var original_color = get_meta("original_color") if has_meta("original_color") else Color.WHITE

	if material and material is StandardMaterial3D:
		if _is_selected:
			# Highlight: brighter version of original color
			material.albedo_color = original_color.lightened(0.3)
			material.emission_enabled = true
			material.emission = original_color
			material.emission_energy_multiplier = 0.5
		else:
			# Restore original
			material.albedo_color = original_color
			material.emission_enabled = false
