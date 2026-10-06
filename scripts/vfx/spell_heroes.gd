class_name SpellHeroes
extends RefCounted
## Combat effects, the hero moments of a damage spell that worked: chain lightning (a lightning spell jumps caster ->
## target -> target as a thin flickering bolt) and a meteor (a fire spell drops a molten comet with a braided trail
## onto each target). Every random choice comes from the cast's seed.


## A thin chain connects the actual targets; its small impact rings do not hide their miniatures.
static func chain_lightning(host: Node3D, from: Vector3, targets: Array, s: int, p: int) -> void:
	var holder := Node3D.new()
	host.add_child(holder)
	var tw := holder.create_tween()
	for flicker in 3:
		tw.tween_callback(func() -> void:
			for c in holder.get_children():
				c.queue_free()
			var a := from
			for i in targets.size():
				FxBolt.jag(holder, a, targets[i], s + flicker * 101 + i * 13, 0.00075, 0.018)
				a = targets[i])
		tw.tween_interval(0.09)
	for i in targets.size():
		SpellForms.ripple(host, targets[i], Color(0.5, 1.2, 2.0), 0.06)
		FxBurst.spawn(host, FxBurst.Look.FROST, targets[i], Vector3.UP, 14, s + i, p, 1.4,
			Color(0.4, 0.7, 0.95))
	tw.tween_interval(0.13)
	tw.tween_callback(holder.queue_free)


## A molten comet and a curved, tapered trail; a brief impact blooms into embers and a smoke ring.
static func meteor(host: Node3D, at: Vector3, s: int, p: int, on_impact: Callable) -> void:
	var sky := at + Vector3(-0.14, 0.32, -0.09)
	var rock := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.01
	sphere.height = 0.02
	sphere.radial_segments = 12
	sphere.rings = 6
	rock.mesh = sphere
	rock.material_override = SpellForms.material(Color(2.3, 0.7, 0.12), true)
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(rock)
	rock.global_position = sky
	SpellForms.stream(host, sky, at, Color(2.0, 0.55, 0.08), s, 2)
	var tw := rock.create_tween()
	tw.tween_property(rock, "global_position", at, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		FxBurst.spawn(host, FxBurst.Look.EMBER, at, Vector3.UP, 32, s + 1, p, 1.2)
		FxBurst.spawn(host, FxBurst.Look.PUFF, at, Vector3.UP, 12, s + 2, p, 1.3, Color(0.4, 0.32, 0.27))
		FxBurst.spawn(host, FxBurst.Look.PUFF, at - Vector3.UP * 0.02, Vector3.ZERO, 16, s + 3, p, 1.3,
			Color(0.7, 0.45, 0.25), true)
		if on_impact.is_valid():
			on_impact.call()
		rock.queue_free())
