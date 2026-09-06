    use super::*;
    use crate::state::{Bands, Mods, MoveBands, Profile, Profiles, Roster};
    use std::collections::HashMap;

    /// Four 1"-radius single-model units on one line: a charger host (unit 0)
    /// with a joined hero (unit 1) two inches in front of it, and a target host
    /// (unit 2) with a joined hero (unit 3) three inches in front of IT. The
    /// four base-edge gaps the engage test can pick from are therefore
    /// 10" (host to host), 8" and 7" (one hero folded) and 5" (both) — one
    /// number per fold, so a single assertion says which lists were measured.
    pub(super) fn four_unit_line() -> State {
        let profile = Profile {
            unit_id: "u".into(),
            name: "u".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: String::new(),
            faction_folder: String::new(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let xs = [0.0, 2.0, 12.0, 9.0];
        State {
            roster: Rc::new(Roster {
                keys: vec!["a".into(), "ah".into(), "b".into(), "bh".into()],
                index: HashMap::new(),
                profile: vec![0, 0, 0, 0],
            }),
            profiles: Rc::new(Profiles { list: vec![profile], index: HashMap::new() }),
            round: 0,
            rounds_total: 1,
            scoring: Rc::from(""),
            objectives: vec![],
            markers_meta: vec![],
            destroy_seq: vec![],
            vp: None,
            vp_flavour: None,
            vp_memo: None,
            cast_events: vec![],
            player: vec![0, 0, 1, 1],
            alive: vec![1; 4],
            activated: vec![false; 4],
            shaken: vec![false; 4],
            fatigued: vec![false; 4],
            in_cover: vec![false; 4],
            aircraft: vec![false; 4],
            dormant: vec![false; 4],
            dormant_models: vec![0; 4],
            dormant_wounds: vec![Vec::new(); 4],
            casts: vec![0; 4],
            morale_bonus: vec![0; 4],
            ambush_arrived_round: vec![-1; 4],
            earliest_arrival_round: vec![-1; 4],
            wound_frac: vec![1.0; 4],
            positions: xs.iter().map(|x| vec![[x * IN2M, 0.0, 0.0]]).collect(),
            wounds: vec![vec![1]; 4],
            radii: vec![vec![IN2M]; 4],
            mods: vec![Mods::default(); 4],
            mods_base: (0..4).map(|_| Rc::new(Mods::default())).collect(),
            attached: Rc::new(vec![vec![1], vec![], vec![3], vec![]]),
            attached_to: Rc::new(vec![None, Some(0), None, Some(2)]),
            los: vec![None, None, None, None],
            los_pairs: None,
            bands: vec![Bands::default(); 4],
            shroud: vec![None; 4],
            charge_no_difficult: vec![false; 4],
            charge_probe_r: vec![0.0; 4],
            buffs: vec![Vec::new(); 4],
            vs_mark_round: vec![-1; 4],
            hit_and_run_round: vec![-1; 4],
            growth_markers: vec![0; 4],
            growth_round: vec![-1; 4],
            second_wind_used: vec![false; 4],
            second_wind_round: -1,
            second_wind_uses: 0,
            sidestep_budget: Default::default(),
            limited_used: vec![Vec::new(); 4],
            piercing_tag_used: vec![false; 4],
            piercing_tag_markers: vec![0; 4],
            storm_used: vec![Vec::new(); 4],
        }
    }

    /// Fear(X) (GF/AoF v3.5.1): "counts as having dealt +X wounds when
    /// checking who won melee." Unit 0 (host, Fear(2)) deals 1 wound and
    /// takes 2 from unit 2 (host, no Fear) — raw tallies say unit 0 loses
    /// (1 < 2), but 1+2 > 2 means Fear(2) should flip the result. Both units'
    /// quality is set to fail morale for certain, so `alive == 0` after the
    /// call marks exactly which side was made to test — and lose.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The bearer: an "a" whose ONLY rule is the named chaos Storm, read off
    /// the REAL gf registry (`assets/solo/rules_mechanics_gf.json`).
    fn storm_bearer(rule: &str, faction: &str, rules_epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![rule.into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// Bearer "a" vs a 3-model Defense-4 target "b" 5" edge-to-edge (inside
    /// the 12" band); ah/bh field no models. `breath_line`'s shape, but the
    /// rule arrives through the registry.
    fn storm_line(rule: &str, faction: &str, rules_epoch: u32) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[5.0 * IN2M, 0.0, 0.0], [5.02 * IN2M, 0.0, 0.0], [5.04 * IN2M, 0.0, 0.0]],
            vec![],
        ];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M; 3], vec![]];
        st.wounds = vec![vec![1], vec![], vec![1, 1, 1], vec![]];
        st.alive = vec![1, 0, 3, 0];
        let bearer = storm_bearer(rule, faction, rules_epoch);
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.model_count = 3;
        b.wounds_max = vec![1, 1, 1];
        b.ctx.defense = 4;
        (
            st,
            vec![
                bearer,
                UnitStatic { name: "ah".into(), ..Default::default() },
                b,
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    fn storm_action() -> Action {
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None }
    }

    fn run_storm(
        st: &State,
        statics: &[UnitStatic],
        seed: i64,
        rules_epoch: u32,
    ) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(
            statics, st, &storm_action(), &terrain, seams, &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// Storm of Change: seed 37 = storm faces [1, 1, 2] (one success), Shred
    /// save batch [3, 3, 1] at Defense 4 — 3 failed saves + Shred's +1 on the
    /// natural 1. The epoch-5 control (the fleet stamps 5) draws NOTHING.
    #[test]
    fn storm_of_change_fires_shred_on_activation_at_epoch_six_not_five() {
        let (st, statics) = storm_line("Storm of Change", "wormhole_daemons_of_change", 6);
        let (next, shot) = run_storm(&st, &statics, 37, 6);
        let storm = &shot.rolls[0];
        assert_eq!(
            (storm.kind, storm.count, storm.target, storm.owner.as_str()),
            ("attack", 3, 2, "a"),
            "the once-per-game burst rolls its 3 dice at the 2+ trigger"
        );
        let save = &shot.rolls[1];
        assert_eq!((save.kind, save.count, save.target, save.owner.as_str()), ("defense", 3, 4, "b"));
        assert_eq!(shot.caused, 4, "3 failed saves + Shred's +1 on the natural 1");
        assert_eq!(next.alive[2], 0);
        assert!(
            shot.log.iter().any(|l| l.contains("Storm of Change")
                && l.contains("unleashes the storm")),
            "rules must log: the line names the rule, the bearer and the dice"
        );

        let (st5, statics5) = storm_line("Storm of Change", "wormhole_daemons_of_change", 5);
        let (next5, shot5) = run_storm(&st5, &statics5, 37, 5);
        assert!(shot5.rolls.is_empty(), "epoch 5 predates the wave-3 port");
        assert!(shot5.log.is_empty());
        assert_eq!(next5.wounds[2], vec![1, 1, 1]);
    }

    /// Storm of Lust, payload Surge — one die PER HIT, each 6 adds a hit
    /// (the Surge primitive's own facet). Seed 3: storm [1, 1, 4] (one
    /// success), surge dice [4, 6, 4] add one, the grown batch [3, 1, 2, 5]
    /// loses three. Epoch 5: nothing.
    #[test]
    fn storm_of_lust_pays_surge_dice_per_hit_at_epoch_six_not_five() {
        let (st, statics) = storm_line("Storm of Lust", "wormhole_daemons_of_lust", 6);
        let (next, shot) = run_storm(&st, &statics, 3, 6);
        let storm = &shot.rolls[0];
        assert_eq!((storm.kind, storm.count, storm.target), ("attack", 3, 2));
        let surge = &shot.rolls[1];
        assert_eq!(
            (surge.kind, surge.count, surge.target, surge.faces.clone()),
            ("attack", 3, 6, vec![4, 6, 4]),
            "one die per hit, 6 = one extra hit"
        );
        let save = &shot.rolls[2];
        assert_eq!(
            (save.kind, save.count, save.target),
            ("defense", 4, 4),
            "the batch grows by the surge six before it rolls"
        );
        assert_eq!(shot.caused, 3);
        assert_eq!(next.alive[2], 0);

        let (st5, statics5) = storm_line("Storm of Lust", "wormhole_daemons_of_lust", 5);
        let (next5, shot5) = run_storm(&st5, &statics5, 3, 5);
        assert!(shot5.rolls.is_empty());
        assert_eq!(next5.wounds[2], vec![1, 1, 1]);
    }

    /// Storm of Plague, payload Bane — the defender re-rolls its unmodified
    /// 6s (the Bane primitive's own batch leg). Seed 3: storm [1, 1, 4] (one
    /// success), save batch [4, 6, 4] — the six blocks, Bane re-rolls it into
    /// a 3, that failed re-roll wounds. Epoch 5: nothing.
    #[test]
    fn storm_of_plague_forces_the_bane_reroll_at_epoch_six_not_five() {
        let (st, statics) = storm_line("Storm of Plague", "wormhole_daemons_of_plague", 6);
        let (_, shot) = run_storm(&st, &statics, 3, 6);
        let storm = &shot.rolls[0];
        assert_eq!((storm.kind, storm.count, storm.target), ("attack", 3, 2));
        let save = &shot.rolls[1];
        assert_eq!((save.kind, save.count, save.target, save.faces.clone()), ("defense", 3, 4, vec![4, 6, 4]));
        let reroll = &shot.rolls[2];
        assert_eq!(
            (reroll.kind, reroll.count, reroll.target, reroll.faces.clone()),
            ("defense", 1, 4, vec![3]),
            "Bane re-rolls the defender's unmodified six"
        );
        assert_eq!(shot.caused, 1, "the re-rolled six failed into a wound");

        let (st5, statics5) = storm_line("Storm of Plague", "wormhole_daemons_of_plague", 5);
        let (next5, shot5) = run_storm(&st5, &statics5, 3, 5);
        assert!(shot5.rolls.is_empty());
        assert_eq!(next5.wounds[2], vec![1, 1, 1]);
    }

    /// Storm of War, payload AP(1) — the save target worsens by one (Defense
    /// 4+ becomes 5+). Seed 3: storm [1, 1, 4] (one success), batch [4, 6, 4]
    /// at target 5 — two failures. Epoch 5: nothing.
    #[test]
    fn storm_of_war_puts_ap_one_on_the_burst_at_epoch_six_not_five() {
        let (st, statics) = storm_line("Storm of War", "wormhole_daemons_of_war", 6);
        let (next, shot) = run_storm(&st, &statics, 3, 6);
        let storm = &shot.rolls[0];
        assert_eq!((storm.kind, storm.count, storm.target), ("attack", 3, 2));
        let save = &shot.rolls[1];
        assert_eq!(
            (save.kind, save.count, save.target),
            ("defense", 3, 5),
            "AP(1) shifts the save from Defense 4+ to 5+"
        );
        assert_eq!(shot.caused, 2);
        assert_eq!(next.alive[2], 1);

        let (st5, statics5) = storm_line("Storm of War", "wormhole_daemons_of_war", 5);
        let (next5, shot5) = run_storm(&st5, &statics5, 3, 5);
        assert!(shot5.rolls.is_empty());
        assert_eq!(next5.wounds[2], vec![1, 1, 1]);
    }

    /// ONCE per game, not once per activation: the burst spends the bearer's
    /// flag (the `limited_used` shape — DISPLAY name, never reset), and a
    /// preset flag keeps the burst quiet on a fresh target pool.
    #[test]
    fn storm_is_once_per_game_per_bearer() {
        let (st, statics) = storm_line("Storm of Change", "wormhole_daemons_of_change", 6);
        let (next, shot) = run_storm(&st, &statics, 3, 6);
        assert!(!shot.rolls.is_empty());
        assert_eq!(next.storm_used[0], vec!["Storm of Change".to_string()]);

        let (st2, statics2) = storm_line("Storm of Change", "wormhole_daemons_of_change", 6);
        let mut spent = st2;
        spent.storm_used[0] = vec!["Storm of Change".to_string()];
        let (next2, shot2) = run_storm(&spent, &statics2, 3, 6);
        assert!(shot2.rolls.is_empty(), "already spent this game");
        assert!(shot2.log.is_empty());
        assert_eq!(next2.wounds[2], vec![1, 1, 1]);
    }

    /// No enemy within the 12" band — the burst does NOT fire and the
    /// once-per-game is NOT spent (main.gd:17257's own gate).
    #[test]
    fn storm_out_of_reach_is_not_spent() {
        let (mut st, statics) = storm_line("Storm of Change", "wormhole_daemons_of_change", 6);
        st.positions[2] =
            vec![[20.0 * IN2M, 0.0, 0.0], [20.02 * IN2M, 0.0, 0.0], [20.04 * IN2M, 0.0, 0.0]];
        let (next, shot) = run_storm(&st, &statics, 3, 6);
        assert!(shot.rolls.is_empty(), "18\" edge gap is past the 12\" band");
        assert!(next.storm_used[0].is_empty());
        assert_eq!(next.wounds[2], vec![1, 1, 1]);
    }

    #[test]
    fn fear_x_lifts_its_own_side_s_tally_in_the_ev_melee_comparison() {
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: st.roster.keys.clone(),
            index: HashMap::new(),
            profile: vec![0, 0, 1, 0],
        });
        st.wounds[0] = vec![8]; // su_before(10) - 8 = 2 dealt BY the target
        st.wounds[2] = vec![9]; // tu_before(10) - 9 = 1 dealt BY the Fear unit
        let statics = vec![
            UnitStatic { ctx: Ctx { fear: 2, ..Ctx::default() }, quality: 6, ..UnitStatic::default() },
            UnitStatic { quality: 6, ..UnitStatic::default() },
        ];
        expected_melee_morale(&mut st, &statics, 0, 10, 2, 10);
        assert_eq!(st.alive[0], 1, "the Fear(2) unit dealt 1+2=3 > 2, it must not test morale");
        assert_eq!(st.alive[2], 0, "the plain unit lost the comparison and must rout");
    }

    /// D5-4. `nearest_melee_gap_in` (:8526) measures `_moving_models` on BOTH
    /// sides, so the joined heroes' bases are the ones that decide this charge:
    /// 5", not the hosts' 10". Folding only one side would read 8" or 7", which
    /// is why the assertion is on the exact number and not on "smaller".
    #[test]
    fn the_engage_test_measures_from_a_joined_heros_base_on_both_sides() {
        let st = four_unit_line();
        let on = Seams { hero_attach: true, ..Seams::default() };
        assert!((engage_gap_in(&st, 0, 2, on) - 5.0).abs() < 1e-6);
    }

    /// The seam OFF is the D5-1 reading, hosts alone — the identity that keeps
    /// every recorded corpus replaying. The RED knob (`engage_fold=false` in the
    /// header) has to return exactly that number while `hero_attach` stays on,
    /// or it is not a red for this rung but for the whole seam.
    #[test]
    fn the_hosts_alone_answer_with_the_seam_off_and_under_the_red_knob() {
        let st = four_unit_line();
        let off = Seams::default();
        let red = Seams { hero_attach: true, no_engage_fold: true, ..Seams::default() };
        assert!((engage_gap_in(&st, 0, 2, off) - 10.0).abs() < 1e-6);
        assert_eq!(engage_gap_in(&st, 0, 2, red), engage_gap_in(&st, 0, 2, off));
    }

    /// D5-2b — the target is a 92 x 120 mm OVAL whose recorded (circumscribing)
    /// radius is still 1". Across its short axis the table measures 0.6084" of
    /// base, not 1", so the engage gap opens from 10" to 10.3916" — but ONLY
    /// while the resolver is imitating the live table. With both charge seams
    /// off it is imitating `BattleSim`, whose own `edge_gap_in`
    /// (battle_sim.gd:869) knows nothing but the radius, and the answer must
    /// stay the D5-1 number to the digit.
    #[test]
    fn an_oval_target_is_measured_by_its_support_extent_under_the_charge_seams() {
        let mut st = four_unit_line();
        let mut oval = st.profiles.list[0].clone();
        oval.base_shape = "oval".into();
        oval.base_w_mm = 92.0;
        oval.base_d_mm = 120.0;
        st.profiles = Rc::new(Profiles {
            list: vec![st.profiles.list[0].clone(), oval],
            index: HashMap::new(),
        });
        st.roster = Rc::new(Roster {
            keys: st.roster.keys.clone(),
            index: HashMap::new(),
            profile: vec![0, 0, 1, 0],
        });
        let short_semi_in = 92.0 / (92.0f64 * 92.0 + 120.0 * 120.0).sqrt();
        let want = 12.0 - 1.0 - short_semi_in;
        for seams in [
            Seams { charge_landing: true, ..Seams::default() },
            Seams { movement: true, ..Seams::default() },
        ] {
            let got = engage_gap_in(&st, 0, 2, seams);
            assert!((got - want).abs() < 1e-6, "shaped engage gap {got}, want {want}");
        }
        assert!((engage_gap_in(&st, 0, 2, Seams::default()) - 10.0).abs() < 1e-6);
    }

    /// A hero with no models left is `_moving_models`' empty list: it drops out
    /// of the minimum instead of dragging it to `INFINITY`, the same way an
    /// empty `b_shapes` does on the table.
    #[test]
    fn a_dead_joined_hero_does_not_move_the_engage_gap() {
        let mut st = four_unit_line();
        st.positions[3].clear();
        st.positions[1].clear();
        let on = Seams { hero_attach: true, ..Seams::default() };
        assert!((engage_gap_in(&st, 0, 2, on) - 10.0).abs() < 1e-6);
    }


    fn gun(name: &str, attacks: i64, range: i64) -> ShootProfile {
        ShootProfile { name: name.into(), attacks, count: 1, range, ..Default::default() }
    }

    /// One static per unit of `four_unit_line` (whose roster shares profile 0, so
    /// the roster is rebuilt alongside): the charger host carries a 24" RIFLE and a
    /// CCW, its joined hero a 36" HEAVY GUN and a FIST, the two enemies nothing.
    fn hero_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.index.clone(),
            profile: vec![0, 1, 2, 3],
        });
        let host = UnitStatic {
            name: "host".into(),
            model_count: 1,
            shoot: vec![gun("Rifle", 1, 24)],
            melee: vec![gun("CCW", 2, 0)],
            ..Default::default()
        };
        let hero = UnitStatic {
            name: "hero".into(),
            model_count: 1,
            shoot: vec![gun("Heavy Gun", 3, 36)],
            melee: vec![gun("Fist", 4, 0)],
            ..Default::default()
        };
        (st, vec![host, hero, UnitStatic::default(), UnitStatic::default()])
    }

    fn kept(statics: &[UnitStatic], melee: bool, sc: &Scratch) -> Vec<String> {
        let own = if melee { &statics[0].melee } else { &statics[0].shoot };
        let all = folded_slice(own, sc);
        if melee {
            all.iter().map(|p| p.name.clone()).collect()
        } else {
            sc.keep.iter().map(|&i| all[i].name.clone()).collect()
        }
    }


    use crate::faces_to_hits;
    use crate::io::SplitShot;

    /// `hero_line` with the roster INDEX filled and the two ENEMY statics
    /// named like their roster keys, so the save batches sign a real unit's
    /// name.
    fn split_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = hero_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r
                .keys
                .iter()
                .enumerate()
                .map(|(i, k)| (k.clone(), i))
                .collect::<HashMap<_, _>>(),
            profile: r.profile.clone(),
        });
        statics[2] = UnitStatic { name: "b".into(), ..Default::default() };
        statics[3] = UnitStatic { name: "bh".into(), ..Default::default() };
        (st, statics)
    }

    fn split_shot(member: &str, weapon: &str, target: &str) -> SplitShot {
        SplitShot {
            member: member.into(),
            weapon: weapon.into(),
            target: target.into(),
        }
    }


    /// A tagger (unit 0, the name's own stamp) and its victim (unit 2, "b")
    /// 12" apart on the split line, the victim the VALUE pick (alive + Tough 1
    /// beats every other enemy candidate's 1). The Rifle draws 6 attack dice
    /// at the Default 2+ hit target; the victim saves at Defense 4, so the
    /// spent markers' +AP is observable on the save target — dice.rs's own
    /// Piercing-Growth precedent.
    fn tag_line(rule: &str, markers: i64, range_in: f64) -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = split_line();
        statics[0] = UnitStatic {
            name: "tagger".into(),
            model_count: 1,
            shoot: vec![gun("Rifle", 6, 24)],
            piercing_tags: vec![PiercingTagEntry {
                name: rule.into(),
                markers,
                range_in,
                needs_los: true,
            }],
            ..Default::default()
        };
        statics[2].ctx = Ctx { defense: 4, tough: 1, ..Default::default() };
        (st, statics)
    }

    fn tag_volley(
        statics: &[UnitStatic],
        st: &State,
        seams: Seams,
    ) -> (State, ShootResult) {
        // The ROSTER keys are the split line's (a/ah/b/bh); the STATICS names
        // (what the table's get_name shows and every log line signs) are the
        // fixture's own.
        let action = Action {
            kind: HOLD,
            unit: "a".into(),
            dest: None,
            shoot: Some("b".into()),
            charge: None,
            patient: false,
            split: None,
            traced: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(27);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, &action, &terrain, seams, &mut rng, &mut tray,
        )
        .expect("volley resolves")
    }

    /// NML-1152 — `split_line` with `host` and `b` each on a 2" base, 12"
    /// centre to centre: the RANGE-VALIDITY edge gap (B11, both radii off) is
    /// 12 - 2 - 2 = 8" (under 9"), while the MODIFIER distance stays the raw
    /// 12" centre gap (over 9") — the exact edge-under/centre-over split the
    /// corpus audit found (qag_ref act 24: edge 7.95" vs centre 14.30").
    fn stealth_split_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = split_line();
        st.radii[0] = vec![2.0 * IN2M];
        st.radii[2] = vec![2.0 * IN2M];
        statics[0].ctx.quality = 4;
        statics[2].ctx = Ctx { defense: 4, stealth: true, ..Default::default() };
        (st, statics)
    }


    /// A Mend bearer line: actor `a` (bears Mend, unwounded Tough(2)) with the
    /// joined hero `ah` (Tough(4), two wounds down) 2" ahead, the wounded
    /// Tough(3) regiment `t` (model 0 two wounds down) 4" from `a` — 2" from
    /// `ah`, so the hero's base puts it in reach — and an enemy far out.
    fn mend_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        // Players 0/0/1/1 in the base fixture — `t` must be FRIENDLY.
        st.player = vec![0, 0, 0, 1];
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: vec!["a".into(), "ah".into(), "t".into(), "f".into()],
            index: ["a", "ah", "t", "f"]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.to_string(), i))
                .collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![[2.0 * IN2M, 0.0, 0.0]],
            vec![[4.0 * IN2M, 0.0, 0.0], [4.2 * IN2M, 0.0, 0.0]],
            vec![[30.0 * IN2M, 0.0, 0.0]],
        ];
        st.wounds = vec![vec![2], vec![2], vec![1, 3], vec![1]];
        let mut a = UnitStatic { name: "a".into(), ..Default::default() };
        a.model_count = 1;
        a.wounds_max = vec![2];
        a.mend_active = true;
        let mut ah = UnitStatic { name: "ah".into(), ..Default::default() };
        ah.model_count = 1;
        ah.wounds_max = vec![4];
        ah.is_hero = true;
        let mut t = UnitStatic { name: "t".into(), ..Default::default() };
        t.model_count = 2;
        t.wounds_max = vec![3, 3];
        (st, vec![a, ah, t, UnitStatic { name: "f".into(), ..Default::default() }])
    }

    fn mend_action() -> Action {
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None }
    }


    /// `a` — two models at 0", Quality 4, one Rifle — is the bearer AND the
    /// best-value friendly unit in range (2 alive + Tough 1 = 3 against `ah`'s
    /// 2), so a "friendly" buff lands on itself and the very next roll of the
    /// same activation has to read it. `b` is three enemy models at 12".
    fn buff_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        // Movement now reads every obstacle's base profile as well as its
        // precomputed combat static; all four profile indices must exist.
        st.profiles = Rc::new(Profiles {
            list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new(),
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0], [0.02 * IN2M, 0.0, 0.0]],
            vec![[2.0 * IN2M, 0.0, 0.0]],
            vec![[12.0 * IN2M, 0.0, 0.0], [12.02 * IN2M, 0.0, 0.0], [12.04 * IN2M, 0.0, 0.0]],
            vec![],
        ];
        st.radii = vec![vec![IN2M; 2], vec![IN2M], vec![IN2M; 3], vec![]];
        st.wounds = vec![vec![1; 2], vec![1], vec![1; 3], vec![]];
        st.alive = vec![2, 1, 3, 0];
        let mut a = UnitStatic {
            name: "a".into(),
            model_count: 2,
            shoot: vec![gun("Rifle", 1, 24)],
            melee: vec![gun("CCW", 1, 0)],
            ..Default::default()
        };
        a.wounds_max = vec![1, 1];
        a.ctx.quality = 4;
        a.ctx.tough = 1;
        let mut ah = UnitStatic { name: "ah".into(), model_count: 1, ..Default::default() };
        ah.ctx.tough = 1;
        let mut b = UnitStatic { name: "b".into(), model_count: 3, ..Default::default() };
        b.wounds_max = vec![1, 1, 1];
        b.ctx.defense = 4;
        b.ctx.quality = 4;
        b.ctx.tough = 1;
        (st, vec![a, ah, b, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    /// One "Utility Buff" registry entry, at the family's printed defaults.
    fn ub(name: &str) -> UtilityBuff {
        UtilityBuff {
            name: name.into(),
            range_in: 12.0,
            target: "friendly".into(),
            max_targets: 1,
            once: true,
            ..Default::default()
        }
    }

    fn buff_action(shoot: Option<&str>) -> Action {
        Action {
            kind: HOLD,
            unit: "a".into(),
            dest: None,
            shoot: shoot.map(|s| s.to_string()),
            charge: None,
            patient: false,
            split: None,
            traced: None,
        }
    }

    /// Runs one fixture activation on a fresh tray and hands back the state and
    /// the report.
    fn run_buff(st: &State, statics: &[UnitStatic], action: &Action, seed: i64) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, action, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// WAVE 3 fixture — the buff line with an AP(1) rifle on the shooter and,
    /// when `with_alias`, Guardian's own stamp on the 12"-away target "b".
    fn fortified_line(with_alias: bool) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        statics[0].shoot[0].ap = 1;
        statics[0].shoot[0].attacks = 64; // a save batch is guaranteed to follow
        if with_alias {
            statics[2].ctx.fortified_alias_ap = 1;
            statics[2].ctx.fortified_alias_over_in = 9.0;
            statics[2].fortified_alias_name = "Guardian".into();
        }
        (st, statics)
    }

    /// The defender's Regeneration batch — `regen_batch` signs it with the
    /// DEFENDER's name and stamps it "attack".
    fn regen_rolls(r: &ShootResult) -> usize {
        // Filtered on the Regeneration TARGET so `b`'s own post-volley morale
        // die — same kind, same owner — is never counted as one.
        r.rolls.iter().filter(|x| x.kind == "attack" && x.owner == "b" && x.target == 5).count()
    }

    fn fold_legs(rule: &str) -> (Vec<UnitStatic>, State) {
        let (mut st, statics) = buff_line();
        st.buffs[0].push(mods::LiveMod {
            hit_mod: 0, casting_mod: 0, morale_mod: 0, grants_rule: Rc::from(rule),
            scope: Rc::from(""), attackers: false, once: true,
        });
        (statics, st)
    }

    fn fold_leg(rule: &str, epoch: u32) -> Ctx {
        let (statics, st) = fold_legs(rule);
        ctx_live(statics[0].ctx.clone(), &statics, &st, 0, false, epoch)
    }


    /// One record as the pre-attack pick (`record_buff`, main.gd:16534) lands
    /// it on the marked unit: the whole grant rides `beneficiary: "attackers"`.
    fn mark(rule: &str) -> crate::mods::LiveMod {
        crate::mods::LiveMod {
            hit_mod: 0,
            casting_mod: 0,
            morale_mod: 0,
            grants_rule: Rc::from(rule),
            scope: Rc::from("shooting"),
            attackers: true,
            once: true,
        }
    }

    /// The volley fixture with the sighting seam ON and the record's own epoch,
    /// so the wave-3 mark consumers are reachable at 6 and inert at 5.
    fn run_marked(st: &State, statics: &[UnitStatic], epoch: u32, buffs: &[(usize, &crate::mods::LiveMod)]) -> ShootResult {
        let mut s = st.clone();
        for (u, m) in buffs {
            s.buffs[*u] = vec![(*m).clone()];
        }
        let seams = Seams { sighting: true, rules_epoch: epoch, ..Default::default() };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, &s, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray,
        )
        .unwrap()
        .1
    }


    /// A RUSH action with a shoot target. `dest: None` keeps the activation
    /// stationary — the same way every OTHER shoot fixture in this file
    /// sidesteps `Unsupported::MovedShootLos` (the port declines a MOVED
    /// unit's shot rather than re-probe LOS off a stale pre-move matrix; that
    /// decline is pre-existing and shared with ADVANCE, untouched by B11).
    fn rush_shoot(target: &str) -> Action {
        Action {
            kind: RUSH,
            unit: "a".into(),
            dest: None,
            shoot: Some(target.to_string()),
            charge: None,
            patient: false,
            split: None,
            traced: None,
        }
    }

    fn advance_shoot(target: &str) -> Action {
        Action { kind: ADVANCE, ..rush_shoot(target) }
    }



    /// Bearer `a` (carries Re-Position Artillery, NOT attached to anyone —
    /// `Seams::default()` keeps hero_attach off, so the base fixture's own
    /// attachment wiring never applies) with a friendly Artillery model `g`
    /// 4" ahead (inside the 6" pick range) that starts with NO weapons at
    /// all (so it never has a shoot target on its own); two enemies on the
    /// same line past `g` — `e1` 26" out and never activated, `e2` only 6"
    /// out but ALREADY activated — so the table's "not-yet-activated first"
    /// key must send `g` toward the FARTHER `e1`.
    fn reposition_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.player = vec![0, 0, 1, 1];
        st.activated = vec![false, false, false, true];
        st.roster = Rc::new(crate::state::Roster {
            keys: vec!["a".into(), "g".into(), "e1".into(), "e2".into()],
            index: ["a", "g", "e1", "e2"].iter().enumerate().map(|(i, k)| (k.to_string(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![[4.0 * IN2M, 0.0, 0.0]],
            vec![[30.0 * IN2M, 0.0, 0.0]],
            vec![[10.0 * IN2M, 0.0, 0.0]],
        ];
        let a = UnitStatic { name: "a".into(), model_count: 1, reposition_artillery_active: true, ..Default::default() };
        let mut g = UnitStatic { name: "g".into(), model_count: 1, ..Default::default() };
        g.ctx.artillery = true;
        g.ctx.tough = 1;
        let e1 = UnitStatic { name: "e1".into(), model_count: 1, ..Default::default() };
        let e2 = UnitStatic { name: "e2".into(), model_count: 1, ..Default::default() };
        (st, vec![a, g, e1, e2])
    }

    fn reposition_action() -> Action {
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None }
    }


    /// BLOCK B3 — a(idx0, the bearer) vs b(idx2, the target), 3" apart
    /// edge-to-edge (inside the 6" range); ah/bh (idx1/3) field no models, so
    /// neither the bearer fold nor the target pick can ever reach them — a
    /// deliberately clean one-bearer-one-target case. b fields 3 alive
    /// Tough(1) models at Defense 4, so Blast(3) caps its hit count at 3 and
    /// the save target is `save_target(4, 1) == 5` (AP(1)).
    fn breath_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[5.0 * IN2M, 0.0, 0.0], [5.02 * IN2M, 0.0, 0.0], [5.04 * IN2M, 0.0, 0.0]],
            vec![],
        ];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M; 3], vec![]];
        st.wounds = vec![vec![1], vec![], vec![1, 1, 1], vec![]];
        st.alive = vec![1, 0, 3, 0];
        let mut a = UnitStatic { name: "a".into(), ..Default::default() };
        a.model_count = 1;
        a.breath_attack_active = true;
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.model_count = 3;
        b.wounds_max = vec![1, 1, 1];
        b.ctx.defense = 4;
        (
            st,
            vec![
                a,
                UnitStatic { name: "ah".into(), ..Default::default() },
                b,
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    fn breath_action() -> Action {
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None }
    }


    /// `small_board()`'s 72" x 48" school board with a FOREST bar across
    /// x in [3", 6"), z in [-3", 3") —
    /// a 3"-thick difficult block sitting squarely on the straight line from the
    /// unit to its destination, and NOT on the rigid landing spot, which is what
    /// makes `_targets_in_difficult` (:5159) answer "route around it".
    fn forest_bar_board() -> crate::terrain::Terrain {
        // `type_at` indexes cells as `floor(inches / 3 + 15)` on this 72" x 48"
        // grid, so cell 16 is x in [3", 6") and cells 14/15 are z in [-3", 3").
        let cells = vec![[16.0, 14.0, crate::terrain::FOREST as f64],
                         [16.0, 15.0, crate::terrain::FOREST as f64]];
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells,
            sandbox: vec![],
            pieces: vec![],
            walls: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    fn advance_to(x_in: f64) -> Action {
        Action {
            kind: ADVANCE,
            unit: "a".into(),
            dest: Some([x_in * IN2M as f64, 0.0, 0.0]),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
        }
    }

    /// A lone 4-model unit (Tough 1, Quality 4+) — row 12 (`dangerous_end_morale`,
    /// DEFECT_LEDGER): GF v3.5.1 p.10/p.12, main.gd:1092-1098.
    fn dangerous_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions[0] = vec![
            [0.0, 0.0, 0.0],
            [0.02 * IN2M, 0.0, 0.0],
            [0.04 * IN2M, 0.0, 0.0],
            [0.06 * IN2M, 0.0, 0.0],
        ];
        st.radii[0] = vec![IN2M; 4];
        st.wounds[0] = vec![1; 4];
        st.alive[0] = 4;
        let mut a = UnitStatic { name: "a".into(), model_count: 4, ..Default::default() };
        a.wounds_max = vec![1; 4];
        a.ctx.quality = 4;
        a.ctx.tough = 1;
        (st, vec![a, UnitStatic::default(), UnitStatic::default(), UnitStatic::default()])
    }

    /// Marks BOTH cell-index neighbours on x AND z DANGEROUS (`forest_bar_board`'s
    /// own straddling trick): a rigid ADVANCE band always lands `dangerous_line`'s
    /// unit exactly on x=6"/z=0", both of them cell-index boundaries.
    fn dangerous_bar_board() -> crate::terrain::Terrain {
        let cells = vec![
            [16.0, 14.0, crate::terrain::DANGEROUS as f64],
            [16.0, 15.0, crate::terrain::DANGEROUS as f64],
            [17.0, 14.0, crate::terrain::DANGEROUS as f64],
            [17.0, 15.0, crate::terrain::DANGEROUS as f64],
        ];
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells,
            sandbox: vec![],
            walls: vec![],
            pieces: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }


    /// Block C fixture (the `duel` shape) — a single-model carrier "a" with
    /// one melee profile facing a single-model target "b" whose base-edge gap
    /// (inches) the caller picks. Bands are the state defaults (rush 12").
    fn vr_charge_line(gap_in: f64) -> (State, Vec<UnitStatic>) {
        let blade = ShootProfile { name: "Blade".into(), attacks: 8, count: 1, range: 0, ..Default::default() };
        let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into()],
            index: ["a".to_string(), "b".to_string()]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.clone(), i))
                .collect(),
            profile: vec![0, 1],
        });
        st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![1, 1];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[(gap_in + 2.0) * IN2M, 0.0, 0.0]]];
        st.wounds = vec![vec![1], vec![1]];
        st.radii = vec![vec![IN2M], vec![IN2M]];
        (st, vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Charger".into(),
                melee: vec![blade],
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Target".into(),
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
        ])
    }

    fn vr_charge() -> Action {
        Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        }
    }

    /// The seam-armed resolver run every VR charge test replays: the M4
    /// movement port is what the table's `_charge_move` (:2213) feeds, so the
    /// +2" must reach its band argument exactly there. `versatile_reach: true`
    /// because every existing caller of this helper is proving the RULE
    /// itself (the on-by-default `play_game` reading) — the knob's own
    /// off/on behaviour has its dedicated test below.
    fn vr_resolve(st: &State, statics: &[UnitStatic], action: &Action) -> State {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, action, &small_board(),
            Seams { movement: true, versatile_reach: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap()
        .0
    }

    /// The post-move base-edge gap of the charger vs its target, in inches.
    fn vr_gap(next: &State) -> f64 {
        geom::edge_gap_in(
            &next.positions[0], &next.radii[0], &next.positions[1], &next.radii[1],
            DEFAULT_BASE_RADIUS_M,
        )
    }


    /// A 6x4 ft school board (72" x 48"), the `terrain.rs` `school()` fixture's
    /// own shape, empty of cells — only `board_in` matters to `clamp_move_to_board`.
    fn small_board() -> crate::terrain::Terrain {
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![],
            sandbox: vec![],
            pieces: vec![],
            walls: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }


    /// Wave 4 — a one-model "Hit & Run" Boost carrier for the REAL `build_for`
    /// (the gf faction block whose mechanics entry fields the name), with the
    /// shoot key the action rides (`buff_action` fires the shot leg on the key
    /// alone — the same shape the 3" tests use).
    fn boost_carrier(system: &str, faction: &str, rules: &[&str]) -> crate::state::Profile {
        crate::state::Profile {
            unit_id: "u".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![crate::state::Weapon {
                name: "Rifle".into(),
                range: 24.0,
                attacks: 2,
                count: 1,
                ap: 0,
                rules: vec![],
            }],
            special_rules: rules.iter().map(|s| s.to_string()).collect(),
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: system.into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        }
    }

    /// The buff_line scene with the shooter slot swapped for the REAL
    /// `build_for` product of that carrier, patched down to the carrier's own
    /// single model.
    fn boost_line(
        system: &str,
        faction: &str,
        rules: &[&str],
        epoch: u32,
    ) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        let mut reg = crate::rules::Registries::new(&repo_root());
        statics[0] = UnitStatic::build_for(&mut reg, &boost_carrier(system, faction, rules), epoch);
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.radii[0] = vec![IN2M];
        st.wounds[0] = vec![1];
        st.alive[0] = 1;
        (st, statics)
    }

    /// S11 — the `forest_bar_board` forest mirrored onto the kiting side: unit
    /// 0's Hit & Run step runs from x≈0 straight to x≈-3" (away from "b" at
    /// x=12"), and cells (13,14)/(13,15) cover x in [-6",-3") — the corridor's
    /// far edge, the same near-landing relationship the S3 fixture has.
    fn kiting_forest_board() -> crate::terrain::Terrain {
        let cells = vec![[13.0, 14.0, crate::terrain::FOREST as f64],
                         [13.0, 15.0, crate::terrain::FOREST as f64]];
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells,
            sandbox: vec![],
            pieces: vec![],
            walls: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }





    /// Block B13 fixture — unit 0 a 3x1-wound striker (Quality 4, one melee
    /// profile), unit 1 the defender (3x1 wounds, Defense 4) carrying
    /// `def_retaliate` as its `retaliate_hits_per_wound` (0 = rule absent).
    fn duel(def_retaliate: i64) -> (State, Vec<UnitStatic>) {
        let blade = ShootProfile { name: "Blade".into(), attacks: 8, count: 1, range: 0, ..Default::default() };
        let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let statics = vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
                name: "Striker".into(),
                melee: vec![blade],
                model_count: 3,
                wounds_max: vec![1, 1, 1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 3, retaliate_hits_per_wound: def_retaliate, ..Default::default() },
                name: "Target".into(),
                model_count: 3,
                wounds_max: vec![1, 1, 1],
                ..Default::default()
            },
        ];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into()],
            index: HashMap::new(),
            profile: vec![0, 1],
        });
        st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![3, 3];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions[0] = vec![[0.0, 0.0, 0.0], [0.8, 0.0, 0.0], [1.2, 0.0, 0.0]];
        st.wounds[0] = vec![1, 1, 1];
        st.radii[0] = vec![IN2M, IN2M, IN2M];
        st.positions[1] = vec![[2.0, 0.0, 0.0], [3.0, 0.0, 0.0], [4.0, 0.0, 0.0]];
        st.wounds[1] = vec![1, 1, 1];
        st.radii[1] = vec![IN2M, IN2M, IN2M];
        (st, statics)
    }




    /// Block C5 fixture — unit 0 the 1-model Instinctive carrier (Quality 4,
    /// one 8-dice melee profile), unit 1 the target 10" away, unit 2 a SECOND
    /// enemy at `third_at` (9" = the forfeit case, 9.5" = the half-inch band's
    /// own boundary), unit 3 a far bystander so no per-unit vector moves.
    fn instinctive_line(third_at: f64) -> (State, Vec<UnitStatic>) {
        let blade = ShootProfile {
            name: "Blade".into(),
            attacks: 8,
            count: 1,
            range: 0,
            ..Default::default()
        };
        let profile: Profile =
            serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let statics = vec![
            UnitStatic {
                ctx: Ctx {
                    quality: 4,
                    defense: 4,
                    tough: 1,
                    models: 1,
                    instinctive_hit_bonus: 1,
                    ..Default::default()
                },
                name: "Striker".into(),
                melee: vec![blade],
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Target".into(),
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Rival".into(),
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
        ];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into(), "c".into(), "d".into()],
            index: HashMap::new(),
            profile: vec![0, 1, 2, 2],
        });
        st.profiles = Rc::new(Profiles {
            list: vec![profile.clone(), profile.clone(), profile.clone(), profile],
            index: HashMap::new(),
        });
        st.player = vec![0, 1, 1, 1];
        st.alive = vec![1, 1, 1, 1];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.positions[1] = vec![[10.0 * IN2M, 0.0, 0.0]];
        st.positions[2] = vec![[third_at, 0.0, 0.0]];
        st.positions[3] = vec![[20.0 * IN2M, 0.0, 0.0]];
        (st, statics)
    }

    /// The striker's first "attack" batch after one strike phase — the melee
    /// hit roll's modified target is the number the rule moves.
    fn striker_hit_target(third_at: f64) -> i64 {
        let (mut st, statics) = instinctive_line(third_at);
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        shot.rolls
            .iter()
            .find(|r| r.kind == "attack" && r.owner == "Striker")
            .expect("the striker's hit batch")
            .target
    }

    // ================================================ mutant-killing tests ====


    /// One bearer (unit 0, Breath Attack) facing two enemies on the x axis:
    /// "Alpha" (unit 1: 3 alive, Defense 3) and "Bravo" (unit 2: 2 alive,
    /// Defense 5); unit 3 is a dead bystander. Base-edge gaps 3" and 4", both
    /// inside the 6" breath range, LOS clear (`los_pairs` carries no matrix).
    /// Scores: Alpha `3 · 1/2 = 1.5`, Bravo `2 · 5/6 ≈ 1.67` — Bravo wins.
    fn breath_scorer_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.player = vec![0, 1, 1, 1];
        st.alive = vec![1, 3, 2, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.positions[1] = vec![[5.0 * IN2M, 0.0, 0.0]];
        st.positions[2] = vec![[6.0 * IN2M, 0.0, 0.0]];
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: HashMap::new(),
            profile: vec![0, 1, 2, 2],
        });
        let bearer = UnitStatic {
            name: "Bearer".into(),
            breath_attack_active: true,
            ..Default::default()
        };
        let alpha = UnitStatic {
            name: "Alpha".into(),
            ctx: Ctx { defense: 3, ..Default::default() },
            ..Default::default()
        };
        let bravo = UnitStatic {
            name: "Bravo".into(),
            ctx: Ctx { defense: 5, ..Default::default() },
            ..Default::default()
        };
        (st, vec![bearer, alpha, bravo])
    }

    /// Fires one breath activation at seed 5 (whose first face, the trigger
    /// die, is a 6) and reports who ate the save batch — the signature of the
    /// unit the scorer picked.
    fn breath_save_owner(statics: &[UnitStatic], st: &mut State) -> String {
        let mut shot = ShootResult::default();
        let mut tray = Tray::seeded(5);
        tray_breath_attack(statics, st, 0, Seams::default(), &mut tray, &mut shot);
        shot.rolls.iter().find(|r| r.kind == "defense")
            .map(|r| r.owner.clone())
            .unwrap_or_default()
    }


    /// A Hit & Run host (unit 0) with an enemy due south (unit 3, 9" centre
    /// to centre on the z axis) — the only live enemy, so the flee direction
    /// is exactly [0, -1] and the 3" step lands at z = -3" in metres.
    fn har_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.positions[3] = vec![[0.0, 0.0, 9.0 * IN2M]];
        let host = UnitStatic {
            name: "Fleer".into(),
            hit_and_run_active: true,
            ..Default::default()
        };
        (st, vec![host])
    }


    /// A carrier with NEITHER the full "Hit & Run" gate NOR a half set yet —
    /// enemy 9" due south (the flee anchor), same geometry as `har_line` — so
    /// each test turns on exactly one flag and one trigger side.
    fn hnr_half_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.positions[3] = vec![[0.0, 0.0, 9.0 * IN2M]];
        (st, vec![UnitStatic { name: "Kiter".into(), ..Default::default() }])
    }



    /// One four-unit line whose profile 0 carries a Growth Markers rule at
    /// the registry's two-rate shape and unit 0 holding `markers` markers.
    /// At 4 markers the exact bonus is ap `2·4 + 5·(4/2) = 18`, hit
    /// `1·4 + 3·(4/2) = 10`.
    fn growth_line(markers: i64) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.growth_markers = vec![markers, 0, 0, 0];
        let rule = GrowthRule {
            name: "Test Growth".into(),
            ap_per_marker: 2,
            ap_per_two: 5,
            hit_per_marker: 1,
            hit_per_two: 3,
            ..Default::default()
        };
        (st, vec![UnitStatic { growth: vec![rule], ..Default::default() }])
    }


    /// S10 fixture on the four-unit line: unit 0 "a" (player 0, one 24" gun)
    /// at (30", 24") on the 72x48 board, unit 2 "b" (player 1) 20" east, unit
    /// 3 out of the way, one neutral marker 5" east of "a".
    fn s10_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "ah".into(), "b".into(), "bh".into()],
            index: ["a", "ah", "b", "bh"]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.to_string(), i))
                .collect(),
            profile: vec![0, 0, 0, 0],
        });
        st.positions[0] = vec![[30.0 * IN2M, 0.0, 24.0 * IN2M]];
        st.positions[1] = vec![[30.0 * IN2M, 0.0, 30.0 * IN2M]];
        st.positions[2] = vec![[50.0 * IN2M, 0.0, 24.0 * IN2M]];
        st.positions[3] = vec![[2.0 * IN2M, 0.0, 46.0 * IN2M]];
        st.objectives =
            vec![crate::state::Objective { pos: [35.0 * IN2M, 0.0, 24.0 * IN2M], owner: -1 }];
        let mut shooter = UnitStatic { name: "a".into(), ..Default::default() };
        shooter.shoot =
            vec![ShootProfile { name: "gun".into(), range: 24, ..Default::default() }];
        (st, vec![shooter])
    }

    #[cfg(test)]
    mod los_model_tests {
        use super::*;
        use crate::terrain::{self, CellParams, Obb, PlainTerrain};

        fn at(x_in: f64, z_in: f64) -> [f64; 3] {
            [x_in * IN2M, 0.0, z_in * IN2M]
        }

        /// NML-1160's fixture, and the whole defect in one picture: a CONTAINER wall
        /// two cells tall (world cells (0,0) and (0,1), i.e. x in [0,3)" and z in
        /// [0,6)") with a two-model unit on each side. Both unit CENTRES sit at
        /// z = 5.25", behind the wall; the NORTH model of each sits at z = 9.0",
        /// with a clear lane past the wall's end. `SchoolTerrain.los_blocked` — the
        /// centre-to-centre probe self-play stamps into `los_pairs` — says blocked;
        /// `SoloController._has_los`, which is the ONLY sight test the table itself
        /// applies, says the shot is on.
        fn los_line() -> (State, Vec<UnitStatic>, Terrain) {
            let (mut st, mut statics) = buff_line();
            st.positions = vec![
                vec![at(-3.0, 1.5), at(-3.0, 9.0)],
                vec![],
                vec![at(6.0, 1.5), at(6.0, 9.0)],
                vec![],
            ];
            st.radii = vec![vec![0.016; 2], vec![], vec![0.016; 2], vec![]];
            st.wounds = vec![vec![1; 2], vec![], vec![1; 2], vec![]];
            st.alive = vec![2, 0, 2, 0];
            statics[2].model_count = 2;
            statics[2].wounds_max = vec![1, 1];
            statics[2].ctx.defense = 6; // the fixture has to LAND wounds to show one
            statics[0].shoot = vec![gun("Rifle", 20, 24)];
            let terrain = Terrain::build(&PlainTerrain {
                cells: vec![
                    [15.0, 15.0, terrain::CONTAINER as f64],
                    [15.0, 16.0, terrain::CONTAINER as f64],
                ],
                sandbox: Vec::<Obb>::new(),
                pieces: vec![],
                walls: vec![],
                cell_params: CellParams {
                    table_size_feet: [6.0, 4.0],
                    grid_rotation_degrees: 0.0,
                    grid_size_inches: 3.0,
                    inches_to_meters: IN2M,
                },
            });
            (st, statics, terrain)
        }

        fn shoot_at_b() -> Action {
            Action {
                kind: HOLD,
                unit: "a".into(),
                dest: None,
                shoot: Some("b".into()),
                charge: None,
                patient: false,
                split: None,
                traced: None,
            }
        }

        fn centre_matrix(st: &State, terrain: &Terrain) -> Vec<bool> {
            let n = st.units();
            let centres: Vec<V3> = (0..n).map(|i| geom::centre(&st.positions[i])).collect();
            let mut m = vec![true; n * n];
            for i in 0..n {
                for j in 0..n {
                    m[i * n + j] = !terrain.los_blocked(centres[i], centres[j]);
                }
            }
            m
        }

        fn run(st: &State, statics: &[UnitStatic], terrain: &Terrain, seams: Seams) -> State {
            let mut tray = Tray::seeded(11);
            let mut rng = GodotRng::new(0);
            resolve_stochastic_tray_on_board(statics, st, &shoot_at_b(), terrain, seams, &mut rng, &mut tray)
                .unwrap()
                .0
        }

        /// RED for the rung: the shot the table would take, refused by the coarse
        /// matrix and taken by the per-model one — on ONE state, with one knob
        /// between the two runs.
        #[test]
        fn a_model_lane_past_a_wall_is_a_shot_the_centre_probe_refuses() {
            let (st, statics, terrain) = los_line();
            let n = st.units();
            let coarse = centre_matrix(&st, &terrain);
            assert!(!coarse[2], "the fixture's wall has to block the centre line a -> b");
            let model = sight::sight_matrix(&st, &terrain);
            assert!(model[2] && model[2 * n], "one model on each side has a clear lane");

            // Knob OFF — `los_pairs` is the centre probe. `_los_clear` refuses and
            // the resolve leaves the target untouched: bit-identical to a HOLD.
            let mut dark = st.clone();
            dark.los_pairs = Some(Rc::new(coarse));
            let off = run(&dark, &statics, &terrain, Seams::default());
            assert_eq!(wounds_left(&off, 2), wounds_left(&dark, 2), "today the volley is dropped");

            // Knob ON — the same state, the same seed, the per-model matrix.
            let mut lit = st.clone();
            lit.los_pairs = Some(Rc::new(model));
            let on = run(&lit, &statics, &terrain, Seams { los_model: true, ..Seams::default() });
            assert!(wounds_left(&on, 2) < wounds_left(&lit, 2), "the lane the models have is a volley");
        }

        /// The guard on `refresh_los_pairs`: with `los_model` the per-model matrix
        /// survives a unit moving, because a clone inherits `su["los"]` untouched on
        /// the table too (`clone_state`, battle_sim.gd:1644-1651). Without the seam
        /// the mover's row and column are rewritten with the CENTRE probe — which on
        /// this fixture puts the coarse answer back one activation later.
        #[test]
        fn the_seam_stops_a_move_rewriting_the_matrix_with_the_centre_probe() {
            let (st, _statics, terrain) = los_line();
            let n = st.units();
            let mut parent = st.clone();
            parent.los_pairs = Some(Rc::new(sight::sight_matrix(&st, &terrain)));
            // One inch east, still behind the wall and still with the same lane.
            let mut moved = parent.clone();
            moved.positions[0] = vec![at(-2.0, 1.5), at(-2.0, 9.0)];

            let mut kept = moved.clone();
            refresh_los_pairs(&mut kept, &parent, &terrain, Seams { los_model: true, ..Seams::default() });
            assert!(kept.los_pairs.as_ref().unwrap()[2], "the per-model answer survives the move");
            assert!(kept.los_pairs.as_ref().unwrap()[2 * n], "and so does the reverse row");

            let mut coarse = moved.clone();
            refresh_los_pairs(&mut coarse, &parent, &terrain, Seams::default());
            assert!(!coarse.los_pairs.as_ref().unwrap()[2], "RED: without the seam it goes coarse");
            assert!(!coarse.los_pairs.as_ref().unwrap()[2 * n]);
        }
    }

// Per-family test modules (wave-4 layout): one file per family, so two
// family PRs in the same wave never append to the same region. A new
// family adds ONE line to this ALPHABETICAL list plus its own file; the
// fixtures every family shares stay here, in the module root.
mod breath_attack;
mod breath_score;
mod buff_consumption_bridge;
mod deathstrike;
mod dest_side_arms;
mod fold_gate_fixture;
mod growth_bonus_score;
mod growth_markers;
mod growth_markers_epoch6;
mod half_primitives;
mod hit_and_run;
mod hit_and_run_boost_band;
mod hit_and_run_score;
mod instinctive;
mod limited_weapons;
mod mark_consumers;
mod melee_reach_table;
mod mend;
mod piercing_tag;
mod plain_moves;
mod quick_shot;
mod reposition_artillery;
mod retaliate;
mod second_wind;
mod second_wind_score;
mod split_fire;
mod versatile_reach;
mod weapons;
