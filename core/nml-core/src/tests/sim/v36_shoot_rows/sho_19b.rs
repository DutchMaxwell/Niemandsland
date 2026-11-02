//! SHO-19b tests (rules 3.6, lane shoot): an Enhanced Watchborn token reaches a Watchborn
//! bearer's first attack with no distance gate, is spent by that exchange, and reads nothing
//! below `EPOCH_73_V36`.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::Spell;

fn watch_bearer(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let mut profile = st.profiles.list[0].clone();
    profile.name = "Watchborn".into();
    profile.game_system = "gf".into();
    profile.faction_folder = "watch_brothers".into();
    profile.special_rules = vec!["Watchborn".into()];
    st.profiles = Rc::new(crate::state::Profiles {
        list: vec![profile.clone()],
        index: Default::default(),
    });
    st.roster = Rc::new(crate::state::Roster {
        keys: st.roster.keys.clone(),
        index: st.roster.index.clone(),
        profile: vec![0, 0, 0, 0],
    });
    let mut reg = crate::rules::Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
    let bearer = UnitStatic::build_for(&mut reg, &profile, rules_epoch);
    (st, vec![bearer, UnitStatic::default(), UnitStatic::default(), UnitStatic::default()])
}

/// RED on main: the cast lands an Enhanced Watchborn grant, the first 5" shot gets the pick,
/// and the exchange spends the token so the next attack has no pick.
#[test]
fn enhanced_watchborn_skips_the_gate_on_the_first_attack_then_is_spent() {
    let (mut st, statics) = watch_bearer(EPOCH_73_V36);
    let grant = Spell {
        effect_kind: "buff".into(),
        grants_rule: "Enhanced Watchborn".into(),
        ..Default::default()
    };
    apply_cast_effect(&statics, &mut st, 0, &grant, 1.0, Seams::default(), None);
    assert!(crate::mods::granted(&st, 0, "Enhanced Watchborn"), "the cast lands the token");

    let base = ctx_of(&statics[0], &st, 0);
    let live = ctx_live(base, &statics, &st, 0, false, EPOCH_73_V36);
    let p = ShootProfile { range: 24, attacks: 20, versatile_attack: true, ..Default::default() };
    let def = Ctx { defense: 4, tough: 1, models: 5, ..Default::default() };
    let plain = crate::combat::profile_ev(&p, 4, &base, &def, 5.0, false);
    let buffed = crate::combat::profile_ev(&p, 4, &live, &def, 5.0, false);
    assert!(buffed > plain, "the token opens the 5\" shot: {plain} -> {buffed}");

    crate::mods::spend_once(&mut st, 0, &[crate::mods::Role::Grant], false);
    assert!(!crate::mods::granted(&st, 0, "Enhanced Watchborn"), "the first attack spent it");
    let after = ctx_live(base, &statics, &st, 0, false, EPOCH_73_V36);
    assert_eq!(
        crate::combat::profile_ev(&p, 4, &after, &def, 5.0, false),
        plain,
        "the next attack has no token"
    );
}

/// The old side: the same cast below 73 does not open the 5" shot.
#[test]
fn below_epoch_73_the_enhanced_token_does_not_open_the_gate() {
    let (mut st, statics) = watch_bearer(EPOCH_72_PLAYTEST_RULES);
    let grant = Spell {
        effect_kind: "buff".into(),
        grants_rule: "Enhanced Watchborn".into(),
        ..Default::default()
    };
    apply_cast_effect(&statics, &mut st, 0, &grant, 1.0, Seams::default(), None);
    let base = ctx_of(&statics[0], &st, 0);
    let live = ctx_live(base, &statics, &st, 0, false, EPOCH_72_PLAYTEST_RULES);
    let p = ShootProfile { range: 24, attacks: 20, versatile_attack: true, ..Default::default() };
    let def = Ctx { defense: 4, tough: 1, models: 5, ..Default::default() };
    assert_eq!(
        crate::combat::profile_ev(&p, 4, &live, &def, 5.0, false),
        crate::combat::profile_ev(&p, 4, &base, &def, 5.0, false),
        "below 73 the token reads no no-gate behaviour"
    );
}
