# Web build → itch.io (automatic browser test build)

The [`web-itch.yml`](../.github/workflows/web-itch.yml) workflow exports the game
to WebAssembly and publishes it to **itch.io** via `butler`, so the latest work
is playable in a browser. It runs automatically on every push to a `claude/**`
branch and can be triggered manually (**Actions → Web Build → itch.io → Run
workflow**) for any branch.

## One-time setup

1. **Create an itch.io project**
   - Sign in at itch.io → **Dashboard → Create new project**.
   - *Kind of project*: **HTML**. Give it a title; note its URL slug
     (`https://<user>.itch.io/<slug>`).
   - Save as **Draft** (or Restricted) for now — you don't need to publish it.

2. **Generate an API key**
   - itch.io → **Settings → API keys** (`https://itch.io/user/settings/api-keys`)
     → **Generate new API key**. Copy it.

3. **Add the GitHub repo settings**
   (**Settings → Secrets and variables → Actions**)
   - **Secret** `BUTLER_API_KEY` = the itch.io API key.
   - **Variable** `ITCH_TARGET` = `<itch-user>/<game-slug>` (e.g. `dutchmaxwell/niemandsland`).

4. **Trigger a build** — push to your `claude/**` branch, or run the workflow
   manually. CI builds the web export and `butler push`es it to the `html5`
   channel.

5. **Enable "play in browser" (first upload only)**
   - On the itch.io project's **Edit game** page, the uploaded `html5` build
     appears. Tick **"This file will be played in the browser"**.
   - Set the embed **viewport** (e.g. `1280×720`, enable the **Fullscreen
     button**) and Save.
   - Subsequent `butler` pushes update the build automatically — no further
     clicks needed.

Without the secret/variable the workflow still runs and uploads the build as the
**`web-build`** artifact on the run (download + serve locally), but skips the
itch.io push.

## Caveats

- **Renderer:** browsers have no Vulkan, so the web build uses the
  **Compatibility** renderer (`rendering_method.web="gl_compatibility"` in
  `project.godot`). Lighting, glow/bloom (incl. the hover highlight) and some
  effects (SSAO, soft shadows) look different from or are absent compared to the
  desktop Forward+ build. This is a good target for testing **UI, interaction,
  dice and layout** — not final visuals.
- **Trimmed build / load time:** the heavy miniature GLBs are excluded from the
  web export (`assets/miniatures/*/glb/*` in the Web preset's `exclude_filter`),
  keeping the build small (~50 MB) so it loads in seconds. **Imported OPR armies
  therefore show fallback shapes instead of their 3D models** in the browser;
  everything else (UI, dice, table/terrain, hover highlight, undo/redo,
  multi-delete) works. To ship the full models instead, remove that filter entry
  — but the `.pck` then balloons to ~1.3 GB (minutes-long load), which is also
  why GitHub Pages (100 MB/file) is not an option.
- **Threads are off** in the Web export preset, so no special cross-origin
  headers are required.
- **Multiplayer** (the relay backend) is not expected to work in-browser; the web
  build is for single-player testing.

## Local test of a web build (without itch.io)

Download the `web-build` artifact from an Actions run, then serve it (the files
must be served over HTTP, not opened as `file://`):

```bash
mkdir -p build/web                  # place the downloaded web export's files here
# (move the unzipped web-build artifact's contents into build/web/)
python3 serve_web.py                # run from the PROJECT ROOT → http://localhost:8060
```

> Use `serve_web.py` (project root, serves `build/web/`), **not** `python3 -m
> http.server` — the bare server omits the cross-origin isolation headers
> (COOP/COEP) the Godot 4 web export requires for SharedArrayBuffer, and the build
> fails to start ("Failed to fetch") without them.
