// --- Relief (AAA steps 3 and 4): ONE height function per surface class, in inches (raised > 0); the shading normal is its gradient by
// finite differences (pattern: tiefwerk_landmark.gdshader). Features smaller than a pixel fade out (px = inches per pixel), so nothing shimmers.
// Walls: frame, inset field, plate seams, rivets as domes, louvres, signage plates, conduits. Same panel maths as the albedo in fragment().

float feature(float size_in, float px) {   // 1 when the feature spans a few pixels, 0 when it is sub-pixel
	return smoothstep(px * 0.7, px * 2.5, size_in);
}

float dome(float d, float r, float h) {   // a round-headed bump of radius r
	return h * sqrt(max(1.0 - d * d / (r * r), 0.0));
}

float wall_height(vec2 uv, float px) {
	vec2 pid = floor(uv / PLATE);
	vec2 fp = (fract(uv / PLATE) - 0.5) * PLATE;
	vec2 ap = abs(fp);
	float ph = h21(pid + 9.1);
	float ed = PLATE * 0.5 - max(ap.x, ap.y);   // inches to the plate edge
	float h = -0.03 * smoothstep(0.12, 0.17, ed) * feature(0.1, px);   // the field sits behind its frame
	h -= 0.02 * smoothstep(0.04, 0.0, ed) * feature(0.04, px);   // the seam between two plates
	float along = ap.x > ap.y ? fp.y : fp.x;   // rivets: a row along the frame, 0.25 in apart, 0.05 in across
	float rv = length(vec2((fract(along / 0.25 + 0.5) - 0.5) * 0.25, ed - 0.085));
	h += dome(rv, 0.026, 0.02) * step(0.1, ph) * feature(0.05, px);
	if (ph < 0.1) {   // a louvred vent: tilted slats over dark gaps
		float t = fract(uv.y * 5.0);
		float slat = -0.05 + 0.08 * smoothstep(0.42, 0.9, t) * smoothstep(1.0, 0.92, t);
		h = mix(h, slat, step(ap.x, 0.5) * step(ap.y, 0.42) * feature(0.1, px));
	} else if (ph < 0.2) {   // a signage plate stands a hair proud of the wall
		h += 0.012 * step(ap.x, 0.55) * step(ap.y, 0.32);
	} else if (h21(vec2(floor(uv.y / PLATE), floor(uv.x / 6.0)) + 21.0) > 0.82) {   // a conduit: a half-round bar
		float t = (fp.y - 0.45) / 0.07;
		h += 0.05 * sqrt(max(1.0 - t * t, 0.0)) * feature(0.14, px);
	}
	return h;
}

// The wall's shading normal (world space) and its height at the point (for roughness).
vec3 wall_relief(vec2 uv, vec3 n, float px, out float h0) {
	const float DE = 0.008;
	h0 = wall_height(uv, px);
	float hu = (wall_height(uv + vec2(DE, 0.0), px) - h0) / DE;
	float hv = (wall_height(uv + vec2(0.0, DE), px) - h0) / DE;
	vec3 tu = abs(n.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);   // uv.x runs along z on x-facing walls, along x on z-facing ones
	return normalize(n - hu * tu - hv * vec3(0.0, 1.0, 0.0));
}
