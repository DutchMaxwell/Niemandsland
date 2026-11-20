use super::*;
use super::melee_landing_gaps::{exact_seams, two_unit_melee};

    // ---- Melee door lines (lane melee95): where a Deadly weapon's landing and the pool's wound line stand, in the table's order ----

    /// A one-model striker with a plain Blade then a Deadly Spear at a defender of five Tough(1) models. The planted faces: the hit roll of both
    /// weapons (`hits`), then each weapon's save roll; everything else is a 1.
    fn deadly_lines(spear_first: bool, planted: Vec<Vec<u8>>) -> Vec<String> {
        let (mut statics, mut st) = two_unit_melee(1, 5, 1);
        let blade = ShootProfile { name: "Blade".into(), attacks: 3, count: 1, range: 0, ..Default::default() };
        let spear = ShootProfile { name: "Spear".into(), attacks: 3, count: 1, range: 0, deadly: 3, ..Default::default() };
        statics[0].melee = if spear_first { vec![spear, blade] } else { vec![blade, spear] };
        let mut faces = planted;
        faces.extend((0..24).map(|_| vec![1u8; 24]));
        let mut tray = Tray::supplied(faces);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, true, 7.0, exact_seams(), &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    /// A Deadly weapon's landing says its casualties right away, and the pool's "takes N wounds" line counts the Deadly wounds too (the table's
    /// `taken_before`, #2826); the casualty line after it names the pool's own. RED: "Def takes 1 wound" and one "loses 4 models" at the end.
    #[test]
    fn a_deadly_weapon_says_its_casualties_before_the_pool_line_that_counts_its_wounds() {
        let lines = deadly_lines(false, vec![vec![4, 4, 4], vec![4, 4, 4], vec![4, 4, 1], vec![1, 1, 1]]);
        let at = lines.iter().position(|l| l.starts_with("Deadly(3)")).unwrap_or_else(|| panic!("{lines:?}"));
        assert_eq!(lines[at..], [
            "Deadly(3): 3 unsaved ×3, no carry-over → 3 wounds dealt (Spear)",
            "Def loses 3 models (2/5)",
            "Def takes 4 wounds (1/5)",
            "Def loses a model (1/5)",
        ], "{lines:?}");
    }

    /// The Deadly landing goes back to where its weapon's saves ended: the next weapon's save lines come after it (the table lands Deadly before the
    /// next group rolls). RED: both save lines first, the Deadly lines after.
    #[test]
    fn a_deadly_weapon_lands_before_the_next_weapons_saves() {
        let lines = deadly_lines(true, vec![vec![4, 4, 4], vec![4, 4, 4], vec![1, 1, 1], vec![4, 4, 4]]);
        let at = lines.iter().position(|l| l.starts_with("Deadly(3)")).unwrap_or_else(|| panic!("{lines:?}"));
        assert_eq!(lines[at - 1], "Def saves on 4+", "{lines:?}");
        assert_eq!(lines[at + 1], "Def loses 3 models (2/5)", "{lines:?}");
        assert_eq!(lines[at + 2], "Def saves on 4+", "the second weapon's saves follow the landing: {lines:?}");
        assert_eq!(lines.iter().filter(|l| l.starts_with("Def saves")).count(), 2, "{lines:?}");
    }

    /// Wounds that reach the pool after the Deadly landing wiped the defender still make the table say "takes N wounds" (with the inline ones), after
    /// "destroyed"; with none reaching the pool there is no wound line at all, only the Deadly line and the casualties. RED: no line in either case
    /// for the first, a different count for none.
    #[test]
    fn the_wound_line_follows_the_pool_even_on_a_destroyed_defender() {
        let wiped = deadly_lines(false, vec![vec![4, 4, 4], vec![4, 4, 4], vec![1, 1, 1], vec![1, 1, 1]]);
        assert_eq!(wiped[wiped.len() - 3..], ["Def loses 3 models (2/5)", "Def takes 5 wounds (0/5)", "Def destroyed"], "{wiped:?}");
        let quiet = deadly_lines(false, vec![vec![4, 4, 4], vec![4, 4, 4], vec![4, 4, 4], vec![1, 1, 1]]);
        assert!(quiet.iter().all(|l| !l.contains("takes")), "no pool wound, no wound line: {quiet:?}");
        assert_eq!(quiet.last().map(String::as_str), Some("Def loses 3 models (2/5)"), "{quiet:?}");
    }
