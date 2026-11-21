// --- Authored surfaces (AAA step 10): four tiling PBR sets from R2 (TiefwerkLibrary), 1024 px per 3 in, under the procedural look.
// The colour keeps its procedural structure (frames, seams, paint, grime, puddles) and gains the set's own variation as a mean-preserving
// ratio; the set's normal bends the shading normal, its roughness and occlusion vary round the procedural values. Every plate gets its own
// offset (and a mirror on walls, a quarter turn on tops) so the tile never reads as a tile. Uses the display-value convention of the board
// shader (the textures are sampled raw, no sRGB hint). Sets: 0 painted steel (walls), 1 rusted plate (tier-1 deck), 2 concrete (ground,
// street, sump), 3 roof slab (tiers 2 and 3). Nothing here runs until t1_on is set (all twelve textures cached): the fallback is the
// pure procedural look.

uniform float t1_on = 0.0;
uniform sampler2D t1_alb_0 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_alb_1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_alb_2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_alb_3 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_nrm_0 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_nrm_1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_nrm_2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_nrm_3 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_orm_0 : filter_linear_mipmap_anisotropic, repeat_enable;   // r = occlusion, g = roughness
uniform sampler2D t1_orm_1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_orm_2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t1_orm_3 : filter_linear_mipmap_anisotropic, repeat_enable;

const float T1_TILE = 3.0;                           // inches of board per tile (tile_in of the manifest)
const vec4 T1_COLOUR = vec4(0.9, 0.9, 0.85, 0.8);    // how much of each set's colour variation reaches the surface
const float T1_BUMP = 0.55;                          // how far the set's normal bends the shading normal

// One set at the plate's own texture coordinates: the colour ratio to the set's mean, the height slope (u, v) and occlusion / roughness
// relative to the set's mean. The mean is the smallest mip level. Explicit gradients (of the continuous board uv) keep the mip level right
// across the jumps between plates.
void t1_sample(sampler2D ta, sampler2D tn, sampler2D to, vec2 uvt, vec2 dx, vec2 dy, out vec3 ratio, out vec2 slope, out vec2 ao_rough) {
	ratio = clamp(textureGrad(ta, uvt, dx, dy).rgb / max(textureLod(ta, vec2(0.5), 12.0).rgb, vec3(0.03)), 0.2, 2.6);
	vec2 nm = textureGrad(tn, uvt, dx, dy).rg * 2.0 - 1.0;   // BC5 keeps only red and green: rebuild the rest
	slope = vec2(-nm.x, nm.y) / max(sqrt(max(1.0 - dot(nm, nm), 0.0)), 0.3);
	vec3 o = textureGrad(to, uvt, dx, dy).rgb;
	vec3 o_mean = textureLod(to, vec2(0.5), 12.0).rgb;
	ao_rough = vec2(o.r / max(o_mean.r, 0.05), o.g - o_mean.g);
}

void t1_apply(int k, bool top, vec2 uv, vec2 duv_x, vec2 duv_y, vec3 n, inout vec3 alb, inout float rough, inout float ao, inout vec3 nrel) {
	int s = !top ? 0 : k == 3 ? 1 : (k == 4 || k == 6) ? 3 : 2;
	float plate = s == 3 ? cell_in : PLATE;   // the plates the procedural look already seams: 1.5 in on walls and floors, 3 in slabs on roofs
	vec3 hv = vec3(h21(floor(uv / plate) + 31.7), h21(floor(uv / plate) + 5.3), h21(floor(uv / plate) + 77.1));
	float q = top ? floor(hv.z * 4.0) * 1.5708 : 0.0;
	mat2 m = (!top && hv.z > 0.5) ? mat2(vec2(-1.0, 0.0), vec2(0.0, 1.0)) : mat2(vec2(cos(q), sin(q)), vec2(-sin(q), cos(q)));
	vec2 uvt = m * (uv / T1_TILE) + hv.xy;
	vec2 dx = m * duv_x / T1_TILE, dy = m * duv_y / T1_TILE;
	vec3 ratio;
	vec2 slope, ar;
	if (s == 0) {
		t1_sample(t1_alb_0, t1_nrm_0, t1_orm_0, uvt, dx, dy, ratio, slope, ar);
	} else if (s == 1) {
		t1_sample(t1_alb_1, t1_nrm_1, t1_orm_1, uvt, dx, dy, ratio, slope, ar);
	} else if (s == 2) {
		t1_sample(t1_alb_2, t1_nrm_2, t1_orm_2, uvt, dx, dy, ratio, slope, ar);
	} else {
		t1_sample(t1_alb_3, t1_nrm_3, t1_orm_3, uvt, dx, dy, ratio, slope, ar);
	}
	float dry = smoothstep(0.08, 0.3, rough);   // water lies level and glossy: the set shows through only where the surface is not wet
	alb *= mix(vec3(1.0), ratio, T1_COLOUR[s] * dry);
	ao *= mix(1.0, clamp(ar.x, 0.3, 1.2), 0.8);
	rough = clamp(rough + ar.y * 0.9 * dry, 0.04, 1.0);
	vec2 g = transpose(m) * slope;   // back from texture space to board uv
	vec3 tu = top ? vec3(1.0, 0.0, 0.0) : abs(n.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 tv = top ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	nrel = normalize(nrel - (tu * g.x + tv * g.y) * T1_BUMP * dry);
}
