//! T-JOINED-HERO-FATIGUE (`EPOCH_91_JOINED_HERO_FATIGUE`, maintainer ruling 19.11.): a hero joined to a unit is part of
//! the unit, so a melee that tires the host tires the hero with it - at the charge and at the strike-back, on the tray
//! and in the expected-value estimate. The table's `_solo_set_fatigued` loops the attached heroes; the core set the host
//! index only and the hero kept striking at full Quality. Below 91 the host-only write stays, byte for byte.
use super::*;
use crate::acts::{EPOCH_90_JOINED_ONE_RECOVERY, EPOCH_91_JOINED_HERO_FATIGUE};

/// Indices of the `four_unit_line` board: 0 = charger host, 1 = its joined hero, 2 = defender host, 3 = its joined hero.
const CHARGER: usize = 0;
const DEFENDER: usize = 2;

fn blade(name: &str, attacks: i64) -> ShootProfile {
    ShootProfile { name: name.into(), attacks, count: 1, range: 0, ..Default::default() }
}

/// Four tough units (30 wounds a model, so nobody dies and every flag is the fight's own doing): each host fields three
/// models and one joined hero with one model; every model stands on the same spot, inside striking reach.
fn fixture() -> (Vec<UnitStatic>, State) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    let unit = |name: &str, models: i64, weapon: ShootProfile| UnitStatic {
        ctx: Ctx { quality: 3, defense: 4, tough: 30, models, ..Default::default() },
        name: name.into(),
        melee: vec![weapon],
        model_count: models,
        wounds_max: vec![30; models as usize],
        ..Default::default()
    };
    let statics = vec![
        unit("Charger", 3, blade("Blade", 2)),
        unit("Charger Hero", 1, blade("Greatsword", 3)),
        unit("Defender", 3, blade("Club", 2)),
        unit("Defender Hero", 1, blade("Mace", 3)),
    ];
    let mut st = four_unit_line();
    let keys: Vec<String> = vec!["a".into(), "ah".into(), "b".into(), "bh".into()];
    let index = keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    st.roster = Rc::new(Roster { keys, index, profile: vec![0, 1, 2, 3] });
    st.profiles = Rc::new(Profiles { list: vec![profile; 4], index: HashMap::new() });
    st.alive = vec![3, 1, 3, 1];
    st.wounds = vec![vec![30; 3], vec![30], vec![30; 3], vec![30]];
    st.radii = Rc::new(vec![vec![IN2M; 3], vec![IN2M], vec![IN2M; 3], vec![IN2M]]);
    st.positions = vec![
        vec![[IN2M, 0.0, 0.0]; 3],
        vec![[IN2M, 0.0, 0.0]],
        vec![[0.0, 0.0, 0.0]; 3],
        vec![[0.0, 0.0, 0.0]],
    ];
    (statics, st)
}

fn seams(rules_epoch: u32, hero_attach: bool) -> Seams {
    Seams { rules_epoch, hero_attach, ..Default::default() }
}

/// One charge of host `a` at host `b` on the tray; returns the board after it and the result.
fn tray(rules_epoch: u32, hero_attach: bool) -> (State, ShootResult) {
    let (statics, mut st) = fixture();
    let mut shot = ShootResult::default();
    let mut tray = Tray::seeded(27);
    tray_charge(&statics, &mut st, CHARGER, DEFENDER, seams(rules_epoch, hero_attach), &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    (st, shot)
}

#[test]
fn a_charge_tires_the_joined_heroes_of_both_sides_from_epoch_91() {
    let (st, shot) = tray(EPOCH_91_JOINED_HERO_FATIGUE, true);
    assert_eq!(st.fatigued, vec![true, true, true, true], "host and hero are one unit, so both are tired: {:?}", shot.log);
}

/// The gate: below 91 the very same fight tires the two hosts only, which is what recorded games replay.
#[test]
fn at_epoch_90_a_charge_tires_the_hosts_only() {
    let (st, shot) = tray(EPOCH_90_JOINED_ONE_RECOVERY, true);
    assert_eq!(st.fatigued, vec![true, false, true, false], "the pre-91 write is the host index alone: {:?}", shot.log);
}

/// The hero fold is its own seam: without it the core does not believe in the chain, at any epoch.
#[test]
fn without_the_hero_fold_a_charge_tires_the_hosts_only() {
    let (st, _) = tray(EPOCH_91_JOINED_HERO_FATIGUE, false);
    assert_eq!(st.fatigued, vec![true, false, true, false], "no `hero_attach`, no hero write");
}

/// The tray writes no line for the mirror (the table's own mirror is silent), so the log is identical either side of the gate.
#[test]
fn the_mirror_writes_no_battle_log_line() {
    let (_, before) = tray(EPOCH_90_JOINED_ONE_RECOVERY, true);
    let (_, after) = tray(EPOCH_91_JOINED_HERO_FATIGUE, true);
    assert_eq!(before.log, after.log, "the table says nothing when it tires an attached hero");
}

/// What the flag is for: a second melee on the same board. The tired defender hero strikes back on unmodified 6s from 91,
/// where the pre-91 hero (never tired) still struck at its own Quality 3+.
fn hero_strike_back_target(rules_epoch: u32) -> i64 {
    let (statics, mut st) = fixture();
    let sm = seams(rules_epoch, true);
    let (mut shot, mut tray) = (ShootResult::default(), Tray::seeded(27));
    tray_charge(&statics, &mut st, CHARGER, DEFENDER, sm, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    let mut second = ShootResult::default();
    tray_charge(&statics, &mut st, CHARGER, DEFENDER, sm, &mut tray, &mut second, 0.0, Cover::Recorded(None));
    second
        .rolls
        .iter()
        .find(|r| r.kind == "attack" && r.owner == "Defender Hero")
        .expect("the defender's hero strikes back in the second melee")
        .target
}

#[test]
fn a_tired_joined_hero_strikes_on_unmodified_sixes_from_epoch_91() {
    assert_eq!(hero_strike_back_target(EPOCH_91_JOINED_HERO_FATIGUE), 6, "the hero fights tired, like its unit");
}

#[test]
fn at_epoch_90_the_joined_hero_still_strikes_at_full_quality() {
    assert_eq!(hero_strike_back_target(EPOCH_90_JOINED_ONE_RECOVERY), 3, "the pre-91 hero was never marked tired");
}

/// The expected-value estimate the planner prices a charge with writes the same flags (it feeds the next estimate).
fn ev_charge(rules_epoch: u32) -> State {
    let (statics, st) = fixture();
    let action = Action {
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
    resolve_on_board(&statics, &st, &action, &Terrain::default(), seams(rules_epoch, true)).expect("the EV charge resolves")
}

#[test]
fn the_expected_value_charge_tires_the_joined_heroes_from_epoch_91() {
    assert_eq!(ev_charge(EPOCH_91_JOINED_HERO_FATIGUE).fatigued, vec![true, true, true, true]);
}

#[test]
fn at_epoch_90_the_expected_value_charge_tires_the_hosts_only() {
    assert_eq!(ev_charge(EPOCH_90_JOINED_ONE_RECOVERY).fatigued, vec![true, false, true, false]);
}
