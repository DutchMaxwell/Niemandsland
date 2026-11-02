use super::*;

// DAT-17a — the Regeneration Buff engine half. A granted Regeneration is a
// one-time grant spent by the FIRST exchange that brings a wound in to its
// holder: from EPOCH_73_V36 the defender spends it as soon as wounds enter,
// even when the regeneration roll ignores them all; an exchange that brings no
// wound in does not spend it. The holder's own attack still does not spend it
// at 73. Below 73 the old unconditional spend answers for both sides, so a
// recorded replay is byte-identical.
//
// Red first: on main `keep_regen` survives every exchange that left the holder
// unwounded, so an exchange whose wounds are all ignored keeps the grant; and
// it is not epoch-gated, so a 72 replay no longer spends what the old path
// spent. The all-ignored test is the RED witness for the kept behaviour; the
// zero-wound exchange already kept the grant on main and must keep it still.

/// The Regeneration Buff as the catalogue exports it: a once buff carrying
/// `grants_rule: "Regeneration"`.
fn regen_spell() -> Spell {
    Spell {
        name: "Regeneration Buff".into(),
        status: "castable".into(),
        threshold: 1,
        range_in: 18.0,
        target_count: 1,
        effect_kind: "buff".into(),
        grants_rule: "Regeneration".into(),
        ..Default::default()
    }
}

/// Land the grant through the LIVE cast-effect tree (`apply_cast_effect`), the
/// same push a real once spell uses — never a hand-built `LiveMod`.
fn land_regen_grant(st: &mut State, statics: &[UnitStatic], ti: usize, epoch: u32) {
    apply_cast_effect(
        statics, st, ti, &regen_spell(), 1.0,
        Seams { rules_epoch: epoch, ..Default::default() }, None,
    );
}

/// The recorded grant reads as Regeneration ONLY from EPOCH_73_V36. At 72 and
/// below the ledger stays blind and the unit's own static stamp decides.
#[test]
fn a_recorded_regeneration_grant_gives_a_regen_target_at_73_and_none_at_72() {
    let (mut st, statics) = buff_line();
    land_regen_grant(&mut st, &statics, 0, crate::acts::EPOCH_73_V36);
    let unit = &statics[st.roster.profile[0]];

    let ctx73 = ctx_live(ctx_of(unit, &st, 0), &statics, &st, 0, false, crate::acts::EPOCH_73_V36);
    assert!(ctx73.regeneration, "the grant must read as Regeneration at 73");
    assert_eq!(ctx73.regen_target, 5, "the granted target is the registry's 5+");
    assert_eq!(ctx73.regen_target_spell, 5, "spell wounds share the same 5+");

    let ctx72 = ctx_live(ctx_of(unit, &st, 0), &statics, &st, 0, false, 72);
    assert!(!ctx72.regeneration, "below 73 the grant stays blind");
    assert_eq!(ctx72.regen_target, 0, "below 73 no target");
}

/// (a) At 73 a zero-wound exchange does NOT spend the grant: no wound came in,
/// so Regeneration was never asked to turn one away.
#[test]
fn a_regeneration_grant_survives_a_zero_wound_exchange_at_73() {
    let (mut st, mut statics) = duel(0);
    land_regen_grant(&mut st, &statics, 1, EPOCH_73_V36);
    statics[0].melee[0].attacks = 0; // no attack dice -> no wounds at all
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    let (caused, _, _, _) = strike_phase(
        &statics, &mut st, 0, 1, false, 0.0,
        Seams { rules_epoch: EPOCH_73_V36, ..Default::default() },
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert_eq!(caused, 0, "the fixture resolves no wound");
    assert_eq!(st.buffs[1].len(), 1, "a zero-wound exchange leaves the grant in place");
}

/// (b) An exchange that brings wounds in, all of which Regeneration ignores,
/// still spends the grant: the roll it was granted for did happen.
#[test]
fn a_regeneration_grant_spends_when_the_roll_ignores_every_wound() {
    let (mut st, mut statics) = duel(0);
    land_regen_grant(&mut st, &statics, 1, EPOCH_73_V36);
    statics[1].ctx.regeneration = true;
    statics[1].ctx.regen_target = 2;
    statics[1].ctx.regen_target_spell = 2;
    let before = wounds_left(&st, 1);
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    let (caused, _, _, _) = strike_phase(
        &statics, &mut st, 0, 1, false, 0.0,
        Seams { rules_epoch: EPOCH_73_V36, ..Default::default() },
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert!(shot.rolls.iter().any(|x| x.owner == "Target" && x.target == 2),
        "the fixture must cause wounds for the roll to ignore");
    assert_eq!(caused, 0, "the roll ignored every wound");
    assert_eq!(wounds_left(&st, 1), before, "Regeneration ignored every wound");
    assert!(st.buffs[1].is_empty(), "an all-ignored exchange still spends the grant");
}

/// The holder's own attack still does NOT spend the grant at 73: Regeneration
/// applies to wounds its holder takes, not to the wounds it inflicts.
#[test]
fn a_regeneration_grant_is_not_spent_by_the_holders_own_attack() {
    let (mut st, statics) = duel(0);
    land_regen_grant(&mut st, &statics, 0, EPOCH_73_V36);
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0,
        Seams { rules_epoch: EPOCH_73_V36, ..Default::default() },
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert_eq!(st.buffs[0].len(), 1, "the striker's own attack leaves its grant untouched");
}

/// A wounding exchange spends the grant on the WOUNDED holder (the defender).
#[test]
fn a_regeneration_grant_spends_on_a_wounding_exchange() {
    let (mut st, statics) = duel(0);
    land_regen_grant(&mut st, &statics, 1, EPOCH_73_V36);
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0,
        Seams { rules_epoch: EPOCH_73_V36, ..Default::default() },
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert!(st.buffs[1].is_empty(), "the wounding exchange spends the grant");
}

/// (c) Below 73 the buff list after an exchange is byte-identical to the old
/// path: that path spent every once-grant unconditionally, on both sides.
#[test]
fn a_replay_below_73_spends_the_grant_the_way_the_old_path_did() {
    let below = Seams { rules_epoch: EPOCH_72_PLAYTEST_RULES, ..Default::default() };
    let (mut st, mut statics) = duel(0);
    land_regen_grant(&mut st, &statics, 1, EPOCH_72_PLAYTEST_RULES);
    statics[0].melee[0].attacks = 0;
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, below,
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert!(st.buffs[1].is_empty(), "at 72 the old path spends the defender's grant");

    let (mut st, statics) = duel(0);
    land_regen_grant(&mut st, &statics, 0, EPOCH_72_PLAYTEST_RULES);
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, below,
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert!(st.buffs[0].is_empty(), "at 72 the old path spends the attacker's grant too");
}
