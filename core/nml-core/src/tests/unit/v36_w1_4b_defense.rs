//! Rules 3.6 row W1.4b (Fortified / Shielded / Guarded / Banner most-models parity) tests; owned by row W1.4b.
use super::*;

/// The profile-build strength is 3 host models; the live snapshot decides how
/// many are still standing. The joined hero rides ONLY the snapshot — the
/// shape the live fold exists for — so the static stamp never sees it and the
/// old profile-build read stays on.
fn host_profile(rule: &str) -> Profile {
    Profile {
        cost: 0,
        unit_id: "host".into(),
        name: "Host".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1, 1, 1],
        model_count: 3,
        weapons: vec![],
        special_rules: if rule.is_empty() { vec![] } else { vec![rule.into()] },
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: "knight_brothers".into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: Default::default(),
    }
}

fn hero_profile() -> Profile {
    let mut p = host_profile("");
    p.unit_id = "hero".into();
    p.name = "Hero".into();
    p.wounds_max = vec![1];
    p.model_count = 1;
    p
}

/// A two-unit snapshot: `host_alive` standing host models plus one living
/// joined hero that carries no defence rule of its own.
fn live_state(rule: &str, host_alive: i64) -> crate::state::State {
    let n = usize::try_from(host_alive).expect("host_alive");
    let host_positions = vec!["[0.0,0.0,0.0]"; n].join(",");
    let host_wounds = vec!["1"; n].join(",");
    let host_radii = vec!["0.0254"; n].join(",");
    let plain = format!(
        r#"{{"round":0,"rounds_total":1,"units":{{
          "host":{{"player":1,"alive":{host_alive},"activated":false,"shaken":false,"fatigued":false,"in_cover":false,"aircraft":false,"dormant":false,"dormant_models":0,"dormant_wounds":[],"casts":0,"morale_bonus":0,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":1.0,"positions":[{host_positions}],"wounds":[{host_wounds}],"radii":[{host_radii}],"mods":{{}},"mods_base":{{}},"attached":["hero"],"attached_to":""}},
          "hero":{{"player":1,"alive":1,"activated":false,"shaken":false,"fatigued":false,"in_cover":false,"aircraft":false,"dormant":false,"dormant_models":0,"dormant_wounds":[],"casts":0,"morale_bonus":0,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":1.0,"positions":[[1.0,0.0,0.0]],"wounds":[1],"radii":[0.0254],"mods":{{}},"mods_base":{{}},"attached":[],"attached_to":"host"}}
        }}}}"#
    );
    let mut index = std::collections::HashMap::new();
    index.insert("host".to_string(), 0);
    index.insert("hero".to_string(), 1);
    let profiles = std::rc::Rc::new(Profiles {
        list: vec![host_profile(rule), hero_profile()],
        index,
    });
    let mut cache = crate::state::ProfileCache::new(profiles);
    let mut roster = None;
    crate::io::state_from_json_with_epoch(&plain, &mut cache, &mut roster, EPOCH_73_V36)
        .expect("live state")
}

/// The host's context after the live fold at `epoch`.
fn ctx_at(rule: &str, host_alive: i64, epoch: u32) -> Ctx {
    let st = live_state(rule, host_alive);
    let mut reg = Registries::new(&repo_root());
    let statics: Vec<UnitStatic> = (0..st.roster.len())
        .map(|i| UnitStatic::build_for(&mut reg, &st.profiles.list[st.roster.profile[i]], epoch))
        .collect();
    let i = st.roster.index["host"];
    crate::sim::ctx_live(crate::sim::ctx_of(&statics[i], &st, i), &statics, &st, i, false, epoch)
}

/// Three living models, two of them Fortified carriers: the strict majority
/// holds, so the stamp stays.
#[test]
fn a_fortified_squad_keeps_it_while_two_of_three_living_models_carry_it() {
    let c = ctx_at("Fortified", 2, EPOCH_73_V36);
    assert!(c.fortified, "two of three living models carry Fortified: the majority holds");
}

/// One carrier dies: one carrier of two living models is an exact half, so the
/// live majority turns the stamp off at 73. Below the gate the profile-build
/// stamp stays untouched.
#[test]
fn losing_a_fortified_carrier_clears_it_at_73_but_not_at_72() {
    let at73 = ctx_at("Fortified", 1, EPOCH_73_V36);
    assert!(
        !at73.fortified,
        "one carrier of two living models is an exact half: the live majority clears the stamp"
    );
    let at72 = ctx_at("Fortified", 1, EPOCH_72_PLAYTEST_RULES);
    assert!(at72.fortified, "below the gate the profile-build stamp stays untouched");
}

/// Guarded is the OR of its five family names: it holds while one name is a
/// live majority and clears once none of them is.
#[test]
fn guarded_holds_while_a_family_name_is_a_live_majority_and_clears_when_none_is() {
    let holds = ctx_at("Sturdy", 2, EPOCH_73_V36);
    assert!(holds.guarded, "Sturdy is a live majority (two of three): Guarded holds");
    let gone = ctx_at("Sturdy", 1, EPOCH_73_V36);
    assert!(
        !gone.guarded,
        "one of two is not a majority for any family name: Guarded clears"
    );
}

/// A joined hero without the rule is one model; it does not switch off a host
/// majority.
#[test]
fn a_joined_hero_without_the_rule_does_not_switch_the_host_majority_off() {
    let c = ctx_at("Fortified", 3, EPOCH_73_V36);
    assert!(c.fortified, "three of four living models carry it: one plain hero does not switch it off");
}
