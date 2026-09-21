shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/visual/reference_ground.gdshaderinc"
uniform bool clip_base = false;
uniform bool surface_relief = false;
float relief(vec2 p) {
	float amp = desert_mode ? 0.45 : 1.0;
	return ((surface_noise(p*2.6)-0.5)*0.008+(surface_noise(p*7.5)-0.5)*0.003)*amp;
}
// The drift mound is vertex-only: the fragment needs relief four times for the normal,
// and the drift loop there cost ~9 ms. The mound still reads from its silhouette and
// the brighter, noised sand in the fragment.
float full_relief(vec2 p) {
	return relief(p) + drift_height(p);
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
 float wet = (desert_mode || tundra_mode || volcanic_mode) ? 0.0 : clamp(0.10+path*0.62,0.0,1.0);
	ALBEDO = ground_sample(ground_xz)*mix(1.0,0.80,wet);
	ROUGHNESS = mix(0.80,0.24,wet);
	SPECULAR = mix(0.28,0.68,wet);
	METALLIC = 0.0;
	if (tundra_mode) {
		float ice = tundra_ice(ground_xz);
		ROUGHNESS = mix(0.94,0.20,ice);
		SPECULAR = mix(0.24,0.65,ice);
	}
	if (volcanic_mode) {
		ROUGHNESS = mix(0.98,0.78,volcanic_crust(ground_xz));
		SPECULAR = 0.18;
	}
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
	float slope_x=surface_relief ? (relief(ground_xz)-relief(ground_xz+vec2(step_size,0.0)))/step_size : 0.0;
	float slope_z=surface_relief ? (relief(ground_xz)-relief(ground_xz+vec2(0.0,step_size)))/step_size : 0.0;
	vec3 surface_normal=normalize(vec3((h-hx)*14.0+slope_x,1.0,(h-hz)*14.0+slope_z));
	NORMAL=normalize((VIEW_MATRIX*vec4(surface_normal,0.0)).xyz);
}
