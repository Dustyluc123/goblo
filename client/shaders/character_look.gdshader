shader_type spatial;
// Personagem do editor (fase 4.0, ADR 0051): uma malha com a textura de paleta do Mini
// Characters e as peças feitas em código. A cor do vértice diz o que cada pedaço é (alfa):
// 0 = textura; 0,25 = pele (troca por skin_color, se escolhida, mantendo o sombreado guardado
// no vermelho); 0,5 = cabelo do personagem (troca por hair_color, idem); 0,75 = penteado extra (hair_color ou a cor do vértice); 1 = a cor
// do vértice (roupas, chapéus). Pele e cabelo são parâmetros de instância: um material só
// para todos os personagens.

uniform sampler2D colormap : source_color, filter_linear_mipmap;
instance uniform vec4 skin_color = vec4(0.0);
instance uniform vec4 hair_color = vec4(0.0);

void fragment() {
	vec3 tex = texture(colormap, UV).rgb;
	float mode = COLOR.a;
	vec3 c = tex;
	if (mode > 0.9) {
		c = COLOR.rgb;
	} else if (mode > 0.6) {
		c = hair_color.a > 0.5 ? hair_color.rgb : COLOR.rgb;
	} else if (mode > 0.4) {
		// O vermelho guarda o brilho do vértice em relação ao quadrado da paleta (÷ 2).
		c = hair_color.a > 0.5 ? hair_color.rgb * COLOR.r * 2.0 : tex;
	} else if (mode > 0.1) {
		c = skin_color.a > 0.5 ? skin_color.rgb * COLOR.r * 2.0 : tex;
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
