use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

// FAB-C15 — rules 3.6 "Stealth Buff" is a once-grant of Stealth to ONE
// friendly unit within 12", not a permanent Stealth on the bearer. From 73 the
// entry is a Utility Buff granting `Stealth`; below the gate the old-data
// replay leg still stamps the Stealth alias on the bearer, byte-exact.
// Second leg: "Spell Resistance" no longer carries `all_models`, and the named
// most-models read (REGEN_MOST_MODELS) still delivers.

/// The carrier: a single-model gf robot_legions unit whose ONLY printed rule is
/// the REAL registry entry, plus one 24" rifle. Built through the real
/// `build_for`, never a hand-made ctx.
fn carrier(epoch: u32) -> UnitStatic {
    let p = Profile {
        cost: 0,
        unit_id: "a".into(),
        name: "a".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1],
        model_count: 1,
        weapons: vec![crate::state::Weapon {
            name: "Rifle".into(),
            range: 24.0,
            attacks: 2,
            count: 1,
            ap: 0,
            rules: vec![],
        }],
        special_rules: vec!["Stealth Buff".into()],
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: "robot_legions".into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    };
    let mut reg = crate::rules::Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, epoch)
}

/// The row's board: bearer "a" at the origin, a dead joined hero, friend "in"
/// 5" away (inside the 12" pick range, Tough 2 — value 3 beats the bearer's
/// own, so the pick lands on IT), and friend "out" 15" away (beyond the pick
/// range, Tough 9).
fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    st.roster = Rc::new(crate::state::Roster {
        keys: st.roster.keys.clone(),
        index: st.roster.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.player = vec![0, 0, 0, 0];
    st.alive = vec![1, 0, 1, 1];
    st.wounds = vec![vec![1], vec![], vec![1], vec![1]];
    st.positions = vec![
        vec![[0.0, 0.0, 0.0]],
        vec![],
        vec![[5.0 * IN2M, 0.0, 0.0]],
        vec![[15.0 * IN2M, 0.0, 0.0]],
    ];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], vec![IN2M]]);
    let mut inside = UnitStatic { name: "in".into(), ..Default::default() };
    inside.ctx.tough = 2;
    let mut outside = UnitStatic { name: "out".into(), ..Default::default() };
    outside.ctx.tough = 9;
    (
        st,
        vec![
            carrier(epoch),
            UnitStatic { name: "ah".into(), ..Default::default() },
            inside,
            outside,
        ],
    )
}

/// One HOLD activation of the bearer — the pre-attack slot the utility tray
/// occupies, dice-free.
fn run_line(st: &State, statics: &[UnitStatic], epoch: u32) -> State {
    let action = Action {
        kind: HOLD, unit: "a".into(), dest: None, shoot: None,
        charge: None, patient: false, split: None, traced: None, teleport: None,
    };
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
        .unwrap()
        .0
}

/// One 2-attack rifle volley at `def` from `dist_in`.
fn incoming_volley(def: &Ctx, dist_in: f64) -> crate::dice::ShootResult {
    let us = carrier(EPOCH_73_V36);
    let profiles = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let strikers = [crate::dice::Shooter {
        profiles: &profiles, keep: &[0], attacks: &[2], att: &att, owner: "att",
    }];
    let mut tray = crate::dice::Tray::seeded(27);
    crate::dice::resolve_volley_with_tray(
        &strikers, def, "Target", dist_in, dist_in, false, false, false, false, &mut tray,
    )
}

/// At 73 the bearer is NOT Stealth itself: the entry is a Utility Buff that
/// offers the once-grant, and no Stealth alias is stamped on the carrier.
#[test]
fn at_73_the_stealth_buff_bearer_is_not_stealth_and_offers_the_grant() {
    let us = carrier(EPOCH_73_V36);
    let buff = us
        .utility_buffs
        .iter()
        .find(|b| b.name == "Stealth Buff")
        .expect("at 73 the entry reads as a Utility Buff once-grant");
    assert_eq!(buff.grants_rule, "Stealth", "the entry grants Stealth");
    assert_eq!(buff.target, "friendly", "one picked friendly");
    assert_eq!(buff.max_targets, 1);
    assert_eq!(buff.range_in, 12.0);
    assert!(buff.once, "a one-time grant");
    assert!(!us.ctx.stealth, "the bearer must NOT be Stealth itself");
    assert_eq!(us.ctx.stealth_alias_penalty, 0, "no permanent -1 on the bearer");

    let shot = incoming_volley(&us.ctx, 12.0);
    assert_eq!(shot.rolls[0].target, 4, "a shot at the bearer past 9\" pays no Stealth -1");
}

/// At 73 the live Utility-Buff tray hands the grant to the in-range friendly
/// and the target's live context reads Stealth. The volley's battle log names
/// the rule and the target.
#[test]
fn at_73_the_tray_grants_stealth_to_a_friendly_within_twelve() {
    let (st, statics) = line(EPOCH_73_V36);
    let next = run_line(&st, &statics, EPOCH_73_V36);
    assert_eq!(next.buffs[2].len(), 1, "the 5\" friend receives the once-grant");
    let rec = &next.buffs[2][0];
    assert_eq!(&*rec.name, "Stealth Buff", "the record names the rule");
    assert_eq!(&*rec.grants_rule, "Stealth", "the record carries the printed grant");
    assert!(rec.once, "the once-per-activation promise rides the record");
    assert!(next.buffs[0].is_empty(), "the bearer stays unstamped");
    assert!(next.buffs[3].is_empty(), "the 15\" friend is beyond the 12\" pick");

    let tgt = crate::sim::ctx_live(
        crate::sim::ctx_of(&statics[2], &next, 2), &statics, &next, 2, false, EPOCH_73_V36,
    );
    assert!(tgt.stealth, "the granted Stealth applies to the picked friendly");

    let shot = incoming_volley(&tgt, 12.0);
    assert_eq!(shot.rolls[0].target, 5, "the granted -1 makes Quality 4+ read 5+");
    let log = shot.log.join("\n");
    assert!(log.contains("Stealth"), "the battle log names Stealth: {log}");
    assert!(log.contains("Target"), "the battle log names the target: {log}");
}

/// Below 73 nothing changes: no Utility-Buff row is offered, and the old-data
/// replay leg still stamps the carrier's Stealth alias (-1 over 9").
#[test]
fn below_73_the_bearer_keeps_its_old_alias_and_offers_nothing() {
    let us = carrier(EPOCH_72_PLAYTEST_RULES);
    assert!(
        us.utility_buffs.iter().all(|b| b.name != "Stealth Buff"),
        "below 73 the entry is not a utility-buff grant"
    );
    assert_eq!(us.ctx.stealth_alias_penalty, 1, "the 3.5 alias keeps its -1");
    assert_eq!(us.ctx.stealth_alias_over_in, 9.0, "over 9\" as printed");
    assert!(!us.ctx.stealth, "the alias, never the literal-Stealth stamp");
}

/// F16: the dropped `all_models` flag is inert — a mixed unit (three carrier
/// models + one plain joined hero) still takes the most-models Spell
/// Resistance read at 73, in both the data and the resolver.
#[test]
fn spell_resistance_keeps_most_models_after_the_all_models_drop() {
    let mut reg = crate::rules::Registries::new(&repo_root());
    let map = reg.rules_for("gf");
    let entry = map.lookup("robot_legions", "Spell Resistance").expect("the common entry");
    assert!(!entry.param_b("all_models"), "the 3.6 text has no all-models clause");

    let p = Profile {
        cost: 0,
        unit_id: "sr".into(),
        name: "sr".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1, 1, 1],
        model_count: 3,
        weapons: vec![],
        special_rules: vec!["Spell Resistance".into()],
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: "robot_legions".into(),
        item_grants: vec![],
        attached_hero_rules: vec![vec![]],
        move_bands: MoveBands::default(),
    };
    let us = UnitStatic::build_for(&mut reg, &p, EPOCH_73_V36);
    assert_eq!(us.ctx.regen_target, 6, "three of four models: the 6+ most-models read holds");
    assert_eq!(us.ctx.regen_target_spell, 2, "a spell wound is ignored on 2+");
}
