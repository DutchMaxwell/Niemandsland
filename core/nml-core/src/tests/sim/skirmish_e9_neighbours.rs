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
        let hit = land_blast_spill(&statics, &mut st, &parts, &spill, &[3], (12.0, 12.0), false, seams, &mut tray, &mut shot);
        assert_eq!(st.alive[3] == 0, dies, "face {face}");
        assert_eq!(hit.iter().map(|h| h.0).collect::<Vec<_>>(), if dies { vec![3] } else { vec![] }, "face {face}");
        assert_eq!(shot.rolls.len(), 1, "only the save: {:?}", shot.rolls);
        assert!(shot.log.iter().any(|l| l.starts_with("Blast: Squad takes 1 hit from Squad's Mortar")), "{:?}", shot.log);
    }
}

/// The Blast board in `sys`: unit "a" (player 0) holds a Blast(3) gun (3 attacks, Quality 2) and casts "Storm" (2 hits,
/// Blast(3)); "b" (one model) stands 12 in east; "bh" (two models) stands 1.5 in behind "b", on b's side; every save is a 6+.
fn blast_board(sys: &str) -> (State, Vec<UnitStatic>) {
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
    st.casts = vec![2, 0, 0, 0];
    let gun = ShootProfile { name: "Mortar".into(), attacks: 3, count: 1, range: 24, blast: 3, ..Default::default() };
    let unit = |name: &str, n: i64, shoot: Vec<ShootProfile>| UnitStatic {
        name: name.into(), shoot, model_count: n, wounds_max: vec![1; n as usize],
        ctx: Ctx { quality: 2, defense: 6, models: n, ..Default::default() }, ..Default::default()
    };
    let storm = crate::rules::Spell {
        name: "Storm".into(), status: "modeled".into(), range_in: 18.0, target_count: 1, effect_kind: "damage".into(),
        effect_hits: 2, weapon_rules: vec!["Blast(3)".into()], ..Default::default()
    };
    let caster = UnitStatic { is_caster: true, spells: vec![storm], casts_per_round: 2, ..unit("Gunners", 1, vec![gun]) };
    (st, vec![caster, unit("Spare", 1, vec![]), unit("Target", 1, vec![]), unit("Neighbours", 2, vec![])])
}

/// End to end in `sys` at `epoch`: "a" fires its Mortar at "b".
fn blast_game(sys: &str, epoch: u32, seed: i64) -> (State, ShootResult) {
    blast_game_in(sys, epoch, seed, false)
}

/// `blast_game` with the neighbour "bh" in cover (`cover`).
fn blast_game_in(sys: &str, epoch: u32, seed: i64, cover: bool) -> (State, ShootResult) {
    let (mut st, statics) = blast_board(sys);
    st.in_cover[3] = cover;
    let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(seed));
    resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), seams, &mut rng, &mut tray).unwrap()
}

/// End to end in `sys` at `epoch`: "a" casts Storm at "b".
fn spell_game(sys: &str, epoch: u32, seed: i64) -> (State, ShootResult) {
    let (mut st, statics) = blast_board(sys);
    let c = crate::activation::CastInput { seq: 0, caster: "a".into(), spell: "Storm".into(), targets: vec!["b".into()], base: 4, threshold: 1, ..Default::default() };
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let (mut tray, mut shot) = (Tray::seeded(seed), ShootResult::default());
    crate::sim::tray_cast(&statics, &mut st, 0, &c, seams, &mut tray, &mut shot);
    (st, shot)
}

/// From the skirmish Blast epoch a gff Blast that hits spills onto the unit behind its target, which rolls its own saves
/// and takes the wounds; one epoch below - and in gf at the epoch - the neighbour is never touched.
#[test]
fn a_skirmish_blast_reaches_the_unit_behind_its_target_from_the_epoch() {
    let e = crate::acts::EPOCH_99_SKIRMISH_BLAST;
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

/// A game recorded at epoch 98 (the live epoch before the bump) replays unchanged: a gff Blast(3) that spills onto the unit
/// behind its target at 99 leaves that unit untouched at 98 - both models standing at full wounds, no neighbour roll.
#[test]
fn a_record_at_epoch_98_leaves_the_neighbour_of_a_gff_blast_untouched() {
    let seed = (0..200).find(|&s| blast_game("gff", 99, s).1.log.iter().any(|l| l.starts_with("Blast: Neighbours takes")))
        .expect("a seed where the Mortar hits and spills at 99");
    let (st, shot) = blast_game("gff", 98, seed);
    assert_eq!((st.alive[3], st.wounds[3].clone()), (2, vec![1, 1]), "98: the neighbour is untouched");
    assert!(!shot.rolls.iter().any(|r| r.owner == "Neighbours"), "98: no neighbour roll: {:?}", shot.rolls);
    let (_, shot) = blast_game("gff", 99, seed);
    assert!(shot.rolls.iter().any(|r| r.owner == "Neighbours"), "99: the neighbour rolls its saves: {:?}", shot.rolls);
}

/// A neighbour the spread leaves at half strength (one of its two models down) tests morale like a shot target: one
/// morale roll signed by it after its saves.
#[test]
fn a_neighbour_at_half_strength_tests_morale() {
    let e = crate::acts::EPOCH_99_SKIRMISH_BLAST;
    let (st, shot) = (0..400).map(|s| blast_game("gff", e, s)).find(|(st, _)| st.alive[3] == 1)
        .expect("a seed where the spread kills one of the two neighbours");
    let own: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| r.owner == "Neighbours").collect();
    assert!(own.iter().any(|r| r.kind != "defense" && r.count == 1), "a morale die for the neighbour: {:?}", shot.rolls);
    assert_eq!(st.alive[3], 1);
}

/// Blast ignores cover, and so do the hits it spills: a neighbour in cover saves at its plain Defense (6+, not 5+), and
/// the skip is said once, naming Blast.
#[test]
fn a_spilled_blast_hit_ignores_the_neighbours_cover() {
    let e = crate::acts::EPOCH_99_SKIRMISH_BLAST;
    let (_, shot) = (0..200).map(|s| blast_game_in("gff", e, s, true))
        .find(|(_, shot)| shot.log.iter().any(|l| l.starts_with("Blast: Neighbours takes")))
        .expect("a seed where the Mortar hits and spills");
    let saves: Vec<i64> = shot.rolls.iter().filter(|r| r.kind == "defense" && r.owner == "Neighbours").map(|r| r.target).collect();
    assert!(!saves.is_empty() && saves.iter().all(|&t| t == 6), "the neighbour saves at 6+, cover skipped: {:?}", shot.rolls);
    assert!(shot.log.iter().any(|l| l.starts_with("Blast: ") && l.contains("cover save is skipped")), "{:?}", shot.log);
}

/// From the skirmish Blast epoch a gff Blast spell spills onto the unit behind its target, which rolls its own saves; one
/// epoch below - and in gf at the epoch - the spell keeps the plain multiply and the neighbour is never touched.
#[test]
fn a_skirmish_blast_spell_reaches_the_unit_behind_its_target_from_the_epoch() {
    let e = crate::acts::EPOCH_99_SKIRMISH_BLAST;
    let spilled = |shot: &ShootResult| shot.log.iter().any(|l| l.starts_with("Blast(3): ") && l.contains("on units within reach"));
    let seed = (0..200).find(|&s| spell_game("gff", e, s).1.rolls.iter().any(|r| r.owner == "Neighbours"))
        .expect("a seed where Storm is cast and spills");
    let (_, shot) = spell_game("gff", e, seed);
    assert!(spilled(&shot), "{:?}", shot.log);
    for (sys, epoch) in [("gff", e - 1), ("gf", e)] {
        let (st, shot) = spell_game(sys, epoch, seed);
        assert!(!spilled(&shot) && !shot.rolls.iter().any(|r| r.owner == "Neighbours"), "{sys} at {epoch}: {:?}", shot.log);
        assert_eq!((st.alive[3], st.wounds[3].clone()), (2, vec![1, 1]), "{sys} at {epoch}: the neighbour is untouched");
    }
}

/// End to end in `sys` at `epoch`: "a" charges "b" (3 in east, saves on 2+) with a Blast(3) hammer (3 attacks); "b" has
/// no weapon and strikes nothing back; "bh" (two models) stands 1.5 in behind "b".
fn melee_game(sys: &str, epoch: u32, seed: i64) -> (State, ShootResult) {
    let (mut st, mut statics) = blast_board(sys);
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    st.positions[2] = vec![at(3.0, 0.0)];
    st.positions[3] = vec![at(5.5, 0.0), at(5.5, 1.2)];
    statics[0].melee = vec![ShootProfile { name: "Hammer".into(), attacks: 3, count: 1, blast: 3, ..Default::default() }];
    statics[2].ctx.defense = 2; // the target mostly saves, so a charge that wounds only the bystander turns up
    let action = Action { kind: CHARGE, unit: "a".into(), dest: Some(at(2.0, 0.0)), shoot: None, charge: Some("b".into()), patient: false, split: None, traced: None, teleport: None };
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(seed));
    resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), seams, &mut rng, &mut tray).unwrap()
}

/// From the skirmish Blast epoch a melee Blast spills onto the unit behind its target too; one epoch below - and in gf
/// at the epoch - the neighbour is never touched.
#[test]
fn a_skirmish_melee_blast_reaches_the_unit_behind_its_target_from_the_epoch() {
    let e = crate::acts::EPOCH_99_SKIRMISH_BLAST;
    let rolled = |shot: &ShootResult| shot.rolls.iter().any(|r| r.owner == "Neighbours");
    let seed = (0..200).find(|&s| rolled(&melee_game("gff", e, s).1)).expect("a seed where the Hammer hits and spills");
    let (_, shot) = melee_game("gff", e, seed);
    assert!(shot.log.iter().any(|l| l.starts_with("Blast(3): ") && l.contains("on units within reach")), "{:?}", shot.log);
    for (sys, epoch) in [("gff", e - 1), ("gf", e)] {
        let (st, shot) = melee_game(sys, epoch, seed);
        assert!(!rolled(&shot), "{sys} at {epoch}: {:?}", shot.log);
        assert_eq!((st.alive[3], st.wounds[3].clone()), (2, vec![1, 1]), "{sys} at {epoch}: the neighbour is untouched");
    }
}

/// Ruling D12: the bystander's wounds never join the melee's tally - a charge that wounds only the neighbour is a tie
/// (no morale die for the target, which struck nothing back) - and a bystander left at half strength tests morale.
#[test]
fn a_melee_blast_bystander_is_no_part_of_the_melee_result() {
    let e = crate::acts::EPOCH_99_SKIRMISH_BLAST;
    let morale = |shot: &ShootResult, who: &str| shot.rolls.iter().any(|r| r.owner == who && r.kind != "defense" && r.count == 1);
    let (_, shot) = (0..400).map(|s| melee_game("gff", e, s))
        .find(|(st, _)| st.alive[2] == 1 && st.alive[3] == 1)
        .expect("a seed where the target survives unwounded and one neighbour falls");
    assert!(morale(&shot, "Neighbours"), "the bystander at half strength tests: {:?}", shot.rolls);
    assert!(!morale(&shot, "Target"), "a tie: the target takes no morale test: {:?}", shot.rolls);
}

/// The strafe is the skirmish spread's deny entry (no Aircraft in either skirmish book): even a gff strafe at the epoch
/// keeps its Blast on the unit it crossed - a unit 1 in behind that unit is never touched.
#[test]
fn a_strafe_never_spreads_its_blast() {
    let (mut st, mut statics) = super::strafing::strafe_line();
    let keys: Vec<String> = vec!["a".into(), "b".into(), "c".into()];
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 1] });
    let mut list = st.profiles.list.clone();
    for p in list.iter_mut() {
        p.game_system = "gff".into();
    }
    st.profiles = Rc::new(Profiles { list, index: HashMap::new() });
    st.player = vec![0, 1, 1];
    st.alive = vec![1, 1, 1];
    st.attached = Rc::new(vec![vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None]);
    st.positions.push(vec![[5.0 * IN2M, 0.0, 3.0 * IN2M]]);
    st.wounds.push(vec![1]);
    Rc::make_mut(&mut st.radii).push(vec![IN2M]);
    statics[0].strafe_shoot[0].blast = 3;
    let seams = Seams { rules_epoch: crate::acts::EPOCH_99_SKIRMISH_BLAST, ..Seams::default() };
    for seed in 0..40 {
        let (next, shot) = resolve_stochastic_tray_on_board(&statics, &st, &advance_to(12.0), &crate::terrain::Terrain::default(),
            seams, &mut GodotRng::new(0), &mut Tray::seeded(seed)).unwrap();
        assert!(shot.rolls.iter().any(|r| r.owner == "Strafer"), "seed {seed}: the strafe fired");
        assert!(!shot.log.iter().any(|l| l.contains("on units within reach")), "seed {seed}: {:?}", shot.log);
        assert_eq!((next.alive[2], next.wounds[2].clone()), (1, vec![1]), "seed {seed}: the unit behind is untouched");
    }
}

/// Ruling D15: a Blast bystander the spilled hits shook "was attacked", so the attacker may push it (gff, at the push
/// epoch, which lies past the Blast one). The neighbours test on 6+ here, so a lost model usually shakes them.
#[test]
fn a_blast_bystander_shaken_by_the_spill_may_be_pushed() {
    let e = crate::acts::EPOCH_101_SKIRMISH_PUSH;
    let game = |seed: i64| {
        let (st, mut statics) = blast_board("gff");
        statics[3].ctx.quality = 6;
        let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None, traced: None, teleport: None };
        let mut tray = Tray::seeded(seed);
        tray.offer_push(Some(crate::activation::PushInput { target: "bh".into(), model: 0, to: st.positions[3][0] }));
        resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), Seams { rules_epoch: e, tray_exact: true, ..Seams::default() }, &mut GodotRng::new(0), &mut tray).unwrap()
    };
    let (st, shot) = (0..400).map(game).find(|(st, _)| st.shaken[3] && st.alive[3] > 0).expect("a seed where the spill shakes the neighbours");
    assert!(shot.log.iter().any(|l| l.starts_with("Push: Gunners rolls") && l.contains("Neighbours")), "the push holds and rolls: {:?} {:?}", st.shaken, shot.log);
}

/// Ruling D15, melee: the charged target that loses the fight and turns Shaken was attacked; the push holds.
#[test]
fn a_charged_target_shaken_by_the_melee_may_be_pushed() {
    let e = crate::acts::EPOCH_101_SKIRMISH_PUSH;
    let game = |seed: i64| {
        let (mut st, mut statics) = blast_board("gff");
        let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
        st.positions[2] = vec![at(3.0, 0.0)];
        st.positions[3] = vec![at(30.0, 30.0), at(30.0, 31.2)];
        st.wounds[2] = vec![3];
        statics[2].ctx.quality = 6;
        statics[0].melee = vec![ShootProfile { name: "Blade".into(), attacks: 3, count: 1, ..Default::default() }];
        let action = Action { kind: CHARGE, unit: "a".into(), dest: Some(at(2.0, 0.0)), shoot: None, charge: Some("b".into()), patient: false, split: None, traced: None, teleport: None };
        let mut tray = Tray::seeded(seed);
        tray.offer_push(Some(crate::activation::PushInput { target: "b".into(), model: 0, to: at(4.0, 0.0) }));
        resolve_stochastic_tray_on_board(&statics, &st, &action, &crate::terrain::Terrain::default(), Seams { rules_epoch: e, tray_exact: true, ..Seams::default() }, &mut GodotRng::new(0), &mut tray).unwrap()
    };
    let (_, shot) = (0..400).map(game).find(|(st, _)| st.shaken[2] && st.alive[2] > 0).expect("a seed where the charge shakes the target");
    assert!(shot.log.iter().any(|l| l.starts_with("Push: Gunners rolls") && l.contains("Target")), "the push holds and rolls: {:?}", shot.log);
}
