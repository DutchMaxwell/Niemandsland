extends RefCounted
## A lighting controller stand-in that records the setters the dusk of the ruin town calls.

var calls := {}
var _directional_light: DirectionalLight3D
var _fill_light: DirectionalLight3D   # the scene's fill light, turned by hand by dusk()


func set_sun_color(v: Color) -> void: calls["set_sun_color"] = v
func set_sun_energy(v: float) -> void: calls["set_sun_energy"] = v
func set_sun_angles(h: float, v: float) -> void: calls["set_sun_angles"] = [h, v]
func set_ambient_color(v: Color) -> void: calls["set_ambient_color"] = v
func set_ambient_energy(v: float) -> void: calls["set_ambient_energy"] = v
func set_exposure(v: float) -> void: calls["set_exposure"] = v
func set_fill_light_color(v: Color) -> void: calls["set_fill_light_color"] = v
func set_fill_light_energy(v: float) -> void: calls["set_fill_light_energy"] = v
func set_ssao_radius(v: float) -> void: calls["set_ssao_radius"] = v
func set_ssao_intensity(v: float) -> void: calls["set_ssao_intensity"] = v
func set_sdfgi_energy(v: float) -> void: calls["set_sdfgi_energy"] = v
func set_ssil_intensity(v: float) -> void: calls["set_ssil_intensity"] = v
