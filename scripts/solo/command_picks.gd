class_name CommandPicks
extends RefCounted
## PICK-CHOICE (D-PICK, maintainer 27.11.): during deployment the owner of an AoF: Skirmish command-group unit picks the
## two friendly units its Banner / Musician reaches. A pick lands through the unit-property sync (the other table sees it)
## with one log line; battle start locks it (CR3 then fills only units the owner left without picks). Which units the
## command reaches in play is the core's (`command_picks` rides the profile); here are only the owner's two clicks.

const MAX_PICKS := 2


## Why `owner_unit` may not pick now ("" = it may): not a command group, not the deployment, or not this player's unit.
static func refusal(main, owner_unit: GameUnit) -> String:
	if owner_unit == null or not BattleSim.carries_command(owner_unit):
		return "only an AoF: Skirmish command group picks the units its command reaches"
	if main == null or main.opr_army_manager == null or not main.opr_army_manager.is_deployment_phase():
		return "command picks are chosen at deployment and stay for the battle"
	if main._solo_is_ai_unit(owner_unit) or not main._solo_i_own_unit(owner_unit):
		return "only %s's owner picks its command" % owner_unit.get_name()
	return ""


## Picks `pick` for `owner_unit`, or takes it back when it is already picked. Returns the battle-log line it said, or the
## refusal (toasted, nothing changes): another player's unit, the unit itself, a destroyed unit, or a third pick.
static func toggle(main, owner_unit: GameUnit, pick: GameUnit) -> String:
	var why := refusal(main, owner_unit)
	if why.is_empty() and (pick == null or pick == owner_unit or pick.get_alive_count() <= 0
			or int(pick.unit_properties.get("player_id", 0)) != int(owner_unit.unit_properties.get("player_id", 0))):
		why = "%s's command reaches only another living friendly unit" % owner_unit.get_name()
	var picks: Array = (owner_unit.unit_properties.get("command_picks", []) as Array).duplicate()
	if why.is_empty() and not picks.has(pick.unit_id) and picks.size() >= MAX_PICKS:
		why = "%s already reaches two units - take one back first" % owner_unit.get_name()
	if not why.is_empty():
		main._show_toast(why)
		return why
	if picks.has(pick.unit_id):
		picks.erase(pick.unit_id)
	else:
		picks.append(pick.unit_id)
	main._sync_unit_property(owner_unit, "command_picks", picks if not picks.is_empty() else null)
	var names := PackedStringArray(picks.map(func(k: String) -> String:
		var u: GameUnit = main.opr_army_manager.game_units.get(k)
		return u.get_name() if u != null else k))
	var line := "Command group: %s's command will reach %s (chosen)" % [owner_unit.get_name(), " and ".join(names)] \
		if not names.is_empty() else "Command group: %s's picks cleared - the two nearest at battle start" % owner_unit.get_name()
	main._log_rule_event(BattleLog.Category.GENERAL, line)
	return line


## PC2 (D-PICK Q1/Q2): the card's "Command picks" arms a pick on the table for `owner_unit`: every friendly living unit
## wears a pulse ring, the picked ones a solid ring; a click on one picks it or takes it back (the card stays on the
## owner). The card's "Done picking", a second press, or the battle start ends it.
static var picking: GameUnit = null
static var _rings: Array = []


static func begin(main, owner_unit: GameUnit) -> void:
	var why := refusal(main, owner_unit)
	if not why.is_empty():
		main._show_toast(why)
		return
	finish(main)
	picking = owner_unit
	_draw(main)
	main._show_toast("Click up to two friendly units for %s's command; click one again to take it back" % owner_unit.get_name())


static func finish(main) -> void:
	_clear_rings()
	var was := picking
	picking = null
	if was != null and main != null and main.unit_dock != null:
		main.unit_dock.refresh_presented()


## A table click while a pick is armed: a friendly candidate is picked or taken back and true comes back (the caller keeps
## the owner's card); anything else ends the pick (false: the click selects as usual). Battle start ends it too.
static func take_click(main, clicked: GameUnit) -> bool:
	if picking == null:
		return false
	if not refusal(main, picking).is_empty() or clicked == null or clicked == picking \
			or int(clicked.unit_properties.get("player_id", 0)) != int(picking.unit_properties.get("player_id", 0)):
		finish(main)
		return false
	toggle(main, picking, clicked)
	_draw(main)
	main.unit_dock.present_unit(picking)
	return true


static func _clear_rings() -> void:
	for r in _rings:
		if is_instance_valid(r):
			(r as Node).queue_free()
	_rings.clear()


static func _draw(main) -> void:
	_clear_rings()
	var picks: Array = picking.unit_properties.get("command_picks", [])
	for u in main.opr_army_manager.game_units.values():
		var gu := u as GameUnit
		if gu == picking or gu.get_alive_count() <= 0 \
				or int(gu.unit_properties.get("player_id", 0)) != int(picking.unit_properties.get("player_id", 0)):
			continue
		var at := Vector3.ZERO
		var n := 0
		for m in gu.get_alive_models():
			if (m as ModelInstance).node != null:
				at += (m as ModelInstance).node.global_position
				n += 1
		if n > 0:
			_rings.append(main._solo_spawn_picked_ring(at / n) if picks.has(gu.unit_id)
				else main._solo_spawn_pulse_ring(at / n, Color(1.0, 0.75, 0.2, 0.8)))
