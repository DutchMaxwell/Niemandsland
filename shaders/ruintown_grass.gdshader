// ruintown_grass.gdshader - the blade clumps of the ruin town (BoardgenTownGrass): one MultiMesh clump of 5 blades per point of the green map.
// Mesh units: inches across, 1.0 up (the instance scales x / z by an inch and y by the blade height). UV.y 0 root -> 1 tip; TANGENT = the blade's
// across direction and UV2.x = the signed half width there (the far-camera widening); INSTANCE_CUSTOM = (hash, height / 0.38, dry flag, 0).
// Colour: the ONE green of the ground under it (ruintown_green.gdshaderinc), so blades and soil never disagree; lit like the kit's plants
// (light() of ruintown_dress_veg.gdshaderinc) plus the ground's moon fill as emission (the albedo^2.2 x 2.4 of grit_fill), so a blade reads
// as bright as the soil it stands on. Two-sided, no shadow pass (the instances cast none).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/tiefwerk_noise.gdshaderinc"
#include "res://shaders/ruintown_green.gdshaderinc"
#include "res://shaders/ruintown_dress_veg.gdshaderinc"

uniform vec3 board_origin = vec3(0.0);   // the board centre (world): the green is looked up in board inches like the board shader's
uniform float wind = 1.0;   // 0 = still (pinned stills, reduce motion)

const float IN_M = 0.0254;
const vec3 STRAW = vec3(1.3, 1.05, 0.62);   // the dry tint of the kit's plants
const float GRASS_FILL = 2.4;   // = GRIT_FILL of the ground

varying vec2 xz_in;
varying float dry_flag;

void vertex() {
	thin = 1.0;
	dry_flag = INSTANCE_CUSTOM.z;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	xz_in = (world - board_origin).xz / IN_M;
	vec2 drift = xz_in * 0.15 - vec2(TIME * 0.6 * 0.15);   // 0.15 per in, scrolling 0.6 in/s
	vec2 sway = vec2(vnoise(drift), vnoise(drift + 17.3)) * 2.0 - 1.0;
	VERTEX.xz += sway * UV.y * UV.y * 0.03 * wind;   // local x / z are inches
	float d = length(world - CAMERA_POSITION_WORLD);
	VERTEX += TANGENT * UV2.x * 0.6 * max(d - 0.8, 0.0);   // wider beyond 0.8 m: no sub-pixel shimmer at the play camera
}

void fragment() {
	vec3 alb = green_tone(xz_in, 0.0) * mix(0.55, 1.15, UV.y);
	alb = mix(alb, dot(alb, vec3(0.3, 0.6, 0.1)) * STRAW * 1.15, 0.92 * step(0.5, dry_flag));
	ALBEDO = alb;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
	AO = mix(0.35, 1.0, UV.y);
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	EMISSION = pow(alb, vec3(2.2)) * GRASS_FILL * AO;
}
