class_name AiValue
extends RefCounted
## KUGEL v1 (NML-1045) — the VALUE net: "how clearly does this position stand
## for the side to move?", trained on the honest era's finished games against
## the final VP MARGIN (wipeout = maximum margin). The policy net answers
## "which move?"; this one answers "how good?" — the half the search never had,
## its leaf estimate being hand-built to this day.
##
## Character C (maintainer grill 23.08. "erst töten, dann tanzen"): the LABEL
## stays an honest margin; the CONSUMER decides the attitude. Below the crush
## threshold the margin is squashed steeply (any solid lead reads as "won" —
## secure it); above it the raw margin keeps paying, so a decided game is
## played out for maximum damage.
##
## Loading is env-gated (NML_VALUE_PATH) and every consumer must survive an
## empty net: no file, no behaviour change — byte-identical to the pre-Kugel
## planner. The forward pass mirrors netlab/value_train.py exactly (row encoder,
## three pooled groups, state layer, tanh head).

const CRUSH_AT := 0.55      # margin from which the game counts as decided
const SQUASH_K := 4.0       # steepness below the threshold: win first

static var _net: Dictionary = {}
static var _tried := false


static func net() -> Dictionary:
	if _tried:
		return _net
	_tried = true
	var path := OS.get_environment("NML_VALUE_PATH").strip_edges()
	if path.is_empty() or not FileAccess.file_exists(path):
		return _net
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and (parsed as Dictionary).has("head_weight"):
		_net = parsed
	return _net


## Test seam: inject a net without a file (and reset with {}).
static func set_net_for_test(n: Dictionary) -> void:
	_net = n
	_tried = true


static func _lin_relu(x: Array, w: Array, b: Array) -> Array:
	var out: Array = []
	out.resize(b.size())
	for o in range(b.size()):
		var row: Array = w[o]
		var acc := float(b[o])
		for i in range(mini(row.size(), x.size())):
			acc += float(row[i]) * float(x[i])
		out[o] = maxf(acc, 0.0)
	return out


## The raw margin estimate in [-1, 1] from `player`'s view, or NAN without a net.
static func margin(state: Dictionary, player: int) -> float:
	var n := net()
	if n.is_empty():
		return NAN
	var rows: Array = BattleSim.board_rows(state)
	if rows.is_empty():
		return NAN
	var in_dim := int(n["in_dim"])
	var rounds_total := float(maxi(int(state.get("rounds_total", 4)), 1))
	var clock := float(state.get("round", 1)) / rounds_total
	var hid: int = (n["state_0_bias"] as Array).size()
	var pools: Array = []
	var counts := [0.0, 0.0, 0.0]
	for p in range(3):
		var z: Array = []
		z.resize(hid)
		z.fill(0.0)
		pools.append(z)
	for raw in rows:
		var r: Array = raw
		var x: Array = []
		x.resize(in_dim + 2)
		x.fill(0.0)
		for j in range(mini(r.size(), in_dim)):
			x[j] = float(r[j])
		x[in_dim] = clock
		x[in_dim + 1] = rounds_total
		var emb := _lin_relu(_lin_relu(x, n["row_0_weight"], n["row_0_bias"]),
			n["row_2_weight"], n["row_2_bias"])
		var c0 := int(float(r[0]))
		var pi := 2 if c0 >= 3 else (0 if c0 == player else 1)
		var pool: Array = pools[pi]
		for j in range(hid):
			pool[j] = float(pool[j]) + float(emb[j])
		counts[pi] += 1.0
	var flat: Array = []
	for p in range(3):
		var div: float = maxf(float(counts[p]), 1.0)
		for j in range(hid):
			flat.append(float((pools[p] as Array)[j]) / div)
	var sv := _lin_relu(flat, n["state_0_weight"], n["state_0_bias"])
	var hw: Array = (n["head_weight"] as Array)[0]
	var acc := float((n["head_bias"] as Array)[0])
	for j in range(mini(hw.size(), sv.size())):
		acc += float(hw[j]) * float(sv[j])
	return tanh(acc)


## Character-C shaping of a raw margin into the eval's 0..1 currency.
static func shaped(m: float) -> float:
	if absf(m) >= CRUSH_AT:
		# decided: keep paying for damage — 0.90..1.00 (or 0.00..0.10 mirrored)
		var over := (absf(m) - CRUSH_AT) / maxf(1.0 - CRUSH_AT, 0.001)
		var top := 0.90 + 0.10 * clampf(over, 0.0, 1.0)
		return top if m > 0.0 else 1.0 - top
	return 1.0 / (1.0 + exp(-SQUASH_K * m))   # undecided: win first


## Blend weight for the value net (NML_VALUE_BLEND, default 0.0 = OFF).
static func blend_weight() -> float:
	var e := OS.get_environment("NML_VALUE_BLEND").strip_edges()
	return clampf(float(e), 0.0, 1.0) if e != "" else 0.0
