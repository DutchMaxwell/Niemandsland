//! G4R3 F-SURGE-GRANT (rules 3.6, `EPOCH_73_V36`): a spell that hands its target's ATTACKERS the rule
//! "Surge" (a once-grant on the target's ledger, `beneficiary: "attackers"`) pays +1 hit per unmodified 6
//! on the volley that targets it. The table folds the grant into the shooter's profile
//! (`_solo_bridge_granted_flags`); `ctx_live_vs` read only Rending, Furious, Relentless and Shred
//! (aof_1000_net_002 act 25: Peasant Bowmen's Bow against a unit under Curse of the Huntress).
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::rules::Registries;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// A real profile built the way the game builds it: a bowman with a plain Bow that prints no Surge.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "bowmen":{"unit_id":"bowmen","name":"Peasant Bowmen","quality":4,"defense":4,"tough":1,
    "wounds_max":[1,1],"model_count":2,"caster_value":0,"base_radius":0.0254,"game_system":"aof",
    "faction_folder":"chivalrous_kingdoms","special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Bow","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

/// `buff_line` with the bowmen on unit 0 and a hardened target (unit 2, three models of three wounds) so
/// neither volley can wipe it.
fn line() -> (State, Vec<UnitStatic>) {
    let header = crate::read_act_header(HEADER).expect("HEADER parses");
    let mut reg = Registries::new(&repo_root());
    let bowmen = UnitStatic::build_for(&mut reg, header.profiles.get("bowmen").expect("bowmen"), EPOCH_73_V36);
    assert!(!bowmen.shoot[0].surge, "the Bow prints no Surge of its own");
    let (mut st, mut statics) = buff_line();
    statics[0] = UnitStatic { model_count: 2, wounds_max: vec![1, 1], ..bowmen };
    statics[2].wounds_max = vec![3, 3, 3];
    st.wounds[2] = vec![3, 3, 3];
    (st, statics)
}

/// The ledger record the table keeps on the TARGET after the spell: a once-grant of "Surge" to its attackers.
fn curse() -> crate::mods::LiveMod {
    crate::mods::LiveMod {
        hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0,
        grants_rule: Rc::from("Surge"), scope: Rc::from("shooting"), attackers: true, once: true,
        name: Rc::from("Curse of the Huntress"),
    }
}

fn run(st: &State, statics: &[UnitStatic], seed: i64, epoch: u32) -> (State, ShootResult) {
    let terrain = crate::terrain::Terrain::default();
    resolve_stochastic_tray_on_board(
        statics, st, &buff_action(Some("b")), &terrain, Seams { rules_epoch: epoch, ..Seams::default() },
        &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(seed),
    )
    .unwrap()
}

/// The hits the saves ran on (the vs_grant_marks precedent).
fn hits(r: &ShootResult) -> i64 {
    r.rolls.iter().filter(|x| x.kind == "defense").map(|x| x.count).sum()
}

/// The unmodified 6s among the attack faces.
fn sixes(r: &ShootResult) -> i64 {
    r.rolls.iter().find(|x| x.kind == "attack").expect("the attack roll").faces.iter().filter(|&&f| f == 6).count() as i64
}

/// The first seed whose eight Bow dice carry at least one unmodified 6 (so the grant has something to pay on).
fn seed_with_a_six() -> i64 {
    let (st, statics) = line();
    (1..=40).find(|&s| sixes(&run(&st, &statics, s, EPOCH_73_V36).1) >= 1).expect("a seed with a six")
}

/// RED on main: the grant sits on the target's ledger and nothing reads it.
#[test]
fn a_spell_granted_surge_pays_one_hit_per_unmodified_six_at_epoch_73() {
    let (st, statics) = line();
    let seed = seed_with_a_six();
    let (_, plain) = run(&st, &statics, seed, EPOCH_73_V36);
    let mut marked = st.clone();
    marked.buffs[2] = vec![curse()];
    let (_, granted) = run(&marked, &statics, seed, EPOCH_73_V36);
    assert_eq!(hits(&granted) - hits(&plain), sixes(&plain), "+1 hit per unmodified 6 against the cursed unit");
}

/// Below 73 the attackers-side Surge stays unread: the record lands on the ledger and pays nothing.
#[test]
fn below_epoch_73_the_grant_stays_unread() {
    let (st, statics) = line();
    let seed = seed_with_a_six();
    let (_, plain) = run(&st, &statics, seed, EPOCH_72_PLAYTEST_RULES);
    let mut marked = st.clone();
    marked.buffs[2] = vec![curse()];
    let (_, granted) = run(&marked, &statics, seed, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(hits(&granted), hits(&plain), "epoch 72: byte-identical");
}

/// "Once": the exchange spends the record, so the next volley at the same unit pays nothing extra.
#[test]
fn the_grant_is_spent_by_the_volley_that_used_it() {
    let (st, statics) = line();
    let seed = seed_with_a_six();
    let mut marked = st.clone();
    marked.buffs[2] = vec![curse()];
    let (after, _) = run(&marked, &statics, seed, EPOCH_73_V36);
    assert!(after.buffs[2].is_empty(), "the exchange spends the once-record");
    let (_, again) = run(&after, &statics, seed, EPOCH_73_V36);
    let (_, control) = run(&after, &statics, seed, EPOCH_73_V36);
    assert_eq!(hits(&again), hits(&control));
}

/// Rules-must-log: the volley names the book rule and the spell that granted it.
#[test]
fn the_volley_names_surge_and_the_spell_that_granted_it() {
    let (st, statics) = line();
    let mut marked = st.clone();
    marked.buffs[2] = vec![curse()];
    let (_, shot) = run(&marked, &statics, seed_with_a_six(), EPOCH_73_V36);
    assert!(
        shot.log.iter().any(|l| l.starts_with("Surge: Peasant Bowmen") && l.contains("Curse of the Huntress")),
        "log: {:?}", shot.log
    );
    let (_, plain) = run(&st, &statics, seed_with_a_six(), EPOCH_73_V36);
    assert!(plain.log.iter().all(|l| !l.starts_with("Surge:")), "no grant, no line");
}
