extends GdUnitTestSuite
## One-core phase 1, step 7: the Rust core is mandatory, so a test run without it is red, not skipped.
## The cases that need NmlCore run unconditionally; this guard names the cause once, in plain words,
## instead of leaving a dozen unrelated failures to explain. CI loads the core before the shards run.


func test_the_nmlcore_extension_is_loaded() -> void:
	assert_bool(ClassDB.class_exists("NmlCore")).override_failure_message(
		"NmlCore is not loaded. Build it: cargo build --release --features onnx-tract "
		+ "--manifest-path core/nml-core-godot/Cargo.toml && bash core/install_gdextension.sh, "
		+ "then re-import the project.").is_true()
