extends "res://scripts/network_manager.gd"
## A NetworkManager DOUBLE one layer below the socket, not above it.
##
## The suites in this directory drive the REAL production bodies (broadcast_unit_created,
## sync_unit_created, the band-authority check, the restore-lock interaction) — that is the whole
## point of an e2e test. What must NOT run for real is the actual multiplayer transport: no ENet
## peer, no relay, no @rpc/command-channel round trip. So this double overrides only the narrow
## seam _remote_call() (the one place production turns a decision into a wire send) plus the small
## set of status queries a test needs to drive from BOTH roles (host / guest, online / solo)
## without a real socket pair. Everything else — build_unit_created_payload, may_create_units_for_slot,
## sync_unit_created's idempotency and restore-lock waiting — is inherited unmodified and runs for
## real. Mirrors test/e2e/e2e_mp_reanimation_position_test.gd's FakeNet, one layer further down the
## stack (that one intercepts main's calls to NetworkManager; this one intercepts NetworkManager's
## own send).

var active: bool = true
var sent: Array = []
var my_slot: int = 1
var session_host: bool = true


func is_multiplayer_active() -> bool:
	return active


func _validate_rpc_ready(_context: String = "") -> bool:
	return true


func get_my_player_slot() -> int:
	return my_slot


func _is_session_host() -> bool:
	return session_host


func _remote_call(method: String, args: Array, target_peer: int = 0) -> void:
	sent.append({"m": method, "a": args, "t": target_peer})
