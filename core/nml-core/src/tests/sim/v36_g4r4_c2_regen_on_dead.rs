//! Rules 3.6 row G4R4 R3-C2 (replay row aof_1000_net_035 act 32): when Deadly wounds already destroy the
//! defender, the pool's Regeneration die is not rolled - there is no living model left to ignore a wound.
//!
//! The table lands Deadly first and the pool afterwards, so the pool's ignore roll finds an empty unit. The
//! core rolled the pool's Regeneration in the dice leg BEFORE any landing and drew one die too many. From
//! `EPOCH_73_V36` the leg asks whether the Deadly groups wipe the defender and skips that roll; the battle log
//! names the rule. Below 73 the extra die stays, byte for byte.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// A real attacker with a Deadly(3) harpoon and a plain pike, and a real one-model Artillery with Cursed Undead
/// (a 6+ ignore roll per wound), both built from profiles the way the game builds a unit.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "hunters":{"unit_id":"hunters","name":"Hunters","quality":2,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Harpoon","range":0,"attacks":1,"count":1,"ap":0,"rules":["Deadly(3)"]},
      {"name":"Sky-Pike","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "artillery":{"unit_id":"artillery","name":"Artillery","quality":4,
    "defense":6,"tough":3,"wounds_max":[3],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"vampiric_undead",
    "special_rules":["Cursed Undead"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Unit 0 = the Hunters, unit 2 = the Artillery with two of its three wounds left, 2.5" away.
fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![], vec![[2.5 * IN2M, 0.0, 0.0]], vec![]];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], vec![]]);
    st.wounds = vec![vec![1], vec![], vec![2], vec![]];
    st.alive = vec![1, 0, 1, 0];
    st.attached = Rc::new(vec![vec![]; 4]);
    st.attached_to = Rc::new(vec![None; 4]);
    let header = read_act_header(HEADER).expect("HEADER parses");
    let (dummy, hunters_p, artillery_p) = (st.profiles.list[0].clone(), header.profiles.get("hunters").expect("hunters").clone(), header.profiles.get("artillery").expect("artillery").clone());
    st.profiles = Rc::new(Profiles { list: vec![hunters_p, dummy.clone(), artillery_p, dummy], index: HashMap::new() });
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), epoch);
    let (hunters, artillery) = (build("hunters"), build("artillery"));
    (st, vec![hunters, UnitStatic { name: "ah".into(), ..Default::default() }, artillery, UnitStatic { name: "bh".into(), ..Default::default() }])
}

fn charge(st: &State, statics: &[UnitStatic], seed: i64, epoch: u32) -> (State, ShootResult) {
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
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(seed));
    // The live seams derive the tray-exact landing order from the epoch (plan.rs): Takedown, Deadly, THEN the pool.
    let tray_exact = crate::acts::rule_on(epoch, crate::acts::EPOCH_70_TRAY_EXACT);
    let seams = Seams { rules_epoch: epoch, hero_attach: true, tray_exact, ..Seams::default() };
    resolve_stochastic_tray_on_board(statics, st, &action, &Terrain::default(), seams, &mut rng, &mut tray).unwrap()
}

/// How many Regeneration (Cursed Undead, 6+) roll entries the Artillery's ignore tests wrote.
fn regen_rolls(shot: &ShootResult) -> usize {
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Artillery" && r.target == 6).count()
}

/// The wounds the Deadly(3) hit lands after the Artillery's 6+ ignore dice: three dice, one per wound of the hit.
/// Nothing when no Deadly hit got through the save.
fn deadly_wounds(shot: &ShootResult) -> Option<i64> {
    let r = shot.rolls.iter().find(|r| r.kind == "attack" && r.owner == "Artillery" && r.target == 6 && r.count == 3)?;
    Some(3 - r.faces.iter().filter(|&&f| f >= 6).count() as i64)
}

/// Every charge in which the Deadly hit ALONE destroys the Artillery (two wounds left, so two landed Deadly wounds
/// do it); a Deadly hit that leaves it standing and a pike wound that finishes it are not this case.
fn deadly_wipes(epoch: u32) -> Vec<(State, ShootResult)> {
    let (st, statics) = line(epoch);
    (0..300)
        .map(|s| charge(&st, &statics, s, epoch))
        .filter(|(next, shot)| next.alive[2] == 0 && deadly_wounds(shot).is_some_and(|d| d >= 2))
        .collect()
}

/// The row: a Deadly wipe leaves no pool ignore roll - one roll entry (the Deadly dice), never two - and the
/// log names the rule on the charges where the pike's wound would have rolled one.
#[test]
fn a_deadly_wipe_rolls_no_pool_regeneration_die_from_73() {
    let all = deadly_wipes(EPOCH_73_V36);
    assert!(all.len() >= 20, "fixture: the Deadly hit wipes the Artillery often enough ({})", all.len());
    for (i, (_, shot)) in all.iter().enumerate() {
        assert!(regen_rolls(shot) <= 1, "wipe #{i} rolled a die for the pool after the unit was gone: {:?}", shot.rolls);
    }
    assert!(
        all.iter().any(|(_, shot)| shot.log.iter().any(|l| l.starts_with("Regeneration:") && l.contains("Artillery"))),
        "the applied rule names itself on at least one wipe"
    );
}

/// Below 73 the extra die stays: some wipe still rolls two ignore entries.
#[test]
fn below_73_the_pool_regeneration_die_is_still_rolled() {
    let all = deadly_wipes(EPOCH_72_PLAYTEST_RULES);
    assert!(all.iter().any(|(_, shot)| regen_rolls(shot) == 2), "{} wipes, none with the pool die", all.len());
    assert!(all.iter().all(|(_, shot)| shot.log.iter().all(|l| !l.starts_with("Regeneration:"))));
}

/// CONTROL: a unit the pike's single wound leaves standing still gets that wound's ignore die at 73.
#[test]
fn a_surviving_unit_still_rolls_its_pool_regeneration_die_at_73() {
    let (st, statics) = line(EPOCH_73_V36);
    let survived: Vec<_> = (0..300).map(|s| charge(&st, &statics, s, EPOCH_73_V36)).filter(|(next, _)| next.alive[2] > 0).collect();
    let one_die = |shot: &ShootResult| shot.rolls.iter().any(|r| r.kind == "attack" && r.owner == "Artillery" && r.target == 6 && r.count == 1);
    assert!(survived.iter().any(|(_, shot)| one_die(shot)), "{} survivors, none rolled the pike wound's ignore die", survived.len());
}
