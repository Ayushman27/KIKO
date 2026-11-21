#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform vec2 u_mouse;
uniform float u_is_gmode;

out vec4 fragColor;

// Simplex-style 2D noise
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x*34.0)+1.0)*x); }

float snoise(vec2 v) {
    const vec4 C = vec4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                        0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                        -0.577350269189626, // -1.0 + 2.0 * C.x
                        0.024390243902439); // 1.0 / 41.0
    vec2 i  = floor(v + dot(v, C.yy) );
    vec2 x0 = v -   i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
        + i.x + vec3(0.0, i1.x, 1.0 ));
    vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m ;
    m = m*m ;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
    vec3 g;
    g.x  = a0.x  * x0.x  + h.x  * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

float fbm(vec2 p) {
    float total = 0.0;
    float amp = 0.55;
    float freq = 1.0;
    for(int i = 0; i < 5; i++) {
        total += amp * snoise(p * freq);
        freq *= 2.05;
        amp *= 0.48;
    }
    return total;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / u_resolution;
    vec2 p = (fragCoord * 2.0 - u_resolution) / min(u_resolution.x, u_resolution.y);

    float t = u_time * 0.18;
    
    // Domain warping for organic silky smoke & fluid dispersion
    vec2 q = vec2(fbm(p + vec2(0.0, t * 0.4)), fbm(p + vec2(5.2, 1.3 - t * 0.3)));
    vec2 r = vec2(fbm(p + 4.0 * q + vec2(1.7 - t * 0.5, 9.2 + t * 0.2)),
                  fbm(p + 4.0 * q + vec2(8.3 + t * 0.3, 2.8 - t * 0.4)));

    float f = fbm(p + 3.5 * r);

    // Deep luxury dark background base
    vec3 bgAlpha = vec3(0.03, 0.045, 0.07);
    vec3 bgGMode = vec3(0.05, 0.02, 0.01);
    vec3 bgColor = mix(bgAlpha, bgGMode, u_is_gmode);
    
    // Vibrant ethereal smoke swirls that respond to dual-mode accent
    // Alpha mode: cyan / indigo
    vec3 smokeCyan = vec3(0.0, 0.78, 0.98);
    vec3 smokeDeepAlpha = vec3(0.08, 0.12, 0.28);
    vec3 smokeGlowAlpha = vec3(0.15, 0.45, 0.85);

    // G mode: fiery orange / ember
    vec3 smokeOrange = vec3(1.0, 0.34, 0.15);
    vec3 smokeDeepG = vec3(0.28, 0.06, 0.02);
    vec3 smokeGlowG = vec3(1.0, 0.25, 0.05);

    vec3 smokePrimary = mix(smokeCyan, smokeOrange, u_is_gmode);
    vec3 smokeDeep = mix(smokeDeepAlpha, smokeDeepG, u_is_gmode);
    vec3 smokeGlow = mix(smokeGlowAlpha, smokeGlowG, u_is_gmode);

    vec3 col = mix(bgColor, smokeDeep, clamp(f * 1.4, 0.0, 1.0));
    col = mix(col, smokePrimary, clamp(length(q) * f * 0.85, 0.0, 1.0));
    col += smokeGlow * pow(clamp(f * 1.2, 0.0, 1.0), 3.0) * 0.65;

    // Soft vignetting
    float vignette = smoothstep(1.5, 0.4, length(uv - 0.5) * 1.4);
    col *= vignette;

    fragColor = vec4(col, 0.95);
}
