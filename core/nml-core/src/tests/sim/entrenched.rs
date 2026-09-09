use super::*;

    // ---- wave 4 (port-entrenched): the per-unit moved_round stamp -----------

    /// (e) Every EXECUTED move stamps `moved_round` (main.gd:7786-7793 stamps
    /// on ANY executed move); a HOLD never stamps, and a new round self-clears
    /// by COMPARISON (no sweep).
    #[test]
    fn an_executed_move_stamps_moved_round_and_a_hold_never_does() {
        let (mut st, statics) = buff_line();
        let mut prof_list = st.profiles.list.clone();
        prof_list[0].move_bands.advance = 6.0;
        st.profiles = Rc::new(Profiles { list: prof_list, index: HashMap::new() });
        let terrain = crate::terrain::Terrain::default();

        // ADVANCE: the unit actually moves — the stamp lands.
        let advance = Action {
            kind: ADVANCE, unit: "a".into(),
            dest: Some([3.0 * IN2M, 0.0, 0.0]),
            shoot: None, charge: None, patient: false, split: None, traced: None, teleport: None,
        };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.moved_round[0], next.round, "the executed move stamps the round");
        assert_eq!(next.moved_round[2], -1, "a unit that never activated stays unstamped");

        // HOLD: no move, no stamp.
        let mut tray2 = Tray::seeded(11);
        let mut rng2 = crate::rng::GodotRng::new(0);
        let (held, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(None), &terrain, Seams::default(), &mut rng2, &mut tray2,
        )
        .unwrap();
        assert_eq!(held.moved_round[0], -1, "a HOLD never stamps");

        // (f) the stamp self-clears by comparison against State::round —
        // no sweep, the reader's `!=` does the work.
        let mut later = next;
        later.round += 1;
        assert_ne!(later.moved_round[0], later.round, "a new round reads as unmoved");
    }

    /// (e) the pile-in half: the engage snap of a charge is an EXECUTED move
    /// and stamps `moved_round` (main.gd:7786-7793's "any executed move",
    /// NML-208's mandatory melee moves included).
    #[test]
    fn the_engage_snap_counts_as_moving() {
        let (mut st, _statics) = buff_line();
        // Charger "a" 0.5" short of base contact with "b" at 12" (1" radii).
        st.positions[0] = vec![[9.5 * IN2M, 0.0, 0.0], [9.52 * IN2M, 0.0, 0.0]];
        let mut next = st.clone();
        let snap = (crate::mv::step::MoveRules { rules_epoch: 7 })
            .snap_charge_state(&mut next, 0, 2, 1.0, false);
        assert!(snap.is_some(), "the snap closed the residual base gap");
        assert_eq!(next.moved_round[0], next.round, "the pile-in stamps the round");
    }

    /// (e) the consolidation half: `consolidate_after_melee`'s 3" survivor
    /// move is an EXECUTED move and stamps `moved_round`.
    #[test]
    fn the_consolidation_move_counts_as_moving() {
        let (mut st, _statics) = buff_line();
        // "b" wiped; a living far enemy gives the consolidation its goal.
        st.alive[2] = 0;
        st.positions[3] = vec![[20.0 * IN2M, 0.0, 0.0]];
        st.radii[3] = vec![IN2M];
        st.wounds[3] = vec![1];
        st.alive[3] = 1;
        let terrain = small_board();
        let seams = Seams { consolidate: true, rules_epoch: 7, ..Default::default() };
        let mut next = st.clone();
        consolidate_after_melee(&mut next, Cover::Board(&terrain), seams, 0, 2);
        assert_eq!(next.moved_round[0], next.round, "the consolidation move stamps the round");
        assert_eq!(next.moved_round[2], -1, "the wiped unit is never stamped");
    }

    // ---- the Entrenched Buff grant leg (gf, STAMPED -> PORTED) --------------

    /// One recorded "Entrenched Buff" runtime record — a Utility Buff whose
    /// `grants_rule: "Entrenched"` lands on the bearer's ledger (the
    /// `_solo_apply_grant` overlay shape the other granted base rules ride).
    fn entrenched_grant() -> mods::LiveMod {
        mods::LiveMod {
            hit_mod: 0, casting_mod: 0, morale_mod: 0,
            ap_mod: 0, def_mod: 0, defense_mod: 0,
            grants_rule: Rc::from("Entrenched"),
            scope: Rc::from(""),
            attackers: false,
            once: true,
        }
    }

    fn run_granted(
        st: &State, statics: &[UnitStatic], epoch: u32, buffs: Vec<(usize, mods::LiveMod)>,
    ) -> ShootResult {
        let mut s = st.clone();
        for (u, m) in buffs {
            s.buffs[u] = vec![m];
        }
        let seams = Seams { rules_epoch: epoch, ..Default::default() };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, &s, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray,
        )
        .unwrap()
        .1
    }

    /// The GRANT leg: a target carrying Entrenched ONLY via a recorded
    /// `grants_rule: "Entrenched"` record, unmoved this round, takes the -2
    /// over 9" at epoch 7 — the SAME stationary read a statically carried
    /// Entrenched gets (main.gd's grant overlay writes the name onto the
    /// chain, main.gd:3730; the read at :5694-5702 never distinguished).
    #[test]
    fn a_granted_entrenched_takes_the_penalty_while_unmoved() {
        let (st, statics) = buff_line();
        let on = run_granted(&st, &statics, 7, vec![(2, entrenched_grant())]);
        assert_eq!(on.rolls[0].target, 6, "granted Entrenched, unmoved: Quality 4+ -> 6+");
        assert!(
            on.log.iter().any(|l| l.contains("[Entrenched]")),
            "the applied rule names itself (rules-must-log): {:?}",
            on.log
        );
        // The moved twin: the record is on the ledger but the gate is shut.
        let mut moved_state = st.clone();
        moved_state.moved_round[2] = moved_state.round;
        let off = run_granted(&moved_state, &statics, 7, vec![(2, entrenched_grant())]);
        assert_eq!(off.rolls[0].target, 4, "moved this round: the stationary read stands down");
        assert!(!off.log.iter().any(|l| l.contains("[Entrenched]")));
    }

    /// The replay gate: below `EPOCH_7_TABLE_RULES` the grant leg is inert
    /// (and the target carries no STATIC Entrenched, so nothing fires at all).
    #[test]
    fn the_grant_leg_is_inert_below_epoch_7() {
        let (st, statics) = buff_line();
        let off = run_granted(&st, &statics, 6, vec![(2, entrenched_grant())]);
        assert_eq!(off.rolls[0].target, 4, "epoch 6: no grant read, no penalty");
        assert!(!off.log.iter().any(|l| l.contains("[Entrenched]")));
    }
