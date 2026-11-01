//! Rules 3.6 row W1.4b (Steadfast / Evasive / Shrouding / Growth / Spell Resistance / Dodge most-models parity) tests; owned by row W1.4b.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One unit profile: `rules` on the host, `attached` as the profile's own
/// attached-hero rule lists.
fn unit_json(
    game: &str, faction: &str, rules: &[&str], models: i64, attached: &[&[&str]],
) -> String {
    let list = |r: &[&str]| serde_json::to_string(r).unwrap();
    let heroes: Vec<String> = attached.iter().map(|h| list(h)).collect();
    format!(
        r#"{{"unit_id":"host","name":"Host","quality":4,"defense":4,"tough":1,
          "wounds_max":[1,1,1],"model_count":{models},"caster_value":0,"base_radius":0.016,
          "game_system":"{game}","faction_folder":"{faction}",
          "special_rules":{},"item_grants":[],"attached_hero_rules":[{}],
          "move_bands":{{"advance":6.0,"rush":12.0}},"weapons":[]}}"#,
        list(rules), heroes.join(","),
    )
}

/// The host static built at `epoch`, plus the profile table its state reads.
fn evasion_build(
    host: &str, epoch: u32,
) -> (UnitStatic, std::rc::Rc<crate::state::Profiles>) {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{"host":{host},
          "hero":{}}}}}"#,
        unit_json("gf", "", &[], 1, &[]),
    );
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    let built = UnitStatic::build_for(&mut reg, header.profiles.get("host").expect("host"), epoch);
    (built, header.profiles.clone())
}

/// The joined-unit state: the host with `host_alive` living models and one
/// attached hero with `hero_alive`, as the live snapshot carries them.
fn evasion_state(
    profiles: std::rc::Rc<crate::state::Profiles>, host_alive: i64, hero_alive: i64,
) -> crate::state::State {
    let plain = format!(
        r#"{{"round":0,"rounds_total":1,"units":{{
          "host":{{"player":1,"alive":{host_alive},
            "positions":[[0.0,0.0,0.0],[0.02,0.0,0.0],[0.04,0.0,0.0]],
            "wounds":[1,1,1],"radii":[0.0254,0.0254,0.0254],
            "attached":["hero"],"mods":{{}},"mods_base":{{}}}},
          "hero":{{"player":1,"alive":{hero_alive},"positions":[[0.0,0.1,0.0]],
            "wounds":[1],"radii":[0.0254],            "attached":[],"attached_to":"host",
            "mods":{{}},"mods_base":{{}}}}}}}}"#
    );
    let mut cache = crate::state::ProfileCache::new(profiles);
    let mut roster = None;
    crate::io::state_from_json(&plain, &mut cache, &mut roster).expect("state")
}

fn live_evasion(host: &UnitStatic, st: &crate::state::State, epoch: u32) -> Ctx {
    crate::sim::ctx_live(crate::sim::ctx_of(host, st, 0), std::slice::from_ref(host), st, 0, false, epoch)
}

// --- (a) 3 living models, 2 carry Dodge: still on. ---

#[test]
fn two_of_three_living_models_keep_dodge_at_epoch_73() {
    let (host, profiles) = evasion_build(&unit_json("gf", "", &["Dodge"], 2, &[]), EPOCH_73_V36);
    let st = evasion_state(profiles, 2, 1);
    assert!(live_evasion(&host, &st, EPOCH_73_V36).dodge,
        "two host models carry Dodge out of three living models: a strict majority");
}

// --- (b) One carrier dies: off at 73, the static stamp stands at 72. ---

#[test]
fn one_of_two_living_models_loses_dodge_at_epoch_73() {
    let (host, profiles) = evasion_build(&unit_json("gf", "", &["Dodge"], 2, &[]), EPOCH_73_V36);
    let st = evasion_state(profiles, 1, 1);
    assert!(!live_evasion(&host, &st, EPOCH_73_V36).dodge,
        "one carrier of two living models is exactly half, not most: Dodge is off");
}

#[test]
fn the_same_dead_carrier_keeps_dodge_at_epoch_72() {
    let (host, profiles) = evasion_build(&unit_json("gf", "", &["Dodge"], 2, &[]), EPOCH_72_PLAYTEST_RULES);
    let st = evasion_state(profiles, 1, 1);
    assert!(live_evasion(&host, &st, EPOCH_72_PLAYTEST_RULES).dodge,
        "below 73 the static stamp is byte-identical: Dodge stays on");
}

#[test]
fn one_of_two_living_models_loses_evasive_at_epoch_73() {
    let (host, profiles) = evasion_build(&unit_json("gf", "", &["Evasive"], 2, &[]), EPOCH_73_V36);
    let st = evasion_state(profiles, 1, 1);
    assert!(!live_evasion(&host, &st, EPOCH_73_V36).evasive,
        "one carrier of two living models is exactly half, not most: Evasive is off");
}

#[test]
fn the_same_dead_carrier_keeps_evasive_at_epoch_72() {
    let (host, profiles) = evasion_build(&unit_json("gf", "", &["Evasive"], 2, &[]), EPOCH_72_PLAYTEST_RULES);
    let st = evasion_state(profiles, 1, 1);
    assert!(live_evasion(&host, &st, EPOCH_72_PLAYTEST_RULES).evasive,
        "below 73 the static stamp is byte-identical: Evasive stays on");
}

// --- (c) The Boost alias keeps Evasive while the plain majority is off. ---

#[test]
fn an_evasive_boost_alias_keeps_evasive_on_when_the_plain_majority_is_off() {
    let (host, profiles) = evasion_build(
        &unit_json("gf", "", &["Machine-Fog", "Enhanced Machine-Fog"], 1, &[]), EPOCH_73_V36,
    );
    let st = evasion_state(profiles, 1, 1);
    let ctx = live_evasion(&host, &st, EPOCH_73_V36);
    assert!(ctx.evasive_alias, "the Boost leg is the reason Evasive is stamped on");
    assert!(ctx.evasive,
        "no living model carries plain Evasive, but the Boost alias leg keeps the stamp on");
}

// --- (d) A plain joined hero does not switch the host majority off. ---

#[test]
fn a_plain_joined_hero_does_not_switch_the_host_majority_off() {
    let (host, profiles) = evasion_build(&unit_json("gf", "", &["Dodge"], 3, &[]), EPOCH_73_V36);
    let st = evasion_state(profiles, 3, 1);
    assert!(live_evasion(&host, &st, EPOCH_73_V36).dodge,
        "three host carriers of four living models: a plain joined hero is only one model");
}
