//! Rules 3.6 row W1.4b, audit doubt: a stamp set ONLY by an aura fold must
//! survive `ctx_live` at `EPOCH_73_V36` (and stay byte-identical at 72).
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One unit profile; `rules` are the profile's own carried names.
fn unit_json(game: &str, faction: &str, rules: &[&str], model_count: i64) -> String {
    let list = |r: &[&str]| serde_json::to_string(r).unwrap();
    format!(
        r#"{{"unit_id":"host","name":"Host","quality":4,"defense":4,"tough":1,
          "wounds_max":[1,1,1],"model_count":{model_count},"caster_value":0,"base_radius":0.016,
          "game_system":"{game}","faction_folder":"{faction}",
          "special_rules":{},"item_grants":[],"attached_hero_rules":[],
          "move_bands":{{"advance":6.0,"rush":12.0}},"weapons":[]}}"#,
        list(rules),
    )
}

/// The aura-expanded static plus the RAW profile table the live state reads.
fn aura_build(
    host: &str, epoch: u32,
) -> (UnitStatic, std::rc::Rc<crate::state::Profiles>) {
    let hero = unit_json("gf", "", &[], 1);
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{"host":{host},"hero":{hero}}}}}"#
    );
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    let built = UnitStatic::build_for(&mut reg, header.profiles.get("host").expect("host"), epoch);
    (built, header.profiles.clone())
}

/// The joined-unit state: `host_alive` living host models plus one living
/// attached hero that carries nothing.
fn aura_state(
    profiles: std::rc::Rc<crate::state::Profiles>, host_alive: i64,
) -> crate::state::State {
    let plain = format!(
        r#"{{"round":0,"rounds_total":1,"units":{{
          "host":{{"player":1,"alive":{host_alive},
            "positions":[[0.0,0.0,0.0],[0.02,0.0,0.0],[0.04,0.0,0.0]],
            "wounds":[1,1,1],"radii":[0.0254,0.0254,0.0254],
            "attached":["hero"],"mods":{{}},"mods_base":{{}}}},
          "hero":{{"player":1,"alive":1,"positions":[[0.0,0.1,0.0]],
            "wounds":[1],"radii":[0.0254],"attached":[],"attached_to":"host",
            "mods":{{}},"mods_base":{{}}}}}}}}"#
    );
    let mut cache = crate::state::ProfileCache::new(profiles);
    let mut roster = None;
    crate::io::state_from_json(&plain, &mut cache, &mut roster).expect("state")
}

fn live_ctx(host: &UnitStatic, st: &crate::state::State, epoch: u32) -> Ctx {
    let mut reg = Registries::new(&repo_root());
    let statics: Vec<UnitStatic> = st.profiles.list.iter()
        .map(|p| UnitStatic::build_for(&mut reg, p, epoch)).collect();
    crate::sim::ctx_live(crate::sim::ctx_of(host, st, 0), &statics, st, 0, false, epoch)
}

// --- (a) The aof "Fortified Aura" is an Aura Channel: the fold grants the
// bare base to a unit that carries none of the family names itself. ---

#[test]
fn an_aura_only_fortified_stamp_survives_ctx_live_at_epoch_73() {
    let host = unit_json("aof", "duchies_of_vinci", &["Fortified Aura"], 3);
    let (built, profiles) = aura_build(&host, EPOCH_73_V36);
    assert!(built.ctx.fortified, "the aura fold stamps Fortified on the unit");
    let st = aura_state(profiles, 3);
    assert!(live_ctx(&built, &st, EPOCH_73_V36).fortified,
        "the unit carries no Fortified name itself: the live majority must not clear the aura stamp");
}

#[test]
fn the_same_aura_only_fortified_stamp_stands_at_epoch_72() {
    let host = unit_json("aof", "duchies_of_vinci", &["Fortified Aura"], 3);
    let (built, profiles) = aura_build(&host, EPOCH_72_PLAYTEST_RULES);
    let st = aura_state(profiles, 3);
    assert!(live_ctx(&built, &st, EPOCH_72_PLAYTEST_RULES).fortified,
        "below 73 the static stamp is byte-identical: the aura keeps it");
}

// --- (b) The aof "Versatile Defense Aura" is an Aura Channel too. ---

#[test]
fn an_aura_only_guarded_stamp_survives_ctx_live_at_epoch_73() {
    let host = unit_json("aof", "change_disciples", &["Versatile Defense Aura"], 3);
    let (built, profiles) = aura_build(&host, EPOCH_73_V36);
    assert!(built.ctx.guarded, "the aura fold stamps Versatile Defense on the unit");
    let st = aura_state(profiles, 3);
    assert!(live_ctx(&built, &st, EPOCH_73_V36).guarded,
        "the unit carries no Guarded-family name itself: the live majority must not clear the aura stamp");
}

#[test]
fn the_same_aura_only_guarded_stamp_stands_at_epoch_72() {
    let host = unit_json("aof", "change_disciples", &["Versatile Defense Aura"], 3);
    let (built, profiles) = aura_build(&host, EPOCH_72_PLAYTEST_RULES);
    let st = aura_state(profiles, 3);
    assert!(live_ctx(&built, &st, EPOCH_72_PLAYTEST_RULES).guarded,
        "below 73 the static stamp is byte-identical: the aura keeps it");
}

// --- (c) No registry aura grants the literal "Stealth" bool: the closest
// Stealth aura carries the Changebound alias, which the live read never
// touches. A stamp that any non-majority source set (the aura fold's shape)
// must not be cleared when the profile carries no Stealth name itself. ---

#[test]
fn an_aura_only_stealth_stamp_survives_ctx_live_at_epoch_73() {
    let mut built = aura_build(&unit_json("gf", "", &[], 3), EPOCH_73_V36).0;
    built.ctx.stealth = true;
    let (_again, profiles) = aura_build(&unit_json("gf", "", &[], 3), EPOCH_73_V36);
    let st = aura_state(profiles, 3);
    assert!(live_ctx(&built, &st, EPOCH_73_V36).stealth,
        "the profile carries no Stealth name: the live majority must not clear an aura-set stamp");
}
