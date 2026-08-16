extends GdUnitTestSuite
## PARITY: the clone scores in GDScript exactly what torch scored in training.
## The fixture carries RANDOM weights on purpose — this proves the maths, not
## the policy. A drifted implementation would steer real games with a
## different brain, so the loader refuses a net whose selftest disagrees.

const FIXTURE := "res://test/data/clone_parity.json"


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Dictionary


func test_gdscript_scores_match_torch_to_1e_minus_4() -> void:
	var net := _fixture()
	var st: Dictionary = net["selftest"]
	var got := AiClone.scores(net, st["board"], int(st["side"]), st["menu"])
	assert_int(got.size()).is_equal((st["expected"] as Array).size())
	for i in range(got.size()):
		assert_float(float(got[i])).is_equal_approx(float((st["expected"] as Array)[i]), 1e-4)


func test_a_drifted_net_is_refused() -> void:
	var net := _fixture()
	assert_bool(AiClone.selftest_ok(net)).is_true()
	var bent := net.duplicate(true)
	var b: Array = bent["head_b1"]
	b[0] = float(b[0]) + 1.0        # one nudged bias = a different brain
	bent["head_b1"] = b
	assert_bool(AiClone.selftest_ok(bent)).is_false()


func test_menu_tuples_speak_the_trainer_s_language() -> void:
	var st: Dictionary = _fixture()["selftest"]
	var a: Dictionary = (st["menu"] as Array)[0]
	var v := AiClone.action_vec(a, (st["board"] as Array).size())
	assert_int(v.size()).is_equal(10)
	assert_float(float(v[int(a["kind"])])).is_equal(1.0)
	assert_float(float(v[5])).is_equal_approx(float(a["dest_x"]) / 36.0, 1e-6)
	assert_float(float(v[7])).is_equal(1.0 if int(a["victim_row"]) >= 0 else 0.0)
