// Vegetação (árvores, arbustos, flores, grama e pedras do Nature Pack): cor por vértice
// (com a AO da base já gravada pela ModelLibrary) vezes a cor da instância, um pouco de
// variação de tom por instância e vento. Barato: só contas no vértice, sem texturas.
//
// O vento empurra cada vértice de lado conforme a altura dele no modelo (a base fica
// parada), com a fase vinda da posição da instância (cada planta balança no seu tempo).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Deslocamento máximo (unidades do modelo) no topo; 0 = sem vento (pedras).
uniform float wind_strength = 0.0;
// Altura (unidades do modelo) em que o balanço chega ao máximo.
uniform float wind_height = 3.0;
uniform float wind_speed = 1.1;
// Variação de brilho e tom por instância (0,08 = ±8%).
uniform float variation = 0.08;

varying float v_var;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float seed = fract(sin(dot(origin, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	v_var = (seed - 0.5) * 2.0 * variation;
	if (wind_strength > 0.0) {
		float k = clamp(VERTEX.y / wind_height, 0.0, 1.0);
		k *= k;
		float t = TIME * wind_speed + seed * 6.2831;
		float gust = 0.65 + 0.35 * sin(TIME * 0.37 + dot(origin, vec3(0.013, 0.011, 0.017)));
		vec3 sway = vec3(sin(t) + 0.3 * sin(t * 2.7 + 1.3), 0.0, 0.55 * cos(t * 0.83 + 0.4));
		VERTEX += sway * wind_strength * k * gust;
	}
}

void fragment() {
	vec3 c = COLOR.rgb * (1.0 + v_var);
	// Um pouco de tom: instâncias mais claras puxam para o amarelo, mais escuras para o azul.
	c *= vec3(1.0 + v_var * 0.5, 1.0, 1.0 - v_var * 0.5);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
