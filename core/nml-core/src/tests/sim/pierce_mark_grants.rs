use super::*;

// ------------- EPOCH 21 INERT MARKS — the two Piercing marks' grants must fold -------------

/// MARK_FAMILY_SWEEP_2026-09-14, INERT row (finding 1): the #870 vs_target
/// marks Piercing Fighting Mark / Piercing Shooting Mark land their once-grant
/// on the attacker under the BASE name ("Piercing Fighting" / "Piercing
/// Shooting"), and no grant reader in either layer asks for those names. The
/// only grant readers ask for the entry's own `grants_rule` strings —
/// "AP(+1) in melee" / "AP(+1) when shooting" (sim.rs `ctx_live`, the two
/// dice folds at dice.rs) — and can never match one, so both layers stamp and
/// spend the mark and nothing folds. Knobs with no wire.
///
/// The registry entry says what the effect IS (unit.rs:324-327 quotes the
/// printed army-book wording): AP(+1) in melee / AP(+1) when shooting for
/// whoever attacks the marked unit, once. Every mechanism piece already
/// exists: the epoch-9 once-grant (`tray_vs_marks`) and the two AP folds off
/// `Ctx::pierce_melee_grant` / `Ctx::pierce_shooting_grant`. The link between
/// them is missing. These tests pin the board leg at the frozen
/// `EPOCH_21_INERT_MARKS`: at 21 the mark's exchange saves one rung harder;
/// at 20 (and every epoch below) the corpus keeps the recorded inert mark.
///
/// The carrier is `buff_line`'s shooter with the mark hand-stamped exactly as
/// the registry ships it (the aof goblins / gf dao_union entry shape:
/// vs_target, beneficiary "attackers", grants_rule, scope, once, 18", LOS).
fn pierce_line(rule: &str, grants_rule: &str, scope: &str) -> (State, Vec<UnitStatic>) {
    let (st, mut statics) = buff_line();
    statics[0].shoot = vec![gun("Rifle", 6, 24)];
    statics[0].utility_buffs = vec![UtilityBuff {
        vs_target: true,
        needs_los: true,
        range_in: 18.0,
        once: true,
        grants_rule: grants_rule.into(),
        scope: scope.into(),
        beneficiary: "attackers".into(),
        ..ub(rule)
    }];
    (st, statics)
}

/// Every save batch the report recorded, as (target) in draw order — the AP
/// rung is observable there and nowhere else (`save_target(defense, ap)`).
fn save_targets(res: &ShootResult) -> Vec<i64> {
    res.rolls
        .iter()
        .filter(|r| r.kind == "defense")
        .map(|r| r.target)
        .collect()
}

/// `run_buff` with the record's own `rules_epoch` (Seams::default() rides
/// epoch 0, which no mark leg under test here lives at).
fn run_pierce_epoch(
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

/// Shooting leg (gf dao_union's Piercing Shooting Mark, "AP(+1) when
/// shooting"): the volley's save batch rides AP(+1) from 21 on, never below.
/// Seed 13's first four hit faces at 4+ are [4,3,6,6] — three hits, so the
/// save batch ALWAYS draws (the buff_consumption_bridge seed-13 precedent).
#[test]
fn piercing_shooting_mark_ap_fires_from_21_and_not_below() {
    let (st, statics) = pierce_line("Piercing Shooting Mark", "AP(+1) when shooting", "shooting");

    // ----- epoch 21: the fix — the granted AP reaches the volley's saves -----
    let (next21, marked21) = run_pierce_epoch(&st, &statics, &buff_action(Some("b")), 13, 21);
    assert_eq!(
        next21.vs_mark_round[0],
        st.round,
        "the mark fired at the attack seam"
    );
    let saves21 = save_targets(&marked21);
    assert!(!saves21.is_empty(), "seed 13 lands hits, the save batch draws");
    assert!(
        saves21.iter().all(|&t| t == 5),
        "at 21 every save rides AP(+1): defense 4 saves at 5+, got {:?}",
        saves21
    );

    // ----- epoch 20: the corpus leg — the recorded inert mark still stands -----
    let (_, marked20) = run_pierce_epoch(&st, &statics, &buff_action(Some("b")), 13, 20);
    let saves20 = save_targets(&marked20);
    assert!(!saves20.is_empty(), "the same seed draws the same hits at 20");
    assert!(
        saves20.iter().all(|&t| t == 4),
        "below 21 the mark is spent for nothing, as recorded: got {:?}",
        saves20
    );

    // ----- epoch 19: the LIVE predecessor epoch of this bump (#935's move-
    // grants fold, 18 was #932's reservation) — the pre-bump reading by name,
    // and every smaller epoch replays byte-identically with it.
    assert_eq!(
        crate::acts::EPOCH_19_MOVE_GRANTS_FOLD, 19,
        "the live epoch the corpus legs below replay is this bump's predecessor"
    );
    let (_, marked19) = run_pierce_epoch(&st, &statics, &buff_action(Some("b")), 13, 19);
    let saves19 = save_targets(&marked19);
    assert!(!saves19.is_empty(), "the same seed draws the same hits at 19");
    assert!(
        saves19.iter().all(|&t| t == 4),
        "epoch 19 replays the recorded inert mark exactly: got {:?}",
        saves19
    );
}

/// Melee leg (aof goblins' Piercing Fighting Mark, "AP(+1) in melee"): the
/// #929 charge fixture — the marked enemy pulled to 2.5" so the charge
/// connects — with a 24-attack CCW so the strike save batch always draws
/// (seed 11's first 24 faces carry 17 hits at 3+).
#[test]
fn piercing_fighting_mark_ap_fires_from_21_and_not_below() {
    let (mut st, mut statics) = pierce_line("Piercing Fighting Mark", "AP(+1) in melee", "melee");
    st.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0]];
    st.radii[2] = vec![IN2M];
    st.wounds[2] = vec![1];
    st.alive[2] = 1;
    statics[2].model_count = 1;
    statics[2].wounds_max = vec![1];
    statics[0].melee = vec![gun("CCW", 24, 0)];
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

    // ----- epoch 21: the fix — the granted AP reaches the strikes' saves -----
    let (next21, struck21) = run_pierce_epoch(&st, &statics, &charge, 11, 21);
    assert_eq!(next21.vs_mark_round[0], st.round, "the mark fired on the charge");
    let saves21 = save_targets(&struck21);
    assert!(!saves21.is_empty(), "seed 11 carries 17 hits at 3+ — the strike saves draw");
    assert!(
        struck21.rolls.iter().any(|r| r.kind == "attack" && r.target == 4),
        "the charge strikes at the bare Quality 4+ — the mark's +1 is AP only"
    );
    assert!(
        saves21.iter().all(|&t| t == 5),
        "at 21 every strike save rides AP(+1): defense 4 saves at 5+, got {:?}",
        saves21
    );

    // ----- epoch 20: the corpus leg — the recorded inert mark still stands -----
    let (_, struck20) = run_pierce_epoch(&st, &statics, &charge, 11, 20);
    let saves20 = save_targets(&struck20);
    assert!(!saves20.is_empty(), "the same seed draws the strike saves at 20");
    assert!(
        saves20.iter().all(|&t| t == 4),
        "below 21 the mark is stamped and spent for nothing, as recorded: got {:?}",
        saves20
    );

    // ----- epoch 19: the LIVE predecessor epoch of this bump (#935) — the
    // pre-bump reading; every smaller epoch replays identically with it.
    let (_, struck19) = run_pierce_epoch(&st, &statics, &charge, 11, 19);
    let saves19 = save_targets(&struck19);
    assert!(!saves19.is_empty(), "the same seed draws the strike saves at 19");
    assert!(
        saves19.iter().all(|&t| t == 4),
        "epoch 19 replays the recorded inert mark exactly: got {:?}",
        saves19
    );
}
