use super::*;

    // ---------------- Aura Channel (rules-wave3-aura1, epoch 6) --------------

    #[test]
    fn a_furious_aura_grants_furious_to_its_unit_at_epoch_6() {
        assert!(aura_static("Furious Aura", "alien_hives", 6).ctx.furious);
        assert!(!aura_static("Furious Aura", "alien_hives", 5).ctx.furious, "epoch 5 keeps the import-fold-only reading");
        assert!(!aura_static("", "alien_hives", 6).ctx.furious, "no aura entry, no grant");
    }

    #[test]
    fn a_steadfast_aura_grants_steadfast_to_its_unit_at_epoch_6() {
        assert!(aura_static("Steadfast Aura", "change_disciples", 6).steadfast_active);
        assert!(!aura_static("Steadfast Aura", "change_disciples", 5).steadfast_active);
        assert!(!aura_static("", "change_disciples", 6).steadfast_active);
    }

    #[test]
    fn a_resistance_aura_grants_resistance_to_its_unit_at_epoch_6() {
        assert_eq!(aura_static("Resistance Aura", "change_disciples", 6).ctx.regen_target, 6);
        assert_eq!(aura_static("Resistance Aura", "change_disciples", 5).ctx.regen_target, 0);
        assert_eq!(aura_static("", "change_disciples", 6).ctx.regen_target, 0);
    }

    #[test]
    fn an_unpredictable_fighter_aura_grants_the_fighter_at_epoch_6() {
        assert!(aura_static("Unpredictable Fighter Aura", "dwarf_guilds", 6).ctx.unpredictable);
        assert!(!aura_static("Unpredictable Fighter Aura", "dwarf_guilds", 5).ctx.unpredictable);
        assert!(!aura_static("", "dwarf_guilds", 6).ctx.unpredictable);
    }

    #[test]
    fn a_versatile_defense_aura_guards_its_unit_at_epoch_6() {
        assert!(aura_static("Versatile Defense Aura", "change_disciples", 6).ctx.guarded);
        assert!(!aura_static("Versatile Defense Aura", "change_disciples", 5).ctx.guarded);
        assert!(!aura_static("", "change_disciples", 6).ctx.guarded);
    }

    #[test]
    fn a_counter_attack_aura_strikes_first_in_melee_at_epoch_6() {
        assert!(aura_static("Counter-Attack Aura", "dao_union", 6).melee.iter().all(|sp| sp.counter));
        assert!(!aura_static("Counter-Attack Aura", "dao_union", 5).melee.iter().any(|sp| sp.counter));
        assert!(!aura_static("", "dao_union", 6).melee.iter().any(|sp| sp.counter));
    }

    #[test]
    fn a_no_retreat_aura_grants_no_retreat_at_epoch_6() {
        assert!(aura_static("No Retreat Aura", "infected_colonies", 6).ctx.no_retreat);
        assert!(!aura_static("No Retreat Aura", "infected_colonies", 5).ctx.no_retreat);
        assert!(!aura_static("", "infected_colonies", 6).ctx.no_retreat);
    }

    #[test]
    fn a_fortified_aura_fortifies_its_unit_at_epoch_6() {
        assert!(aura_static("Fortified Aura", "blessed_sisters", 6).ctx.fortified);
        assert!(!aura_static("Fortified Aura", "blessed_sisters", 5).ctx.fortified);
        assert!(!aura_static("", "blessed_sisters", 6).ctx.fortified);
    }

    #[test]
    fn an_unpredictable_shooter_aura_grants_the_shooter_at_epoch_6() {
        assert!(aura_static("Unpredictable Shooter Aura", "infected_colonies", 6).ctx.unpredictable_shooting);
        assert!(!aura_static("Unpredictable Shooter Aura", "infected_colonies", 5).ctx.unpredictable_shooting);
        assert!(!aura_static("", "infected_colonies", 6).ctx.unpredictable_shooting);
    }

    #[test]
    fn a_hit_and_run_shooter_aura_grants_the_shooter_at_epoch_6() {
        assert!(aura_static("Hit & Run Shooter Aura", "custodian_brothers", 6).hit_and_run_shooter_active);
        assert!(!aura_static("Hit & Run Shooter Aura", "custodian_brothers", 5).hit_and_run_shooter_active);
        assert!(!aura_static("", "custodian_brothers", 6).hit_and_run_shooter_active);
    }

    #[test]
    fn a_ranged_shrouding_aura_shrouds_its_unit_at_epoch_6() {
        assert!(aura_static("Ranged Shrouding Aura", "custodian_brothers", 6).ctx.ranged_shrouding);
        assert!(!aura_static("Ranged Shrouding Aura", "custodian_brothers", 5).ctx.ranged_shrouding);
        assert!(!aura_static("", "custodian_brothers", 6).ctx.ranged_shrouding);
    }

    #[test]
    fn a_melee_shrouding_aura_shrouds_the_charge_at_epoch_6() {
        assert_eq!(aura_capture("Melee Shrouding Aura", "battle_brothers", 6).shroud, Some([3.0, 6.0]));
        assert_eq!(aura_capture("Melee Shrouding Aura", "battle_brothers", 5).shroud, None);
        assert_eq!(aura_capture("", "battle_brothers", 6).shroud, None);
    }

    #[test]
    fn an_unstoppable_in_melee_aura_banes_melee_at_epoch_6() {
        assert!(aura_static("Unstoppable in Melee Aura", "custodian_brothers", 6).melee.iter().all(|sp| sp.bane));
        assert!(!aura_static("Unstoppable in Melee Aura", "custodian_brothers", 5).melee.iter().any(|sp| sp.bane));
        assert!(!aura_static("", "custodian_brothers", 6).melee.iter().any(|sp| sp.bane));
    }

    #[test]
    fn a_shred_in_melee_aura_shreds_melee_at_epoch_6() {
        assert!(aura_static("Shred in Melee Aura", "blessed_sisters", 6).melee.iter().all(|sp| sp.shred_alias));
        assert!(!aura_static("Shred in Melee Aura", "blessed_sisters", 5).melee.iter().any(|sp| sp.shred_alias));
        assert!(!aura_static("", "blessed_sisters", 6).melee.iter().any(|sp| sp.shred_alias));
    }

    #[test]
    fn a_shred_when_shooting_aura_shreds_shooting_at_epoch_6() {
        assert!(aura_static("Shred when Shooting Aura", "custodian_brothers", 6).shoot.iter().all(|sp| sp.shred_alias));
        assert!(!aura_static("Shred when Shooting Aura", "custodian_brothers", 5).shoot.iter().any(|sp| sp.shred_alias));
        assert!(!aura_static("", "custodian_brothers", 6).shoot.iter().any(|sp| sp.shred_alias));
    }
