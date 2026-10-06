shader_type sky;
render_mode use_debanding;
// Static valley radiance, derived from the approved gfx/backdrop-options hero extension.
uniform int world_mood = 0;
uniform vec3 biome_tint = vec3(1.0);
float hash13(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise3d(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 valley_sky(vec3 dir) {
 float altitude = max(dir.y, 0.0);
 vec3 sun_dir = normalize(vec3(-0.55, 0.37, -0.78));
 float toward_sun = max(dot(dir, sun_dir), 0.0);
 vec3 horizon = mix(vec3(0.38,0.48,0.61), vec3(1.35,0.61,0.23), pow(toward_sun,4.0));
 vec3 zenith = vec3(0.10,0.23,0.42);
 vec3 result = mix(horizon, zenith, smoothstep(0.0,0.85,altitude));
 vec3 cloud_p = vec3(dir.xz / max(dir.y + 0.32, 0.12) * 1.4, 2.1);
 float clouds = smoothstep(0.48,0.72,fbm(cloud_p));
 float cloud_band = smoothstep(0.02,0.20,dir.y) * (1.0-smoothstep(0.65,0.95,dir.y));
 vec3 cloud_col = mix(vec3(0.29,0.36,0.49), vec3(1.6,0.95,0.55), pow(toward_sun,6.0));
 result = mix(result, cloud_col, clouds * cloud_band * 0.68);
 result += vec3(3.0,1.8,0.85) * pow(toward_sun,128.0);
 result += vec3(12.0,9.0,5.0) * smoothstep(0.99965,0.99985,toward_sun);
 result = mix(vec3(0.12,0.14,0.13), result, smoothstep(-0.22,0.02,dir.y));
 if (world_mood == 1) { result = mix(result, vec3(0.34,0.55,0.80), 0.45); }
 if (world_mood == 2 || world_mood == 4) {
  float cloud = smoothstep(0.2,0.65,fbm(cloud_p));
  result = mix(vec3(0.14,0.18,0.24),vec3(0.40,0.44,0.48),cloud) * (world_mood == 4 ? 0.65 : 1.0);
 }
 if (world_mood == 3) { result *= vec3(0.015,0.035,0.085); }
 return result * biome_tint;
}

void sky() { COLOR = valley_sky(EYEDIR); }
