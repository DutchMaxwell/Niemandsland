use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

    // ------- I4 / Rules 3.6: the table's cover lines in the core (soak game 16, round 4) ---

    /// The log of one volley of `n` shooters (one weapon each) at a defender called "Def".
    fn volley_log(att: &Ctx, def: &Ctx, weapon: ShootProfile, n: usize) -> Vec<String> {
        let profiles = [weapon];
        let owners = ["Att", "Mate"];
        let shooters: Vec<Shooter> = (0..n)
            .map(|i| Shooter { profiles: &profiles, keep: &[0], attacks: &[6], att, owner: owners[i] })
            .collect();
        resolve_volley_with_tray(&shooters, def, "Def", 12.0, 12.0, true, true, true, true, &mut Tray::seeded(27)).log
    }

    fn covered(defense: i64) -> Ctx {
        Ctx { in_cover: true, ..defender(defense, 5) }
    }

    fn said(log: &[String], text: &str) -> usize {
        log.iter().filter(|l| l.as_str() == text).count()
    }

    const COVER: &str = "Def is in cover: +1 Defense (saves on 3+)";
    const KEPT: &str = "Indirect: Att — Def's cover counts (only sight-blocker cover is ignored)";

    /// A save that really used the cover says so once per volley, with the Defense it rolled on; the cases where the cover did not
    /// lower the save say nothing (no cover, Blast drops it, a Defense already at the floor). RED before the fix: the core never said it.
    #[test]
    fn a_covered_save_says_the_cover_line_once_per_volley() {
        let att = shooter(4);
        let two = volley_log(&att, &covered(4), rifle(6), 2);
        assert_eq!(said(&two, COVER), 1, "once for two shooters: {two:?}");
        let (open, blast, floor) = (
            volley_log(&att, &defender(4, 5), rifle(6), 1),
            volley_log(&att, &covered(4), ShootProfile { blast: 3, ..rifle(6) }, 1),
            volley_log(&att, &covered(2), rifle(6), 1),
        );
        assert!(open.iter().all(|l| !l.contains("in cover")), "no cover, no line: {open:?}");
        assert!(blast.iter().all(|l| !l.contains("in cover")), "Blast drops the cover: {blast:?}");
        assert!(floor.iter().all(|l| !l.contains("in cover")), "a Defense at the floor is not lowered by cover: {floor:?}");
    }

    /// A mark on the target makes the shot Indirect on the table, so a covered save of it says "cover counts" (before the plain
    /// cover line, as the table orders them). A shot without the mark, or below 73, does not. RED before the fix: no "cover counts".
    #[test]
    fn a_marked_targets_kept_cover_names_itself_before_the_cover_line() {
        let att = Ctx { rules_epoch: EPOCH_73_V36, ..shooter(4) };
        let marked = Ctx { indirect_mark: true, ..covered(4) };
        let log = volley_log(&att, &marked, rifle(6), 2);
        let at = |t: &str| log.iter().position(|l| l == t);
        assert!(at(KEPT).is_some() && at(KEPT) < at(COVER), "kept-cover line first, then the cover line: {log:?}");
        assert_eq!(said(&log, KEPT), 1, "once per volley: {log:?}");
        let plain = volley_log(&att, &covered(4), rifle(6), 1);
        assert!(plain.iter().all(|l| !l.contains("cover counts")), "no mark, no Indirect: {plain:?}");
        let old = volley_log(&Ctx { rules_epoch: EPOCH_72_PLAYTEST_RULES, ..att }, &marked, rifle(6), 1);
        assert!(old.iter().all(|l| !l.contains("cover counts")), "the pre-73 reading stays silent: {old:?}");
    }
