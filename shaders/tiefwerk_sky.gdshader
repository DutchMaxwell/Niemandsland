shader_type sky;
// Tiefwerk's vault: the undercity has no open sky. Near black overhead, a band of dim haze in the lowest 18 degrees, sparse warm and cold
// work lights far off in that band and the silhouettes of a few huge structures cutting the haze. No disc. The shader never reads the frame
// clock (a sky that does re-renders its radiance map every frame) and the lights and shapes stay out of the cube-map pass.
// Colours are linear (no source_color hint): the scene exposure and grade lift them to a dark slate and a dim blue-grey haze.
uniform vec3 overhead = vec3(0.006, 0.008, 0.012);
uniform vec3 haze = vec3(0.035, 0.045, 0.06);
uniform float light_strength = 1.0;
uniform float shape_strength = 1.0;
const float HAZE_DEG = 18.0;

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	float el = degrees(asin(clamp(EYEDIR.y, -1.0, 1.0)));
	float band = 1.0 - smoothstep(0.0, HAZE_DEG, abs(el));   // the haze is thickest at the horizon and gone 18 degrees up
	vec3 col = mix(overhead, haze, band);
	if (!AT_CUBEMAP_PASS) {
		// three or four structures far off: each one a range of azimuth with its own top elevation, darker than the haze it stands in
		float az = atan(EYEDIR.z, EYEDIR.x) / 6.28318 + 0.5;   // 0..1 round the horizon
		float cut = 0.0;
		for (int i = 0; i < 4; i++) {
			float lo = h31(vec3(float(i), 1.0, 7.0));
			float w = mix(0.03, 0.09, h31(vec3(float(i), 2.0, 7.0)));
			float top = mix(6.0, 16.0, h31(vec3(float(i), 3.0, 7.0)));
			float da = abs(fract(az - lo + 0.5) - 0.5);   // the distance round the circle from the shape's centre
			cut = max(cut, (1.0 - smoothstep(w, w + 0.004, da)) * (1.0 - smoothstep(top - 0.4, top, el)) * step(-2.0, el));
		}
		col = mix(col, overhead * 0.6, cut * shape_strength);
		// work lights: one jittered point per cell of a coarse grid the view sphere cuts through, only 2-14 degrees up, warm or cold by hash
		vec3 q = EYEDIR * 40.0;
		vec3 c = floor(q);
		float h = h31(c);
		vec3 p = c + 0.5 + (vec3(h31(c + 1.7), h31(c + 5.3), h31(c + 9.1)) - 0.5) * 0.6;
		float lamp = smoothstep(0.16, 0.03, length(q - p)) * step(0.80, h) * smoothstep(2.0, 3.0, el) * (1.0 - smoothstep(13.0, 14.0, el));
		vec3 tint = h31(c + 3.3) > 0.5 ? vec3(1.0, 0.62, 0.28) : vec3(0.55, 0.75, 1.0);
		col += tint * lamp * light_strength * mix(0.4, 1.0, h31(c + 4.4)) * (1.0 - 0.7 * cut);
	}
	COLOR = col;
}
