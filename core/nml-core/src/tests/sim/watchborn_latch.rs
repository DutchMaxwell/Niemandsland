use super::*;

// ---------------------- EPOCH_38_WATCHBORN_LATCH: one pick per ACTIVATION ---

/// Watchborn-shaped fixture: a single-model shooter "a" (Quality 4) with TWO
/// versatile rifles over 9" from two single-model targets — "b" (plain
/// Defense 5, whose EV-best is decisively +1 to hit) and "c" (Shielded
/// Defense 4, whose own EV-best is AP(+1)). One act per unit per round makes
/// the round stamp the activation latch, so the two split volleys are two
/// volleys of ONE activation.
fn watchborn_volley_line() -> (State, Vec<UnitStatic>) {
    let rifle = |name: &str| ShootProfile {
        name: name.into(),
        attacks: 8,
        count: 1,
        range: 24,
        versatile_attack: true,
        ..Default::default()
    };
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into(), "c".into()],
        index: ["a".to_string(), "b".to_string(), "c".to_string()]
            .iter()
            .enumerate()
            .map(|(i, k)| (k.clone(), i))
            .collect(),
        profile: vec![0, 1, 2],
    });
    st.profiles = Rc::new(Profiles {
        list: vec![profile.clone(), profile.clone(), profile],
        index: HashMap::new(),
    });
    st.player = vec![0, 1, 1];
    st.alive = vec![1, 1, 1];
    st.attached = Rc::new(vec![vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None]);
    st.positions = vec![
        vec![[0.0, 0.0, 0.0]],
        vec![[14.0 * IN2M, 0.0, 0.0]],
        vec![[14.0 * IN2M, 12.0 * IN2M, 0.0]],
    ];
    st.wounds = vec![vec![1], vec![1], vec![1]];
    st.radii = vec![vec![IN2M], vec![IN2M], vec![IN2M]];
    (st, vec![
        UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            name: "Watchborn".into(),
            shoot: vec![rifle("Rifle A"), rifle("Rifle B")],
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        },
        UnitStatic {
            ctx: Ctx { defense: 5, tough: 1, models: 1, ..Default::default() },
            name: "Plain".into(),
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        },
        UnitStatic {
            ctx: Ctx { defense: 4, tough: 1, models: 1, shielded: true, ..Default::default() },
            name: "Shielded".into(),
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        },
    ])
}

/// One activation, two volleys: split fire aims Rifle A at "b" and Rifle B
/// at "c" (the split list's order makes b the FIRST eligible attack).
fn watchborn_split_action() -> Action {
    Action {
        kind: HOLD,
        unit: "a".into(),
        dest: None,
        shoot: Some("b".into()),
        charge: None,
        patient: false,
        split: Some(vec![
            crate::io::SplitShot {
                member: "Watchborn".into(),
                weapon: "Rifle A".into(),
                target: "b".into(),
            },
            crate::io::SplitShot {
                member: "Watchborn".into(),
                weapon: "Rifle B".into(),
                target: "c".into(),
            },
        ]),
        traced: None,
        teleport: None,
    }
}

fn watchborn_run(
    st: &State,
    statics: &[UnitStatic],
    action: &Action,
    rules_epoch: u32,
) -> crate::dice::ShootResult {
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        statics, st, action, &small_board(),
        Seams { movement: true, rules_epoch, ..Seams::default() },
        &mut rng, &mut tray,
    )
    .unwrap()
    .1
}

/// The book (the `Versatile Attack`/`Versatile Reach` pair): "When this unit
/// is activated, pick one effect ... until the end of the activation" — ONE
/// pick per activation, so the second volley of the same activation rides the
/// first pick even where its own EV-best differs. At 38 the recorded roll
/// targets prove it: both volleys roll the first pick's +1-to-hit target (3+)
/// and the activation names the pick exactly once. RED against the per-volley
/// re-decision: the shielded second volley re-decides to AP(+1) and rolls 4+.
#[test]
fn two_volleys_of_one_activation_keep_one_pick_at_38() {
    let (st, statics) = watchborn_volley_line();
    let act = watchborn_split_action();

    let new_leg = watchborn_run(&st, &statics, &act, crate::acts::EPOCH_38_WATCHBORN_LATCH);
    let picks: Vec<&String> = new_leg.log.iter().filter(|l| l.contains("picks")).collect();
    assert_eq!(
        picks.len(),
        1,
        "rules-must-log: ONE pick line per activation, got {picks:?}; full log: {:?}; \
         all rolls: {:?}",
        new_leg.log,
        new_leg.rolls.iter().map(|r| (r.kind, r.count, r.target)).collect::<Vec<_>>(),
    );
    let volley_targets: Vec<i64> = new_leg
        .rolls
        .iter()
        .filter(|r| r.kind == "attack" && r.count == 8)
        .map(|r| r.target)
        .collect();
    assert_eq!(
        volley_targets,
        vec![3, 3],
        "one pick: the first eligible attack (vs plain Defense 4) decides +1 to hit \
         and the shielded second volley REUSES it — no per-volley re-decision"
    );

    let old_leg = watchborn_run(&st, &statics, &act, crate::acts::EPOCH_37_UNSTOPPABLE_AURA);
    let old_targets: Vec<i64> = old_leg
        .rolls
        .iter()
        .filter(|r| r.kind == "attack" && r.count == 8)
        .map(|r| r.target)
        .collect();
    assert_eq!(
        old_targets,
        vec![3, 4],
        "old leg byte-exact: every volley re-decides — the shielded target's own \
         EV-best is AP(+1), so its roll target stays 4+ and no pick line is logged"
    );
    assert!(
        old_leg.log.iter().all(|l| !l.contains("picks")),
        "old leg: the once-per-activation pick line does not exist below the gate"
    );
}

/// The core's melee half: a Watchborn CHARGE from over 9" carries the picked
/// bonus into the melee dice fold — the same latch the volley fold reads
/// (mirrored from dice.rs's volley pick), the bonus its own planner
/// (`combat::profile_ev`'s `!melee || charging` leg) already counted on. RED
/// against the current fold: the melee dice have no versatile leg, so the
/// charge rolls its plain 4+ while the planner charged on 3+.
#[test]
fn a_charge_over_nine_inches_carries_the_pick_into_the_melee_fold() {
    let blade = ShootProfile {
        name: "Blade".into(),
        attacks: 8,
        count: 1,
        range: 0,
        versatile_attack: true,
        ..Default::default()
    };
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into()],
        index: ["a".to_string(), "b".to_string()]
            .iter()
            .enumerate()
            .map(|(i, k)| (k.clone(), i))
            .collect(),
        profile: vec![0, 1],
    });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[14.0 * IN2M, 0.0, 0.0]]];
    st.wounds = vec![vec![1], vec![1]];
    st.radii = vec![vec![IN2M], vec![IN2M]];
    let statics = vec![
        UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            name: "Watchborn".into(),
            melee: vec![blade],
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        },
        UnitStatic {
            ctx: Ctx { defense: 5, tough: 1, models: 1, ..Default::default() },
            name: "Target".into(),
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        },
    ];
    let act = Action {
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

    let new_leg = watchborn_run(&st, &statics, &act, crate::acts::EPOCH_38_WATCHBORN_LATCH);
    let strike_targets: Vec<i64> = new_leg
        .rolls
        .iter()
        .filter(|r| r.kind == "attack" && r.count == 8)
        .map(|r| r.target)
        .collect();
    assert_eq!(
        strike_targets,
        vec![3],
        "the charge is the activation's first eligible attack: its EV-best vs plain \
         Defense 5 is +1 to hit, and the picked bonus reaches the MELEE dice fold (3+); \
         full report log: {:?}; all rolls: {:?}",
        new_leg.log,
        new_leg.rolls.iter().map(|r| (r.kind, r.count, r.target)).collect::<Vec<_>>(),
    );

    let old_leg = watchborn_run(&st, &statics, &act, crate::acts::EPOCH_37_UNSTOPPABLE_AURA);
    let old_targets: Vec<i64> = old_leg
        .rolls
        .iter()
        .filter(|r| r.kind == "attack" && r.count == 8)
        .map(|r| r.target)
        .collect();
    assert_eq!(
        old_targets,
        vec![4],
        "old leg byte-exact: no versatile leg in the melee fold — the charge rolls \
         its plain 4+ with no pick line"
    );
    assert!(old_leg.log.iter().all(|l| !l.contains("picks")));
}
