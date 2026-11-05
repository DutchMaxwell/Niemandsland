//! G4R4 row C-GRANTED-RANGE (core half): a spell can hand a unit a Royal Legion-family rule ("Lust Boon" grants
//! Enhanced Lustbound, +8" shooting range) and the table reads that live grant per member when it measures the
//! volley's reach. The core stamped a reach bonus only from the unit's STATIC rules, so a granted +8" never opened a
//! longer shot. From `EPOCH_73_V36` the volley reads the live grant too (battle log: the granted rule's name).
//! Replay rows: gf_1000_net_026 act 9 and gf_1000_net_027 act 2 (the harness half, carrying the cast's token into the
//! act's `pre` block, is a separate row).
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// A real Lust Disciples shooter: two models, a 24" rifle each, no static Royal Legion rule.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "shooter":{"unit_id":"shooter","name":"Shooter","quality":4,"defense":4,"tough":1,"wounds_max":[1,1],"model_count":2,
    "caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"lust_disciples",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":2,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// One live ledger record on the shooter's own net: the granted rule name, once.
fn grant(rule: &str) -> crate::mods::LiveMod {
    crate::mods::LiveMod {
        hit_mod: 0,
        casting_mod: 0,
        morale_mod: 0,
        ap_mod: 0,
        def_mod: 0,
        defense_mod: 0,
        move_mod: 0,
        grants_rule: Rc::from(rule),
        scope: Rc::from(""),
        attackers: false,
        once: true,
        name: Rc::from(rule),
    }
}

/// The shooter "a" (built the way the game builds it) and the target "b" parked 30" away, past the plain 24".
fn line(epoch: u32, granted: Option<&str>) -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    statics[0] = UnitStatic::build_for(&mut reg, header.profiles.get("shooter").expect("shooter"), epoch);
    st.positions[2] = vec![[30.0 * IN2M, 0.0, 0.0], [30.02 * IN2M, 0.0, 0.0], [30.04 * IN2M, 0.0, 0.0]];
    // `ah` off the firing line so the range gate is the ONLY variable.
    st.positions[1] = vec![[-2.0 * IN2M, 5.0 * IN2M, 0.0]];
    if let Some(rule) = granted {
        st.buffs[0].push(grant(rule));
    }
    (st, statics)
}

fn volley(st: &State, statics: &[UnitStatic], epoch: u32) -> ShootResult {
    let seams = Seams { sighting: true, rules_epoch: epoch, ..Default::default() };
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(statics, st, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray).unwrap().1
}

fn fired(shot: &ShootResult) -> bool {
    shot.rolls.iter().any(|r| r.kind == "attack")
}

/// The row: the granted Enhanced Lustbound adds 8" to the rifle's 24", so the target at 30" is in reach, and the
/// battle log names the granted rule. RED on main: the grant is on the ledger but nothing reads it for reach.
#[test]
fn a_granted_royal_legion_rule_extends_the_volleys_reach_at_73() {
    let (st, statics) = line(EPOCH_73_V36, Some("Enhanced Lustbound"));
    let shot = volley(&st, &statics, EPOCH_73_V36);
    assert!(fired(&shot), "24 + 8 covers the 30\" gap: {:?}", shot.rolls);
    assert!(
        shot.log.iter().any(|l| l.starts_with("Enhanced Lustbound:") && l.contains("+8\" reach")),
        "the applied rule names itself: {:?}",
        shot.log
    );
}

/// CONTROL: no grant, no extra reach — the same volley stays silent at 30".
#[test]
fn without_the_grant_the_rifle_stays_at_24_inches() {
    let (st, statics) = line(EPOCH_73_V36, None);
    assert!(!fired(&volley(&st, &statics, EPOCH_73_V36)));
}

/// CONTROL: a granted rule that is no Royal Legion entry (the Furious record of the other grant tests) adds nothing.
#[test]
fn a_grant_without_a_reach_bonus_adds_no_reach() {
    let (st, statics) = line(EPOCH_73_V36, Some("Furious"));
    assert!(!fired(&volley(&st, &statics, EPOCH_73_V36)));
}

/// CONTROL: below 73 the grant stays inert for reach, byte for byte.
#[test]
fn below_73_the_grant_adds_no_reach() {
    let (st, statics) = line(EPOCH_72_PLAYTEST_RULES, Some("Enhanced Lustbound"));
    assert!(!fired(&volley(&st, &statics, EPOCH_72_PLAYTEST_RULES)));
}
