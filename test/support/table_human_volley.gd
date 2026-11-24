class_name TableHumanVolley
## Test facade: the GDScript table's own human volley, run the way the window door ran it before a shot the rules core cannot
## resolve became a free dice roll. The reference arm of the door-vs-table compare suites while the table resolver still
## exists; production no longer reaches it. Kept here so the private-access gate counts these accesses once.


## One table volley of `att` at `foe` and the activation's end, as `_run_human_attack` did on a refused door.
static func shoot(main: Node, att: GameUnit, foe: GameUnit) -> void:
	await main.begin_activation(att)
	main._solo_log_unmodeled_rules(att)
	main._solo_log_unmodeled_rules(foe)
	CoreActivation.note_legacy(main, "human_shoot", att, [foe])
	await main._run_human_shooting(att, foe)
	att.unit_properties["shot_round"] = main.opr_army_manager.current_round
	main.human_attack_resolved.emit(att, false)
	await main._solo_complete_human_attack(att)
	CoreActivation.close_session(main, att.unit_id)
