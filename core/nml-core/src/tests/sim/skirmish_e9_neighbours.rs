//! The skirmish Blast(X) spread's neighbours (`sim::blast_neighbours`): the target's own side, base edge to base edge
//! within the spread distance (3 in in the Firefight / AoF: Skirmish books), with their living models.
use super::*;

/// Unit 0 = the target (two models at x 20 / 21.5 in), unit 1 its side at 2.9 in edge gap, unit 2 its side at 3.1 in,
/// unit 3 the shooter's side at 0.5 in. 32 mm bases (0.63 in radius): centre distance = gap + 1.26 in.
fn spread_line() -> State {
    let mut st = four_unit_line();
    let r = 0.63 * IN2M;
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    st.positions = vec![
        vec![at(20.0, 20.0), at(21.5, 20.0)],
        vec![at(21.5, 20.0 + 2.9 + 1.26)],
        vec![at(20.0 - 3.1 - 1.26, 20.0)],
        vec![at(20.0, 20.0 - 0.5 - 1.26)],
    ];
    st.radii = Rc::new(vec![vec![r, r], vec![r], vec![r], vec![r]]);
    st.player = vec![1, 1, 1, 0];
    st.alive = vec![2, 1, 1, 1];
    st
}

#[test]
fn only_the_targets_side_within_the_spread_counts() {
    let st = spread_line();
    assert_eq!(blast_neighbours(&st, 0, 3.0), vec![(1, 1)], "2.9 in in, 3.1 in out, the shooter's side never");
    assert_eq!(blast_neighbours(&st, 0, 3.2), vec![(1, 1), (2, 1)]);
    assert_eq!(blast_neighbours(&st, 0, 2.8), vec![]);
}

/// A destroyed unit, or one off the table (in reserve: no models placed), takes no share.
#[test]
fn a_dead_or_reserved_unit_is_no_neighbour() {
    let mut st = spread_line();
    st.alive[1] = 0;
    assert_eq!(blast_neighbours(&st, 0, 3.2), vec![(2, 1)]);
    let mut st = spread_line();
    st.positions[2].clear();
    assert_eq!(blast_neighbours(&st, 0, 3.2), vec![(1, 1)]);
}

/// One spilled hit on a one-model neighbour: a failed save (1) kills it and names it as wounded; a passed save (6) leaves
/// it standing. The hit rolls only the save (fixed hits) and says one line.
#[test]
fn a_spilled_hit_rolls_the_neighbours_save_and_lands() {
    let gun = ShootProfile { name: "Mortar".into(), attacks: 1, count: 1, range: 24, blast: 3, ..Default::default() };
    let statics = vec![UnitStatic { name: "Squad".into(), shoot: vec![gun], ctx: Ctx { quality: 4, defense: 4, models: 1, ..Default::default() }, ..Default::default() }];
    let parts = vec![(0usize, Scratch::default(), Ctx { quality: 4, ..Default::default() })];
    let spill = [crate::dice::BlastSpill { shooter: 0, profile: 0, hits: vec![1] }];
    let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Default::default() };
    for (face, dies) in [(1u8, true), (6, false)] {
        let mut st = four_unit_line();
        let mut shot = ShootResult::default();
        let mut tray = Tray::supplied(vec![vec![face]]);
        let hit = land_blast_spill(&statics, &mut st, &parts, &spill, &[3], (12.0, 12.0), seams, &mut tray, &mut shot);
        assert_eq!(st.alive[3] == 0, dies, "face {face}");
        assert_eq!(hit.iter().map(|h| h.0).collect::<Vec<_>>(), if dies { vec![3] } else { vec![] }, "face {face}");
        assert_eq!(shot.rolls.len(), 1, "only the save: {:?}", shot.rolls);
        assert!(shot.log.iter().any(|l| l.starts_with("Blast: Squad takes 1 hit from Squad's Mortar")), "{:?}", shot.log);
    }
}

/// End to end in `sys` at `epoch`: unit "a" (player 0) holds and fires a Blast(3) gun (3 attacks, Quality 2) at "b" (one
/// model, 12 in east); "bh" (two models) stands 1.5 in behind "b", on b's side; every save is a 6+.
fn blast_game(sys: &str, epoch: u32, seed: i64) -> (State, ShootResult) {
    let mut st = four_unit_line();
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 3] });
    let mut p = st.profiles.list[0].clone();
    p.game_system = sys.into();
    st.profiles = Rc::new(Profiles { list: vec![p; 4], index: HashMap::new() });
    let r = 0.5 * IN2M;
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    st.positions = vec![vec![at(0.0, 0.0)], vec![at(-30.0, 0.0)], vec![at(12.0, 0.0)], vec![at(14.5, 0.0), at(14.5, 1.2)]];
    st.radii = Rc::new(vec![vec![r], vec![r], vec![r], vec![r, r]]);
    st.wounds = vec![vec![1], vec![1], vec![1], vec![1, 1]];
    st.alive = vec![1, 1, 1, 2];
    let gun = ShootProfile { name: "Mortar".into(), attacks: 3, count: 1, range: 24, blast: 3, ..Default::default() };
    let unit = |name: &str, n: i64, shoot: Vec<ShootProfile>| UnitStatic {
        name: name.into(), shoot, model_count: n, wounds_max: vec![1; n as usize],
        ctx: Ctx { quality: 2, defense: 6, models: n, ..Default::default() }, ..Default::default()
    };
    let statics = vec![unit("Gunners", 1, vec![gun]), unit("Spare", 1, vec![]), unit("Target", 1, vec![]), unit("Neighbours", 2, vec![])];
    let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(seed));
    resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), seams, &mut rng, &mut tray).unwrap()
}

/// From the skirmish Blast epoch a gff Blast that hits spills onto the unit behind its target, which rolls its own saves
/// and takes the wounds; one epoch below - and in gf at the epoch - the neighbour is never touched.
#[test]
fn a_skirmish_blast_reaches_the_unit_behind_its_target_from_the_epoch() {
    let e = crate::acts::PENDING_EPOCH_SKIRMISH_BLAST;
    let seed = (0..200).find(|&s| blast_game("gff", e, s).1.log.iter().any(|l| l.starts_with("Blast: Neighbours takes")))
        .expect("a seed where the Mortar hits and spills");
    let (st, shot) = blast_game("gff", e, seed);
    assert!(shot.log.iter().any(|l| l.starts_with("Blast(3): ") && l.contains("on units within reach")), "{:?}", shot.log);
    assert!(st.alive[3] < 2 || shot.log.iter().any(|l| l.starts_with("Blast: Neighbours takes")), "the neighbour rolled");
    for (sys, epoch) in [("gff", e - 1), ("gf", e)] {
        let (st, shot) = blast_game(sys, epoch, seed);
        assert!(!shot.log.iter().any(|l| l.starts_with("Blast: Neighbours")), "{sys} at {epoch}: {:?}", shot.log);
        assert_eq!((st.alive[3], st.wounds[3].clone()), (2, vec![1, 1]), "{sys} at {epoch}: the neighbour is untouched");
    }
}

/// A neighbour the spread leaves at half strength (one of its two models down) tests morale like a shot target: one
/// morale roll signed by it after its saves.
#[test]
fn a_neighbour_at_half_strength_tests_morale() {
    let e = crate::acts::PENDING_EPOCH_SKIRMISH_BLAST;
    let (st, shot) = (0..400).map(|s| blast_game("gff", e, s)).find(|(st, _)| st.alive[3] == 1)
        .expect("a seed where the spread kills one of the two neighbours");
    let own: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| r.owner == "Neighbours").collect();
    assert!(own.iter().any(|r| r.kind != "defense" && r.count == 1), "a morale die for the neighbour: {:?}", shot.rolls);
    assert_eq!(st.alive[3], 1);
}
