shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color;
uniform bool wood = false;
varying vec3 p;
varying float up;
void vertex() { p = VERTEX; up = abs(NORMAL.y); }
void fragment() {
	// Metre-scaled nap/grain; filter fine fibres before they alias at play distance.
	float across = mix(p.y, p.x, up);
	float phase = wood ? across*420.0 + sin(p.z*15.0)*3.0 : (p.x+p.z)*3600.0;
	float fibre = sin(phase)*exp(-fwidth(phase)*fwidth(phase));
	float broad = sin(p.x*65.0 + sin(p.z*17.0));
	ALBEDO = base_color.rgb*(1.0 + fibre*(wood ? 0.24 : 0.08) + broad*0.06);
	ROUGHNESS = wood ? 0.68 : 0.98;
	SPECULAR = wood ? 0.28 : 0.12;
}
