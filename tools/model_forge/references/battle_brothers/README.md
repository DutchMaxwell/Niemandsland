# Battle Brothers — design references & IP-safe approach

**Status (approved):** `01_hero_FINAL.png` is the locked-in Battle Brothers look + render
style. `00_style_reference.png` is the image fed to Nano Banana as the **style reference**
(reference_image_path) to reproduce that render look on every unit of the faction.

## The look
- **Palette:** dark slate-grey armour, copper-bronze trim, glowing teal optics, deep maroon
  cloth tabard. (An original Niemandsland identity — deliberately NOT Ultramarine blue/gold/red.)
- **Helmet:** smooth one-piece full-face visor, single horizontal teal light strip, featureless
  (no eye lenses / mouth grille / snout).
- **Shoulders:** wide FLAT trapezoidal plates with diagonal copper chevrons (NOT round pauldrons).
- **Chest:** one bold copper HEXAGON badge (NOT an eagle/aquila).
- **Weapon:** original sleek bullpup carbine with a teal energy cell (NOT a boxy bolter).
- **Render:** clean semi-realistic miniature render (the `00_style_reference` look) — not flat
  comic, not heavy cel-shade.

## IP-safety — the key lesson (do NOT lose this)
The models are CC-BY-SA 4.0 and must avoid Games Workshop / OPR IP.
1. **NEVER list GW terms in the image prompt — not even to "avoid" them.** Text-to-image models
   can't negate and the mere mention of "aquila / Space Marine / purity seals" *anchors* them
   (that produced the aquila + Primaris helmet in `iter_v1/v2`). Describe the original design
   **positively and very specifically** instead. The `explicitly_avoid` list in the YAML is
   internal documentation only and is NOT fed to the image model.
2. Keep the genre (heavy armoured sci-fi soldier — a free trope) but change palette + silhouette
   so it is clearly original, not a Space Marine.

## Iterations (what went wrong → learning)
- `iter_v1_STILL_SPACE_MARINE` — IP terms removed from prompt but Ultramarine palette kept → still a Space Marine.
- `iter_v2_aquila_primaris_helmet` — the avoid-list in the prompt anchored an aquila + Primaris helmet.
- `iter_v3_too_comic` — positive-only fixed the IP, but render was too flat/comic.
- `iter_v4_too_celshade` — cel-shaded game-engine, closer but a bit too toon.
- `01_hero_FINAL` (v5) — positive-only design + `00_style_reference` as style ref → approved.

The same positive-only + style-reference approach applies to every other faction (keep each
faction's own palette/theme).
