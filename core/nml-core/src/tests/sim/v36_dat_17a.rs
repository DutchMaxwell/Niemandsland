//! Rules 3.6 row DAT-17a tests: a granted Regeneration (the Regeneration Buff, or a spell's "gets Regeneration once")
//! is read by the core from the frozen rules 3.6 epoch and is spent by the first exchange that wounds its holder; owned by lane data.
use super::*;

const EPOCH_72: u32 = crate::acts::EPOCH_72_PLAYTEST_RULES;
const EPOCH_73: u32 = crate::acts::EPOCH_73_V36;

/// The buff line with a four-shot rifle on the shooter and Defense 6+ on the 12" target "b" (unit 2),
/// so the volley wounds it. Seed 13 lands three wounds (the Unstoppable Mark pin uses the same dice).
fn volley_line() -> (State, Vec<UnitStatic>) {
    let (st, mut statics) = buff_line();
    statics[0].shoot = vec![gun("Rifle", 4, 24)];
    statics[2].ctx.defense = 6;
    (st, statics)
}

/// One once-record that grants Regeneration, as the Utility Buff seam and a spell cast both write it.
fn grant_regeneration(state: &mut State, unit: usize) {
    state.buffs[unit].push(mods::LiveMod {
        hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0,
        grants_rule: Rc::from("Regeneration"),
        scope: Rc::from(""), attackers: false, once: true, name: Rc::from("Regeneration Buff"),
    });
}

/// One "a" shoots "b" volley on a fresh tray at the record's own rules epoch.
fn run_at(st: &State, statics: &[UnitStatic], seed: i64, epoch: u32) -> (State, ShootResult) {
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(seed);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        statics, st, &buff_action(Some("b")), &terrain,
        Seams { rules_epoch: epoch, ..Seams::default() }, &mut rng, &mut tray,
    )
    .unwrap()
}

fn wounds_taken(state: &State) -> i64 {
    3 - state.wounds[2].iter().sum::<i64>()
}

/// The grant makes the holder roll the printed 5+ Regeneration from the rules 3.6 epoch; a 72 record, and a
/// holder without the grant, roll nothing.
#[test]
fn a_granted_regeneration_rolls_for_its_holder_from_73() {
    let (mut st, statics) = volley_line();
    let plain = run_at(&st, &statics, 13, EPOCH_73).1;
    assert_eq!(regen_rolls(&plain), 0, "no grant, no regeneration roll");
    grant_regeneration(&mut st, 2);
    let (_, granted) = run_at(&st, &statics, 13, EPOCH_73);
    assert_eq!(regen_rolls(&granted), 1, "the grant rolls one pooled regeneration batch at 5+");
    let (_, old) = run_at(&st, &statics, 13, EPOCH_72);
    assert_eq!(regen_rolls(&old), 0, "epoch 72 replays without reading the grant");
}

/// "Next time the effect would apply": the holder's own attack is not that time, so the grant survives it.
/// Below 73 the old generic spend stays: the attack takes the record.
#[test]
fn the_holders_own_attack_does_not_spend_the_grant() {
    let (mut st, statics) = volley_line();
    grant_regeneration(&mut st, 0);
    let (next, _) = run_at(&st, &statics, 13, EPOCH_73);
    assert_eq!(next.buffs[0].len(), 1, "the shooter keeps its Regeneration grant");
    let (old, _) = run_at(&st, &statics, 13, EPOCH_72);
    assert!(old.buffs[0].is_empty(), "epoch 72 keeps the generic spend byte-exact");
}

/// The first exchange that wounds the holder spends the grant, and the report names the Regeneration Buff.
#[test]
fn an_exchange_that_wounds_the_holder_spends_the_grant_and_logs_it() {
    let (mut st, statics) = volley_line();
    grant_regeneration(&mut st, 2);
    let (next, shot) = run_at(&st, &statics, 13, EPOCH_73);
    assert!(next.wounds[2].iter().sum::<i64>() < 3 || regen_rolls(&shot) == 1, "the fixture wounds the holder");
    assert!(next.buffs[2].is_empty(), "the wounding exchange spends the grant");
    assert!(
        shot.log.iter().any(|l| l.contains("Regeneration Buff") && l.contains("consumed")),
        "rules-must-log: {:?}",
        shot.log
    );
}

/// An exchange that does not wound the holder is not "the time the effect would apply": the grant stays.
#[test]
fn an_exchange_without_wounds_keeps_the_grant() {
    let (mut st, statics) = volley_line();
    grant_regeneration(&mut st, 2);
    let quiet = (0..200)
        .map(|seed| (seed, run_at(&st, &statics, seed, EPOCH_73)))
        .find(|(_, (next, shot))| wounds_taken(next) == 0 && !shot.rolls.is_empty());
    let (seed, (next, shot)) = quiet.expect("some seed in 0..200 shoots without wounding the target");
    assert_eq!(regen_rolls(&shot), 0, "seed {seed}: no wound reached the regeneration step");
    assert_eq!(next.buffs[2].len(), 1, "seed {seed}: the zero-wound exchange leaves the grant alone");
}
