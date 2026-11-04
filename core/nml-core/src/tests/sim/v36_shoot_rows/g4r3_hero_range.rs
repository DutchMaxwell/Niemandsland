//! G4R3 F-HERO-RANGE (rules 3.6, `EPOCH_73_V36`): shooting range is measured per MODEL, so a joined
//! hero's weapon is gated by the hero's OWN nearest gap to the target, not by the host's. The core
//! gated every member by the host's gap and dropped a hero weapon the table fires (gf_1000_net_010
//! act 13: 12" Dual Suit-Flamers, host gap 12.3", hero gap 10.7"). Below 73 the old gate replays.
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::rules::Registries;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Two real profiles the way the game builds them: a host with NO weapon of its own and a hero
/// with one 12" flamer, so every attack die in the volley is the hero's.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "host":{"unit_id":"host","name":"Battle Suit Elite","quality":4,"defense":4,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"gf",
    "faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "hero":{"unit_id":"hero","name":"Suit Commander","quality":4,"defense":4,"tough":3,
    "wounds_max":[3],"model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"gf",
    "faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Dual Suit-Flamers","range":12,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

/// Unit 0 = the host, unit 1 = its joined hero, unit 2 = the lone target, all on 1" bases. The
/// host stands 12.3" from the target (edge to edge), the hero `hero_gap_in` from it.
fn line(hero_gap_in: f64) -> (State, Vec<UnitStatic>) {
    let header = crate::read_act_header(HEADER).expect("HEADER parses");
    let mut reg = Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), EPOCH_73_V36);
    let (mut st, mut statics) = hero_line();
    statics[0] = build("host");
    statics[1] = build("hero");
    statics[2] = UnitStatic {
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
        name: "Target".into(),
        model_count: 1,
        wounds_max: vec![9],
        ..Default::default()
    };
    st.wounds[2] = vec![9];
    let keys = st.roster.keys.clone();
    let index = keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    st.roster = Rc::new(Roster { keys, index, profile: vec![0, 1, 2, 3] });
    let base = st.profiles.list[0].clone();
    st.profiles = Rc::new(Profiles { list: vec![base; 4], index: HashMap::new() });
    st.alive = vec![1, 1, 1, 0];
    st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, Some(0), None, None]);
    let target_x = 14.3; // host edge gap 14.3 - 1 - 1 = 12.3"
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.positions[1] = vec![[(target_x - 2.0 - hero_gap_in) * IN2M, 0.0, 0.0]];
    st.positions[2] = vec![[target_x * IN2M, 0.0, 0.0]];
    st.positions[3].clear();
    for u in 0..4 {
        Rc::make_mut(&mut st.radii)[u] = vec![IN2M];
    }
    (st, statics)
}

/// The hero's attack dice through the whole tray resolve of a HOLD volley at unit 2.
fn hero_dice(hero_gap_in: f64, epoch: u32, sighting: bool) -> i64 {
    let (st, statics) = line(hero_gap_in);
    let mut hold = advance_to(0.0);
    hold.kind = HOLD;
    hold.dest = None;
    hold.shoot = Some("b".into());
    let seams = Seams {
        rules_epoch: epoch, hero_attach: true, range_by_base_edge: true, sighting, ..Seams::default()
    };
    let terrain = crate::terrain::Terrain::default();
    let (_, shot): (State, ShootResult) = resolve_stochastic_tray_on_board(
        &statics, &st, &hold, &terrain, seams, &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(1),
    )
    .unwrap();
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Suit Commander").map(|r| r.count).sum()
}

#[test]
fn the_fixture_has_the_gaps_the_diagnosis_measured() {
    let (st, _) = line(10.7);
    assert!((range_gap_in(&st, &st.positions[0], 0, 2) - 12.3).abs() < 1e-6, "host gap 12.3\"");
    assert!((range_gap_in(&st, &st.positions[1], 1, 2) - 10.7).abs() < 1e-6, "hero gap 10.7\"");
}

/// RED on main: the host's 12.3" gap drops the hero's 12" flamer before sight is even asked.
#[test]
fn a_hero_standing_nearer_fires_its_weapon_at_epoch_73() {
    for sighting in [true, false] {
        assert_eq!(hero_dice(10.7, EPOCH_73_V36, sighting), 2, "sighting={sighting}: two flamer dice");
    }
}

#[test]
fn below_epoch_73_the_host_gap_still_drops_the_hero_weapon() {
    for sighting in [true, false] {
        assert_eq!(hero_dice(10.7, EPOCH_72_PLAYTEST_RULES, sighting), 0, "sighting={sighting}: epoch 72 replays");
    }
}

/// The gate is the hero's OWN gap: a hero behind the host (13.3"), level with it (12.3") and a hair
/// past the weapon's range (12.01") are all out of a 12" weapon's reach — no slack.
#[test]
fn a_hero_out_of_range_by_its_own_gap_does_not_fire() {
    for sighting in [true, false] {
        for gap in [13.3, 12.3, 12.01] {
            assert_eq!(hero_dice(gap, EPOCH_73_V36, sighting), 0, "sighting={sighting}: {gap}\" of 12\"");
        }
    }
}

/// A hair inside the weapon's range the hero fires (the range test is the edge gap, no centre ruler).
#[test]
fn a_hero_just_inside_its_range_fires() {
    for sighting in [true, false] {
        assert_eq!(hero_dice(11.99, EPOCH_73_V36, sighting), 2, "sighting={sighting}: 11.99\" of 12\"");
    }
}
