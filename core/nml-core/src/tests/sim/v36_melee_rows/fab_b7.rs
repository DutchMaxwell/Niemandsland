//! FAB-B7: a joined hero's Fear(X) counts in the melee result — the chain fights as one unit, so
//! the score of a side carries the host's Fear PLUS every LIVING attached hero's. Below
//! `EPOCH_73_V36` the host-only read stands and every recorded corpus replays.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// Charger host (0) with a joined hero (1) carrying `hero_fear`, defender (2) with Fear 0.
/// `su_left`/`tu_left` are what is LEFT after the strikes, so `before = 10` fixes the tallies:
/// the charger dealt 10 - tu_left, the defender 10 - su_left.
fn duel(hero_fear: i64, su_left: i64, tu_left: i64, rules_epoch: u32) -> i64 {
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: st.roster.keys.clone(),
        index: HashMap::new(),
        profile: vec![0, 1, 2, 0],
    });
    st.wounds[0] = vec![su_left];
    st.wounds[1] = vec![1];
    st.wounds[2] = vec![tu_left];
    st.alive[1] = 1;
    Rc::get_mut(&mut st.attached).unwrap()[0] = vec![1];
    let statics = vec![
        UnitStatic { ctx: Ctx::default(), quality: 6, ..UnitStatic::default() },
        UnitStatic { ctx: Ctx { fear: hero_fear, ..Ctx::default() }, quality: 6, ..UnitStatic::default() },
        UnitStatic { ctx: Ctx::default(), quality: 6, ..UnitStatic::default() },
    ];
    expected_melee_morale(
        &mut st,
        &statics,
        0,
        10,
        2,
        10,
        0,
        0.0,
        0.0,
        Seams { rules_epoch, hero_attach: true, ..Default::default() },
    );
    if st.alive[0] == 0 {
        0
    } else if st.alive[2] == 0 {
        2
    } else {
        99
    }
}

/// The charger took 2 and the defender took 0, and the charger's joined hero carries Fear(2):
/// the hero's Fear counts as dealt, so the charger scores 0 + 2 against the defender's 2 — a tie,
/// nobody tests. With the hero ignored the charger scores 0 and loses, so this pins the chain read.
#[test]
fn a_joined_hero_fear_counts_for_the_chain_at_epoch_73() {
    assert_eq!(duel(2, 8, 10, EPOCH_73_V36), 99, "73: 0 taken + 2 Fear vs 2 taken, a tie");
}

/// Below 73 the host-only read stands: the same duel keeps the defender losing.
#[test]
fn the_hero_fear_stays_out_below_epoch_73() {
    assert_eq!(duel(2, 8, 10, EPOCH_72_PLAYTEST_RULES), 0, "72: the hero's Fear does not join the chain");
}
