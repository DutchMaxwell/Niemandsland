use super::*;

#[test]
fn propose_order_is_deterministic_and_the_seed_moves_only_the_tail() {
    let reach: Vec<u16> = (0..100u16).collect();
    let hand = vec![30u16, 31];
    let a = propose_order(&reach, &hand, 7, 72);
    assert_eq!(a, propose_order(&reach, &hand, 7, 72), "same seed -> same order");
    let b = propose_order(&reach, &hand, 8, 72);
    let ring = |v: &[(u16, u8)]| v.iter().take_while(|x| x.1 == 0).count();
    assert!(ring(&a) > 0, "the ring shells come first");
    assert_eq!(ring(&a), ring(&b), "the seed does not move the rings");
    assert_ne!(a, b, "the seed moves the uniform tail");
    // the order is a permutation of the reachable set MINUS the hand cells (already in the menu)
    let mut sa: Vec<u16> = a.iter().map(|x| x.0).collect();
    sa.sort_unstable();
    let mut expect: Vec<u16> = reach.iter().copied().filter(|c| !hand.contains(c)).collect();
    expect.sort_unstable();
    assert_eq!(sa, expect);
}

#[test]
fn grid_seed_is_stable_and_position_sensitive() {
    let st = crate::sim::tests::four_unit_line();
    let s = grid_seed(&st, 0, 1);
    assert_eq!(s, grid_seed(&st, 0, 1));
    assert_ne!(s, grid_seed(&st, 2, 1));
    assert_ne!(s, grid_seed(&st, 0, 2));
}
