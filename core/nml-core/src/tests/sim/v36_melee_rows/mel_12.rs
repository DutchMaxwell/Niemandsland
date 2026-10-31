//! MEL-12 — Regenerative Strength rolls one die per token for direct wounds instead of adding
//! attacks (rules 3.6), once per round, before the strikes and never while Fatigued. Epoch 72
//! keeps the old extra-attack payout and rolls no token dice.

use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::Roll;

/// The REAL registry product: a gf `alien_hives` "Regenerative Strength" carrier (one 1-attack
/// melee weapon, one model), read at `rules_epoch`. Quality 7 keeps the weapon's own strikes off
/// the wound pool so the assertions see the token dice alone.
fn rs_carrier(epoch: u32) -> UnitStatic {
    let p: Profile = serde_json::from_str(
        r#"{"unit_id":"a","name":"RS","quality":4,"defense":4,"tough":1,"wounds_max":[1],
            "model_count":1,"game_system":"gf","faction_folder":"alien_hives",
            "special_rules":["Regenerative Strength"],
            "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}"#,
    )
    .unwrap();
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut us = UnitStatic::build_for(&mut reg, &p, epoch);
    us.ctx.quality = 7;
    us
}

/// Unit 0: the Regenerative Strength carrier with 3 banked tokens. Unit 1: a 3-model Defense-4
/// target that cannot be reached by the Quality-7 weapon, so only token wounds land.
fn board(epoch: u32) -> (Vec<UnitStatic>, State) {
    let attacker = rs_carrier(epoch);
    let defender = UnitStatic {
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
        name: "Target".into(),
        model_count: 3,
        wounds_max: vec![1, 1, 1],
        ..Default::default()
    };
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into()],
        index: HashMap::new(),
        profile: vec![0, 1],
    });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 3];
    st.shaken = vec![false, false];
    st.fatigued = vec![false, false];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.wounds[0] = vec![1];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M];
    st.positions[1] = vec![[IN2M, 0.0, 0.0], [2.0 * IN2M, 0.0, 0.0], [3.0 * IN2M, 0.0, 0.0]];
    st.wounds[1] = vec![1, 1, 1];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M, IN2M, IN2M];
    st.growth_markers[0] = 3;
    (vec![attacker, defender], st)
}

/// The token batch (3 dice at 4+) — its count and target keep it apart from the weapon's to-hit.
fn token_rolls(shot: &ShootResult) -> Vec<&Roll> {
    shot.rolls.iter().filter(|r| r.owner == "RS" && r.count == 3 && r.target == 4).collect()
}

fn weapon_strike(shot: &ShootResult) -> &Roll {
    shot.rolls.iter().filter(|r| r.owner == "RS").last().expect("the weapon's own to-hit die")
}

#[test]
fn a_regenerative_strength_unit_rolls_one_die_per_token_instead_of_extra_attacks_at_73() {
    let (statics, mut st) = board(EPOCH_73_V36);
    let seams = Seams { rules_epoch: EPOCH_73_V36, ..Default::default() };
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, seams, &mut Tray::seeded(27), &mut shot,
        StrikeSet::All, Cover::Recorded(None),
    );
    let tokens = token_rolls(&shot);
    assert_eq!(tokens.len(), 1, "one token batch: {:?}", shot.rolls);
    assert_eq!(tokens[0].faces.len(), 3, "3 markers -> 3 dice");
    let k = tokens[0].faces.iter().filter(|&&f| f >= 4).count() as i64;
    assert_eq!(weapon_strike(&shot).count, 1, "the tokens add no attacks");
    assert!(
        shot.log.iter().any(|l| l == &format!("Regenerative Strength: RS rolls 3 dice, {k} wounds")),
        "rules-must-log: {:?}",
        shot.log
    );
    // The direct wounds land with the phase's pool. Quality 7 can only hit on an unmodified 6 and
    // the Defense-4 target fails only unmodified 1s, so the weapon's own share is readable.
    let hits = weapon_strike(&shot).faces.iter().filter(|&&f| f == 6).count() as i64;
    let unsaved = shot
        .rolls
        .iter()
        .filter(|r| r.kind == "defense" && r.owner == "Target")
        .flat_map(|r| r.faces.iter())
        .filter(|&&f| f == 1)
        .count() as i64;
    assert!(hits >= unsaved, "sanity: never more unsaved than hits");
    assert_eq!(
        st.wounds[1].len() as i64,
        3 - (k + unsaved).min(3),
        "the token wounds land on the target"
    );
}

#[test]
fn a_fatigued_regenerative_strength_unit_rolls_no_token_dice_at_73() {
    let (statics, mut st) = board(EPOCH_73_V36);
    st.fatigued[0] = true;
    let seams = Seams { rules_epoch: EPOCH_73_V36, ..Default::default() };
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, seams, &mut Tray::seeded(27), &mut shot,
        StrikeSet::All, Cover::Recorded(None),
    );
    assert!(token_rolls(&shot).is_empty(), "a Fatigued unit rolls no token dice: {:?}", shot.rolls);
    assert!(
        shot.log.iter().any(|l| l.contains("Regenerative Strength") && l.contains("Fatigued")),
        "the skip names the rule: {:?}",
        shot.log
    );
}

#[test]
fn a_second_activation_in_the_same_round_rolls_no_second_token_batch() {
    let (statics, mut st) = board(EPOCH_73_V36);
    let seams = Seams { rules_epoch: EPOCH_73_V36, ..Default::default() };
    let mut shot = ShootResult::default();
    let mut tray = Tray::seeded(27);
    for _ in 0..2 {
        strike_phase(
            &statics, &mut st, 0, 1, false, 0.0, seams, &mut tray, &mut shot,
            StrikeSet::All, Cover::Recorded(None),
        );
    }
    assert_eq!(token_rolls(&shot).len(), 1, "once per round: {:?}", shot.rolls);
    assert!(
        shot.log.iter().any(|l| l.contains("already rolled its dice this round")),
        "the second skip names the rule: {:?}",
        shot.log
    );
}

#[test]
fn at_epoch_72_regenerative_strength_still_adds_attacks_and_rolls_no_token_dice() {
    let (statics, mut st) = board(EPOCH_72_PLAYTEST_RULES);
    let seams = Seams { rules_epoch: EPOCH_72_PLAYTEST_RULES, ..Default::default() };
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, seams, &mut Tray::seeded(27), &mut shot,
        StrikeSet::All, Cover::Recorded(None),
    );
    assert!(token_rolls(&shot).is_empty(), "no token dice below 73: {:?}", shot.rolls);
    assert_eq!(weapon_strike(&shot).count, 4, "3 markers still add 3 attacks at 72");
}

#[test]
fn another_growth_markers_rule_keeps_its_extra_attacks_at_epoch_73() {
    let (mut statics, mut st) = board(EPOCH_73_V36);
    statics[0] = UnitStatic {
        ctx: Ctx { quality: 7, defense: 4, tough: 1, models: 1, ..Default::default() },
        name: "RS".into(),
        melee: vec![ShootProfile { name: "Claws".into(), attacks: 1, count: 1, range: 0, ..Default::default() }],
        growth: vec![GrowthRule {
            name: "Piercing Growth".into(),
            attacks_per_marker: 1,
            ..Default::default()
        }],
        model_count: 1,
        wounds_max: vec![1],
        ..Default::default()
    };
    let seams = Seams { rules_epoch: EPOCH_73_V36, ..Default::default() };
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, seams, &mut Tray::seeded(27), &mut shot,
        StrikeSet::All, Cover::Recorded(None),
    );
    assert!(token_rolls(&shot).is_empty(), "no Regenerative Strength, no token dice: {:?}", shot.rolls);
    assert_eq!(weapon_strike(&shot).count, 4, "another Growth Markers rule keeps its extra attacks at 73");
}
