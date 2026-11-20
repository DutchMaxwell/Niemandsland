shader_type spatial;
// Look of the cylinders and boxes of the generated board's landmarks (BoardgenLandmarks): ONE material for every plain part. The look
// comes per instance (INSTANCE_CUSTOM.x), the instance colour is the base paint (display values, like the board shader), the size of the
// instance in inches comes from the model matrix. Procedural, same family as tiefwerk_board.gdshader: no texture file, nothing from a
// third party.
// looks: 0 plain; cylinders: 1 tank shell (varied dented plates, welds, rivets, rust streaks, grime, one hazard band),
// 2 tank cap (hatch, seams), 3 bare pipe (soot at the ends, rust), 4 insulation jacket (cladding seams, straps);
// boxes: 10 weathered paint (chips down to rust, grime from the foot, a weld line), 11 the same with warning stripes and bolts.

varying vec3 lpos;      // the vertex in the unit mesh: a cylinder's y runs along its length (-0.5..0.5), its radius is 0.5
varying vec3 dims;      // the instance size in inches: a cylinder's x and z = diameter, y = length
varying flat vec3 lnrm; // the face normal in mesh space (a box's face picks its two axes by it)
varying flat float look;

const float IN = 0.0254;
const float TAU_F = 6.2831853;
const vec3 RUST = vec3(0.42, 0.20, 0.09);

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	dims = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz)) / IN;
	look = INSTANCE_CUSTOM.x;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 17.1;
		a *= 0.5;
	}
	return s;
}

// A thin line every `step_in` inches (0 on the line, 1 off it).
float seam(float v, float step_in, float w) {
	return smoothstep(0.0, w, abs(fract(v / step_in + 0.5) - 0.5) * step_in);
}

// The height of a tank shell at (arc, along) inches: each plate has its own slight bulge and a few dents.
float shell_height(vec2 p, float course) {
	vec2 cell = vec2(fract((p.x + course * 0.6) / 1.57), fract(p.y / 0.75)) - 0.5;
	float bulge = (0.25 - dot(cell, cell)) * (h21(vec2(floor((p.x + course * 0.6) / 1.57), course)) - 0.4);
	return bulge * 0.7 + (fbm(p * vec2(2.2, 2.6)) - 0.5) * 0.5;
}

void fragment() {
	int k = int(look + 0.5);
	vec3 alb = COLOR.rgb;
	float rough = 0.8, met = 0.25, spec = 0.5, ao = 1.0;
	float along = (lpos.y + 0.5) * dims.y;   // inches from the low end
	float arc = (atan(lpos.z, lpos.x) / TAU_F + 0.5) * 3.14159 * dims.x;   // inches round a cylinder
	bool cap = abs(lpos.y) > 0.499;   // the flat ends of a cylinder

	if (k == 1 && !cap) {   // tank shell: four courses of plates, welded and riveted
		float course = floor(along / 0.75);
		vec2 p = vec2(arc, along);
		float pid = h21(vec2(floor((arc + course * 0.6) / 1.57), course));
		float n1 = fbm(p * 0.5), n2 = fbm(vec2(arc * 1.9, along * 0.11 + course * 3.0));
		alb *= mix(0.82, 1.12, pid) * mix(0.85, 1.1, n1);
		alb = mix(alb, alb * vec3(0.92, 1.0, 1.08), step(0.7, pid));   // a few plates were repainted cooler
		float welds = seam(along, 0.75, 0.035);
		float plates = seam(arc + course * 0.6, 1.57, 0.03);
		alb *= mix(0.32, 1.0, welds * plates);
		float riv = smoothstep(0.05, 0.02, length(vec2(fract(arc / 0.42) - 0.5, (fract(along / 0.75 + 0.5) - 0.5) * 0.75 / 0.42 * 2.0) * 0.42 * 0.5));
		alb += riv * 0.2;
		float streak = smoothstep(0.52, 0.74, n2) * smoothstep(0.9, 0.0, fract(along / 0.75));   // rust bleeds down from each weld
		alb = mix(alb, RUST * mix(0.7, 1.2, n1), streak * 0.95);
		alb *= mix(0.5, 1.0, smoothstep(0.0, 1.1, along));   // grime climbs from the foot
		alb *= mix(1.0, 0.7, smoothstep(2.7, 3.0, along));   // soot under the rim
		float band = step(1.45, along) * step(along, 2.0);   // one hazard band: diagonal stripes, chipped and grimy
		float hazard = step(0.5, fract((arc + along) * 0.9));
		alb = mix(alb, mix(vec3(0.06), vec3(0.78, 0.6, 0.1) * mix(0.7, 1.0, n1), hazard), band * 0.92);
		alb = mix(alb, RUST * mix(0.6, 1.0, n1), band * smoothstep(0.64, 0.78, fbm(p * 2.4 + 3.0)) * 0.7);
		float e = 0.06;   // the dents, as a tangent-space normal from the height field
		float h0 = shell_height(p, course);
		NORMAL_MAP = vec3(0.5 - (shell_height(p + vec2(e, 0.0), course) - h0) * 2.0, 0.5 - (shell_height(p + vec2(0.0, e), course) - h0) * 2.0, 1.0);
		NORMAL_MAP_DEPTH = 1.0;
		rough = mix(0.32, 0.9, max(n2, streak)) * mix(0.8, 1.2, pid);   // fresh paint shines, rust does not
		met = 0.35;
		spec = 0.7;
	} else if (k == 2) {   // tank cap: a hatch, concentric seams
		vec2 xy = lpos.xz * dims.x;
		float rr = length(xy);
		float n1 = fbm(xy * 1.3);
		alb *= mix(0.8, 1.1, n1) * mix(0.5, 1.0, seam(rr, 0.32, 0.03));
		alb = mix(alb, vec3(0.14, 0.14, 0.15), smoothstep(0.34, 0.3, rr) * 0.8);
		alb += smoothstep(0.03, 0.015, abs(rr - 0.26)) * 0.1;
		alb = mix(alb, RUST * 0.8, smoothstep(0.62, 0.8, n1) * 0.5);
		rough = 0.5;
		met = 0.4;
		spec = 0.7;
	} else if (k == 3) {   // bare pipe: soot toward the flanges, rust spots
		float n1 = fbm(vec2(arc * 2.0, along * 1.6));
		alb *= mix(0.8, 1.1, n1) * mix(0.45, 1.0, smoothstep(0.0, 0.4, min(along, dims.y - along)));
		alb = mix(alb, RUST, smoothstep(0.62, 0.8, n1) * 0.6);
		rough = 0.5;
		met = 0.5;
	} else if (k == 4) {   // insulation jacket: sheet-metal cladding with straps, dented and dirty
		float n1 = fbm(vec2(arc * 3.0, along * 1.4));
		alb *= mix(0.78, 1.1, n1) * mix(0.4, 1.0, seam(along, 0.6, 0.04)) * mix(0.55, 1.0, seam(arc, 0.9, 0.025));
		alb = mix(alb, vec3(0.3, 0.27, 0.22), smoothstep(0.6, 0.78, fbm(vec2(arc * 1.3, along * 0.7 + 4.0))) * 0.7);
		rough = mix(0.25, 0.7, n1);
		met = 0.6;
		spec = 0.8;
	} else if (k >= 10) {   // boxes: the face picks its two axes
		vec3 an = abs(lnrm);
		vec2 uv = an.x > 0.5 ? vec2(lpos.z * dims.z, lpos.y * dims.y) : an.y > 0.5 ? vec2(lpos.x * dims.x, lpos.z * dims.z) : vec2(lpos.x * dims.x, lpos.y * dims.y);
		float h = (lpos.y + 0.5) * dims.y;   // inches above the foot of the part
		float n1 = fbm(uv * 1.2 + dims.xy), n2 = fbm(uv * vec2(2.5, 0.35) + 9.0);
		if (k == 11 && an.y < 0.5) {   // warning stripes, chipped, with a bolt in each corner
			float stripe = step(0.5, fract((uv.x + uv.y) * 0.45));
			alb = mix(vec3(0.07), alb, stripe);
			vec2 half_face = vec2(an.x > 0.5 ? dims.z : dims.x, dims.y) * 0.5;
			alb += smoothstep(0.07, 0.03, length(abs(uv) - (half_face - 0.22))) * 0.25;
		}
		alb *= mix(0.78, 1.1, n1);
		float chip = smoothstep(0.5, 0.64, fbm(uv * 3.1 + 4.0));
		alb = mix(alb, mix(RUST, vec3(0.3, 0.3, 0.32), step(0.82, h21(floor(uv * 3.1)))), chip * 0.9);
		float long_in = dims.y > max(dims.x, dims.z) ? h : max(dims.x, dims.z) * (lpos.x + 0.5);   // bolts on a post or a chord, a weld every few
		alb += smoothstep(0.05, 0.02, length(vec2((fract(long_in / 1.1) - 0.5) * 1.1, uv.x))) * 0.3;
		alb = mix(alb, RUST * 0.8, smoothstep(0.5, 0.75, n2) * 0.75);   // rust runs down
		alb *= mix(0.4, 1.0, smoothstep(0.0, 3.5, h)) * mix(0.8, 1.0, n1);   // grime from the foot
		rough = mix(0.35, 0.85, max(chip, n2));
		met = mix(0.3, 0.1, chip);
		spec = 0.6;
	}
	ALBEDO = pow(alb, vec3(2.2)) * ao;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = met;
	SPECULAR = spec;
}
