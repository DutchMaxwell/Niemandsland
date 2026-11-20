use super::*;

    // EPOCH_93_DANGER_RULES_RIDER (93): the seam-off volley's LEGACY spell rider (`resolve`'s shoot branch) adds the best
    // affordable in-range damage spell to the volley's expectation and pays its tokens, a cast nobody makes (the table has
    // no such rider). This is the expectation path (no tray); the tray path's pin lives in `activation.rs`
    // (`cast_o7_the_volleys_spell_rider_spends_no_token_on_the_tray_path`).
    use crate::acts::EPOCH_93_DANGER_RULES_RIDER;
    use crate::rules::{Spell, SpellModifier};

    /// Unit "a" (2 models, one 24" Rifle) is a caster holding `tokens` with one 3-hit bolt (cost 1, range 18"); the
    /// target "b" stands 12" away, inside both.
    fn caster_line(tokens: i64) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        statics[0].is_caster = true;
        statics[0].spells = vec![Spell {
            name: "bolt".into(),
            status: "modeled".into(),
            threshold: 1,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "damage".into(),
            effect_hits: 3,
            modifier: SpellModifier::default(),
            ..Default::default()
        }];
        st.casts[0] = tokens;
        (st, statics)
    }

    /// (tokens left, the target's wounds left, as wounds + the fractional carry) after one plain Hold volley.
    fn volley(rules_epoch: u32, seam_cast: bool) -> (i64, f64) {
        let (st, statics) = caster_line(4);
        let seams = Seams { rules_epoch, cast: seam_cast, ..Default::default() };
        let next = resolve(&statics, &st, &buff_action(Some("b")), None, seams, None).expect("a plain volley");
        (next.casts[0], next.wounds[2].iter().sum::<i64>() as f64 - next.wound_frac[2])
    }

    /// RED on a build without the gate: the 93 row keeps paying the rider's token and its spell damage.
    #[test]
    fn from_93_a_seam_off_volley_prices_and_pays_no_spell_rider() {
        let (tokens, left) = volley(EPOCH_93_DANGER_RULES_RIDER, false);
        assert_eq!(tokens, 4, "the volley spends no spell token (the table's 4)");
        let (old_tokens, old_left) = volley(EPOCH_93_DANGER_RULES_RIDER - 1, false);
        assert!(left > old_left, "the bolt's expected wounds leave with the rider: {left} vs {old_left}");
        assert_eq!(old_tokens, 3, "92 keeps paying the rider");
    }

    /// The legacy reading stays byte-identical below 93 (the rider pays 1 and its EV joins the volley).
    #[test]
    fn at_92_the_legacy_rider_still_pays_one_token_and_wounds_more() {
        let (tokens, left) = volley(EPOCH_93_DANGER_RULES_RIDER - 1, false);
        let (_, plain_left) = {
            let (mut st, mut statics) = caster_line(4);
            statics[0].is_caster = false; // no caster -> `caster_of` None -> the rider cannot fire
            st.casts[0] = 0;
            let seams = Seams { rules_epoch: EPOCH_93_DANGER_RULES_RIDER - 1, ..Default::default() };
            let next = resolve(&statics, &st, &buff_action(Some("b")), None, seams, None).unwrap();
            (next.casts[0], next.wounds[2].iter().sum::<i64>() as f64 - next.wound_frac[2])
        };
        assert_eq!(tokens, 3);
        assert!(left < plain_left, "the rider's spell EV joins the volley at 92: {left} vs {plain_left}");
    }

    /// `seam_cast` ON never had the rider: the gate does not move a single bit of that path.
    #[test]
    fn the_seam_on_path_is_untouched_by_the_gate() {
        assert_eq!(volley(EPOCH_93_DANGER_RULES_RIDER - 1, true), volley(EPOCH_93_DANGER_RULES_RIDER, true));
    }
