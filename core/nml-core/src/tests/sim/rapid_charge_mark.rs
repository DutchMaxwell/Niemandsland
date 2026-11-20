use super::*;

#[test]
fn marked_target_opens_a_fourteen_inch_charge_only_at_epoch_66() {
    let (mut st, mut statics) = vr_charge_line(14.0);
    let charger_profile: Profile = serde_json::from_str(
        r#"{"unit_id":"a","name":"Charger","game_system":"aof","faction_folder":"dark_elves"}"#,
    ).unwrap();
    let mut registry = crate::rules::Registries::new(&repo_root());
    let charger_stamp = UnitStatic::build_for(&mut registry, &charger_profile, 66);
    assert_eq!(charger_stamp.rapid_charge_grant_in, 4.0,
        "the charger's book supplies the Mark's four inches");
    statics[0].rapid_charge_grant_in = charger_stamp.rapid_charge_grant_in;
    // Keep the target alive so the post-charge base gap remains measurable.
    st.wounds[1] = vec![20];
    statics[1].ctx.tough = 20;
    statics[1].wounds_max = vec![20];
    st.buffs[1].push(mods::LiveMod {
        hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0,
        def_mod: 0, defense_mod: 0, move_mod: 0, range_in: 0,
        grants_rule: Rc::from("Rapid Charge"), scope: Rc::from("melee"),
        attackers: true, once: true, name: Rc::from("Rapid Charge Mark"),
    });
    let charge = vr_charge();
    let run = |epoch| {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &small_board(),
            Seams { rules_epoch: epoch, movement: true, ..Seams::default() },
            &mut rng, &mut tray,
        ).unwrap()
    };
    let (old, old_log) = run(65);
    assert!(vr_gap(&old) > 1.0, "without the grant, 12\" cannot close 14\"");
    assert!(old_log.log.iter().all(|line| !line.contains("Rapid Charge Mark: +4\"")));
    let (new, new_log) = run(66);
    assert!(vr_gap(&new) < 0.3, "the mark's +4\" opens the 14\" charge, gap {}", vr_gap(&new));
    assert!(new_log.log.iter().any(|line| line.contains("Rapid Charge Mark: +4\" charge reach against Target")));
}


/// #845 CORE HALF — the table (#870/#1204) records the vs-target Mark on the
/// MARKED ENEMY; the core's `tray_vs_marks` still wrote it onto the BEARER
/// with a hard-coded `scope: ""`, while `rapid_charge_mark_bonus_in` reads the
/// TARGET for a `scope: "melee"` GrantVs "Rapid Charge" record — so the Mark
/// was dead in fresh sims. This drives the REAL aof/dark_elves entry through a
/// real marking volley and a real charge: the marked 14" charge closes, the
/// unmarked control cannot.
fn mark_setup(e: u32) -> (State, Vec<UnitStatic>) {
    let (st0, mut statics) = buff_line();
    // The enemy (roster key "b", index 2) sits a mark-less charge away: a
    // base-edge gap of ~14" against the default 12" rush.
    let mut st = st0.clone();
    st.positions[2] = vec![
        [16.0 * IN2M, 0.0, 0.0],
        [16.02 * IN2M, 0.0, 0.0],
        [16.04 * IN2M, 0.0, 0.0],
    ];
    // The unit carries the REAL registry entry; `build_for` also stamps the
    // charger's own book value (the Mark's four inches).
    let mut registry = crate::rules::Registries::new(&repo_root());
    let marker_profile: Profile = serde_json::from_str(
        r#"{"unit_id":"a","name":"a","game_system":"aof","faction_folder":"dark_elves","special_rules":["Rapid Charge Mark"]}"#,
    ).unwrap();
    let marker = UnitStatic::build_for(&mut registry, &marker_profile, e);
    assert_eq!(marker.utility_buffs.len(), 1, "the Mark resolves off the registry");
    assert!(marker.utility_buffs[0].vs_target, "the attack-seam kind");
    assert_eq!(marker.utility_buffs[0].grants_rule, "Rapid Charge");
    assert_eq!(marker.rapid_charge_grant_in, 4.0, "the book's four inches");
    statics[0].utility_buffs = marker.utility_buffs;
    statics[0].rapid_charge_grant_in = marker.rapid_charge_grant_in;
    statics[0].shoot = vec![gun("Rifle", 4, 24)];
    statics[0].melee = vec![gun("CCW", 8, 0)];
    (st, statics)
}

#[test]
fn a_fresh_sim_marks_the_enemy_and_opens_a_friendly_charge_at_epoch_71() {
    use crate::acts::EPOCH_71_RAPID_CHARGE_MARK;
    let e = EPOCH_71_RAPID_CHARGE_MARK;
    let (st, statics) = mark_setup(e);

    let charge = Action {
        kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
        charge: Some("b".into()), patient: false, split: None, traced: None, teleport: None,
    };

    // Control: without the Mark the same 14" charge cannot close.
    let mut plain = statics.clone();
    plain[0].utility_buffs = vec![];
    plain[0].rapid_charge_grant_in = 0.0;
    let (plain_after, _) = mark_run(&st, &plain, &charge, e);
    assert!(mark_gap(&plain_after) > 1.0,
        "without the Mark, 12\" cannot close 14\" (gap {})", mark_gap(&plain_after));

    // The marking volley: the bearer shoots the enemy; the attack seam records
    // the Mark on the TARGET, never on the bearer's own net.
    let shoot = buff_action(Some("b"));
    let (marked_state, _) = mark_run(&st, &statics, &shoot, e);
    assert!(
        marked_state.buffs[2].iter().any(|r| r.scope.as_ref() == "melee"
            && r.attackers && r.grants_rule.as_ref() == "Rapid Charge"),
        "the Mark must live on the marked enemy: {:?}", marked_state.buffs[2]
    );
    assert!(
        marked_state.buffs[0].iter().all(|r| r.grants_rule.as_ref() != "Rapid Charge"),
        "and never on the bearer's own net"
    );

    // The friendly charge now reads the target's grant, closes the gap, logs.
    let (after, report) = mark_run(&marked_state, &statics, &charge, e);
    assert!(mark_gap(&after) < 0.3,
        "the Mark's +4\" opens the 14\" charge (gap {})", mark_gap(&after));
    assert!(
        report.log.iter().any(|l| l.contains("Rapid Charge Mark: +4\" charge reach against b")),
        "rules-must-log: {:?}", report.log
    );
}

fn mark_run(
    st: &State, statics: &[UnitStatic], action: &Action, epoch: u32,
) -> (State, ShootResult) {
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        statics, st, action, &small_board(),
        Seams { rules_epoch: epoch, movement: true, ..Seams::default() },
        &mut rng, &mut tray,
    ).unwrap()
}

fn mark_gap(next: &State) -> f64 {
    crate::geom::edge_gap_in(
        &next.positions[0], &next.radii[0], &next.positions[2], &next.radii[2],
        crate::sim::DEFAULT_BASE_RADIUS_M,
    )
}

/// Byte-exact replay of 66-70 corpora: below `EPOCH_71_RAPID_CHARGE_MARK` the
/// legacy once-grant stays on the BEARER (spent within the volley) and the marked
/// enemy carries no record.
#[test]
fn the_rapid_charge_mark_leaves_the_marked_enemy_clean_at_epoch_70() {
    use crate::acts::EPOCH_70_TRAY_EXACT;
    let e = EPOCH_70_TRAY_EXACT;
    let (st, statics) = mark_setup(e);
    let (state, _) = mark_run(&st, &statics, &buff_action(Some("b")), e);
    assert!(
        state.buffs[2].iter().all(|r| r.grants_rule.as_ref() != "Rapid Charge"),
        "legacy path: no Rapid Charge record on the marked enemy: {:?}", state.buffs[2]
    );
}

/// The Piercing Fighting Mark's melee scope (aof/goblins' own entry, `vs_target`, scope `melee`, grants "AP(+1) in melee"): the table records it on the MARKED unit with
/// that scope, where a volley never spends it, so it waits for the next charger. `EPOCH_94_PARITY_BATCH` puts the core's record there too, keeps it through the
/// volley and reports it in the delta's `marks_left`; below the gate the Mark stays on the bearer with the scope dropped and the volley spends it.
fn piercing_fighting_setup(e: u32) -> (State, Vec<UnitStatic>) {
    let (st, mut statics) = mark_setup(e);
    let mut registry = crate::rules::Registries::new(&repo_root());
    let profile: Profile = serde_json::from_str(
        r#"{"unit_id":"a","name":"a","game_system":"aof","faction_folder":"goblins","special_rules":["Piercing Fighting Mark"]}"#,
    ).unwrap();
    let marker = UnitStatic::build_for(&mut registry, &profile, e);
    assert_eq!((marker.utility_buffs.len(), marker.utility_buffs[0].scope.as_str()), (1, "melee"), "the entry is the melee-scoped vs-target Mark");
    statics[0].utility_buffs = marker.utility_buffs;
    statics[0].rapid_charge_grant_in = 0.0;
    (st, statics)
}

#[test]
fn from_the_gate_a_volley_leaves_the_piercing_fighting_mark_on_the_marked_unit() {
    use crate::acts::EPOCH_94_PARITY_BATCH as GATE;
    let (st, statics) = piercing_fighting_setup(GATE);
    let (after, _) = mark_run(&st, &statics, &buff_action(Some("b")), GATE);
    assert!(after.buffs[2].iter().any(|r| r.attackers && r.once && &*r.scope == "melee" && &*r.grants_rule == "AP(+1) in melee"),
        "the Mark waits on the marked unit: {:?}", after.buffs[2]);
    assert!(after.buffs[0].is_empty(), "and never on the bearer: {:?}", after.buffs[0]);
    let row = crate::activation::delta_of(&st, &after).into_iter().find(|d| d.key == "b").expect("the marked unit's row");
    assert_eq!(row.marks_left, vec![("Piercing Fighting Mark".to_string(), "melee".to_string(), "AP(+1) in melee".to_string())]);
    assert!(crate::activation::delta_of(&st, &after).iter().all(|d| d.key == "b" || d.marks_left.is_empty()), "only the marked unit carries it");
}

#[test]
fn below_the_gate_the_piercing_fighting_mark_is_spent_by_the_volley() {
    use crate::acts::EPOCH_94_PARITY_BATCH as GATE;
    let (st, statics) = piercing_fighting_setup(GATE - 1);
    let (after, _) = mark_run(&st, &statics, &buff_action(Some("b")), GATE - 1);
    assert!(after.buffs[2].is_empty() && after.buffs[0].is_empty(), "spent, nothing left: {:?} / {:?}", after.buffs[0], after.buffs[2]);
    assert!(crate::activation::delta_of(&st, &after).iter().all(|d| d.marks_left.is_empty()));
}

/// The Rapid Charge Mark (kept on the target since epoch 71) is reported too: the table holds the same record after a volley.
#[test]
fn the_rapid_charge_mark_a_volley_leaves_is_reported_in_marks_left() {
    use crate::acts::EPOCH_71_RAPID_CHARGE_MARK as E;
    let (st, statics) = mark_setup(E);
    let (after, _) = mark_run(&st, &statics, &buff_action(Some("b")), E);
    let row = crate::activation::delta_of(&st, &after).into_iter().find(|d| d.key == "b").expect("the marked unit's row");
    assert_eq!(row.marks_left, vec![("Rapid Charge Mark".to_string(), "melee".to_string(), "Rapid Charge".to_string())]);
}

/// A charger's strikes read the record off the marked unit from the gate on (`ctx_live_vs`, melee only): AP(+1) in melee; a volley and a lower epoch read nothing.
#[test]
fn a_charger_reads_the_waiting_piercing_fighting_mark_from_the_gate() {
    use crate::acts::EPOCH_94_PARITY_BATCH as GATE;
    let (st, statics) = piercing_fighting_setup(GATE);
    let (marked, _) = mark_run(&st, &statics, &buff_action(Some("b")), GATE);
    let read = |epoch: u32, melee: bool| {
        crate::sim::ctx_live_vs(ctx_of(&statics[0], &marked, 0), &statics, &marked, 0, 2, melee, epoch).pierce_melee_grant
    };
    assert!(read(GATE, true), "the charger's strikes carry AP(+1)");
    assert!(!read(GATE, false), "a volley never reads a melee-scoped record");
    assert!(!read(GATE - 1, true), "below the gate nothing reads it");
}
