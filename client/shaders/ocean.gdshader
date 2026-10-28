// Oceano animado: ondulação grande na geometria, ondinhas na normal, cor mais clara perto
// da costa (COLOR.r = profundidade 0..1), espuma leve nos cantos que encostam na terra
// (COLOR.g) e brilho do sol. O planeta fica na origem, então a normal da esfera é a
// própria posição normalizada.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.55, 0.86, 0.87, 1.0);
uniform vec4 deep_color : source_color = vec4(0.22, 0.52, 0.78, 1.0);
uniform vec4 foam_color : source_color = vec4(0.97, 0.99, 1.0, 1.0);
uniform float swell_height = 0.12;
uniform float ripple_strength = 0.2;

varying vec3 world_pos;
varying float depth;
varying float foam;

float swell(vec3 p, float t) {
	return sin(dot(p, vec3(0.071, 0.043, 0.059)) + t * 0.9) * 0.6
		+ sin(dot(p, vec3(-0.052, 0.067, 0.031)) + t * 1.3) * 0.4;
}

float ripples(vec3 p, float t) {
	return sin(dot(p, vec3(0.9, 0.3, 0.6)) * 0.9 + t * 1.6)
		+ sin(dot(p, vec3(-0.4, 0.8, 0.5)) * 1.37 + t * 2.1) * 0.6
		+ sin(dot(p, vec3(0.2, -0.5, 0.85)) * 2.13 + t * 2.9) * 0.35
		+ sin(dot(p, vec3(-0.7, -0.2, 0.68)) * 3.07 + t * 3.7) * 0.2;
}

void vertex() {
	vec3 n = normalize(VERTEX);
	VERTEX += n * swell(VERTEX, TIME) * swell_height;
	NORMAL = n;
	world_pos = VERTEX;
	depth = COLOR.r;
	foam = COLOR.g;
}

void fragment() {
	vec3 n = normalize(world_pos);
	vec3 helper = abs(n.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t1 = normalize(cross(helper, n));
	vec3 t2 = cross(n, t1);
	float e = 0.25;
	float h0 = ripples(world_pos, TIME);
	float dx = ripples(world_pos + t1 * e, TIME) - h0;
	float dy = ripples(world_pos + t2 * e, TIME) - h0;
	// As ondinhas somem com a distância (de longe viram listras repetidas).
	float near_fade = 1.0 - smoothstep(20.0, 160.0, length(VERTEX));
	vec3 wn = normalize(n - (t1 * dx + t2 * dy) * ripple_strength * near_fade);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, depth));
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, shallow_color.rgb * 1.15, fresnel * 0.35);
	float band = sin(TIME * 1.4 + dot(world_pos, vec3(0.6, 0.45, 0.35)) * 1.5) * 0.5 + 0.5;
	float f = foam * (1.0 - depth) * smoothstep(0.45, 0.95, band + h0 * 0.15);
	col = mix(col, foam_color.rgb, f * 0.55);
	ALBEDO = col;
	ROUGHNESS = mix(0.12, 0.6, f);
	SPECULAR = 0.6;
}
