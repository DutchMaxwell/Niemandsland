//! Firefight goldens (plan steps 21-23): one small scene per rule, played through the step API the table drives
//! (`activation::step_activation`) from the table's own JSON shape (an act header's profiles + a plain state), with every
//! die given in the fixture. The outcome - the battle-log lines, the dice asked for, and each unit's models, wounds and
//! Shaken flag - is pinned in the same fixture under `pinned`. A rules change that moves an outcome turns its golden red;
//! a deliberate change re-blesses it with `NML_FF_GOLDEN_BLESS=1 cargo test --test ff_golden` and the diff shows in review.
//!
//! Fixtures: `tests/fixtures/ff_golden/<name>.json`. Each plays at its own `epoch` (a record replays at the epoch it was
//! made under), so a later epoch bump does not move a golden; the bump's own goldens pin the new leg.
use nml_core::activation::{step_activation, ActStep, Input};
use nml_core::io::{state_from_json_with_epoch, Seams};
use nml_core::rules::Registries;
use nml_core::state::ProfileCache;
use nml_core::terrain::{CellParams, PlainTerrain, Terrain};
use nml_core::unit::UnitStatic;
use serde_json::{json, Value};
use std::collections::{BTreeMap, VecDeque};

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/ff_golden");
const IN2M: f64 = 0.0254;

/// Plays the fixture's activation and returns what `pinned` holds.
fn play(fx: &Value) -> Value {
    let epoch = fx["epoch"].as_u64().expect("epoch") as u32;
    let header = nml_core::acts::read_act_header(&fx["header"].to_string()).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let st = state_from_json_with_epoch(&fx["state"].to_string(), &mut cache, &mut None, epoch).expect("state");
    let mut reg = Registries::new(REPO);
    let statics: Vec<UnitStatic> = st.profiles.list.iter().map(|p| UnitStatic::build_for(&mut reg, p, epoch)).collect();
    let feet = &fx["terrain"]["table_feet"];
    let terrain = Terrain::build(&PlainTerrain {
        cells: fx["terrain"]["cells"].as_array().map_or(vec![], |c| c.iter().map(|v| [v[0].as_f64().unwrap(), v[1].as_f64().unwrap(), v[2].as_f64().unwrap()]).collect()),
        cell_params: CellParams { table_size_feet: [feet[0].as_f64().unwrap(), feet[1].as_f64().unwrap()], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: IN2M },
        ..Default::default()
    });
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let mut dice: BTreeMap<String, VecDeque<Vec<u8>>> = fx["dice"].as_object().expect("dice").iter()
        .map(|(k, v)| (k.clone(), v.as_array().unwrap().iter().map(|f| f.as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as u8).collect()).collect()))
        .collect();
    let i = &fx["intent"];
    let mut t = vec![Input::Begin, Input::Intent {
        kind: i["kind"].as_i64().unwrap_or(0), shoot: i["shoot"].as_str().map(String::from), split: None,
        charge: i["charge"].as_str().map(String::from), no_step: false,
    }];
    // A move: the table's drop (`placed.at`, inches, one spot per model) with each model's dragged path (`placed.trails`).
    if let Some(p) = fx.get("placed") {
        let inch = |v: &Value| v.as_f64().unwrap() * IN2M;
        t.push(Input::Placed {
            at: p["at"].as_array().unwrap().iter().map(|a| [inch(&a[0]), inch(&a[1]), inch(&a[2])]).collect(),
            trails: p["trails"].as_array().unwrap().iter()
                .map(|tr| tr.as_array().unwrap().iter().map(|q| [inch(&q[0]), inch(&q[1])]).collect()).collect(),
        });
    }
    // Answers the table sends up front with the transcript (its probes: a push, its spot, the defender's place).
    for c in fx["choices"].as_array().into_iter().flatten() {
        t.push(Input::Choice { id: c[0].as_str().unwrap().into(), option: c[1].as_str().unwrap().into() });
    }
    let unit = fx["unit"].as_str().expect("unit");
    let mut rolls = vec![];
    for _ in 0..200 {
        match step_activation(&statics, &st, unit, &terrain, seams, &t, true) {
            ActStep::NeedRoll { faces, kind, .. } => {
                let f = dice.get_mut(kind).and_then(VecDeque::pop_front)
                    .unwrap_or_else(|| panic!("{}: no dice left for a '{kind}' roll of {faces} (rolls so far {rolls:?})", fx["golden"]));
                assert_eq!(f.len(), faces, "{}: the '{kind}' roll asks {faces} dice, the fixture gives {f:?}", fx["golden"]);
                rolls.push(json!([kind, f]));
                t.push(Input::Faces(f));
            }
            ActStep::NeedChoice { id, options, .. } => {
                let o = fx["answers"][&id].as_str().unwrap_or_else(|| panic!("{}: no answer for {id} ({options:?})", fx["golden"]));
                t.push(Input::Choice { id, option: o.into() });
            }
            ActStep::Done { state, lines, .. } => {
                let units: Vec<Value> = (0..state.player.len()).map(|u| json!({
                    "unit": state.roster.keys[u], "alive": state.alive[u], "shaken": state.shaken[u], "wounds": state.wounds[u],
                    "at_in": state.positions[u].iter().map(|p| [(p[0] / IN2M * 1000.0).round() / 1000.0, (p[2] / IN2M * 1000.0).round() / 1000.0]).collect::<Vec<_>>(),
                })).collect();
                let left: Vec<&String> = dice.iter().filter(|(_, q)| !q.is_empty()).map(|(k, _)| k).collect();
                assert!(left.is_empty(), "{}: dice never asked for: {left:?}", fx["golden"]);
                return json!({ "rolls": rolls, "lines": lines.iter().map(|l| l.text.clone()).collect::<Vec<_>>(), "final": units });
            }
            other => panic!("{}: the activation stopped: {other:?}", fx["golden"]),
        }
    }
    panic!("{}: no end after 200 steps", fx["golden"])
}

/// Every fixture in the directory: played, compared with its `pinned` (or written, under `NML_FF_GOLDEN_BLESS`).
#[test]
fn every_firefight_golden_plays_as_pinned() {
    let mut names: Vec<_> = std::fs::read_dir(DIR).expect("fixture dir").filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "json")).collect();
    names.sort();
    assert!(!names.is_empty(), "no goldens under {DIR}");
    let bless = std::env::var_os("NML_FF_GOLDEN_BLESS").is_some();
    let mut bad = vec![];
    for path in names {
        let mut fx: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).expect("fixture json");
        let got = play(&fx);
        if bless {
            fx["pinned"] = got;
            std::fs::write(&path, serde_json::to_string_pretty(&fx).unwrap() + "\n").unwrap();
        } else if fx["pinned"] != got {
            bad.push(format!("{}:\n  pinned {}\n  now    {}", path.display(), fx["pinned"], got));
        }
    }
    assert!(bad.is_empty(), "goldens moved:\n{}", bad.join("\n"));
}
