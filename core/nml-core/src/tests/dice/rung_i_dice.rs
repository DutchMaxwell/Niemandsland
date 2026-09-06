use super::*;

    // ------------- Rung I (audit 2026-09-02, DEFECT_LEDGER row 31): the dice

    /// Condition kind 1 — `on_charge` (Piercing Assault): AP(+1) only while
    /// charging. RED before this rung: the dice save stayed at Defense 4+ in
    /// both rows, because `resolve_melee_with_tray` never read `p.cond_ap`.
    #[test]
    fn piercing_assault_raises_the_melee_save_ap_only_while_charging() {
        let us = cond_ap_static("piercing_assault");
        let p = [us.melee[0].clone()];
        let def = defender(4, 5);
        let mut t1 = Tray::seeded(27);
        let charging = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &def, "Target", true, true, true, &mut t1);
        assert_eq!(charging.rolls[1].target, 5, "AP(+1) on the charge: Defense 4+ -> 5+");
        let mut t2 = Tray::seeded(27);
        let steady = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &def, "Target", false, true, true, &mut t2);
        assert_eq!(steady.rolls[1].target, 4, "no charge: Piercing Assault stays silent");
    }

    /// The `cond_ap_dice` knob itself (`Knobs::cond_ap_dice` / `Seams::cond_ap_dice`,
    /// DEFECT_LEDGER row 31): a legacy-vintage replay (knob OFF, what every
    /// corpus recorded before this rung carries) rolls the SAME charging
    /// Piercing Assault attack with no AP at all — byte-identical to the old
    /// engine `~/selfplay_out/gen0_teacher` was recorded with; the shipped
    /// setting (ON) applies it. RED if the `if cond_ap_dice` guard in
    /// `resolve_melee_with_tray` is dropped: the "off" row would flip to 5+.
    #[test]
    fn the_cond_ap_dice_knob_off_replays_legacy_and_on_applies_the_fix() {
        let us = cond_ap_static("piercing_assault");
        let p = [us.melee[0].clone()];
        let def = defender(4, 5);
        let mut off = Tray::seeded(27);
        let legacy = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &def, "Target", true, false, true, &mut off);
        assert_eq!(legacy.rolls[1].target, 4, "knob OFF: charging Piercing Assault still saves at 4+");
        let mut on = Tray::seeded(27);
        let shipped = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &def, "Target", true, true, true, &mut on);
        assert_eq!(shipped.rolls[1].target, 5, "knob ON: the same charge now saves at 5+");
    }

// --- Wave 2 granted-rule READS: legs folded in `sim::ctx_live` (gated there).

    #[test]
    fn the_versatile_attack_buff_picks_the_shoot_arm_over_9_in() {
        let p = [rifle(8)];
        let def = defender(4, 5);
        let mut t1 = Tray::seeded(27);
        let on = Ctx { quality: 4, versatile_grant: true, ..shooter(4) };
        let mut t2 = Tray::seeded(27);
        let g = resolve_volley_with_tray(&[striker(&p, &[0], &[8], &on)], &def, "Target", 12.0, 12.0, true, true, true, false, &mut t1);
        let pl = resolve_volley_with_tray(&[striker(&p, &[0], &[8], &shooter(4))], &def, "Target", 12.0, 12.0, true, true, true, false, &mut t2);
        assert!(g.rolls[1].target != pl.rolls[1].target || g.rolls[0].target != pl.rolls[0].target,
            "the granted pick_one must move a target");
    }

    #[test]
    fn the_slayer_mark_folds_granted_ap_vs_tough_3_at_both_legs() {
        let p = [rifle(8)];
        let tough = Ctx { defense: 4, models: 5, tough: 3, ..defender(4, 5) };
        let mut t1 = Tray::seeded(27);
        let on = Ctx { quality: 4, slayer_grant: true, ..shooter(4) };
        let mut t2 = Tray::seeded(27);
        let g = resolve_volley_with_tray(&[striker(&p, &[0], &[8], &on)], &tough, "Target", 12.0, 12.0, true, true, true, false, &mut t1);
        assert_eq!(g.rolls[1].target, 6, "over 9\" vs Tough 3+: the granted AP(+2) lands");
        let pl = resolve_volley_with_tray(&[striker(&p, &[0], &[8], &shooter(4))], &tough, "Target", 12.0, 12.0, true, true, true, false, &mut t2);
        assert_eq!(pl.rolls[1].target, 4, "no grant, no AP");
        let mut t3 = Tray::seeded(27);
        let blades = [blade(6)];
        let m = resolve_melee_with_tray(&[striker(&blades, &[0], &[6], &on)], &tough, "Target", true, true, true, &mut t3);
        assert_eq!(m.rolls[1].target, 6, "charging vs Tough 3+: the melee leg lands too");
    }

    #[test]
    fn the_piercing_assault_buff_folds_granted_ap_on_the_charge() {
        let blades = [blade(6)];
        let def = defender(4, 5);
        let mut t1 = Tray::seeded(27);
        let on = Ctx { quality: 4, pierce_assault_grant: true, ..shooter(4) };
        let mut t2 = Tray::seeded(27);
        let c = resolve_melee_with_tray(&[striker(&blades, &[0], &[6], &on)], &def, "Target", true, true, true, &mut t1);
        assert_eq!(c.rolls[1].target, 5, "the granted on_charge AP(+1) lands");
        let s = resolve_melee_with_tray(&[striker(&blades, &[0], &[6], &on)], &def, "Target", false, true, true, &mut t2);
        assert_eq!(s.rolls[1].target, 4, "no charge: the granted condition stays shut");
    }

    #[test]
    fn the_piercing_shooting_and_fighting_marks_fold_their_flat_ap() {
        let p = [rifle(8)];
        let def = defender(4, 5);
        let mut t1 = Tray::seeded(27);
        let sg = Ctx { quality: 4, pierce_shooting_grant: true, ..shooter(4) };
        let g = resolve_volley_with_tray(&[striker(&p, &[0], &[8], &sg)], &def, "Target", 12.0, 12.0, true, true, true, false, &mut t1);
        assert_eq!(g.rolls[1].target, 5, "AP(+1) when shooting");
        let blades = [blade(6)];
        let mut t2 = Tray::seeded(27);
        let mg = Ctx { quality: 4, pierce_melee_grant: true, ..shooter(4) };
        let mut t3 = Tray::seeded(27);
        let m = resolve_melee_with_tray(&[striker(&blades, &[0], &[6], &mg)], &def, "Target", false, true, true, &mut t2);
        assert_eq!(m.rolls[1].target, 5, "AP(+1) in melee");
        let pl = resolve_volley_with_tray(&[striker(&p, &[0], &[8], &shooter(4))], &def, "Target", 12.0, 12.0, true, true, true, false, &mut t3);
        assert_eq!(pl.rolls[1].target, 4, "the marks ride their grant, not the bearer");
    }

    #[test]
    fn the_primal_boost_buff_draws_the_granted_low_surge_dice() {
        let blades = [blade(6)];
        let on = Ctx { quality: 4, surge_grant: true, ..shooter(4) };
        let mut t1 = Tray::seeded(27);
        let def = defender(4, 5);
        let mut t2 = Tray::seeded(27);
        let g = resolve_melee_with_tray(&[striker(&blades, &[0], &[6], &on)], &def, "Target", false, true, true, &mut t1);
        let pl = resolve_melee_with_tray(&[striker(&blades, &[0], &[6], &shooter(4))], &def, "Target", false, true, true, &mut t2);
        let attacks = |r: &ShootResult| r.rolls.iter().filter(|x| x.kind == "attack").count();
        assert_eq!(attacks(&g) - attacks(&pl), 1, "the low-surge draw is its own extra attack roll");
    }

    /// The CLASS FIX (external review 03.09. item 3 / F9, `acts::rule_on`):
    /// this rule's effective reading at its two `sim.rs` call sites is
    /// `seams.cond_ap_dice || rule_on(seams.rules_epoch, 1)`. `rules_epoch: 0`
    /// (every pre-epoch corpus, this test's own boolean-OFF row above
    /// included) must still resolve with no AP at all;
    /// `rules_epoch: CURRENT_RULES_EPOCH` — what a fresh `play_game()`
    /// stamps — turns the SAME rule on even with the boolean itself left
    /// `false`, exactly the `versatile_reach` sibling test (sim.rs) proves
    /// for its rule.
    #[test]
    fn the_cond_ap_dice_epoch_gate_matches_the_knob_gate() {
        use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
        let us = cond_ap_static("piercing_assault");
        let p = [us.melee[0].clone()];
        let def = defender(4, 5);
        let mut off = Tray::seeded(27);
        let legacy = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &def, "Target", true,
            false || rule_on(0, 1), true, &mut off);
        assert_eq!(legacy.rolls[1].target, 4, "epoch 0, knob false: still saves at 4+");
        let mut on = Tray::seeded(27);
        let shipped = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &def, "Target", true,
            false || rule_on(CURRENT_RULES_EPOCH, 1), true, &mut on);
        assert_eq!(shipped.rolls[1].target, 5, "epoch CURRENT_RULES_EPOCH, knob false: now saves at 5+");
    }
