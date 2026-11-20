//! Plan H, H-18 (`PENDING_EPOCH_VERSATILE_MODIFIED_HIT`): the Versatile Attack pick is made on the number the first eligible shot rolls at,
//! not on the plain Quality. A Quality-4 AP(1) shooter at Defense 3+ ties plain (the tie goes to AP(+1), the table's pick); against Stealth
//! from over 9" the number is 5+ and the hit mode wins. The core latched the pick before the dice on the plain Quality 4 and said AP(+1).
//! Units are built the way the game builds them (real profiles through `UnitStatic::build_for`).
use super::*;
use crate::acts::PENDING_EPOCH_VERSATILE_MODIFIED_HIT as PENDING;
use crate::dice::Tray;
use crate::read_act_header;
use crate::rules::Registries;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Pickers (Quality 4, Versatile Attack, an AP(1) rifle) and two Defense-3 targets: Stalkers (Stealth) and plain Walkers.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "pickers":{"unit_id":"pickers","name":"Pickers","quality":4,"defense":4,"tough":1,"wounds_max":[1],
    "model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"aof","faction_folder":"human_empire",
    "special_rules":["Versatile Attack"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":12,"count":1,"ap":1,"rules":[]}]},
  "stealth":{"unit_id":"stealth","name":"Stalkers","quality":4,"defense":3,"tough":1,"wounds_max":[400],
    "model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"aof","faction_folder":"human_empire",
    "special_rules":["Stealth"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Club","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "plain":{"unit_id":"plain","name":"Walkers","quality":4,"defense":3,"tough":1,"wounds_max":[400],
    "model_count":1,"caster_value":0,"base_radius":0.0254,"game_system":"aof","faction_folder":"human_empire",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Club","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

/// Unit 0 = the Pickers, unit 2 = the target `key`, `gap_in` apart edge to edge, built at `epoch`.
fn line(key: &str, gap_in: f64, epoch: u32) -> (State, Vec<UnitStatic>) {
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = Registries::new(&repo_root());
    let mut build = |k: &str| UnitStatic::build_for(&mut reg, header.profiles.get(k).expect(k), epoch);
    let (pickers, target) = (build("pickers"), build(key));
    assert!(pickers.shoot[0].versatile_attack, "the Rifle carries Versatile Attack");
    assert_eq!(target.ctx.stealth, key == "stealth", "{key}: Stealth is the only to-hit rule here");
    let (mut st, mut statics) = buff_line();
    statics[0] = UnitStatic { model_count: 1, wounds_max: vec![1], ..pickers };
    statics[2] = UnitStatic { model_count: 1, wounds_max: vec![400], ..target };
    (st.alive[0], st.alive[2]) = (1, 1);
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.positions[2] = vec![[(gap_in + 2.0) * IN2M, 0.0, 0.0]];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M], vec![IN2M], vec![]]);
    (st.wounds[0], st.wounds[2]) = (vec![1], vec![400]);
    (st, statics)
}

/// One HOLD volley at `key`: the activation's pick line and the State's latch after it.
fn volley(key: &str, gap_in: f64, epoch: u32) -> (String, i64) {
    let (st, statics) = line(key, gap_in, epoch);
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let terrain = crate::terrain::Terrain::default();
    let (next, shot) = resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &terrain, seams,
        &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(3)).unwrap();
    let line = shot.log.iter().find(|l| l.contains("picks")).cloned().unwrap_or_else(|| format!("no pick line: {:?}", shot.log));
    (line, if next.versatile_pick_round[0] == next.round { next.versatile_pick_mode[0] } else { 0 })
}

/// RED on main (the gate is off there): the plain Quality 4 ties and picks AP(+1); the number rolled at is 5+.
#[test]
fn from_the_pending_epoch_the_pick_reads_the_stealth_modified_number() {
    let (line, latch) = volley("stealth", 12.0, PENDING);
    assert!(line.contains("Pickers picks +1 to hit"), "{line}");
    assert!(line.starts_with("Versatile Attack:"), "the line names the book rule: {line}");
    assert_eq!(latch, 1, "the pick is stamped on the round latch (1 = +1 to hit) for the rest of the activation");
}

/// Below the gate the old latch replays: the plain Quality 4, AP(+1).
#[test]
fn below_the_pending_epoch_the_pick_still_reads_the_plain_quality() {
    let (line, latch) = volley("stealth", 12.0, PENDING - 1);
    assert!(line.contains("Pickers picks AP(+1)"), "{line}");
    assert_eq!(latch, 2);
}

/// CONTROL (passes before and after): no to-hit rule on the target, the plain Quality is the number rolled.
#[test]
fn a_plain_target_picks_alike_below_and_at_the_pending_epoch() {
    for epoch in [PENDING - 1, PENDING] {
        let (line, latch) = volley("plain", 12.0, epoch);
        assert!(line.contains("Pickers picks AP(+1)"), "epoch {epoch}: {line}");
        assert_eq!(latch, 2, "epoch {epoch}");
    }
}

/// CONTROL: inside the gate there is no eligible shot, so no pick and no latch, at either epoch.
#[test]
fn within_the_gate_there_is_no_pick() {
    for epoch in [PENDING - 1, PENDING] {
        let (line, latch) = volley("stealth", 5.0, epoch);
        assert!(line.starts_with("no pick line"), "epoch {epoch}: {line}");
        assert_eq!(latch, 0, "epoch {epoch}");
    }
}
