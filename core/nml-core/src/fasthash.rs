//! A small deterministic hasher (the FxHash multiply-rotate family) for LOOKUP-ONLY maps on hot paths.
//!
//! `std`'s default `RandomState` is SipHash-1-3 with a random key per map: DoS-hard and slow (it was ~5 % of a game's CPU
//! for the terrain grid lookups alone). Use this only for maps whose iteration order cannot reach an outcome - every
//! site says why next to the declaration. The hash is a pure function of the key (no per-process key), so a map built
//! twice iterates the same way twice; nothing may rely on WHICH order that is.
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

const K: u64 = 0xf135_7aea_2e62_a9c5;

#[derive(Clone, Copy, Default)]
pub struct FastHasher {
    h: u64,
}

impl FastHasher {
    #[inline]
    fn add(&mut self, w: u64) {
        self.h = (self.h.rotate_left(5) ^ w).wrapping_mul(K);
    }
}

impl Hasher for FastHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        let (chunks, rest) = bytes.as_chunks::<8>();
        for c in chunks {
            self.add(u64::from_le_bytes(*c));
        }
        if !rest.is_empty() {
            let mut b = [0u8; 8];
            b[..rest.len()].copy_from_slice(rest);
            self.add(u64::from_le_bytes(b) ^ ((rest.len() as u64) << 56));
        }
    }
    #[inline]
    fn write_u8(&mut self, i: u8) {
        self.add(i as u64);
    }
    #[inline]
    fn write_u32(&mut self, i: u32) {
        self.add(i as u64);
    }
    #[inline]
    fn write_u64(&mut self, i: u64) {
        self.add(i);
    }
    #[inline]
    fn write_i64(&mut self, i: i64) {
        self.add(i as u64);
    }
    #[inline]
    fn write_usize(&mut self, i: usize) {
        self.add(i as u64);
    }
    #[inline]
    fn finish(&self) -> u64 {
        // hashbrown takes the bucket from the LOW bits and a 7-bit tag from the HIGH bits of the hash: the multiply leaves
        // the entropy high, so rotate part of it down.
        self.h.rotate_left(26)
    }
}

pub type FastBuild = BuildHasherDefault<FastHasher>;
pub type FastMap<K, V> = HashMap<K, V, FastBuild>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_fast_map_answers_exactly_like_a_std_map() {
        let mut fast: FastMap<(i64, i64), i32> = FastMap::default();
        let mut std_: HashMap<(i64, i64), i32> = HashMap::new();
        let mut s = 0x2545_F491_4F6C_DD1Du64;
        for i in 0..5000 {
            s ^= s << 13;
            s ^= s >> 7;
            s ^= s << 17;
            let k = ((s % 97) as i64 - 20, ((s >> 20) % 89) as i64 - 20); // includes negatives and many collisions of the low bits
            assert_eq!(fast.insert(k, i), std_.insert(k, i));
        }
        assert_eq!(fast.len(), std_.len());
        for (k, v) in &std_ {
            assert_eq!(fast.get(k), Some(v));
        }
        assert_eq!(fast.get(&(1000, 1000)), None);
        let mut a: Vec<_> = fast.iter().map(|(k, v)| (*k, *v)).collect();
        let mut b: Vec<_> = std_.iter().map(|(k, v)| (*k, *v)).collect();
        a.sort();
        b.sort();
        assert_eq!(a, b);
        // deterministic: the same hasher twice gives the same hash
        use std::hash::BuildHasher;
        let h = |k: &(i64, i64)| FastBuild::default().hash_one(k);
        assert_eq!(h(&(3, 4)), h(&(3, 4)));
        assert_ne!(h(&(3, 4)), h(&(4, 3)));
    }

    #[test]
    fn string_keys_of_every_length_hash_apart() {
        use std::hash::BuildHasher;
        let b = FastBuild::default();
        let keys: Vec<String> = (0..20).map(|n| "p1_u".repeat(1 + n % 5) + &n.to_string()).collect();
        let hs: std::collections::HashSet<u64> = keys.iter().map(|k| b.hash_one(k.as_str())).collect();
        assert_eq!(hs.len(), keys.len());
    }
}
