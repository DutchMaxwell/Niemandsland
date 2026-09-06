use super::*;

    // ------------------------------- wave 3: the Piercing-Tag family ---

    /// Piercing Tag — the activation places 1 marker on the toughest enemy in
    /// 24"/LOS and THIS volley spends it: +AP(1) on the save, the pool empty
    /// and the once-per-game flag set after. Epoch literals 6/5, NOT
    /// `CURRENT_RULES_EPOCH`: a wave-4 bump must not re-date what these mean.
    /// RED before the fix: nothing places, nothing spends.
    #[test]
    fn piercing_tag_places_one_marker_and_spends_it_on_this_volley() {
        let (st, statics) = tag_line("Piercing Tag", 1, 24.0);
        let s6 = Seams { rules_epoch: 6, ..Seams::default() };
        let (next, shot) = tag_volley(&statics, &st, s6);
        assert_eq!(shot.rolls[1].target, 5, "the spent marker's +AP(1) on this volley");
        assert!(next.piercing_tag_used[0], "the once-per-game flag set at the placement");
        assert_eq!(next.piercing_tag_markers[2], 0, "the pool spends whole");
        assert!(
            shot.log.iter().any(|l| l.starts_with("Piercing Tag: tagger places 1 marker on b")),
            "rules-must-log: the placement line, main.gd:17025 shape — got {:#?}",
            shot.log
        );
        assert!(
            shot.log.iter().any(|l| l.starts_with("Piercing Tag: 1 marker spent")),
            "rules-must-log: the spend line, main.gd:17040 shape — got {:#?}",
            shot.log
        );

        // The gate: a rules_epoch-5 record (the fleet stamps 5 today) replays
        // the pre-wave reading — no placement, no spend, no lines.
        let s5 = Seams { rules_epoch: 5, ..Seams::default() };
        let (next5, shot5) = tag_volley(&statics, &st, s5);
        assert_eq!(shot5.rolls[1].target, 4, "epoch 5: no markers, the plain save");
        assert!(!next5.piercing_tag_used[0]);
        assert_eq!(next5.piercing_tag_markers[2], 0);
        assert!(shot5.log.iter().all(|l| !l.contains("Piercing Tag")));

        // Once per game: a bearer that already placed never places again.
        let (mut used, _) = tag_line("Piercing Tag", 1, 24.0);
        used.piercing_tag_used[0] = true;
        let (next_u, shot_u) = tag_volley(&statics, &used, s6);
        assert_eq!(shot_u.rolls[1].target, 4, "used: no second placement");
        assert_eq!(next_u.piercing_tag_markers[2], 0);
    }

    /// Piercing Spotter — the same resolver at its OWN literal and params
    /// (range 30): the table's AI never rolls the printed 4+ (`place_roll` is
    /// dead data on main.gd:17002 too — one `unit_rules_of_primitive` loop
    /// serves the whole family), so the twin places the same maxi(rating, 1)
    /// marker and logs the rule's own name. Epoch literals 6/5.
    #[test]
    fn piercing_spotter_places_through_the_same_family_resolver() {
        let (st, statics) = tag_line("Piercing Spotter", 1, 30.0);
        let s6 = Seams { rules_epoch: 6, ..Seams::default() };
        let (next, shot) = tag_volley(&statics, &st, s6);
        assert_eq!(shot.rolls[1].target, 5, "the spent marker's +AP(1) at the Spotter's own 30-inch read");
        assert!(
            shot.log.iter().any(|l| l.starts_with("Piercing Spotter: tagger places 1 marker on b")),
            "the placement names the SPOTTER — got {:#?}",
            shot.log
        );
        assert!(!next.piercing_tag_used[2], "only the TAGGER's flag moves — the victim carries no rule");

        let s5 = Seams { rules_epoch: 5, ..Seams::default() };
        let (next5, shot5) = tag_volley(&statics, &st, s5);
        assert_eq!(shot5.rolls[1].target, 4, "epoch 5: no markers, the plain save");
        assert!(shot5.log.iter().all(|l| !l.contains("Piercing")));
    }

    /// Piercing Target — the third name at its OWN literal and params (range
    /// 18): the table implements its "+AP(X) when attacking" with the same
    /// marker pool and the same spend-everything volley seam (main.gd:17012's
    /// primitive loop + :3123), so the twin does too. Epoch literals 6/5.
    #[test]
    fn piercing_target_places_through_the_same_family_resolver() {
        let (st, statics) = tag_line("Piercing Target", 1, 18.0);
        let s6 = Seams { rules_epoch: 6, ..Seams::default() };
        let (next, shot) = tag_volley(&statics, &st, s6);
        assert_eq!(shot.rolls[1].target, 5, "the spent marker's +AP(1) at the Target's own 18-inch read");
        assert!(
            shot.log.iter().any(|l| l.starts_with("Piercing Target: tagger places 1 marker on b")),
            "the placement names the TARGET — got {:#?}",
            shot.log
        );
        assert_eq!(next.piercing_tag_markers[2], 0);

        let s5 = Seams { rules_epoch: 5, ..Seams::default() };
        let (next5, shot5) = tag_volley(&statics, &st, s5);
        assert_eq!(shot5.rolls[1].target, 4, "epoch 5: no markers, the plain save");
        assert!(shot5.log.iter().all(|l| !l.contains("Piercing")));
    }

    /// NML-1150: an act whose two members fire at TWO different units resolves
    /// as the table resolves it — one tray volley per target group, in the
    /// act's group order, on ONE tray. The host's rifle opens at `b`, the
    /// joined hero's heavy gun answers at `bh`; each defender eats only its
    /// own group's wounds, and the tray stands exactly where the drawn faces
    /// put it. RED for the whole rung: swapping the act's group order moves
    /// the draw order with it (proven red once by the same assertions under
    /// the swapped list).
    #[test]
    fn the_volley_resolves_per_target_group_in_the_acts_order() {
        let (st, statics) = split_line();
        let action = Action {
            kind: HOLD,
            unit: "a".into(),
            dest: None,
            shoot: Some("b".into()),
            charge: None,
            patient: false,
            split: Some(vec![
                split_shot("host", "Rifle", "b"),
                split_shot("hero", "Heavy Gun", "bh"),
            ]),
            traced: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = crate::sim::resolve_stochastic_tray_on_board(
            &statics, &st, &action, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        // The draw order: the FIRST group's volley, then the second's — the
        // host's 1 rifle die at `b`, its save batch, then the hero's 3 heavy
        // gun dice at `bh` with THAT defender's own save batch. Per-model
        // sighting off, so the counts are the survivor-scaled attacks.
        let kinds: Vec<&str> = shot.rolls.iter().map(|r| r.kind).collect();
        let owners: Vec<&str> = shot.rolls.iter().map(|r| r.owner.as_str()).collect();
        assert_eq!(kinds, vec!["attack", "defense", "attack", "defense"]);
        assert_eq!(owners, vec!["host", "b", "hero", "bh"]);
        assert_eq!(shot.rolls[0].count, 1);
        assert_eq!(shot.rolls[2].count, 3);
        // The per-group HIT count: each save batch is exactly the hits its own
        // hit roll drew (faces recomputed off the port's OWN roll, dice_rules
        // style), signed by ITS group's defender.
        for (hit, save) in [(0usize, 1usize), (2, 3)] {
            let hits = faces_to_hits(&shot.rolls[hit].faces, shot.rolls[hit].target as u8) as i64;
            assert_eq!(shot.rolls[save].count, hits.max(0));
            assert_eq!(shot.rolls[save].owner, if hit == 0 { "b" } else { "bh" });
        }
        // The per-group WOUNDS: each defender eats ONLY its own group's
        // unsaved wounds — `b` stands (its save blocks everything at Defense
        // 0 in this fixture), `bh` falls to its group's one landed wound.
        assert_eq!(next.alive[2], 1);
        assert_eq!(next.wounds[2].iter().sum::<i64>(), 1);
        assert_eq!(next.alive[3], 0);
        assert!(next.wounds[3].is_empty());
        assert_eq!(shot.caused, 1);
        // The tray position: exactly the faces the report drew, no more.
        let mut probe = Tray::seeded(11);
        let total: usize = shot.rolls.iter().map(|r| r.count as usize).sum();
        probe.roll(total);
        assert_eq!(tray.state_i64(), probe.state_i64());
    }

    /// RED PROOF, split vs pooled: `b`'s Stealth must fire off the 12" CENTRE
    /// gap on both the pooled plan (no split aim) and a split group forced
    /// onto the very same (host, b) pair (recorded target `bh`, but the one
    /// aim entry names `b`) — even though the two paths disagree on `d`
    /// itself (pooled keeps the raw 12" nearest-model gap; split subtracts
    /// both radii to 8"). Quality 4, Stealth -1: to-hit 5+, not 4+ — a bug
    /// that read the RANGE gap for the modifier would give 4+ on the split
    /// leg (8" <= 9") while the pooled leg still read 5+, disagreeing.
    #[test]
    fn the_modifier_gate_reads_centre_distance_on_both_the_pooled_and_split_paths() {
        let (st, statics) = stealth_split_line();
        let terrain = crate::terrain::Terrain::default();

        let pooled = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()),
            charge: None, patient: false, split: None, traced: None,
        };
        let mut tray_a = Tray::seeded(11);
        let mut rng_a = crate::rng::GodotRng::new(0);
        let (_, shot_a) = resolve_stochastic_tray_on_board(
            &statics, &st, &pooled, &terrain, Seams::default(), &mut rng_a, &mut tray_a,
        )
        .unwrap();

        let split = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("bh".into()),
            charge: None, patient: false,
            split: Some(vec![split_shot("host", "Rifle", "b")]),
            traced: None,
        };
        let mut tray_b = Tray::seeded(11);
        let mut rng_b = crate::rng::GodotRng::new(0);
        let (_, shot_b) = resolve_stochastic_tray_on_board(
            &statics, &st, &split, &terrain, Seams::default(), &mut rng_b, &mut tray_b,
        )
        .unwrap();

        assert_eq!(shot_a.rolls[0].target, 5, "pooled: Stealth fires off the 12\" centre gap");
        assert_eq!(shot_b.rolls[0].target, 5, "split: must agree with the pooled path");
    }
