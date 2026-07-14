class_name ImportAwaitGuard
extends RefCounted

## Per-player "liveness" generation counter for the guest's army-import await timeout.
##
## A guest receives a remote army as a stream of RPCs: one header, N unit batches, then a
## complete (see main.gd _on_remote_army_* / network_manager broadcast_army_batched). If the
## host drops — or the relay loses the final message — mid-stream, the complete never arrives
## and the guest waits forever (LOADING ARMY overlay stuck, presence broadcasts paused). This
## guard drives an INACTIVITY timeout: header and every unit RPC bump the player's generation
## ("still making progress"); each bump arms a fresh timer capturing that generation. When a
## timer fires it aborts ONLY if its captured generation is still current — i.e. nothing has
## progressed since it was armed. So a healthy import (units 250 ms apart, then complete) keeps
## superseding its own timers and never falsely aborts, while a genuine stall trips exactly once.
##
## Pure and scene-tree-free so the decision logic is unit-testable; the SceneTreeTimer wiring
## lives in main.gd.

# === Private state =====================================================================

var _generation: Dictionary = {}  # player_id -> int


# === Public API ========================================================================

## Bump the player's generation and return the new token. Call on the header RPC and on every
## unit RPC — each call marks fresh progress and yields the token the matching timer captures.
func bump(player_id: int) -> int:
	var g: int = int(_generation.get(player_id, 0)) + 1
	_generation[player_id] = g
	return g


## True when a timer that captured `gen` is still the latest arming for this player — nothing
## has progressed since, so the await is genuinely stalled and the timer should abort. A later
## bump (unit/complete) or a clear() makes an older token stale, and its timer becomes a no-op.
func is_current(player_id: int, gen: int) -> bool:
	return _generation.has(player_id) and int(_generation[player_id]) == gen


## Forget a player's generation — the import completed or was aborted. Idempotent. After this,
## every outstanding timer for that player is stale (is_current returns false), so the pending
## SceneTreeTimers self-cancel when they fire.
func clear(player_id: int) -> void:
	_generation.erase(player_id)


## Whether any player currently has an armed (unresolved) await. Test/diagnostic helper.
func is_awaiting() -> bool:
	return not _generation.is_empty()
