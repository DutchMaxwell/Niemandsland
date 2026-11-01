//! Rules 3.6 row W1.4b (Regeneration family most-models parity) tests; owned by row W1.4b.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::io::state_from_json_with_epoch;
use crate::sim::{ctx_live, ctx_of};
use crate::state::{ProfileCache, Profiles, State};
use std::rc::Rc;

/// One host plus up to two joined heroes, built through the REAL registry.
/// `hero_rules` is one rule list per living hero; the host's
/// `attached_hero_rules` carries the same lists (the stamp-time reading).
const FIXTURE: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "host":{"unit_id":"host","name":"Host","quality":4,
    "defense":4,"tough":1,"wounds_max":HOST_WOUNDS,"model_count":HOST_MODELS,"caster_value":0,
    "base_radius":0.016,"game_system":"SYSTEM","faction_folder":"FACTION",
    "special_rules":HOST_RULES,"item_grants":[],
    "attached_hero_rules":HERO_RULES,"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[]},
  "h1":{"unit_id":"h1","name":"Hero One","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"SYSTEM","faction_folder":"FACTION",
    "special_rules":H1_RULES,"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "h2":{"unit_id":"h2","name":"Hero Two","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"SYSTEM","faction_folder":"FACTION",
    "special_rules":H2_RULES,"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

struct Fixture {
    statics: Vec<UnitStatic>,
    state: State,
    host: usize,
}

fn rules_json(rules: &[&str]) -> String {
    format!(
        "[{}]",
        rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",")
    )
}

/// The live ask: the host's own context re-read over the snapshot.
fn live(fx: &Fixture, epoch: u32) -> Ctx {
    let us = &fx.statics[fx.state.roster.profile[fx.host]];
    ctx_live(ctx_of(us, &fx.state, fx.host), &fx.statics, &fx.state, fx.host, false, epoch)
}

#[allow(clippy::too_many_arguments)]
fn fixture(
    system: &str,
    faction: &str,
    host_rules: &[&str],
    host_models: i64,
    hero_rules: &[&[&str]],
    host_alive: i64,
    hero_alive: &[i64],
    epoch: u32,
) -> Fixture {
    let h1 = hero_rules.first().map(|r| rules_json(r)).unwrap_or_else(|| "[]".into());
    let h2 = hero_rules.get(1).map(|r| rules_json(r)).unwrap_or_else(|| "[]".into());
    let text = FIXTURE
        .replace("SYSTEM", system)
        .replace("FACTION", faction)
        .replace("HOST_WOUNDS", &format!("{:?}", vec![1i64; host_models as usize]))
        .replace("HOST_MODELS", &host_models.to_string())
        .replace("HOST_RULES", &rules_json(host_rules))
        .replace(
            "HERO_RULES",
            &format!(
                "[{}]",
                hero_rules.iter().map(|r| rules_json(r)).collect::<Vec<_>>().join(",")
            ),
        )
        .replace("H1_RULES", &h1)
        .replace("H2_RULES", &h2);
    let header = read_act_header(&text).expect("fixture header parses");
    let profiles: Rc<Profiles> = Rc::clone(&header.profiles);
    let mut reg = Registries::new(&repo_root());
    let statics: Vec<UnitStatic> = profiles
        .list
        .iter()
        .map(|p| UnitStatic::build_for(&mut reg, p, epoch))
        .collect();
    let attached: Vec<String> = (0..hero_rules.len()).map(|i| format!("h{}", i + 1)).collect();
    let mut units = format!(
        r#""host":{{"player":1,"alive":{host_alive},"attached":[{}]}}"#,
        attached.iter().map(|k| format!("\"{k}\"")).collect::<Vec<_>>().join(",")
    );
    for (i, alive) in hero_alive.iter().enumerate() {
        units.push_str(&format!(
            r#","h{}":{{"player":1,"alive":{alive},"attached_to":"host"}}"#,
            i + 1
        ));
    }
    let state_text = format!(r#"{{"round":0,"rounds_total":1,"units":{{{units}}}}}"#);
    let mut cache = ProfileCache::new(Rc::clone(&profiles));
    let mut roster_cache = None;
    let state = state_from_json_with_epoch(&state_text, &mut cache, &mut roster_cache, epoch)
        .expect("fixture state parses");
    let host = state.roster.index["host"];
    Fixture { statics, state, host }
}

/// (a) Three living models where two carry Regeneration are most: the roll stays.
#[test]
fn two_of_three_living_models_keep_regeneration_at_73() {
    let fx = fixture(
        "gf", "robot_legions", &["Regeneration"], 2, &[&["Hero"]], 2, &[1], EPOCH_73_V36,
    );
    let ctx = live(&fx, EPOCH_73_V36);
    assert!(ctx.regeneration, "two of three living models carry Regeneration");
    assert_eq!(ctx.regen_target, 5, "the registry's 5+");
}

/// (b) A carrier dies: 1 of 2 is an exact half at 73, and the static stamp on
/// the live leg is not touched below the gate (at 72 the host's own rule stands).
#[test]
fn a_dead_carrier_turns_the_family_off_at_73_but_not_at_72() {
    let at73 = fixture(
        "gf", "robot_legions", &["Regeneration"], 2, &[&["Hero"]], 1, &[1], EPOCH_73_V36,
    );
    let ctx73 = live(&at73, EPOCH_73_V36);
    assert!(!ctx73.regeneration, "1 of 2 living models is an exact half, not most");

    let at72 = fixture(
        "gf", "robot_legions", &["Regeneration"], 2, &[&["Hero"]], 1, &[1],
        EPOCH_72_PLAYTEST_RULES,
    );
    let ctx72 = live(&at72, EPOCH_72_PLAYTEST_RULES);
    assert!(ctx72.regeneration, "below 73 the live majority never decides");
    assert_eq!(ctx72.regen_target, 5, "the static 5+ replays byte-exact");
}

/// (c) A plain joined hero does not strip the host's majority.
#[test]
fn a_plain_joined_hero_does_not_switch_the_host_majority_off() {
    let fx = fixture(
        "gf", "robot_legions", &["Regeneration"], 3, &[&["Hero"]], 3, &[1], EPOCH_73_V36,
    );
    let ctx = live(&fx, EPOCH_73_V36);
    assert!(ctx.regeneration, "three of four living models carry Regeneration");
    assert_eq!(ctx.regen_target, 5);
}

/// (d) The live target folds the smaller printed target of the living
/// majority-bearing models: two Regeneration heroes (5+) outvote the last
/// Knightborn host model (6+/2+).
#[test]
fn the_live_target_takes_the_smaller_printed_target_among_the_carriers() {
    let fx = fixture(
        "gff", "knight_brothers", &["Knightborn"], 3,
        &[&["Hero", "Regeneration"], &["Hero", "Regeneration"]],
        1, &[1, 1], EPOCH_73_V36,
    );
    let ctx = live(&fx, EPOCH_73_V36);
    assert!(ctx.regeneration, "two of three living models carry Regeneration");
    assert_eq!(ctx.regen_target, 5, "the living carriers' 5+ beats the dead stamp's 6+");
}
