use super::*;
use super::melee_landing_gaps::two_unit_melee;

    // ---- Melee Deadly (lane melee95): the wounds left once the chain is dead roll no ignore dice, as at the table ----

    /// A Deadly(3) strike with two unsaved wounds at ONE Tough(3) model with a 6+ ignore rule (Cursed Undead, Regeneration): the first wound's
    /// three ignore dice and its landing kill the model, so the table (`_solo_land_deadly_wounds`: empty pick, break) rolls no dice for the second.
    /// Returns the ignore rolls (three dice at 6+) the strike drew at `epoch`.
    fn ignore_rolls(epoch: u32) -> usize {
        let (mut statics, mut st) = two_unit_melee(1, 1, 3);
        statics[0].melee[0] = ShootProfile { name: "Spear".into(), attacks: 2, count: 1, range: 0, deadly: 3, ..Default::default() };
        statics[0].ctx.rules_epoch = epoch;
        let c = &mut statics[1].ctx;
        (c.rules_epoch, c.regeneration, c.regen_target, c.playtest_rules) = (epoch, true, 6, true);
        let mut faces = vec![vec![4, 4], vec![1, 1], vec![1, 1, 1]];
        faces.extend((0..24).map(|_| vec![1u8; 24]));
        let mut tray = Tray::supplied(faces);
        let mut shot = ShootResult::default();
        let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
        strike_phase(&statics, &mut st, 0, 1, true, 7.0, seams, &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
        assert_eq!(st.alive[1], 0, "the Deadly wound killed the model");
        shot.rolls.iter().filter(|r| r.target == 6 && r.count == 3).count()
    }

    /// RED at the pending epoch: the core threw the second wound's three dice as well (2 rolls against the table's 1). Below it nothing moves.
    #[test]
    fn a_dead_chain_gets_no_more_ignore_dice_from_the_deadly_wounds_left() {
        assert_eq!(ignore_rolls(crate::acts::PENDING_EPOCH_DEADLY_STOPS), 1, "94: the second wound is dropped, no dice");
        assert_eq!(ignore_rolls(crate::acts::CURRENT_RULES_EPOCH), 2, "below the epoch the old fold rolls both wounds' dice");
    }
