# gdUnit4 tests for the command-protocol codec (Phase 1 of the netcode replatform).
extends GdUnitTestSuite


func test_encode_decode_roundtrip() -> void:
	var bytes := MPCommand.encode("sync_move", 7, {"id": 1000001, "x": 3})
	var env := MPCommand.decode(bytes)
	assert_that(env.get("t")).is_equal("sync_move")
	assert_that(env.get("s")).is_equal(7)
	assert_that(env.get("p")).is_equal({"id": 1000001, "x": 3})


func test_decode_empty_is_empty_dict() -> void:
	assert_that(MPCommand.decode(PackedByteArray())).is_equal({})


func test_decode_non_envelope_variant_is_empty_dict() -> void:
	# A valid Variant that isn't our {t,s,p} envelope must decode to {} (ignored).
	assert_that(MPCommand.decode(var_to_bytes(42))).is_equal({})
