//! The Slayer Mark of the gf / aof books (`target: enemy, beneficiary: attackers`, picked in the pre-attack slot) is a once-grant of "Slayer" on the MARKED unit's
//! ledger. The table hands the rule to whoever attacks that unit (`_solo_bridge_granted_flags`), so a shooter that held gets AP(+2) against a Tough(3+) target and says
//! why; `ctx_live_vs` bridged Rending, Furious, Relentless, Shred and Surge from that record and not Slayer. From `EPOCH_94_PARITY_BATCH` it does.
use super::super::*;

use crate::acts::EPOCH_94_PARITY_BATCH as GATE;
use crate::dice::{ShootResult, Tray};

/// The shooter (unit 0, eight Rifle shots, Quality 4) held in `buff_action`; the target (unit 2, three models of three wounds, Defense 4, Tough 3).
fn line() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    statics[0].shoot[0].attacks = 8;
    statics[0].ctx.v36_rules = true;   // the 3.6 spelling of the line (the shooter's own stamp, as `ctx_for` writes it from the epoch)
    statics[2].wounds_max = vec![3, 3, 3];
    statics[2].ctx.tough = 3;
    st.wounds[2] = vec![3, 3, 3];
    (st, statics)
}

/// The record the table keeps on the TARGET after the pick: a once-grant of "Slayer" to its attackers.
fn mark() -> crate::mods::LiveMod {
    crate::mods::LiveMod {
        hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0, range_in: 0,
        grants_rule: Rc::from("Slayer"), scope: Rc::from(""), attackers: true, once: true, name: Rc::from("Slayer Mark"),
    }
}

/// The volley on a supplied tray (eight hits, eight failed saves) at `epoch`: the state, the result and the lines the tray said (the door's lines).
fn run(st: &State, statics: &[UnitStatic], epoch: u32) -> (State, ShootResult, Vec<String>) {
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::supplied(vec![vec![6; 8], vec![1; 8]]);
    let (after, shot) = resolve_stochastic_tray_on_board(
        statics, st, &buff_action(Some("b")), &terrain, Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() },
        &mut crate::rng::GodotRng::new(0), &mut tray,
    )
    .unwrap();
    (after, shot, tray.all_lines().into_iter().map(|l| l.text).collect())
}

/// The target number of the save batch.
fn save_target(r: &ShootResult) -> i64 {
    r.rolls.iter().find(|x| x.kind == "defense").expect("a save batch").target
}

/// RED on main: the record sits on the target's ledger and the shooter's AP stays 0 (saves on 4+).
#[test]
fn a_held_shooter_gets_ap_2_from_the_slayer_mark_on_its_target() {
    let (st, statics) = line();
    let (_, plain, said) = run(&st, &statics, GATE);
    assert_eq!(save_target(&plain), 4, "no mark: the plain save");
    assert!(said.iter().all(|l| !l.starts_with("Slayer:")), "no mark, no line: {said:?}");
    let mut marked = st.clone();
    marked.buffs[2] = vec![mark()];
    let (after, shot, said) = run(&marked, &statics, GATE);
    assert_eq!(save_target(&shot), 6, "Defense 4+ with AP(+2)");
    assert!(said.iter().any(|l| l == "Slayer: AP(+2) because a held"), "said: {said:?}");
    assert!(after.buffs[2].is_empty(), "the exchange spends the once-record");
}

/// Below the gate the record stays unread, as recorded corpora replay it.
#[test]
fn below_the_gate_the_slayer_mark_stays_unread() {
    let (st, statics) = line();
    let mut marked = st.clone();
    marked.buffs[2] = vec![mark()];
    let (_, shot, said) = run(&marked, &statics, GATE - 1);
    assert_eq!(save_target(&shot), 4, "epoch 93: byte-identical");
    assert!(said.iter().all(|l| !l.starts_with("Slayer:")), "said: {said:?}");
}

/// A target below Tough 3 gets nothing from it (the rule's own condition), and the volley says nothing.
#[test]
fn the_grant_needs_a_tough_3_target() {
    let (st, mut statics) = line();
    statics[2].ctx.tough = 2;
    let mut marked = st.clone();
    marked.buffs[2] = vec![mark()];
    let (_, shot, _) = run(&marked, &statics, GATE);
    assert_eq!(save_target(&shot), 4);
}
