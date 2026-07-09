extends GdUnitTestSuite
## ImportAwaitGuard — the pure liveness logic behind the guest's army-import await timeout
## (fix/import-await-timeout, 3+ hardening completion). A guest buffers a remote army between
## its header and complete RPCs; if the host goes silent mid-stream the guest must give up and
## recover instead of hanging on the LOADING ARMY overlay. This guard decides whether a fired
## inactivity timer is still the latest arming (should abort) or has been superseded by fresh
## progress (no-op). The SceneTreeTimer wiring lives in main.gd (_arm_import_await_timeout).

const ImportAwaitGuardScript := preload("res://scripts/import_await_guard.gd")


func _make() -> ImportAwaitGuard:
	return ImportAwaitGuardScript.new()


func test_first_bump_returns_one_and_is_current() -> void:
	var g := _make()
	var t := g.bump(2)
	assert_int(t).is_equal(1)
	assert_bool(g.is_current(2, t)).is_true()


func test_bump_increments_per_player() -> void:
	var g := _make()
	assert_int(g.bump(2)).is_equal(1)
	assert_int(g.bump(2)).is_equal(2)
	assert_int(g.bump(2)).is_equal(3)


## A later bump (a fresh unit RPC) supersedes the previous token: the old timer must NOT abort,
## the new one is now the live arming. This is what makes a slow-but-progressing import safe.
func test_later_bump_makes_earlier_token_stale() -> void:
	var g := _make()
	var first := g.bump(1)   # header arms timer #1
	var second := g.bump(1)  # a unit arrives → arms timer #2
	assert_bool(g.is_current(1, first)).is_false()   # timer #1 fires → no-op
	assert_bool(g.is_current(1, second)).is_true()   # timer #2 is the live one


## clear() = the complete RPC arrived (or we aborted). Every outstanding token goes stale, so
## any pending timers self-cancel when they fire.
func test_clear_makes_all_tokens_stale() -> void:
	var g := _make()
	var t := g.bump(3)
	g.clear(3)
	assert_bool(g.is_current(3, t)).is_false()


func test_is_current_false_for_unknown_player() -> void:
	var g := _make()
	assert_bool(g.is_current(99, 1)).is_false()


func test_players_are_independent() -> void:
	var g := _make()
	var a := g.bump(1)
	var b := g.bump(2)
	# Clearing player 1 must not disturb player 2's live arming.
	g.clear(1)
	assert_bool(g.is_current(1, a)).is_false()
	assert_bool(g.is_current(2, b)).is_true()


func test_is_awaiting_reflects_pending_imports() -> void:
	var g := _make()
	assert_bool(g.is_awaiting()).is_false()
	g.bump(1)
	assert_bool(g.is_awaiting()).is_true()
	g.clear(1)
	assert_bool(g.is_awaiting()).is_false()


func test_clear_is_idempotent() -> void:
	var g := _make()
	g.bump(1)
	g.clear(1)
	g.clear(1)  # second clear must not error
	assert_bool(g.is_awaiting()).is_false()


## Full healthy-stream shape: header, three units, then complete — at every step only the newest
## token is current, and after complete nothing is awaiting. No timer would ever abort here.
func test_healthy_stream_never_leaves_stale_current_token() -> void:
	var g := _make()
	var tokens: Array[int] = []
	tokens.append(g.bump(1))            # header
	for _i in range(3):
		tokens.append(g.bump(1))        # units
	# Only the last arming is live; all earlier timers are no-ops.
	for i in range(tokens.size() - 1):
		assert_bool(g.is_current(1, tokens[i])).is_false()
	assert_bool(g.is_current(1, tokens[-1])).is_true()
	g.clear(1)                          # complete
	assert_bool(g.is_awaiting()).is_false()
