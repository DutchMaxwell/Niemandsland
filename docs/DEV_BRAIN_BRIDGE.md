# Developer brain bridge (not a player release)

This opt-in experiment lets the existing Rust search ask a trusted, local
Python evaluator for batched leaf values. It is off by default, unavailable
in release Godot builds, and does not install a model or change exports,
downloads, multiplayer, saves, or release workflows. Use only in developer
solo games. Do not use it for multiplayer or reproducibility-critical runs.

## Start with the public dummy

Build/install the optional extension in your development checkout:

```sh
cargo build --manifest-path core/Cargo.toml -p nml-core-godot --release -j2
bash core/install_gdextension.sh
NML_BRAIN_MODULE=brain_dummy python3 tools/brain_server.py
```

Then, in another terminal, launch the editor/debug game with the Rust planner
enabled and start a solo game. With both switches below set, AI-marked slots
automatically use the rollout planner; human slots remain human. No new player
difficulty is exposed. Explicit arena difficulty selections take precedence:

```sh
NML_CORE=1 NML_BRAIN_URL=http://127.0.0.1:8765 NML_BRAIN_W=1 \
  godot --path .
```

The dummy returns zero, **not intelligent play**. The actual trained evaluator
requires the lab-maintained private adapter; none is supplied here. A leaf
evaluator is not the existing `NML_PLAYOUT_NET` policy-planning mode. Leave
`NML_PLAYOUT_NET*` unset; those unsupported modes still decline. The bridge
does not implement the position solver or any missing rules.

## Private adapter contract

`NML_BRAIN_MODULE` is a trusted importable Python module name (for example,
`brain_dummy` or `my_lab.adapter`). Add the adapter's directory to `PYTHONPATH`
when it is not installed in the server's Python environment.
It exports `score(states, side) -> list[float]`, optionally `BRAIN_NAME` and
`BRAIN_HASH`. Loading executes that module's Python code, so never point it at
an untrusted download. Load the model once at module import, not per request.
For a real model, set `BRAIN_HASH` to its checkpoint/content hash; the fallback
hash identifies **only the adapter source file**, not model weights.

Despite the parameter name, `states` contains **policy token dictionaries**,
not raw board states. This is the existing `PyLeafValue::value` callback
contract in `core/nml-core-py/src/lib.rs`. Both bindings call
`nml-core::tokens::build(..., cands=[], best=-1, ...)`; both leaf paths now
serialize with `Tokens::to_json`. Float32 feature values are promoted exactly
to float64 before JSON, preserving the old Python float values. The server
must not call `policy_tokens` a second time or mirror side 2 again.

Each dictionary has the existing keys/shapes:

| Key | Shape |
| --- | --- |
| `units`, `units_mask` | 24×72, 24 |
| `objs`, `objs_mask` | 6×12, 6 |
| `terr`, `terr_mask` | 18×12, 18 |
| `glob` | 16 |
| `cands`, `cands_mask` | 160×40, 160; state-only, masked out |
| `actor`, `target`, `label` | 160, 160, scalar -1 |

Leaves are ordered by candidate pool, then rollout boundary, already in the
searching side's frame. Return exactly one finite numeric value per leaf in
that same order. Values use the existing `leaf_value_fn` evaluation scale;
the core applies `leaf_value_w` during leaf backup. No clipping or sign change
is introduced by the bridge. Exceptions, wrong lengths and non-finite values
are errors, not zeros. Keep scoring deterministic and the model immutable
through a game. Restart/new game when changing the model.

## HTTP contract, schema 1

One POST to `/`, `Content-Type: application/json`, per activation's leaf batch:

```json
{"schema":1,"core_commit":"0123456789abcdef0123456789abcdef01234567","rules_epoch":6,"side":2,"leaves":["<full policy_tokens dictionary described above>"]}
```

The string placeholder above stands for the full dictionary, not a literal
wire value. A startup identity probe uses the same envelope with `leaves: []`;
it does not invoke the scorer. Example response for one leaf:

```json
{"schema":1,"values":[0.25],"brain":{"name":"local-value","hash":"checkpoint-content-hash"}}
```

`core_commit` uses the extension's build identity (explicit `NML_BUILD_COMMIT`
before build, else Git HEAD, else `unknown`). `rules_epoch` identifies the
compiled rule epoch. These fields describe the caller; the generic server
validates their shape, **not model compatibility**. The private adapter owner
must choose a compatible model/token vocabulary. This bridge does not certify
that model training and table rules match.

Only literal loopback HTTP endpoints are accepted, with an explicit port:
`http://127.0.0.1:8765` (IPv6 loopback is accepted by the client too). No DNS,
redirects, proxy, TLS, remote address, or Unix socket support. The supplied
server binds IPv4 loopback only, refuses non-loopback peers and browser
`Origin` requests, and requires bounded, length-delimited JSON bodies.
It is not an authentication boundary against other local processes.

## Switches and failure behavior

- `NML_BRAIN_URL` unset/empty: no client, probe, extra decision field or network
  call. Existing Rust/GDScript routing is unchanged.
- `NML_BRAIN_W`: finite positive weight, default 1 when armed. Unset the URL
  to disable the bridge. Invalid configuration declines explicitly.
- `NML_BRAIN_TIMEOUT_MS`: whole HTTP exchange deadline, default 200 ms,
  accepted range 1–10000. Token construction precedes this deadline. A slow
  server may continue its work after the client declines.
- `NML_BRAIN_PORT`: server listen port, default 8765.

A game-start probe logs `brain: <name> <hash> at <url>, w=<w>` for each native
controller. Successful decisions carry brain name/hash, batches consumed and
batch microseconds (including token construction/serialization). Failed
requests, timeout, schema/length errors, changed brain identity, token-export
limits and unsupported rules return typed declines. The controller logs each
decline reason once and uses its existing GDScript planner. No failed call is
reported as a brain-assisted decision. An initial probe failure leaves this
controller declined for the game; restart the game after restoring the server.

The Rust search imagines **the twin's supported rule subset**, while the
real table executes **the table's rules**. The position-solver gap and existing
declines remain. This developer connection is not the shipped neural-opponent
milestone, a rule-parity proof, or a replacement for export/runtime work.

## Tests

`cargo test --manifest-path core/Cargo.toml --workspace --release -j2` includes
an independent fake HTTP server for the client. The normal Python suite
includes the public server's dummy/validation tests. Install the extension
before running `test/e2e/e2e_dev_brain_test.gd`; otherwise its optional native
tests explicitly skip. That suite boots the real main scene, asserts a
brain-tagged controller decision, and terminates its own fake process to
exercise the fallback. The fake is independent of the public server so PR 1
can be tested without PR 2 or private code.
