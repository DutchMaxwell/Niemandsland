shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Space background shader with animated twinkling stars
// Applied to an infinite ground plane below the table

uniform vec3 deep_space_color : source_color = vec3(0.02, 0.02, 0.08);
uniform vec3 nebula_color_1 : source_color = vec3(0.1, 0.05, 0.2);
uniform vec3 nebula_color_2 : source_color = vec3(0.05, 0.1, 0.15);
uniform float star_density : hint_range(0.0, 1.0) = 0.4;
uniform float star_brightness : hint_range(0.0, 2.0) = 1.0;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 1.5;
uniform float nebula_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float scale : hint_range(0.1, 10.0) = 1.0;

// Hash functions for pseudo-random star placement
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
}

// Noise function for nebula effect
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion for nebula clouds
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return value;
}

// Star field with twinkling
float stars(vec2 uv, float time) {
    float star_value = 0.0;

    // Multiple star layers for depth
    for (int layer = 0; layer < 3; layer++) {
        float layer_scale = 50.0 + float(layer) * 30.0;
        vec2 grid = floor(uv * layer_scale);
        vec2 grid_uv = fract(uv * layer_scale);

        // Random star position within each grid cell
        float rand = hash(grid + float(layer) * 100.0);

        // Only some cells have stars based on density
        if (rand < star_density * (0.5 + float(layer) * 0.25)) {
            // Star position
            vec2 star_pos = vec2(hash(grid * 1.1), hash(grid * 2.3)) * 0.8 + 0.1;
            float dist = length(grid_uv - star_pos);

            // Star size varies
            float star_size = 0.02 + hash2(grid) * 0.03;
            star_size /= (1.0 + float(layer) * 0.5); // Smaller stars in background

            // Twinkle effect - each star twinkles at different rate and phase
            float twinkle_phase = hash(grid * 3.7) * 6.28;
            float twinkle_rate = 0.5 + hash(grid * 4.2) * twinkle_speed;
            float twinkle = 0.5 + 0.5 * sin(time * twinkle_rate + twinkle_phase);

            // Some stars twinkle more than others
            float twinkle_amount = hash(grid * 5.1);
            twinkle = mix(1.0, twinkle, twinkle_amount * 0.8);

            // Star glow
            float glow = smoothstep(star_size * 3.0, 0.0, dist);
            float core = smoothstep(star_size, 0.0, dist);

            // Star color variation (subtle blue/white/yellow)
            float color_rand = hash(grid * 6.3);
            float brightness = (glow * 0.3 + core * 0.7) * twinkle;
            brightness *= (0.7 + float(2 - layer) * 0.15); // Brighter foreground stars

            star_value += brightness;
        }
    }

    return star_value * star_brightness;
}

void fragment() {
    // Use world position for seamless infinite plane
    vec2 uv = UV * scale;

    // Deep space base color
    vec3 color = deep_space_color;

    // Add nebula clouds
    float nebula1 = fbm(uv * 0.5 + vec2(TIME * 0.01, 0.0));
    float nebula2 = fbm(uv * 0.3 + vec2(0.0, TIME * 0.008));

    vec3 nebula = mix(nebula_color_1, nebula_color_2, nebula1);
    nebula *= nebula2 * nebula_intensity;
    color += nebula;

    // Add stars
    float star_brightness_value = stars(uv, TIME);

    // Star color (slight variation from pure white)
    vec3 star_color = vec3(0.9, 0.95, 1.0);
    color += star_color * star_brightness_value;

    // Add a subtle gradient from center
    float vignette = 1.0 - length(UV - 0.5) * 0.3;
    color *= vignette;

    ALBEDO = color;
    EMISSION = color; // Make it glow
}
