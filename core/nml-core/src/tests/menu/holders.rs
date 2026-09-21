use super::*;
    use crate::state::{Bands, Mods, MoveBands, Profile, Profiles, Roster};
    use std::collections::HashMap;
    use std::rc::Rc;

    // ---- Wave 6 (`lead/menutargets`) — the MENUHOLDERS menu leg: when
    //      `Tuning::holders` is on, the best-EV shoot target and the best
    //      charge victim among enemies that QUALIFY — `holder_or_unactivated`:
    //      any model within 3" of an objective not owned by the acting player,
    //      or not yet activated this round — are appended AFTER every existing
    //      entry, and only when they differ from the unqualified picks. Off =
    //      byte-identical menu. -------

    /// A three-unit line, one model each: unit 0 the gunner (player 0, a 24"
    /// rifle, no melee), unit 1 "Wall" (player 1, defense 6 — the HIGHER-EV
    /// shoot target, activated, 8" from the objective so it does NOT qualify),
    /// unit 2 "Squish" (player 1, defense 2 — the LOWER-EV target, also
    /// activated, standing ON the objective owned by its own side, so it
    /// qualifies through the 3" ring alone). The objective sits at unit 2's
    /// centre, 20" down the line — inside the rifle's reach, outside any
    /// charge reach the gunner has (none, melee being empty).
    fn holders_line() -> State {
        let n = 3;
        let gunner = Profile {
            unit_id: "g".into(),
            name: "Gunner".into(),
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
        let mut wall = gunner.clone();
        wall.unit_id = "w".into();
        wall.name = "Wall".into();
        let mut squish = gunner.clone();
        squish.unit_id = "s".into();
        squish.name = "Squish".into();
        let profiles = Rc::new(Profiles {
            list: vec![gunner, wall, squish],
            index: HashMap::new(),
        });
        let roster = Rc::new(Roster {
            keys: vec!["u0".into(), "u1".into(), "u2".into()],
            index: HashMap::new(),
            profile: vec![0, 1, 2],
        });
        let attached: Vec<Vec<usize>> = vec![vec![], vec![], vec![]];
        let mut attached_to = vec![None; n];
        for (host, hs) in attached.iter().enumerate() {
            for &h in hs {
                attached_to[h] = Some(host);
            }
        }
        State {
            roster,
            profiles,
            round: 0,
            rounds_total: 1,
            scoring: Rc::from(""),
            objectives: vec![crate::state::Objective {
                pos: [20.0 * IN2M, 0.0, 0.0],
                owner: 1,
            }],
            markers_meta: vec![],
            destroy_seq: vec![],
            vp: None,
            vp_flavour: None,
            vp_memo: None,
            cast_events: vec![],
            player: vec![0, 1, 1],
            alive: vec![1; n],
            activated: vec![false, true, true],
            shaken: vec![false; n],
            fatigued: vec![false; n],
            in_cover: vec![false; n],
            aircraft: vec![false; n],
            dormant: vec![false; n],
            dormant_models: vec![0; n],
            dormant_wounds: vec![Vec::new(); n],
            casts: vec![0; n],
            morale_bonus: vec![0; n],
            ambush_arrived_round: vec![-1; n],
            earliest_arrival_round: vec![-1; n],
            wound_frac: vec![1.0; n],
            wounds: vec![vec![1], vec![1], vec![1]],
            positions: vec![
                vec![[0.0, 0.0, 0.0]],
                vec![[12.0 * IN2M, 0.0, 0.0]],
                vec![[20.0 * IN2M, 0.0, 0.0]],
            ],
            radii: vec![vec![IN2M], vec![IN2M], vec![IN2M]],
            mods: vec![Mods::default(); n],
            mods_base: (0..n).map(|_| Rc::new(Mods::default())).collect(),
            attached: Rc::new(attached),
            attached_to: Rc::new(attached_to),
            los: vec![None; n],
            los_pairs: None,
            bands: vec![Bands::default(); n],
            shroud: vec![None; n],
            charge_no_difficult: vec![false; n],
            charge_probe_r: vec![0.0; n],
            buffs: (0..n).map(|_| Vec::new()).collect(),
            vs_mark_round: vec![-1; n],
            hit_and_run_round: vec![-1; n],
            moved_round: vec![-1; n],
            delayed_action_round: vec![-1; n],
            coordinate_via_round: vec![-1; n],
            reckless_rolled_round: vec![-1; n],
            reckless_ap_round: vec![-1; n],
            reckless_backfire_round: vec![-1; n],
            versatile_pick_round: vec![-1; n],
            versatile_pick_mode: vec![0; n],
            retreating_strike_round: vec![-1; n],
            growth_markers: vec![0; n],
            vengeance_markers: vec![0; n],
            growth_round: vec![-1; n],
            second_wind_used: vec![false; n], teleport_used: vec![false; n],
            reinforcement_used: vec![false; n],
            second_wind_round: -1,
            second_wind_uses: 0,
            sidestep_budget: Default::default(),
            limited_used: vec![Vec::new(); n],
            piercing_tag_used: vec![false; n],
            piercing_tag_markers: vec![0; n],
            spot_markers: vec![0; n],
            tag_markers: vec![0; n],
            spot_round: vec![-1; n],
            precision_used: vec![Vec::new(); n],
            storm_used: vec![Vec::new(); n],
            feats_used: vec![Vec::new(); n],
        }
    }

    /// One static per state unit: the gunner carries the rifle; "Wall" (defense
    /// 6) blocks MORE of the rifle's EV than "Squish" (defense 2), so the
    /// unqualified max-EV pick is "Wall" — the whole point of the fixture is
    /// that the QUALIFIED pick ("Squish") is a different unit.
    fn holders_statics() -> Vec<UnitStatic> {
        vec![
            UnitStatic {
                ctx: crate::unit::Ctx {
                    quality: 4, defense: 4, tough: 1, models: 1, ..Default::default()
                },
                name: "Gunner".into(),
                model_count: 1,
                shoot: vec![gun("Rifle", 1, 24)],
                ..Default::default()
            },
            UnitStatic {
                ctx: crate::unit::Ctx {
                    quality: 4, defense: 6, tough: 1, models: 1, ..Default::default()
                },
                name: "Wall".into(),
                model_count: 1,
                ..Default::default()
            },
            UnitStatic {
                ctx: crate::unit::Ctx {
                    quality: 4, defense: 2, tough: 1, models: 1, ..Default::default()
                },
                name: "Squish".into(),
                model_count: 1,
                ..Default::default()
            },
        ]
    }

    /// `Candidate` carries no `PartialEq`, so assertions compare the plain
    /// shape the GDScript candidate dict would carry: kind, shoot, charge,
    /// dest (exact — every dest here is a deterministic expression).
    /// (kind, shoot, charge, dest) — the menu entry as the assertions compare it.
    type Shape = (i64, Option<String>, Option<String>, Option<[f64; 3]>);
    fn shape(menu: &[Candidate]) -> Vec<Shape> {
        menu.iter()
            .map(|c| (c.kind, c.shoot.clone(), c.charge.clone(), c.dest))
            .collect()
    }

    fn gun(name: &str, attacks: i64, range: i64) -> ShootProfile {
        ShootProfile { name: name.into(), attacks, count: 1, range, ..Default::default() }
    }

    /// THE OFF MENU: `holders` off is EXACTLY today's menu — hold; hold + best
    /// shoot ("Wall", the higher-EV defense-6 target); rush to the objective;
    /// the retreat advance away from the nearest enemy; the safe advance
    /// toward it. No charge (the gunner has no melee), no second wave, no wide
    /// shoot, no teleport.
    #[test]
    fn holders_off_menu_is_unchanged() {
        let st = holders_line();
        let statics = holders_statics();
        let mut sc = Scratch::default();
        let menu = candidates_tuned(
            &st, &Terrain::default(), &statics, 0, &mut sc, Tuning::default(),
        );
        let s = shape(&menu);
        assert_eq!(s.len(), 5, "the pinned OFF menu: {:?}", s);
        assert_eq!(s[0], (HOLD, None, None, None));
        assert_eq!(s[1], (HOLD, Some("u1".into()), None, None), "the max-EV pick is the defense-6 target");
        assert_eq!(s[2], (RUSH, None, None, Some([20.0 * IN2M, 0.0, 0.0])), "the rush goal is the objective");
        assert_eq!(s[3].0, ADVANCE, "the retreat advance: {:?}", s[3]);
        assert_eq!(s[4].0, ADVANCE, "the safe advance: {:?}", s[4]);
    }

    /// THE LEG: `holders` on adds ONE entry at the tail — a HOLD carrying the
    /// best shoot among QUALIFYING enemies ("Squish", on the enemy-owned
    /// objective), because that pick differs from the unqualified one. No
    /// charge entry: the gunner has no melee, so the qualified
    /// `best_charge` answers None exactly like the unqualified one.
    #[test]
    fn holders_on_appends_the_qualified_shoot_target() {
        let st = holders_line();
        let statics = holders_statics();
        let tuning = Tuning { holders: true, ..Tuning::default() };
        let mut sc = Scratch::default();
        let off = candidates_tuned(&st, &Terrain::default(), &statics, 0, &mut sc, Tuning::default());
        let mut sc = Scratch::default();
        let on = candidates_tuned(&st, &Terrain::default(), &statics, 0, &mut sc, tuning);
        let mut expected = shape(&off);
        expected.push((HOLD, Some("u2".into()), None, None));
        assert_eq!(shape(&on), expected, "ON = OFF + one qualified HOLD+shoot at the tail");
    }