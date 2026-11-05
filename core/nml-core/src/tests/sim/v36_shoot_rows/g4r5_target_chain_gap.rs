//! G4R5 R13 F-TARGET-CHAIN-GAP (rules 3.6, `EPOCH_73_V36`; replay rows gf_1000_net_022 act 8, gf_024 act 7,
//! gf_035 act 10): shooting range is measured to the nearest model of the target's WHOLE chain, the host and its
//! living joined heroes. The weapon keep gate measured the target HOST alone and dropped a weapon the table fires
//! (host 12.5" away, its hero 11.5" away, a 12" gun). Three entries read the gap: the split group, the pooled
//! volley, and a joined shooter hero's own gap. Below 73 the host-only gate replays.
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::io::SplitShot;
use crate::rules::Registries;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Real profiles the way the game builds them: a host with a 12" Rifle (3 dice), a host with no weapon, and a
/// hero with a 12" Carbine (2 dice).
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "gunners":{"unit_id":"gunners","name":"Gun Squad","quality":4,"defense":4,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"gf",
    "faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":12,"attacks":3,"count":1,"ap":0,"rules":[]}]},
  "drill":{"unit_id":"drill","name":"Drill Squad","quality":4,"defense":4,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"gf",
    "faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "leader":{"unit_id":"leader","name":"Squad Leader","quality":4,"defense":4,"tough":3,
    "wounds_max":[3],"model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"gf",
    "faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Carbine","range":12,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

/// Unit 0 = the shooter host, 1 = its joined hero (both at the origin), 2 = the target host, 3 = the target's
/// joined hero, all on 1" bases. The target host stands 12.5" away (edge to edge when `by_edge`, else centre
/// to centre), its hero `hero_gap_in` away and 2.5" to the side, so no base stands in a sight line.
fn line(by_edge: bool, armed_host: bool, hero_gap_in: f64) -> (State, Vec<UnitStatic>) {
    let header = crate::read_act_header(HEADER).expect("HEADER parses");
    let mut reg = Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), EPOCH_73_V36);
    let (mut st, mut statics) = hero_line();
    statics[0] = build(if armed_host { "gunners" } else { "drill" });
    statics[1] = build("leader");
    for (u, name) in [(2, "Target Host"), (3, "Target Hero")] {
        statics[u] = UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            name: name.into(),
            model_count: 1,
            wounds_max: vec![9],
            ..Default::default()
        };
    }
    let keys = st.roster.keys.clone();
    let index = keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    st.roster = Rc::new(Roster { keys, index, profile: vec![0, 1, 2, 3] });
    let base = st.profiles.list[0].clone();
    st.profiles = Rc::new(Profiles { list: vec![base; 4], index: HashMap::new() });
    st.alive = vec![1, 1, 1, 1];
    st.wounds = vec![vec![1], vec![3], vec![9], vec![9]];
    st.attached = Rc::new(vec![vec![1], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, Some(0), None, Some(2)]);
    let off = if by_edge { 2.0 } else { 0.0 };
    let hero_x = ((hero_gap_in + off).powi(2) - 2.5_f64.powi(2)).sqrt();
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.positions[1] = vec![[0.0, 0.0, 0.0]];
    st.positions[2] = vec![[(12.5 + off) * IN2M, 0.0, 0.0]];
    st.positions[3] = vec![[hero_x * IN2M, 0.0, 2.5 * IN2M]];
    for u in 0..4 {
        Rc::make_mut(&mut st.radii)[u] = vec![IN2M];
    }
    (st, statics)
}

/// The attack dice `owner` rolled in a HOLD volley at unit 2; `split` aims the host's Rifle at "b" through a split
/// group while the recorded target is the hero "bh".
fn dice(owner: &str, by_edge: bool, armed_host: bool, hero_gap_in: f64, epoch: u32, sighting: bool, split: bool) -> (i64, Vec<String>) {
    let (st, statics) = line(by_edge, armed_host, hero_gap_in);
    let mut hold = advance_to(0.0);
    hold.kind = HOLD;
    hold.dest = None;
    hold.shoot = Some(if split { "bh" } else { "b" }.into());
    if split {
        hold.split = Some(vec![SplitShot { member: "Gun Squad".into(), weapon: "Rifle".into(), target: "b".into() }]);
    }
    let seams = Seams {
        rules_epoch: epoch, hero_attach: true, range_by_base_edge: by_edge, sighting, ..Seams::default()
    };
    let terrain = crate::terrain::Terrain::default();
    let (_, shot): (State, ShootResult) = resolve_stochastic_tray_on_board(
        &statics, &st, &hold, &terrain, seams, &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(1),
    )
    .unwrap();
    let n = shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == owner).map(|r| r.count).sum();
    (n, shot.log)
}

#[test]
fn the_fixture_has_the_gaps_the_diagnosis_measured() {
    let (st, _) = line(true, true, 11.5);
    assert!((range_gap_in(&st, &st.positions[0], 0, 2) - 12.5).abs() < 1e-6, "host gap 12.5\"");
    assert!((range_gap_in(&st, &st.positions[0], 0, 3) - 11.5).abs() < 1e-6, "hero gap 11.5\"");
    let (st, _) = line(false, true, 11.5);
    assert!((crate::geom::dist_in(&st.positions[0], &st.positions[2]) - 12.5).abs() < 1e-6, "centre host 12.5\"");
    assert!((crate::geom::dist_in(&st.positions[0], &st.positions[3]) - 11.5).abs() < 1e-6, "centre hero 11.5\"");
}

/// RED on main, pooled entry: the host's 12.5" gap drops the 12" Rifle although the target's hero stands 11.5" away.
#[test]
fn a_weapon_in_reach_of_the_targets_joined_hero_fires_at_epoch_73() {
    for (by_edge, sighting) in [(true, true), (true, false), (false, true), (false, false)] {
        let (n, log) = dice("Gun Squad", by_edge, true, 11.5, EPOCH_73_V36, sighting, false);
        assert_eq!(n, 3, "by_edge={by_edge} sighting={sighting}: three Rifle dice {log:?}");
    }
}

/// RED on main, split entry: the same shot through a split group aimed at the target host.
#[test]
fn a_split_group_measures_to_the_targets_joined_hero_at_epoch_73() {
    for sighting in [true, false] {
        let (n, log) = dice("Gun Squad", true, true, 11.5, EPOCH_73_V36, sighting, true);
        assert_eq!(n, 3, "sighting={sighting}: three Rifle dice {log:?}");
    }
}

/// RED on main, hero entry: a joined shooter hero's own gap is measured to the target's chain too.
#[test]
fn a_joined_heros_weapon_in_reach_of_the_targets_hero_fires_at_epoch_73() {
    for (by_edge, sighting) in [(true, true), (true, false), (false, true), (false, false)] {
        let (n, log) = dice("Squad Leader", by_edge, false, 11.5, EPOCH_73_V36, sighting, false);
        assert_eq!(n, 2, "by_edge={by_edge} sighting={sighting}: two Carbine dice {log:?}");
    }
}

/// The applied rule names itself in the battle log, the way the table does ("range is measured to the nearest model").
#[test]
fn the_chain_gap_writes_a_battle_log_line() {
    let (_, log) = dice("Gun Squad", true, true, 11.5, EPOCH_73_V36, false, false);
    assert!(log.iter().any(|l| l.contains("Shooting Range:") && l.contains("nearest model of Target Host")), "{log:?}");
}

/// CONTROL: below 73 the host-only gap replays - the weapon stays dropped on every entry.
#[test]
fn below_epoch_73_the_host_gap_still_drops_the_weapon() {
    for sighting in [true, false] {
        assert_eq!(dice("Gun Squad", true, true, 11.5, EPOCH_72_PLAYTEST_RULES, sighting, false).0, 0, "pooled");
        assert_eq!(dice("Gun Squad", true, true, 11.5, EPOCH_72_PLAYTEST_RULES, sighting, true).0, 0, "split");
        assert_eq!(dice("Squad Leader", true, false, 11.5, EPOCH_72_PLAYTEST_RULES, sighting, false).0, 0, "hero");
    }
}

/// CONTROL: the chain gap is the nearest model, no slack - a hero at 12.01" and a hero behind the host (13.5") are
/// out of a 12" gun's reach, a hero at 11.99" is in.
#[test]
fn the_chain_gap_is_the_nearest_model_with_no_slack() {
    for gap in [13.5, 12.5, 12.01] {
        assert_eq!(dice("Gun Squad", true, true, gap, EPOCH_73_V36, false, false).0, 0, "{gap}\" of 12\"");
    }
    assert_eq!(dice("Gun Squad", true, true, 11.99, EPOCH_73_V36, false, false).0, 3, "11.99\" of 12\"");
}

/// CONTROL: a target host already in reach fires on its own, with or without a hero (passes before and after).
#[test]
fn a_target_host_in_reach_fires_on_its_own_gap() {
    let (st, statics) = line(true, true, 11.5);
    let mut near = st.clone();
    near.positions[2] = vec![[11.0 * IN2M, 0.0, 0.0]];
    near.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
    near.attached_to = Rc::new(vec![None, Some(0), None, None]);
    near.alive[3] = 0;
    near.positions[3].clear();
    let mut hold = advance_to(0.0);
    hold.kind = HOLD;
    hold.dest = None;
    hold.shoot = Some("b".into());
    let seams = Seams { rules_epoch: EPOCH_73_V36, hero_attach: true, range_by_base_edge: true, ..Seams::default() };
    let (_, shot) = resolve_stochastic_tray_on_board(
        &statics, &near, &hold, &crate::terrain::Terrain::default(), seams,
        &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(1),
    )
    .unwrap();
    let n: i64 = shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Gun Squad").map(|r| r.count).sum();
    assert_eq!(n, 3, "{:?}", shot.log);
}
