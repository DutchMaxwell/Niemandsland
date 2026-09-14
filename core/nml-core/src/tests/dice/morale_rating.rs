use super::*;
use crate::state::Profile;
use crate::unit::capture_reads_for_epoch;

    // ---- EPOCH_39_MORALE_RATING: the Morale(X) primitive joins the morale test ---

    /// The fixture, end to end through the REAL registry: a Morale(2) carrier
    /// (the gf COMMON block fields `{"primitive": "Morale", "params":
    /// {"rating": "X"}}` — the value 2 is the raw rule string's own
    /// `Morale(2)`), no Banner, Quality 4. The table folds the rating into the
    /// SAME number as the Banner bonus (`SoloController.morale_bonus_of` =
    /// Banner best-of over unit + attached heroes PLUS `morale_rating_of`'s
    /// rating best-of, solo_controller.gd:5638, the rating walk :5642-5653)
    /// and the morale test consumes that one number (main.gd:8586 ->
    /// `_solo_morale_bonus`); the capture stamps it as ONE dict value
    /// (battle_sim.gd:1598). The core's capture twin read the Banner half
    /// only, so every core-driven Morale carrier tested X too low. The plain
    /// Quality 4+ target fails on a 3 by exactly 1; with the rating the
    /// target is 2+ and the same die passes.
    const MORALE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Morale(2)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn morale_profile() -> Profile {
        let header = read_act_header(MORALE_HEADER).expect("header");
        header.profiles.get("carrier").expect("carrier").clone()
    }

    /// The capture twin's stamp, by epoch: below 39 the pre-port reading
    /// (Banner-only), at 39 the table's one number. 35 is the live stamp this
    /// wave moves off of; 38 is the epoch immediately below the bump at
    /// rebase time — both pinned so the OLD leg survives whichever epochs
    /// land first.
    #[test]
    fn the_capture_twin_folds_the_rating_from_39_not_below() {
        let p = morale_profile();
        let stamp = |epoch: u32| {
            let mut reg = Registries::new(&repo_root());
            capture_reads_for_epoch(&mut reg, &p, epoch).morale_bonus
        };
        assert_eq!(
            stamp(35), 0,
            "epoch 35 (the live stamp): the rating is NOT folded — every recorded game replays"
        );
        assert_eq!(
            stamp(38), 0,
            "epoch 38: still the pre-port reading (EPOCH_39_MORALE_RATING is frozen)"
        );
        assert_eq!(
            stamp(39), 2,
            "epoch 39: Morale(2) rides the SAME morale_bonus stamp the table's morale_bonus_of writes (battle_sim.gd:1598)"
        );
    }

    /// RED/GREEN through the REAL tray, along the REAL data path (capture
    /// stamp -> state dict -> ctx -> rolled test): the same die (seed 8 shows
    /// 3 — one under the plain Quality 4+ target) fails the test at 38 and
    /// passes it at 39, where the stamp carries the +2. No Banner, no spell
    /// mods, melee=false so a fail is Shaken and never a Rout.
    #[test]
    fn a_morale_2_carrier_fails_the_test_at_38_and_passes_it_at_39() {
        let p = morale_profile();
        let stamp = |epoch: u32| {
            let mut reg = Registries::new(&repo_root());
            capture_reads_for_epoch(&mut reg, &p, epoch).morale_bonus
        };
        let ctx38 = Ctx { quality: 4, morale_bonus: stamp(38), ..Default::default() };
        let (out38, r38) =
            resolve_morale_with_tray(&ctx38, "Carrier", false, false, false, 1, &mut Tray::seeded(8));
        assert_eq!(r38.rolls[0].target, 4, "38: the plain Quality 4+ target");
        assert_eq!(out38, Morale::Shaken, "the die shows 3 — one under the target");
        let ctx39 = Ctx { quality: 4, morale_bonus: stamp(39), ..Default::default() };
        let (out39, r39) =
            resolve_morale_with_tray(&ctx39, "Carrier", false, false, false, 1, &mut Tray::seeded(8));
        assert_eq!(r39.rolls[0].target, 2, "39: Quality 4 - 2 = the 2+ target");
        assert_eq!(out39, Morale::Passed, "the same die 3 now passes");
    }

    /// The GREEN split pin: the statics carry the rating SEPARATELY for the
    /// rules-must-log line (`sim::tray_morale`), while the EV ctx keeps the
    /// table's own Banner-only reading (ai_ev.gd:142-143) — only the ROLLED
    /// test adds the rating, through the capture stamp.
    #[test]
    fn the_ctx_stamp_carries_the_rating_split_for_the_log_line() {
        let p = morale_profile();
        let mut reg = Registries::new(&repo_root());
        let us38 = UnitStatic::build_for(&mut reg, &p, 38);
        assert_eq!(us38.ctx.morale_rating, 0, "38: no split below the gate");
        assert_eq!(us38.ctx.morale_bonus, 0, "and the EV stamp stays banner-only");
        let us39 = UnitStatic::build_for(&mut reg, &p, 39);
        assert_eq!(us39.ctx.morale_rating, 2, "39: the split rides the statics");
        assert_eq!(
            us39.ctx.morale_bonus, 0,
            "the EV ctx keeps the banner-only reading (ai_ev.gd:142-143)"
        );
    }
