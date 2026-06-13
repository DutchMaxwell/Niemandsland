# Contributing

Thanks for trying the alpha! Right now, **bug reports and feedback** via the issue
templates are the most useful thing you can do.

## Reporting issues

Use the **Bug report** or **Feedback / idea** templates. For bugs, include your OS,
the version, and steps to reproduce.

## Code contributions

- Engine: **Godot 4.6** (Forward+). Language: GDScript. See
  [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) to build, run and test.
- Branch off `main` and open a pull request.
- **Conventional commits** (`feat:`, `fix:`, `refactor:`, `docs:`, `perf:`).
- Run the tests before pushing: gdUnit4 suites in `test/` and pytest in `relay/`
  (commands in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)).
- Keep the codebase **English**; match the existing style
  ([`.claude/AAA_CODING_STANDARDS.md`](.claude/AAA_CODING_STANDARDS.md)).

## Scope note

The offline 3D asset-generation pipeline lives in a separate repository; this repo
consumes its outputs on demand from a CDN. Contributions here are about the game,
the relay, and the docs.
