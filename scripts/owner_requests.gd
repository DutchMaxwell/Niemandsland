class_name OwnerRequests
extends RefCounted
## The resolver side of the owner request wire: a roll or a choice that belongs to a unit is asked
## of the human who owns it, over the same command channel every other sync uses. The table sends
## `request_roll` and waits for `roll_result`; no answer within the bound is a visible automatic
## roll (see docs/glossary.md, "owner request").
##
## The module owns only the wire and its state. It reads the network manager through `net_of` at
## call time, because a test swaps it per session, and writes its battle-log lines through
## `log_line`.

## No-reply bound: a disconnect mid-volley must fall back to a visible auto-roll, not freeze
## the whole attack resolution forever.
const SOLO_REMOTE_SAVE_TIMEOUT_S := 120.0

var timeout_s := SOLO_REMOTE_SAVE_TIMEOUT_S  # tests shorten it; play never does
var waiters: Dictionary = {}  # request id -> {"faces": Array, "done": bool}
var session := "%08x%08x" % [randi(), Time.get_ticks_usec() & 0xffffffff]
var seq := 0

var _net_of: Callable
var _slot_of: Callable
var _log_line: Callable


func _init(net_of: Callable, slot_of: Callable, log_line: Callable) -> void:
	_net_of = net_of
	_slot_of = slot_of
	_log_line = log_line


func _net() -> Variant:
	return _net_of.call()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## `request_roll` to `owner_peer`, then a bounded wait for its `roll_result`. Returns the reply
## ({"faces", "done"}); "done" false = no answer within the timeout.
func request(owner_peer: int, rq: Dictionary) -> Dictionary:
	seq += 1
	var req := seq
	var payload := {"req": req, "rs": session}
	payload.merge(rq)
	waiters[req] = {
		"faces": [],
		"done": false,
		"peer": owner_peer,
		"aborted": false,
		"slot": _slot_of.call(owner_peer),
		"payload": payload
	}
	_net().send_command("request_roll", payload, owner_peer)
	var waiter: Dictionary = waiters[req]
	var waited := 0.0
	while (
		not bool(waiter.get("done", false))
		and not bool(waiter.get("aborted", false))
		and waited < timeout_s
	):
		await _tree().create_timer(0.1).timeout
		waited += 0.1
	var reply: Dictionary = waiters.get(req, {})
	waiters.erase(req)
	return reply


## #1867: end pending owner requests at once when their owner is gone — a departed peer (its id)
## or a failed rejoin (all). Callers read "done": false as the existing visible fallback.
func release(peer: int = 0) -> void:
	for req in waiters:
		var waiter: Dictionary = waiters[req]
		if peer == 0 or int(waiter.get("peer", 0)) == peer:
			waiter["aborted"] = true


## #1882: true while a connected peer has no seat yet - the window between the relay's reused-id
## flush and the version handshake that rebuilds peer_to_slot. A roll waits through it instead of
## treating a returning player as absent.
func handshake_pending() -> bool:
	var net: Variant = _net()
	if net == null or not net.is_multiplayer_active():
		return false
	for peer in net.connected_peers:
		if not (net.peer_to_slot as Dictionary).has(int(peer)):
			return true
	return false


## #1882: a reused-id rejoin is reported as peer_disconnected + peer_connected in the SAME frame
## (relay_multiplayer_peer.gd _emit_peer_connected). One frame later the peer is back, so the
## request release is deferred: only a peer that stays away is a leave (#1867 still holds).
func release_after_flush(peer_id: int) -> void:
	await _tree().process_frame
	var net: Variant = _net()
	if net != null and net.connected_peers.has(peer_id):
		return
	release(peer_id)


## #1882 part 2: the relay drops a frame whose target socket is gone, so an owner's answer given
## during the host's outage dies on the wire. Once the returning peer has its seat back, re-send
## every still-pending request with the SAME id — the owner replays its stored answer.
func resend(peer_id: int) -> void:
	var net: Variant = _net()
	if net == null or waiters.is_empty():
		return
	var slot: int = _slot_of.call(peer_id)
	if slot <= 0:
		return
	for req in waiters:
		var waiter: Dictionary = waiters[req]
		if int(waiter.get("slot", 0)) != slot:
			continue
		waiter["peer"] = peer_id
		net.send_command("request_roll", waiter.get("payload", {}), peer_id)
		_log_line.call("Roll request sent again after the rejoin")


## Resolver side: the owner's faces arrived — release the waiting roll.
func on_result(req: int, faces: Array) -> void:
	if not waiters.has(req):
		return
	var waiter: Dictionary = waiters[req]
	if bool(waiter.get("done", false)):
		# P4.D-23: the first answer is the answer; a second one (stale or replayed) never overwrites it
		return
	waiter["faces"] = faces
	waiter["done"] = true
