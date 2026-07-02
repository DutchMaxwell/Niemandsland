shader_type canvas_item;
// Balatro-style card tilt for a 2D Control card (Handover D / D2). Fakes a 3D-camera perspective on a
// CanvasItem by rotating the quad's vertices in a virtual 3D space and projecting them back — the
// documented godotshaders.com "Balatro card tilt" pattern (canvas_item, FOV + X/Y rotation), NOT true
// 3D. Drive rot_x/rot_y from the hover offset (CardVisual does this via a spring); a faint specular
// sheen shifts WITH the tilt. All strengths are small on purpose — "felt, not noticed".

uniform float fov : hint_range(20.0, 120.0) = 55.0;   // virtual camera FOV (deg)
uniform float rot_x = 0.0;                             // tilt around X (deg): from vertical hover offset
uniform float rot_y = 0.0;                             // tilt around Y (deg): from horizontal hover offset
uniform vec2  rect_size = vec2(152.0, 100.0);          // the card's pixel size (set by CardVisual)
uniform float sheen_strength : hint_range(0.0, 0.5) = 0.10;

varying vec2 v_uv;

void vertex() {
	// Work in a centered -0.5..0.5 quad, rotate it as a 3D plane, project with a pinhole camera.
	vec2 centered = UV - 0.5;
	float ax = radians(rot_x);
	float ay = radians(rot_y);
	vec3 p = vec3(centered, 0.0);
	// rotate around Y then X
	p = vec3(p.x * cos(ay) + p.z * sin(ay), p.y, -p.x * sin(ay) + p.z * cos(ay));
	p = vec3(p.x, p.y * cos(ax) - p.z * sin(ax), p.y * sin(ax) + p.z * cos(ax));
	// perspective divide (focal length from FOV; push the plane in front of the camera)
	float focal = 1.0 / tan(radians(fov) * 0.5);
	float z = p.z + focal;
	vec2 proj = p.xy * focal / max(z, 0.001);
	// back to the control's local pixel space
	VERTEX = (proj + 0.5) * rect_size;
	v_uv = UV;
}

void fragment() {
	COLOR = texture(TEXTURE, v_uv);
	// Specular sheen: a soft diagonal highlight whose position tracks the tilt, so the card catches
	// "light" as it turns. Kept subtle and additive; premultiplied by the sprite alpha so it never
	// bleeds past the rounded card edges (the card frame's own alpha).
	vec2 dir = normalize(vec2(rot_y, -rot_x) + vec2(0.0001));
	float d = dot(v_uv - 0.5, dir);
	float band = smoothstep(0.35, 0.0, abs(d - 0.15));
	COLOR.rgb += band * sheen_strength * COLOR.a;
}
