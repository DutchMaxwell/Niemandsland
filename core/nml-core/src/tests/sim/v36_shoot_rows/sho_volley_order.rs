//! Volley-order tests (rules 3.6, lane shoot): the Versatile pick latches on the FIRST FIRED
//! weapon, in the table's resolve-first order (Takedown, Deadly, the rest), not on the first
//! profile of the unit's header.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::state::Weapon;

/// A one-model Versatile Expert "a" (Quality 3) whose header lists a Reliable Flamer BEFORE a
/// Deadly Fusion Rifle (the gf_1000_net_011 shape), and a plain Defense 5 target "b" 9.5" from
/// base edge to base edge (11.5" between the centres, inside the guns' 12" pooled reach and over
/// the 9" shooting gate, so the pick is eligible at every epoch). The Expert's static is built
/// the way the game builds it: `build_for` over the shipped gf rule map.
fn flamer_then_fusion(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let base = st.profiles.list[0].clone();
    let mut unit = base.clone();
    unit.name = "Expert".into();
    unit.game_system = "gf".into();
    unit.faction_folder = "watch_brothers".into();
    unit.special_rules = vec!["Versatile Expert".into()];
    unit.quality = 3;
    unit.wounds_max = vec![1];
    unit.weapons = vec![
        Weapon { name: "Flamer".into(), range: 12.0, attacks: 1, count: 1, ap: 0, rules: vec!["Blast(3)".into(), "Reliable".into()] },
        Weapon { name: "Fusion Rifle".into(), range: 12.0, attacks: 1, count: 1, ap: 4, rules: vec!["AP(4)".into(), "Deadly(3)".into()] },
    ];
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into()],
        index: ["a", "b"].iter().enumerate().map(|(i, k)| (k.to_string(), i)).collect(),
        profile: vec![0, 1],
    });
    st.profiles = Rc::new(Profiles { list: vec![unit.clone(), base], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[11.5 * IN2M, 0.0, 0.0]]];
    st.wounds = vec![vec![1], vec![1]];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M]]);
    let mut reg = crate::rules::Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
    let foe = UnitStatic {
        ctx: Ctx { defense: 5, tough: 1, models: 1, ..Default::default() },
        name: "Plain".into(),
        model_count: 1,
        wounds_max: vec![1],
        ..Default::default()
    };
    (st, vec![UnitStatic::build_for(&mut reg, &unit, rules_epoch), foe])
}

/// The Expert holds and shoots "b": the volley's log and attack-roll targets, in draw order.
fn volley(rules_epoch: u32) -> (Vec<String>, Vec<i64>) {
    let (st, statics) = flamer_then_fusion(rules_epoch);
    assert_eq!(statics[0].shoot.len(), 2, "setup: both weapons built, in header order");
    assert_eq!(statics[0].shoot[0].name, "Flamer");
    let act = Action {
        kind: HOLD,
        unit: "a".into(),
        dest: None,
        shoot: Some("b".into()),
        charge: None,
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    };
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    let r = resolve_stochastic_tray_on_board(
        &statics, &st, &act, &small_board(),
        Seams { movement: true, rules_epoch, ..Seams::default() },
        &mut rng, &mut tray,
    )
    .unwrap()
    .1;
    let mut log = r.log.clone();
    log.extend(r.rolls.iter().map(|x| format!("ROLL {} x{} at {}+ ({})", x.kind, x.count, x.target, x.owner)));
    let targets = r.rolls.iter().filter(|x| x.kind == "attack").map(|x| x.target).collect();
    (log, targets)
}

/// RED on main (gf_1000_net_011 acts 1 / 12): the table fires the Deadly Fusion Rifle first, so
/// the activation's pick is read off IT: against Defense 5 its best is +1 to hit (2+). The core
/// latched on the header-first Flamer, whose Reliable 2+ gains nothing from +1 to hit, and so
/// picked AP(+1), leaving the Fusion Rifle at its plain 3+.
#[test]
fn the_pick_latches_on_the_deadly_weapon_that_fires_first_at_epoch_73() {
    let (log, targets) = volley(EPOCH_73_V36);
    assert!(
        log.iter().any(|l| l.contains("picks +1 to hit for this activation")),
        "the pick is read off the first fired weapon; log: {log:?}"
    );
    assert_eq!(targets, vec![2, 2], "Fusion Rifle 3+ -> 2+ with the pick, then the Reliable Flamer at 2+; log: {log:?}");
}

/// The pin: below 73 the latch keeps reading the header-first profile (AP(+1), Fusion Rifle 3+).
#[test]
fn below_epoch_73_the_latch_keeps_the_header_order() {
    let (log, targets) = volley(EPOCH_72_PLAYTEST_RULES);
    assert!(log.iter().any(|l| l.contains("picks AP(+1) for this activation")), "log: {log:?}");
    assert_eq!(targets, vec![3, 2]);
}
