use super::*;

    // ---- the cold ledgers (limited_used, precision_used, storm_used, feats_used) and `radii` are copy-on-write: a clone SHARES them and
    // a write on the clone un-shares it, the original never changes. ----

    /// One check per field: shared after `clone`, the clone's write lands on the clone only.
    macro_rules! cow_case {
        ($name:ident, $field:ident, $t:ty, $write:expr, $probe:expr) => {
            #[test]
            fn $name() {
                let orig = four_unit_line();
                let before = orig.$field.clone();
                let mut copy = orig.clone();
                assert!(Rc::ptr_eq(&orig.$field, &copy.$field), "a clone shares the field");
                let write: fn(&mut Rc<Vec<$t>>) = $write;
                write(&mut copy.$field);
                assert!(!Rc::ptr_eq(&orig.$field, &copy.$field), "the write un-shared it");
                assert_eq!(orig.$field, before, "the original is unchanged");
                let probe: fn(&Rc<Vec<$t>>) -> bool = $probe;
                assert!(probe(&copy.$field), "the clone carries the write");
                assert!(!probe(&orig.$field), "the original does not");
            }
        };
    }

    cow_case!(limited_used_is_cow, limited_used, Vec<String>, |v| Rc::make_mut(v)[0].push("x".into()), |v| !v[0].is_empty());
    cow_case!(precision_used_is_cow, precision_used, Vec<String>, |v| Rc::make_mut(v)[1].push("x".into()), |v| !v[1].is_empty());
    cow_case!(storm_used_is_cow, storm_used, Vec<String>, |v| Rc::make_mut(v)[2].push("x".into()), |v| !v[2].is_empty());
    cow_case!(feats_used_is_cow, feats_used, Vec<String>, |v| Rc::make_mut(v)[3].push("x".into()), |v| !v[3].is_empty());
    cow_case!(radii_is_cow, radii, Vec<f64>, |v| Rc::make_mut(v)[0][0] += 1.0, |v| v[0][0] > 1.0);

    /// A real production write (the Storm burst's once-per-game stamp) on a clone never reaches the parent state.
    #[test]
    fn storm_stamp_does_not_reach_the_parent() {
        let (st, statics) = storm_line("Storm of Change", "daemons_of_change", 6);
        let (next, _) = run_storm(&st, &statics, 3, 6);
        assert_eq!(next.storm_used[0], vec!["Storm of Change".to_string()]);
        assert!(st.storm_used[0].is_empty(), "the parent ledger stays open");
    }
