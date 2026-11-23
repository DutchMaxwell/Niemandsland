// ruintown_dress.gdshader - the shared material of the ruin-town dressing kit (plan RUINTOWN_DRESSING step 7, v1).
// One ShaderMaterial per textured kit material (BoardgenDressMaterials). The merged dress mesh is in board space, so with
// world_uv the set is projected from the vertex position in inches along the normal's dominant axis and runs on across
// neighbouring modules; without it the mesh UV (authored in inches) is used. ONE continuous lookup per set, no per-fragment
// offsets (maintainer 22.11.: the two-lookup blend made coursed masonry look patched, not built). Macro and grime come in step 14.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_in = 3.0;   // inches of board one texture tile covers
uniform bool world_uv = false;
uniform vec4 tone : source_color = vec4(1.0);
uniform float normal_depth = 1.0;

varying vec2 dress_uv;

void vertex() {
	vec2 uv_in = UV;
	if (world_uv) {
		vec3 p = VERTEX / 0.0254;   // metres -> inches
		vec3 n = abs(NORMAL);
		if (n.y >= n.x && n.y >= n.z) {   // TANGENT = direction of +u, BINORMAL = direction of -v (Godot's convention)
			uv_in = p.xz; TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, -1.0);
		} else if (n.x >= n.z) {
			uv_in = vec2(p.z, -p.y); TANGENT = vec3(0.0, 0.0, 1.0); BINORMAL = vec3(0.0, 1.0, 0.0);
		} else {
			uv_in = vec2(p.x, -p.y); TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 1.0, 0.0);
		}
	}
	dress_uv = uv_in / max(tile_in, 0.01);
}

void fragment() {
	vec3 orm = texture(orm_tex, dress_uv).rgb;
	ALBEDO = texture(albedo_tex, dress_uv).rgb * tone.rgb * COLOR.rgb * 2.0;   // the kit stores tint x 0.5
	NORMAL_MAP = texture(normal_tex, dress_uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
}
