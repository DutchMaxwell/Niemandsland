use super::*;
use crate::acts::read_act_header;
use crate::io;

    // ------------------- wave 5 group (b): the Takedown Shot latch -----

    // FEAT PR 2 (docs/plans/FEAT_DESIGN_2026-09-08.md §4). The shot seam
    // appends the once-per-game extra attack at the entry's own Quality
    // when the bearer's `State.feats_used` does not name "Takedown Shot",
    // then stamps the name — the #827 latch's second reader, gated on the
    // FROZEN `EPOCH_7_TABLE_RULES`. Five tests, one per brief line: the
    // volley fires exactly ONE extra attack at 2+ and the ledger shows the
    // name (a), a second volley in the same game fires none (b), a bearer
    // without the name fires none (c), an epoch-6 replay is byte-identical
    // (d), and the extra attack rolls at 2+ never at the bearer's Quality
    // (e).

    /// The bearer: a gf/ratmen_clans profile whose ONLY rule is the named
    /// Takedown entry, read off the REAL registry
    /// (`assets/solo/rules_mechanics_gf.json`: extra_attack_q 2, ap 2,
    /// uses_per_game 1). The REAL `build_for` product — the synthetic
    /// extra attack is the shoot array's ONLY profile.
    fn ts_bearer_named(rules_epoch: u32, rule: &str) -> UnitStatic {
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
            faction_folder: "ratmen_clans".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// The volley fixture: `storm_line`'s shape — bearer "a" (1 model) at
    /// 0", target "b" (3 models, Defense 4) at 5", sighted on the plain
    /// rows (los all-clear). Every attack roll this volley draws IS the
    /// bonus: the bearer carries no other ranged weapon.
    fn ts_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
        let (st, _) = storm_line("Takedown Shot", "ratmen_clans", rules_epoch);
        let bearer = ts_bearer_named(rules_epoch, "Takedown Shot");
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.model_count = 3;
        b.wounds_max = vec![1, 1, 1];
        b.ctx.defense = 4;
        (st, vec![bearer, ts_dummy("ah"), b, ts_dummy("bh")])
    }

    fn ts_dummy(name: &str) -> UnitStatic {
        UnitStatic { name: name.into(), ..Default::default() }
    }

    /// One HOLD+shoot activation on the tray path — the seed decides only
    /// the faces, never the extra attack's die count or target.
    fn run_shoot(st: &State, statics: &[UnitStatic], rules_epoch: u32) -> (State, ShootResult) {
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
        let terrain = Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    fn attack_rolls(shot: &ShootResult) -> Vec<&crate::dice::Roll> {
        shot.rolls.iter().filter(|r| r.kind == "attack").collect()
    }

    /// (a) — the first volley while unspent: exactly ONE extra attack at
    /// Quality 2+ (ap 2, Deadly 3, Takedown — the entry's own params), the
    /// latch gains the DISPLAY name, and the rules-must-log line names the
    /// rule. RED before the read: no synthetic exists, the volley draws
    /// nothing and the latch stays empty.
    #[test]
    fn the_first_volley_fires_one_extra_attack_and_stamps_the_latch() {
        let s7 = ts_bearer_named(7, "Takedown Shot");
        let syn = s7.shoot.last().expect("a carrier is stamped at epoch 7");
        assert_eq!(syn.name, "Takedown Shot", "the latch key is the rule name");
        assert_eq!(syn.extra_attack_q, 2, "the entry's own Quality");
        assert_eq!(syn.ap, 2, "the entry's own AP");
        assert_eq!(syn.deadly, 3, "the table's own Deadly(3) default");
        assert!(s7.shoot.len() == 1, "no weapon of the bearer's own: the roll IS the bonus");
        let (st, statics) = ts_line(7);
        let (next, shot) = run_shoot(&st, &statics, 7);
        let atk = attack_rolls(&shot);
        assert_eq!(
            (atk.len(), atk[0].count, atk[0].target, atk[0].owner.as_str()),
            (1, 1, 2, "a"),
            "exactly ONE extra attack at 2+: {:?}",
            shot.rolls
        );
        assert_eq!(
            next.feats_used[0],
            vec!["Takedown Shot".to_string()],
            "the ledger shows the name (the recorder's key)"
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Takedown Shot") && l.contains("extra attack")),
            "rules-must-log: the applied rule names its line: {:?}",
            shot.log
        );
    }

    /// (b) — the second volley in the SAME game fires none: the stamp
    /// holds in the state's latch, the gate sees the folded name and the
    /// synthetic never joins. RED before the gate: the read re-fires every
    /// volley — the over-credit shape.
    #[test]
    fn a_second_volley_in_the_same_game_fires_none() {
        let (st, statics) = ts_line(7);
        let (next, _) = run_shoot(&st, &statics, 7);
        let (next2, shot2) = run_shoot(&next, &statics, 7);
        assert!(
            attack_rolls(&shot2).is_empty(),
            "the latch is closed: no second extra attack: {:?}",
            shot2.rolls
        );
        assert_eq!(
            next2.feats_used[0],
            vec!["Takedown Shot".to_string()],
            "the replay does not re-spend"
        );
    }

    /// (c) — a bearer without the NAME fires none: "Takedown Strike" (the
    /// melee family sibling) stamps the melee array only, the shoot array
    /// stays empty and the volley draws nothing. RED under a primitive-
    /// whole read that would credit every Takedown name (#489).
    #[test]
    fn a_bearer_without_the_name_fires_none() {
        let (st, mut statics) = ts_line(7);
        statics[0] = ts_bearer_named(7, "Takedown Strike");
        let (next, shot) = run_shoot(&st, &statics, 7);
        assert!(
            attack_rolls(&shot).is_empty(),
            "no ranged synthetic on a Strike bearer: {:?}",
            shot.rolls
        );
        assert!(next.feats_used[0].is_empty(), "nothing spent, nothing stamped");
    }

    /// (d) — an epoch-6 replay is byte-identical: the FROZEN gate keeps
    /// the stamp off the statics (no synthetic exists) and even a
    /// hypothetically pre-folded ledger key rides INERTLY — nothing
    /// fires, nothing re-spends, nothing logs. RED under the mutation
    /// that drops the epoch gate.
    #[test]
    fn an_epoch_6_replay_is_byte_identical() {
        assert!(
            ts_bearer_named(6, "Takedown Shot").shoot.is_empty(),
            "an epoch-6 record carries no synthetic"
        );
        let (mut st, statics) = ts_line(6);
        st.feats_used[0].push("Takedown Shot".to_string());
        let (next, shot) = run_shoot(&st, &statics, 6);
        assert!(
            attack_rolls(&shot).is_empty(),
            "epoch 6: nothing fires: {:?}",
            shot.rolls
        );
        assert_eq!(
            next.feats_used[0],
            vec!["Takedown Shot".to_string()],
            "the folded key rides along INERTLY below the gate"
        );
        assert!(
            !shot.log.iter().any(|l| l.contains("Takedown Shot")),
            "epoch 6: nothing logs: {:?}",
            shot.log
        );
    }

    /// (e) — the extra attack rolls at the entry's own 2+, NEVER at the
    /// bearer's Quality (4): the ranged fold's own-Quality override, the
    /// melee `melee_hit_target` shape (dice.rs). RED before the override:
    /// the volley reads the Ctx quality and rolls the bonus at 4+.
    #[test]
    fn the_extra_attack_rolls_at_2plus_not_the_bearers_quality() {
        let (st, statics) = ts_line(7);
        let (_, shot) = run_shoot(&st, &statics, 7);
        let atk = attack_rolls(&shot);
        assert_eq!(atk.len(), 1);
        assert_ne!(statics[0].ctx.quality, 2, "the fixture's bearer is not a 2+ shooter anyway");
        assert_eq!(atk[0].target, 2, "the entry's own Quality, not the bearer's {}: {:?}", statics[0].ctx.quality, shot.rolls);
    }
