# evo(gen4): candidate 4 -- variant 405

What changed: when a marker ends up with NO unit on either side still projected
to hold it, the old eval handed it outright to its current owner as a full
1.0 / 0.0. Variant 405 instead treats such a marker as genuinely contested
ground: the owner keeps only a fading paper advantage that halves each round
still left to play (reusing the eval's existing per-round DISCOUNT constant),
reaching the referee's exact 1/0 answer only on the final round.

Why: that branch fires on a projection, and the projection can be wrong —
melee replies are invisible to the threat model, so a unit counted as "dead on
arrival" may well survive and hold — and every remaining round is another
chance for the enemy to flip the marker. Mid-game it is therefore not the sure
point the old score claimed, and the locked extreme values made the rollout
search see a cliff (1.0 -> ratio) exactly where the board had barely changed.

Scope: destroy missions and the no-marker trivial case keep the frozen path;
variant 0 is byte-identical to before (no v0 function was touched).
