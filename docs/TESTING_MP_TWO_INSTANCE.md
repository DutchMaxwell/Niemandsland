# Two-instance multiplayer regression test

`test/mp/run_two_instance.py` starts a local relay and two real headless Godot
clients. It creates one private room, waits for the version handshake and the
host-authoritative slot table, loads the same deterministic fixture in both
clients, and drives the production entry points used by the UI.

The default run covers:

- round-duration spell placement and expiry;
- Fatigued status placement and round reset;
- two round-start ticks of Piercing Growth;
- the live LOS line and sight count over a human opponent.

The driver compares both peers after every step. A timeout, process crash,
English or German GDScript parser/runtime error, wrong expected value, or peer
divergence exits non-zero. Raw logs and snapshots remain in the requested run
directory. Temporary `XDG_DATA_HOME` directories are separate for each peer and
are removed on success and failure.

## Run

Install the relay's Python requirements first. The complete acceptance command
runs the scenario three times and compares normalized snapshots:

```bash
python -m pip install -r relay/requirements.txt
python test/mp/run_two_instance.py --run-dir reports/mp-two-instance
```

For the project's Flatpak Godot installation:

```bash
relay/.venv/bin/python test/mp/run_two_instance.py \
  --godot "flatpak run --filesystem=home --share=network org.godotengine.Godot" \
  --run-dir reports/mp-two-instance
```

The run directory must be new. `--repeat 1` is useful while developing a
scenario; the default remains three because snapshot determinism is part of the
test contract. Use `--timeout 120` to change the per-scenario deadline. The
driver chooses a free relay port unless `--port` is supplied and waits for at
least 3500 MB of available memory before starting either Godot process.

PR #665's activation-economy scenario is intentionally opt-in until that branch
lands:

```bash
python test/mp/run_two_instance.py --run-dir reports/mp-two-instance-transport \
  --repeat 1 --include-transport
```

## Artifacts

Each `run-NN/` contains `host.log`, `guest.log`, `relay.log`, the raw checkpoint
JSON files, and `deterministic-snapshots.json`. The root contains
`determinism.json` on success or `failure.json` on failure. Determinism comparison
replaces only the relay's cryptographically random room code, including its
formatted occurrence in the battle log; unit state, marker state, flags, LOS
result, and the rest of each battle-log tail remain in the comparison.

The effective standard status markers are represented by `status_markers` in a
snapshot. This is deliberate: the acting peer stores Fatigued/Shaken/Activated
in unit flags, while the receive path also retains the corresponding wire marker
name in a model's generic marker array. Custom and spell marker names remain in
the per-model `markers` arrays.

## Add a scenario

1. Add a small deterministic unit to `_setup_fixture()` only when the existing
   fixture cannot express the case. Keep stable unit and network IDs.
2. Add a command in `_run_command()` that calls the production entry point used
   by the UI. Do not call a `NetworkManager.sync_*` or RPC method directly.
3. Send the command only to the acting peer from `Run.scenario()`. Commands sent
   to both peers are reserved for local fixture setup that produces no network
   traffic.
4. Wait on the resulting state predicate, then call `checkpoint()`. Include a
   unit/property diagnostic so a RED result identifies the peer, unit, expected
   value, and actual value.
5. Prove the test RED by reverting the relevant fix in a scratch worktree, then
   restore the fix and run the default three-pass command.

Synchronization is state-driven. Short polling intervals only re-read process
and snapshot state; fixed sleeps are not used as proof that a network action has
arrived.

## Known limitations

- The harness verifies two-player relay sessions. It does not cover 3+ player
  slot assignment or reconnect/fault behavior; `test/mp/run_soak.py` owns those
  long-running transport tests.
- LOS enters targeting mode at the audited targeting seam because the full
  human-vs-human attack resolver is intentionally outside the product contract.
  Ray-picking, target ownership, line construction, and sight-count rendering
  are real production paths.
- The fixture is local and deterministic on both clients. Army Forge download,
  model CDN access, and import-state replication belong to the existing soak
  workloads and are intentionally excluded from this sub-five-minute gate.

## Proposed CI step

Workflow changes are intentionally separate. A Linux job with Godot 4.6 and the
relay requirements installed can run:

```yaml
- name: Two-instance multiplayer regressions
  run: |
    python test/mp/run_two_instance.py \
      --godot godot \
      --run-dir reports/mp-two-instance
- name: Upload multiplayer artifacts
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: mp-two-instance
    path: reports/mp-two-instance
```
