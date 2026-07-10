shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Terrain-projected miniature base top: reads as a seamless window onto the battlefield
// ground directly beneath the model, like a hobbyist basing a mini to match the table.
//
// It MIRRORS table_ground.gdshader: the table plane samples its biome battlemap through the
// mesh's built-in UV; here there is no such UV, so the base RECONSTRUCTS the same plane UV
// from its WORLD XZ position (uv_axis_sign matches the PlaneMesh winding — verified in
// table_ground_projection_test.gd). The projection is therefore live (moves with the model)
// and produces the identical centre-crop + micro-detail the table shows at that spot.
//
// Accepted v1 limitation: only the biome ground texture is sampled — decals/stains and 3D
// terrain overlays are not part of the window.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Same procedural micro-relief as the table: sampled as a tangent-space normal so the base
// answers the sun IDENTICALLY to the board (identical texture => identical brightness), and as a
// height field for the same albedo micro-variation. Without the normal the flat base read darker
// than the normal-mapped board it sits on — the actual brightness mismatch this shader fixes.
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// All parameters below are pushed from table.gd and are SHARED across every base (one material
// per table/biome state), so a biome or table-size change updates every model's base at once.
uniform vec2 uv_scale = vec2(1.0);            // table_size_feet / reference (centre-crop), = Table._biome_uv_scale()
uniform vec2 table_center_xz = vec2(0.0);     // table origin in world metres
uniform vec2 inv_table_size = vec2(1.0);      // 1 / (table size in metres)
uniform vec2 uv_axis_sign = vec2(1.0, 1.0);   // matches PlaneMesh UV winding
uniform float detail_tiling = 28.0;
uniform float detail_normal_strength : hint_range(0.0, 1.0) = 0.35;  // = table_ground.gdshader
uniform float detail_albedo_strength : hint_range(0.0, 0.5) = 0.12;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform bool has_texture = false;             // false until a biome/fallback texture is bound
uniform vec3 fallback_color = vec3(0.2, 0.35, 0.2);

// Rim shading is a CONTACT-SHADOW HINT only, not a readability vignette: it is zero across the
// centre (which must read identical to the board) and only a thin outer band is touched.
// vignette_strength = max darkening at the very rim; vignette_start = the rim_t where shading
// begins (so 1.0 - vignette_start is the rim-shade band width). Tuned from Table.BASE_TOP_VIGNETTE_*.
// SHIPPED DEFAULT IS 0.0 — the black beveled rim alone grounds the base; the uniform is retained
// only for later taste-tuning (see Table.BASE_TOP_VIGNETTE_STRENGTH).
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.80;

varying vec2 world_xz;
// Centred shape coordinate (base centre = 0, shape boundary = length 1). Baked into UV at
// mesh-build time. The top is a flat QUAD (like a PlaneMesh, which the sun answers identically);
// fragments outside the base outline are discarded so the quad reads as the base's round/oval/
// square shape. A single-apex triangle FAN here rendered markedly darker under this shader in
// Godot 4.6 (measured); a quad + discard is the shape without that artefact — see base_decor.gd.
varying vec2 shape_uv;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	shape_uv = UV;
}

void fragment() {
	// Clip the bounding quad to the base outline (round/oval => length 1; square is pre-scaled so
	// it never exceeds 1). The rim hides this edge, so a hard discard boundary is invisible.
	float rim_t = length(shape_uv);
	if (rim_t > 1.0) {
		discard;
	}
	rim_t = clamp(rim_t, 0.0, 1.0);
	// Reconstruct the table plane UV (0..1) from world XZ, exactly as the PlaneMesh would.
	vec2 plane_uv = 0.5 + (world_xz - table_center_xz) * inv_table_size * uv_axis_sign;
	// Same centre-crop as table_ground.gdshader (clamp keeps samples inside the battlemap).
	vec2 macro_uv = clamp(0.5 + (plane_uv - 0.5) * uv_scale, vec2(0.0), vec2(1.0));
	vec3 base_col = has_texture ? texture(albedo_tex, macro_uv).rgb : fallback_color;

	// Same micro colour variation as the table so the window blends seamlessly. Uses the SAME
	// detail UV (plane_uv * detail_tiling == the table's UV * detail_tiling at this world point).
	vec2 duv = plane_uv * detail_tiling;
	if (has_texture) {
		float h = texture(detail_height, duv).r;
		base_col *= 1.0 + (h - 0.5) * 2.0 * detail_albedo_strength;
	}

	// Contact-shadow hint toward the rim only (zero across the centre).
	float v = smoothstep(vignette_start, 1.0, clamp(rim_t, 0.0, 1.0));
	base_col *= 1.0 - v * vignette_strength;

	ALBEDO = base_col;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;

	// Match the table's tangent-space detail relief so the base catches the same sun glints.
	// The fan mesh carries a world-aligned tangent (+X) — see BaseDecor._top_mesh.
	vec3 n = texture(detail_normal, duv).xyz;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = detail_normal_strength;
}
