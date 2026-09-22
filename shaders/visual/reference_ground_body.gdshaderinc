// Body of the reference ground shader, shared by reference_ground.gdshader (the accepted reference look,
// menu diorama + reference scene) and reference_ground_table.gdshader (the game-table tier, which defines
// TABLE_TIER). Without TABLE_TIER this is the reference shader unchanged.
#include "res://shaders/visual/reference_ground.gdshaderinc"
uniform bool clip_base = false;
uniform bool surface_relief = false;
float relief(vec2 p) {
	float amp = desert_mode ? 0.45 : 1.0;
	if (urban_mode) { amp = 0.15; }
	return ((surface_noise(p*2.6)-0.5)*0.008+(surface_noise(p*7.5)-0.5)*0.003)*amp;
}
// The drift mound is vertex-only: the fragment needs relief four times for the normal,
// and the drift loop there cost ~9 ms. The mound still reads from its silhouette and
// the brighter, noised sand in the fragment.
float full_relief(vec2 p) {
	return relief(p) + (urban_mode ? 0.0 : drift_height(p));
}
varying vec2 ground_xz;
void vertex() {
 ground_xz = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
 if(surface_relief) { VERTEX.y += full_relief(ground_xz); }
}
void fragment() {
 if (clip_base && length(UV) > 1.0) { discard; }
 // Wet-after-rain: damp soil is darker and glossier, strongest along the worn path.
 float pc = -0.60+sin(ground_xz.y*8.0+0.4)*0.085;
 float pw = 0.020+surface_noise(ground_xz*38.0)*0.020;
 float path = (1.0-smoothstep(pw,pw+0.030,abs(ground_xz.x-pc)))*smoothstep(0.02,0.15,ground_xz.y);
 float wet = (desert_mode || tundra_mode || volcanic_mode || urban_mode) ? 0.0 : clamp(0.10+path*0.62,0.0,1.0);
	ALBEDO = ground_sample(ground_xz)*mix(1.0,0.80,wet);
	ROUGHNESS = mix(0.80,0.24,wet);
	SPECULAR = mix(0.28,0.68,wet);
	METALLIC = 0.0;
	if (urban_mode) {
		float damp = urban_contact_enabled ? texture(urban_contact_mask,ground_xz/urban_board_size+vec2(0.5)).a : 0.0;
		ROUGHNESS = mix(mix(0.86,0.98,urban_contact(ground_xz)),0.30,damp);
		SPECULAR = mix(0.23,0.48,damp);
	}
	if (jungle_mode) {
		ALBEDO = jungle_sample(ground_xz)*0.92;
		float damp = (1.0-jungle_growth(ground_xz))*smoothstep(0.40,0.70,surface_noise(ground_xz*12.0));
		ROUGHNESS = mix(0.88,0.30,damp);
		SPECULAR = mix(0.25,0.54,damp);
	}
	if (tundra_mode) {
		float ice = tundra_ice(ground_xz);
		ROUGHNESS = mix(0.94,0.20,ice);
		SPECULAR = mix(0.24,0.65,ice);
	}
	if (volcanic_mode) {
		ROUGHNESS = mix(0.98,0.78,volcanic_crust(ground_xz));
		SPECULAR = 0.18;
	}
#ifdef TABLE_TIER
	// Game-table tier: ONE height value (the surface just computed) and screen-space derivatives give the
	// bump, and the derivatives of the displaced position give the relief. The reference below evaluates
	// the whole biome surface three more times for finite differences (up to 36 anisotropic texture fetches
	// per pixel on volcanic/jungle/urban) — the close-up frame-time cost on the game table. Same bump
	// strength: the reference normal is (h - h(x + 0.00014 m)) * 14, i.e. 0.00196 m per unit of height.
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dpdx = dFdx(world_pos);
	vec3 dpdy = dFdy(world_pos);
	vec3 geometric = normalize(cross(dpdy, dpdx));
	if (geometric.y < 0.0) { geometric = -geometric; }
	float height = dot(ALBEDO, vec3(0.3,0.5,0.2));
	vec3 r1 = cross(dpdy, geometric);
	vec3 r2 = cross(geometric, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	vec3 surface_normal = normalize(abs(det) * geometric - grad * 0.00196);
	NORMAL = normalize((VIEW_MATRIX * vec4(surface_normal, 0.0)).xyz);
#else
	float step_size=0.00014;
	vec2 uv=ground_xz*2.2;
	float h=dot(tiled_surface(earth_tex,uv),vec3(0.3,0.5,0.2));
	float hx=dot(tiled_surface(earth_tex,uv+vec2(step_size*2.2,0.0)),vec3(0.3,0.5,0.2));
	float hz=dot(tiled_surface(earth_tex,uv+vec2(0.0,step_size*2.2)),vec3(0.3,0.5,0.2));
	if (tundra_mode) {
		// Snow has its own fine crust, not the deep relief of the buried rocky soil.
		h = dot(tundra_sample(ground_xz),vec3(0.3,0.5,0.2));
		hx = dot(tundra_sample(ground_xz+vec2(step_size,0.0)),vec3(0.3,0.5,0.2));
		hz = dot(tundra_sample(ground_xz+vec2(0.0,step_size)),vec3(0.3,0.5,0.2));
	}
	if (volcanic_mode) {
		h = dot(volcanic_sample(ground_xz),vec3(0.3,0.5,0.2));
		hx = dot(volcanic_sample(ground_xz+vec2(step_size,0.0)),vec3(0.3,0.5,0.2));
		hz = dot(volcanic_sample(ground_xz+vec2(0.0,step_size)),vec3(0.3,0.5,0.2));
	}
	if (jungle_mode) {
		h = dot(jungle_sample(ground_xz),vec3(0.3,0.5,0.2));
		hx = dot(jungle_sample(ground_xz+vec2(step_size,0.0)),vec3(0.3,0.5,0.2));
		hz = dot(jungle_sample(ground_xz+vec2(0.0,step_size)),vec3(0.3,0.5,0.2));
	}
	float slope_x=surface_relief ? (relief(ground_xz)-relief(ground_xz+vec2(step_size,0.0)))/step_size : 0.0;
	if (urban_mode) {
		h = dot(urban_sample(ground_xz),vec3(0.3,0.5,0.2));
		hx = dot(urban_sample(ground_xz+vec2(step_size,0.0)),vec3(0.3,0.5,0.2));
		hz = dot(urban_sample(ground_xz+vec2(0.0,step_size)),vec3(0.3,0.5,0.2));
	}
	float slope_z=surface_relief ? (relief(ground_xz)-relief(ground_xz+vec2(0.0,step_size)))/step_size : 0.0;
	vec3 surface_normal=normalize(vec3((h-hx)*14.0+slope_x,1.0,(h-hz)*14.0+slope_z));
	NORMAL=normalize((VIEW_MATRIX*vec4(surface_normal,0.0)).xyz);
#endif
}
