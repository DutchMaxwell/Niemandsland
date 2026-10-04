use super::*;

    // ------------------- audit 2026-09-13 §2.1: Deadly lands PER MODEL ------

    // The audit board (analysis/RULE_FIDELITY_AUDIT_2026-09-13.md §2.1): a
    // 3-model Tough(3) unit with wounds remaining [3, 1, 1] takes 2 unsaved
    // wounds from a Deadly(3) weapon. The book (GF v3.5.1 p.14, `gf/_common.json`)
    // assigns each wound to one model, multiplies THERE, and the surplus does
    // not carry over; the table plays it that way
    // (`SoloController.apply_deadly_wounds`, solo_controller.gd:8333-8352):
    // 3 absorbed on the first model, 1 on the next — TWO models die, ONE
    // survives, still holding its objective. The core multiplied at the POOL
    // level (dice.rs save_batch `unsaved * mult` against the unit's printed
    // Tough) and let `land_wounds` spill the 6 onto every model — the unit was
    // wiped. This test pins the core's outcome to the table's.

    /// The audit board: attacker "a" (1 model, one Deadly(3) rifle, 2 attacks,
    /// Quality 2+, AP(2)) vs defender "b" (3 models, printed Tough(3), Defense
    /// 4) 5" apart on the plain line. State wounds [3, 1, 1]: the first model
    /// fresh, the other two each down to 1.
    fn deadly_line() -> (State, Vec<UnitStatic>) {
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
        st.wounds = vec![vec![1], vec![], vec![3, 1, 1], vec![]];
        st.alive = vec![1, 0, 3, 0];
        let mut a = UnitStatic { name: "a".into(), ..Default::default() };
        a.model_count = 1;
        a.wounds_max = vec![1];
        a.ctx.quality = 2;
        a.ctx.defense = 4;
        a.shoot = vec![ShootProfile {
            name: "Deadly rifle".into(),
            attacks: 2,
            count: 1,
            range: 24,
            ap: 2,
            deadly: 3,
            ..Default::default()
        }];
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.model_count = 3;
        b.wounds_max = vec![3, 3, 3];
        b.ctx.defense = 4;
        b.ctx.tough = 3;
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

    /// One HOLD+shoot activation on the tray path (the `run_shoot` shape); the
    /// epoch picks the Deadly gate's leg (14 = per model, 13 = pooled legacy).
    fn run_shoot(st: &State, statics: &[UnitStatic], seed: i64, rules_epoch: u32) -> (State, ShootResult) {
        let action = Action {
            kind: HOLD,
            unit: "a".into(),
            dest: None,
            shoot: Some("b".into()),
            charge: None,
            patient: false,
            split: None,
            traced: None,
            teleport: None,
        };
        let terrain = Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    /// The audit board on the tray, at `EPOCH_14_DEADLY_LANDING`. Seed 2 draws
    /// [5, 4] on the attack roll (Quality 2+ -> 2 hits) and [1, 3] on the save
    /// batch (target 6 -> both fail): exactly 2 unsaved wounds into the
    /// Deadly(3) weapon.
    #[test]
    fn deadly_wounds_do_not_carry_onto_the_next_model() {
        let (st, statics) = deadly_line();
        let (next, shot) = run_shoot(&st, &statics, 2, 14);
        // The stream: one attack roll of 2 at Quality 2+, one save batch of 2
        // at Defense 4 + AP(2) = 6 — exactly the two draws, nothing pooled.
        let atk: Vec<_> = shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "a").collect();
        assert_eq!(
            (atk.len(), atk[0].count, atk[0].target),
            (1, 2, 2),
            "fixture: the volley draws 2 attack dice at 2+: {:?}",
            shot.rolls
        );
        let save: Vec<_> = shot.rolls.iter().filter(|r| r.kind == "defense").collect();
        assert_eq!(
            (save.len(), save[0].count, save[0].target),
            (1, 2, 6),
            "fixture: one save batch of 2 at 6+: {:?}",
            shot.rolls
        );
        // The tally is the RAW unsaved count (the table's shooting tally,
        // `total_caused += w`, main.gd:3318).
        assert_eq!(shot.caused, 2, "2 unsaved, the raw count: {:?}", shot.rolls);
        // THE DEFECT: the book and the table absorb 3 on the first model and 1
        // on the next — two models die, ONE survives. The pool multiply wiped
        // all three.
        assert_eq!(
            next.alive[2], 1,
            "the table leaves ONE model standing: alive {:?}, wounds {:?}",
            next.alive, next.wounds
        );
        assert_eq!(
            next.wounds[2], vec![1],
            "the survivor is the third model at its 1 remaining wound: {:?}",
            next.wounds
        );
        // Rules-must-log: the applied rule names itself, the table's own line
        // (main.gd:6778).
        assert!(
            shot.log.iter().any(|l| l.contains("Deadly(3): 2 unsaved ×3") && l.contains("no carry-over")),
            "the Deadly landing names itself: {:?}",
            shot.log
        );
    }

    /// THE OLD LEG, pinned (the gate discipline): the same board at epoch 13 —
    /// one below the gate — keeps the POOL multiply verbatim. The 2 unsaved
    /// become 6 pooled wounds and `land_wounds` spills them: the unit is wiped
    /// and the tally is the multiplied 6. Same seed, same stream — only the
    /// leg differs.
    #[test]
    fn at_epoch_13_the_pool_multiply_still_wipes_the_unit() {
        let (st, statics) = deadly_line();
        let (next, shot) = run_shoot(&st, &statics, 2, 13);
        assert_eq!(shot.caused, 6, "2 unsaved × Deadly(3), the pooled tally");
        assert_eq!(
            (shot.rolls[0].count, shot.rolls[1].count),
            (2, 2),
            "the stream is identical on both legs: {:?}",
            shot.rolls
        );
        assert_eq!(next.alive[2], 0, "the legacy leg wipes the unit: wounds {:?}", next.wounds);
        assert!(
            !shot.log.iter().any(|l| l.contains("no carry-over")),
            "the legacy leg has no Deadly landing line: {:?}",
            shot.log
        );
    }

    // --------------------- D17, EPOCH_67_MARKERS_BURSTS: host/hero + Tough --

    /// `land_deadly_wounds` called directly (it is `pub`, this module's own
    /// `use super::*`) — no attacker fixture needed, the algorithm is the unit
    /// under test. "a" (host): model 0 a FRESH Tough(1) body, model 1 a FRESH
    /// Tough(3) team member; "ah" (joined hero, `four_unit_line`'s own
    /// attachment): one Tough(1) model.
    fn deadly_chain() -> State {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions[0] = vec![[0.0, 0.0, 0.0], [0.02 * IN2M, 0.0, 0.0]];
        st.wounds[0] = vec![1, 3];
        st.radii[0] = vec![IN2M; 2];
        st.alive[0] = 2;
        st.positions[1] = vec![[2.0 * IN2M, 0.0, 0.0]];
        st.wounds[1] = vec![1];
        st.radii[1] = vec![IN2M];
        st.alive[1] = 1;
        st.profiles = Rc::new(Profiles {
            list: vec![
                Profile { wounds_max: vec![1, 3], model_count: 2, ..host_profile("a") },
                Profile { wounds_max: vec![1], model_count: 1, ..host_profile("ah") },
                Profile { wounds_max: vec![], model_count: 0, ..host_profile("b") },
                Profile { wounds_max: vec![], model_count: 0, ..host_profile("bh") },
            ],
            index: HashMap::new(),
        });
        st
    }

    fn host_profile(id: &str) -> Profile {
        Profile {
            unit_id: id.into(), name: id.into(), quality: 4, defense: 4, tough: 1,
            wounds_max: vec![], model_count: 1, weapons: vec![], special_rules: vec![],
            caster_value: 0, base_radius: 0.0, base_shape: String::new(), base_w_mm: 0.0,
            base_d_mm: 0.0, game_system: String::new(), faction_folder: String::new(),
            item_grants: vec![], attached_hero_rules: vec![], move_bands: MoveBands::default(),
        }
    }

    /// D17 (a) leg 1 — with NEITHER host model already wounded, a Deadly(3)
    /// wound falls to `land_wounds`'s own slot order (index 0 = the Tough(1)
    /// body), not the model with the most remaining wounds: the body dies
    /// instead of the fresh Tough(3) team member taking a 3-wound bite. Below
    /// the gate the OLD reading still picks the team (most remaining wounds).
    #[test]
    fn a_deadly_wound_lands_on_the_body_not_a_fresh_tough_team_member_from_epoch_67() {
        let mut st67 = deadly_chain();
        let s67 = Seams { rules_epoch: crate::acts::EPOCH_67_MARKERS_BURSTS, hero_attach: true, ..Seams::default() };
        let dealt = land_deadly_wounds(&mut st67, 0, 1, 3, s67);
        assert_eq!(dealt, 1, "capped at the body's own 1 remaining wound: {:?}", st67.wounds);
        assert_eq!(st67.wounds[0], vec![3], "the body died, the team member stands untouched: {:?}", st67.wounds);
        assert_eq!(st67.alive[0], 1);

        let mut st66 = deadly_chain();
        let s66 = Seams { rules_epoch: crate::acts::EPOCH_66_DISTANCE_TRUTH, hero_attach: true, ..Seams::default() };
        let dealt66 = land_deadly_wounds(&mut st66, 0, 1, 3, s66);
        assert_eq!(dealt66, 3, "below the gate: the OLD 'most remaining wounds' pick hits the team for all 3: {:?}", st66.wounds);
        assert_eq!(st66.wounds[0], vec![1], "the team died (3-3=0, removed), the body stands: {:?}", st66.wounds);
    }

    /// D17 (a) leg 2 — an ALREADY-WOUNDED Tough slot (here the team member, one
    /// wound already taken, current < max) is finished off before a FRESH slot
    /// even when the fresh one sits earlier in the array (the tie the old
    /// array-order pick would have resolved the other way); once the whole
    /// host chain is dead the leftover wound reaches the joined hero instead
    /// of being wasted (p.15 "heroes must be assigned wounds last").
    #[test]
    fn an_already_wounded_tough_slot_is_finished_first_then_the_leftover_reaches_the_hero() {
        let mut st = deadly_chain();
        st.wounds[0] = vec![1, 1]; // body still at its 1, the team already down to 1 of 3
        let s = Seams { rules_epoch: crate::acts::EPOCH_67_MARKERS_BURSTS, hero_attach: true, ..Seams::default() };

        // Wound 1: the DAMAGED team member (index 1), not the fresh-tied body at index 0.
        assert_eq!(land_deadly_wounds(&mut st, 0, 1, 1, s), 1);
        assert_eq!(st.wounds[0], vec![1], "the team died, only the body remains: {:?}", st.wounds);
        assert_eq!(st.alive[0], 1);

        // Wound 2: the body, the only host model left — the host chain is now wiped.
        assert_eq!(land_deadly_wounds(&mut st, 0, 1, 1, s), 1);
        assert_eq!(st.wounds[0], Vec::<i64>::new());
        assert_eq!(st.alive[0], 0, "the host is fully wiped: {:?}", st.wounds);
        assert_eq!(st.alive[1], 1, "the hero is untouched so far: {:?}", st.wounds);

        // Wound 3: nothing left in the host — the joined hero takes it (never wasted).
        assert_eq!(land_deadly_wounds(&mut st, 0, 1, 1, s), 1);
        assert_eq!(st.alive[1], 0, "the leftover wound reached the hero instead of being wasted");

        // Wound 4: the whole chain is dead now — wasted, not an error.
        assert_eq!(land_deadly_wounds(&mut st, 0, 1, 1, s), 0);
    }

    /// B8 (stage-0 freeze 02.10., row T_c4_L_d0_s2): a joined hero that holds a
    /// WOUND slot but no POSITION — the trainer's arena fold below
    /// `EPOCH_69_HERO_FOLD` built exactly that for the hero of an Ambush host.
    /// The host chain is wiped, the Deadly wound spills onto the ghost hero and
    /// `positions.remove` on the empty vector panicked the whole process. The
    /// guard drops the wound slot, removes no position, and COUNTS the desync
    /// (the stderr line rides on the same counter) — it never panics.
    #[test]
    fn a_deadly_spill_onto_a_hero_without_positions_logs_instead_of_panicking() {
        let mut st = deadly_chain();
        st.wounds[0] = vec![];
        st.positions[0] = vec![];
        st.radii[0] = vec![];
        st.alive[0] = 0;
        st.positions[1] = vec![];
        st.radii[1] = vec![];
        st.alive[1] = 0; // the ghost: wounds [1], no model on the table
        let s = Seams { rules_epoch: crate::acts::EPOCH_67_MARKERS_BURSTS, hero_attach: true, ..Seams::default() };
        let before = crate::sim::DESYNC_HITS.load(std::sync::atomic::Ordering::Relaxed);
        land_deadly_wounds(&mut st, 0, 1, 3, s);
        assert_eq!(st.wounds[1], Vec::<i64>::new(), "the ghost's wound slot is spent: {:?}", st.wounds);
        assert_eq!((st.positions[1].len(), st.alive[1]), (0, 0));
        assert!(
            crate::sim::DESYNC_HITS.load(std::sync::atomic::Ordering::Relaxed) > before,
            "the guard must log the desync, never hide it"
        );
    }

    /// Stage-0 P9 (the tray controls, freeze report B10): under
    /// `TreeDice::Tray` the tree declines on ANY `unported` flag (tree.rs
    /// `transition` / `playout`), and every Deadly activation was flagged
    /// `deadly` although the per-model landing above IS the table's
    /// `apply_deadly_wounds` from `EPOCH_14_DEADLY_LANDING` — so every L_tray /
    /// T_tray pick of a Deadly army declined. From 14 neither leg (volley,
    /// melee) flags it; below 14 the pooled multiply is a real divergence and
    /// still does. The landed state stays one model list per unit.
    #[test]
    fn a_per_model_deadly_activation_is_ported_so_the_tray_tree_takes_it() {
        let (mut st, mut statics) = deadly_line();
        // The live epoch's landing reads `Profile::wounds_max` (the epoch-67 leg, `deadly_chain`'s note).
        st.profiles = Rc::new(Profiles {
            list: vec![
                Profile { wounds_max: vec![1], ..host_profile("a") },
                host_profile("ah"),
                Profile { wounds_max: vec![3, 3, 3], model_count: 3, ..host_profile("b") },
                host_profile("bh"),
            ],
            index: HashMap::new(),
        });
        statics[0].melee = vec![ShootProfile {
            name: "Deadly blade".into(), attacks: 4, count: 1, ap: 2, deadly: 3, ..Default::default()
        }];
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None, charge: Some("b".into()),
            patient: false, split: None, traced: None, teleport: None,
        };
        let mut near = st.clone(); // the charge fixtures' 2.5" (buff_consumption_bridge.rs)
        near.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0], [2.52 * IN2M, 0.0, 0.0], [2.54 * IN2M, 0.0, 0.0]];
        let fight = |rules_epoch: u32| {
            let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(2));
            let seams = Seams { rules_epoch, ..Seams::default() };
            resolve_stochastic_tray_on_board(&statics, &near, &charge, &Terrain::default(), seams, &mut rng, &mut tray)
                .unwrap()
        };
        let one_list = |s: &State| {
            (0..s.units()).all(|u| s.wounds[u].len() == s.positions[u].len() && s.alive[u] as usize == s.positions[u].len())
        };
        for epoch in [crate::acts::EPOCH_14_DEADLY_LANDING, crate::acts::CURRENT_RULES_EPOCH] {
            let (next, shot) = run_shoot(&st, &statics, 2, epoch);
            assert!(shot.deadly_tally > 0, "epoch {epoch}: the volley landed Deadly wounds: {:?}", shot.rolls);
            assert!(shot.unported.is_empty() && one_list(&next), "epoch {epoch} volley: {:?}", shot.unported);
            let (next, melee) = fight(epoch);
            assert!(melee.deadly_tally > 0, "epoch {epoch}: the charge landed Deadly wounds: {:?}", melee.rolls);
            assert!(melee.unported.is_empty() && one_list(&next), "epoch {epoch} melee: {:?}", melee.unported);
        }
        assert!(run_shoot(&st, &statics, 2, 13).1.unported.contains(&"deadly"), "legacy volley leg flags");
        assert!(fight(13).1.unported.contains(&"deadly"), "legacy melee leg flags");
    }

    /// Tray-exact S1b: every casualty writer keeps `kits` slot-aligned with `positions` and
    /// takes the DYING model's kit (told apart here by `wounds_max`): land_wounds' slot 0,
    /// land_deadly_wounds' pick, and a withdraw that empties the unit.
    #[test]
    fn every_casualty_takes_its_own_kit_and_the_lists_stay_aligned() {
        let kit = |wmax: i64| crate::state::Kit { weapons: vec![0], equipment: 0, wounds_max: wmax };
        let mut st = deadly_chain();
        st.kits = vec![Rc::new(vec![kit(1), kit(3)]), Rc::new(vec![kit(7)])];
        let aligned = |st: &State| (0..2).all(|u| st.kits[u].len() == st.positions[u].len());
        land_wounds(&mut st, 0, 1); // slot 0 (the Tough(1) body) dies
        assert!(aligned(&st), "{:?}", st.kits);
        assert_eq!(st.kits[0].iter().map(|k| k.wounds_max).collect::<Vec<_>>(), vec![3]);
        let s = Seams { rules_epoch: crate::acts::EPOCH_67_MARKERS_BURSTS, hero_attach: true, ..Seams::default() };
        land_deadly_wounds(&mut st, 0, 1, 3, s); // the Tough(3) member, then nothing left in the host
        assert!(aligned(&st) && st.kits[0].is_empty(), "{:?}", st.kits);
        crate::deployment::withdraw_as_destroyed(&mut st, 1, 1);
        assert!(aligned(&st) && st.kits[1].is_empty(), "{:?}", st.kits);
    }

    /// Tray-exact S7: a Takedown weapon (here also Deadly(3)) resolves as a unit of [1] against the
    /// target's MOST VALUABLE model (`casualty_order(..).last()`, the table's `attacker_pick_target`):
    /// w x 3 lands on that one model, overkill lost, so one model dies however many wounds go
    /// through. Without the switch the same unsaved wounds land per model and kill one each.
    #[test]
    fn a_takedown_volley_kills_only_the_picked_model_with_tray_exact() {
        let (mut st, mut statics) = deadly_line();
        (statics[0].shoot[0].takedown, statics[0].shoot[0].attacks) = (true, 6);
        (st.wounds[2], statics[2].wounds_max) = (vec![1, 1, 1], vec![1, 1, 1]);
        st.profiles = Rc::new(Profiles {
            list: vec![
                Profile { wounds_max: vec![1], ..host_profile("a") },
                host_profile("ah"),
                Profile { wounds_max: vec![1, 1, 1], model_count: 3, ..host_profile("b") },
                host_profile("bh"),
            ],
            index: HashMap::new(),
        });
        let k = |w: u16| crate::state::Kit { weapons: vec![w], equipment: 0, wounds_max: 1 };
        st.kits = vec![Rc::new(vec![]), Rc::new(vec![]), Rc::new(vec![k(1), k(0), k(0)])]; // slot 0 = launcher
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let shoot = |tray_exact: bool| {
            let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(2));
            let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact, ..Seams::default() };
            resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut rng, &mut tray).unwrap()
        };
        let (next, shot) = shoot(true);
        assert!(shot.deadly_tally >= 2, "fixture: at least two unsaved: {:?}", shot.rolls);
        assert_eq!(next.alive[2], 2, "one model, however many wounds: {:?}", next.wounds);
        assert_eq!(next.kits[2].iter().map(|k| k.weapons[0]).collect::<Vec<_>>(), vec![0, 0], "the launcher was picked");
        assert!(shot.log.iter().any(|l| l.starts_with("Takedown:")), "{:?}", shot.log);
        assert!(shoot(false).0.alive[2] < 2, "without the switch each unsaved Deadly wound takes a model");
    }

    /// Tray-exact S9: the melee twin — a charging Takedown blade (Deadly(3)) lands on the target's
    /// most valuable model only (main.gd:7275-7283), Takedown first, overkill lost. Without the
    /// switch each unsaved Deadly wound takes a model.
    #[test]
    fn a_takedown_charge_kills_only_the_picked_model_with_tray_exact() {
        let (mut st, mut statics) = deadly_line();
        statics[0].melee = vec![ShootProfile {
            name: "Takedown blade".into(), attacks: 6, count: 1, deadly: 3, takedown: true, ..Default::default()
        }];
        (st.wounds[2], statics[2].wounds_max) = (vec![1, 1, 1], vec![1, 1, 1]);
        st.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0], [2.52 * IN2M, 0.0, 0.0], [2.54 * IN2M, 0.0, 0.0]];
        st.profiles = Rc::new(Profiles {
            list: vec![
                Profile { wounds_max: vec![1], ..host_profile("a") },
                host_profile("ah"),
                Profile { wounds_max: vec![1, 1, 1], model_count: 3, ..host_profile("b") },
                host_profile("bh"),
            ],
            index: HashMap::new(),
        });
        let k = |w: u16| crate::state::Kit { weapons: vec![w], equipment: 0, wounds_max: 1 };
        st.kits = vec![Rc::new(vec![]), Rc::new(vec![]), Rc::new(vec![k(1), k(0), k(0)])]; // slot 0 = launcher
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None, charge: Some("b".into()),
            patient: false, split: None, traced: None, teleport: None,
        };
        let fight = |tray_exact: bool| {
            let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(2));
            let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact, ..Seams::default() };
            resolve_stochastic_tray_on_board(&statics, &st, &charge, &Terrain::default(), seams, &mut rng, &mut tray).unwrap()
        };
        let (next, shot) = fight(true);
        assert!(shot.deadly_tally >= 2, "fixture: at least two unsaved: {:?}", shot.rolls);
        assert_eq!(next.alive[2], 2, "one model, however many wounds: {:?}", next.wounds);
        assert_eq!(next.kits[2].iter().map(|k| k.weapons[0]).collect::<Vec<_>>(), vec![0, 0], "the launcher was picked");
        assert!(shot.log.iter().any(|l| l.starts_with("Takedown:")), "{:?}", shot.log);
        assert!(fight(false).0.alive[2] < 2, "without the switch each unsaved Deadly wound takes a model");
    }

