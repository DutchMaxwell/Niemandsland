use super::*;
use super::melee_landing_gaps::{exact_seams, two_unit_melee};

    // ---- Melee door lines (lane melee95): the Shaken strike-back says it counts as Fatigued, as the table does ----

    fn lines_of(shaken: bool, charging: bool) -> Vec<String> {
        let (statics, mut st) = two_unit_melee(3, 5, 1);
        st.shaken[0] = shaken;
        let mut faces: Vec<Vec<u8>> = vec![vec![4, 4, 4, 1, 1, 1]];
        faces.extend((0..24).map(|_| vec![1u8; 24]));
        let mut tray = Tray::supplied(faces);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, charging, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    /// A Shaken striker (it can only be striking back) says it counts as Fatigued, before its first weapon line, once; a rested one says nothing.
    /// RED: the core applied the fatigue (the 6s) and said nothing (melee soak 21.11., Steam-Suits at Wardens).
    #[test]
    fn a_shaken_strike_back_says_it_counts_as_fatigued() {
        let lines = lines_of(true, false);
        let at = lines.iter().position(|l| l == "Shaken: Att strikes back counting as fatigued (6+)").unwrap_or_else(|| panic!("{lines:?}"));
        assert!(lines[at + 1..].iter().all(|l| !l.starts_with("Shaken:")), "once: {lines:?}");
        assert!(lines.iter().position(|l| l.starts_with("Att strikes with Blade")).is_some_and(|w| w > at), "before the weapon line: {lines:?}");
        assert!(lines_of(false, false).iter().all(|l| !l.starts_with("Shaken:")), "a rested unit says nothing");
    }
