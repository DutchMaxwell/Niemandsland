//! Rules 3.6 row G4R5 R15 F-PRIMAL-GRANT-ONCE (replay row aof_1000_net_032 act 31, a charge): ONE "Enhanced Primal" grant
//! is carried in two channels - the overlay rule on the unit's own rules and the ledger buff the spell records - and the
//! core rolled an extra-attack group for EACH channel. The table rolls one: a live grant only LOWERS the threshold of a
//! member that prints the extra-die form (Primal), and only a member without the printed form rolls the grant's own
//! group. From `EPOCH_73_V36`; below 73 the two groups replay. Both halves (the volley and the charge) are tested on the
//! live path with units built the way the game builds them.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::read_act_header;
use crate::rules::Registries;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// A Primal beast (prints the extra-die form), a Boosted beast (Primal plus the overlay rule "Enhanced Primal", the shape
/// the table records), and a Plain beast (no Primal at all). Each fires a 12-die Rifle and strikes with 12-attack Claws.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "primal":{"unit_id":"primal","name":"Primal Beast","quality":4,"defense":4,"tough":1,"wounds_max":[1],
    "model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhosts",
    "special_rules":["Primal"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":12,"count":1,"ap":0,"rules":[]},
      {"name":"Claws","range":0,"attacks":12,"count":1,"ap":0,"rules":[]}]},
  "boosted":{"unit_id":"boosted","name":"Boosted Beast","quality":4,"defense":4,"tough":1,"wounds_max":[1],
    "model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhosts",
    "special_rules":["Primal","Enhanced Primal"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":12,"count":1,"ap":0,"rules":[]},
      {"name":"Claws","range":0,"attacks":12,"count":1,"ap":0,"rules":[]}]},
  "plain":{"unit_id":"plain","name":"Plain Beast","quality":4,"defense":4,"tough":1,"wounds_max":[1],
    "model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhosts",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":12,"count":1,"ap":0,"rules":[]},
      {"name":"Claws","range":0,"attacks":12,"count":1,"ap":0,"rules":[]}]}}}"#;

/// The ledger record the spell Primordial Roar leaves on its target: a grant of "Enhanced Primal" for the whole chain.
fn roar() -> crate::mods::LiveMod {
    crate::mods::LiveMod {
        hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0,
        grants_rule: Rc::from("Enhanced Primal"), scope: Rc::from(""), attackers: false, once: false,
        name: Rc::from("Primordial Roar"),
    }
}

/// Unit 0 = the beast `key` (one model, at the origin, built at `epoch` like a record of that epoch) with the grant when `granted`; unit 2 = a hardened one-model target.
fn line(key: &str, granted: bool, epoch: u32) -> (State, Vec<UnitStatic>) {
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = Registries::new(&repo_root());
    let beast = UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), epoch);
    assert!(beast.shoot[0].surge_attack == (key != "plain"), "{key}: the Primal form is stamped exactly where it is printed");
    let (mut st, mut statics) = buff_line();
    statics[0] = beast;
    statics[2].model_count = 1;
    statics[2].wounds_max = vec![400];
    statics[2].ctx.tough = 400;
    (st.alive[0], st.alive[2]) = (1, 1);
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.positions[2] = vec![[2.0 * IN2M, 0.0, 0.0]]; // base contact: in reach of the charge's strike (3") and of the Rifle
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M], vec![IN2M], vec![]]);
    st.wounds[0] = vec![1];
    st.wounds[2] = vec![400];
    if granted {
        st.buffs[0] = vec![roar()];
    }
    (st, statics)
}

/// The beast's attack rolls through one HOLD volley at unit 2 (`volley`) or one charge into it, as (count, faces).
fn attack_rolls(volley: bool, key: &str, granted: bool, seed: i64, epoch: u32) -> (Vec<(i64, Vec<u8>)>, Vec<String>) {
    let (mut st, statics) = line(key, granted, epoch);
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let shot = if volley {
        let terrain = crate::terrain::Terrain::default();
        resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &terrain, seams,
            &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(seed)).unwrap().1
    } else {
        let (mut tray, mut shot) = (Tray::seeded(seed), ShootResult::default());
        tray_charge(&statics, &mut st, 0, 2, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
        shot
    };
    let owner = statics[0].name.clone();
    (shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == owner).map(|r| (r.count, r.faces.clone())).collect(), shot.log)
}

/// The first seed whose 12 main dice carry at least one unmodified 6 AND one unmodified 5 (so every group has a size).
fn seed_with_a_six_and_a_five(volley: bool) -> i64 {
    (1..400)
        .find(|&s| {
            let (rolls, _) = attack_rolls(volley, "plain", false, s, EPOCH_73_V36);
            rolls.first().is_some_and(|(_, f)| f.contains(&6) && f.contains(&5))
        })
        .expect("a seed with a six and a five")
}

fn sizes(rolls: &[(i64, Vec<u8>)]) -> (i64, i64) {
    let f = &rolls[0].1;
    (f.iter().filter(|&&x| x == 6).count() as i64, f.iter().filter(|&&x| x == 5).count() as i64)
}

/// The extra-attack groups after the main roll, as their dice counts.
fn groups(rolls: &[(i64, Vec<u8>)]) -> Vec<i64> {
    rolls.iter().skip(1).map(|(c, _)| *c).collect()
}

/// RED on main: a printed Primal carrying the ledger grant rolls TWO groups (its own 6s and the grant's 5s and 6s).
/// From 73 the grant only lowers the printed form's threshold: ONE group of every 6 and 5.
#[test]
fn a_printed_primal_with_the_ledger_grant_rolls_one_group_at_epoch_73() {
    for volley in [true, false] {
        let seed = seed_with_a_six_and_a_five(volley);
        let (rolls, log) = attack_rolls(volley, "primal", true, seed, EPOCH_73_V36);
        let (sixes, fives) = sizes(&rolls);
        assert_eq!(groups(&rolls), vec![sixes + fives], "volley={volley}: one group of the sixes and the fives {rolls:?}");
        assert!(log.iter().any(|l| l.starts_with("Enhanced Primal:") && l.contains("Primal Beast")), "volley={volley}: names the rule {log:?}");
    }
}

/// RED on main, the replay shape (aof_032/31): the printed Primal with the overlay rule widens its own window AND carries
/// the ledger grant - two groups of the same dice. From 73: one.
#[test]
fn the_overlay_and_the_ledger_grant_of_one_spell_roll_one_group_at_epoch_73() {
    for volley in [true, false] {
        let seed = seed_with_a_six_and_a_five(volley);
        let (rolls, _) = attack_rolls(volley, "boosted", true, seed, EPOCH_73_V36);
        let (sixes, fives) = sizes(&rolls);
        assert_eq!(groups(&rolls), vec![sixes + fives], "volley={volley}: one group {rolls:?}");
    }
}

/// CONTROL (passes before and after): a member WITHOUT the printed form rolls the grant's own group, one group of 6s and 5s.
#[test]
fn a_member_without_the_printed_form_rolls_the_grants_own_group() {
    for volley in [true, false] {
        let seed = seed_with_a_six_and_a_five(volley);
        let (rolls, _) = attack_rolls(volley, "plain", true, seed, EPOCH_73_V36);
        let (sixes, fives) = sizes(&rolls);
        assert_eq!(groups(&rolls), vec![sixes + fives], "volley={volley}: the grant's own group {rolls:?}");
    }
}

/// CONTROL (passes before and after): a printed Primal with no grant rolls its own group, the unmodified 6s only.
#[test]
fn a_printed_primal_without_a_grant_rolls_its_sixes_only() {
    for volley in [true, false] {
        let seed = seed_with_a_six_and_a_five(volley);
        let (rolls, log) = attack_rolls(volley, "primal", false, seed, EPOCH_73_V36);
        assert_eq!(groups(&rolls), vec![sizes(&rolls).0], "volley={volley}: sixes only {rolls:?}");
        assert!(log.iter().all(|l| !l.starts_with("Enhanced Primal:")), "no grant, no line {log:?}");
    }
}

/// Below 73 the two groups replay byte for byte: the printed 6s, then the grant's 5s and 6s.
#[test]
fn below_epoch_73_the_two_groups_replay() {
    for volley in [true, false] {
        let seed = seed_with_a_six_and_a_five(volley);
        let (rolls, _) = attack_rolls(volley, "primal", true, seed, EPOCH_72_PLAYTEST_RULES);
        let (sixes, fives) = sizes(&rolls);
        assert_eq!(groups(&rolls), vec![sixes, sixes + fives], "volley={volley}: epoch 72 replays two groups {rolls:?}");
    }
}
