extends GdUnitTestSuite
## PLAN H, H-18 (`EPOCH_94_PARITY_BATCH` = 94, lead decision 20.11.): a Versatile Attack pick (+1 to hit or AP(+1), once per
## activation) is made on the number the first eligible weapon really rolls at. The table reads the MODIFIED to-hit (Stealth, Evasive, Artillery
## on the target; Artillery, Good Shot, the Unpredictable die on the shooter), the core latched it before the dice on the plain Quality. Q4 AP(1) at Defense 3+: plain, the
## two modes tie and the tie goes to AP(+1); at 5+ (the target's minus) the hit mode wins. From 94 the core's dice decide on the modified number.
## Real: the main scene, NmlCore, the importer's unit builder, the table's AI body. Constructed: the units.
## The table arm left with the AI table resolver; door values are snapshot pins read on main df2284f38 (docs/adr/0005-snapshot-pins.md).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://versatile_pick_dice"
const SEEDS := 16
const PENDING_EPOCH := 94
const PICK := "COMBAT|Versatile Attack:"

## The door's pick line per seed, read on main (where the table still shoots and equals the door).
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_TARGET_STEALTH := [
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_TARGET_EVASIVE := [
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_TARGET_ARTILLERY := [
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"],
	["COMBAT|Versatile Attack: Pickers picks +1 to hit for this activation"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_SHOOTER_PLUS := [
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"]]
# Snapshot pin: read from the rules core on main, not derived from the rulebook (docs/adr/0005-snapshot-pins.md).
const WANT_PLAIN := [
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"],
	["COMBAT|Versatile Attack: Pickers picks AP(+1) for this activation"]]

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before := 0


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Five Versatile shooters, one rifle each at `ap`; `rules` rides the unit (the unit's own Artillery for the shooter-side case).
func _shooter(quality: int, ap: int, rules := [], system := "gf", faction := "battle_brothers", versatile := "Versatile Attack") -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Pickers"
	ou.size = 5
	ou.quality = quality
	ou.defense = 4
	ou.game_system = system
	ou.special_rules.assign([versatile] + rules)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 2
	w.count = 5
	w.special_rules.assign(["AP(%d)" % ap])
	ou.weapons.append(w)
	return {"unit": ou, "faction": faction, "system": system}


func _target(rules: Array, system := "gf", faction := "battle_brothers") -> Dictionary:
	var ou := OPRApiClient.OPRUnit.new()
	ou.name = "Targets"
	ou.size = 10
	ou.quality = 4
	ou.defense = 3
	ou.game_system = system
	ou.special_rules.assign(rules)
	return {"unit": ou, "faction": faction, "system": system}


func _faces(rolls: Array) -> Array:
	return rolls.map(func(r: Dictionary) -> String: return "%s:%d:%s" % [r["kind"], int(r["count"]), r["faces"]])


## EVERY battle-log line of the volley (H-18 lift: the door says what the table says), in a stable order.
func _sorted(lines: Array) -> Array:
	var out := lines.duplicate()
	out.sort()
	return out


func _picks(lines: Array) -> Array:
	return lines.filter(func(l: String) -> bool: return l.begins_with(PICK))


## The door's pick lines at `epoch`, per seed, against the pinned values.
func _picks_door(shooter: Dictionary, target: Dictionary, epoch: int, want: Array) -> void:
	AiActRecorder.rules_epoch = epoch
	var dice := ProjectSettings.globalize_path(DICE)
	var got: Array = []
	var fired := 0
	for s in SEEDS:
		var door := await RosterSweep.volley(_main, shooter, target, s, true, dice)
		var picks := _picks(door["lines"])
		got.append(picks)
		fired += 1 if not picks.is_empty() else 0
	assert_int(fired).override_failure_message("the door never made a pick, nothing is pinned").is_equal(SEEDS)
	assert_array(got).override_failure_message("the door's pick line moved from the pinned values").is_equal(want)


## The target's to-hit minus moves the door's pick to the hit mode on the modified number.
func test_a_to_hit_minus_on_the_target_moves_the_pick_in_both_halves_from_94() -> void:
	var rules := ["Stealth", "Evasive", "Artillery"]
	var want := [WANT_TARGET_STEALTH, WANT_TARGET_EVASIVE, WANT_TARGET_ARTILLERY]
	for i in rules.size():
		await _picks_door(_shooter(4, 1), _target([rules[i]]), PENDING_EPOCH, want[i])


## The shooter's own plus: Artillery (held, target over 12") makes Quality 5 a 4+, where the plain 5+ picks the hit mode and the 4+ picks AP(+1).
func test_the_shooters_own_to_hit_plus_moves_the_pick_in_both_halves_from_94() -> void:
	await _picks_door(_shooter(5, 1, ["Artillery"]), _target([]), PENDING_EPOCH, WANT_SHOOTER_PLUS)


## Control: a target without a to-hit rule, the plain Quality IS the rolled number.
func test_a_plain_target_picks_alike_at_both_epochs() -> void:
	await _picks_door(_shooter(4, 1), _target([]), PENDING_EPOCH, WANT_PLAIN)
