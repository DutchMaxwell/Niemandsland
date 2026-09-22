//! RULESMISSING — `Registries` names the mechanics files it could not READ,
//! so a player's bug report quotes the path instead of "the rules are empty".
//!
//! An unreadable file still yields the empty map / no spells exactly as
//! before (rules.rs `rules_for` / `spells_for`); only the reason is kept.

use nml_core::Registries;

/// (a) An EMPTY root: the read fails, the empty map stands, and the failed
/// path is recorded ONCE per path — a cached second `rules_for` must not
/// push it again, and `spells_for` appends its own path after the rules one.
#[test]
fn an_empty_root_names_the_missing_rules_then_spells_path() {
    let root = std::env::temp_dir().join(format!(
        "nml_rules_missing_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&root).expect("unique temp root");
    let root_s = root.display().to_string();
    let rules_path = root.join("assets/solo").join("rules_mechanics_gf.json");
    let spells_path = root.join("assets/solo").join("spells_mechanics_gf.json");

    let mut reg = Registries::new(&root_s);
    assert!(reg.rules_for("gf").empty, "an absent file yields the empty map");
    assert_eq!(
        reg.missing_files().to_vec(),
        vec![rules_path.display().to_string()],
        "the rules path is named exactly once"
    );

    reg.rules_for("gf");
    assert_eq!(
        reg.missing_files().to_vec(),
        vec![rules_path.display().to_string()],
        "the cache hit must not push the path a second time"
    );

    let _ = reg.spells_for("gf", "x");
    assert_eq!(
        reg.missing_files().to_vec(),
        vec![
            rules_path.display().to_string(),
            spells_path.display().to_string()
        ],
        "rules first, spells second"
    );

    std::fs::remove_dir_all(&root).expect("temp root removed");
}

/// (b) The real repo root — the test binary runs with cwd = `core/nml-core`,
/// so the root is `../..`. Both files are there: the map loads, nothing is
/// missing.
#[test]
fn the_repo_root_reads_both_files_and_names_nothing_missing() {
    let mut reg = Registries::new("../..");
    assert!(
        !reg.rules_for("gf").empty,
        "assets/solo/rules_mechanics_gf.json must parse at the repo root"
    );
    assert!(
        reg.missing_files().is_empty(),
        "nothing is missing at the repo root: {:?}",
        reg.missing_files()
    );
}
