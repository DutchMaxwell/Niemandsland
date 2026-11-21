use super::*;
use super::melee_landing_gaps::{exact_seams, two_unit_melee};
use crate::unit::CondAp;

    // ---- Melee door lines (lane melee95): the Guarded family's charge line and the generic conditional-AP line, in the table's words ----

    fn lines_of(tune: impl FnOnce(&mut [UnitStatic]), charging: bool) -> Vec<String> {
        let (mut statics, mut st) = two_unit_melee(3, 5, 3);
        tune(&mut statics);
        let mut faces: Vec<Vec<u8>> = vec![vec![4, 4, 4, 1, 1, 1], vec![1, 1, 1]];
        faces.extend((0..24).map(|_| vec![1u8; 24]));
        let mut tray = Tray::supplied(faces);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, charging, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    /// A defender with a Guarded-family rule says the +1 Defense a charge from over 6" gives it, once, before the strikes (the table's
    /// `_solo_melee_strike_phase`); a strike-back (the defender charged nobody) pays and says nothing. RED: the strike says no such line.
    #[test]
    fn a_guarded_defender_names_the_charge_bonus() {
        let sturdy = |s: &mut [UnitStatic]| {
            s[1].ctx.guarded = true;
            s[1].ctx.guarded_name = "Sturdy";
            s[1].ctx.guarded_charge_over_in = 6.0;
        };
        let lines = lines_of(sturdy, true);
        assert_eq!(lines[0], "Def (Sturdy): charged from over 6\" — +1 Defense (saves on 3+)", "{lines:?}");
        assert!(lines_of(sturdy, false).iter().all(|l| !l.contains("charged from over")), "no charge, no line");
        assert!(lines_of(|_| {}, true).iter().all(|l| !l.contains("charged from over")), "no Guarded rule, no line");
    }

    /// A conditional-AP rule the generic pass stamps (Disintegrate against Tough(3)+) says its AP in melee, as it does in a volley; against a
    /// Tough(1) defender the condition fails and nothing is said. RED: the melee strike says nothing.
    #[test]
    fn a_disintegrate_strike_names_its_ap() {
        let disintegrate = |s: &mut [UnitStatic]| {
            s[0].melee[0].cond_ap = vec![CondAp { ap_bonus: 2, condition: "vs_tough_ge".into(), threshold: 3, say_name: "Disintegrate".into(), ..Default::default() }];
        };
        let lines = lines_of(disintegrate, true);
        assert!(lines.iter().any(|l| l == "Disintegrate: AP(+2) against Def"), "{lines:?}");
        let (mut statics, mut st) = two_unit_melee(3, 5, 1);
        disintegrate(&mut statics);
        let mut tray = Tray::supplied((0..24).map(|_| vec![1u8; 24]).collect());
        strike_phase(&statics, &mut st, 0, 1, true, 7.0, exact_seams(), &mut tray, &mut ShootResult::default(), StrikeSet::All, Cover::Recorded(None));
        assert!(tray.all_lines().iter().all(|l| !l.text.contains("Disintegrate")), "Tough(1): the condition fails, no line");
    }
