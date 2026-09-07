use super::*;

    // --------------------- wave 4 follow-up: Retreating Strike (Ravage alias) ---

    /// The registry-built bearer: an aof/dark_elves profile whose rules ride
    /// the REAL registry (`assets/solo/rules_mechanics_aof.json`, primitive
    /// "Ravage", param `trigger: "post_melee_move"`). The REAL `build_for`
    /// product, read at `epoch`.
    fn rs_bearer(rules_epoch: u32, rules: &[&str]) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: rules.iter().map(|r| r.to_string()).collect(),
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "aof".into(),
            faction_folder: "dark_elves".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// Bearer "a" in CONTACT with a one-model target "b" (2" centres, 1"
    /// radii): the `storm_line` shape shrunk to striking distance.
    fn rs_line(rules_epoch: u32, rules: &[&str]) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions[2] = vec![[2.0 * IN2M, 0.0, 0.0]];
        let bearer = rs_bearer(rules_epoch, rules);
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.ctx.quality = 4;
        b.ctx.defense = 4;
        b.ctx.tough = 1;
        (st, vec![bearer, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    fn run_rs_direct(st: &State, statics: &[UnitStatic], rules_epoch: u32) -> ShootResult {
        let mut next = st.clone();
        let mut tray = Tray::seeded(11);
        let mut shot = ShootResult::default();
        let seams = Seams { rules_epoch, ..Seams::default() };
        tray_retreating_strike(statics, &mut next, 0, seams, &mut tray, &mut shot);
        shot
    }

    /// The stamp: the REAL registry entry (primitive "Ravage", param
    /// `trigger: "post_melee_move"`) lands on the statics behind the FROZEN
    /// `EPOCH_7_TABLE_RULES`, with the RAW name's rating — the Boarding
    /// Attack upgrade prints `Retreating Strike(3)`.
    #[test]
    fn the_real_registry_stamps_retreating_strike_at_epoch_seven_not_six() {
        let on = rs_bearer(7, &["Retreating Strike(3)"]);
        assert_eq!(on.retreating_strikes.len(), 1, "epoch 7: the entry is stamped");
        let s = &on.retreating_strikes[0];
        assert_eq!(s.name, "Retreating Strike");
        assert_eq!(s.rating, 3, "the raw name's parenthesized rating");
        assert_eq!(s.trigger, "post_melee_move");
        let off = rs_bearer(6, &["Retreating Strike(3)"]);
        assert!(off.retreating_strikes.is_empty(), "epoch 6: the record predates the wave");
        // A bare name carries no rating — the resolver's maxi(.., 1) floor is
        // the handler's job (main.gd:5867).
        let bare = rs_bearer(7, &["Retreating Strike"]);
        assert_eq!(bare.retreating_strikes[0].rating, 0);
    }

    /// The handler: once per round, the nearest enemy within the 3" melee gap
    /// takes `maxi(rating,1) x alive` direct-wound dice at the shared Ravage
    /// 6+ (main.gd:5863-5871, roll kind "ravage"). The table's `Retreating
    /// Strike: ... strikes while retreating` line names the rule.
    #[test]
    fn the_strike_lashes_out_at_the_nearest_enemy_in_reach() {
        let (st, statics) = rs_line(7, &["Retreating Strike(3)"]);
        let shot = run_rs_direct(&st, &statics, 7);
        let die = shot
            .rolls
            .iter()
            .find(|r| r.kind == "ravage")
            .expect("one ravage batch on the tray");
        assert_eq!((die.count, die.target, die.owner.as_str()), (3, 6, "a"), "3 dice = rating 3 x 1 model");
        assert!(
            shot.log.iter().any(|l| l.contains("Retreating Strike") && l.contains("strikes while retreating")),
            "rules-must-log: the strike line names the rule -- got {:#?}",
            shot.log
        );

        // The gate: a rules_epoch-6 record (the fleet stamps 5 today) rolls
        // nothing.
        let shot6 = run_rs_direct(&st, &statics, 6);
        assert!(shot6.rolls.iter().all(|r| r.kind != "ravage"), "epoch 6: no strike");
        assert!(shot6.log.iter().all(|l| !l.contains("Retreating Strike")));
    }

    /// Once per round: a bearer whose stamp already carries this round draws
    /// no second batch (main.gd:5861/:5866).
    #[test]
    fn the_strike_is_once_per_round_per_bearer() {
        let (mut st, statics) = rs_line(7, &["Retreating Strike(3)"]);
        st.retreating_strike_round[0] = 0;
        let shot = run_rs_direct(&st, &statics, 7);
        assert!(shot.rolls.iter().all(|r| r.kind != "ravage"), "already struck this round");
    }

    /// Out of reach: the nearest enemy beyond the 3" melee gap takes nothing
    /// and the once-per-round is NOT spent (main.gd:5864-5865).
    #[test]
    fn no_enemy_in_reach_spends_nothing() {
        let (mut st, statics) = rs_line(7, &["Retreating Strike(3)"]);
        st.positions[2] = vec![[8.0 * IN2M, 0.0, 0.0]];
        let shot = run_rs_direct(&st, &statics, 7);
        assert!(shot.rolls.iter().all(|r| r.kind != "ravage"), "beyond 3\": no strike");
    }

    /// The trigger scope, ported as the table documents it (main.gd:5845-5848,
    /// :1095-1097): the strike fires ONLY on the automated post-MELEE Hit &
    /// Run step -- a carrier that actually steps rolls at its NEW position;
    /// the shooting leg never strikes. Integration through the real
    /// activation: charger in contact, Hit & Run steps it 3" away, the gap is
    /// exactly 3.0" and the strike fires.
    #[test]
    fn the_strike_fires_on_the_post_melee_hit_and_run_step() {
        let (mut st, statics) = rs_line(7, &["Hit & Run", "Retreating Strike(3)"]);
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch: 7, ..Seams::default() };
        let (_, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, seams, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(
            shot.rolls.iter().any(|r| r.kind == "ravage"),
            "post-melee step in reach: the strike fires -- got {:#?}",
            shot.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );

        // The shooting leg never strikes: a carrier that only SHOT and stepped
        // draws no ravage batch (main.gd:1096's `not can_shoot` gate).
        let (st0, statics0) = rs_line(7, &["Hit & Run", "Retreating Strike(3)"]);
        let shoot_act = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()),
            charge: None, patient: false, split: None, traced: None,
        };
        let mut tray0 = Tray::seeded(11);
        let mut rng0 = crate::rng::GodotRng::new(0);
        let (_, shot0) = resolve_stochastic_tray_on_board(
            &statics0, &st0, &shoot_act, &terrain, seams, &mut rng0, &mut tray0,
        )
        .unwrap();
        assert!(
            shot0.rolls.iter().all(|r| r.kind != "ravage"),
            "the shooting leg never strikes -- got {:#?}",
            shot0.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>()
        );
    }
