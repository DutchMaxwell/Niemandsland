use super::*;

// DAT-17a — the Regeneration Buff engine half. A granted Regeneration is a
// one-time grant: the FIRST exchange that wounds its holder spends it. The
// holder's own attack does not spend it, and a zero-wound exchange does not
// spend it either. Wounds that bypass Regeneration still count as wounding the
// holder. RED first — none of these reads or spends exist today.

/// One recorded "Regeneration Buff" grant: a live `grants_rule: "Regeneration"`
/// once-record, as a spell's `duration: "once"` effect lands it.
fn regen_grant() -> mods::LiveMod {
    mods::LiveMod {
        hit_mod: 0,
        casting_mod: 0,
        morale_mod: 0,
        ap_mod: 0,
        def_mod: 0,
        defense_mod: 0,
        move_mod: 0,
        grants_rule: Rc::from("Regeneration"),
        scope: Rc::from(""),
        attackers: false,
        once: true,
        name: Rc::from("Regeneration Buff"),
    }
}

/// The recorded grant reads as Regeneration ONLY from EPOCH_73_V36. At 72 and
/// below the ledger stays blind and the unit's own static stamp decides.
#[test]
fn a_recorded_regeneration_grant_gives_a_regen_target_at_73_and_none_at_72() {
    let (mut st, statics) = buff_line();
    st.buffs[0].push(regen_grant());
    let unit = &statics[st.roster.profile[0]];

    let ctx73 = ctx_live(ctx_of(unit, &st, 0), &statics, &st, 0, false, crate::acts::EPOCH_73_V36);
    assert!(ctx73.regeneration, "the grant must read as Regeneration at 73");
    assert_eq!(ctx73.regen_target, 5, "the granted target is the registry's 5+");
    assert_eq!(ctx73.regen_target_spell, 5, "spell wounds share the same 5+");

    let ctx72 = ctx_live(ctx_of(unit, &st, 0), &statics, &st, 0, false, 72);
    assert!(!ctx72.regeneration, "below 73 the grant stays blind");
    assert_eq!(ctx72.regen_target, 0, "below 73 no target");
}

/// A zero-wound exchange does NOT spend the grant — today `spend_exchange`
/// burns every once-grant unconditionally.
#[test]
fn a_regeneration_grant_survives_a_zero_wound_exchange() {
    let (mut st, mut statics) = duel(0);
    st.buffs[1].push(regen_grant());
    statics[0].melee[0].attacks = 0; // no attack dice -> no wounds -> no spend
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, Seams::default(),
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert_eq!(st.buffs[1].len(), 1, "a zero-wound exchange leaves the grant in place");
}

/// The holder's own attack does NOT spend the grant: the striker wounds the
/// defender but takes no wounds itself. Today the attacker's once-grant is
/// burned regardless of who was wounded.
#[test]
fn a_regeneration_grant_is_not_spent_by_the_holders_own_attack() {
    let (mut st, statics) = duel(0);
    st.buffs[0].push(regen_grant());
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, Seams::default(),
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert_eq!(st.buffs[0].len(), 1, "the striker's own attack leaves its grant untouched");
}

/// A wounding exchange spends the grant on the WOUNDED holder (the defender).
#[test]
fn a_regeneration_grant_spends_on_a_wounding_exchange() {
    let (mut st, statics) = duel(0);
    st.buffs[1].push(regen_grant());
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    strike_phase(
        &statics, &mut st, 0, 1, false, 0.0, Seams::default(),
        &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None),
    );
    assert!(st.buffs[1].is_empty(), "the wounding exchange spends the grant");
}
