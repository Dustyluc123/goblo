// Chão do globo: cor por vértice (bioma, já em espaço linear), sombreamento flat calculado
// pelas derivadas da posição (dispensa normais duplicadas na malha) e um ruído sutil em
// duas escalas para o chão não ficar chapado.
//
// Estações (fase 2.5): o alfa da cor marca os biomas que mudam (floresta, campo, tundra,
// montanha). A fase vem da data (season_phase, no hemisfério norte; no sul, + 2), igual a
// client/scripts/seasons.gd: outono dourado, inverno branco, primavera verde mais claro,
// com transição suave nas viradas e nada entre os trópicos.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform float season_phase = 1.5;
uniform float season_on = 1.0;
uniform float season_blend = 0.1095;

varying vec3 world_pos;

float season_weight(float p, float s) {
	float d = mod(p - s + 2.0, 4.0) - 2.0;
	return smoothstep(-season_blend, season_blend, d) * (1.0 - smoothstep(1.0 - season_blend, 1.0 + season_blend, d));
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	float n = value_noise(world_pos * 0.25) * 0.6 + value_noise(world_pos * 1.3) * 0.4;
	// Manchas grandes (dezenas de unidades): umas mais secas e claras (puxam para o amarelo),
	// outras mais úmidas e escuras. Quebra as áreas lisas do chão.
	float patches = value_noise(world_pos * 0.045) * 0.65 + value_noise(world_pos * 0.11) * 0.35;
	vec3 dry = COLOR.rgb * vec3(1.10, 1.06, 0.86);
	vec3 lush = COLOR.rgb * vec3(0.90, 0.96, 0.92);
	vec3 base = mix(lush, dry, smoothstep(0.3, 0.75, patches));
	float lat = degrees(asin(clamp(normalize(world_pos).y, -1.0, 1.0)));
	float k = COLOR.a * season_on * smoothstep(22.5, 25.5, abs(lat));
	if (k > 0.0) {
		float ph = mod(season_phase + (lat < 0.0 ? 2.0 : 0.0), 4.0);
		float spring = season_weight(ph, 0.0);
		float autumn = season_weight(ph, 2.0);
		float winter = season_weight(ph, 3.0);
		vec3 golden = base * vec3(1.22, 0.9, 0.48) + vec3(0.05, 0.025, 0.0);
		base = mix(base, golden, autumn * k * mix(0.55, 0.85, patches));
		base = mix(base, base * vec3(0.98, 1.08, 0.9), spring * k * 0.7);
		vec3 snow = vec3(0.86, 0.9, 0.97) * (0.96 + 0.04 * patches);
		base = mix(base, snow, winter * k * 0.92);
	}
	ALBEDO = base * (0.93 + 0.14 * n);
	ROUGHNESS = 1.0;
}
