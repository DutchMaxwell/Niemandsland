//! Rules 3.6 row MOR-11 tests (sim module); owned by lane morale.

use super::super::*;
use super::four_unit_line;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::state::Roster;
use std::collections::HashMap;
use std::rc::Rc;

// MOR-11: the AI's ESTIMATE agrees with the resolver. `morale_fails_expected` reads its Quality
// through `morale_quality`; from EPOCH_73_V36 a nearby Tough(9)+ Hero lifts it the same way the
// table test does. Below 73 the estimate keeps the unit's own Quality, byte for byte.

/// Unit 0 = a Q4 squad, unit 1 = its friendly Q3 Tough(9) Hero at a 5" base-edge gap (1" bases,
/// so the centres sit 7" apart). `tweak` bends one thing per test; the bool is the estimate.
fn aura_estimate(epoch: u32, tweak: impl FnOnce(&mut State, &mut Vec<UnitStatic>)) -> bool {
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: st.roster.keys.clone(),
        index: HashMap::new(),
        profile: vec![0, 1, 0, 0],
    });
    st.attached = Rc::new(vec![vec![]; 4]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.positions[1] = vec![[7.0 * IN2M, 0.0, 0.0]];
    let mut statics = vec![
        UnitStatic {
            name: "Squad".into(),
            quality: 4,
            ctx: Ctx { quality: 4, ..Ctx::default() },
            model_count: 1,
            wounds_max: vec![1],
            ..UnitStatic::default()
        },
        UnitStatic {
            name: "Warlord".into(),
            quality: 3,
            is_hero: true,
            ctx: Ctx { quality: 3, tough: 9, ..Ctx::default() },
            model_count: 1,
            wounds_max: vec![1],
            ..UnitStatic::default()
        },
    ];
    tweak(&mut st, &mut statics);
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Default::default() };
    morale_fails_expected(&st, &statics, 0, seams)
}

/// RED on origin/main: the estimate keeps its own Q4 and calls the test a fail even though a Q3
/// Tough(9)+ Hero stands inside 6".
#[test]
fn a_q4_unit_within_six_inches_of_a_q3_tough_nine_hero_passes_the_estimate_at_73() {
    assert!(!aura_estimate(EPOCH_73_V36, |_, _| {}), "the Hero's Q3 lets the estimate pass");
}

/// Control: below 73 the same state keeps the unit's own Q4 estimate (today's behaviour).
#[test]
fn the_same_unit_keeps_its_own_q4_estimate_at_72() {
    assert!(aura_estimate(EPOCH_72_PLAYTEST_RULES, |_, _| {}));
}

/// Control: the aura ends past six inches (base edge to base edge).
#[test]
fn a_hero_seven_inches_away_does_not_lift_the_estimate() {
    assert!(aura_estimate(EPOCH_73_V36, |st, _| {
        st.positions[1] = vec![[9.0 * IN2M, 0.0, 0.0]];
    }));
}

/// Control: a Shaken Hero lends nothing to the estimate either.
#[test]
fn a_shaken_hero_does_not_lift_the_estimate() {
    assert!(aura_estimate(EPOCH_73_V36, |st, _| st.shaken[1] = true));
}

/// Control: a joined Hero keeps the old joined-hero read (EPOCH_65) — the strongest Quality of the
/// joined unit, here the Hero's Q3, at BOTH epochs. The aura never adds or changes that read.
#[test]
fn a_joined_hero_keeps_the_old_joined_hero_read() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        assert!(!aura_estimate(epoch, |st, _| {
            st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
            st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        }), "joined Hero read at epoch {epoch}");
    }
}
