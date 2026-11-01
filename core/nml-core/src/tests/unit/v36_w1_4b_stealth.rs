//! Rules 3.6 row W1.4b (Stealth family most-models parity) tests; owned by row W1.4b.
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
fn stealth_build(
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
fn stealth_state(
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

fn live_stealth(host: &UnitStatic, st: &crate::state::State, epoch: u32) -> Ctx {
    // `ctx_live` reads the whole statics table by roster index (the live regen fold
    // looks at every joined hero), not just the host's row.
    let mut reg = Registries::new(&repo_root());
    let statics: Vec<UnitStatic> = st.profiles.list.iter()
        .map(|p| UnitStatic::build_for(&mut reg, p, epoch)).collect();
    crate::sim::ctx_live(crate::sim::ctx_of(host, st, 0), &statics, st, 0, false, epoch)
}

// --- (a) 3 living models, 2 carry Stealth: still on. ---

#[test]
fn two_of_three_living_models_keep_stealth_at_epoch_73() {
    let (host, profiles) = stealth_build(&unit_json("gf", "", &["Stealth"], 2, &[]), EPOCH_73_V36);
    let st = stealth_state(profiles, 2, 1);
    assert!(live_stealth(&host, &st, EPOCH_73_V36).stealth,
        "two host models carry Stealth out of three living models: a strict majority");
}

// --- (b) One carrier dies: off at 73, the static stamp stands at 72. ---

#[test]
fn one_of_two_living_models_loses_stealth_at_epoch_73() {
    let (host, profiles) = stealth_build(&unit_json("gf", "", &["Stealth"], 2, &[]), EPOCH_73_V36);
    let st = stealth_state(profiles, 1, 1);
    assert!(!live_stealth(&host, &st, EPOCH_73_V36).stealth,
        "one carrier of two living models is exactly half, not most: the rule is off");
}

#[test]
fn the_same_dead_carrier_keeps_stealth_at_epoch_72() {
    let (host, profiles) = stealth_build(&unit_json("gf", "", &["Stealth"], 2, &[]), EPOCH_72_PLAYTEST_RULES);
    let st = stealth_state(profiles, 1, 1);
    assert!(live_stealth(&host, &st, EPOCH_72_PLAYTEST_RULES).stealth,
        "below 73 the static stamp is byte-identical: the rule stays on");
}

// --- (c) A plain joined hero does not switch the host majority off. ---

#[test]
fn a_plain_joined_hero_does_not_switch_the_host_majority_off() {
    let (host, profiles) = stealth_build(&unit_json("gf", "", &["Stealth"], 3, &[]), EPOCH_73_V36);
    let st = stealth_state(profiles, 3, 1);
    assert!(live_stealth(&host, &st, EPOCH_73_V36).stealth,
        "three host carriers of four living models: a plain joined hero is only one model");
}

// --- (d) An unlisted Stealth alias keeps the all-models read. ---

#[test]
fn an_unlisted_alias_keeps_the_all_models_read() {
    let hero: &[&str] = &["Hero"];
    let (host, profiles) = stealth_build(
        &unit_json("aof", "change_disciples", &["Enhanced Changebound"], 3, &[hero]), EPOCH_73_V36,
    );
    assert_eq!(host.ctx.stealth_alias_penalty, 0, "one plain joined hero strips the alias");
    let st = stealth_state(profiles, 3, 1);
    assert_eq!(live_stealth(&host, &st, EPOCH_73_V36).stealth_alias_penalty, 0,
        "an unlisted alias keeps the all-models read: the live majority is for the family list only");
}
