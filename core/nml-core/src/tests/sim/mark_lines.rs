//! Plan H: a vs-target Mark says the table's three lines on the core's own path (the pick, the record's activation, the spend), each naming the
//! MARKED unit. The table says them in `_solo_apply_vs_marks`, `_solo_record_spell_mod` and `_solo_spend_records`; the core placed and spent the
//! Mark silently (a trace line only, for two of them), so the Mark carriers stayed refused at the door. Lines only: no die, no state moves.
use super::surge_mark::surge_mark_line;
use super::*;

/// One HOLD volley of the Surge Mark carrier "a" at "b" on a supplied tray (eight hits that all fail their save), the tray's lines.
fn lines_of_a_marked_volley() -> Vec<String> {
    lines_with_faces(vec![vec![4; 8], vec![1; 8], vec![4; 4], vec![4; 4]])
}

/// The same volley with the tray's own faces (the first group is the eight attack dice).
fn lines_with_faces(faces: Vec<Vec<u8>>) -> Vec<String> {
    let (st, mut statics) = surge_mark_line(crate::acts::CURRENT_RULES_EPOCH);
    (statics[0].name, statics[2].name) = ("Att".into(), "Def".into());
    let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
    let mut tray = Tray::supplied(faces);
    let _ = resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray);
    tray.all_lines().into_iter().map(|l| l.text).collect()
}

#[test]
fn a_mark_names_the_pick_the_record_and_the_spend() {
    let lines = lines_of_a_marked_volley();
    let at = |needle: &str| lines.iter().position(|l| l.contains(needle));
    let pick = at("Surge Mark: Att marks Def — friendly units attacking it gain Surge (once)").unwrap_or_else(|| panic!("no pick line: {lines:?}"));
    let active = at("Surge Mark on Def is ACTIVE: grants Surge — applies ONCE").unwrap_or_else(|| panic!("no ACTIVE line: {lines:?}"));
    let spent = at("\"Surge Mark\" on Def is consumed (applies once)").unwrap_or_else(|| panic!("no consumed line: {lines:?}"));
    assert!(pick < active && active < spent, "the table's order: pick, record, spend: {lines:?}");
}

/// The Mark's effect line (`_solo_hits`): two unmodified 6s pay two bonus hits against the marked unit, said between the record and the spend.
#[test]
fn a_surge_mark_names_its_effect_between_the_record_and_the_spend() {
    let lines = lines_with_faces(vec![vec![6, 6, 4, 4, 4, 4, 4, 4], vec![1; 10], vec![4; 4], vec![4; 4]]);
    let at = |needle: &str| lines.iter().position(|l| l.contains(needle));
    let active = at("Surge Mark on Def is ACTIVE").unwrap_or_else(|| panic!("no ACTIVE line: {lines:?}"));
    let effect = at("Surge Mark: +2 hits (unmodified 6s) against the marked Def (once)").unwrap_or_else(|| panic!("no effect line: {lines:?}"));
    let spent = at("\"Surge Mark\" on Def is consumed (applies once)").unwrap_or_else(|| panic!("no consumed line: {lines:?}"));
    assert!(active < effect && effect < spent, "the table's order: record, effect, spend: {lines:?}");
}
