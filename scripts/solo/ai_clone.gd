class_name AiClone
extends RefCounted
## The behaviour CLONE's policy (NML-1009, Plan B v2): given a position and a
## menu of candidate moves, score every candidate the way the TEACHER (the
## decision tree) would have chosen. Every net before this one answered "who
## wins from here?"; this one answers "what would he play?".
##
## The maths mirrors netlab/clone_train.py ClonePolicy exactly — three pooled
## row embeddings (mine / theirs / markers) plus the ACTING unit's own row,
## against one embedding per candidate action. Any drift between the two
## implementations would steer games with a silently different brain, so a
## loaded net MUST carry a selftest block (a real position, its menu and the
## scores torch produced) and is REFUSED when the recomputation disagrees.
## Same gate the encoder nets carry (ai_mission_eval._encoder_selftest_ok).

const SELFTEST_TOL := 1e-4
const DEST_X_SCALE := 36.0   # table half-width in inches — must match the trainer
const DEST_Z_SCALE := 24.0

static var _net_cache: Dictionary = {}
static var _tried := false
static var _seat_nets: Dictionary = {}   # seat(int) → weights, for net-vs-net


## Loaded once from NML_CLONE_PATH; {} = no clone, callers keep their own brain.
static func net() -> Dictionary:
	if _tried:
		return _net_cache
	_tried = true
	_net_cache = _load(OS.get_environment("NML_CLONE_PATH").strip_edges())
	return _net_cache


## The policy for ONE seat: NML_CLONE_P1 / NML_CLONE_P2 put a DIFFERENT net in
## each chair, which is how a generation is judged against its predecessor
## (paired, same seeds, same activation order). Falls back to the single-net
## NML_CLONE_PATH, so every earlier run keeps working unchanged.
static func net_for(seat: int) -> Dictionary:
	if _seat_nets.has(seat):
		return _seat_nets[seat]
	var path := OS.get_environment("NML_CLONE_P%d" % seat).strip_edges()
	var loaded := _load(path) if path != "" else net()
	_seat_nets[seat] = loaded
	return loaded


static func _load(path: String) -> Dictionary:
	if path == "":
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("row_w1"):
		printerr("[CLONE] FATAL: no policy weights at '%s'" % path)
		return {}
	if not selftest_ok(parsed as Dictionary):
		printerr("[CLONE] FATAL: policy selftest FAILED — refusing to steer with a drifted net")
		return {}
	return parsed


## Test seam: install weights without touching the environment.
static func set_net(n: Dictionary) -> void:
	_net_cache = n
	_tried = true


## The action tuples the trainer sees — ONE source for the corpus writer and
## for play, so what the clone scores is what it learned.
static func menu_tuples(state: Dictionary, key: String, cands: Array) -> Array:
	var row_of := {}
	var i := 0
	for k in state["units"]:
		if int((state["units"][k] as Dictionary)["alive"]) > 0:
			row_of[str(k)] = i
			i += 1
	var out: Array = []
	for c in cands:
		var cd: Dictionary = c
		var dest: Vector3 = cd.get("dest", Vector3.ZERO)
		var victim := str(cd.get("charge", cd.get("shoot", "")))
		out.append({"kind": int(cd["kind"]),
			"dest_x": snappedf(dest.x / BattleSim.IN2M, 0.1),
			"dest_z": snappedf(dest.z / BattleSim.IN2M, 0.1),
			"victim_row": int(row_of.get(victim, -1)),
			"unit_row": int(row_of.get(key, -1))})
	return out


## One score per menu entry (higher = more teacher-like). [] without a net.
static func scores(net_in: Dictionary, board: Array, side: int, menu: Array) -> Array:
	if net_in.is_empty() or board.is_empty() or menu.is_empty():
		return []
	var in_dim := int(net_in["in_dim"])
	var h: int = (net_in["row_b1"] as Array).size()
	var pools: Array = []
	var counts := [0.0, 0.0, 0.0, 0.0]
	for p in range(4):
		var zero: Array = []
		zero.resize(h)
		zero.fill(0.0)
		pools.append(zero)
	var actor_row := int((menu[0] as Dictionary).get("unit_row", -1))
	for r in range(board.size()):
		var raw: Array = board[r]
		var x: Array = []
		x.resize(in_dim)
		x.fill(0.0)
		for j in range(mini(raw.size(), in_dim)):
			x[j] = float(raw[j])
		var emb := _lin_relu(_lin_relu(x, net_in["row_w1"], net_in["row_b1"]),
			net_in["row_w2"], net_in["row_b2"])
		var c0 := int(float(raw[0]))
		var pi := 2 if c0 == 3 else (0 if c0 == side else 1)
		_add_into(pools[pi], emb)
		counts[pi] += 1.0
		if r == actor_row:
			_add_into(pools[3], emb)
			counts[3] += 1.0
	var parts: Array = []
	for p in range(4):
		var div: float = maxf(float(counts[p]), 1.0)
		for j in range(h):
			parts.append(float((pools[p] as Array)[j]) / div)
	var svec := _lin_relu(parts, net_in["state_w1"], net_in["state_b1"])
	var out: Array = []
	for a in menu:
		var av := _lin_relu(action_vec(a as Dictionary, board, side),
			net_in["act_w1"], net_in["act_b1"])
		var cat: Array = svec.duplicate()
		cat.append_array(av)
		var hid := _lin_relu(cat, net_in["head_w1"], net_in["head_b1"])
		var z := float(net_in["head_b2"])
		var w2: Array = net_in["head_w2"]
		for j in range(w2.size()):
			z += float(w2[j]) * float(hid[j])
		out.append(z)
	return out


## The compact action description, byte-for-byte the trainer's action_vec().
static func action_vec(a: Dictionary, board: Array, side: int) -> Array:
	var kinds := 5
	var v: Array = []
	v.resize(kinds + 5 + GEO_DIM)
	v.fill(0.0)
	var k := int(a.get("kind", 0))
	if k >= 0 and k < kinds:
		v[k] = 1.0
	var span := float(maxi(board.size(), 1))
	v[kinds + 0] = float(a.get("dest_x", 0.0)) / DEST_X_SCALE
	v[kinds + 1] = float(a.get("dest_z", 0.0)) / DEST_Z_SCALE
	v[kinds + 2] = 1.0 if int(a.get("victim_row", -1)) >= 0 else 0.0
	v[kinds + 3] = float(int(a.get("victim_row", -1))) / span
	v[kinds + 4] = float(int(a.get("unit_row", -1))) / span
	var geo := geo_vec(a, board, side)
	for i in range(GEO_DIM):
		v[kinds + 5 + i] = float(geo[i])
	return v


## Where the move ENDS relative to what matters — markers, the enemy, my own
## line, and whether the move closes or opens those gaps. Without these the
## policy is unlearnable: absolute destinations against a POOLED board cannot
## express "this spot sits on a marker" (measured — the absolute-only tuple
## scored exactly what always-guess-the-commonest-index scores).
const GEO_DIM := 8

static func geo_vec(a: Dictionary, board: Array, side: int) -> Array:
	var ur := int(a.get("unit_row", -1))
	var ax := 0.0
	var az := 0.0
	if ur >= 0 and ur < board.size():
		ax = float((board[ur] as Array)[1])
		az = float((board[ur] as Array)[2])
	var dx := float(a.get("dest_x", 0.0))
	var dz := float(a.get("dest_z", 0.0))
	if int(a.get("kind", 0)) == 0:   # HOLD carries no destination: it stays put
		dx = ax
		dz = az
	var m_d := _near(board, "marker", side, ur, dx, dz)
	var m_now := _near(board, "marker", side, ur, ax, az)
	var f_d := _near(board, "foe", side, ur, dx, dz)
	var f_now := _near(board, "foe", side, ur, ax, az)
	return [sqrt((dx - ax) * (dx - ax) + (dz - az) * (dz - az)) / 12.0,
		m_d / 12.0, 1.0 if m_d <= 3.0 else 0.0, (m_now - m_d) / 12.0,
		f_d / 12.0, (f_now - f_d) / 12.0,
		_near(board, "friend", side, ur, dx, dz) / 12.0,
		1.0 if f_d <= 1.0 else 0.0]


static func _near(board: Array, kind: String, side: int, actor_row: int,
		x: float, z: float) -> float:
	var best := 99.0
	for i in range(board.size()):
		var r: Array = board[i]
		var c0 := int(float(r[0]))
		if kind == "marker" and c0 != 3:
			continue
		if kind == "foe" and (c0 == 3 or c0 == side):
			continue
		if kind == "friend" and (c0 != side or i == actor_row):
			continue
		var d := sqrt((float(r[1]) - x) * (float(r[1]) - x) + (float(r[2]) - z) * (float(r[2]) - z))
		best = minf(best, d)
	return best


## Recompute the shipped selftest row; any mismatch means the two brains drifted.
static func selftest_ok(n: Dictionary) -> bool:
	var st: Dictionary = n.get("selftest", {})
	if st.is_empty():
		return false
	var got := scores(n, st["board"], int(st["side"]), st["menu"])
	var want: Array = st["expected"]
	if got.size() != want.size():
		return false
	for i in range(got.size()):
		if absf(float(got[i]) - float(want[i])) > SELFTEST_TOL:
			printerr("[CLONE] selftest mismatch at %d: %.6f vs %.6f" % [i, got[i], want[i]])
			return false
	return true


static func _add_into(pool: Array, emb: Array) -> void:
	for j in range(emb.size()):
		pool[j] = float(pool[j]) + float(emb[j])


static func _lin_relu(x: Array, w: Array, b: Array) -> Array:
	var out: Array = []
	for j in range(b.size()):
		var acc := float(b[j])
		for i in range(x.size()):
			acc += float(x[i]) * float((w[i] as Array)[j])
		out.append(maxf(acc, 0.0))
	return out
