use super::*;

// ------------- EPOCH 15 MARK BENEFICIARY — which side the Precision marks feed -------------

/// The carrier: an "a" whose ONLY rule is the named mark, read off the REAL
/// registry (gf dark_elf_raiders prints Precision Fighting Mark, gf
/// soul_snatcher_cults Precision Shooting Mark — the wrong-side pair of
/// MARK_FAMILY_SWEEP_2026-09-14).
fn mark_carrier(rule: &str, faction: &str, rules_epoch: u32) -> UnitStatic {
    let p = Profile {
        unit_id: "a".into(),
        name: "a".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1],
        model_count: 1,
        weapons: vec![],
        special_rules: vec![rule.into()],
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: faction.into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    };
    let mut reg = crate::rules::Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, rules_epoch)
}

/// The stamp IS the fix: from the frozen `EPOCH_15_MARK_BENEFICIARY` the
/// registry's `beneficiary: "attackers"` rides the stamp, so `record_buff`
/// lands the row on the marked enemy as an ATTACKERS-side record (`Role::
/// VsTarget`). Below 15 the key reads as absent — every corpus recorded at 14
/// or below replays the wrong side it was recorded with. The mark stays OUT of
/// the vs-grant seam in both legs (`vs_target` false): it is a modifier mark,
/// picked once per activation at the utility seam, not a rule grant.
#[test]
fn precision_marks_stamp_the_attackers_beneficiary_from_15_and_nothing_below() {
    let at_15 = mark_carrier("Precision Fighting Mark", "dark_elf_raiders", 15);
    assert_eq!(at_15.utility_buffs.len(), 1);
    assert_eq!(at_15.utility_buffs[0].beneficiary, "attackers");
    assert!(!at_15.utility_buffs[0].vs_target);

    let at_14 = mark_carrier("Precision Fighting Mark", "dark_elf_raiders", 14);
    assert_eq!(at_14.utility_buffs.len(), 1);
    assert_eq!(
        at_14.utility_buffs[0].beneficiary,
        "",
        "the epoch-14 corpus leg: the key reads as absent, the old wrong side stands"
    );
    assert!(!at_14.utility_buffs[0].vs_target);

    let psm_15 = mark_carrier("Precision Shooting Mark", "soul_snatcher_cults", 15);
    assert_eq!(psm_15.utility_buffs[0].beneficiary, "attackers");
    let psm_14 = mark_carrier("Precision Shooting Mark", "soul_snatcher_cults", 14);
    assert_eq!(psm_14.utility_buffs[0].beneficiary, "");
}

/// The board picture (MARK_FAMILY_SWEEP_2026-09-14): a player marks the enemy
/// regiment, spends the once-per-activation pick — and the +1 must land on the
/// rolls made AGAINST that regiment, never on the regiment's own. At 15 the
/// marked unit's own to-hit fold stays clean and its `vs_hit_mod` carries the
/// +1 for whoever attacks it; at 14 the corpus leg keeps the recorded wrong
/// side: the marked unit's OWN rolls carry the +1 and the attacker gets
/// nothing.
#[test]
fn precision_fighting_mark_bonus_feeds_the_rolls_against_the_marked_unit_at_15_not_the_marks_own_at_14() {
    // ----- epoch 15: the fix -----
    let (st, mut statics) = buff_line();
    let carrier = mark_carrier("Precision Fighting Mark", "dark_elf_raiders", 15);
    let mut a = UnitStatic { model_count: 2, wounds_max: vec![1, 1], ..carrier };
    a.melee = vec![gun("CCW", 1, 0)];
    statics[0] = a;
    let (next, _) = run_mark_epoch(&st, &statics, &buff_action(None), 11, 15);
    assert_eq!(next.buffs[2].len(), 1, "the pick lands on the marked enemy");
    assert!(
        next.buffs[2][0].attackers,
        "the row belongs to whoever attacks the marked unit, never to its own net"
    );
    let c = ctx_live(statics[2].ctx, &statics, &next, 2, true, 15);
    assert_eq!(c.hit_mod, 0, "the marked unit's OWN rolls are untouched");
    assert_eq!(c.vs_hit_mod, 1, "+1 to the rolls made against the marked unit");

    // The charge that follows in the same activation strikes at 3+ where the
    // bare fixture strikes at 4+.
    let (mut st2, mut statics2) = buff_line();
    st2.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0]];
    st2.radii[2] = vec![IN2M];
    st2.wounds[2] = vec![1];
    st2.alive[2] = 1;
    statics2[2].model_count = 1;
    statics2[2].wounds_max = vec![1];
    let carrier15 = mark_carrier("Precision Fighting Mark", "dark_elf_raiders", 15);
    let mut a15 = UnitStatic { model_count: 2, wounds_max: vec![1, 1], ..carrier15 };
    a15.melee = vec![gun("CCW", 1, 0)];
    statics2[0] = a15;
    let (_, buffed) = run_mark_epoch(&st2, &statics2, &mark_charge(), 11, 15);
    assert_eq!(buffed.rolls[0].target, 3, "the attacker hits at 3+ against the marked unit");

    // ----- epoch 14: the corpus leg — the wrong side still stands -----
    let (st3, mut statics3) = buff_line();
    let carrier14 = mark_carrier("Precision Fighting Mark", "dark_elf_raiders", 14);
    let mut a14 = UnitStatic { model_count: 2, wounds_max: vec![1, 1], ..carrier14 };
    a14.melee = vec![gun("CCW", 1, 0)];
    statics3[0] = a14;
    let (next14, _) = run_mark_epoch(&st3, &statics3, &buff_action(None), 11, 14);
    assert_eq!(next14.buffs[2].len(), 1);
    assert!(
        !next14.buffs[2][0].attackers,
        "recorded at 14: the row sits in the marked unit's own net"
    );
    let c14 = ctx_live(statics3[2].ctx, &statics3, &next14, 2, true, 14);
    assert_eq!(c14.hit_mod, 1, "the marked unit's OWN rolls carry the +1 — the recorded wrong side");
    assert_eq!(c14.vs_hit_mod, 0, "the attacker gets nothing, as recorded");

    let (mut st4, mut statics4) = buff_line();
    st4.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0]];
    st4.radii[2] = vec![IN2M];
    st4.wounds[2] = vec![1];
    st4.alive[2] = 1;
    statics4[2].model_count = 1;
    statics4[2].wounds_max = vec![1];
    let carrier14b = mark_carrier("Precision Fighting Mark", "dark_elf_raiders", 14);
    let mut a14b = UnitStatic { model_count: 2, wounds_max: vec![1, 1], ..carrier14b };
    a14b.melee = vec![gun("CCW", 1, 0)];
    statics4[0] = a14b;
    let (_, plain) = run_mark_epoch(&st4, &statics4, &mark_charge(), 11, 14);
    assert_eq!(plain.rolls[0].target, 4, "no attacker bonus at 14 — the corpus replays unchanged");
}

fn mark_charge() -> Action {
    Action {
        kind: CHARGE,
        unit: "a".into(),
        dest: None,
        shoot: None,
        charge: Some("b".into()),
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    }
}

/// `run_buff` with the record's own `rules_epoch` (Seams::default() rides
/// epoch 0, which no mark leg under test here lives at).
fn run_mark_epoch(
    st: &State,
    statics: &[UnitStatic],
    action: &Action,
    seed: i64,
    epoch: u32,
) -> (State, ShootResult) {
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(seed);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        statics,
        st,
        action,
        &terrain,
        Seams { rules_epoch: epoch, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .unwrap()
}
