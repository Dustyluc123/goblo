class_name BiomeStyle
extends RefCounted
## Aparência de cada bioma: cor do chão e das paredes dos degraus.
##
## A vegetação não fica mais aqui: árvores, pedras, flores e arbustos vêm do servidor
## (server/data/game/objects.json) e a grama do cliente vem de client/data/decoracao.json.


## Cor do topo de cada bioma (sRGB).
const COLORS := {
	WorldData.Biome.OCEAN: Color("6fb6dc"),
	WorldData.Biome.BEACH: Color("f1e1a6"),
	WorldData.Biome.TROPICAL_FOREST: Color("5fae63"),
	WorldData.Biome.FOREST: Color("86c46f"),
	WorldData.Biome.GRASSLAND: Color("b9d77a"),
	WorldData.Biome.DESERT: Color("ecc98a"),
	WorldData.Biome.MOUNTAIN: Color("a59e95"),
	WorldData.Biome.TUNDRA: Color("a9b48f"),
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
			return DIRT_WALL.srgb_to_linear()
	return SAND_WALL.srgb_to_linear()


## Número estável entre 0 e 1 a partir de um inteiro.
static func hash01(x: int) -> float:
	var h := (x * 2654435761) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	h ^= h >> 13
	return float(h & 0xFFFF) / 65535.0
