extends RefCounted
## Test facade for the owner-request wire's rejoin path: a pending request, the host's
## peer-joined handler (main._on_peer_version_validated -> owner_requests.resend) and the
## wire's own state. The private-access gate counts every `main._x` a test writes; keep those
## accesses here so an extraction out of main.gd moves this one file, not the suites.


var _main: Node


func _init(main: Node) -> void:
	_main = main


func set_timeout(seconds: float) -> void:
	_main._owner_roll_timeout_s = seconds


## Start one real pending owner request; the coroutine runs in the background (call without await).
func fire_request(peer: int) -> void:
	await _main._owner_request(peer, {"unit": "u1", "kind": "morale", "count": 1, "target": 4,
		"purpose": "morale test"})


## The request ids still waiting for an owner's answer.
func pending_ids() -> Array:
	return _main._solo_remote_save_waiters.keys()


func is_pending(req: int) -> bool:
	return _main._solo_remote_save_waiters.has(req)


## The owner's answer arrives on the command channel.
func answer(req: int, faces: Array, peer: int) -> void:
	_main._on_network_command("roll_result", {"req": req, "faces": faces}, peer)


## The host's peer-joined handler: the peer has its seat back after a rejoin.
func peer_joined(peer_id: int) -> void:
	_main._on_peer_version_validated(peer_id)
