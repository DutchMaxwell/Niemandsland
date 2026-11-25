//! The skirmish vertical rules (3.6 Firefight / AoF: Skirmish p.15): Jumping. `super::*` is activation's own items.
use super::*;
use crate::acts::{EPOCH_94_PARITY_BATCH, PENDING_EPOCH_SKIRMISH_JUMP};
use crate::state::Roster;
use std::rc::Rc;

/// `four_unit_line` with its roster indexed, one static "Squad".
fn squad_line() -> (State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0; 4] });
    (st, vec![UnitStatic { name: "Squad".into(), ..Default::default() }])
}

/// A 4 x 4 board of 3 in cells (x, z -6..6 in): columns x >= 0 at `h` in, no ladder. Unit "a" (`sys`) stands 1 in east of
/// the edge on top; `rules` are written onto its profile.
fn ledge(h: f64, sys: &str, rules: &[&str]) -> (State, Vec<UnitStatic>, Terrain) {
    let (mut st, statics) = squad_line();
    st.positions[0] = vec![[1.0 * INCHES_TO_METERS, h * INCHES_TO_METERS, 1.5 * INCHES_TO_METERS]];
    let p = &mut Rc::get_mut(&mut st.profiles).expect("owned").list[0];
    p.game_system = sys.into();
    p.special_rules = rules.iter().map(|r| r.to_string()).collect();
    let t = crate::terrain::tier_board_for_test(4, 4, (0..16).map(|i| if i % 4 >= 2 { h } else { 0.0 }).collect(), Vec::new());
    (st, statics, t)
}

/// The drop 2 in west, off the ledge, at `epoch`: the check's answer and the jumps it asks for.
fn drop_off(h: f64, sys: &str, rules: &[&str], epoch: u32) -> (Check, Vec<(usize, u32, f64)>) {
    let (st, statics, t) = ledge(h, sys, rules);
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let drop = Drop { mode: ADVANCE, placed: vec![[-INCHES_TO_METERS, 0.0, 1.5 * INCHES_TO_METERS]], ..Default::default() };
    (check_move(&statics, &st, 0, seams, &t, &drop, true), jump_dice_of(&st, 0, seams, &t, &drop))
}

fn cliff() -> Check {
    Check::Refused { reason: "Squad: cliff: no ladder here".into() }
}

fn ok(c: &Check) -> bool {
    matches!(c, Check::Ok { .. })
}

/// GFF/AOFS-E11-02: from the Jumping epoch a 4 in drop is a 4-dice jump whose height does not count toward the move;
/// one epoch below it is the cliff it always was.
#[test]
fn e11_02_a_4_in_drop_is_a_4_dice_jump() {
    let e = PENDING_EPOCH_SKIRMISH_JUMP;
    assert!(e > crate::acts::CURRENT_RULES_EPOCH, "a placeholder no record has played");
    for sys in ["gff", "aofs"] {
        let (c, jumps) = drop_off(4.0, sys, &[], e);
        assert!(ok(&c), "{sys}: {c:?}");
        assert_eq!(jumps, vec![(0, 4, 4.0)], "{sys}");
        let Check::Ok { lines } = c else { unreachable!() };
        assert!(lines.iter().any(|l| l.rule == "jump" && l.text == "Squad: model 1 jumps down 4 in - 4 dice at 2+, the jump does not count toward the move"), "{lines:?}");
        assert_eq!(drop_off(4.0, sys, &[], e - 1), (cliff(), vec![]), "{sys} one epoch below");
    }
    assert_eq!(drop_off(4.0, "gf", &[], e), (cliff(), vec![]), "gf has no drops");
}

/// The jump's height is not counted: 6 in down a ledge plus a 2 in walk fits a 6 in Advance only because the drop is free.
#[test]
fn a_jump_does_not_count_toward_the_move() {
    let (c, jumps) = drop_off(6.0, "gff", &[], PENDING_EPOCH_SKIRMISH_JUMP);
    assert!(ok(&c), "{c:?}");
    assert_eq!(jumps, vec![(0, 6, 6.0)]);
}

/// GFF/AOFS-E14-01: Strider halves the jump dice, rounding up: 5 in -> 3 dice.
#[test]
fn e14_01_strider_halves_jump_dice() {
    let (c, jumps) = drop_off(5.0, "gff", &["Strider"], PENDING_EPOCH_SKIRMISH_JUMP);
    assert!(ok(&c), "{c:?}");
    assert_eq!(jumps, vec![(0, 3, 5.0)]);
}

/// Guards (green before the rule too): a 3 in drop is regular movement with no jump, a 7 in drop is refused, and a Flying
/// unit goes over a 5 in edge without dice.
#[test]
fn e11_01_e11_04_e13_01_guards() {
    let e = PENDING_EPOCH_SKIRMISH_JUMP;
    for epoch in [EPOCH_94_PARITY_BATCH, e] {
        let (c, jumps) = drop_off(3.0, "gff", &[], epoch);
        assert!(ok(&c) && jumps.is_empty(), "3 in at {epoch}: {c:?} {jumps:?}");
        assert_eq!(drop_off(7.0, "gff", &[], epoch).0, cliff(), "7 in at {epoch}");
        let (c, jumps) = drop_off(5.0, "gff", &["Flying"], epoch);
        assert!(ok(&c) && jumps.is_empty(), "Flying at {epoch}: {c:?} {jumps:?}");
    }
}
