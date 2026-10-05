class_name SpellHeroes
extends RefCounted
## Combat effects, the hero moments of a damage spell that worked: chain lightning (a lightning spell jumps caster ->
## target -> target as a thin flickering bolt) and, in the next step, a meteor (a fire spell drops a molten comet onto
## each target). Every random choice comes from the cast's seed.


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
