use super::*;
use crate::state::Weapon;

// ---- TEST WAVE 2026-09-15 — the two `marks` rows of proven_vs_read_part2
// (Furious Mark, Quick Shot Mark), judged CORRECT by READING both layers and
// pinned by nothing. The fixture shape is the merged vs-grant-marks wave's
// (#958/#979): place -> attack -> the facet lands on the marked target's
// exchange and is spent by it, never on the unmarked control. Neither
// placement carries a rules-must-log line (the trace is Surge Mark's own),
// so the numbers are the witness. Both by the rule's EXACT NAME through the
// REAL gf registry, at `CURRENT_RULES_EPOCH` — no epoch bump, nothing
// changes behaviour.

/// The carrier: a two-model "a" whose ONLY rule is the named mark, read off
/// the REAL registry (gf rebel_guerrillas prints Furious Mark, gf
/// wormhole_daemons_of_lust Quick Shot Mark — the two rows' own pairs). A
/// 24" 8-shot rifle and a 6-attack CCW, both AP(0).
fn mark_carrier(rule: &str, faction: &str, rules_epoch: u32) -> UnitStatic {
    let p = Profile {
        unit_id: "a".into(),
        name: "a".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1, 1],
        model_count: 2,
        weapons: vec![
            Weapon { name: "Rifle".into(), range: 24.0, attacks: 8, count: 1, ap: 0, rules: vec![] },
            Weapon { name: "CCW".into(), range: 0.0, attacks: 6, count: 1, ap: 0, rules: vec![] },
        ],
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

/// `run_buff` with the record's own `rules_epoch` (Seams::default() rides
/// epoch 0, which no live mark leg lives at).
fn run_marks_epoch(
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

/// The defense rolls the volley drew, summed — the hit count the saves ran on.
fn defense_count(r: &ShootResult) -> i64 {
    r.rolls.iter().filter(|x| x.kind == "defense").map(|x| x.count).sum()
}

/// The carrier on "a", the enemy hardened to three models of three wounds so
/// the marked exchange can never wipe the target before the spent one fires.
fn mark_line(rule: &str, faction: &str, epoch: u32) -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    let carrier = mark_carrier(rule, faction, epoch);
    let mut a = UnitStatic { model_count: 2, wounds_max: vec![1, 1], ..carrier };
    a.shoot = vec![gun("Rifle", 8, 24)];
    statics[0] = a;
    statics[2].wounds_max = vec![3, 3, 3];
    st.wounds[2] = vec![3, 3, 3];
    (st, statics)
}

/// Furious Mark (gf rebel_guerrillas, `grants_rule: "Furious"`, vs_target):
/// the charge seam places the mark, the marked exchange's melee strikes pay
/// Furious's +1 hit per unmodified 6 (charge only), and the exchange spends
/// the once-grant — seed 7's six CCW faces carry three unmodified 6s, so the
/// marked charge out-defends the spent one by exactly 3 — while the
/// rule-less control pays nothing anywhere.
#[test]
fn furious_mark_pays_the_extra_six_hits_once_on_the_marked_charge() {
    use crate::acts::CURRENT_RULES_EPOCH;
    let e = CURRENT_RULES_EPOCH;
    let stamp = mark_carrier("Furious Mark", "rebel_guerrillas", e);
    assert_eq!(stamp.utility_buffs.len(), 1, "the mark reads as the vs_target Utility Buff");
    assert!(stamp.utility_buffs[0].vs_target, "the mark rides the attack seam");
    assert_eq!(stamp.utility_buffs[0].grants_rule, "Furious", "the entry's grants_rule");

    let (mut st, statics) = mark_line("Furious Mark", "rebel_guerrillas", e);
    st.positions[2] = vec![
        [2.5 * IN2M, 0.0, 0.0],
        [2.52 * IN2M, 0.0, 0.0],
        [2.54 * IN2M, 0.0, 0.0],
    ];
    let charge = Action {
        kind: CHARGE,
        unit: "a".into(),
        dest: None,
        shoot: None,
        charge: Some("b".into()),
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    };
    let (next1, s1) = run_marks_epoch(&st, &statics, &charge, 7, e);
    assert_eq!(next1.vs_mark_round[0], st.round, "the charge seam placed the mark");
    let strike = s1
        .rolls
        .iter()
        .find(|x| x.kind == "attack" && x.count == 6)
        .expect("the CCW strike");
    let sixes = strike.faces.iter().filter(|f| **f == 6).count() as i64;
    assert!(sixes >= 1, "fixture guard: the six CCW faces carry an unmodified 6");
    let v1 = defense_count(&s1);
    let (next2, s2) = run_marks_epoch(&next1, &statics, &charge, 7, e);
    let v2 = defense_count(&s2);

    // The unmarked control: the same seed and the same two charges, no rule.
    // Quality 2 on the target keeps its morale die passing (2+) so the second
    // charge still has a live target. Both second charges are FATIGUED
    // charges (the first charge fatigues the charger), so the spent exchange
    // is compared against the control's own second charge, not the first.
    let (mut st0, mut statics0) = buff_line();
    statics0[0].melee = vec![gun("CCW", 6, 0)];
    statics0[0].shoot = vec![gun("Rifle", 8, 24)];
    statics0[2].wounds_max = vec![3, 3, 3];
    statics0[2].ctx.quality = 2;
    st0.wounds[2] = vec![3, 3, 3];
    st0.positions[2] = vec![
        [2.5 * IN2M, 0.0, 0.0],
        [2.52 * IN2M, 0.0, 0.0],
        [2.54 * IN2M, 0.0, 0.0],
    ];
    let (nextc1, c1) = run_marks_epoch(&st0, &statics0, &charge, 7, e);
    let (_, c2) = run_marks_epoch(&nextc1, &statics0, &charge, 7, e);
    let plain1 = defense_count(&c1);
    let plain2 = defense_count(&c2);

    assert_eq!(
        v1 - plain1, sixes,
        "+1 hit per unmodified 6 on the marked charge ({} vs the plain {})",
        v1, plain1
    );
    assert_eq!(v2, plain2, "once: the spent exchange reads plain against the marked target");
    assert_eq!(
        next2.vs_mark_round[0], next1.vs_mark_round[0],
        "once per round: the mark does not re-place"
    );
}

/// Quick Shot Mark (gf wormhole_daemons_of_lust, `grants_rule: "Quick
/// Shot"`, scope "shooting", the pick kind — the entry carries no
/// `vs_target`): the pick lands the row on the marked enemy as an
/// ATTACKERS-side once-record, never on the marker's own net, and the first
/// exchange with the marked enemy spends it. No fold reads the grant
/// target-aware yet (RULE_FIDELITY_WAVE2's own finding), so the record — by
/// its exact name — is the row's whole core read.
#[test]
fn quick_shot_mark_lands_its_shooting_scoped_record_on_the_marked_enemy_once() {
    use crate::acts::CURRENT_RULES_EPOCH;
    let e = CURRENT_RULES_EPOCH;
    let stamp = mark_carrier("Quick Shot Mark", "wormhole_daemons_of_lust", e);
    assert_eq!(stamp.utility_buffs.len(), 1, "the mark reads as the Utility Buff pick");
    assert!(!stamp.utility_buffs[0].vs_target, "the pick kind — the record rides the utility seam");
    assert_eq!(stamp.utility_buffs[0].grants_rule, "Quick Shot", "the entry's grants_rule");
    assert_eq!(stamp.utility_buffs[0].scope, "shooting", "the entry's own scope");
    assert_eq!(stamp.utility_buffs[0].range_in, 18.0, "the entry's pick range");

    let (st, statics) = mark_line("Quick Shot Mark", "wormhole_daemons_of_lust", e);
    let (next, _) = run_marks_epoch(&st, &statics, &buff_action(None), 9, e);
    assert_eq!(
        next.buffs[2].len(),
        1,
        "the pick lands one record on the marked enemy (12\" inside the 18\" pick)"
    );
    let rec = &next.buffs[2][0];
    assert_eq!(&*rec.name, "Quick Shot Mark", "the record's own name (#489)");
    assert_eq!(&*rec.grants_rule, "Quick Shot", "the record's grant");
    assert_eq!(&*rec.scope, "shooting", "the record's scope");
    assert!(rec.attackers, "the record belongs to whoever attacks the marked unit");
    assert!(rec.once, "duration once");
    assert!(next.buffs[0].is_empty(), "nothing lands on the marker's own net");

    // The first exchange with the marked enemy spends the once-record.
    let (next1, _) = run_marks_epoch(&st, &statics, &buff_action(Some("b")), 9, e);
    assert!(next1.buffs[2].is_empty(), "the exchange spends the once-record");

    // The rule-less control: no record anywhere.
    let (st0, mut statics0) = buff_line();
    statics0[0].shoot = vec![gun("Rifle", 8, 24)];
    let (next0, _) = run_marks_epoch(&st0, &statics0, &buff_action(None), 9, e);
    assert!(
        next0.buffs[2].is_empty() && next0.buffs[0].is_empty(),
        "no rule, no record"
    );
}
