//! SHO-19 live-path tests (rules 3.6, lane shoot): a Versatile Expert unit shooting from
//! inside 9" still latches its pick when the live context is built for the volley — the
//! static no-gate flag survives `ctx_live`, and a live grant only adds to it.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::state::Weapon;

/// A one-model Expert "a" (Quality 4, one 24" rifle) and a plain Defense 5 target "b"
/// whose nearest base edge is `gap_in` inches away. The Expert's static is built the way
/// the game builds it: `build_for` over the shipped gf rule map.
fn expert_line(rules_epoch: u32, gap_in: f64) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let mut expert = st.profiles.list[0].clone();
    expert.name = "Expert".into();
    expert.game_system = "gf".into();
    expert.faction_folder = "watch_brothers".into();
    expert.special_rules = vec!["Versatile Expert".into()];
    expert.wounds_max = vec![1];
    expert.weapons = vec![Weapon { name: "Rifle".into(), range: 24.0, attacks: 20, count: 1, ap: 0, rules: vec![] }];
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into()],
        index: ["a", "b"].iter().enumerate().map(|(i, k)| (k.to_string(), i)).collect(),
        profile: vec![0, 0],
    });
    st.profiles = Rc::new(Profiles { list: vec![expert.clone()], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[(gap_in + 2.0) * IN2M, 0.0, 0.0]]];
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
    (st, vec![UnitStatic::build_for(&mut reg, &expert, rules_epoch), foe])
}

/// The Expert holds and shoots its target: the volley's own log and rolls.
fn expert_volley(rules_epoch: u32, gap_in: f64) -> crate::dice::ShootResult {
    let (st, statics) = expert_line(rules_epoch, gap_in);
    assert!(statics[0].ctx.versatile_no_gate == (rules_epoch >= EPOCH_73_V36), "setup: the static flag");
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
    resolve_stochastic_tray_on_board(
        &statics, &st, &act, &small_board(),
        Seams { movement: true, rules_epoch, ..Seams::default() },
        &mut rng, &mut tray,
    )
    .unwrap()
    .1
}

/// RED on main: `ctx_live` overwrote the static Expert flag with the (absent) live grant,
/// so the 4" volley latched no pick and rolled its plain 4+.
#[test]
fn a_versatile_expert_at_four_inches_latches_its_pick_at_epoch_73() {
    let r = expert_volley(EPOCH_73_V36, 4.0);
    assert!(
        r.log.iter().any(|l| l.starts_with("Versatile Expert:") && l.contains("picks +1 to hit")),
        "rules-must-log: the book rule names the pick; log: {:?}",
        r.log
    );
    let targets: Vec<i64> = r.rolls.iter().filter(|x| x.kind == "attack" && x.count == 20).map(|x| x.target).collect();
    assert_eq!(targets, vec![3], "the +1 to hit reaches the volley's dice (Quality 4 -> 3+)");
}

/// The pin: below 73 the Expert has no no-gate pick, so 4" latches nothing.
#[test]
fn below_epoch_73_a_four_inch_volley_latches_no_pick() {
    let r = expert_volley(EPOCH_72_PLAYTEST_RULES, 4.0);
    assert!(r.log.iter().all(|l| !l.contains("picks")), "72 keeps the 9\" gate; log: {:?}", r.log);
    let targets: Vec<i64> = r.rolls.iter().filter(|x| x.kind == "attack" && x.count == 20).map(|x| x.target).collect();
    assert_eq!(targets, vec![4]);
}
