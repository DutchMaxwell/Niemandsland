# Grassland surface

`grassland_surface.webp` is original Niemandsland art, generated with the built-in
OpenAI image generation tool on 2026-09-16 and released under CC-BY-SA 4.0.
No third-party reference image was used. The generated 1254x1254 PNG was resized
to 1024x1024 and encoded as WebP at quality 90 for the game. The committed import
settings enable mipmaps and high-quality VRAM compression.

This is an albedo source, not a scanned PBR material set. Fine relief uses the
existing procedural detail normal; dry/damp roughness is authored in the shared
grassland shader. The board and miniature bases sample the same material.

Final generation prompt:

```text
Use case: photorealistic-natural. Asset type: seamless tileable game ground albedo texture, 2048 by 2048 square. Create a production-quality physically plausible diffuse base-color texture for temperate European battlefield grassland, orthographic straight overhead, edge-to-edge material, no perspective. Ground is a calm, dark desaturated earthy olive meadow: roughly 55 percent very short dense moss and fine worn grass in irregular connected patches, 40 percent compacted brown-grey fine earth with subtle granular structure, 5 percent tiny scattered muted shale grit. Broad soft organic transitions between the earth and moss, varied patch sizes, subtle dry umber accents, natural restrained colors. Think high-end scanned terrain material for a realistic miniature diorama. The fine material remains rich and tactile but its overall contrast is low and cohesive, so small miniatures remain legible on top. Lighting: perfectly even diffuse neutral albedo, no baked directional lighting, no shadows, no ambient occlusion, no highlights, no vignette. Keep all edges continuous and genuinely tileable; no obvious center composition or large repeating motif. Absolutely no tall grass, no large pale leaves, no twigs, no big white rocks, no flowers, no puddles, no cracks, no roads, no footprints, no props, no buildings, no grid, no labels, no text, no watermark. Output is the texture alone, not a material sphere or presentation sheet.
```
