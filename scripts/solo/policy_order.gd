class_name PolicyOrder
extends RefCounted
## NML-1158b step 6 — the GDScript twin of `core/nml-core/src/policy.rs`'s
## `PolicyNet`/`Policy::score_menu`: the `netlab/policy_train.py` export
## (schema `policy_net/1`), loaded and forwarded so the table and the twin
## re-rank a unit's own menu identically (design §7 step 7's identity gate).
##
## This is NOT `AiClone` (the REFUSED playout-net seam, #475 — clone_train's
## `row_w1`/pooled-embedding forward): a different net, a different schema, a
## different caller. It only ever feeds `AiPlanner._reorder_within_unit`
## (PHASE 2 of `plan_with_rollout`); the rollout policy is untouched.
##
## `menu_tuples`/`action_vec`/`extras_for` are `AiClone`'s own — pure board
## geometry, already reused by `tools/policy_dump.gd` (step 1) for the same
## reason: one source for "where does this move end", not a second copy.

const SCHEMA := "policy_net/1"
const PHI_FIXED := 22   # `state_phi`'s per-pool column count (policy.rs:406)

static var _net: Dictionary = {}
static var _tried := false


## Loaded once from NML_POLICY_PATH; {} = no net, `_reorder_within_unit` no-ops.
static func net() -> Dictionary:
	if not _tried:
		_tried = true
		var path := OS.get_environment("NML_POLICY_PATH").strip_edges()
		if path != "":
			_net = load_net(path)
	return _net


## Test seam: install weights without touching the environment.
static func set_net(n: Dictionary) -> void:
	_net = n
	_tried = true


static func load_net(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or str((parsed as Dictionary).get("schema", "")) != SCHEMA:
		printerr("[POLICY_ORDER] FATAL: no %s net at '%s'" % [SCHEMA, path])
		return {}
	if not selftest_ok(parsed as Dictionary):
		printerr("[POLICY_ORDER] FATAL: policy selftest FAILED — refusing to order with a drifted net")
		return {}
	return parsed


## Same bar `AiClone.score_close`/`policy.rs`'s loader gate: a drifted net
## must not silently steer the pool.
static func selftest_ok(net_in: Dictionary) -> bool:
	var st: Dictionary = net_in.get("selftest", {})
	if st.is_empty():
		return false
	var phi: Array = st.get("phi", [])
	var vecs: Array = st.get("vecs", [])
	var expected: Array = st.get("expected", [])
	if vecs.size() != expected.size():
		return false
	for i in range(vecs.size()):
		var got := logit(net_in, phi, vecs[i])
		var want := float(expected[i])
		if absf(got - want) > 1e-4 + absf(want) * 1e-6:
			return false
	return true


## `state_phi` policy.rs:395-411 / policy_train.py:50-70 — three pooled
## row embeddings (marker/mine/theirs) + their row shares + a ZERO actor
## block + the side one-hot. `Policy::score_menu` always calls the Rust twin
## with `actor_row = -1` (the trainer's BUG-COMPATIBLE recovery, policy.rs
## :385-390 pins it), so this twin skips the actor-row branch entirely
## instead of carrying dead code for a value that is never anything else.
static func state_phi(board: Array, side: int) -> Array:
	var pools: Array = []
	for _p in range(3):
		var z: Array = []
		z.resize(PHI_FIXED)
		z.fill(0.0)
		pools.append(z)
	var n := [0.0, 0.0, 0.0]
	for r in board:
		var row: Array = r
		var c0 := int(float(row[0]))
		var p := 0 if c0 == 3 else (1 if c0 == side else 2)
		for j in range(mini(PHI_FIXED, row.size())):
			(pools[p] as Array)[j] += float(row[j])
		n[p] += 1.0
	var phi: Array = []
	for p in range(3):
		for j in range(PHI_FIXED):
			phi.append(float((pools[p] as Array)[j]) / maxf(float(n[p]), 1.0))
	var total := maxf(float(board.size()), 1.0)
	for c in n:
		phi.append(float(c) / total)
	for _j in range(PHI_FIXED):
		phi.append(0.0)
	phi.append(1.0 if side == 1 else 0.0)
	phi.append(1.0 if side == 2 else 0.0)
	return phi


## One candidate logit — `PolicyNet::logit` policy.rs:117-127: `b2` first,
## `w2` accumulates over `relu(w1·[phi;vec] + b1)`, same order the trainer's
## export and `AiClone.scores` both add in.
static func logit(net_in: Dictionary, phi: Array, vec: Array) -> float:
	var w1: Array = net_in["w1"]
	var b1: Array = net_in["b1"]
	var w2: Array = net_in["w2"]
	var z := float(net_in["b2"])
	for j in range(b1.size()):
		var acc := float(b1[j])
		for i in range(phi.size()):
			acc += float(phi[i]) * float((w1[i] as Array)[j])
		for i in range(vec.size()):
			acc += float(vec[i]) * float((w1[phi.size() + i] as Array)[j])
		z += maxf(acc, 0.0) * float(w2[j])
	return z


## One logit per candidate of ONE unit's menu, in menu order — the twin of
## `Policy::score_menu`. Softmax over the menu (if any) happens at the
## caller: cross-menu logits are NOT calibrated (design §1).
static func score_menu(net_in: Dictionary, board: Array, side: int, menu_tuples: Array) -> Array:
	if net_in.is_empty() or menu_tuples.is_empty():
		return []
	var phi := state_phi(board, side)
	var extras := AiClone.extras_for(int(net_in.get("act_dim", 5 + 5 + AiClone.GEO_DIM + 2)))
	var out: Array = []
	for t in menu_tuples:
		out.append(logit(net_in, phi, AiClone.action_vec(t, board, side, extras)))
	return out
