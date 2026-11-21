use super::*;
use crate::acts::PENDING_EPOCH_SPELL_NO_STACK as GATE;
use crate::activation::CastInput;
use crate::rules::Spell;

    /// `PENDING_EPOCH_SPELL_NO_STACK` (lead ruling 20.11., GF 3.6 "Rules priority & stacking effects"): the same spell does not stack. Three casts of an
    /// Indirect mark on one target leave ONE record from the pending epoch (the later casts refresh it), three below it (the old stacking replays). RED before
    /// the fix: the first assert (three records). Controls: a different target gets its own record, a different spell stacks beside it, an effect-less
    /// spell still names its landing.
    #[test]
    fn a_second_identical_spell_record_refreshes_the_first_from_the_pending_epoch() {
        let mark = |name: &str| Spell { name: name.into(), effect_kind: "debuff".into(), threshold: 1, target_count: 1, beneficiary: "attackers".into(),
            grants_rule: "Indirect".into(), ..Default::default() };
        let cast = |spell: &Spell| CastInput { spell: spell.name.clone(), once: true, base: 2, threshold: 1, ..Default::default() };
        let run = |epoch: u32| -> State {
            let (mut st, _) = buff_line();
            let (tri, other) = (mark("Triangulation Bots"), mark("Other Mark"));
            for _ in 0..3 {
                tray_spell_effect(&mut st, &[2], &cast(&tri), &tri, epoch);
            }
            tray_spell_effect(&mut st, &[3], &cast(&tri), &tri, epoch);
            tray_spell_effect(&mut st, &[2], &cast(&other), &other, epoch);
            st
        };
        let at = run(GATE);
        assert_eq!(at.buffs[2].len(), 2, "three casts of one spell = one record, the other spell stacks beside it: {:?}", at.buffs[2]);
        assert_eq!(at.buffs[3].len(), 1, "a different target gets its own record");
        assert_eq!(at.cast_buffs.iter().filter(|(t, _, _)| *t == 2).count(), 2, "the delta names the two records that were placed, not the refreshed casts");
        let below = run(GATE - 1);
        assert_eq!(below.buffs[2].len(), 4, "below the pending epoch the old stacking replays byte-exact");
    }
