uniform sampler2D meadow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D woodland_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int forest_count = 0;
uniform vec4 forest_regions[16];
uniform float forest_angles[16];
uniform int wall_count=0;
uniform vec4 wall_regions[64];
uniform bool desert_mode = false;
uniform bool tundra_mode = false;
uniform bool volcanic_mode = false;
uniform bool jungle_mode = false;
uniform bool urban_mode = false;
uniform bool urban_contact_enabled = true;
uniform sampler2D urban_contact_mask : filter_linear_mipmap, repeat_disable;
uniform vec2 urban_board_size = vec2(1.8288,1.2192);
uniform float wind_time = 0.0;
uniform int drift_count = 0;
uniform vec4 drift_points[32];
uniform bool woody_ground_enabled = false;
uniform sampler2D woody_ground_mask : filter_linear_mipmap, repeat_disable;
uniform vec2 woody_board_size = vec2(1.8288,1.2192);
#include "res://shaders/visual/reference_volcanic_surface.gdshaderinc"

float woody_contact(vec2 p) {
	return woody_ground_enabled ? texture(woody_ground_mask,p/woody_board_size+vec2(0.5)).r : 0.0;
}

// Integer hashing keeps neighboring cells identical across GPU optimizations.
float surface_hash(vec2 p) {
 uvec2 q = uvec2(ivec2(p));
 uint h = (q.x * 16777619u) ^ (q.y * 1103515245u);
 h = ((h >> 16u) ^ h) * 16777619u;
 h = (h >> 13u) ^ h;
 return float(h & 65535u) / 65535.0;
}
float surface_noise(vec2 p) {
 vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
 return mix(mix(surface_hash(i), surface_hash(i + vec2(1,0)), f.x),
 mix(surface_hash(i + vec2(0,1)), surface_hash(i + vec2(1,1)), f.x), f.y);
}
vec2 mirrored_uv(vec2 uv) { return 1.0 - abs(mod(uv, 2.0) - 1.0); }
vec3 tiled_surface(sampler2D tex, vec2 uv) {
#ifdef TABLE_TIER
 // Game-table tier: one fetch; the reference blends in 15 % of a rotated second fetch against tiling.
 return texture(tex,mirrored_uv(uv)).rgb;
#else
 vec2 rotated = mat2(vec2(0.8,0.6),vec2(-0.6,0.8)) * uv * 0.71 + vec2(0.37,0.61);
 return mix(texture(tex,mirrored_uv(uv)).rgb,texture(tex,mirrored_uv(rotated)).rgb,0.15);
#endif
}
// Wind-piled sand: a soft mound at the foot of every ruin wall and placed prop, so the
// props sit in the terrain instead of on top of it. Walls use the wall segments; placed
// props come in as drift_points (xz + radius).
float drift_mask(vec2 p) {
	float m = 0.0;
	for (int i = 0; i < drift_count; i++) {
		float d = length(p - drift_points[i].xy) / max(drift_points[i].z, 0.0001);
		m = max(m, 1.0 - smoothstep(0.0,1.0,d));
	}
	return m;
}
float drift_height(vec2 p) {
	float h = 0.0;
	for (int i = 0; i < drift_count; i++) {
		float r = max(drift_points[i].z, 0.0001);
		float d = length(p - drift_points[i].xy) / r;
		float m = 1.0 - smoothstep(0.0,1.0,d);
		h += m * m * r * 0.20;
	}
	for (int i = 0; i < wall_count; i++) {
		vec2 a = wall_regions[i].xy, b = wall_regions[i].zw;
		vec2 e = b - a;
		float t = clamp(dot(p - a, e) / max(dot(e, e), 0.000001), 0.0, 1.0);
		float d = length(p - (a + t * e));
		float m = 1.0 - smoothstep(0.0, 0.030, d);
		h += m * m * 0.007;
	}
	return h;
}
// Wind-rippled sand with cracked-earth pans and scree patches. Reuses the same three
// samplers as the grassland (meadow=sand, earth=cracked, woodland=scree).
vec3 desert_sample(vec2 p) {
	vec3 sand = tiled_surface(meadow_tex, p * 5.0);
	vec3 crack = tiled_surface(earth_tex, p * 6.0);
	vec3 scree = tiled_surface(woodland_tex, p * 7.0);
	float warp = surface_noise(p * 3.1) * 0.35;
	float ripple = sin((p.y + warp) * 260.0) * 0.5 + 0.5;
	ripple = pow(ripple, 1.6);
	float crack_mask = smoothstep(0.58, 0.80, surface_noise(p * 3.4));
	float scree_mask = smoothstep(0.76, 0.94, surface_noise(p * 7.0));
	vec3 col = mix(sand, crack, crack_mask * 0.80);
	col = mix(col, scree, scree_mask * 0.50);
	col *= mix(0.93, 1.07, ripple);
	// The surface stays stationary; separate low ribbons carry airborne sand.
	float broad = surface_noise(p * 7.0);
	col = mix(col, col * vec3(1.05, 1.00, 0.90), broad * 0.5);
	float foot = 0.0;
	for (int i = 0; i < wall_count; i++) {
		vec2 a = wall_regions[i].xy, b = wall_regions[i].zw;
		vec2 e = b - a;
		float t = clamp(dot(p - a, e) / max(dot(e, e), 0.000001), 0.0, 1.0);
		float d = length(p - (a + t * e));
		foot = max(foot, 1.0 - smoothstep(0.004, 0.024, d));
	}
	col *= mix(vec3(1.0), vec3(0.82, 0.78, 0.68), foot * 0.6);
	// Clean, brighter sand where the wind piles it up against a wall or a prop; broken
	// with fine noise so the mound does not read as a smooth white dome.
	col = mix(col, sand * vec3(1.12,1.05,0.93), drift_mask(p) * (0.45 + 0.35 * surface_noise(p * 46.0)));
	// Grit and dry organic material gather at the woody vegetation's feet.
	col = mix(col,scree*vec3(0.86,0.82,0.73),woody_contact(p)*0.62);
	// Warm the pale sand toward a real desert tan; the raw texture is almost white
	// and the bright sun bleached it further.
	return col * vec3(0.92, 0.78, 0.56);
}
// Broad wind-scoured ground connects exposed soil; finer noise breaks the snow edge.
// Keep coverage identical to ReferenceMaterials.tundra_snow for vegetation placement.
float tundra_snow(vec2 p) {
	float cover = surface_noise(p * 5.2) * 0.60 + surface_noise(p * 21.0) * 0.25 + surface_noise(p * 67.0) * 0.15;
	return smoothstep(0.40, 0.53, cover);
}
float tundra_ice(vec2 p) {
	return (1.0 - tundra_snow(p)) * smoothstep(0.54,0.74,surface_noise(p * 8.0 + vec2(19.0,7.0)));
}
vec3 tundra_sample(vec2 p) {
	vec3 snow = tiled_surface(meadow_tex,p * 5.0);
	vec3 soil = tiled_surface(earth_tex,p * 5.0) * vec3(0.72,0.73,0.77);
	vec3 ice = tiled_surface(woodland_tex,p * 6.0) * vec3(0.50,0.62,0.70);
	vec3 exposed = mix(soil,ice,smoothstep(0.54,0.74,surface_noise(p * 8.0 + vec2(19.0,7.0))));
	float crust = surface_noise(p * 140.0);
	snow *= mix(0.87,1.0,crust) * vec3(0.86,0.91,0.96);
	// Sheltered soil and needle duff interrupt the snow directly below each crown.
	float contact = woody_contact(p);
	return mix(exposed*mix(1.0,0.84,contact),snow,tundra_snow(p)*(1.0-contact*0.85));
}
// Broad cooled flows interrupted by softer wind-settled ash, never new lava hazards.
float volcanic_crust(vec2 p) {
	vec2 warp = vec2(surface_noise(p*3.7),surface_noise(p*3.7+17.0))-vec2(0.5);
	return smoothstep(0.37,0.68,surface_noise(p*4.5+warp*1.4));
}
vec3 volcanic_sample(vec2 p) {
	vec3 ash = volcanic_surface_sample(meadow_tex,p*5.0)*vec3(0.92,0.94,0.98);
	vec3 lava = volcanic_surface_sample(earth_tex,p*6.0)*vec3(0.87,0.90,0.96);
	vec3 chips = volcanic_surface_sample(woodland_tex,p*7.5);
	float crust = volcanic_crust(p);
	vec3 base = mix(ash,lava,crust*0.90);
	float rubble = smoothstep(0.57,0.79,surface_noise(p*13.0));
	base = mix(base,chips,rubble*0.45+woody_contact(p)*0.25);
	return base*mix(1.0,0.82,woody_contact(p));
}
float jungle_growth(vec2 p) {
	return smoothstep(0.28,0.60,surface_noise(p*5.3)*0.65+surface_noise(p*18.0)*0.35);
}
vec3 jungle_sample(vec2 p) {
	// Reuse the continuous non-reflected sampler introduced for volcanic surfaces.
	vec3 soil = volcanic_surface_sample(earth_tex,p*5.0)*vec3(0.62,0.67,0.60);
	vec3 moss = volcanic_surface_sample(meadow_tex,p*5.0)*vec3(0.80,1.06,0.70);
	vec3 litter = volcanic_surface_sample(woodland_tex,p*6.0)*vec3(0.65,0.68,0.58);
	float growth = jungle_growth(p);
	float shelter = max(woody_contact(p),smoothstep(0.46,0.75,surface_noise(p*8.0+11.0))*0.65);
	vec3 col = mix(soil,moss,0.16+growth*0.82);
	return mix(col,litter,shelter*0.68)*mix(1.0,0.87,woody_contact(p));
}
// Broken pavement islands interrupt quieter asphalt. Fine dust connects the actual
// wall feet to low rubble; this mask describes decoration, never a new hazard.
float urban_contact(vec2 p) {
	return urban_contact_enabled ? texture(urban_contact_mask,p/urban_board_size+vec2(0.5)).r : 0.0;
}
float urban_pavement(vec2 p) {
	float islands = surface_noise(p*4.0)*0.52+surface_noise(p*17.0)*0.27+surface_noise(p*91.0)*0.21;
	return smoothstep(0.43,0.55,islands);
}
vec3 urban_sample(vec2 p) {
	vec3 asphalt = volcanic_surface_sample(meadow_tex,p*6.0)*vec3(0.68,0.72,0.77);
	vec3 concrete = volcanic_surface_sample(earth_tex,p*7.0)*vec3(0.52,0.52,0.50);
	vec3 dust = volcanic_surface_sample(woodland_tex,p*9.0)*vec3(0.68,0.64,0.58);
	concrete *= mix(0.67,1.03,surface_noise(p*23.0));
	vec3 col = mix(asphalt,concrete,urban_pavement(p));
	vec4 marks = urban_contact_enabled ? texture(urban_contact_mask,p/urban_board_size+vec2(0.5)) : vec4(0.0);
	float powder = marks.r*(0.46+0.48*surface_noise(p*66.0));
	col = mix(col,dust,powder);
	col *= 1.0-marks.g*(0.36+0.26*surface_noise(p*71.0));
	col = mix(col,col*vec3(1.03,0.65,0.43),marks.b*0.65);
	return col*mix(1.0,0.68,marks.a);
}
vec3 ground_sample(vec2 p) {
	if (urban_mode) { return urban_sample(p); }
	if (jungle_mode) { return jungle_sample(p); }
	if (volcanic_mode) { return volcanic_sample(p); }
	if (tundra_mode) { return tundra_sample(p); }
	if (desert_mode) { return desert_sample(p); }
	vec2 uv_earth = p * 2.2;
 vec2 uv_grass = p * 5.0;
 float broad = surface_noise(p * 10.0) * 0.65 + surface_noise(p * 43.0) * 0.35;
 float meadow = smoothstep(0.24, 0.56, broad);
 float path_center = -0.60+sin(p.y*8.0+0.4)*0.085;
 float path_width = 0.020+surface_noise(p*38.0)*0.020;
 float path = (1.0-smoothstep(path_width,path_width+0.030,abs(p.x-path_center)))*smoothstep(0.02,0.15,p.y);
 vec3 earth = tiled_surface(earth_tex, uv_earth);
 vec3 grass = tiled_surface(meadow_tex, uv_grass);
 vec3 col = mix(grass * vec3(0.60,0.60,0.40), earth * vec3(0.80,0.79,0.72), max(path, clamp((1.0 - meadow) * 0.42, 0.0, 0.42)));
 col *= mix(0.77,1.12,surface_noise(p*82.0));
 float patchy = surface_noise(p*6.5);
 col = mix(col, col*vec3(1.10,1.04,0.86), patchy*0.45*(1.0-path));
 // Smooth noise instead of per-cell hashing: the integer hash made every cell a
 // visible flat square, which read as little tiles on the field.
 float grit = surface_noise(p*95.0);
 col *= mix(0.90,1.10,grit*grit);
 float pebble = surface_noise(p*52.0+vec2(37.0,11.0));
 col = mix(col, col*vec3(1.22,1.20,1.14), smoothstep(0.78,0.95,pebble));
 float dark = surface_noise(p*68.0+vec2(5.0,91.0));
 col = mix(col, col*vec3(0.66,0.62,0.53), smoothstep(0.80,0.96,dark));
 float woodland = 0.0;
 for (int i = 0; i < forest_count; i++) {
  vec2 d = p - forest_regions[i].xy;
  float c = cos(forest_angles[i]), s = sin(forest_angles[i]);
  d = mat2(vec2(c,-s),vec2(s,c)) * d;
  float distance_to_edge = length(d / forest_regions[i].zw);
  woodland = max(woodland, 1.0 - smoothstep(0.78,1.18 + 0.10 * broad,distance_to_edge));
 }
 col = mix(col, tiled_surface(woodland_tex, p*6.0) * vec3(0.64,0.64,0.49), woodland * 0.85);
 col = mix(col,earth*vec3(0.87,0.82,0.71),path*0.72);
 float foot=0.0;
 for(int i=0;i<wall_count;i++){
  vec2 a=wall_regions[i].xy,b=wall_regions[i].zw;
  vec2 e=b-a;
  float t=clamp(dot(p-a,e)/max(dot(e,e),0.000001),0.0,1.0);
  float d=length(p-(a+t*e));
  foot=max(foot,1.0-smoothstep(0.005,0.025+0.008*broad,d));
 }
 col*=mix(vec3(1.0),vec3(0.56,0.58,0.45),foot*0.65);
 return col * 0.94;
}
