shader_type sky;

// Space skybox shader with animated twinkling stars
// Creates an immersive cosmos around the play area

uniform vec3 deep_space_color : source_color = vec3(0.01, 0.01, 0.04);
uniform vec3 nebula_color_1 : source_color = vec3(0.08, 0.02, 0.15);
uniform vec3 nebula_color_2 : source_color = vec3(0.02, 0.08, 0.12);
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float star_brightness : hint_range(0.0, 3.0) = 1.5;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 1.2;
uniform float nebula_intensity : hint_range(0.0, 1.0) = 0.25;

// Hash functions for pseudo-random star placement
float hash(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float hash2(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// 3D Noise function for nebula
float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n = mix(
        mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
            mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
        mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
            mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
    return n;
}

// Fractal Brownian Motion for nebula clouds
float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise3d(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Star field with twinkling
float stars(vec3 dir, float time) {
    float star_value = 0.0;

    // Multiple star layers for depth
    for (int layer = 0; layer < 3; layer++) {
        float layer_scale = 80.0 + float(layer) * 40.0;
        vec3 grid = floor(dir * layer_scale);
        vec3 grid_uv = fract(dir * layer_scale);

        float rand = hash(grid + float(layer) * 100.0);

        if (rand < star_density * (0.4 + float(layer) * 0.2)) {
            vec3 star_pos = vec3(hash(grid * 1.1), hash(grid * 2.3), hash(grid * 3.7)) * 0.8 + 0.1;
            float dist = length(grid_uv - star_pos);

            float star_size = 0.015 + hash2(grid) * 0.025;
            star_size /= (1.0 + float(layer) * 0.4);

            // Twinkle effect
            float twinkle_phase = hash(grid * 3.7) * 6.28;
            float twinkle_rate = 0.3 + hash(grid * 4.2) * twinkle_speed;
            float twinkle = 0.6 + 0.4 * sin(time * twinkle_rate + twinkle_phase);

            float twinkle_amount = hash(grid * 5.1);
            twinkle = mix(1.0, twinkle, twinkle_amount * 0.7);

            float glow = smoothstep(star_size * 4.0, 0.0, dist);
            float core = smoothstep(star_size, 0.0, dist);

            float brightness = (glow * 0.2 + core * 0.8) * twinkle;
            brightness *= (0.6 + float(2 - layer) * 0.2);

            star_value += brightness;
        }
    }

    return star_value * star_brightness;
}

void sky() {
    vec3 dir = EYEDIR;

    // Deep space base color
    vec3 color = deep_space_color;

    // Add nebula clouds using direction as 3D coordinates
    float nebula1 = fbm(dir * 2.0 + vec3(TIME * 0.005, 0.0, 0.0));
    float nebula2 = fbm(dir * 1.5 + vec3(0.0, TIME * 0.003, 0.0));

    vec3 nebula = mix(nebula_color_1, nebula_color_2, nebula1);
    nebula *= nebula2 * nebula_intensity;
    color += nebula;

    // Add stars
    float star_val = stars(dir, TIME);
    vec3 star_color = vec3(0.95, 0.97, 1.0);
    color += star_color * star_val;

    // Slight horizon glow (optional - for atmosphere feel)
    float horizon = 1.0 - abs(dir.y);
    horizon = pow(horizon, 8.0) * 0.1;
    color += vec3(0.1, 0.15, 0.2) * horizon;

    COLOR = color;
}
