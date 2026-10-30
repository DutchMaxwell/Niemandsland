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
