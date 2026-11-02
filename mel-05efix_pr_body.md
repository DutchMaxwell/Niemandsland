DRAFT — row MEL-05e-fix, release 0.3.15 "Rules 3.6".

## What changes for a player

- From rules 3.6 (epoch 73) the AI's charge score counts the defender's Counter strike-first only when the defender will actually strike back. A Fatigued or Shaken defender, or one whose Counter entry opts out of the strike-first slot, no longer thins our charge.
- Epoch 72 and below replay unchanged: the Counter thinning is still unconditional.
- The Rust twin now mirrors the Gadget Data path exactly: `AiEv.charge_score` (ai_ev.gd:1107) reads `SoloController.counter_strikes_first` (solo_controller.gd:8921), and the decision uses the same epoch condition.

## RED / GREEN

- RED (only the new MEL-05e-fix case fails):
  https://github.com/DutchMaxwell/Niemandsland/actions/runs/41426018837/job/125212697453
- GREEN (all jobs green):
  GREEN_RUN_URL

## Local commands and results

- `cargo_slot.sh check -p nml-core --tests --manifest-path core/nml-core/Cargo.toml` on the RED tree: rc=0 (pre-existing warnings only).
- The green patch is handed to the lead with this body; the lead runs the test and gate pass and fills the GREEN link.
- The sandbox does not run godot; CI is the gdUnit gate.
- `tools/epoch_gate_check.py` on the diff: no epoch bump, nothing to check (pass).

## Files

- `core/nml-core/src/menu.rs` — `charge_score` gates the Counter strike-first term on the `SoloController.counter_strikes_first` policy from epoch 73; the per-target policy is computed in `best_charge`.
- `core/nml-core/src/tests/sim/v36_melee_rows/mel_05.rs` — the existing MEL-05 test module, plus the gated charge-score case and the strike-back-policy case.

## Size

- `size-check` (push hook) on the RED tree: 14 production lines added vs origin/main. The green tree adds the helper and the gate; the lead's push reports the final number as SIZE_CHECK_NUMBER.
