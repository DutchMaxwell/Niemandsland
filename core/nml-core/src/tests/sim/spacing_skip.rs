use super::*;

    // ---- `SpacingObstacles`: skipping a unit by its bounding box never changes a `legal` answer. ----

    fn xorshift(s: &mut u64) -> u64 {
        *s ^= *s << 13;
        *s ^= *s >> 7;
        *s ^= *s << 17;
        *s
    }

    /// The pre-change test, verbatim: every (mover model, obstacle model) pair, `length` widened, compared with `r + own_r`.
    fn legal_reference(own: &[(geom::V3, f64)], list: &[(geom::V3, f64)], step: geom::V3) -> bool {
        for (p, own_r) in own {
            let q = geom::add(*p, step);
            for (oc, r) in list {
                let flat: geom::V3 = [q[0] - oc[0], 0.0, q[2] - oc[2]];
                if (geom::length(flat) as f64) < r + own_r {
                    return false;
                }
            }
        }
        true
    }

    fn build(units: &[Vec<(geom::V3, f64)>]) -> SpacingObstacles {
        let mut o = SpacingObstacles::default();
        for u in units {
            o.list.extend(u.iter().copied());
            o.end_unit();
        }
        o
    }

    const TS: [f64; 9] = [1.0, 0.0, 0.5, 0.25, 0.75, 0.125, 0.875, 0.3125, 0.9375];

    /// Realistic scale (metres on a 1.8 x 1.2 m table, base radii 12-50 mm, 1" buffer), 3-16 units, obstacles ON THE BOUNDARY of a
    /// mover model's path (at `r + own_r` +- {0, 1e-7 .. 5e-3}, along an axis or at an angle). Answers must equal the reference for
    /// every `t`, blocking cases must occur, and most units must be skipped (else this proves nothing).
    #[test]
    fn skipping_units_never_changes_the_answer_and_does_skip() {
        let mut st = 0xFEED_FACE_1234_5678u64;
        let unit = |st: &mut u64| (xorshift(st) % 2_000_001) as f64 / 1_000_000.0 - 1.0;
        let (mut units_total, mut units_live, mut blocked, mut free) = (0usize, 0usize, 0u32, 0u32);
        for round in 0..6000 {
            let n_own = 1 + (xorshift(&mut st) % 8) as usize;
            let own_r = [0.0127, 0.016, 0.025, 0.03][(xorshift(&mut st) % 4) as usize];
            let (cx, cz) = (unit(&mut st) * 0.8, unit(&mut st) * 0.5);
            let own: Vec<(geom::V3, f64)> = (0..n_own)
                .map(|_| ([(cx + unit(&mut st) * 0.06) as f32, 0.0, (cz + unit(&mut st) * 0.06) as f32], own_r))
                .collect();
            let delta = [(unit(&mut st) * 0.3) as f32, 0.0, (unit(&mut st) * 0.3) as f32];
            let mut units: Vec<Vec<(geom::V3, f64)>> = (0..3 + xorshift(&mut st) % 14)
                .map(|_| {
                    let (ux, uz) = (unit(&mut st) * 0.9, unit(&mut st) * 0.6);
                    let buf = 0.0254 * (xorshift(&mut st) % 2) as f64;
                    (0..1 + xorshift(&mut st) % 10)
                        .map(|_| ([(ux + unit(&mut st) * 0.08) as f32, 0.0, (uz + unit(&mut st) * 0.08) as f32], [0.0127, 0.016, 0.025][(xorshift(&mut st) % 3) as usize] + buf))
                        .collect()
                })
                .collect();
            for _ in 0..4 {
                let m = &own[(xorshift(&mut st) as usize) % own.len()];
                let t = (xorshift(&mut st) % 1001) as f64 / 1000.0;
                let (px, pz) = (m.0[0] as f64 + delta[0] as f64 * t, m.0[2] as f64 + delta[2] as f64 * t);
                let r = [0.0127, 0.016, 0.025][(xorshift(&mut st) % 3) as usize] + 0.0254 * (xorshift(&mut st) % 2) as f64;
                let off = [0.0, 1e-7, -1e-7, 1e-5, -1e-5, 1e-4, -1e-4, 1e-3, -1e-3, 5e-3, -5e-3][(xorshift(&mut st) % 11) as usize];
                let ang = [0.0, std::f64::consts::FRAC_PI_2, std::f64::consts::PI, -std::f64::consts::FRAC_PI_2, unit(&mut st) * std::f64::consts::PI][(xorshift(&mut st) % 5) as usize];
                let d = r + m.1 + off;
                let k = (xorshift(&mut st) as usize) % units.len();
                units[k].push(([(px + d * ang.cos()) as f32, 0.0, (pz + d * ang.sin()) as f32], r));
            }
            let obstacles = build(&units);
            for t in TS {
                let step = geom::mul(delta, t);
                let want = legal_reference(&own, &obstacles.list, step);
                assert_eq!(obstacles.legal(&own, step), want, "round {round} t {t}");
                if t == 1.0 {
                    units_total += obstacles.spans.len();
                    units_live += (obstacles.live(&own, step) & ((1u64 << obstacles.spans.len()) - 1)).count_ones() as usize;
                }
                if want { free += 1 } else { blocked += 1 }
            }
        }
        assert!(units_live * 2 < units_total, "most units must be skipped: live {units_live} of {units_total}");
        assert!(blocked > 3000 && free > 3000, "both outcomes must occur: blocked {blocked} free {free}");
    }

    /// NaN / infinite / huge / signed-zero coordinates and radii, empty movers, 70 units (past the 64-bit mask): same answers.
    #[test]
    fn odd_values_and_many_units_keep_the_answer() {
        let mut st = 0x1234_5678_9ABC_DEF1u64;
        let odd = |st: &mut u64| match xorshift(st) % 12 {
            0 => f32::NAN,
            1 => f32::INFINITY,
            2 => f32::NEG_INFINITY,
            3 => -0.0,
            4 => 3.0e19,
            5 => 999.99,
            6 => -1000.01,
            _ => ((xorshift(st) >> 8) % 400) as f32 / 100.0 - 2.0,
        };
        let odd_r = |st: &mut u64| match xorshift(st) % 9 {
            0 => f64::NAN,
            1 => f64::INFINITY,
            2 => -0.5,
            3 => 0.0,
            _ => 0.03 + (xorshift(st) % 100) as f64 / 1000.0,
        };
        for round in 0..3000 {
            let n_own = (xorshift(&mut st) % 4) as usize;
            let own: Vec<(geom::V3, f64)> = (0..n_own).map(|_| ([odd(&mut st), 0.0, odd(&mut st)], odd_r(&mut st))).collect();
            let units: Vec<Vec<(geom::V3, f64)>> = (0..1 + xorshift(&mut st) % 70)
                .map(|_| (0..xorshift(&mut st) % 4).map(|_| ([odd(&mut st), 0.0, odd(&mut st)], odd_r(&mut st))).collect())
                .collect();
            let obstacles = build(&units);
            for t in [1.0, 0.0, 0.5] {
                let step = geom::mul([odd(&mut st), 0.0, odd(&mut st)], t);
                assert_eq!(obstacles.legal(&own, step), legal_reference(&own, &obstacles.list, step), "round {round} t {t}");
            }
        }
    }

    /// A unit past index 63 is always tested: the only blocker sits in unit 65 of 70.
    #[test]
    fn a_blocker_in_unit_sixty_five_is_found() {
        let mut units: Vec<Vec<(geom::V3, f64)>> = (0..70).map(|i| vec![([5.0 + i as f32, 0.0, 5.0], 0.04)]).collect();
        units[65] = vec![([0.01, 0.0, 0.0], 0.04)];
        let own = [([0.0f32, 0.0, 0.0], 0.03)];
        let o = build(&units);
        assert!(!o.legal(&own, [0.0; 3]));
        assert_eq!(o.legal(&own, [0.0; 3]), legal_reference(&own, &o.list, [0.0; 3]));
    }

    /// The blocker sits in unit 1, units 64..69 are far away: a skip decision made for a high unit must never clear a low unit's bit.
    #[test]
    fn a_blocker_in_a_low_unit_survives_many_far_units() {
        let mut units: Vec<Vec<(geom::V3, f64)>> = (0..70).map(|i| vec![([5.0 + i as f32, 0.0, 5.0], 0.04)]).collect();
        units[1] = vec![([0.01, 0.0, 0.0], 0.04)];
        let own = [([0.0f32, 0.0, 0.0], 0.03)];
        let o = build(&units);
        assert!(!legal_reference(&own, &o.list, [0.0; 3]));
        assert!(!o.legal(&own, [0.0; 3]));
    }
