use super::*;

    // ------------------------------------------------- BLOCK B11: Quick Shot ---

    /// A Quick Shot carrier's RUSH still rolls its volley, and the activation
    /// names the rule (rules-must-log).
    #[test]
    fn quick_shot_lets_a_rush_action_fire_its_volley() {
        let (st, mut statics) = buff_line();
        statics[0].quick_shot_active = true;
        let (_, shot) = run_buff(&st, &statics, &rush_shoot("b"), 11);
        assert!(!shot.rolls.is_empty());
        assert!(shot.log.iter().any(|l| l.starts_with("Quick Shot:")));
    }

    /// The same RUSH, no rule: no volley, no log line — RUSH stays a move-only
    /// action for every carrier that does not have Quick Shot.
    #[test]
    fn without_quick_shot_a_rush_action_never_shoots() {
        let (st, statics) = buff_line();
        let (_, shot) = run_buff(&st, &statics, &rush_shoot("b"), 11);
        assert!(shot.rolls.is_empty());
        assert!(shot.log.is_empty());
    }

    /// ADVANCE already shoots regardless of Quick Shot — B11 only widens the
    /// predicate to include RUSH, it must not touch ADVANCE's own gate.
    #[test]
    fn advance_shoots_with_or_without_quick_shot() {
        let (st, mut statics) = buff_line();
        let (_, without) = run_buff(&st, &statics, &advance_shoot("b"), 11);
        assert!(!without.rolls.is_empty());
        statics[0].quick_shot_active = true;
        let (_, with_rule) = run_buff(&st, &statics, &advance_shoot("b"), 11);
        assert!(!with_rule.rolls.is_empty());
    }
