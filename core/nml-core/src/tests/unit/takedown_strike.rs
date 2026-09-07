use super::*;

    // --- Wave 4 follow-up (port-takedown-strike, epoch 7) ---
    //
    // "Takedown Strike" (gf x5 / aof x7, primitive Takedown): "Once per game,
    // when it's this model's turn to attack in melee, it may make one attack
    // at Quality 2+ with AP(2), Deadly(3), and Takedown." Table:
    // `_solo_takedown_bonus_groups` main.gd:16756, joined into the strike
    // groups at :6032-6034 — a synthetic single-attack group at its OWN
    // Quality, spent once per game per bearer (`takedown_bonus_used_<name>`).
    // Core seam: a synthetic LIMITED melee profile appended by the stamp (the
    // existing `limited_used` ledger is the once-per-game shape the dice.rs
    // doc note points at), and the melee fold reading the profile's own
    // Quality override. One RED/GREEN test through the REAL registry, plus
    // one epoch test. The epoch literals here are 7/6, never
    // `CURRENT_RULES_EPOCH`, so a wave-5 bump cannot re-date these
    // assertions.

    /// The family's carrier template: one blade, so the melee array is
    /// non-empty (the Strike bonus group is melee-only by its own name).
    const TS_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ogres",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,
          "rules":[]}]}}}"#;

    /// The REAL `build_for` product of a carrier carrying `rules` in
    /// aof/ogres, read at `epoch`.
    fn ts_unit(rules: &[&str], epoch: u32) -> UnitStatic {
        let printed =
            rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = TS_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("TS_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// A plain Defense-4 target of one Tough(1) model.
    fn target() -> Ctx {
        Ctx { defense: 4, models: 1, tough: 1, ..Default::default() }
    }

    /// One strike phase with EVERY melee profile of `us` against `def`.
    fn strike(us: &UnitStatic, def: &Ctx) -> crate::dice::ShootResult {
        let n = us.melee.len();
        let profiles: Vec<_> = us.melee.iter().cloned().collect();
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles,
            keep: &(0..n).collect::<Vec<usize>>(),
            attacks: &vec![1i64; n],
            att: &att,
            owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_melee_with_tray(&strikers, def, "def", false, false, false, &mut tray)
    }

    fn logged(out: &crate::dice::ShootResult, needle: &str) -> bool {
        out.log.iter().any(|l| l.contains(needle))
    }

    /// The bearer's melee array gains the synthetic once-per-game bonus group
    /// (main.gd:16756's shape: one attack, AP(2), Deadly(3), Takedown,
    /// Limited-spend) and the strike phase rolls it at the entry's OWN
    /// Quality (2+, the printed text) — RED before the port, which has no
    /// second melee profile and no Quality-2 strike at all.
    #[test]
    fn takedown_strike_appends_the_once_per_game_bonus_group_at_epoch_7() {
        let us = ts_unit(&["Takedown Strike"], 7);
        assert_eq!(us.melee.len(), 2, "epoch 7: the bonus group is its OWN profile (RED before the port)");
        let b = &us.melee[1];
        assert_eq!(b.name, "Takedown Strike", "the ledger key is the rule name (the table's `takedown_bonus_used_<name>`)");
        assert_eq!(b.attacks, 1, "one attack, never scaled with the unit");
        assert_eq!(b.ap, 2, "AP(2), the printed text");
        assert_eq!(b.deadly, 3, "Deadly(3), the printed text");
        assert!(b.takedown, "and Takedown — the existing landing path");
        assert!(b.limited, "once per game — the `limited_used` ledger shape");
        let out = strike(&us, &target());
        assert!(
            out.rolls.iter().any(|r| r.kind == "attack" && r.target == 2),
            "epoch 7: the bonus attack rolls at Quality 2+ (RED before the port): {:?}",
            out.rolls.iter().map(|r| (r.kind.as_str(), r.target)).collect::<Vec<_>>()
        );
        assert!(
            logged(&out, "Takedown Strike"),
            "rules-must-log: the bonus group names itself (RED before the port): {:?}",
            out.log
        );
        // A bearer-less unit gains nothing.
        let none = ts_unit(&[], 7);
        assert_eq!(none.melee.len(), 1, "no rule, no bonus group");
    }

    /// EPOCH TEST: a record stamped 6 sees the old behaviour exactly — the
    /// melee array stays the weapon's own, no Quality-2 strike, no log line.
    /// The name read is born at 7.
    #[test]
    fn takedown_strike_is_inert_below_epoch_7() {
        for epoch in [7u32, 6] {
            let us = ts_unit(&["Takedown Strike"], epoch);
            let out = strike(&us, &target());
            assert_eq!(
                out.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "att").count(),
                1,
                "epoch {epoch}: the blade's single strike slot only"
            );
            if epoch == 6 {
                assert!(!logged(&out, "Takedown Strike"), "epoch 6: nothing fires, nothing logs");
                assert!(
                    !out.rolls.iter().any(|r| r.kind == "attack" && r.target == 2),
                    "epoch 6: no Quality-2 strike"
                );
            }
        }
    }
