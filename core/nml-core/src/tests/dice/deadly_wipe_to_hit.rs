use super::*;

    /// A Deadly launcher (group 1) kills the target's last model, then five plain rifles (group 2) fire. The volley is
    /// simultaneous: the target's to-hit penalty holds for the rifles too. Answers the rifles' to-hit target.
    fn rifles_target_after_a_deadly_wipe(def: Ctx) -> i64 {
        let att = Ctx { rules_epoch: def.rules_epoch, ..shooter(3) };
        let guns = [
            ShootProfile { name: "Deadly Launcher".into(), deadly: 3, ap: 2, ..rifle(1) },
            ShootProfile { name: "Plain Rifle".into(), ..rifle(5) },
        ];
        let sh = [Shooter { profiles: &guns, keep: &[0, 1], attacks: &[1, 5], att: &att, owner: "Cov Shooter" }];
        // Launcher hits (6), the save fails (1), then the rifles' five faces.
        let mut tray = Tray::supplied(vec![vec![6], vec![1], vec![3, 1, 4, 1, 6], vec![1, 1, 1]]);
        let mut land = |_: &[(i64, i64)]| -> i64 { 0 }; // the Deadly group wipes the lone model
        let r = resolve_volley_with_pick_label(&sh, &def, "Lone Hero", 12.0, 12.0, true, true, true, true, true, true,
            &|_| (false, "trooper".into(), 0), &|_, _| None, Some(&mut land), None, &mut tray);
        let attacks: Vec<&Roll> = r.rolls.iter().filter(|x| x.kind == "attack").collect();
        assert_eq!(attacks.len(), 2, "fixture: two attack rolls {:?}", r.rolls);
        assert_eq!(attacks[0].count, 1, "fixture: the Deadly launcher fires first");
        attacks[1].target
    }

    fn lone_hero(epoch: u32) -> Ctx {
        Ctx { rules_epoch: epoch, ..defender(4, 1) }
    }

    /// RED on main: the wiped read dropped Stealth, so the rifles rolled 3+ instead of 4+.
    #[test]
    fn a_deadly_wipe_keeps_the_stealth_penalty_for_the_second_weapon_group() {
        let e = crate::acts::EPOCH_97_WIPED_TO_HIT_DECLARED;
        assert_eq!(rifles_target_after_a_deadly_wipe(Ctx { stealth: true, ..lone_hero(e) }), 4, "Stealth -1 holds: 3+ becomes 4+");
    }

    #[test]
    fn a_deadly_wipe_keeps_the_evasive_and_aircraft_penalties_for_the_second_weapon_group() {
        let e = crate::acts::EPOCH_97_WIPED_TO_HIT_DECLARED;
        assert_eq!(rifles_target_after_a_deadly_wipe(Ctx { evasive: true, ..lone_hero(e) }), 4, "Evasive -1 holds");
        let air = Ctx { aircraft_hit_penalty: 1, aircraft_hit_name: "Aircraft", ..lone_hero(e) };
        assert_eq!(rifles_target_after_a_deadly_wipe(air), 4, "Aircraft -1 holds");
    }

    /// Records stamped below the gate replay as recorded: the old wiped read drops the penalty.
    #[test]
    fn below_the_gate_a_deadly_wipe_still_drops_the_penalty() {
        let e = crate::acts::EPOCH_97_WIPED_TO_HIT_DECLARED - 1;
        assert_eq!(rifles_target_after_a_deadly_wipe(Ctx { stealth: true, ..lone_hero(e) }), 3);
        assert_eq!(rifles_target_after_a_deadly_wipe(lone_hero(crate::acts::EPOCH_97_WIPED_TO_HIT_DECLARED)), 3, "no rule, no penalty");
    }
