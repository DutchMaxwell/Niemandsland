use super::*;
use crate::state::Weapon;
use crate::combat::BEST_HIT_TARGET;

// ---- TEST WAVE 2026-09-14, the marks (vs-grants) family — the four `none`
// rows of `proven_vs_read.tsv` (sweeps B/C judged them CORRECT by READING
// both layers; nothing pinned their numbers). One test per row, each by the
// rule's EXACT NAME, at `CURRENT_RULES_EPOCH` — no epoch bump, nothing
// changes behaviour. The fixture shape is the merged Surge Mark #958 one:
// place -> attack -> the facet lands on the marked target's exchange and is
// spent by it, never on the unmarked control. None of the four reads has a
// trace line (the placement trace is Surge Mark's own), so there is no log
// line to pin.

/// The carrier: a two-model "a" whose ONLY rule is the named mark, read off
/// the REAL registry (gf human_defense_force prints Relentless Mark, gf
/// orc_marauders Rending Mark, gf custodian_brothers Shred Mark, gf
/// alien_hives Unpredictable Fighter Mark — the four rows' own pairs). A
/// 24" 8-shot rifle (seed 9's eight faces carry two unmodified 6s) and a
/// 6-attack CCW, both AP(0).
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
            Weapon {
                name: "Rifle".into(),
                range: 24.0,
                attacks: 8,
                count: 1,
                ap: 0,
                rules: vec![],
            },
            Weapon {
                name: "CCW".into(),
                range: 0.0,
                attacks: 6,
                count: 1,
                ap: 0,
                rules: vec![],
            },
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

/// The defense rolls the volley drew, summed — the hit count the saves ran on
/// (the surge_mark precedent).
fn defense_count(r: &ShootResult) -> i64 {
    r.rolls.iter().filter(|x| x.kind == "defense").map(|x| x.count).sum()
}

/// The carrier on "a", the enemy hardened to three models of three wounds so
/// the marked volley can never wipe the target before the spent one fires.
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

/// Relentless Mark (gf human_defense_force, `grants_rule: "Relentless"`,
/// vs_target): the attack seam places the mark, the once-grant pays +1 hit
/// per unmodified 6 PAST the 9" long-range gate (12" here) — seed 9's eight
/// faces carry two 6s, so the marked volley out-hits the spent one by exactly
/// 2 — and the rule-less control pays nothing anywhere.
#[test]
fn relentless_mark_pays_the_extra_six_hits_once_against_the_marked_target() {
    use crate::acts::CURRENT_RULES_EPOCH;
    let e = CURRENT_RULES_EPOCH;
    let stamp = mark_carrier("Relentless Mark", "human_defense_force", e);
    assert_eq!(stamp.utility_buffs.len(), 1, "the mark reads as the vs_target Utility Buff");
    assert!(stamp.utility_buffs[0].vs_target, "the mark rides the attack seam");
    assert_eq!(stamp.utility_buffs[0].grants_rule, "Relentless", "the entry's grants_rule");

    let (st, statics) = mark_line("Relentless Mark", "human_defense_force", e);
    let action = buff_action(Some("b"));
    let (next1, r1) = run_marks_epoch(&st, &statics, &action, 9, e);
    assert_eq!(next1.vs_mark_round[0], st.round, "the attack seam placed the mark");
    let sixes = r1
        .rolls
        .first()
        .expect("the attack roll comes first")
        .faces
        .iter()
        .filter(|f| **f == 6)
        .count() as i64;
    assert!(sixes >= 1, "fixture guard: the eight attack faces carry an unmodified 6");
    let v1 = defense_count(&r1);
    let (next2, r2) = run_marks_epoch(&next1, &statics, &action, 9, e);
    let v2 = defense_count(&r2);
    assert_eq!(
        v1 - v2, sixes,
        "+1 hit per unmodified 6 past 9\" (12\" here), spent with the exchange: {} vs {}",
        v1, v2
    );
    assert!(v2 >= 1, "the spent volley still rolls its plain hits");
    assert_eq!(
        next2.vs_mark_round[0], next1.vs_mark_round[0],
        "once per round: the mark does not re-place"
    );

    // The unmarked control: without the rule the same seed rolls no bonus at
    // all, in either volley.
    let (st0, mut statics0) = buff_line();
    statics0[0].shoot = vec![gun("Rifle", 8, 24)];
    let (_, r0a) = run_marks_epoch(&st0, &statics0, &action, 9, e);
    let (_, r0b) = run_marks_epoch(&st0, &statics0, &action, 9, e);
    assert_eq!(
        defense_count(&r0a),
        defense_count(&r0b),
        "no rule, no grant: both control volleys roll plain"
    );
}

/// Rending Mark (gf orc_marauders, `grants_rule: "Rending"`, vs_target): the
/// marked volley's unmodified 6s save one batch deeper — defense 4 + the
/// rending AP(4) bonus = target 8, an impossible d6 save — while the spent
/// exchange rolls every save at the plain 4.
#[test]
fn rending_mark_saves_the_marked_target_sixes_at_ap4_once() {
    use crate::acts::CURRENT_RULES_EPOCH;
    let e = CURRENT_RULES_EPOCH;
    let stamp = mark_carrier("Rending Mark", "orc_marauders", e);
    assert_eq!(stamp.utility_buffs.len(), 1, "the mark reads as the vs_target Utility Buff");
    assert!(stamp.utility_buffs[0].vs_target, "the mark rides the attack seam");
    assert_eq!(stamp.utility_buffs[0].grants_rule, "Rending", "the entry's grants_rule");

    let (st, statics) = mark_line("Rending Mark", "orc_marauders", e);
    let action = buff_action(Some("b"));
    let (next1, r1) = run_marks_epoch(&st, &statics, &action, 9, e);
    assert_eq!(next1.vs_mark_round[0], st.round, "the attack seam placed the mark");
    assert!(
        r1.rolls.iter().any(|x| x.kind == "defense" && x.count == 2 && x.target == 8),
        "the two unmodified 6s save one batch at defense 4 + AP(4) = 8 — no d6 ever passes"
    );
    let (_, r2) = run_marks_epoch(&next1, &statics, &action, 9, e);
    assert!(
        r2.rolls.iter().all(|x| x.kind != "defense" || x.target == 4),
        "the spent exchange rolls every save at the plain defense 4: {:?}",
        r2.rolls
    );

    // The unmarked control: without the rule no save batch leaves the plain 4.
    let (st0, mut statics0) = buff_line();
    statics0[0].shoot = vec![gun("Rifle", 8, 24)];
    let (_, r0) = run_marks_epoch(&st0, &statics0, &action, 9, e);
    assert!(
        r0.rolls.iter().all(|x| x.kind != "defense" || x.target == 4),
        "no rule, no AP(4) batch"
    );
}

/// Shred Mark (gf custodian_brothers, `grants_rule: "Shred"`, NOT vs_target —
/// the pick kind): the once-per-activation utility pick lands the row on the
/// marked enemy as an ATTACKERS-side record, the volley's failed natural 1s
/// each pay one extra shred wound, and the exchange spends the record.
#[test]
fn shred_mark_lands_the_attackers_record_and_the_failed_ones_pay_one_extra_wound() {
    use crate::acts::CURRENT_RULES_EPOCH;
    let e = CURRENT_RULES_EPOCH;
    let stamp = mark_carrier("Shred Mark", "custodian_brothers", e);
    assert_eq!(stamp.utility_buffs.len(), 1, "the mark reads as the Utility Buff pick");
    assert!(!stamp.utility_buffs[0].vs_target, "the pick kind — the record rides the utility seam");
    assert_eq!(stamp.utility_buffs[0].grants_rule, "Shred", "the entry's grants_rule");

    let (st, mut statics) = buff_line();
    let carrier = mark_carrier("Shred Mark", "custodian_brothers", e);
    let mut a = UnitStatic { model_count: 2, wounds_max: vec![1, 1], ..carrier };
    a.shoot = vec![gun("Rifle", 8, 24)];
    statics[0] = a;

    // The pick lands the row on the marked enemy, on the ATTACKERS side
    // (mark_beneficiary precedent), and stays until an exchange reads it.
    let (next, _) = run_marks_epoch(&st, &statics, &buff_action(None), 9, e);
    assert_eq!(next.buffs[2].len(), 1, "the pick lands on the marked enemy");
    assert!(
        next.buffs[2][0].attackers,
        "the row belongs to whoever attacks the marked unit, never to its own net"
    );
    assert_eq!(&*next.buffs[2][0].grants_rule, "Shred", "the record's grant");

    // The number, on the dice tray: the attacker's volley against the marked
    // unit reads the record through `ctx_live_vs`'s granted_vs fold, and the
    // same tray rolls both save batches, so the delta IS the record's number.
    let prof = [ShootProfile { range: 24, attacks: 64, ..Default::default() }];
    let defc = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    let volley = |att: &Ctx| {
        let mut tray = Tray::seeded(9);
        crate::dice::resolve_volley_with_tray(
            &[crate::dice::Shooter { profiles: &prof, keep: &[0], attacks: &[64], att, owner: "att" }],
            &defc, "b", 12.0, 12.0, false, true, true, true, &mut tray,
        )
    };
    let marked_att =
        ctx_live_vs(ctx_of(&statics[next.roster.profile[0]], &next, 0), &statics, &next, 0, 2, false, e);
    let plain_att =
        ctx_live_vs(ctx_of(&statics[st.roster.profile[0]], &st, 0), &statics, &st, 0, 2, false, e);
    let with = volley(&marked_att);
    let without = volley(&plain_att);
    let ones: i64 = with
        .rolls
        .iter()
        .filter(|x| x.kind == "defense")
        .map(|x| x.faces.iter().filter(|f| **f == 1).count() as i64)
        .sum();
    assert!(ones >= 1, "fixture guard: the save batch drew at least one natural 1");
    assert_eq!(
        with.wounds - without.wounds,
        ones,
        "each failed natural 1 pays one extra shred wound against the marked target: {} -> {}",
        without.wounds,
        with.wounds
    );

    // The real seam spends the once-record with the exchange.
    let (next1, _) = run_marks_epoch(&st, &statics, &buff_action(Some("b")), 9, e);
    assert!(next1.buffs[2].is_empty(), "the exchange spends the once-record");
}

/// Unpredictable Fighter Mark (gf alien_hives, `grants_rule: "Unpredictable
/// Fighter"`, vs_target): the charge seam places the mark and the melee
/// exchange rolls the ONE phase die before anything else — 1-3 is AP(+1) on
/// every melee weapon (save target 4 -> 5), 4-6 is +1 to hit (Quality 4 -> 3)
/// — and the spent exchange rolls no phase die.
#[test]
fn unpredictable_fighter_mark_rolls_the_phase_die_against_the_marked_target_once() {
    use crate::acts::CURRENT_RULES_EPOCH;
    let e = CURRENT_RULES_EPOCH;
    let stamp = mark_carrier("Unpredictable Fighter Mark", "alien_hives", e);
    assert_eq!(stamp.utility_buffs.len(), 1, "the mark reads as the vs_target Utility Buff");
    assert!(stamp.utility_buffs[0].vs_target, "the mark rides the attack seam");
    assert_eq!(
        stamp.utility_buffs[0].grants_rule, "Unpredictable Fighter",
        "the entry's grants_rule"
    );

    let (mut st, statics) = mark_line("Unpredictable Fighter Mark", "alien_hives", e);
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
    let (next1, s1) = run_marks_epoch(&st, &statics, &charge, 9, e);
    assert_eq!(next1.vs_mark_round[0], st.round, "the charge seam placed the mark");
    let phase = s1.rolls.first().expect("the phase die comes before anything else");
    assert_eq!(phase.count, 1, "ONE die for the whole phase");
    assert_eq!(phase.target, BEST_HIT_TARGET, "the phase die is scored as its own roll");
    let face = phase.faces[0] as i64;
    let (want_ap, want_hit) = if face <= 3 { (1, 4) } else { (0, 3) };
    let strike = s1
        .rolls
        .iter()
        .find(|x| x.kind == "attack" && x.count != 1)
        .expect("the CCW strike");
    assert_eq!(
        strike.target, want_hit,
        "face {}: 4-6 is +1 to hit (Quality 4 -> 3), 1-3 leaves the roll",
        face
    );
    let save = s1.rolls.iter().find(|x| x.kind == "defense").expect("the save batch");
    assert_eq!(
        save.target,
        4 + want_ap,
        "face {}: 1-3 is AP(+1) on every melee weapon, 4-6 none",
        face
    );

    // Spent: the second charge rolls no phase die.
    let (_, s2) = run_marks_epoch(&next1, &statics, &charge, 9, e);
    assert!(
        !s2.rolls.first().is_some_and(|x| x.count == 1),
        "once: the spent exchange rolls no phase die: {:?}",
        s2.rolls
    );
}
