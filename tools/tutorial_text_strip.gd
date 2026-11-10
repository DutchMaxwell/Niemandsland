extends RefCounted
## Strips third-party rule text from a serialized table (SaveManager.serialize_game_state shape): the
## session rule-description map (top level and per unit) is emptied and every spell loses its `effect`
## text (name + threshold stay). The two board builders call this before a table is written, so a
## rebuilt tutorial board cannot bring the text back; the game fills these from the army book at runtime.
## Returns the number of characters removed (0 when there was nothing to strip).


static func strip_state(state: Dictionary) -> int:
	var removed := _empty_map(state)
	for u in state.get("game_units", []):
		if u is Dictionary and u.get("unit_properties") is Dictionary:
			removed += _empty_map(u["unit_properties"])
	var spells: Variant = state.get("player_spells", {})
	if spells is Dictionary:
		for pid in spells:
			if not (spells[pid] is Array):
				continue
			for sp in spells[pid]:
				if sp is Dictionary and sp.has("effect"):
					removed += str(sp["effect"]).length()
					sp.erase("effect")
	return removed


static func _empty_map(holder: Dictionary) -> int:
	var m: Variant = holder.get("rule_descriptions")
	if not (m is Dictionary):
		return 0
	var n := 0
	for k in m:
		n += str(m[k]).length()
	(m as Dictionary).clear()
	return n
