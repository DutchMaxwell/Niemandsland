# Contributing to Niemandsland

Thanks for trying the alpha! There are several ways to help, from low to high effort.

## 1. Give feedback (most valuable right now)

This is an early alpha — telling us what's broken or awkward is the single most
useful thing you can do.

- **[Open an issue](../../issues/new/choose)** and pick a template:
  - 🐞 **Bug report** — something broke or behaves wrong.
  - 💡 **Feedback / idea** — UX friction, suggestions, feature ideas.
- For bugs, please include your **OS** (Windows / macOS / Linux), the
  **version** (title bar, e.g. `v0.3.6.0-alpha`), and **steps to reproduce**. A Godot
  log or screenshot helps a lot.
- Security issues: please report privately — see [`SECURITY.md`](SECURITY.md).

## 2. Improve the docs

Spotted something outdated or unclear? Doc-only PRs are very welcome and easy to
review. The docs index is [`docs/README.md`](docs/README.md).

## 3. Contribute code

### Dev setup

You need **[Godot 4.6](https://godotengine.org/download)** (Forward+ renderer).

```bash
git clone https://github.com/DutchMaxwell/Niemandsland.git
cd Niemandsland
godot --path . --editor      # open in the editor, then F5 to run
# or run headless / directly:
godot --path .
```

Main scene: `scenes/startup_menu.tscn`. Build/run/test details (incl. the Flatpak
invocation used in development) are in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

### Where things live

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — systems, scripts, data flow,
  networking and the (critical) scaling conventions. **Read this first.**
- [`PROJECT_STATUS.md`](PROJECT_STATUS.md) — what works / in progress / planned, a
  good place to find something to pick up.
- `scripts/` — the GDScript game code; `test/` — gdUnit4 suites; `relay/` — the
  multiplayer WebSocket relay (Python).

### Tests

Run the tests before pushing — CI runs the same on Godot 4.6:

```bash
# gdUnit4 (GDScript) — see docs/DEVELOPMENT.md for the full runner command:
godot --headless -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://test
# relay (Python):
cd relay && pip install -r requirements-dev.txt && python -m pytest
```

### Pull request flow

1. Branch off `main` (`git checkout -b feat/my-change`).
2. Keep the codebase **English** (identifiers, comments, commit messages) and match
   the existing style — see [`docs/CODING_STANDARDS.md`](docs/CODING_STANDARDS.md).
3. Use **conventional commits**: `feat:`, `fix:`, `refactor:`, `docs:`, `perf:`.
4. Make sure the tests pass and the project imports without GDScript parse errors.
5. Open a PR against `main` describing what changed and why. CI must be green.

By submitting a pull request you agree that your contribution is licensed under
the project's [MIT License](LICENSE).

### Scope note

The offline 3D asset-generation pipeline (image generation → TRELLIS → GLB) lives in
a **separate private repository**; this repo consumes only its outputs, delivered on
demand from a CDN. Contributions here are about the game, the relay, and the docs —
not asset generation.

## How this project is run

Niemandsland is maintained by a single person, for fun, in their spare time — please
treat it that way:

- **Feedback first.** The most useful contribution is a clear bug report or idea, not
  a large surprise pull request.
- **Discuss before you build.** For anything beyond a small fix, open an issue first
  so we can agree on the approach. Big unsolicited PRs may be declined simply because
  they don't fit the direction — that's not personal.
- **The maintainer has the final say** on what gets merged, the roadmap and the
  scope. Reviews and replies are best-effort, with no timeline or guarantee.
- **No obligation.** An open issue or PR is a suggestion, not a ticket we owe you.

## Code of conduct

Be kind and constructive. This is a hobby project made for fun; assume good faith,
keep discussion on-topic, and help newcomers where you can.
