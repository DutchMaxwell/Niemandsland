use super::*;

    /// Audit 2026-09-13 §2.4 — Sturdy + Sturdy Boost must be ONE +1: the Boost
    /// replaces the base rule's over-9" condition with "always", so the two
    /// readings MAX, never stack. Today the dice fold subtracts in sequence —
    /// `shielded_defense` then `guarded_defense` (dice.rs:989-990) — and the
    /// Dwarf Guilds board from the audit plays 2+ where the book says 3+.
    ///
    /// RED on the volley fold: Defense 4+, Sturdy + Sturdy Boost, AP(1) from
    /// 12" — the save target is 4+ (one +1), not 3+ (two).
    #[test]
    fn sturdy_boost_replaces_the_distance_gate_instead_of_stacking_with_it() {
        let def = Ctx {
            shielded: true,
            shielded_alias: crate::unit::ShieldedAlias::SturdyBoost,
            guarded: true,
            ..defender(4, 5)
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ap_rifle(64)], &[0], &[64], &shooter(4), &def, 12.0, &mut tray,
        );
        assert_eq!(
            out.rolls[1].target, 4,
            "book: the Boost removes the gate, the +1 fires once — 3+ vs AP(1) saves on 4+"
        );
    }

    /// Under 9" the gate never fired, so base and Boost already agreed — the
    /// fix must not move the close-range reading.
    #[test]
    fn under_nine_inches_base_and_boost_already_agree() {
        let def = Ctx {
            shielded: true,
            shielded_alias: crate::unit::ShieldedAlias::SturdyBoost,
            guarded: true,
            ..defender(4, 5)
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ap_rifle(64)], &[0], &[64], &shooter(4), &def, 9.0, &mut tray,
        );
        assert_eq!(out.rolls[1].target, 4, "one +1 at close range too");
    }