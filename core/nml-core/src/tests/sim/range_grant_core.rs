use super::*;

    // ---- AIG-G2: the shooter's own "+6\" range" book rules reach the core ----
    //
    // "Increased Shooting Range" (gf) and "Increased Shooting Range Aura" (aof)
    // are Royal Legion-primitive entries with `range_bonus_in` 6. The table adds
    // `SoloController.shooting_range_bonus(member)` to every ranged weapon's
    // reach; the core stamped the value (`royal_legion_range_in`) but no seam
    // read it. Rules 3.6 (`EPOCH_73_V36`) closes that; below 73 stays as played.

    const V36: u32 = crate::acts::EPOCH_73_V36;

    /// The carrier at 0", a plain target at `gap_in`, a real 24" Rifle built the
    /// way the game builds a unit (`UnitStatic::build_for` over a real registry).
    fn reach_line(system: &str, faction: &str, rules: &[&str], epoch: u32, gap_in: f64) -> (State, Vec<UnitStatic>) {
        let (mut st, statics) = boost_line(system, faction, rules, epoch);
        st.positions[2] = vec![
            [gap_in * IN2M, 0.0, 0.0],
            [(gap_in + 0.02) * IN2M, 0.0, 0.0],
            [(gap_in + 0.04) * IN2M, 0.0, 0.0],
        ];
        // `ah` off the firing line so the range gate is the ONLY variable.
        st.positions[1] = vec![[-2.0 * IN2M, 5.0 * IN2M, 0.0]];
        (st, statics)
    }

    fn fired(r: &ShootResult) -> bool {
        r.rolls.iter().any(|x| x.kind == "attack" && x.count > 0)
    }

    /// gf "Increased Shooting Range": a 24" rifle fires at 27" from epoch 73 and
    /// the battle log names the BOOK rule; 31" is past 24 + 6; below 73 and
    /// without the rule the volley stays silent exactly as it was played.
    #[test]
    fn increased_shooting_range_reaches_a_27_inch_target_from_epoch_73() {
        let rule = ["Increased Shooting Range"];
        let (st, statics) = reach_line("gf", "alien_hives", &rule, V36, 27.0);
        let on = run_marked(&st, &statics, V36, &[]);
        assert!(fired(&on), "epoch 73: 24 + 6 reach covers the 27\" gap");
        assert!(
            on.log.iter().any(|l| l.contains("Increased Shooting Range: a gains +6\" reach on b")),
            "rules-must-log: the book rule names itself, got {:?}", on.log
        );
        let (st72, statics72) = reach_line("gf", "alien_hives", &rule, V36 - 1, 27.0);
        assert!(!fired(&run_marked(&st72, &statics72, V36 - 1, &[])), "below 73 the core never read the grant");
        let (stf, staticsf) = reach_line("gf", "alien_hives", &rule, V36, 31.0);
        assert!(!fired(&run_marked(&stf, &staticsf, V36, &[])), "31\" is past the 30\" reach");
        let (stp, staticsp) = reach_line("gf", "alien_hives", &[], V36, 27.0);
        assert!(!fired(&run_marked(&stp, &staticsp, V36, &[])), "no rule, plain 24\" reach");
    }

    /// aof "Increased Shooting Range Aura": its own entry carries the primitive,
    /// so the carrier gets the same +6" and the log names the Aura spelling.
    #[test]
    fn increased_shooting_range_aura_reaches_a_27_inch_target_from_epoch_73() {
        let rule = ["Increased Shooting Range Aura"];
        let (st, statics) = reach_line("aof", "havoc_dwarves", &rule, V36, 27.0);
        let on = run_marked(&st, &statics, V36, &[]);
        assert!(fired(&on), "epoch 73: the Aura entry's +6\" covers the 27\" gap");
        assert!(
            on.log.iter().any(|l| l.contains("Increased Shooting Range Aura: a gains +6\" reach on b")),
            "rules-must-log: the Aura names itself, got {:?}", on.log
        );
        let (st72, statics72) = reach_line("aof", "havoc_dwarves", &rule, V36 - 1, 27.0);
        assert!(!fired(&run_marked(&st72, &statics72, V36 - 1, &[])), "below 73 the core never read the grant");
    }

    /// The planner's imagination (`profiles_of`, the EV range gate) and the
    /// reach rescale must agree with the volley, or the AI would never walk the
    /// boosted shooter into the shot the table lets it take.
    #[test]
    fn the_ev_range_gate_sees_the_grant_from_epoch_73() {
        let rule = ["Increased Shooting Range"];
        let (_, on) = reach_line("gf", "alien_hives", &rule, V36, 27.0);
        let (_, off) = reach_line("gf", "alien_hives", &rule, V36 - 1, 27.0);
        let mut sc = Scratch::default();
        profiles_of(&on[0], 1, 27.0, &mut sc);
        assert_eq!(sc.keep.len(), 1, "epoch 73: the 24\" rifle is in reach at 27\"");
        let mut sc = Scratch::default();
        profiles_of(&off[0], 1, 27.0, &mut sc);
        assert!(sc.keep.is_empty(), "below 73: out of reach, as played");
    }
