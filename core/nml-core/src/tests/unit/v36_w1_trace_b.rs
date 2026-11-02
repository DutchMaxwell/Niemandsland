//! Rules 3.6 row W1.TRACE-b tests (one trace arm per unit.rs stamp site); owned by row W1.TRACE-b.
//!
//! `sim::trace_rule` writes its line to stderr only while `NML_TRACE_RULES=1`,
//! so each assertion runs the fixture in a CHILD copy of this test binary with
//! that switch set and reads the child's stderr. The child case is selected by
//! `NML_TRACE_CASE`; a normal suite run of `trace_child` (no such variable)
//! just returns.

use super::*;

const E72: u32 = crate::acts::EPOCH_72_PLAYTEST_RULES;
const E73: u32 = crate::acts::EPOCH_73_V36;

fn carrier_json(system: &str, faction: &str, rules: &[&str]) -> String {
    let list = serde_json::to_string(rules).expect("rules json");
    format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
          "carrier":{{"unit_id":"carrier","name":"Carrier","quality":4,
            "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
            "base_radius":0.016,"game_system":"{system}","faction_folder":"{faction}",
            "special_rules":{list},"item_grants":[],
            "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
            "weapons":[{{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}},
              {{"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    )
}

fn case_parts(case: &str) -> (&'static str, &'static str, &'static [&'static str]) {
    match case {
        "regen-alias" => ("gf", "knight_brothers", &["Warding"]),
        "bane-boost" => (
            "gf",
            "goblin_reclaimers",
            &["Bane in Melee", "Mischievous", "Enhanced Mischievous"],
        ),
        "fortified-alias" => ("gf", "prime_brothers", &["Reinforced"]),
        "shot-modifier" => (
            "gf",
            "goblin_reclaimers",
            &["Good Shot", "Precision Fighter Aura"],
        ),
        "shred" => ("gf", "war_disciples", &["Shred"]),
        "evasive-stamp" => ("gf", "battle_brothers", &["Evasive"]),
        "banner-stamp" => ("gf", "battle_brothers", &["Banner"]),
        "stealth-alias-stamp" => ("gf", "change_disciples", &["Changebound"]),
        "piercing-hunter" => ("gf", "battle_brothers", &["Piercing Shooter"]),
        "shielded-alias" => ("gf", "dwarf_guilds", &["Enhanced Sturdy"]),
        "ranged-shrouding" => ("gf", "custodian_brothers", &["Ranged Shrouding"]),
        "surge-window" => ("gf", "blessed_sisters", &["Point-Blank Surge"]),
        other => panic!("unknown trace case {other}"),
    }
}

fn run_case(case: &str, epoch: u32) {
    let (system, faction, rules) = case_parts(case);
    let header = read_act_header(&carrier_json(system, faction, rules)).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("carrier").expect("carrier");
    if case == "banner-stamp" {
        let _ = capture_reads_for_epoch(&mut reg, p, epoch);
    } else {
        let _ = UnitStatic::build_for(&mut reg, p, epoch);
    }
}

fn run_child(case: &str, epoch: u32) -> String {
    let exe = std::env::current_exe().expect("test binary path");
    let out = std::process::Command::new(exe)
        .arg("--exact")
        .arg("unit::tests::v36_w1_trace_b::trace_child")
        .arg("--nocapture")
        .env("NML_TRACE_RULES", "1")
        .env("NML_TRACE_CASE", case)
        .env("NML_TRACE_EPOCH", epoch.to_string())
        .output()
        .expect("spawn the trace child");
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    assert!(out.status.success(), "trace child '{case}' failed: {stderr}");
    stderr
}

fn assert_arm(case: &str, epoch: u32, arm: &str) {
    let stderr = run_child(case, epoch);
    assert!(
        stderr.contains(&format!("[{arm}]")),
        "epoch {epoch}: expected the trace arm [{arm}], got:\n{stderr}"
    );
}

fn assert_no_arm(case: &str, epoch: u32, arm: &str) {
    let stderr = run_child(case, epoch);
    assert!(
        !stderr.contains(&format!("[{arm}]")),
        "epoch {epoch}: the trace arm [{arm}] must not fire, got:\n{stderr}"
    );
}

#[test]
fn trace_child() {
    let Ok(case) = std::env::var("NML_TRACE_CASE") else { return };
    let epoch = std::env::var("NML_TRACE_EPOCH")
        .ok()
        .and_then(|e| e.parse().ok())
        .unwrap_or(E73);
    run_case(&case, epoch);
}

#[test]
fn regen_alias_emits_one_arm_at_73() {
    assert_arm("regen-alias", E73, "regen-alias");
}

#[test]
fn bane_boost_emits_one_arm_at_73() {
    assert_arm("bane-boost", E73, "bane-boost");
}

#[test]
fn fortified_alias_emits_one_arm_at_73() {
    assert_arm("fortified-alias", E73, "fortified-alias");
}

#[test]
fn shot_modifier_emits_one_arm_at_73() {
    assert_arm("shot-modifier", E73, "shot-modifier");
}

#[test]
fn shred_emits_one_arm_at_73() {
    assert_arm("shred", E73, "shred");
}

#[test]
fn evasive_stamp_emits_one_arm_at_73() {
    assert_arm("evasive-stamp", E73, "evasive-stamp");
}

#[test]
fn banner_stamp_emits_one_arm_at_73() {
    assert_arm("banner-stamp", E73, "banner-stamp");
}

#[test]
fn stealth_alias_stamp_emits_one_arm_at_73() {
    assert_arm("stealth-alias-stamp", E73, "stealth-alias-stamp");
}

#[test]
fn piercing_hunter_emits_one_arm_at_73() {
    assert_arm("piercing-hunter", E73, "piercing-hunter");
}

#[test]
fn shielded_alias_emits_one_arm_at_73() {
    assert_arm("shielded-alias", E73, "shielded-alias");
}

#[test]
fn ranged_shrouding_emits_one_arm_at_73() {
    assert_arm("ranged-shrouding", E73, "ranged-shrouding");
}

#[test]
fn surge_window_emits_one_arm_at_73() {
    assert_arm("surge-window", E73, "surge-window");
}

#[test]
fn the_new_arms_are_absent_at_72() {
    for (case, arm) in [
        ("regen-alias", "regen-alias"),
        ("bane-boost", "bane-boost"),
        ("fortified-alias", "fortified-alias"),
        ("shot-modifier", "shot-modifier"),
        ("shred", "shred"),
        ("evasive-stamp", "evasive-stamp"),
        ("banner-stamp", "banner-stamp"),
        ("stealth-alias-stamp", "stealth-alias-stamp"),
        ("piercing-hunter", "piercing-hunter"),
        ("shielded-alias", "shielded-alias"),
        ("ranged-shrouding", "ranged-shrouding"),
        ("surge-window", "surge-window"),
    ] {
        assert_no_arm(case, E72, arm);
    }
}
