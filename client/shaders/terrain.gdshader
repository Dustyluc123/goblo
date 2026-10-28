// Chão do globo: cor por vértice (bioma, já em espaço linear), sombreamento flat calculado
// pelas derivadas da posição (dispensa normais duplicadas na malha) e um ruído sutil em
// duas escalas para o chão não ficar chapado.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

varying vec3 world_pos;

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
	ALBEDO = COLOR.rgb * (0.93 + 0.14 * n);
	ROUGHNESS = 1.0;
}
