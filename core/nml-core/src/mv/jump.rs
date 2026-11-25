//! Jumping in the Firefight and AoF: Skirmish books (p.15) as pure numbers: a drop of up to 3 in is regular movement, a
//! drop of up to 6 in is a jump with one die per inch, a longer drop is refused; a gap of 1 in is stepped over, a wider
//! gap is a jump with one die per inch. Every die must show 2+ (a 1 fails the jump). Flying passes every jump without
//! dice; Strider halves the dice, rounding up. An inch begun counts as a whole inch. Not wired yet.

/// A drop this deep or less is regular movement.
pub const FREE_DROP_IN: f64 = 3.0;
/// A drop deeper than this is refused.
pub const MAX_DROP_IN: f64 = 6.0;
/// A gap this wide or less is stepped over.
pub const FREE_GAP_IN: f64 = 1.0;
/// Every jump die must show this or more.
pub const JUMP_TARGET: u8 = 2;
/// Measuring slack, so a tier height stored as 3.0000001 in is still 3 in.
const EPS_IN: f64 = 1e-6;

/// What a drop (down a ledge) or a gap (across open ground between two heights) asks of a model.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JumpKind {
    /// Regular movement, no roll.
    Free,
    /// A jump with this many dice before Flying or Strider.
    Jump { dice: u32 },
    /// The model may not go there.
    Refused,
}

/// Whole inches, an inch begun counting as one.
fn inches_up(d_in: f64) -> u32 {
    (d_in - EPS_IN).ceil().max(0.0) as u32
}

/// A drop of `drop_in` down a ledge: free up to 3 in, a jump up to 6 in, refused beyond.
pub fn drop_kind(drop_in: f64) -> JumpKind {
    if drop_in <= FREE_DROP_IN + EPS_IN {
        JumpKind::Free
    } else if drop_in <= MAX_DROP_IN + EPS_IN {
        JumpKind::Jump { dice: inches_up(drop_in) }
    } else {
        JumpKind::Refused
    }
}

/// A gap of `gap_in`: free up to 1 in, else a jump with one die per inch (the book names no maximum).
pub fn gap_kind(gap_in: f64) -> JumpKind {
    if gap_in <= FREE_GAP_IN + EPS_IN {
        JumpKind::Free
    } else {
        JumpKind::Jump { dice: inches_up(gap_in) }
    }
}

/// The dice a model really rolls for a jump of `dice`: none with Flying, half rounded up with Strider.
pub fn jump_dice(dice: u32, flying: bool, strider: bool) -> u32 {
    if flying {
        0
    } else if strider {
        dice.div_ceil(2)
    } else {
        dice
    }
}

/// A jump passes when every die shows 2+.
pub fn jump_passes(faces: &[u8]) -> bool {
    faces.iter().all(|&f| f >= JUMP_TARGET)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Book: a 3 in drop is movement, a 4 in drop is a 4-dice jump, a 7 in drop is refused; 6 in is still a jump.
    #[test]
    fn drops_are_free_to_3_in_a_jump_to_6_in_and_refused_beyond() {
        assert_eq!(drop_kind(3.0), JumpKind::Free);
        assert_eq!(drop_kind(3.0 + 1e-9), JumpKind::Free, "measuring slack");
        assert_eq!(drop_kind(4.0), JumpKind::Jump { dice: 4 });
        assert_eq!(drop_kind(4.5), JumpKind::Jump { dice: 5 }, "an inch begun counts");
        assert_eq!(drop_kind(6.0), JumpKind::Jump { dice: 6 });
        assert_eq!(drop_kind(7.0), JumpKind::Refused);
    }

    /// Book: a 1 in gap is stepped over, a 2 in gap is a 2-dice jump.
    #[test]
    fn gaps_are_free_to_1_in_and_one_die_per_inch_beyond() {
        assert_eq!(gap_kind(1.0), JumpKind::Free);
        assert_eq!(gap_kind(2.0), JumpKind::Jump { dice: 2 });
        assert_eq!(gap_kind(1.2), JumpKind::Jump { dice: 2 });
    }

    /// Book: Strider on a 5 in drop rolls 3 dice; Flying rolls none.
    #[test]
    fn strider_halves_rounding_up_and_flying_rolls_nothing() {
        assert_eq!(jump_dice(5, false, true), 3);
        assert_eq!(jump_dice(4, false, true), 2);
        assert_eq!(jump_dice(4, false, false), 4);
        assert_eq!(jump_dice(4, true, true), 0);
    }

    /// Book: 2, 3, 5, 6 passes; 2, 1, 4, 5 fails; no dice passes.
    #[test]
    fn a_jump_passes_only_without_a_1() {
        assert!(jump_passes(&[2, 3, 5, 6]));
        assert!(jump_passes(&[3, 2, 6]));
        assert!(!jump_passes(&[2, 1, 4, 5]));
        assert!(jump_passes(&[]));
    }
}
