# What's new: local review and render handoff

The startup menu opens the release sheet when the installed version differs from
`user://whats_new.cfg`'s last-seen version. Opening the sheet acknowledges that
version. **Help & feedback → What's new?** always reopens it. The close button,
window close control and Escape dismiss it. Its English/German button changes all
five cards and the dialog chrome without changing the rest of the menu's locale.

The heading and acknowledgement both read `application/config/version`. This work
does not bump the release: the checkout currently reports `0.3.13.1-alpha`; the
heading follows the release maintainer's version change automatically.

## Review stack

These are local branches only; no network request, push or remote PR was made.
Review each branch against the listed base, in order. Production counts include
all added/deleted source, data and export configuration lines, including blanks;
tests and this handoff are excluded.

| Branch | Base | Production lines changed |
| --- | --- | ---: |
| `feat/whatsnew-data` | `origin/main` | 95 |
| `feat/whatsnew-dialog` | `feat/whatsnew-data` | 87 |
| `feat/whatsnew-menu` | `feat/whatsnew-dialog` | 27 |

The data branch supplies bilingual copy, acknowledgement and export inclusion.
The dialog branch supplies house-style scrolling cards and dismissal. The final
branch wires startup and menu reopening and queues an update offer until the
release sheet has relinquished native modal ownership.

## Capture queue

Exact composition, camera, scene, lighting, UI and output requirements are in each
card's `capture` field in [`data/whats_new.json`](../data/whats_new.json). Supply:

1. `assets/whats_new/factions.png` — Saurians and Vampiric Undead.
2. `assets/whats_new/borderland.png` — the complete Ruined Borderland table.
3. `assets/whats_new/effects.png` — combat and spell effects; verify Gore Off too.
4. `assets/whats_new/graphics.png` — biome colours and table frame.
5. `assets/whats_new/opponent.png` — an actual solo battle against NACHTMAHR.

All captures are 1920×1080 PNGs. The dialog displays localized house-style image
placeholders until the files exist, then loads the images without a code change.
Capture instructions are not exposed as player-facing copy. GPU captures and
visual review remain for the render lane; no screenshots were fabricated here.

## Validation

The version-persistence and menu-reopening tests were run RED before production
changes. The dialog lifecycle tests were also run RED before its implementation.
The final headless checks cover the three new suites plus `startup_menu_test.gd`,
`update_checker_test.gd` and `ui_polish_test.gd`: 55 tests, zero failures and zero
`SCRIPT ERROR` messages. The editor import also has zero `SCRIPT ERROR` or parse
errors. Existing shadowing warnings and sandbox-denied editor debugger sockets
remain baseline diagnostics. The full repository suite was not run.

Validation logs are in `/tmp/whatsnew-validation/`: `red.log`, `dialog-red.log`,
`import-final.log` and `final-green.log`. Test runs isolate user preferences with
`XDG_DATA_HOME` and `XDG_CONFIG_HOME` under that directory. The live-menu test uses
an offline subclass to suppress update checks and music downloads while running
the real startup lifecycle.
