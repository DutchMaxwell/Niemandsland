use super::super::*;
    use std::collections::HashMap;
    use std::rc::Rc;

    // ---- SHO-01a: an Indirect weapon fires without line of sight only after a Hold ----

    /// One 24" Indirect mortar (the mark_consumers mortar fixture), its static built off the
    /// mechanics maps under `root` at `epoch`; `rules` are the unit's own special rules.
    fn sho01_mortar(root: &str, rules: &str, epoch: u32) -> Vec<crate::unit::ShootProfile> {
        let header = format!(
            r#"{{"kind":"header","knobs":{{}},"profiles":{{
          "carrier":{{"unit_id":"carrier","name":"Carrier","quality":4,
            "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
            "base_radius":0.016,"game_system":"gf","faction_folder":"testfac",
            "special_rules":[{rules}],"item_grants":[],
            "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
            "weapons":[{{"name":"Mortar","range":24,"attacks":1,"count":1,"ap":0,
              "rules":["Indirect"]}}]}}}}}}"#
        );
        let parsed = crate::acts::read_act_header(&header).expect("header parses");
        let mut reg = crate::rules::Registries::new(root);
        let p = parsed.profiles.get("carrier").expect("carrier");
        crate::unit::UnitStatic::build_for(&mut reg, p, epoch).shoot
    }

    /// "a" fires `shoot` at "b" after a `kind` action (an Advance steps 1" away first), with the
    /// a -> b sight blocked in the recorded matrix and the split aim the table recorded; true when
    /// the volley rolled an attack die.
    fn sho01_fires(shoot: Vec<crate::unit::ShootProfile>, kind: i64, epoch: u32) -> bool {
        let (mut st, mut statics) = buff_line();
        let mut dark = vec![true; 16];
        dark[2] = false; // los_pairs[0*4+2] — a does not see b, but sees bh
        st.los_pairs = Some(Rc::new(dark));
        st.alive[3] = 1;
        st.positions[3] = vec![[6.0 * IN2M, 0.0, 0.0]];
        Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
        st.wounds[3] = vec![1];
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        statics[0].shoot = shoot;
        let mut act = buff_action(Some("bh"));
        act.kind = kind;
        if kind == ADVANCE {
            act.dest = Some([-IN2M, 0.0, 0.0]);
        }
        act.split = Some(vec![crate::io::SplitShot {
            member: "a".into(), weapon: "Mortar".into(), target: "b".into(),
        }]);
        let seams = Seams { sighting: true, moved_shoot: true, rules_epoch: epoch, ..Default::default() };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_, shot) = resolve_stochastic_tray_on_board(&statics, &st, &act, &terrain, seams, &mut rng, &mut tray)
            .expect("the volley resolves");
        shot.rolls.iter().any(|r| r.kind == "attack" && r.count == 1)
    }

    /// The temp mechanics map for the lift: "Indirect" asks for Hold, and a faction rule of the
    /// Indirect family prints the key false (the shape SHO-03's Quick Throw entry will take).
    fn sho01_lift_root() -> String {
        let dir = std::env::temp_dir().join(format!("nml_sho01_lift_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let map_dir = dir.join("assets/solo");
        std::fs::create_dir_all(&map_dir).expect("temp map dir");
        let body = r#"{"common":{"Indirect":{"primitive":"Indirect","rated":false,"book_version":"3.6.0",
          "params":{"moved_hit_penalty":1,"ignores_cover":true,"ignores_los":true,"hold_and_shoot":true,
          "los_needs_hold":true}}},"factions":{"testfac":{"Lift Drill":{"primitive":"Indirect","rated":false,
          "book_version":"3.6.0","params":{"los_needs_hold":false}}}}}"#;
        std::fs::write(map_dir.join("rules_mechanics_gf.json"), body).expect("write temp mechanics map");
        dir.to_string_lossy().into_owned()
    }

    /// RED on main: a mortar that Advanced still fired at the unseen target. At epoch 73 the
    /// shipped "Indirect" entry asks for Hold, so the moved shot needs line of sight.
    #[test]
    fn an_advanced_indirect_shooter_needs_line_of_sight_at_epoch_73() {
        let shoot = sho01_mortar(&repo_root(), "", crate::acts::EPOCH_73_V36);
        assert!(!sho01_fires(shoot, ADVANCE, crate::acts::EPOCH_73_V36),
            "an Advance gives up the Indirect sight waiver from epoch 73 (RED on main: it still fires)");
    }

    /// The old leg: under the 3.5 rules a moved Indirect shooter keeps the waiver.
    #[test]
    fn an_advanced_indirect_shooter_keeps_the_waiver_at_epoch_72() {
        let shoot = sho01_mortar(&repo_root(), "", crate::acts::EPOCH_72_PLAYTEST_RULES);
        assert!(sho01_fires(shoot, ADVANCE, crate::acts::EPOCH_72_PLAYTEST_RULES),
            "epoch 72 replays the 3.5 waiver for a moved Indirect shooter");
    }

    /// A Hold keeps the waiver at epoch 73 (control: passes with and without the change).
    #[test]
    fn a_holding_indirect_shooter_keeps_the_waiver_at_epoch_73() {
        let shoot = sho01_mortar(&repo_root(), "", crate::acts::EPOCH_73_V36);
        assert!(sho01_fires(shoot, HOLD, crate::acts::EPOCH_73_V36), "Hold earns the Indirect sight waiver");
    }

    /// An Indirect-family unit rule that prints `los_needs_hold: false` lifts the Hold need, so
    /// SHO-03 is a map entry and nothing else (control: passes with and without the change).
    #[test]
    fn a_unit_rule_printing_los_needs_hold_false_lifts_the_hold_need_at_epoch_73() {
        let shoot = sho01_mortar(&sho01_lift_root(), r#""Lift Drill""#, crate::acts::EPOCH_73_V36);
        assert!(sho01_fires(shoot, ADVANCE, crate::acts::EPOCH_73_V36), "the lift keeps the waiver after an Advance");
    }

    /// SHO-01a pin: the advance-and-shoot aim (`best_shoot_from`, the ADVANCE row's shot) gates on
    /// the recorded sight rows and never waives them for an Indirect gun, so the menu cannot plan a
    /// moved Indirect shot at an unseen enemy - the 3.6 Hold rule needs no menu change.
    #[test]
    fn the_advance_shoot_aim_never_picks_an_unseen_enemy_for_an_indirect_gun() {
        let mut st = crate::sim::tests::four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.profiles = Rc::new(crate::state::Profiles {
            list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new(),
        });
        let mortar = crate::unit::ShootProfile {
            name: "Mortar".into(), attacks: 3, count: 1, range: 24, indirect: true,
            indirect_ignores_los: Some(true), ..Default::default()
        };
        let mut a = crate::unit::UnitStatic { name: "a".into(), model_count: 1, shoot: vec![mortar], ..Default::default() };
        a.ctx.quality = 4;
        a.ctx.tough = 1;
        a.ctx.models = 1;
        let mut b = crate::unit::UnitStatic { name: "b".into(), model_count: 1, ..Default::default() };
        b.ctx.defense = 4;
        b.ctx.tough = 1;
        b.ctx.models = 1;
        let statics = vec![a, crate::unit::UnitStatic::default(), b, crate::unit::UnitStatic::default()];
        st.alive[3] = 0; // b's joined hero is gone: b is the only enemy
        let moved = st.positions[0].clone();
        let mut sc = Scratch::default();
        let seen = crate::menu::best_shoot_from(&st, &statics, 0, &moved, &mut sc, crate::menu::Tuning::default());
        assert_eq!(seen, Some(2), "control: with sight the mortar aims at b");
        st.los[0] = Some(Rc::new(HashMap::from([("b".to_string(), false)])));
        st.rebuild_sees();
        let blind = crate::menu::best_shoot_from(&st, &statics, 0, &moved, &mut sc, crate::menu::Tuning::default());
        assert_eq!(blind, None, "an unseen enemy is never the advance-and-shoot aim, Indirect or not");
    }

    /// `sho01_fires` for the door's pooled volley: "a" fires at "b" (blocked in the sight matrix) with NO recorded split aim, the shape
    /// of the AI door's single-target intent. The split-aim fixtures above pass the gate through the plan; this one meets it.
    fn sho01_pooled_fires(shoot: Vec<crate::unit::ShootProfile>, kind: i64, epoch: u32) -> bool {
        let (mut st, mut statics) = buff_line();
        let mut dark = vec![true; 16];
        dark[2] = false; // los_pairs[0*4+2] - a does not see b
        st.los_pairs = Some(Rc::new(dark));
        statics[0].shoot = shoot;
        let mut act = buff_action(Some("b"));
        act.kind = kind;
        if kind == ADVANCE {
            act.dest = Some([-IN2M, 0.0, 0.0]);
        }
        let seams = Seams { sighting: true, moved_shoot: true, rules_epoch: epoch, ..Default::default() };
        let mut tray = Tray::seeded(11);
        let (_, shot) = resolve_stochastic_tray_on_board(&statics, &st, &act, &crate::terrain::Terrain::default(), seams, &mut crate::rng::GodotRng::new(0), &mut tray)
            .expect("the volley resolves");
        shot.rolls.iter().any(|r| r.kind == "attack" && r.count == 1)
    }

    /// The soak's holding Artillery beast (S1, 17.11.): an Indirect gun at a target nobody sees fired nothing in the core, the table fired.
    /// RED at 84 (the pooled gate asked for sight only), GREEN from 85.
    #[test]
    fn a_holding_indirect_gun_fires_at_an_unseen_pooled_target_from_epoch_85() {
        let build = |epoch| sho01_mortar(&repo_root(), "", epoch);
        assert!(!sho01_pooled_fires(build(crate::acts::EPOCH_84_IGNORE_GROUPS), HOLD, crate::acts::EPOCH_84_IGNORE_GROUPS),
            "a record at 84 replays the sighted-only gate");
        assert!(sho01_pooled_fires(build(crate::acts::EPOCH_85_INDIRECT_GATE), HOLD, crate::acts::EPOCH_85_INDIRECT_GATE),
            "from 85 the Indirect gun opens the gate");
    }

    /// The helper's own reading: Hold keeps the waiver, an Advance gives it up (3.6: it needs Hold), a gun without Indirect never had it, and
    /// the Indirect gun still has to reach ("b" stands 12" away).
    #[test]
    fn the_indirect_gate_keeps_the_hold_need_and_asks_for_an_indirect_weapon() {
        let e = crate::acts::EPOCH_85_INDIRECT_GATE;
        let seams = Seams { sighting: true, moved_shoot: true, rules_epoch: e, ..Default::default() };
        let opens = |shoot: Vec<crate::unit::ShootProfile>, held: bool| {
            let (st, mut statics) = buff_line();
            statics[0].shoot = shoot;
            super::super::indirect_waives_gate(&statics, &st, 0, 2, held, seams)
        };
        assert!(opens(sho01_mortar(&repo_root(), "", e), true), "a holding Indirect gun opens the gate");
        assert!(!opens(sho01_mortar(&repo_root(), "", e), false), "a moved Indirect gun needs sight");
        let mut plain = sho01_mortar(&repo_root(), "", e);
        plain[0].indirect = false;
        assert!(!opens(plain, true), "a gun without Indirect needs sight");
        let mut short = sho01_mortar(&repo_root(), "", e);
        short[0].range = 2;
        assert!(!opens(short, true), "the Indirect gun still has to reach");
    }
