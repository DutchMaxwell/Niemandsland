# Grassland reference visual assets

The reference textures and the generated tree/rock models referenced by
`hero/*.json` and `forest/*.json` are original Niemandsland visual assets, released under
**CC BY-SA 4.0**: https://creativecommons.org/licenses/by-sa/4.0/

Attribution: Niemandsland Contributors.

- `meadow.webp`, `earth.webp`, `woodland.webp`: Google Gemini 2.5 Flash Image
  (NanoBanana), 2026-09-16. Original text descriptions; no reference images.
- `hero/field.webp`, `hero/bark.webp`, `hero/leaf.webp`, `hero/tuft.webp`:
  NanoBanana, 2026-09-17. Original text descriptions; no reference images.
- `hero/rough-earth.webp`, `hero/forest-duff.webp`:
  NanoBanana, 2026-09-17. Original text descriptions; no reference images.
- Generated 3D terrain props: original NanoBanana image sources reconstructed
  with TRELLIS.2 through the existing Model Forge pipeline. The oak image uses
  the project's own previously generated battlefield concept as a style
  reference. No third-party artwork, stock images or game assets were supplied.

Exact prompts, source/output hashes and processing records are in
`provenance.json` and `hero/provenance.json`. Model manifests identify immutable
CDN assets by SHA-256; the binary models are not bundled in this repository.

The license applies to the visual assets to the extent applicable rights
exist. It does not assert exclusive rights in purely generated output or
clear unrelated third-party rights. Tool, service and dependency licenses
remain separate from this project asset license; see `THIRD_PARTY.md`.

Procedural geometry and shaders are original project code under MIT.
Existing miniature and terrain assets retain their existing notices.

## Tundra/desert forest sources (2026-09-21)

The forest image sources and reconstructed models are original text-only
NanoBanana / TRELLIS.2 outputs under the same CC BY-SA 4.0 asset terms and
Niemandsland Contributors attribution. No reference artwork was supplied.
The individual manifests in `forest/` contain source prompts, image hashes,
conditioning records, seeds and export parameters. Runtime crown variation,
wind, snow shading and decorative placement are original MIT-licensed code.
