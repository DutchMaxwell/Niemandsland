// Continuous triangular patch blending with independent rotations and offsets.
// No mirrored coordinates: source landmarks cannot form repeated reflected diamonds.
vec3 volcanic_patch_hash(vec2 p) {
	vec3 q = vec3(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3)),dot(p,vec2(419.2,371.9)));
	return fract(sin(q)*43758.5453);
}
vec3 volcanic_patch(sampler2D tex,vec2 uv,vec2 cell,vec2 dx,vec2 dy) {
	vec3 random = volcanic_patch_hash(cell);
	float angle = (random.z-0.5)*1.4;
	mat2 rotation = mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)));
	vec2 offset = random.xy*7.0;
	return textureGrad(tex,rotation*uv+offset,rotation*dx,rotation*dy).rgb;
}
vec3 volcanic_surface_sample(sampler2D tex,vec2 uv) {
	vec2 grid = mat2(vec2(1.0,0.0),vec2(-0.57735027,1.15470054))*uv;
	vec2 cell = floor(grid),f = fract(grid);
	vec2 a,b,c;
	vec3 weights;
	if (f.x+f.y<1.0) {
		a=cell;b=cell+vec2(1,0);c=cell+vec2(0,1);
		weights=vec3(1.0-f.x-f.y,f.x,f.y);
	} else {
		a=cell+vec2(1,1);b=cell+vec2(0,1);c=cell+vec2(1,0);
		weights=vec3(f.x+f.y-1.0,1.0-f.x,1.0-f.y);
	}
	weights=weights*weights*weights;
	weights/=dot(weights,vec3(1.0));
	// Gradients belong to the continuous coordinates, not the discontinuous cell hash.
	vec2 dx=dFdx(uv),dy=dFdy(uv);
	return volcanic_patch(tex,uv,a,dx,dy)*weights.x+volcanic_patch(tex,uv,b,dx,dy)*weights.y+volcanic_patch(tex,uv,c,dx,dy)*weights.z;
}
