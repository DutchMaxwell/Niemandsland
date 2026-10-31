//! Rules 3.6 lane shoot tests for the sim module; owned by lane shoot.
use super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::Registries;
use crate::state::{Objective, Weapon};

    // ---- SHO-04 (+ AI-02), rules 3.6: Artillery may move like any unit.
    //      Below EPOCH_73_V36 an Artillery unit only Holds — its menu, the
    //      grid pool and the enemy reply model all keep it in place; from
    //      EPOCH_73_V36 on only Immobile does. The carrier's static is built
    //      off the SHIPPED gf map, whose Artillery entry keeps hold_only. -------

    /// The checkout this crate lives in — mirrors the dice tests' helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The gun line: an Artillery gun "a" (one model, one 24" gun, player 0)
    /// and a target "b" (player 1) `gap_in` inches up +x, an objective marker
    /// halfway between them. The gun's static is built at `epoch`.
    fn gun_line(epoch: u32, gap_in: f64) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "ah".into(), "b".into(), "bh".into()],
            index: ["a", "ah", "b", "bh"].iter().enumerate().map(|(i, k)| (k.to_string(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        let base = st.profiles.list[0].clone();
        let mut gun = base.clone();
        gun.name = "Gun".into();
        gun.game_system = "gf".into();
        gun.wounds_max = vec![1];
        gun.special_rules = vec!["Artillery".into()];
        gun.weapons = vec![Weapon {
            name: "Cannon".into(),
            range: 24.0,
            attacks: 4,
            count: 1,
            ap: 0,
            rules: vec![],
        }];
        st.profiles = Rc::new(Profiles {
            list: vec![gun.clone(), base.clone(), base.clone(), base],
            index: HashMap::new(),
        });
        st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![], vec![[gap_in * IN2M, 0.0, 0.0]], vec![]];
        st.wounds = vec![vec![1], vec![], vec![1], vec![]];
        st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], vec![]]);
        st.alive = vec![1, 0, 1, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.objectives = vec![Objective { pos: [gap_in / 2.0 * IN2M, 0.0, 0.0], owner: 1 }];
        let mut reg = Registries::new(&repo_root());
        let foe = UnitStatic {
            name: "b".into(),
            model_count: 1,
            wounds_max: vec![1],
            ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
            ..Default::default()
        };
        (
            st,
            vec![
                UnitStatic::build_for(&mut reg, &gun, epoch),
                UnitStatic { name: "ah".into(), ..Default::default() },
                foe,
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    fn kinds(menu: &[crate::menu::Candidate]) -> Vec<i64> {
        menu.iter().map(|c| c.kind).collect()
    }

    /// The menu, EPOCH_72 leg: the gun only Holds — the objective changes nothing.
    #[test]
    fn artillery_menu_only_holds_at_epoch_72() {
        let (st, statics) = gun_line(EPOCH_72_PLAYTEST_RULES, 16.0);
        assert_eq!(statics[0].hold_only, Some(true), "setup: the shipped map's Artillery entry is read");
        let menu = crate::menu::candidates(&st, &small_board(), &statics, 0);
        assert!(menu.iter().all(|c| c.kind == HOLD), "rules 3.5: Artillery may only Hold: {:?}", kinds(&menu));
    }

    /// The menu, EPOCH_73 leg: the same gun on the same board is offered the rush.
    #[test]
    fn artillery_menu_offers_a_move_at_epoch_73() {
        let (st, statics) = gun_line(EPOCH_73_V36, 16.0);
        assert_eq!(statics[0].hold_only, Some(true), "setup: the shipped map's Artillery entry is read");
        let menu = crate::menu::candidates(&st, &small_board(), &statics, 0);
        assert!(menu.iter().any(|c| c.kind == RUSH), "rules 3.6: Artillery may move: {:?}", kinds(&menu));
    }

    /// The reply model with the hold gate on: the ENEMY gun 28" away with a
    /// 24" cannon. Held in place it cannot reach — zero incoming fire.
    #[test]
    fn enemy_artillery_reply_is_zero_out_of_range_at_epoch_72() {
        let (st, statics) = gun_line(EPOCH_72_PLAYTEST_RULES, 28.0);
        let o = ReplyOpts { v2: true, hold_gate: true, ..ReplyOpts::default() };
        let incoming = reply_threat_opts(&statics, &st, 1, o);
        assert_eq!(incoming[2], 0.0, "rules 3.5: the gun holds, 28\" is out of its 24\" reach");
    }

    /// The same enemy gun under rules 3.6: it may advance 6" and fire.
    #[test]
    fn enemy_artillery_reply_fires_after_an_advance_at_epoch_73() {
        let (st, statics) = gun_line(EPOCH_73_V36, 28.0);
        let o = ReplyOpts { v2: true, hold_gate: true, ..ReplyOpts::default() };
        let incoming = reply_threat_opts(&statics, &st, 1, o);
        assert!(incoming[2] > 0.0, "rules 3.6: the gun advances and fires, got {}", incoming[2]);
    }

    /// The grid pool (AI-02): `plan.rs` drops a hold-only unit from the cells it
    /// widens through `menu::holds_only`, the read the menu and the reply model
    /// share — the gun is held out at epoch 72 and pooled at epoch 73.
    #[test]
    fn the_grid_pool_read_keeps_the_gun_out_at_epoch_72_and_in_at_epoch_73() {
        let (st72, statics72) = gun_line(EPOCH_72_PLAYTEST_RULES, 16.0);
        assert!(crate::menu::holds_only(&st72, &statics72, 0), "rules 3.5: the gun stays out of the pool");
        let (st73, statics73) = gun_line(EPOCH_73_V36, 16.0);
        assert!(!crate::menu::holds_only(&st73, &statics73, 0), "rules 3.6: the gun joins the pool");
    }

    /// Immobile keeps to Hold at both epochs; a hand-built static (epoch 0)
    /// keeps the oldest leg.
    #[test]
    fn immobile_holds_at_both_epochs_and_epoch_0_keeps_the_old_gate() {
        let names = |n: &str| vec![n.to_string()];
        for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
            assert!(crate::menu::forces_hold_at(&names("Immobile"), epoch), "Immobile at {epoch}");
        }
        assert!(crate::menu::forces_hold_at(&names("Artillery"), 0));
        assert!(!crate::menu::forces_hold_at(&names("Ethereal"), EPOCH_72_PLAYTEST_RULES));
    }


// SHO-22 — Piercing Tag and Precision Tag carry TOKENS: the bearer stacks X tokens on one enemy unit or puts
// one token on each of up to X enemy units, and each friendly attack spends ONE token for +1 (rules 3.6).
// Rules 3.5 (the EPOCH_72 leg) piled every marker on one unit and let the first attack spend them all.

/// `tag_line`'s tagger with a second living enemy (unit 3, 9" out) in reach; `lone` empties that second unit.
fn two_enemy_tag_line(rule: &str, markers: i64, lone: bool) -> (State, Vec<UnitStatic>) {
    let (mut st, statics) = tag_line(rule, markers, 24.0);
    if lone {
        st.alive[3] = 0;
    }
    (st, statics)
}

fn seams_at(epoch: u32) -> Seams {
    Seams { rules_epoch: epoch, ..Seams::default() }
}

#[test]
fn piercing_tag_spreads_one_token_on_each_of_two_units_at_epoch_73() {
    let (st, statics) = two_enemy_tag_line("Piercing Tag", 2, false);
    let (next, shot) = tag_volley(&statics, &st, seams_at(EPOCH_73_V36));
    assert_eq!(next.piercing_tag_markers[2..], [0, 1], "one token each; the attack spent one, the other unit keeps its token");
    assert_eq!(shot.rolls[1].target, 5, "ONE token spent: AP(+1) on the save (Defense 4)");
    assert!(
        shot.log.iter().any(|l| l.starts_with("Piercing Tag: tagger places 1 token each, spread over 2 units")),
        "the placement names the spread choice — got {:#?}",
        shot.log
    );
    assert!(
        shot.log.iter().any(|l| l.starts_with("Piercing Tag: one token spent — +1 AP")),
        "the spend names the tag and one token, +1 — got {:#?}",
        shot.log
    );
}

#[test]
fn piercing_tag_stacks_when_only_one_unit_is_in_reach_at_epoch_73() {
    let (st, statics) = two_enemy_tag_line("Piercing Tag", 2, true);
    let (next, shot) = tag_volley(&statics, &st, seams_at(EPOCH_73_V36));
    assert_eq!(next.piercing_tag_markers[2], 1, "two tokens stacked, the attack spent one");
    assert_eq!(shot.rolls[1].target, 5, "ONE token spent: AP(+1), not AP(+2)");
    assert!(
        shot.log.iter().any(|l| l.starts_with("Piercing Tag: tagger places 2 tokens, stacked on b")),
        "the placement names the stack choice — got {:#?}",
        shot.log
    );
}

#[test]
fn piercing_tag_still_piles_everything_on_one_unit_and_spends_it_all_at_epoch_72() {
    let (st, statics) = two_enemy_tag_line("Piercing Tag", 2, false);
    let (next, shot) = tag_volley(&statics, &st, seams_at(EPOCH_72_PLAYTEST_RULES));
    assert_eq!(next.piercing_tag_markers[2..], [0, 0], "3.5: both markers on the toughest unit, spent whole");
    assert_eq!(shot.rolls[1].target, 6, "3.5: AP(+2) from the two markers");
}

/// `buff_line` with Precision Tag (X = 2, 24") and a second living enemy (unit 3) beside the victim.
fn precision_tag_two_enemy_line() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    statics[0].shoot = vec![gun("Rifle", 1, 24)];
    statics[0].utility_buffs = vec![UtilityBuff {
        bonus: "per_removed_marker".into(),
        markers: 2,
        uses_per_game: 1,
        range_in: 24.0,
        target: "enemy".into(),
        ..ub("Precision Tag")
    }];
    st.alive[3] = 1;
    st.positions[3] = vec![[9.0 * IN2M, 0.0, 0.0]];
    Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
    st.wounds[3] = vec![1];
    (st, statics)
}

fn precision_volley(st: &State, statics: &[UnitStatic], epoch: u32) -> (State, ShootResult) {
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(13);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(statics, st, &buff_action(Some("b")), &terrain, seams_at(epoch), &mut rng, &mut tray)
        .unwrap()
}

#[test]
fn precision_tag_spreads_and_each_attack_spends_one_token_at_epoch_73() {
    let (st, statics) = precision_tag_two_enemy_line();
    let (next, volley) = precision_volley(&st, &statics, EPOCH_73_V36);
    assert_eq!(next.tag_markers[2..], [0, 1], "one token each; the attack spent one, the other unit keeps its token");
    assert_eq!(volley.rolls[0].target, 3, "Quality 4 + ONE spent token");
    assert!(
        volley.log.iter().any(|l| l.starts_with("Precision Tag: a places 1 token each, spread over 2 units")),
        "the placement names the spread choice — got {:#?}",
        volley.log
    );
    assert!(
        volley.log.iter().any(|l| l.starts_with("Precision Tag: one token spent — +1 to hit")),
        "the spend names the tag and one token, +1 — got {:#?}",
        volley.log
    );
}

#[test]
fn precision_tag_still_spends_every_marker_at_epoch_72() {
    let (st, statics) = precision_tag_two_enemy_line();
    let (next, volley) = precision_volley(&st, &statics, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(next.tag_markers[2..], [0, 0], "3.5: both markers on the toughest unit, removed whole");
    assert_eq!(volley.rolls[0].target, 2, "3.5: Quality 4 + two removed markers");
}
