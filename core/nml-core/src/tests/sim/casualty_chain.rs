use super::*;

    /// Tray-exact S5 — the core half of the chain-order parity pin (the table half:
    /// test/casualty_order_parity_test.gd, the same fixture). Each fixture chain becomes unit 0
    /// of `four_unit_line`, its joined hero emptied so the group is the unit alone.
    #[test]
    fn the_cores_chain_casualty_order_matches_the_tables_on_the_shared_fixture() {
        let fx: serde_json::Value =
            serde_json::from_str(include_str!("../../../tests/fixtures/casualty_order.json")).unwrap();
        for c in fx["chains"].as_array().unwrap() {
            let mut st = four_unit_line();
            let ms = c["models"].as_array().unwrap();
            let f = |v: &serde_json::Value| v.as_f64().unwrap();
            st.positions[0] = ms.iter().map(|m| [f(&m["pos"][0]), f(&m["pos"][1]), f(&m["pos"][2])]).collect();
            st.wounds[0] = ms.iter().map(|m| m["wounds"].as_i64().unwrap()).collect();
            st.radii[0] = vec![f(&c["base_mm"]) / 2000.0; ms.len()];
            st.alive[0] = ms.len() as i64;
            let mut names: Vec<String> = Vec::new();
            let mut kits = Vec::new();
            for m in ms {
                let mut weapons = Vec::new();
                for w in m["weapons"].as_array().unwrap() {
                    let w = w.as_str().unwrap().to_string();
                    let i = names.iter().position(|n| *n == w).unwrap_or(names.len());
                    if i == names.len() {
                        names.push(w);
                    }
                    weapons.push(i as u16);
                }
                let (e, x) = (m["equipment"].as_u64().unwrap() as u16, m["wounds_max"].as_i64().unwrap());
                kits.push(crate::state::Kit { weapons, equipment: e, wounds_max: x });
            }
            st.kits = vec![Rc::new(kits)];
            (st.positions[1], st.radii[1], st.wounds[1], st.alive[1]) = (vec![], vec![], vec![], 0);
            let want: Vec<usize> =
                c["expected"].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect();
            assert_eq!(crate::casualty::chain_casualty_order(&st, 0, None), Some(want), "{}", c["name"]);
        }
    }
