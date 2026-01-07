shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D SCREEN_TEXTURE: hint_screen_texture,repeat_disable, filter_nearest;
/**
* How blurry the result should be.
* Limited to 20 because of performance, if you want feel free to break it.
*/
uniform float strength : hint_range(0.1, 60.0) = 3.3;
/**
* How dark the blur will be
*/
uniform float mix_percentage: hint_range(0.0, 1.0) = 0.0;
/**
* Base transparency of the blur effect
*/
uniform float base_alpha: hint_range(0.0, 1.0) = 1.0;

float gaussianDistribution(float x, float STD){ // STD stands for standard deviation
	return exp(-(x*x)/(2.*STD*STD))/(sqrt(2.*PI)*STD);
}

vec4 gaussianblur(sampler2D sampler, vec2 pos, vec2 pixel_size, float sigmaUsed, int radius){
    vec4 blurredPixel = vec4(0.0);
    float total_weight = 0.0;
	// Loop over the radius (tecnically its a square)
    for(int i = -radius ; i <= radius; i++){
        for(int j = -radius; j <= radius; j++){
			// Calculate the offset from the current pixel
			vec2 offset = vec2(float(i), float(j))*pixel_size;
			vec2 changedPos = pos + offset;

			// Calculate the weight based on the Gaussian distribution multiplying both dimentions (how far are X and Y form the center (pos))
			float weight = gaussianDistribution(float(i), sigmaUsed)*gaussianDistribution(float(j), sigmaUsed);
			// Add the weighted color value to the blurred pixel (including alpha)
			blurredPixel += texture(SCREEN_TEXTURE, changedPos) * weight;
			total_weight += weight;
        }
    }
	// Normalize the blurred pixel color by the total weight
	blurredPixel/=total_weight;
    return blurredPixel;
}
void fragment() {
    vec4 PixelBlurred = gaussianblur(SCREEN_TEXTURE, SCREEN_UV, SCREEN_PIXEL_SIZE, strength, int(round(3.0 * strength)));
	vec3 color = mix(PixelBlurred.rgb, vec3(0.0), mix_percentage);
    // The radius is 3*strength because it is the point where the Gaussian weight is near zero.

    // Get the original alpha from the control node this shader is applied to
    float alpha = COLOR.a * base_alpha;

    // Preserve transparency for proper blending
    COLOR = vec4(color, alpha);
}
