class_name SpellImpacts
extends RefCounted
## Combat effects: a successful spell's release at its resolved targets, per element (SpellLook): lightning jumps as
## chain lightning, fire drops a meteor and a ring, frost sends a cold wave and grows ice prisms, shadow sends a strand
## and closes a vortex of nested spirals, arcane braids a stream into a rising spiral. Pictures only: they never
## allocate wounds or infer a hit result.


static func release(host: Node3D, from: Vector3, targets: Array, element: int, s: int, preset: int) -> void:
	if element == SpellLook.Element.LIGHTNING:
		SpellHeroes.chain_lightning(host, from, targets, s, preset)
		return
	for i in targets.size():
		var at: Vector3 = targets[i]
		var seed_i := s + 31 * (i + 1)
		var tint: Color = SpellLook.TINTS[element]
		match element:
			SpellLook.Element.FIRE:
				SpellHeroes.meteor(host, at, seed_i, preset, func() -> void:
					SpellForms.ripple(host, at, tint, 0.095))
			SpellLook.Element.FROST:
				SpellForms.stream(host, from, at, tint, seed_i, 2)
				_delayed(host, 0.32, func() -> void:
					SpellForms.crystals(host, at - Vector3.UP * 0.025, seed_i, 11 if preset == 2 else 16)
					SpellForms.ripple(host, at - Vector3.UP * 0.022, tint, 0.09)
					FxBurst.spawn(host, FxBurst.Look.FROST, at, Vector3.ZERO, 20, seed_i, preset, 1.2,
						Color(0.5, 0.7, 0.85), true))
			SpellLook.Element.SHADOW:
				SpellForms.stream(host, from, at, tint, seed_i, 1)
				_delayed(host, 0.3, func() -> void: _vortex(host, at, seed_i, preset))
			_:
				SpellForms.stream(host, from, at, tint, seed_i, 3)
				_delayed(host, 0.34, func() -> void:
					var spiral := SpellForms.curl(host, 0.04, 0.095, 2.1, 0.003, tint, float(posmod(seed_i, 628)) * 0.01)
					spiral.global_position = at - Vector3.UP * 0.025
					spiral.create_tween().tween_property(spiral, "rotation:y", 1.8, 0.7)
					SpellForms.retire(spiral, 0.25, 0.55)
					SpellForms.ripple(host, at, Color(1.6, 1.15, 0.45), 0.07)
					FxBurst.spawn(host, FxBurst.Look.MOTE, at, Vector3.UP, 18, seed_i, preset, 1.0,
						Color(0.55, 0.65, 0.7)))


static func _delayed(host: Node3D, delay_s: float, action: Callable) -> void:
	var tw := host.create_tween()
	tw.tween_interval(delay_s)
	tw.tween_callback(action)


static func _vortex(host: Node3D, at: Vector3, s: int, preset: int) -> void:
	var vortex := Node3D.new()
	vortex.name = "ShadowVortex"
	host.add_child(vortex)
	vortex.global_position = at - Vector3.UP * 0.025
	# Three nested continuous spirals, dark smoke between them; no cut-out crescent or symbolic silhouette.
	for i in 3:
		var curl := SpellForms.curl(vortex, 0.034 + 0.012 * i, 0.085 - 0.018 * i, 1.35,
			0.004, Color(0.65, 0.15, 1.0, 0.8), float(i) * 2.1)
		curl.rotation.y = float(posmod(s, 628)) * 0.01
	var tw := vortex.create_tween().set_parallel()
	tw.tween_property(vortex, "rotation:y", -2.4, 0.9)
	tw.tween_property(vortex, "scale", Vector3(0.08, 1.4, 0.08), 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	SpellForms.ripple(host, at, Color(0.85, 0.22, 1.4), 0.085, true)
	FxBurst.spawn(vortex, FxBurst.Look.WISP, at, Vector3.UP, 22, s, preset, 1.6)
	SpellForms.retire(vortex, 0.55, 0.5)
