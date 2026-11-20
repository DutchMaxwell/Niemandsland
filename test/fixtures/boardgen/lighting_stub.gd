extends RefCounted
## A lighting controller stand-in that records the setters the dusk of the ruin town calls.

var calls := {}


func set_sun_color(v: Color) -> void: calls["set_sun_color"] = v
func set_sun_energy(v: float) -> void: calls["set_sun_energy"] = v
func set_sun_angles(h: float, v: float) -> void: calls["set_sun_angles"] = [h, v]
func set_ambient_color(v: Color) -> void: calls["set_ambient_color"] = v
func set_ambient_energy(v: float) -> void: calls["set_ambient_energy"] = v
func set_exposure(v: float) -> void: calls["set_exposure"] = v
func set_fill_light_color(v: Color) -> void: calls["set_fill_light_color"] = v
func set_fill_light_energy(v: float) -> void: calls["set_fill_light_energy"] = v
