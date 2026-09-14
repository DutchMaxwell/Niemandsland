use super::*;

    // ---- EPOCH_19_MOVE_GRANTS_FOLD: the solo move-grant family moves the unit ----

    /// One `_solo_apply_grant` overlay row (main.gd:3730): a live rule GRANT
    /// whose name reaches the whole joined chain. This is exactly the shape
    /// `sim::record_buff` writes and `io` replays; a FRESH core-simulated game
    /// carries it and NOTHING precomputed — `Profile.move_bands` is built from
    /// the rules a unit PRINTS (the loader's band pass), never from the ones a
    /// spell or aura grants mid-game.
    fn grant_row(rule: &str) -> mods::LiveMod {
        mods::LiveMod {
            hit_mod: 0, casting_mod: 0, morale_mod: 0,
            ap_mod: 0, def_mod: 0, defense_mod: 0,
            move_mod: 0,
            grants_rule: Rc::from(rule),
            scope: Rc::from(""),
            attackers: false,
            once: false,
            name: Rc::from(""),
        }
    }

    /// A registry-built mover on the four-unit line: an aof profile whose book
    /// fields the granted entry's params (Fast/Slow live in `common`, Rapid
    /// Advance/Rapid Rush and Swift in their factions), the grant rows on the
    /// mover's ledger, the other units parked at 40" so no band under test
    /// touches them. `repo_root`'s real registry, same shape as the
    /// `great_musician_bearer` fixture.
    fn granted_line(faction: &str, rules_epoch: u32, grants: &[&str]) -> (State, Vec<UnitStatic>) {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "aof".into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        let bearer = UnitStatic::build_for(&mut reg, &p, rules_epoch);
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.profiles = Rc::new(Profiles {
            list: vec![p.clone(), p.clone(), p.clone(), p],
            index: HashMap::new(),
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[40.0 * IN2M, 0.0, 0.0], [40.02 * IN2M, 0.0, 0.0], [40.04 * IN2M, 0.0, 0.0]],
            vec![],
        ];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M; 3], vec![]];
        st.wounds = vec![vec![1], vec![], vec![1; 3], vec![]];
        st.alive = vec![1, 0, 3, 0];
        st.buffs[0] = grants.iter().map(|g| grant_row(g)).collect();
        (
            st,
            vec![
                bearer,
                UnitStatic { name: "ah".into(), ..Default::default() },
                UnitStatic { name: "b".into(), ..Default::default() },
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    /// One move on the tray path — the seed never matters (a plain move draws
    /// no die). The `move_buff.rs` shape, unit taken from the action.
    fn run_move(
        st: &State,
        statics: &[UnitStatic],
        action: &Action,
        rules_epoch: u32,
    ) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    /// The replay-aware twin of `run_move`: `bands_prefolded` marks a header
    /// that carried `"books"` — a TABLE recording (`act_recorder.gd:266-268`
    /// writes it unconditionally; no writer in `core/nml-core/src` does).
    /// `books` present ⇒ the record's `bands` already fold every grant
    /// (battle_sim.gd:1707 -> move_bands_for_props).
    fn run_move_prefolded(
        st: &State,
        statics: &[UnitStatic],
        action: &Action,
        rules_epoch: u32,
    ) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, bands_prefolded: true, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    fn move_of(kind: i64, unit: &str, x_in: f64) -> Action {
        Action {
            kind,
            unit: unit.into(),
            dest: Some([x_in * IN2M, 0.0, 0.0]),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
            teleport: None,
        }
    }

    /// RED — a unit granted `Fast` mid-game must move its GRANTED band. The
    /// registry's `common` entry carries the numbers the table's band pass
    /// reads (`advance_mod: 2`, `rush_mod: 4`), but the printed
    /// `Profile.move_bands` never sees a grant, and today the core only LOGS
    /// the name (`sim.rs` ctx_live, evidence-only) — so the unit walks its
    /// bare printed 6". Expectation written as `printed + advance_mod`, never
    /// a magic inch constant.
    #[test]
    fn a_granted_fast_extends_the_advance_at_epoch_19() {
        let printed = 6.0;
        let advance_mod = 2.0; // rules_mechanics_aof.json, common "Fast"
        let (st, statics) = granted_line("ogres", 19, &["Fast"]);
        let (landed, _) = run_move(&st, &statics, &move_of(ADVANCE, "a", 20.0), 19);
        let x = landed.positions[0][0][0];
        assert!(
            (x - (printed + advance_mod) * IN2M).abs() < 1e-6,
            "the granted Fast rides +2\" on the advance band: {x}"
        );
    }

    /// RED first — the replay-aware half of the fold. A TABLE record stamped
    /// 19+ carries `"books"` in its header, so its recorded `bands` ALREADY
    /// carry every grant (`battle_sim.gd:1707 -> move_bands_for_props`); the
    /// live delta at the move spend would count every granted inch twice.
    /// `bands_prefolded` (the header's `books` present) must return 0.0.
    #[test]
    fn a_table_recorded_fast_adds_nothing_at_epoch_19() {
        let printed = 6.0;
        let (st, statics) = granted_line("ogres", 19, &["Fast"]);
        let (landed, _) = run_move_prefolded(&st, &statics, &move_of(ADVANCE, "a", 20.0), 19);
        let x = landed.positions[0][0][0];
        assert!(
            (x - printed * IN2M).abs() < 1e-6,
            "the recorded bands already carry the granted Fast, the advance stays printed: {x}"
        );
    }

    /// The epoch twin: a record stamped 18 (every corpus recorded up to
    /// today's live epoch, #932's window included) keeps replaying the
    /// evidence-only read — printed band, grant unchanged.
    #[test]
    fn an_epoch_18_replay_keeps_the_grant_evidence_only() {
        let printed = 6.0;
        let (st, statics) = granted_line("ogres", 18, &["Fast"]);
        let (landed, _) = run_move(&st, &statics, &move_of(ADVANCE, "a", 20.0), 18);
        let x = landed.positions[0][0][0];
        assert!(
            (x - printed * IN2M).abs() < 1e-6,
            "an epoch-18 record replays at the printed band: {x}"
        );
    }

    /// The rush half of the same grant: `+rush_mod` (4) on RUSH.
    #[test]
    fn a_granted_fast_extends_the_rush_at_epoch_19() {
        let printed = 12.0;
        let rush_mod = 4.0; // rules_mechanics_aof.json, common "Fast"
        let (st, statics) = granted_line("ogres", 19, &["Fast"]);
        let (landed, _) = run_move(&st, &statics, &move_of(RUSH, "a", 40.0), 19);
        let x = landed.positions[0][0][0];
        assert!(
            (x - (printed + rush_mod) * IN2M).abs() < 1e-6,
            "the granted Fast rides +4\" on the rush band: {x}"
        );
    }

    /// "Rapid Advance" ("This model moves +4\" when using Advance actions") —
    /// the wood_elves faction entry's own `advance_mod` onto the advance band.
    #[test]
    fn a_granted_rapid_advance_extends_the_advance_at_epoch_19() {
        let printed = 6.0;
        let advance_mod = 4.0; // rules_mechanics_aof.json, wood_elves "Rapid Advance"
        let (st, statics) = granted_line("wood_elves", 19, &["Rapid Advance"]);
        let (landed, _) = run_move(&st, &statics, &move_of(ADVANCE, "a", 20.0), 19);
        let x = landed.positions[0][0][0];
        assert!(
            (x - (printed + advance_mod) * IN2M).abs() < 1e-6,
            "the granted Rapid Advance rides +4\" on the advance band: {x}"
        );
    }

    /// "Rapid Rush" ("This model moves +6\" when using Rush actions") — the
    /// human_empire faction entry's own `rush_mod` onto the rush band.
    #[test]
    fn a_granted_rapid_rush_extends_the_rush_at_epoch_19() {
        let printed = 12.0;
        let rush_mod = 6.0; // rules_mechanics_aof.json, human_empire "Rapid Rush"
        let (st, statics) = granted_line("human_empire", 19, &["Rapid Rush"]);
        let (landed, _) = run_move(&st, &statics, &move_of(RUSH, "a", 40.0), 19);
        let x = landed.positions[0][0][0];
        assert!(
            (x - (printed + rush_mod) * IN2M).abs() < 1e-6,
            "the granted Rapid Rush rides +6\" on the rush band: {x}"
        );
    }

    /// "Slow" — the `common` entry's own -2/-4 onto BOTH bands. A granted
    /// Slow moves the unit LESS than it prints, the same fold the table's
    /// name pass runs (movement_range_controller.gd:116-121).
    #[test]
    fn a_granted_slow_shrinks_the_bands_at_epoch_19() {
        let (st, statics) = granted_line("dwarves", 19, &["Slow"]);
        let (adv, _) = run_move(&st, &statics, &move_of(ADVANCE, "a", 20.0), 19);
        assert!(
            (adv.positions[0][0][0] - 4.0 * IN2M).abs() < 1e-6,
            "the granted Slow rides -2\" on the advance band: {}",
            adv.positions[0][0][0]
        );
        let (rsh, _) = run_move(&st, &statics, &move_of(RUSH, "a", 40.0), 19);
        assert!(
            (rsh.positions[0][0][0] - 8.0 * IN2M).abs() < 1e-6,
            "the granted Slow rides -4\" on the rush band: {}",
            rsh.positions[0][0][0]
        );
    }

    /// "Swift" cancels a granted "Slow" by name — the twins ship the pair
    /// (the table name pass, movement_range_controller.gd:92-109; the static
    /// twin's cancel arm at unit.rs), so both granted together the bands stay
    /// printed. Swift alone carries no inches of its own.
    #[test]
    fn a_granted_swift_cancels_a_granted_slow_at_epoch_19() {
        let (st, statics) = granted_line("dwarves", 19, &["Slow", "Swift"]);
        let (landed, _) = run_move(&st, &statics, &move_of(ADVANCE, "a", 20.0), 19);
        assert!(
            (landed.positions[0][0][0] - 6.0 * IN2M).abs() < 1e-6,
            "Swift cancels the granted Slow, the advance band stays printed: {}",
            landed.positions[0][0][0]
        );
    }

    /// Swift alone: no inches, no delta — the cancel needs a Slow to cancel.
    #[test]
    fn a_granted_swift_alone_changes_nothing_at_epoch_19() {
        let (st, statics) = granted_line("dwarves", 19, &["Swift"]);
        let (landed, _) = run_move(&st, &statics, &move_of(ADVANCE, "a", 20.0), 19);
        assert!(
            (landed.positions[0][0][0] - 6.0 * IN2M).abs() < 1e-6,
            "a Swift grant alone never touches the band: {}",
            landed.positions[0][0][0]
        );
    }
