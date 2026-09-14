use super::*;

    // ---------- The utility-buff family: 13 `none` rows, ONE table ----------
    //
    // D-PROOF (14.09.): the 13 `none` rows of the buffs family in
    // analysis/ledger/proven_vs_read_part2.tsv (the family table's "buffs"
    // line in analysis/PROVEN_VS_READ_PART2_2026-09-14.md) had NO core test
    // pinning their numbers — a read is not a proof. Twelve rows ride the
    // real "Utility Buff" registry primitive and stamp one `mods::LiveMod`
    // record through `tray_utility_buff` -> `utility_targets` ->
    // `record_buff` — the seam #961's Defense Buff uses; the thirteenth,
    // "Stealth Buff", is a Stealth-primitive DATA alias whose number is
    // stamped on the DEFENDER ctx by `stealth_alias_of` (the Machine-Fog
    // walk) and never touches the ledger. Every row is pinned here by its
    // EXACT NAME at `CURRENT_RULES_EPOCH` (no epoch bump, no behaviour
    // change): the record lands on the highest-VALUE friendly pick INSIDE
    // the printed 12" pick range and never on a friend beyond it — not even
    // one whose value would win the pick — the grants / hit_mod numbers are
    // the registry's own, and "Increased Shooting Range Buff" stays the
    // documented all-zero drop (`range_bonus_in` is not modeled on
    // `UtilityBuff`). Rules-must-log: none of these reads carries a trace
    // line of its own — `record_buff` logs only the widened ap/def rows
    // (none here) and the fold log fires only under NML_TRACE_RULES=1,
    // which no core test asserts today.

    /// One family row: the real (system, faction) block the name is read
    /// from, and the kind of number the core must produce.
    #[derive(Clone, Copy)]
    enum Kind {
        /// the record's `grants_rule` payload (the granted rule's name)
        Grant(&'static str),
        /// the record's `hit_mod` and the scope it is bound to
        HitMod(i64, &'static str),
        /// the documented all-zero drop: no record lands anywhere
        Inert,
        /// the Stealth-primitive alias: `hit_penalty` behind `over_in`
        StealthAlias(i64, f64),
    }

    struct Row {
        system: &'static str,
        faction: &'static str,
        rule: &'static str,
        kind: Kind,
    }

    /// The 13 rows, in the family table's own order.
    fn rows() -> Vec<Row> {
        vec![
            Row { system: "aof", faction: "kingdom_of_angels", rule: "Angelic Blessing Boost Buff", kind: Kind::Grant("Angelic Blessing Boost") },
            Row { system: "aof", faction: "vampiric_undead", rule: "Cursed Undead Boost Buff", kind: Kind::Grant("Cursed Undead Boost") },
            Row { system: "aof", faction: "human_empire", rule: "Furious Buff", kind: Kind::Grant("Furious") },
            Row { system: "gf", faction: "blessed_sisters", rule: "Guarded Buff", kind: Kind::Grant("Guarded") },
            Row { system: "gf", faction: "soul_snatcher_cults", rule: "Increased Shooting Range Buff", kind: Kind::Inert },
            Row { system: "aof", faction: "ogres", rule: "Melee Evasion Buff", kind: Kind::Grant("Melee Evasion") },
            Row { system: "gf", faction: "human_defense_force", rule: "No Retreat Buff", kind: Kind::Grant("No Retreat") },
            Row { system: "aof", faction: "dark_elves", rule: "Piercing Assault Buff", kind: Kind::Grant("Piercing Assault") },
            Row { system: "aof", faction: "human_empire", rule: "Precision Shooter Buff", kind: Kind::HitMod(1, "shooting") },
            Row { system: "gf", faction: "robot_legions", rule: "Self-Repair Boost Buff", kind: Kind::Grant("Self-Repair Boost") },
            Row { system: "aof", faction: "havoc_dwarves", rule: "Steadfast Buff", kind: Kind::Grant("Steadfast") },
            Row { system: "aof", faction: "deep_sea_elves", rule: "Stealth Buff", kind: Kind::StealthAlias(1, 9.0) },
            Row { system: "aof", faction: "kingdom_of_angels", rule: "Versatile Attack Buff", kind: Kind::Grant("Versatile Attack") },
        ]
    }

    /// The row's carrier: a single-model unit whose ONLY printed rule is the
    /// REAL registry entry, plus one 24" rifle (silent on a HOLD without a
    /// shoot pick; the reach the stealth row's over-9" gate clamps). The
    /// REAL `build_for` product, read at `epoch`.
    fn carrier(system: &str, faction: &str, rule: &str, epoch: u32) -> UnitStatic {
        let p = Profile {
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
            special_rules: vec![rule.into()],
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
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// The row's board: bearer "a" at the origin, friend "in" 5" away
    /// (inside the printed 12" pick range, Tough 2 — value 3 beats the
    /// bearer's own, so the pick lands on IT), and friend "out" 15" away
    /// (beyond the pick range, Tough 9 — a value that would win the pick if
    /// the range gate leaked). ah/bh field no models. All one player.
    fn buff_line(system: &str, faction: &str, rule: &str) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.player = vec![0, 0, 0, 0];
        st.alive = vec![1, 0, 1, 1];
        st.wounds = vec![vec![1], vec![], vec![1], vec![1]];
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[5.0 * IN2M, 0.0, 0.0]],
            vec![[15.0 * IN2M, 0.0, 0.0]],
        ];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M], vec![IN2M]];
        let mut inside = UnitStatic { name: "in".into(), ..Default::default() };
        inside.ctx.tough = 2;
        let mut outside = UnitStatic { name: "out".into(), ..Default::default() };
        outside.ctx.tough = 9;
        (
            st,
            vec![
                carrier(system, faction, rule, crate::acts::CURRENT_RULES_EPOCH),
                UnitStatic { name: "ah".into(), ..Default::default() },
                inside,
                outside,
            ],
        )
    }

    /// One HOLD activation of the bearer — the pre-attack slot the utility
    /// tray occupies (right after Mend + Breath Attack), dice-free.
    fn run_line(st: &State, statics: &[UnitStatic]) -> State {
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: None,
            charge: None, patient: false, split: None, traced: None, teleport: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
            .0
    }

    /// One 2-attack rifle volley AT `us` at centre distance `dist_in` — the
    /// defender's ctx carries the stealth row's alias numbers.
    fn incoming_volley(us: &UnitStatic, dist_in: f64) -> crate::dice::ShootResult {
        let profiles = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[2], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(
            &strikers, &us.ctx, "Target", dist_in, dist_in, false, false, false, false, &mut tray,
        )
    }

    /// THE family test: the 13 `none` buffs rows, one table, each pinned by
    /// its exact name at `CURRENT_RULES_EPOCH` — the record rows through the
    /// real board fold (the in-range pick stamped, the out-of-range friend
    /// never), the Stealth-primitive row through the alias walk and the
    /// volley seam.
    #[test]
    fn the_thirteen_utility_buff_rows_stamp_their_numbers_at_current_epoch() {
        let table = rows();
        assert_eq!(table.len(), 13, "the buffs family's `none` rows are exactly these 13");
        for row in &table {
            if let Kind::StealthAlias(pen, over) = row.kind {
                // "Stealth Buff" (aof deep_sea_elves): the Stealth-primitive
                // DATA alias — `stealth_alias_of`'s best `hit_penalty` walk,
                // never the literal-Stealth stamp and never a ledger record.
                let on = carrier(row.system, row.faction, row.rule, crate::acts::CURRENT_RULES_EPOCH);
                assert_eq!(on.ctx.stealth_alias_penalty, pen, "{}: the entry's own hit_penalty", row.rule);
                assert_eq!(on.ctx.stealth_alias_over_in, over, "{}: the entry's own over-in gate", row.rule);
                assert!(!on.ctx.stealth_alias_applies_charged, "{}: no charged leg is printed", row.rule);
                assert!(!on.ctx.stealth, "{}: the alias, never the literal-Stealth stamp", row.rule);
                assert!(on.utility_buffs.is_empty(), "{}: a Stealth-primitive name rides no Utility-Buff record", row.rule);
                let far = incoming_volley(&on, 12.0);
                assert_eq!(
                    far.rolls[0].target, 4 + pen,
                    "{}: past the {}\" gate the to-hit target pays the {}", row.rule, over as i64, pen
                );
                let near = incoming_volley(&on, 6.0);
                assert_eq!(near.rolls[0].target, 4, "{}: inside the {}\" gate the target stands", row.rule, over as i64);
                continue;
            }
            let (st, statics) = buff_line(row.system, row.faction, row.rule);
            let next = run_line(&st, &statics);
            assert!(
                next.buffs[3].is_empty(),
                "{}: the 15\" friend is beyond the printed 12\" pick range and is never stamped -- got {:?}",
                row.rule, next.buffs[3]
            );
            if let Kind::Inert = row.kind {
                assert!(
                    next.buffs.iter().all(|v| v.is_empty()),
                    "{}: the all-zero row (range_bonus_in is not modeled) is dropped -- got {:?}",
                    row.rule, next.buffs
                );
                let ub = statics[0].utility_buffs.first().expect("the row IS read off the registry");
                assert_eq!(ub.name, "Increased Shooting Range Buff", "the row is read by its exact name");
                assert_eq!(
                    (ub.hit_mod, ub.casting_mod, ub.morale_mod, ub.ap_mod, ub.def_mod, ub.defense_mod, ub.move_mod),
                    (0, 0, 0, 0, 0, 0, 0),
                    "no modeled knob: the record fold drops the row"
                );
                assert!(ub.grants_rule.is_empty(), "no grant either");
                continue;
            }
            assert_eq!(next.buffs[2].len(), 1, "{}: one record on the in-range pick", row.rule);
            let rec = &next.buffs[2][0];
            assert_eq!(&*rec.name, row.rule, "{}: the record names the rule exactly", row.rule);
            assert!(rec.once, "{}: the once-per-activation promise rides the record", row.rule);
            match row.kind {
                Kind::Grant(g) => assert_eq!(&*rec.grants_rule, g, "{}: the record carries the printed grant", row.rule),
                Kind::HitMod(n, scope) => {
                    assert_eq!(rec.hit_mod, n, "{}: the entry's own hit_mod", row.rule);
                    assert_eq!(&*rec.scope, scope, "{}: the entry's own scope", row.rule);
                }
                _ => unreachable!("only the two record kinds remain"),
            }
            assert!(
                next.buffs[0].is_empty(),
                "{}: the in-range friend outranks the bearer (3 vs 2), the bearer stays unstamped -- got {:?}",
                row.rule, next.buffs[0]
            );
        }
    }
