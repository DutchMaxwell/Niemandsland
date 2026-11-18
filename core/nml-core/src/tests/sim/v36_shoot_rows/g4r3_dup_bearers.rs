use super::super::*;
use crate::acts::{EPOCH_88_SPLIT_LONE_HERO, EPOCH_89_SHARED_BEARERS};
use crate::state::Kit;

// T-DUP-WEAPON-BEARERS — a unit that lists one weapon twice (the Jesters' "Atom Pistol" x8 plain + x2 AP(1))
// fires ONE die per sighted living bearer in total, not per entry. `living_bearers` keys the kits by weapon
// NAME, so both entries read all ten bearers: at 8 sighted the core rolled 8+8=16 dice where the table rolls 8
// (main.gd:5262-5274 splits the bearers, key at main.gd:5091-5094). From EPOCH_89_SHARED_BEARERS the entries
// share the sighted bearers in order, each capped by its own copies; EPOCH_88 keeps the by-name count (replay).

fn pistol(attacks: i64, count: i64, ap: i64) -> ShootProfile {
    ShootProfile { name: "Atom Pistol".into(), attacks, count, range: 12, ap, ..Default::default() }
}

/// Ten Jesters, each with one Atom Pistol in the per-model kit; the unit lists the weapon twice (x8 plain,
/// x2 AP(1)). `near` of the ten stand 5" from the target, the rest 30" behind: only `near` models are sighted.
fn jesters(near: usize) -> (State, Vec<UnitStatic>) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let lone = |name: &str, models: i64| UnitStatic {
        ctx: Ctx { quality: 2, defense: 6, tough: 1, models, ..Default::default() },
        name: name.into(), model_count: models, wounds_max: vec![1; models as usize], ..Default::default()
    };
    let statics = vec![
        UnitStatic { shoot: vec![pistol(8, 8, 0), pistol(2, 2, 1)], ..lone("Jesters", 10) },
        lone("Scouts", 3),
    ];
    let mut st = four_unit_line();
    let keys: Vec<String> = ["a", "b"].iter().map(|k| k.to_string()).collect();
    let index = keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    st.roster = Rc::new(Roster { keys, index, profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![1, 2];
    st.alive = vec![10, 3];
    st.positions[0] = (0..10).map(|i| [(if i < near { 0.0 } else { -30.0 }) * IN2M, 0.0, i as f64 * 0.02 * IN2M]).collect();
    st.positions[1] = (0..3).map(|i| [5.0 * IN2M, 0.0, i as f64 * 0.02 * IN2M]).collect();
    st.wounds[0] = vec![1; 10];
    st.wounds[1] = vec![1; 3];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 10];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M; 3];
    st.kits = vec![
        Rc::new((0..10).map(|_| Kit { weapons: vec![0], equipment: 0, wounds_max: 1 }).collect()),
        Rc::new(Vec::new()),
    ];
    st.kit_names = vec![Rc::new(vec!["Atom Pistol".into()]), Rc::new(Vec::new())];
    (st, statics)
}

/// The tray's per-entry die counts (`sighting` on), with the silent reason each entry carries.
fn tray(st: &State, statics: &[UnitStatic], epoch: u32) -> (Vec<i64>, Vec<&'static str>) {
    let mut sc = Scratch { rules_epoch: epoch, bearers_last: true, say_sight: true, ..Default::default() };
    sighted_profiles_of(&statics[0], st, statics, 0, 1, &[], 5.0, false, &mut sc);
    (sc.attacks, sc.silent)
}

/// Every attack die the Jesters roll through the whole tray resolve (one sighting leg).
fn volley_dice(st: &State, statics: &[UnitStatic], epoch: u32, sighting: bool) -> i64 {
    let mut hold = advance_to(0.0);
    hold.kind = HOLD;
    hold.dest = None;
    hold.shoot = Some("b".into());
    let seams = Seams { rules_epoch: epoch, casualties_bearers_last: true, sighting, ..Seams::default() };
    let terrain = crate::terrain::Terrain::default();
    let (_, shot) = resolve_stochastic_tray_on_board(
        statics, st, &hold, &terrain, seams, &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(1),
    ).unwrap();
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Jesters").map(|r| r.count).sum()
}

#[test]
fn entries_share_the_sighted_bearers_at_epoch_89() {
    let (st, statics) = jesters(8);
    assert_eq!(tray(&st, &statics, EPOCH_89_SHARED_BEARERS).0, vec![8, 0], "8 sighted pistols fire once: 8 + 0");
    assert_eq!(tray(&st, &statics, EPOCH_89_SHARED_BEARERS).1[1], "its bearers already fire another entry of it");
    assert_eq!(volley_dice(&st, &statics, EPOCH_89_SHARED_BEARERS, true), 8, "the sighted leg: 8 dice, not 16");
    // The seeded leg scales by the living count (10), not per-model sight: it still shares the bearers, 10 not 20.
    assert_eq!(volley_dice(&st, &statics, EPOCH_89_SHARED_BEARERS, false), 10, "the seeded leg: 10 dice, not 20");
}

#[test]
fn every_pistol_fires_once_when_all_ten_are_sighted_at_epoch_89() {
    let (st, statics) = jesters(10);
    assert_eq!(tray(&st, &statics, EPOCH_89_SHARED_BEARERS).0, vec![8, 2], "each entry fires its own copies: 8 + 2");
    for sighting in [false, true] {
        assert_eq!(volley_dice(&st, &statics, EPOCH_89_SHARED_BEARERS, sighting), 10, "sighting={sighting}: 10 dice, not 20");
    }
}

#[test]
fn both_entries_read_every_bearer_at_epoch_88() {
    let (st, statics) = jesters(8);
    assert_eq!(tray(&st, &statics, EPOCH_88_SPLIT_LONE_HERO).0, vec![8, 8], "the by-name count stays: 8 + 8");
    assert_eq!(volley_dice(&st, &statics, EPOCH_88_SPLIT_LONE_HERO, true), 16, "the sighted leg replays 16 dice");
    assert_eq!(volley_dice(&st, &statics, EPOCH_88_SPLIT_LONE_HERO, false), 20, "the seeded leg replays 20 dice");
    let (st, statics) = jesters(10);
    assert_eq!(tray(&st, &statics, EPOCH_88_SPLIT_LONE_HERO).0, vec![10, 10], "the by-name count stays: 10 + 10");
    for sighting in [false, true] {
        assert_eq!(volley_dice(&st, &statics, EPOCH_88_SPLIT_LONE_HERO, sighting), 20, "sighting={sighting}: the old 20 dice");
    }
}
