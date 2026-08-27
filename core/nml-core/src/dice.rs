//! NML-1073 M5 D1-B3 — the table's DICE TRAY as a pure stream.
//!
//! The shipped game rolls every combat die through `_solo_tray_roll`
//! (main.gd:7126-7180). In batch mode — the only reproducible one
//! (arena_match.gd:253) — that is exactly this, main.gd:7152-7159:
//!
//! ```text
//! for _di in maxi(1, count):
//!     _inst.append(_tray_rng.randi_range(1, 6))
//! ```
//!
//! TWO things a naive port gets wrong, both pinned by the tests below:
//!
//!   1. `maxi(1, count)` — a ZERO-die roll STILL BURNS ONE DRAW. Skip it and
//!      the whole stream shifts from the first empty volley onward, and every
//!      activation after it is a different game.
//!   2. The tray has its OWN generator. `seed_tray_rng` (main.gd:7120-7121) is
//!      a plain `_tray_rng.seed = seed_value`, i.e. `GodotRng::new(seed)`, and
//!      the arena hands it `_dice_seed` AFTER deployment (arena_match.gd:478),
//!      where `_dice_seed` defaults to the game seed (arena_match.gd:984-985).
//!      Deployment and the roll-off draw from OTHER generators — see the
//!      stream split in `selfplay.py`.
//!
//! Nothing here is new randomness: `GodotRng` is the fixture-proven Godot 4.6
//! `RandomPCG` twin (GATE R, 6003/6003), and a tray face is one
//! `randi_range(1, 6)` on it.

use crate::rng::GodotRng;

/// One dice tray: the generator `seed_tray_rng` seeds, and nothing else.
#[derive(Debug, Clone, Copy)]
pub struct Tray {
    rng: GodotRng,
}

impl Tray {
    /// `main.seed_tray_rng(dice_seed)` — `RandomNumberGenerator.seed = seed`.
    ///
    /// The seed is `i64`, not `u64`, because that is what GDScript hands the
    /// engine and what `GodotRng::new` mirrors; a negative seed must land on
    /// the same stream on both sides.
    pub fn seeded(seed: i64) -> Tray {
        Tray { rng: GodotRng::new(seed) }
    }

    /// A tray that continues a generator already in flight — how a replay
    /// reaches a recorded position in the stream.
    pub fn from_rng(rng: GodotRng) -> Tray {
        Tray { rng }
    }

    /// Re-seeds in place, as a second `seed_tray_rng` call would.
    pub fn seed(&mut self, seed: i64) {
        self.rng.seed(seed);
    }

    /// One roll: `maxi(1, count)` faces of `randi_range(1, 6)`, in draw order.
    /// `count == 0` returns ONE face — the die the table burns and reads as
    /// nothing. Callers that asked for zero dice must ignore the value, not
    /// the draw.
    pub fn roll(&mut self, count: usize) -> Vec<u8> {
        (0..count.max(1)).map(|_| self.rng.randi_range(1, 6) as u8).collect()
    }

    /// `rng.state` — the cheap replay checkpoint GATE R already compares.
    pub fn state_i64(&self) -> i64 {
        self.rng.state_i64()
    }
}

/// Successes in a roll — `DiceRules.count_successes(faces, target, 0)`
/// (dice_rules.gd:55-71), the OPR quality/defense test:
/// a 6 ALWAYS succeeds, a 1 ALWAYS fails, anything else needs `>= target`.
///
/// The modifier is fixed at 0 on purpose: `_solo_tray_roll` sets
/// `_success_modifier = 0` (main.gd:7143) for every scripted roll, so an AI
/// tray roll is never modifier-counted — the modified threshold is baked into
/// `target` by the caller before the dice leave the cup.
pub fn faces_to_hits(faces: &[u8], target: u8) -> usize {
    if target == 0 {
        return 0; // `TARGET_NONE` — dice_rules.gd:57, nothing is being tested.
    }
    faces.iter().filter(|&&f| f >= 6 || (f > 1 && f >= target)).count()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// THE TRAP. Two trays on one seed: burning a zero-die roll must cost
    /// exactly one draw, so the first tray's next three faces are the second's
    /// faces 2..4.
    #[test]
    fn a_zero_die_roll_burns_exactly_one_draw() {
        let mut burned = Tray::seeded(27);
        let mut straight = Tray::seeded(27);
        let zero = burned.roll(0);
        assert_eq!(zero.len(), 1, "maxi(1, count): a zero-die roll still rolls one");
        assert_eq!(burned.roll(3), straight.roll(4)[1..].to_vec());
        assert_eq!(burned.state_i64(), straight.state_i64(), "and only one");
    }

    /// RED PROOF for the rule above: the same two trays with `count` taken
    /// literally. The zero-die roll then costs nothing and every later face is
    /// off by one draw.
    #[test]
    fn red_proof_dropping_the_max_1_rule_shifts_the_stream() {
        let mut naive = GodotRng::new(27);
        let zero_count = 0usize; // `count` taken literally, without `maxi(1, ..)`
        let naive_zero: Vec<u8> =
            (0..zero_count).map(|_| naive.randi_range(1, 6) as u8).collect();
        assert!(naive_zero.is_empty(), "the naive form draws nothing for count 0");
        let after: Vec<u8> = (0..3).map(|_| naive.randi_range(1, 6) as u8).collect();
        let first_four = Tray::seeded(27).roll(4);
        assert_eq!(after, first_four[..3].to_vec(), "the naive form reads faces 1..3");
        assert_ne!(after, first_four[1..].to_vec(), "the table reads faces 2..4 — a shift");
    }

    #[test]
    fn every_face_is_a_d6_face_and_the_stream_is_deterministic() {
        let mut a = Tray::seeded(1_099_511_627_783);
        let mut b = Tray::seeded(1_099_511_627_783);
        let fa = a.roll(600);
        assert_eq!(fa.len(), 600);
        assert!(fa.iter().all(|&f| (1..=6).contains(&f)), "faces outside 1..=6");
        assert_eq!(fa, b.roll(600), "same seed, same faces");
        // Uniform enough that a broken mapping (e.g. `% 6` without the +1)
        // cannot hide: all six faces must actually appear.
        for face in 1u8..=6 {
            assert!(fa.contains(&face), "face {face} never came up in 600 rolls");
        }
    }

    /// A tray is `randi_range(1, 6)` on the twin and nothing else — one draw
    /// per die, in order, sharing the generator's state.
    #[test]
    fn the_tray_is_randi_range_1_6_on_the_twin() {
        let mut tray = Tray::seeded(12345);
        let mut rng = GodotRng::new(12345);
        let faces = tray.roll(64);
        let want: Vec<u8> = (0..64).map(|_| rng.randi_range(1, 6) as u8).collect();
        assert_eq!(faces, want);
        assert_eq!(tray.state_i64(), rng.state_i64());
    }

    /// `DiceRules.is_success` in full: the natural 6 beats an impossible
    /// target, the natural 1 fails an automatic one, and `TARGET_NONE` counts
    /// nothing.
    #[test]
    fn faces_to_hits_follows_the_natural_6_and_natural_1_rules() {
        let faces = [1u8, 2, 3, 4, 5, 6];
        assert_eq!(faces_to_hits(&faces, 4), 3, "4, 5, 6");
        assert_eq!(faces_to_hits(&faces, 2), 5, "everything but the 1");
        assert_eq!(faces_to_hits(&faces, 6), 1, "only the 6");
        assert_eq!(faces_to_hits(&faces, 7), 1, "the natural 6 still succeeds");
        assert_eq!(faces_to_hits(&faces, 1), 5, "the natural 1 still fails");
        assert_eq!(faces_to_hits(&faces, 0), 0, "TARGET_NONE tests nothing");
        assert_eq!(faces_to_hits(&[], 4), 0);
    }
}
