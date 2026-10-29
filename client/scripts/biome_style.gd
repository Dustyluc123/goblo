class_name BiomeStyle
extends RefCounted
## Aparência de cada bioma: cor do chão e das paredes dos degraus.
##
## A vegetação não fica mais aqui: árvores, pedras, flores e arbustos vêm do servidor
## (server/data/game/objects.json) e a grama do cliente vem de client/data/decoracao.json.


## Cor do topo de cada bioma (sRGB). Paleta pastel da fase 2.1: verdes um pouco mais
## claros e quentes (puxando para o amarelo), para conversar com as copas das árvores
## (object_tint em decoracao.json) e com a grama, em vez de um verde saturado chapado.
const COLORS := {
	WorldData.Biome.OCEAN: Color("6fb6dc"),
	WorldData.Biome.BEACH: Color("f3e4b0"),
	WorldData.Biome.TROPICAL_FOREST: Color("79b36c"),
	WorldData.Biome.FOREST: Color("94c277"),
	WorldData.Biome.GRASSLAND: Color("bfd585"),
	WorldData.Biome.DESERT: Color("eccb92"),
	WorldData.Biome.MOUNTAIN: Color("aaa39a"),
	WorldData.Biome.TUNDRA: Color("aeb795"),
	WorldData.Biome.ICE: Color("eef4fa"),
}
const SNOW := Color("f4f7fb")
const SNOW_LINE := 4.0  # montanhas acima desta altura ganham neve
const SAND_WALL := Color("dcc58f")
const ROCK_WALL := Color("8f877e")
const ICE_WALL := Color("cfdcea")
const DIRT_WALL := Color("b49a72")

## Cor do topo da célula (já em espaço linear, pronta para o shader).
static func top_color(world: WorldData, id: int) -> Color:
	var b: int = world.biomes[id]
	var c: Color = COLORS.get(b, Color.MAGENTA)
	if b == WorldData.Biome.MOUNTAIN and world.heights[id] >= SNOW_LINE:
		c = SNOW
	var jitter := hash01(id) - 0.5
	c = c.lightened(jitter * 0.06) if jitter > 0 else c.darkened(-jitter * 0.06)
	return c.srgb_to_linear()


static func wall_color(world: WorldData, id: int) -> Color:
	match int(world.biomes[id]):
		WorldData.Biome.MOUNTAIN:
			return ROCK_WALL.srgb_to_linear()
		WorldData.Biome.ICE:
			return ICE_WALL.srgb_to_linear()
		WorldData.Biome.TUNDRA, WorldData.Biome.FOREST, WorldData.Biome.TROPICAL_FOREST, WorldData.Biome.GRASSLAND:
			# Barranco de grama: a cor do topo mais escura, com um pouco de terra. Terra pura
			# ficava clara demais ao sol e parecia um caminho em volta das células.
			var top: Color = COLORS[int(world.biomes[id])]
			return top.darkened(0.28).lerp(DIRT_WALL, 0.3).srgb_to_linear()
	return SAND_WALL.srgb_to_linear()


## Número estável entre 0 e 1 a partir de um inteiro.
static func hash01(x: int) -> float:
	var h := (x * 2654435761) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	h ^= h >> 13
	return float(h & 0xFFFF) / 65535.0
