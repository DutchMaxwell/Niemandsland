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

    /// The DOOR writes what the volley's tray says (`Tray::say`), not `ShootResult.log`: the same volley on a supplied tray (what a
    /// door step runs on) says the cover line once, right before the save line, and the kept-cover line before it. RED before:
    /// both lines were only pushed to `ShootResult.log`, so the human and AI doors wrote no cover line (Game School ch. 8).
    #[test]
    fn the_door_tray_says_the_cover_lines() {
        let att = Ctx { rules_epoch: EPOCH_73_V36, ..shooter(4) };
        let marked = Ctx { indirect_mark: true, ..covered(4) };
        let profiles = [rifle(6)];
        let run = |tray: &mut Tray| {
            let shooters: Vec<Shooter> = ["Att", "Mate"].iter()
                .map(|o| Shooter { profiles: &profiles, keep: &[0], attacks: &[6], att: &att, owner: o }).collect();
            resolve_volley_with_tray(&shooters, &marked, "Def", 12.0, 12.0, true, true, true, true, tray)
        };
        let seeded = run(&mut Tray::seeded(27));
        let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect());
        assert_eq!(run(&mut tray).rolls, seeded.rolls, "the same dice either way");
        let said: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        let at = |t: &str| said.iter().position(|l| l == t);
        assert!(at(KEPT).is_some() && at(KEPT) < at(COVER), "kept-cover line, then the cover line: {said:?}");
        assert_eq!(said.iter().filter(|l| *l == COVER).count(), 1, "once per volley: {said:?}");
        assert!(said[at(COVER).unwrap() + 1].starts_with("Def saves on"), "the cover line stands right before the save line: {said:?}");
    }

    // ------- PLAN_COVER_36 step 5: cover from sight blockers (`Ctx.screened`) in the save fold ---

    fn screened(defense: i64) -> Ctx {
        Ctx { screened: true, ..defender(defense, 5) }
    }

    fn held_gun(held: bool) -> (Ctx, ShootProfile) {
        let att = Ctx { held, rules_epoch: crate::acts::PENDING_EPOCH_COVER_SCREEN, ..shooter(4) };
        (att, ShootProfile { name: "Gun".into(), indirect: true, indirect_los_needs_hold: true, indirect_cover_needs_hold: true, ..rifle(6) })
    }

    const LIFT: &str = "Indirect: Gun ignores Def's cover from sight blockers";

    /// Behind a blocker alone is +1; with terrain cover too it is still ONE +1 (saves on 3+ from 4, not 2+); Blast drops it.
    /// RED before the fold: `screened` was never read, so the screened-only volley said no cover line.
    #[test]
    fn a_screened_save_takes_one_cover_plus_one() {
        let att = shooter(4);
        let alone = volley_log(&att, &screened(4), rifle(6), 1);
        assert_eq!(said(&alone, COVER), 1, "behind a blocker: +1 Defense: {alone:?}");
        let both = volley_log(&att, &Ctx { in_cover: true, ..screened(4) }, rifle(6), 1);
        assert_eq!(said(&both, COVER), 1, "terrain and blocker give one +1 (3+, not 2+): {both:?}");
        let blast = volley_log(&att, &screened(4), ShootProfile { blast: 3, ..rifle(6) }, 1);
        assert!(blast.iter().all(|l| !l.contains("in cover")), "Blast drops it: {blast:?}");
    }

    /// A held Indirect gun lifts the sight-blocker cover (and says so once) but keeps terrain cover; an Indirect gun that moved
    /// has no waiver and meets the blocker like any gun. RED before the fold: no lift line.
    #[test]
    fn a_held_indirect_lifts_only_the_sight_blocker_cover() {
        let (held, gun) = held_gun(true);
        let lifted = volley_log(&held, &screened(4), gun.clone(), 2);
        assert_eq!(said(&lifted, LIFT), 1, "the lift says itself once per weapon: {lifted:?}");
        assert!(lifted.iter().all(|l| !l.contains("in cover")), "no +1 left: {lifted:?}");
        let kept = volley_log(&held, &Ctx { in_cover: true, ..screened(4) }, gun.clone(), 1);
        assert_eq!(said(&kept, COVER), 1, "terrain cover stays: {kept:?}");
        let (moved, gun) = held_gun(false);
        let met = volley_log(&moved, &screened(4), gun, 1);
        assert_eq!((said(&met, COVER), said(&met, LIFT)), (1, 0), "a moved Indirect needs sight and meets the blocker: {met:?}");
    }

    /// Lead call 21.11.: an Indirect gun that moved without the Hold its entry needs is not firing indirectly, so the
    /// Indirect mark on the target does not hand it the lift either (the table's reading). RED before: the mark clause lifted.
    #[test]
    fn a_moved_indirect_at_a_marked_target_keeps_the_sight_blocker_cover() {
        let (moved, gun) = held_gun(false);
        let log = volley_log(&moved, &Ctx { indirect_mark: true, ..screened(4) }, gun, 1);
        assert_eq!((said(&log, COVER), said(&log, LIFT)), (1, 0), "no waiver, no lift: {log:?}");
    }

    /// PLAN_COVER_36 step 9c: the doors write the tray's lines (#3286), so the lift line is said on the tray too.
    /// RED before: it stood in `ShootResult.log` only.
    #[test]
    fn the_door_tray_says_the_sight_blocker_lift() {
        let (held, gun) = held_gun(true);
        let profiles = [gun];
        let def = screened(4);
        let shooters = [Shooter { profiles: &profiles, keep: &[0], attacks: &[6], att: &held, owner: "Att" }];
        let seeded = resolve_volley_with_tray(&shooters, &def, "Def", 12.0, 12.0, true, true, true, true, &mut Tray::seeded(27));
        let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect()); // a door's tray
        resolve_volley_with_tray(&shooters, &def, "Def", 12.0, 12.0, true, true, true, true, &mut tray);
        let said: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        assert_eq!(said.iter().filter(|l| *l == LIFT).count(), 1, "the tray says the lift once: {said:?}");
    }

    // ------- lines audit (21.11.): the cover-family lines the doors never saw (they were `out.log` only) ---

    /// The tray lines of one volley on a SUPPLIED tray (what a door step runs on) with the dice a seeded run drew.
    fn tray_lines(att: &Ctx, def: &Ctx, weapon: ShootProfile, n: usize) -> Vec<String> {
        let profiles = [weapon];
        let run = |tray: &mut Tray| {
            let shooters: Vec<Shooter> = ["Att", "Mate"].iter().take(n)
                .map(|o| Shooter { profiles: &profiles, keep: &[0], attacks: &[6], att, owner: o }).collect();
            resolve_volley_with_tray(&shooters, def, "Def", 12.0, 12.0, true, true, true, true, tray)
        };
        let seeded = run(&mut Tray::seeded(27));
        let mut tray = Tray::supplied(seeded.rolls.iter().map(|r| r.faces.clone()).collect());
        run(&mut tray);
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    const SKIP: &str = "Anti-Cover: Att ignores Def's cover (save skipped)";

    /// The table's AI-08a line: a weapon whose cover skip is a named map-read rule (`cover_rule`) says so for every shot that skips a
    /// cover the target really had (so twice for two shooters), in the table's words. The cases that say nothing: no cover, Blast, a
    /// Defense at the floor, no rule name. RED on main: the line was only in `ShootResult.log`.
    #[test]
    fn an_anti_cover_skip_says_the_tables_line_on_the_door_tray() {
        let att = shooter(4);
        let gun = || ShootProfile { ignores_cover: true, cover_rule: "Anti-Cover".into(), ..rifle(6) };
        let two = tray_lines(&att, &covered(4), gun(), 2);
        assert_eq!(said(&two, SKIP), 1, "Mate's shot is its own: {two:?}");
        assert_eq!(said(&two, "Anti-Cover: Mate ignores Def's cover (save skipped)"), 1, "{two:?}");
        assert!(two.iter().all(|l| !l.contains("in cover")), "the save is not covered: {two:?}");
        for (why, lines) in [
            ("no cover", tray_lines(&att, &defender(4, 5), gun(), 1)),
            ("a Defense at the floor", tray_lines(&att, &covered(2), gun(), 1)),
            ("Blast", tray_lines(&att, &covered(4), ShootProfile { blast: 3, ..gun() }, 1)),
            ("no rule name", tray_lines(&att, &covered(4), ShootProfile { cover_rule: String::new(), ..gun() }, 1)),
        ] {
            assert!(lines.iter().all(|l| !l.contains("save skipped")), "{why}: {lines:?}");
        }
    }
