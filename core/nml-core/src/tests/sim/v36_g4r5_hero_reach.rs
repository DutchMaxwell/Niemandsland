//! Rules 3.6 row G4R5 R5 F-HERO-REACH (replay row gf_1000_net_019 act 16): a joined hero's weapon is gated by
//! the nearest model of the target's WHOLE unit - the target's own joined hero included.
//!
//! The Highborn reach bonus of the hero was stamped all along (the volley logs it); what dropped the hero's
//! Burst Shred-Blaster Pistol was the range pre-gate, which measured the hero's own gap to the target's HOST
//! only. The table's target models include the attached heroes' (`_solo_sighted_count`), so a hero standing
//! in front of its host is the nearest target model. From `EPOCH_73_V36` the per-member gap takes the nearest
//! model of the target's chain; the host's `g.d` and everything below 73 stay as they were.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// The real Scorchers (Highborn) with their joined Trasara Ioncrinius (Highborn, pistol 9"), and the real
/// Cultists with their Cultist Champion, as the gf_019 recording carries them (one model per unit here).
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "scorchers":{"unit_id":"scorchers","name":"Scorchers","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.0125,"game_system":"gf","faction_folder":"high_elf_fleets",
    "special_rules":["Highborn"],"item_grants":[],
    "attached_hero_rules":[["Tough(3)","Unique Hero","Highborn"]],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Heavy Flamer","range":12,"attacks":1,"count":1,"ap":1,"rules":["AP(1)","Blast(3)","Reliable"]}]},
  "trasara":{"unit_id":"trasara","name":"Trasara Ioncrinius","quality":3,
    "defense":4,"tough":3,"wounds_max":[3],"model_count":1,"caster_value":0,
    "base_radius":0.02,"game_system":"gf","faction_folder":"high_elf_fleets",
    "special_rules":["Tough(3)","Unique Hero","Highborn"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Burst Shred-Blaster Pistol","range":9,"attacks":3,"count":1,"ap":0,"rules":["Rending","Assault"]}]},
  "cultists":{"unit_id":"cultists","name":"Cultists","quality":4,
    "defense":5,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.0125,"game_system":"gf","faction_folder":"havoc_cultists",
    "special_rules":["Havocbound"],"item_grants":[],
    "attached_hero_rules":[["Hero","Tough(3)","Havocbound"]],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Battle Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "champion":{"unit_id":"champion","name":"Cultist Champion","quality":3,
    "defense":5,"tough":3,"wounds_max":[3],"model_count":1,"caster_value":0,
    "base_radius":0.02,"game_system":"gf","faction_folder":"havoc_cultists",
    "special_rules":["Hero","Tough(3)","Havocbound"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Burst Shotgun","range":12,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Units 0/1 = Scorchers + their Trasara, units 2/3 = Cultists + their Champion, at the table's landing in
/// gf_019 act 16 (metres). Trasara is 9.7" (base edge) from the Champion but 13.2" from the Cultists host,
/// so the Highborn 9 + 4 = 13" pistol reaches the Champion only. `champion_alive` false strips the Champion.
fn line(champion_alive: bool) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
    st.positions = vec![
        vec![[0.1217510923743248, 0.0, 0.02169794961810112]],
        vec![[0.17245468497276306, 0.0, 0.06325597316026688]],
        vec![[0.4893606901168823, 0.0, -0.12173530459403992]],
        if champion_alive { vec![[0.4180307388305664, 0.0, -0.0835031270980835]] } else { vec![] },
    ];
    st.radii = Rc::new(vec![vec![0.0125], vec![0.02], vec![0.0125], vec![0.02]]);
    st.wounds = vec![vec![1], vec![3], vec![1], if champion_alive { vec![3] } else { vec![] }];
    st.alive = vec![1, 1, 1, i64::from(champion_alive)];
    st.attached = Rc::new(vec![vec![1], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, Some(0), None, Some(2)]);
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), EPOCH_73_V36);
    let statics = vec![build("scorchers"), build("trasara"), build("cultists"), build("champion")];
    (st, statics)
}

/// The replayed act: a Hold, the table's split aim naming both weapons at the Cultists, the sighted model gate on.
fn volley(champion_alive: bool, epoch: u32) -> ShootResult {
    let (st, statics) = line(champion_alive);
    let mut action = advance_shoot("bh");
    action.kind = HOLD;
    let aim = |member: &str, weapon: &str| crate::io::SplitShot { member: member.into(), weapon: weapon.into(), target: "b".into() };
    action.split = Some(vec![aim("Scorchers", "Heavy Flamer"), aim("Trasara Ioncrinius", "Burst Shred-Blaster Pistol")]);
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(7));
    let seams = Seams { rules_epoch: epoch, hero_attach: true, sighting: true, range_by_base_edge: true, ..Seams::default() };
    resolve_stochastic_tray_on_board(&statics, &st, &action, &small_board(), seams, &mut rng, &mut tray).unwrap().1
}

/// The Pistol's `attack` roll: three dice signed by Trasara.
fn pistol_dice(shot: &ShootResult) -> i64 {
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Trasara Ioncrinius").map(|r| r.count).sum()
}

/// The row (RED on main): Trasara's pistol reaches the Champion, the nearest model of the Cultists unit.
#[test]
fn a_joined_hero_fires_at_the_nearest_model_of_the_targets_whole_unit_from_73() {
    let shot = volley(true, EPOCH_73_V36);
    assert_eq!(pistol_dice(&shot), 3, "the Pistol fires its 3 dice (RED on main: 0); {:?} {:?}", shot.rolls, shot.log);
    assert!(
        shot.log.iter().any(|l| l.contains("Highborn: Trasara Ioncrinius gains +4\" reach on Cultists")),
        "the applied rule names itself: {:?}",
        shot.log
    );
}

/// CONTROL (passes with and without the change): without the Champion the nearest target model is the host,
/// 13.2" away - the Highborn 13" pistol still falls short, so the bonus stays bounded.
#[test]
fn a_hero_out_of_reach_of_every_model_of_the_target_unit_stays_silent() {
    let shot = volley(false, EPOCH_73_V36);
    assert_eq!(pistol_dice(&shot), 0, "{:?} {:?}", shot.rolls, shot.log);
}

/// Below 73 the per-member gap stays the host's: the same pistol is not fired at the Champion's distance.
#[test]
fn below_73_the_hero_is_gated_by_the_host_gap_alone() {
    let shot = volley(true, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(pistol_dice(&shot), 0, "{:?} {:?}", shot.rolls, shot.log);
}
