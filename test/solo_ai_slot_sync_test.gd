extends GdUnitTestSuite
## #673 co-op: the AI-slot designation sync — the wire shape (sorted player ids), the wholesale
## receive path, and the garbage a hostile or buggy sender must not crash on.

const MainScript := preload("res://scripts/main.gd")


func test_payload_is_sorted_player_ids() -> void:
	# The wire shape is an ARRAY of ids (JSON-safe over the command channel), sorted so the
	# message is deterministic and comparable between peers.
	assert_array(MainScript.ai_slots_sync_payload({3: true, 1: true})).is_equal([1, 3])
	assert_array(MainScript.ai_slots_sync_payload({2: true})).is_equal([2])


func test_payload_of_cleared_designation_is_empty() -> void:
	# A cleared designation propagates exactly like a set one — the same message shape, empty.
	assert_array(MainScript.ai_slots_sync_payload({})).is_equal([])


func test_payload_tolerates_string_keys() -> void:
	# solo_ai_slots keys can arrive back from serialization as strings; the payload normalizes.
	assert_array(MainScript.ai_slots_sync_payload({"3": true, 1: true})).is_equal([1, 3])


func test_apply_replaces_wholesale_and_clears_stale_entries() -> void:
	# The receive path CLEARS first: a local stale designation must not survive a sync that no
	# longer carries it.
	var target := {2: true}
	MainScript.apply_ai_slots_sync(target, [1, 3])
	assert_dict(target).is_equal({1: true, 3: true})
	MainScript.apply_ai_slots_sync(target, [])
	assert_dict(target).is_equal({})


func test_apply_drops_invalid_slot_ids() -> void:
	var target := {}
	MainScript.apply_ai_slots_sync(target, [2, 0, -1])
	assert_dict(target).is_equal({2: true})


func test_apply_mutates_the_live_dictionary_in_place() -> void:
	# main holds solo_ai_slots by reference — the applier must mutate it, not swap a copy in.
	var target := {2: true}
	var same: Dictionary = target
	MainScript.apply_ai_slots_sync(target, [3])
	assert_bool(same.has(3)).is_true()
	assert_bool(same.has(2)).is_false()
