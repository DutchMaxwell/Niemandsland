use super::*;

    // ------------------------------------------ block B3: the breath score ---

    /// The score is `min(Blast, alive) * (1 - block)`: a PRODUCT, so Alpha's
    /// 1.5 loses to Bravo's 1.67. Turning the multiply into a plus gives
    /// Alpha 3.5 against 2.83 — the pick flips and the save batch is signed
    /// "Alpha". Seed 5: the trigger die passes.
    #[test]
    fn the_breath_score_is_a_product_never_a_sum() {
        let (mut st, statics) = breath_scorer_line();
        assert_eq!(breath_save_owner(&statics, &mut st), "Bravo");
    }

    /// Same identity, quotient form: `min(Blast, alive) / (1 - block)` scores
    /// Alpha 6 against Bravo 2.4 — again the wrong unit signs the saves.
    #[test]
    fn the_breath_score_is_a_product_never_a_quotient() {
        let (mut st, statics) = breath_scorer_line();
        assert_eq!(breath_save_owner(&statics, &mut st), "Bravo");
    }

    /// The block chance is SUBTRACTED from one: `1 - block` discounts Alpha
    /// by half. `1 + block` inflates it to 1.5 and Alpha's 4.5 beats Bravo's
    /// 2.33 — the pick flips, the owner betrays it.
    #[test]
    fn the_breath_score_subtracts_the_block_chance_never_adds() {
        let (mut st, statics) = breath_scorer_line();
        assert_eq!(breath_save_owner(&statics, &mut st), "Bravo");
    }

    /// And never divides: `1 / block` AMPLIFIES the low-block unit — Alpha
    /// (2 alive, Defense 3: `2·1/2 = 1.0`, mutant `2·2 = 4`) must keep the
    /// pick against Bravo (1 alive, Defense 5: `1·5/6 ≈ 0.83`, mutant
    /// `1·6 = 6`), whose save batch then signs the wrong name.
    #[test]
    fn the_breath_score_uses_one_minus_block_never_one_over_block() {
        let (mut st, mut statics) = breath_scorer_line();
        st.alive[1] = 2;
        st.alive[2] = 1;
        assert_eq!(breath_save_owner(&statics, &mut st), "Alpha");
    }

    /// Two EQUAL scores (2 alive, Defense 3 each → 1.0 both) must keep the
    /// FIRST unit the scan met. A `>=` lets the later twin overwrite it.
    #[test]
    fn the_breath_pick_takes_the_first_of_equal_scores() {
        let (mut st, mut statics) = breath_scorer_line();
        st.alive[1] = 2;
        statics[2].ctx.defense = 3;
        assert_eq!(breath_save_owner(&statics, &mut st), "Alpha");
    }

    /// One breath PER ACTIVATION needs a LIVING bearer: a joined hero that
    /// carries the rule but is dead (alive 0) must not earn the trigger die
    /// for the flagless host. A `>=` on the bearer's alive check lets the
    /// corpse speak — a die lands on the tray anyway.
    #[test]
    fn a_dead_joined_bearer_earns_no_breath_die() {
        let (mut st, mut statics) = breath_scorer_line();
        statics[0].breath_attack_active = false;
        statics.push(UnitStatic {
            name: "Dead Hero".into(),
            breath_attack_active: true,
            ..Default::default()
        });
        st.player[1] = 0;
        st.alive[1] = 0;
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: HashMap::new(),
            profile: vec![0, 3, 2, 2],
        });
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        let mut shot = ShootResult::default();
        let mut tray = Tray::seeded(5);
        tray_breath_attack(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            &mut tray, &mut shot,
        );
        assert!(shot.rolls.is_empty(), "no living bearer, no breath die: {:?}", shot.rolls);
    }

    /// With the hero fold OFF, the target scan must still consider an enemy
    /// that is somebody's attached hero — `hero_attach && attached` only
    /// skips them under the seam. An `||` skips them always, and with Bravo
    /// dead the scan finds no target at all: no die is ever drawn.
    #[test]
    fn with_the_seam_off_an_attached_enemy_is_still_a_breath_target() {
        let (mut st, statics) = breath_scorer_line();
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.alive[2] = 0;
        let mut shot = ShootResult::default();
        let mut tray = Tray::seeded(5);
        tray_breath_attack(&statics, &mut st, 0, Seams::default(), &mut tray, &mut shot);
        assert!(
            shot.rolls.iter().any(|r| r.kind == "attack"),
            "the trigger die is drawn at the attached enemy: {:?}", shot.rolls
        );
    }
