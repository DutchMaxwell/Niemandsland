class_name MPCommand
extends RefCounted
## Wire codec for the hand-rolled multiplayer command protocol (Phase 1 of the netcode replatform —
## see docs/ROADMAP.md "MP netcode replatform"). A command is a {type, seq, payload} envelope
## serialized with var_to_bytes and sent over the relay's channel-1 frames
## (RelayMultiplayerPeer.send_command) — entirely BELOW Godot's @rpc/SceneMultiplayer path-cache,
## so it survives transport reconnects (a new peer id never invalidates anything here).
##
## Keys are kept short (t/s/p) to minimise per-frame overhead on the bursty army-sync path.

# === Public ===

## Encode a command envelope to bytes. `payload` must be plain Variant data (Dictionary/Array/
## primitives) — NO Object references (var_to_bytes would need the _with_objects variant + is an
## untrusted-data risk over the wire).
static func encode(type: String, seq: int, payload: Variant) -> PackedByteArray:
	return var_to_bytes({"t": type, "s": seq, "p": payload})


## Decode bytes to an envelope { "t": type, "s": seq, "p": payload }, or {} on malformed input.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}
	var v: Variant = bytes_to_var(data)
	if v is Dictionary and v.has("t"):
		return v
	return {}
