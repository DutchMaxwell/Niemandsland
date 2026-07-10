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
uniform sampler2D detail_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// All parameters below are pushed from table.gd and are SHARED across every base (one material
// per table/biome state), so a biome or table-size change updates every model's base at once.
uniform vec2 uv_scale = vec2(1.0);            // table_size_feet / reference (centre-crop), = Table._biome_uv_scale()
uniform vec2 table_center_xz = vec2(0.0);     // table origin in world metres
uniform vec2 inv_table_size = vec2(1.0);      // 1 / (table size in metres)
uniform vec2 uv_axis_sign = vec2(1.0, 1.0);   // matches PlaneMesh UV winding
uniform float detail_tiling = 28.0;
uniform float detail_albedo_strength : hint_range(0.0, 0.5) = 0.12;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform bool has_texture = false;             // false until a biome/fallback texture is bound
uniform vec3 fallback_color = vec3(0.2, 0.35, 0.2);

// Subtle AO-style darkening toward the rim so the model stays readable against the camouflage.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.28;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.55;

varying vec2 world_xz;
varying float rim_t;   // 0 = base centre, 1 = base rim (baked into UV.x at mesh-build time)

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	rim_t = UV.x;
}

void fragment() {
	// Reconstruct the table plane UV (0..1) from world XZ, exactly as the PlaneMesh would.
	vec2 plane_uv = 0.5 + (world_xz - table_center_xz) * inv_table_size * uv_axis_sign;
	// Same centre-crop as table_ground.gdshader (clamp keeps samples inside the battlemap).
	vec2 macro_uv = clamp(0.5 + (plane_uv - 0.5) * uv_scale, vec2(0.0), vec2(1.0));
	vec3 base_col = has_texture ? texture(albedo_tex, macro_uv).rgb : fallback_color;

	// Same micro colour variation as the table so the window blends seamlessly.
	if (has_texture) {
		float h = texture(detail_height, plane_uv * detail_tiling).r;
		base_col *= 1.0 + (h - 0.5) * 2.0 * detail_albedo_strength;
	}

	// Subtle readability vignette toward the rim.
	float v = smoothstep(vignette_start, 1.0, clamp(rim_t, 0.0, 1.0));
	base_col *= 1.0 - v * vignette_strength;

	ALBEDO = base_col;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
