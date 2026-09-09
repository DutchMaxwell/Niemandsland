use super::*;

    // ------------------- seam 4 step 2: the ap/def READS (epoch 7) -----------

    /// One recorded ledger row, the shape any recording path leaves behind
    /// (`_solo_record_spell_mod` main.gd:3649-3670). `once` — every one of the
    /// three seam-4 names prints "once (next time the effect would apply)".
    fn row(ap_mod: i64, def_mod: i64, defense_mod: i64) -> mods::LiveMod {
        mods::LiveMod {
            hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod, def_mod, defense_mod,
            grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: true,
            name: Rc::from(""),
        }
    }

    /// The buff line with the shooter's rifle at AP(1): the plain save target
    /// is `save_target(4, 1) == 5`, so one AP rung and one defense rung are
    /// each visible as exactly one rung on rolls[1]. The bearer's own Defense
    /// is pinned at 4 too — test (c) has the defender-side read exercised
    /// back at it — and `b`'s models carry 99-wound bodies where a test needs
    /// the target to survive into a second exchange.
    fn ap_rifle() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        statics[0].shoot[0].ap = 1;
        statics[0].shoot[0].attacks = 64; // a save batch is guaranteed to follow
        statics[0].ctx.defense = 4;
        (st, statics)
    }

    fn run_reads(st: &State, statics: &[UnitStatic], action: &Action, seed: i64, rules_epoch: u32) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, action, &terrain,
            Seams { rules_epoch, ..Default::default() }, &mut rng, &mut tray,
        )
        .unwrap()
    }

    fn save_target_of(shot: &ShootResult) -> i64 {
        let roll = shot.rolls.iter().find(|r| r.kind == "defense").expect("a save batch");
        roll.target
    }

    /// SEAM 4 step 2 (design §4 step 2, epoch 7): the two READS.
    /// Piercing Debuff (gf machine_cults, `ap_mod: -1`): "which loses AP(+1)
    /// when attacking" — the DEBUFFED unit's own volley shoots at AP one
    /// lower, floored by the same `max(0)` every AP sum already rides.
    /// Defense Debuff (aof ratmen, `defense_mod: -1`): "which gets -1 to
    /// defense rolls" — the target saves one rung WORSE, the same fold a
    /// "+1 to defense rolls" roll bonus gets at Shielded/cover (a roll bonus
    /// LOWERS the working rung, `combat::shielded_defense`'s `defense - 1`).
    #[test]
    fn piercing_debuff_cuts_the_bearer_ap_and_defense_debuff_softens_the_save_at_epoch_7() {
        let (st, statics) = ap_rifle();
        let (_, plain) = run_reads(&st, &statics, &buff_action(Some("b")), 27, 7);
        assert_eq!(save_target_of(&plain), 5, "the plain rifle: Defense 4+ at AP(1)");

        // The recorded `ap_mod: -1` row on the SHOOTER: AP(+1) lost.
        let mut deb = st.clone();
        deb.buffs[0].push(row(-1, 0, 0));
        let (_, cut) = run_reads(&deb, &statics, &buff_action(Some("b")), 27, 7);
        assert_eq!(save_target_of(&cut), 4,
            "RED before the fix: the debuffed bearer's volley keeps AP(1)");

        // The recorded `defense_mod: -1` row on the TARGET: one rung worse.
        let mut hex = st.clone();
        hex.buffs[2].push(row(0, 0, -1));
        let (_, soft) = run_reads(&hex, &statics, &buff_action(Some("b")), 27, 7);
        assert_eq!(save_target_of(&soft), 6,
            "RED before the fix: the hexed target saves at its plain rung");
    }

    /// The epoch-6 twin: below `EPOCH_7_TABLE_RULES` both recorded rows stay
    /// inert — the reader gate zeroes the knobs (io.rs, PR 1) and the fold in
    /// `ctx_live` keeps its epoch-7 gate — so the dice are identical to the
    /// plain volley, byte-exact.
    #[test]
    fn the_recorded_ap_and_defense_rows_are_inert_at_epoch_6() {
        let (st, statics) = ap_rifle();
        let (_, plain) = run_reads(&st, &statics, &buff_action(Some("b")), 27, 6);
        assert_eq!(save_target_of(&plain), 5);

        let mut deb = st.clone();
        deb.buffs[0].push(row(-1, 0, 0));
        deb.buffs[2].push(row(0, 0, -1));
        let (_, both) = run_reads(&deb, &statics, &buff_action(Some("b")), 27, 6);        assert_eq!(save_target_of(&both), 5,
            "below 7 the records stay inert: {:?} vs plain {:?}",
            save_target_of(&both), save_target_of(&plain));
    }

    /// Defense Buff (aof human_empire, `def_mod: +1`): "which gets +1 to
    /// defense rolls" — the tray-recorded row on the BEARER raises its own
    /// save by one rung (the roll bonus lowers the working rung, the
    /// Shielded shape). The bearer's own volley cannot show it — a unit
    /// saves at its OWN rung only when it DEFENDS — so the read is exercised
    /// by a second exchange where `b` shoots back at the buffed bearer, and
    /// that same exchange spends the row on the defender leg (main.gd:3925).
    #[test]
    fn defense_buff_raises_the_bearers_save_by_one_rung_at_epoch_7() {
        let (st, mut statics) = ap_rifle();
        statics[0].utility_buffs =
            vec![UtilityBuff { def_mod: 1, ..ub("Defense Buff") }];
        let (next, _) = run_reads(&st, &statics, &buff_action(Some("b")), 27, 7);
        assert_eq!(next.buffs[0].len(), 1,
            "the bearer's defense row is spent by the exchange where it DEFENDS, not by its own attack (main.gd:3925)");

        // The second exchange: b shoots back at the buffed bearer — a saves
        // one rung better (Defense 4+ at AP(0), the row folding 4 -> 3).
        let mut shoot_back = statics.clone();
        shoot_back[2].shoot = vec![gun("Rifle", 64, 24)];
        let back = Action {
            kind: HOLD, unit: "b".into(), dest: None, shoot: Some("a".into()),
            charge: None, patient: false, split: None, traced: None, teleport: None,
        };
        let (next2, buffed) = run_reads(&next, &shoot_back, &back, 27, 7);
        assert_eq!(save_target_of(&buffed), 3,
            "RED before the fix: the recorded def_mod row lands but nothing reads it");
        assert!(next2.buffs[0].is_empty(), "the exchange where a DEFENDED spends it");

        // Epoch 6: the same pick records nothing (PR 1's all-zero guard), so
        // the shoot-back volley stays at the plain rung.
        let (next6, _) = run_reads(&st, &statics, &buff_action(Some("b")), 27, 6);
        let (_, plain6) = run_reads(&next6, &shoot_back, &back, 27, 6);
        assert_eq!(save_target_of(&plain6), 4, "below 7 the row is not even recorded");
    }

    /// The `once` spend (`_solo_consume_once_mods` main.gd:3823-3841): the
    /// first exchange that could have used a row spends it — the AP row on
    /// the ATTACKER leg, the defense row on the DEFENDER leg — so a second
    /// exchange rolls at base. Today no role matches the rows, so they
    /// survive the exchange forever.
    #[test]
    fn once_rows_are_spent_by_the_first_exchange_exactly_like_hit_mod_rows() {
        let (st, mut statics) = ap_rifle();
        statics[2].wounds_max = vec![99, 99, 99]; // the target survives into the second exchange
        let mut deb = st.clone();
        deb.buffs[0].push(row(-1, 0, 0));
        deb.buffs[2].push(row(0, 0, -1));

        let (next, first) = run_reads(&deb, &statics, &buff_action(Some("b")), 27, 7);
        assert!(next.buffs[0].is_empty() && next.buffs[2].is_empty(),
            "RED before the fix: the rows ride the ledger past their exchange ({:?})",
            next.buffs.iter().map(|b| b.len()).collect::<Vec<_>>());

        let (_, second) = run_reads(&next, &statics, &buff_action(Some("b")), 27, 7);
        assert_eq!(save_target_of(&second), 5, "the second exchange rolls at base");
    }
