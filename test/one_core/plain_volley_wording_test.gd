extends GdUnitTestSuite
## One core P3 step 23: pins, byte for byte, the battle-log lines the TABLE writes for one plain volley, so steps 24-26
## can make the Rust core print the same sentences. Layout = test/parity/scenarios/shoot/plain.json (10 Att models with
## a Rifle 24" A1 vs 10 Def models 8" away, no rules). The volley runs through main's real _solo_resolve_ai_volley the
## way the parity gate drives it (test/parity/parity_table.gd): the target holds the AI seat, so its saves roll without
## a prompt. The rules epoch is the live one (AiActRecorder.rules_epoch), so a wording change that rides an epoch bump
## turns this red too. Pinned per seed: every entry the volley adds, in order, as "<CATEGORY>|<text>".
## Not pinned: the `ai` flag, the `detail` text, the prompt path of a human-seat target, a volley with no hit (seed
## 225 stops after the hit line) and the singular "1 block".

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const SCENARIO := "res://test/parity/scenarios/shoot/plain.json"

## seed -> the volley's battle-log lines, "<CATEGORY>|<text>", in log order (found over seeds 0-399 at epoch 75).
const PINNED := {
	0: [   # plural counts, half strength, the morale test fails
		"COMBAT|Att fires at Def",
		"COMBAT|AI (Att): 6 6 6 6 6 4 4 3 1 1 → 7 hits (4+)",
		"COMBAT|Att fires Rifle at Def — 7 hits",
		"COMBAT|Def saves on 4+",
		"COMBAT|AI (Def) defends: 5 4 2 2 2 2 1 → 2 blocks (4+)",
		"COMBAT|Def takes 5 wounds (5/10)",
		"COMBAT|Def loses 5 models (5/10)",
		"COMBAT|AI (Def): 3 → 0 hits (4+)",
		"COMBAT|Def fails morale — Shaken",
	],
	57: [   # no save holds, the morale test passes
		"COMBAT|Att fires at Def",
		"COMBAT|AI (Att): 6 6 5 5 5 5 4 3 2 1 → 7 hits (4+)",
		"COMBAT|Att fires Rifle at Def — 7 hits",
		"COMBAT|Def saves on 4+",
		"COMBAT|AI (Def) defends: 3 2 2 2 1 1 1 → 0 blocks (4+)",
		"COMBAT|Def takes 7 wounds (3/10)",
		"COMBAT|Def loses 7 models (3/10)",
		"COMBAT|AI (Def): 6 → 1 hit (4+)",
		"COMBAT|Def passes morale",
	],
	49: [   # the singular forms: one hit, one wound, a model
		"COMBAT|Att fires at Def",
		"COMBAT|AI (Att): 5 3 3 3 2 2 2 1 1 1 → 1 hit (4+)",
		"COMBAT|Att fires Rifle at Def — 1 hit",
		"COMBAT|Def saves on 4+",
		"COMBAT|AI (Def) defends: 1 → 0 blocks (4+)",
		"COMBAT|Def takes 1 wound (9/10)",
		"COMBAT|Def loses a model (9/10)",
	],
}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## One seeded volley of the scenario (ParityTable.run's plain path); returns the entries it added to the battle log.
func _volley_lines(sc: Dictionary, seed_value: int) -> Array:
	var weapon: Dictionary = sc["weapon"]
	var att: GameUnit = ParityTable._make_unit(_main, sc["attacker"], weapon)
	var dfn: GameUnit = ParityTable._make_unit(_main, sc["defender"], {})
	_main.seed_tray_rng(seed_value)
	var dist_in := float(sc["defender"]["x_in"]) - float(sc["attacker"]["x_in"])   # same z steps: the closest pair
	var wobj: OPRApiClient.OPRWeapon = (att.source_data as OPRApiClient.OPRUnit).weapons[0]
	var plist: Array = AiShooting.profiles_in_range([wobj], dist_in)
	for p in plist:
		_main._solo_stamp_unit_shred(p, att, int(weapon["range_in"]))
	var shots: Array = []
	for p in AiEv.stamp_sergeant(plist, att):
		shots.append({"member": att, "quality": int(sc["attacker"]["quality"]), "alive": att.get_alive_count(),
			"max": att.models.size(), "reach": float(weapon["range_in"]), "profile": p})
	var got: Array = []
	var on_entry := func(e: Dictionary) -> void:
		got.append("%s|%s" % [BattleLog.Category.keys()[int(e["category"])], str(e["text"])])
	_main.battle_log.entry_added.connect(on_entry)
	await _main._solo_resolve_ai_volley(att, dfn, shots)
	_main.battle_log.entry_added.disconnect(on_entry)
	for u in [att, dfn]:
		_main.opr_army_manager.game_units.erase((u as GameUnit).unit_id)
		for m in (u as GameUnit).models:
			var nd: Node = (m as ModelInstance).node
			if nd != null and is_instance_valid(nd):
				nd.free()
	await _main.get_tree().process_frame
	return got


func test_a_plain_volley_writes_the_pinned_lines() -> void:
	var sc := JSON.parse_string(FileAccess.get_file_as_string(SCENARIO)) as Dictionary
	for s in PINNED:
		print("PLAIN_VOLLEY_WORDING seed=%d epoch=%d start" % [s, AiActRecorder.rules_epoch])
		var got := await _volley_lines(sc, int(s))
		print("PLAIN_VOLLEY_WORDING seed=%d lines=%s" % [s, JSON.stringify(got)])
		assert_array(got).override_failure_message("seed %d: the table's plain-volley wording changed\n got %s\nwant %s" % [
			s, JSON.stringify(got), JSON.stringify(PINNED[s])]).is_equal(PINNED[s])
