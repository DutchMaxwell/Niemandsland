//! Opt-in runtime validation against the cdylib Cargo just built, avoiding a
//! stale installed wheel when validating changes to the shared movement core.
use std::{env, fs, path::Path, process::Command};

#[test]
#[ignore = "requires Python with pytest/numpy and the runtime suite dependencies"]
fn python_suite_uses_the_current_core_library() {
    let crate_root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let root = crate_root.parent().unwrap().parent().unwrap();
    let executable = env::current_exe().unwrap();
    let artifacts = executable.parent().unwrap();
    let library = artifacts.join(format!("{}nml_core{}", env::consts::DLL_PREFIX, env::consts::DLL_SUFFIX));
    assert!(library.is_file(), "Cargo must build the Python cdylib for this integration test");
    let directory = env::temp_dir().join(format!("position-parity-python-{}", std::process::id()));
    fs::create_dir_all(&directory).unwrap();
    fs::copy(library, directory.join(format!("nml_core{}", env::consts::DLL_SUFFIX))).unwrap();
    let mut paths = vec![directory.clone(), crate_root.join("python")];
    if let Some(existing) = env::var_os("PYTHONPATH") { paths.extend(env::split_paths(&existing)); }
    let python = env::var_os("NML_PYTHON_TEST_BIN").unwrap_or_else(|| "python3".into());
    let result = Command::new(python).current_dir(root)
        .env("PYTHONPATH", env::join_paths(paths).unwrap())
        .args(["-m", "pytest", "core/nml-core-py/tests/python", "-q"])
        .status().expect("launch the Python runtime suite");
    fs::remove_dir_all(directory).unwrap();
    assert!(result.success(), "the Python runtime suite failed against the current core");
}
