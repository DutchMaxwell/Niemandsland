use super::*;

    // ------------------------------------- D1-B5a: the melee / impact order ---

    /// THE ORDER, and why it is a gate and not a preference: the table rolls the
    /// charge's Impact dice BEFORE the strikes (main.gd:8067 then :8081). Both
    /// phases draw from ONE tray, so swapping them hands the strikes the dice
    /// that belong to Impact — every face from the first roll on is a different
    /// number, and a recorded activation stops replaying.
    #[test]
    fn impact_is_drawn_before_the_strikes_and_swapping_them_desyncs_the_faces() {
        let p = [blade(3)];
        let att = Ctx { quality: 4, impact: 2, models: 2, ..Default::default() };
        let def = defender(5, 4);
        let pools = impact_pools(&att, &def);
        assert_eq!(pools[0], (4, 0), "Impact(2) x 2 models = 4 dice, no AP");
        // The table's order.
        let mut tray = Tray::seeded(27);
        let mut table = ShootResult::default();
        table.absorb(resolve_impact_pool_with_tray(
            pools[0].0, pools[0].1, "Striker", &def, "Target", &mut tray));
        table.absorb(resolve_melee_with_tray(
            &[striker(&p, &[0], &[3], &att)], &def, "Target", true, true, true, &mut tray));
        assert_eq!(table.rolls[0].count, 4);
        assert_eq!(table.rolls[0].target, IMPACT_HIT_TARGET);
        // RED PROOF: the same two phases, strikes first.
        let mut tray = Tray::seeded(27);
        let mut swapped = ShootResult::default();
        swapped.absorb(resolve_melee_with_tray(
            &[striker(&p, &[0], &[3], &att)], &def, "Target", true, true, true, &mut tray));
        swapped.absorb(resolve_impact_pool_with_tray(
            pools[0].0, pools[0].1, "Striker", &def, "Target", &mut tray));
        assert_ne!(faces_of(&table), faces_of(&swapped), "swapping the phases must move the faces");
        assert_ne!(table.rolls[0].faces, swapped.rolls[0].faces,
                   "and it must part on the very FIRST roll, not somewhere downstream");
    }

    /// Ravage is not a weapon: X dice per alive bearer, each 6+ a DIRECT wound
    /// with no hit roll and no save (main.gd:5983-6002), drawn BEFORE the
    /// strikes — so no save batch may ever follow it.
    #[test]
    fn ravage_wounds_directly_and_is_drawn_before_the_strikes() {
        let p = [blade(2)];
        let att = Ctx { quality: 4, ravage: 1, models: 3, ..Default::default() };
        let mut tray = Tray::seeded(9);
        let want = Tray::seeded(9).roll(3);
        let out = resolve_melee_with_tray(
            &[striker(&p, &[0], &[2], &att)], &defender(4, 4), "Target", false, true, true, &mut tray);
        assert_eq!(out.rolls[0].count, 3, "Ravage(1) x 3 alive models");
        assert_eq!(out.rolls[0].target, RAVAGE_WOUND_TARGET);
        assert_eq!(out.rolls[0].faces, want, "Ravage draws first");
        assert_eq!(out.rolls[1].kind, "attack", "the strike follows — no save batch between");
        assert_eq!(out.rolls[1].count, 2);
    }

    /// FATIGUE IS NOT A MODIFIER (main.gd:6062): a fatigued striker hits on an
    /// unmodified 6 and Unpredictable's +1 does not reach it. Applying the bonus
    /// on top turns the 6 into a 5 and the recorded target stops matching.
    #[test]
    fn fatigue_is_a_flat_six_that_no_bonus_reaches() {
        let mut p = blade(1);
        p.reliable = true;
        p.thrust = true;
        let att = Ctx { quality: 5, models: 1, ..Default::default() };
        assert_eq!(melee_hit_target(&p, &att, &defender(4, 1), true, 0), 2,
                   "Reliable 2+, and Thrust cannot go below the 2+ floor");
        let tired = Ctx { fatigued: true, ..att };
        assert_eq!(melee_hit_target(&p, &tired, &defender(4, 1), true, 0), 6);
        assert_eq!(melee_hit_target(&p, &tired, &defender(4, 1), true, 1), 6,
                   "Unpredictable's +1 must not turn a fatigued 6 into a 5");
    }

    /// ONE CLAMP, ON THE SUM (main.gd:6053-6055). Quality 6 into an Evasive
    /// defender with Unpredictable's +1 is `-1 + 1 = 0` -> a 6+. Clamping the
    /// defender's modifier alone and folding the +1 in through a second
    /// `modified_hit_target` clamps twice and answers 5+.
    #[test]
    fn unstoppable_clamps_the_summed_modifier_once() {
        let mut p = blade(1);
        p.unstoppable = true;
        let att = Ctx { quality: 6, models: 1, ..Default::default() };
        let evasive = Ctx { evasive: true, ..defender(4, 1) };
        assert_eq!(melee_hit_target(&p, &att, &evasive, false, 1), 6,
                   "the sum is 0, so the target stays the unmodified Quality");
        // RED: the two-step form the port used before.
        let two_step = modified_hit_target(
            modified_hit_target(6, { let m = -1i64; if m < 0 { 0 } else { m } }), 1);
        assert_eq!(two_step, 5, "clamping twice is one target too generous");
        let plain = Ctx { quality: 6, models: 1, ..Default::default() };
        assert_eq!(melee_hit_target(&blade(1), &plain, &evasive, false, 0), 6,
                   "without Unstoppable the -1 still cannot push past the 6+ ceiling");
    }

    /// D5 — the Heavy pool is its OWN call, so a caller that just watched the
    /// first pool wipe the defender can stop (main.gd:6304). A single-call form
    /// would roll it regardless and shift every later face.
    #[test]
    fn each_impact_pool_is_its_own_call_so_the_caller_can_stop() {
        let att = Ctx { impact: 1, heavy_impact: 2, models: 3, ..Default::default() };
        let pools = impact_pools(&att, &defender(4, 5));
        assert_eq!(pools, [(3, 0), (6, HEAVY_IMPACT_AP)]);
        let tired = Ctx { fatigued: true, ..att };
        assert_eq!(impact_pools(&tired, &defender(4, 5)), [(0, 0), (0, 0)],
                   "a fatigued charger rolls no Impact at all (p.13)");
        // Stopping after the first pool must leave the tray exactly where that
        // pool left it — the second pool's dice are never drawn.
        let mut one = Tray::seeded(5);
        let r = resolve_impact_pool_with_tray(pools[0].0, pools[0].1, "A", &defender(4, 5), "D", &mut one);
        let mut same = Tray::seeded(5);
        same.roll(3);
        assert_eq!(r.rolls[0].count, 3);
        if r.rolls.len() == 1 {
            assert_eq!(one.state_i64(), same.state_i64(), "no hits, no save batch, no extra draw");
        }
    }

    /// D6 — the melee tally is the PRE-Regeneration count (main.gd:6001/:6113),
    /// while the wounds that LAND are the post-Regeneration ones. Comparing the
    /// landed number lets a Regeneration roll decide who tests morale.
    #[test]
    fn the_melee_tally_is_pre_regeneration_and_the_landed_wounds_are_not() {
        let p = [blade(6)];
        let att = Ctx { quality: 2, models: 6, ..Default::default() };
        // Defense 6+ so nearly everything gets through, Regeneration on 2+ so
        // nearly everything is then ignored: the two numbers cannot coincide.
        let def = Ctx { regeneration: true, regen_target: 2, ..defender(6, 6) };
        let mut tray = Tray::seeded(4);
        let out = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &att)], &def, "Target", false, true, true, &mut tray);
        assert!(out.caused > 0, "the strike caused wounds: {:?}", out.rolls);
        assert!(out.wounds < out.caused, "Regeneration ignored some: {} vs {}", out.wounds, out.caused);
    }

    /// An attached hero strikes under the host's activation and signs its own
    /// dice (`_solo_attack_groups` :4284-4290), host first.
    #[test]
    fn an_attached_hero_strikes_after_the_host_and_signs_its_own_dice() {
        let hp = [blade(4)];
        let hero = [blade(1)];
        let att = Ctx { quality: 4, models: 2, ..Default::default() };
        let mut tray = Tray::seeded(21);
        let out = resolve_melee_with_tray(
            &[
                Shooter { profiles: &hp, keep: &[0], attacks: &[4], att: &att, owner: "Host" },
                Shooter { profiles: &hero, keep: &[0], attacks: &[1], att: &att, owner: "Hero" },
            ],
            &defender(6, 3), "Target", false, true, true, &mut tray);
        let attacks: Vec<(&str, i64)> = out.rolls.iter().filter(|r| r.kind == "attack")
            .map(|r| (r.owner.as_str(), r.count)).collect();
        assert_eq!(attacks, vec![("Host", 4), ("Hero", 1)], "host first, then the hero");
    }
