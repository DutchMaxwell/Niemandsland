use super::*;

    /// Audit 2026-09-13 §2.4 — Sturdy + Sturdy Boost must be ONE +1: the Boost
    /// replaces the base rule's over-9" condition with "always", so the two
    /// readings MAX, never stack. Today the dice fold subtracts in sequence —
    /// `shielded_defense` then `guarded_defense` (dice.rs:989-990) — and the
    /// Dwarf Guilds board from the audit plays 2+ where the book says 3+.
    ///
    /// RED on the volley fold: Defense 4+, Sturdy + Sturdy Boost, AP(1) from
    /// 12" — the save target is 4+ (one +1), not 3+ (two).
    #[test]
    fn sturdy_boost_replaces_the_distance_gate_instead_of_stacking_with_it() {
        let def = Ctx {
            shielded: true,
            shielded_alias: crate::unit::ShieldedAlias::SturdyBoost,
            guarded: true,
            sturdy_boost_gates_guarded: true,
            ..defender(4, 5)
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ap_rifle(64)], &[0], &[64], &shooter(4), &def, 12.0, &mut tray,
        );
        assert_eq!(
            out.rolls[1].target, 4,
            "book: the Boost removes the gate, the +1 fires once — 3+ vs AP(1) saves on 4+"
        );
    }

    /// Under 9" the gate never fired, so base and Boost already agreed — the
    /// fix must not move the close-range reading.
    #[test]
    fn under_nine_inches_base_and_boost_already_agree() {
        let def = Ctx {
            shielded: true,
            shielded_alias: crate::unit::ShieldedAlias::SturdyBoost,
            guarded: true,
            sturdy_boost_gates_guarded: true,
            ..defender(4, 5)
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ap_rifle(64)], &[0], &[64], &shooter(4), &def, 9.0, &mut tray,
        );
        assert_eq!(out.rolls[1].target, 4, "one +1 at close range too");
    }

    /// The OLD leg, epoch 12 (the stamp's own gate, `EPOCH_13_WHO_WINS`): a
    /// record whose alias already supplied the shielded half keeps the
    /// STACKED reading — the dice fold must not re-date it.
    #[test]
    fn at_epoch_12_the_boost_still_stacks_with_its_base() {
        let def = Ctx {
            shielded: true,
            shielded_alias: crate::unit::ShieldedAlias::SturdyBoost,
            guarded: true,
            sturdy_boost_gates_guarded: false,
            ..defender(4, 5)
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ap_rifle(64)], &[0], &[64], &shooter(4), &def, 12.0, &mut tray,
        );
        assert_eq!(
            out.rolls[1].target, 3,
            "epoch 12 replays the old stack: shielded -1 then guarded -1"
        );
    }

    /// The stamp wiring itself: a Sturdy Boost carrier stamps the gate flag
    /// at 13, not at 12 — the pair the dice fold reads.
    #[test]
    fn the_gate_flag_stamps_at_thirteen_not_twelve() {
        let tpl = r#"{"kind":"header","knobs":{},"profiles":{
          "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
            "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
            "base_radius":0.016,"game_system":"gf","faction_folder":"dwarf_guilds",
            "special_rules":["Sturdy","Sturdy Boost"],"item_grants":[],
            "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
            "weapons":[{"name":"Blade","range":0,"attacks":1,"count":1,"rules":[]}]}}}"#;
        let header = read_act_header(tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        let on = UnitStatic::build_for(&mut reg, p, 13);
        assert!(on.ctx.sturdy_boost_gates_guarded, "epoch 13: the Boost replaces the gate");
        let mut reg = Registries::new(&repo_root());
        let off = UnitStatic::build_for(&mut reg, p, 12);
        assert!(!off.ctx.sturdy_boost_gates_guarded, "epoch 12 replays the old stack");
    }