//! MEL-07e tests (rules 3.6, lane melee): from `EPOCH_73_V36` the AI's melee and Impact EV against a
//! Parry unit subtract the expected cancels — `min(Parry dice, expected hits) * 1/6` — before the
//! saves. The cancels are applied to the strike's hit pool as a whole (the "most dangerous first"
//! order the dice path uses is not modelled in the estimate). Epoch 72 keeps today's value.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::{impact_ev, melee_ev};
use crate::rules::Registries;

/// A defender through the REAL stamp: `models` models at Defense 4 carrying `rules` ("Parry(1)"),
/// built at `epoch` so the Parry stamp is epoch-gated like production.
fn parry_unit(models: i64, rules: &[&str], epoch: u32) -> UnitStatic {
    let listed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let json = format!(
        r#"{{"unit_id":"u","name":"Defender","model_count":{models},"quality":4,"defense":4,"tough":1,"game_system":"gf","faction_folder":"","special_rules":[{listed}],"weapons":[]}}"#
    );
    let p: Profile = serde_json::from_str(&json).expect("the defender's profile parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, epoch)
}

/// The live context `ctx_of` would hand the EV: the static stamp with the snapshot's alive count.
fn live_ctx(u: &UnitStatic, models: i64) -> Ctx {
    Ctx { models, ..u.ctx }
}

fn blade(attacks: i64) -> ShootProfile {
    ShootProfile { name: "Blade".into(), range: 0, attacks, ..Default::default() }
}

/// 10 attacks at 4+ = 5 expected hits; 2 Parry dice cancel min(2, 5)/6 = 1/3 hit; Defense 4+ saves
/// half, so the EV drops by (1/3)/2 = 1/6.
#[test]
fn the_melee_ev_drops_by_the_expected_cancels_at_epoch_73() {
    let defender = parry_unit(2, &["Parry(1)"], EPOCH_73_V36);
    assert_eq!(defender.ctx.parry_dice, 1, "the stamp puts one die per carrier model");
    let def_parry = live_ctx(&defender, 2);
    let def_plain = Ctx { parry_dice: 0, ..def_parry };
    let att = Ctx { quality: 4, models: 1, ..Default::default() };
    let with_parry = melee_ev(&[blade(10)], &[10], &att, &def_parry, false, 0.0);
    let without = melee_ev(&[blade(10)], &[10], &att, &def_plain, false, 0.0);
    assert!(
        (without - with_parry - 1.0 / 6.0).abs() < 1e-9,
        "Parry must take the expected 1/6 wound off the melee EV: {with_parry} vs {without}"
    );
}

/// Impact(4) hits on 2+ = 10/3 expected hits; 2 Parry dice cancel min(2, 10/3)/6 = 1/3 hit; the
/// Defense 4+ save halves it, so the EV drops by 1/6.
#[test]
fn the_impact_ev_drops_by_the_expected_cancels_at_epoch_73() {
    let defender = parry_unit(2, &["Parry(1)"], EPOCH_73_V36);
    let def_parry = live_ctx(&defender, 2);
    let def_plain = Ctx { parry_dice: 0, ..def_parry };
    let att = Ctx { impact: 4, models: 1, ..Default::default() };
    let with_parry = impact_ev(&att, &def_parry);
    let without = impact_ev(&att, &def_plain);
    assert!(
        (without - with_parry - 1.0 / 6.0).abs() < 1e-9,
        "Parry must take the expected 1/6 wound off the Impact EV: {with_parry} vs {without}"
    );
}

/// The Parry dice never cancel more than the expected hits: 10 Parry(1) models bring 10 dice into
/// 5 expected hits, so the cancels cap at 5/6 hit and the EV drops by (5/6)/2 = 5/12.
#[test]
fn parry_cancels_never_exceed_the_expected_hits() {
    let defender = parry_unit(10, &["Parry(1)"], EPOCH_73_V36);
    let def_parry = live_ctx(&defender, 10);
    let def_plain = Ctx { parry_dice: 0, ..def_parry };
    let att = Ctx { quality: 4, models: 1, ..Default::default() };
    let with_parry = melee_ev(&[blade(10)], &[10], &att, &def_parry, false, 0.0);
    let without = melee_ev(&[blade(10)], &[10], &att, &def_plain, false, 0.0);
    assert!(
        (without - with_parry - 5.0 / 12.0).abs() < 1e-9,
        "the cancels cap at the expected hits: {with_parry} vs {without}"
    );
}

/// CONTROL: below epoch 73 the Parry stamp is off, so the melee EV into the Parry unit is exactly
/// the no-Parry value.
#[test]
fn the_melee_ev_into_a_parry_unit_is_unchanged_at_epoch_72() {
    let defender = parry_unit(2, &["Parry(1)"], EPOCH_72_PLAYTEST_RULES);
    assert_eq!(defender.ctx.parry_dice, 0, "the Parry stamp is off below 73");
    let plain = parry_unit(2, &[], EPOCH_72_PLAYTEST_RULES);
    let att = Ctx { quality: 4, models: 1, ..Default::default() };
    let parry_ev = melee_ev(&[blade(10)], &[10], &att, &live_ctx(&defender, 2), false, 0.0);
    let plain_ev = melee_ev(&[blade(10)], &[10], &att, &live_ctx(&plain, 2), false, 0.0);
    assert!(
        (parry_ev - plain_ev).abs() < 1e-12,
        "epoch 72 must keep today's value: {parry_ev} vs {plain_ev}"
    );
}
