use super::*;

    // ------------------ EPOCH 58: the Precision Debuff's record fold ---------

    /// EPOCH_58_PRECISION_DEBUFF (precision text sweep, 15.09. — row
    /// `Precision Debuff`, gf infected_colonies / alien_hives): the
    /// enemy-target -1-to-hit debuff rides the ONE utility-buff seam every
    /// other enemy pick uses — the REAL registry entry (primitive "Utility
    /// Buff", `hit_mod: -1, range_in: 18, target: "enemy", once, needs_los`)
    /// stamps through `build_for`, and `tray_utility_buff` ->
    /// `utility_targets` -> `record_buff` lands the once-row on the pick's
    /// own ledger, which the victim's next attack reads (`ctx_live`,
    /// `Role::AttackerOwn`). The NEW legs run at the gate's own literal 58
    /// (NOT `CURRENT_RULES_EPOCH` — the gate is frozen, the unstoppable-mark
    /// pins carry their literals the same way); the OLD leg is pinned by the
    /// FROZEN constant immediately below AT REBASE TIME (re-pointed at every
    /// rebase, never the live symbol — today 56 is
    /// `EPOCH_56_GROUNDED_PROTECTION`'s own landed leg, #974; when the
    /// stealthbuild leg lands 57 the constant re-points onto it).
    const OLD_EPOCH: u32 = crate::acts::EPOCH_56_GROUNDED_PROTECTION;

    /// The row's carrier: a single-model gf/infected_colonies unit whose ONLY
    /// printed rule is the REAL registry entry, built off the REAL
    /// `build_for` at `epoch`.
    fn precision_carrier(epoch: u32) -> UnitStatic {
        let p = crate::state::Profile {
            unit_id: "a".into(),
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
            special_rules: vec!["Precision Debuff".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "infected_colonies".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// The debuffed enemy's OWN shooting context, folded live off the state —
    /// the read `dice.rs` adds `att.hit_mod` from (`_solo_hit_mod_info`'s
    /// core twin). ctx_live indexes `state.roster.profile[i]` into the
    /// statics slice, so the WHOLE fixture's slice rides, not a one-unit one.
    fn attacker_ctx(st: &crate::state::State, statics: &[UnitStatic], i: usize, epoch: u32) -> Ctx {
        crate::sim::ctx_live(
            crate::sim::ctx_of(&statics[i], st, i),
            statics, st, i, false, epoch,
        )
    }

    /// One enemy volley (1 die, no AP) at 12" — the roll whose target the
    /// debuff must worsen. The fixture's "b" carries no weapon of its own;
    /// the volley hands it the bearer-line's plain rifle.
    fn enemy_volley(st: &crate::state::State, statics: &[UnitStatic], i: usize, epoch: u32) -> ShootResult {
        let att = attacker_ctx(st, statics, i, epoch);
        let def = crate::sim::ctx_of(&statics[0], st, 0);
        let mut tray = Tray::seeded(5);
        crate::dice::resolve_shooting_with_tray(
            &[gun("Rifle", 1, 24)], &[0], &[1], &att, &def, 12.0, &mut tray,
        )
    }

    /// EPOCH_58_PRECISION_DEBUFF — the NEW leg: the bearer places the debuff
    /// on the 12"-away enemy pick in line of sight (the record lands ON the
    /// enemy — the debuff rides the victim's own net, like the Morale Debuff
    /// row), the enemy's NEXT to-hit rolls one worse (Quality 4+ at 5+), and
    /// the exchange that used it spends the once-record.
    #[test]
    fn the_precision_debuff_worsens_the_enemys_next_to_hit_target_from_58() {
        let (st, mut statics) = buff_line();
        statics[0] = precision_carrier(58);
        assert_eq!(
            statics[0].utility_buffs.len(), 1,
            "the real registry entry stamps at the gate: {:?}",
            statics[0].utility_buffs
        );
        let plain = enemy_volley(&st, &statics, 2, 58);
        assert_eq!(plain.rolls[0].target, 4, "control: the un-debuffed enemy rolls Quality 4+");

        let (mut next, placed) = run_buff_epoch(&st, &statics, &buff_action(None), 11, 58);
        assert!(placed.rolls.is_empty(), "the buff arm is dice-free");
        assert_eq!(next.buffs[2].len(), 1, "the record lands on the ENEMY pick: {:?}", next.buffs);
        assert_eq!(next.buffs[2][0].hit_mod, -1, "the registry's own -1");
        assert_eq!(&*next.buffs[2][0].name, "Precision Debuff", "the record carries its name");
        let debuffed = enemy_volley(&next, &statics, 2, 58);
        assert_eq!(debuffed.rolls[0].target, 5, "the debuffed enemy's next to-hit is one worse");

        // The exchange that used it spends the once-record (main.gd:3823) —
        // a further volley rolls the plain 4+ again and the ledger is empty.
        crate::sim::spend_exchange(&mut next, 2, 0, false);
        assert!(next.buffs.iter().all(|v| v.is_empty()), "the once-record is spent: {:?}", next.buffs);
        let after = enemy_volley(&next, &statics, 2, 58);
        assert_eq!(after.rolls[0].target, 4, "spent: back to the plain Quality 4+");
    }

    /// EPOCH_58_PRECISION_DEBUFF — the OLD leg: below the gate the entry
    /// reads as ABSENT — no stamp, no record, the enemy's to-hit unchanged —
    /// so every corpus recorded before the bump replays byte-exact.
    #[test]
    fn below_the_gate_the_precision_debuff_stays_silent() {
        let (st, mut statics) = buff_line();
        statics[0] = precision_carrier(OLD_EPOCH);
        assert!(
            statics[0].utility_buffs.is_empty(),
            "below 58 the name stamps no utility-buff entry: {:?}",
            statics[0].utility_buffs
        );
        let (next, _) = run_buff_epoch(&st, &statics, &buff_action(None), 11, OLD_EPOCH);
        assert!(
            next.buffs.iter().all(|v| v.is_empty()),
            "no record lands below the gate: {:?}",
            next.buffs
        );
        let after = enemy_volley(&next, &statics, 2, OLD_EPOCH);
        assert_eq!(after.rolls[0].target, 4, "the enemy's to-hit is unchanged");
    }

    /// The printed pick gates: beyond the 18" range, and in range but out of
    /// sight, nothing is recorded — the pick refuses like every other
    /// enemy-target buff's.
    #[test]
    fn the_precision_debuff_respects_the_printed_range_and_sight() {
        let (st, mut statics) = buff_line();
        statics[0] = precision_carrier(58);
        // Out of the printed 18" range: the pick refuses.
        let mut far = st.clone();
        far.positions[2] = vec![
            [30.0 * IN2M, 0.0, 0.0], [30.02 * IN2M, 0.0, 0.0], [30.04 * IN2M, 0.0, 0.0],
        ];
        let (next, _) = run_buff_epoch(&far, &statics, &buff_action(None), 11, 58);
        assert!(next.buffs.iter().all(|v| v.is_empty()), "out of range, no record: {:?}", next.buffs);
        // In range, sight blocked: `needs_los` refuses the pick.
        let mut dark = st.clone();
        let mut m = vec![true; 16];
        m[2] = false; // los_pairs[0 * 4 + 2] — a to b
        dark.los_pairs = Some(Rc::new(m));
        let (next, _) = run_buff_epoch(&dark, &statics, &buff_action(None), 11, 58);
        assert!(next.buffs.iter().all(|v| v.is_empty()), "no sight, no record: {:?}", next.buffs);
    }

    /// `run_buff` with the record's OWN `rules_epoch` (the `Seams::default()`
    /// path rides epoch 0, which is what the pre-class-fix corpora stamp).
    fn run_buff_epoch(
        st: &State,
        statics: &[UnitStatic],
        action: &Action,
        seed: i64,
        epoch: u32,
    ) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, action, &terrain,
            Seams { rules_epoch: epoch, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap()
    }