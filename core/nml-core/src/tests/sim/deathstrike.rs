use super::*;

    // ------------------- block C4: Deathstrike / Self-Destruct, death-half ---

    /// (a) Deathstrike(2) on the defender, the phase lands 4 wounds into
    /// pools [1,3,1]: the two outer models die, the middle survives on 1
    /// wound left — the striker faces a 4-die save batch at its own Defense,
    /// AP 0, the lash lands on the striker, and the returned TALLY credit
    /// stays 0 (main.gd:6174 touches no `_solo_retaliate_credit`).
    #[test]
    fn deathstrike_throws_two_hits_per_killed_model_at_the_striker() {
        let (mut st, mut statics) = duel(0);
        statics[1].ctx.death_hits_per_kill = 2;
        st.wounds[1] = vec![1, 3, 1]; // seed 9 lands 4: exactly the outer two die
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (_, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        assert_eq!(st.alive[1], 1, "fixture: exactly the two outer models die");
        let lash = shot.rolls.last().expect("the dying-models save batch");
        assert_eq!((lash.kind, lash.count, lash.owner.as_str()), ("defense", 4, "Striker"));
        assert_eq!(lash.target, 4, "the striker's own Defense 4+, AP 0");
        assert!(wounds_left(&st, 0) < 3, "the lash lands on the striker");
        assert_eq!(credit, 0, "no tally credit — :6174 never touches _solo_retaliate_credit");
        assert_eq!(shot.log.last().map(String::as_str),
            Some("Deathstrike/Self-Destruct: Target's dying models lash out — Striker takes 4 hits"),
            "the rules-must-log line");
    }

    /// (b) Deathstrike(2) but NO model dies: the 4 landed wounds soak into
    /// pools [5,1,1] and every model survives — nothing lashes back, no log
    /// line. RED when the `killed > 0` guard goes: the block would fire for
    /// `death_hits_per_kill * 0` and push a "…— 0 hits" line.
    #[test]
    fn deathstrike_lashes_nothing_when_no_model_is_lost() {
        let (mut st, mut statics) = duel(0);
        statics[1].ctx.death_hits_per_kill = 2;
        st.wounds[1] = vec![5, 1, 1]; // 4 wounds soak into the first model
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (_, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        assert_eq!(st.alive[1], 3, "fixture: 3 wounds soak, no model dies");
        assert_eq!(credit, 0, "nothing to credit");
        assert!(shot.log.iter().all(|l| !l.contains("dying models")), "nothing logged");
        assert!(shot.rolls.iter().all(|r| !(r.kind == "defense" && r.owner == "Striker")),
            "the striker never rolls a save when no model is lost");
    }

    /// (c) The dying lash is NOT a Retaliate: even with the lash landing on
    /// the striker, the returned tally credit stays exactly what the Retaliate
    /// block left it (0 here) — main.gd:6174 runs `_solo_deathstrike_hits`
    /// without touching `_solo_retaliate_credit`. RED the moment the credit
    /// line is copied over from the Retaliate block.
    #[test]
    fn deathstrike_lash_never_touches_the_retaliate_credit() {
        let (mut st, mut statics) = duel(0);
        statics[1].ctx.death_hits_per_kill = 2;
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (_, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        assert!(shot.rolls.iter().any(|r| r.kind == "defense" && r.owner == "Striker"),
            "fixture: the lash DID fire (pools [1,1,1] lose all three models)");
        assert!(wounds_left(&st, 0) < 3, "the lash landed on the striker");
        assert_eq!(credit, 0, "the tally is the Retaliate credit — untouched by Deathstrike");
    }
