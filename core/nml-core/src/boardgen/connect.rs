//! Stage 3: the ways up. A connector joins two neighbouring cells whose levels differ by exactly one (a 3 in rise):
//! a `Ladder` (3 in rise). Nothing else crosses a tier edge, so a rise of 6 in has no connector, and the board
//! carries no movement cost: the core prices climbs from the heights it reads. There are no stairs (maintainer
//! decision 20.11.): models cannot stand on steps and steps are not 3 in units, so models only ever stand on flat
//! whole cells and every level change is a ladder.
//! Each island (a set of same-level neighbours) gets two ascents from the level below where it has room for two;
//! a final pass joins whatever is still cut off.
use std::collections::VecDeque;
use serde::{Deserialize, Serialize};
use crate::rng::GodotRng;
use super::levels::{mirror, neighbours, shuffle, Cell};
use super::Symmetry;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum ConnectorKind { Ladder }
/// `low` and `high` are cell indices (`z * 16 + x`) of neighbouring cells, `level(high) == level(low) + 1`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct Connector { pub kind: ConnectorKind, pub low: u16, pub high: u16 }

pub fn wire(seed: i64, sym: Symmetry, cells: &[Cell]) -> Vec<Connector> {
    let mut rng = GodotRng::new(seed);
    let mut conns: Vec<Connector> = Vec::new();
    let add = |conns: &mut Vec<Connector>, rng: &mut GodotRng, (low, high): (usize, usize)| {
        // The draw of the retired stair/ladder coin flip stays, so every seed keeps its connector positions: only the kind changed.
        let _ = rng.randi_range(0, 1);
        let kind = ConnectorKind::Ladder;
        for (l, h) in if sym == Symmetry::Point180 { vec![(low, high), (mirror(low), mirror(high))] } else { vec![(low, high)] } {
            if !conns.iter().any(|c| (c.low, c.high) == (l as u16, h as u16)) { conns.push(Connector { kind, low: l as u16, high: h as u16 }); }
        }
    };
    let isl = islands(cells);
    for level in 1..=3u8 {
        for id in 0..isl.count {
            if cells[isl.first[id]].level != level { continue; }
            let mut pairs = access_pairs(cells, &isl, id);
            shuffle(&mut pairs, &mut rng);
            for pair in pairs.into_iter().take(2) {
                let have = conns.iter().filter(|c| isl.of[c.high as usize] == id).count();
                if have < 2 { add(&mut conns, &mut rng, pair); }
            }
        }
    }
    // Join what is still cut off: any neighbouring pair one level apart in different components.
    let mut comp = Dsu::new(cells.len());
    for i in 0..cells.len() { for j in neighbours(i).filter(|&j| cells[j].level == cells[i].level) { comp.union(i, j); } }
    for c in &conns { comp.union(usize::from(c.low), usize::from(c.high)); }
    let mut bridges: Vec<(usize, usize)> = (0..cells.len()).flat_map(|i| neighbours(i).filter(move |&j| cells[j].level == cells[i].level + 1)
        .map(move |j| (i, j))).collect();
    shuffle(&mut bridges, &mut rng);
    for (low, high) in bridges {
        if comp.find(low) != comp.find(high) {
            add(&mut conns, &mut rng, (low, high));
            for c in &conns { comp.union(usize::from(c.low), usize::from(c.high)); }
        }
    }
    conns.sort();
    conns
}

/// Number of connected walkable areas (same-level neighbours plus connectors). A good board has exactly one.
pub fn component_count(cells: &[Cell], conns: &[Connector]) -> usize {
    let mut comp = Dsu::new(cells.len());
    for i in 0..cells.len() { for j in neighbours(i).filter(|&j| cells[j].level == cells[i].level) { comp.union(i, j); } }
    for c in conns { comp.union(usize::from(c.low), usize::from(c.high)); }
    (0..cells.len()).filter(|&i| comp.find(i) == i).count()
}

/// Islands above ground with fewer ascents (connectors to the level below) than `min(2, access pairs they have)`.
pub fn ascent_shortfall(cells: &[Cell], conns: &[Connector]) -> usize {
    let isl = islands(cells);
    (0..isl.count).filter(|&id| cells[isl.first[id]].level >= 1).filter(|&id| {
        let have = conns.iter().filter(|c| isl.of[usize::from(c.high)] == id).count();
        have < access_pairs(cells, &isl, id).len().min(2)
    }).count()
}

struct Islands { of: Vec<usize>, first: Vec<usize>, count: usize }

/// Same-level connected components of the lattice (island ids by first cell index).
fn islands(cells: &[Cell]) -> Islands {
    let (mut of, mut first) = (vec![usize::MAX; cells.len()], Vec::new());
    for s in 0..cells.len() {
        if of[s] != usize::MAX { continue; }
        let (id, mut q) = (first.len(), VecDeque::from([s]));
        first.push(s);
        of[s] = id;
        while let Some(i) = q.pop_front() {
            for j in neighbours(i) { if of[j] == usize::MAX && cells[j].level == cells[s].level { of[j] = id; q.push_back(j); } }
        }
    }
    Islands { count: first.len(), of, first }
}

/// Every (low cell, island cell) neighbour pair that could carry an ascent into island `id`.
fn access_pairs(cells: &[Cell], isl: &Islands, id: usize) -> Vec<(usize, usize)> {
    (0..cells.len()).filter(|&h| isl.of[h] == id).flat_map(|h| neighbours(h).filter(move |&l| cells[l].level + 1 == cells[h].level).map(move |l| (l, h))).collect()
}

struct Dsu(Vec<usize>);
impl Dsu {
    fn new(n: usize) -> Self { Dsu((0..n).collect()) }
    fn find(&mut self, mut i: usize) -> usize { while self.0[i] != i { self.0[i] = self.0[self.0[i]]; i = self.0[i]; } i }
    fn union(&mut self, a: usize, b: usize) { let (a, b) = (self.find(a), self.find(b)); if a != b { self.0[a.max(b)] = a.min(b); } }
}
