//! The Hero in the 3.6 Firefight and AoF: Skirmish books (p.14): units within 6 in of a friendly Hero may use its Quality
//! for morale tests while the Hero is not Shaken; no Tough minimum, and Heroes never join units. Read through
//! `Book::hero_aura_at` from `PENDING_EPOCH_SKIRMISH_HERO` on; one epoch below, the recorded big-game aura (Tough 9+).
use super::*;
use crate::acts::PENDING_EPOCH_SKIRMISH_HERO as E;

/// Unit 0 = "Recruit" (Q5, one model at y 20 in), unit 1 = "Captain" (Hero, Q3, Tough 3, one model at y 25 in):
/// 5 in centre to centre, 32 mm bases -> 3.74 in edge gap. Both players' 0. Built on `four_unit_line`, units 2-3 parked far away.
fn hero_pair(sys: &str, hero_shaken: bool) -> (Vec<UnitStatic>, State) {
    let mut st = four_unit_line();
    let r = 0.63 * IN2M;
    st.positions = vec![
        vec![[20.0 * IN2M, 0.0, 20.0 * IN2M]],
        vec![[20.0 * IN2M, 0.0, 25.0 * IN2M]],
        vec![[40.0 * IN2M, 0.0, 40.0 * IN2M]],
        vec![[44.0 * IN2M, 0.0, 40.0 * IN2M]],
    ];
    st.radii = Rc::new(vec![vec![r]; 4]);
    st.player = vec![0, 0, 1, 1];
    st.shaken = vec![false, hero_shaken, false, false];
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 2] });
    let mut p = st.profiles.list[0].clone();
    p.game_system = sys.into();
    st.profiles = Rc::new(Profiles { list: vec![p.clone(), p.clone(), p], index: HashMap::new() });
    let unit = |name: &str, q: i64, hero: bool| UnitStatic {
        ctx: Ctx { quality: q, defense: 5, tough: 3, models: 1, ..Default::default() },
        name: name.into(), quality: q, is_hero: hero, model_count: 1, wounds_max: vec![3], ..Default::default()
    };
    (vec![unit("Recruit", 5, false), unit("Captain", 3, true), unit("Foe", 4, false)], st)
}

fn seams_at(rules_epoch: u32) -> Seams {
    Seams { rules_epoch, hero_attach: true, tray_exact: true, ..Default::default() }
}

/// A Tough 3 Hero 3.74 in away lends Quality 3 in gff and aofs from the epoch on; one epoch below it does not (Tough 9
/// minimum), and gf never does.
#[test]
fn any_skirmish_hero_within_6_in_lends_its_quality_from_the_epoch() {
    for sys in ["gff", "aofs"] {
        let (statics, st) = hero_pair(sys, false);
        assert_eq!(hero_aura_quality(&statics, &st, 0, 5, seams_at(E)), Some((1, 3)), "{sys}: the Captain lends Q3");
        assert_eq!(hero_aura_quality(&statics, &st, 0, 5, seams_at(E - 1)), None, "{sys}: one epoch below, Tough 9+");
    }
    let (statics, st) = hero_pair("gf", false);
    for epoch in [E - 1, E] {
        assert_eq!(hero_aura_quality(&statics, &st, 0, 5, seams_at(epoch)), None, "gf keeps Tough 9+ at {epoch}");
    }
}

/// A Shaken Hero lends nothing, on both sides of the epoch.
#[test]
fn a_shaken_skirmish_hero_lends_nothing() {
    for sys in ["gff", "aofs"] {
        let (statics, st) = hero_pair(sys, true);
        for epoch in [E - 1, E] {
            assert_eq!(hero_aura_quality(&statics, &st, 0, 5, seams_at(epoch)), None, "{sys} at {epoch}");
        }
    }
}

/// Heroes never join in skirmish: from the epoch the Blast cap of a unit with a hero attached counts the unit alone.
#[test]
fn the_skirmish_blast_cap_counts_no_joined_hero_from_the_epoch() {
    for (sys, joined_counts_at_e) in [("gff", false), ("aofs", false), ("gf", true)] {
        let (_statics, mut st) = hero_pair(sys, false);
        Rc::make_mut(&mut st.attached)[0] = vec![1];
        Rc::make_mut(&mut st.attached_to)[1] = Some(0);
        let cap = |epoch: u32| blast_cap_models(&st, 0, seams_at(epoch), st.book(0));
        assert_eq!(cap(E - 1), 2, "{sys}: one epoch below, host + joined hero");
        assert_eq!(cap(E), if joined_counts_at_e { 2 } else { 1 }, "{sys} at the epoch");
    }
}
