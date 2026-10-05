class_name InterferenceDialog
extends CanvasLayer
## ONE modal tableau for spending spell tokens against an enemy cast (maintainer 2026-07-22: the
## old per-token Yes/No ConfirmationDialog loop). +/- selects the token count, a live line shows
## how the spend shifts the AI's cast roll BEFORE confirming; Confirm/No resolve the await.
## Code-built (no scene), awaitable via ask(); the preview line is a pure static for tests.

var _count := 0
var _pool := 0
var _base_target := 4
var _boost := 0
var _count_label: Label = null
var _preview_label: Label = null
var _mode := "interfere"   # "interfere" (against an enemy cast) | "boost" (the player's own cast)


## PURE: the live preview line — target before/after the interference, with success odds.
static func format_preview(base_target: int, boost: int, interference: int) -> String:
	var before := AiSpell.cast_target(boost, 0, base_target)
	var after := AiSpell.cast_target(boost, interference, base_target)
	return "Cast roll: %d+ → %d+   (success %d%% → %d%%)" % [before, after,
		roundi(AiSpell.cast_success_chance(boost, 0, base_target) * 100.0),
		roundi(AiSpell.cast_success_chance(boost, interference, base_target) * 100.0)]


## PURE: the spot-marker preview (Spotter UX, maintainer 31.07.) — markers removed = +X to hit.
static func format_preview_spot(count: int) -> String:
	return "+%d to hit on this volley" % count if count > 0 else "no bonus — markers stay on the target"


## PURE: the boost-side preview (spell wave F2) — the player's own cast improving with tokens.
static func format_preview_boost(base_target: int, interference: int, boost: int) -> String:
	var before := AiSpell.cast_target(0, interference, base_target)
	var after := AiSpell.cast_target(boost, interference, base_target)
	return "Cast roll: %d+ → %d+   (success %d%% → %d%%)" % [before, after,
		roundi(AiSpell.cast_success_chance(0, interference, base_target) * 100.0),
		roundi(AiSpell.cast_success_chance(boost, interference, base_target) * 100.0)]


## Modal ask: returns the number of tokens the player commits (0 = no interference).
func ask(caster_name: String, spell_name: String, target_label: String,
		base_target: int, boost: int, pool: int, mode: String = "interfere") -> int:
	_mode = mode
	_pool = maxi(0, pool)
	_base_target = base_target
	_boost = boost
	_count = 0
	var info := ""
	if _mode == "interfere":
		info = "%s is casting %s at %s.\nSpell tokens in 18\" line of sight: %d — each spent token gives -1 to the cast roll." % [
			caster_name, spell_name, target_label, _pool]
	elif _mode == "spot":
		# Spotter UX (maintainer 31.07.): removing the target's spot markers is the ATTACKER's
		# choice, caster-points style — each removed marker is +1 to hit this volley.
		info = "%s attacks %s.\nSpot markers on the target: %d — each removed marker gives +1 to hit this volley." % [
			caster_name, target_label, _pool]
	else:
		info = "%s casts %s at %s.\nFriendly spell tokens in 18\" line of sight: %d — each spent token gives +1 to the cast roll." % [
			caster_name, spell_name, target_label, _pool]
	# On the house card (PromptCard, maintainer D98 = a): the stepper, then the live preview line.
	var card := PromptCard.new("Enemy spell!" if _mode == "interfere" \
		else ("Spotted target!" if _mode == "spot" else "Boost your cast?"), info, "OK",
		"No interference" if _mode == "interfere" else ("Leave markers" if _mode == "spot" else "No boost"))
	card.cancel_value = 0
	_count_label = HouseStyle.label("", HouseStyle.VALUE)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.rows.add_child(HouseStyle.stepper([-1, 1], _count_label,
		func(delta: int) -> void: _set_count(_count + delta, card), "Count", true))
	_preview_label = HouseStyle.label("", HouseStyle.NOTE)
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.rows.add_child(_preview_label)
	_set_count(mini(1, _pool), card)   # sensible default: 1 token pre-selected when available
	add_child(card)
	var result: int = await card.answer(0)
	queue_free()
	return result


func _set_count(v: int, card: PromptCard) -> void:
	_count = clampi(v, 0, _pool)
	card.ok_value = _count
	if _count_label != null:
		_count_label.text = "%d %s" % [_count, ("marker" if _count == 1 else "markers") if _mode == "spot" \
			else ("token" if _count == 1 else "tokens")]
	if _preview_label != null:
		if _mode == "interfere":
			_preview_label.text = format_preview(_base_target, _boost, _count)
		elif _mode == "spot":
			_preview_label.text = format_preview_spot(_count)
		else:
			_preview_label.text = format_preview_boost(_base_target, _boost, _count)
	var ok := card.ok_button
	if ok != null:
		if _mode == "interfere":
			ok.text = "Interfere (-%d)" % _count if _count > 0 else "Confirm (no tokens)"
		elif _mode == "spot":
			ok.text = "Remove %d (+%d to hit)" % [_count, _count] if _count > 0 else "Attack without markers"
		else:
			ok.text = "Boost (+%d)" % _count if _count > 0 else "Cast without boost"
