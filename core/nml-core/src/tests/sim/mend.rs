use super::*;

    // -------------------------------------------------- BLOCK B1: MEND ---

    /// BLOCK B1 — one fixture act through the tray: the pre-attack Mend slot
    /// draws exactly ONE die (kind "attack", target 1, signed by the ACTING
    /// unit), the tie prefers the hero on equal lost wounds, and the heal is
    /// the D3 capped at the model's own missing wounds.
    #[test]
    fn mend_heals_the_tied_hero_d3_capped_and_draws_one_die() {
        let (st, statics) = mend_line();
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &mend_action(), &terrain, Seams { hero_attach: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        // Exactly one pre-attack die, the table's own record shape.
        assert_eq!(shot.rolls.len(), 1);
        let r = &shot.rolls[0];
        assert_eq!((r.kind, r.count, r.target, r.owner.as_str()),
            ("attack", 1, MEND_TARGET, "a"));
        // The hero won the tie (lost 2 each; key 2*2+1 beats the regiment's 4)
        // and healed exactly min(D3, its own 2 missing wounds) — never capped
        // WRONG: a D3 face of 4+ cannot exist, and the cap is the model's own.
        let d3 = mend_d3(r.faces[0]);
        assert!((1..=3).contains(&d3));
        assert_eq!(next.wounds[1][0], 2 + d3.min(2));
        assert_eq!(next.wounds[1][0], 2 + mend_d3(r.faces[0]).min(2));
        // The tray stands exactly one draw on.
        let mut probe = Tray::seeded(7);
        probe.roll(1);
        assert_eq!(tray.state_i64(), probe.state_i64());
    }

    /// RED for the whole rung: with the hero unwounded the regiment's model
    /// takes the heal; out of the 3" ring of BOTH bearers nothing qualifies and
    /// the slot draws NOTHING; and without the rule the bearer line stays mute.
    #[test]
    fn mend_picks_the_most_wounded_in_range_and_draws_nothing_without_a_patient() {
        let terrain = crate::terrain::Terrain::default();
        // The hero at full wounds: the regiment's wounded model is the patient.
        let (st, statics) = mend_line();
        let mut st = st;
        st.wounds[1] = vec![4];
        let (next, shot) = {
            let mut tray = Tray::seeded(7);
            let mut rng = crate::rng::GodotRng::new(0);
            resolve_stochastic_tray_on_board(
                &statics, &st, &mend_action(), &terrain, Seams { hero_attach: true, ..Seams::default() }, &mut rng, &mut tray,
            )
            .unwrap()
        };
        let d3 = mend_d3(shot.rolls[0].faces[0]);
        assert_eq!(next.wounds[2][0], 1 + d3.min(2));
        // The regiment walked out of the 3" ring AND the hero sits at full
        // wounds: no patient anywhere, NO draw at all.
        let (st, statics) = mend_line();
        let mut st = st;
        st.positions[2] = vec![[10.0 * IN2M, 0.0, 0.0], [10.2 * IN2M, 0.0, 0.0]];
        st.wounds[1] = vec![4];
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &mend_action(), &terrain, Seams { hero_attach: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty());
        let probe = Tray::seeded(7);
        assert_eq!(tray.state_i64(), probe.state_i64());
        assert_eq!(next.wounds[2][0], 1);
        // No Mend, no die — even with a wounded Tough model standing next door.
        let (st, mut statics) = mend_line();
        statics[0].mend_active = false;
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &mend_action(), &terrain, Seams { hero_attach: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty());
    }

    /// The D3 mapping itself: 1-2→1, 3-4→2, 5-6→3 — main.gd:5247's
    /// `(face + 1) / 2`.
    #[test]
    fn the_mend_d3_maps_the_faces_main_gd_way() {
        for (face, want) in [(1u8, 1i64), (2, 1), (3, 2), (4, 2), (5, 3), (6, 3)] {
            assert_eq!(mend_d3(face), want);
        }
    }

    /// H-5a (Plan H): the heal reaches the table. A supplied tray (the door's) keeps one landing on the patient's capture slot with
    /// its healed wounds (above its own count = a heal) and the table's `_solo_apply_mend` line; the die and the state stay as before.
    /// RED: without the landing / the line in `tray_mend` the door's table keeps the patient wounded and the line is missing.
    #[test]
    fn a_supplied_tray_lands_the_heal_and_says_the_tables_mend_line() {
        let (st, statics) = mend_line();
        let mut next = st.clone();
        let mut tray = Tray::supplied(vec![vec![5]]);
        let mut shot = ShootResult::default();
        tray_mend(&statics, &mut next, 0, Seams { hero_attach: true, ..Seams::default() }, &mut tray, &mut shot);
        assert_eq!(next.wounds[1][0], 4, "face 5 = D3 3, capped at the hero's 2 missing wounds");
        let landing = Landing { unit: 1, models: vec![LandedModel { at: st.positions[1][0], slot: 0, wounds_left: 4, dead: false }], loss_line: false };
        assert_eq!(tray.all_landings(), vec![landing]);
        let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        assert_eq!(lines, ["Mend: a heals 2 wounds (D3 rolled 5) — patient now 4/4"]);
        // A one-wound heal says the singular; a seeded tray keeps neither landing nor line.
        let mut one = st.clone();
        (one.wounds[1], one.wounds[2]) = (vec![3], vec![3, 3]);
        let mut tray = Tray::supplied(vec![vec![1]]);
        tray_mend(&statics, &mut one, 0, Seams { hero_attach: true, ..Seams::default() }, &mut tray, &mut ShootResult::default());
        assert_eq!(tray.all_lines().into_iter().map(|l| l.text).collect::<Vec<_>>(), ["Mend: a heals 1 wound (D3 rolled 1) — patient now 4/4"]);
        let mut seeded = Tray::seeded(7);
        tray_mend(&statics, &mut st.clone(), 0, Seams { hero_attach: true, ..Seams::default() }, &mut seeded, &mut ShootResult::default());
        assert!(seeded.all_landings().is_empty() && seeded.all_lines().is_empty());
    }
