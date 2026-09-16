# Graphics review

Every visual change needs before/after screenshots. Use the same saved board,
camera transforms, resolution, renderer and quality preset for both revisions.
Capture the baseline before editing. Do not retouch or recolour the evidence.

`tools/gfx_lighting_capture.gd` loads the bundled tutorial board in `main.tscn`
and captures Day and Sunset from three fixed viewpoints at 1920x1080 / Medium.
It writes original PNGs and a JSON report with camera transforms and frame times.
Use a real display; Godot's headless renderer cannot produce these screenshots.

```sh
NML_WINDOWED=1 godot --path . --audio-driver Dummy \
  -s res://tools/gfx_lighting_capture.gd -- /tmp/lighting-before
```

Run with isolated `XDG_DATA_HOME` and `XDG_CONFIG_HOME` directories to preserve
the player's settings. Populate their asset caches first and pin the bundled
model manifest using the existing `user://manifest_override.json` mechanism.
Use the same caches for both revisions. Verify that the board loads all 54 models.

The capture disables camera interpolation and hides HUD, flat terrain overlays,
deployment zones, fires and ground mist on both sides. This isolates lighting;
it does not change those features in the game. Vegetation and sky shaders remain
animated, so their fine details can vary between captures.

Frame times are wall-clock frame intervals with VSync and the FPS cap disabled:
90 warm-up frames, then 180 samples per viewpoint, reporting median and p95.
These are end-to-end measurements, not isolated GPU timings. Compare on the same
machine without concurrent GPU workloads; do not infer a speedup from one run.

Include the comparison page and original screenshot links in each graphics PR,
alongside affected scenes, timings, asset credits and validation results. Review
images belong outside shipped game assets. Existing project art is credited to
Niemandsland under CC-BY-SA 4.0; see `THIRD_PARTY.md`.
