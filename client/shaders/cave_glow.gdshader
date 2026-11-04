shader_type spatial;
// Brilho suave das cavernas (fase 4.5): cristais, cogumelos e minérios que brilham. A cor vem
// do vértice; o brilho pulsa devagar, cada coisa no seu ritmo (pela posição no mundo).
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform float glow = 1.6;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.6;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float pulse = 0.8 + 0.2 * sin(TIME * 1.3 + wp.x * 0.7 + wp.z * 0.9);
	EMISSION = COLOR.rgb * glow * pulse;
}
