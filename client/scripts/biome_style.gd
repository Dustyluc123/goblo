class_name BiomeStyle
extends RefCounted
## Aparência de cada bioma: cor do chão e lista de decorações (modelos da Kenney).
##
## Decorações:
## - `big` = árvores e pedras grandes: têm colisão, aparecem mais longe e NÃO dependem
##   da qualidade (todos os jogadores veem as mesmas, o que importa no multiplayer).
## - as outras (grama, plantas, pedrinhas) não têm colisão, somem mais cedo e a
##   quantidade é multiplicada pela densidade da qualidade gráfica.
## `count` é a média por célula (um hexágono tem ~560 unidades²).


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

## Modelos usados como decoração. `collider`: "cylinder" (raio, altura) ou "box", em
## unidades do modelo antes da escala.
const MODELS := {
	"tree": {"path": "res://assets/kenney/mini-forest/tree.glb", "collider": "cylinder", "r": 0.18, "h": 1.6},
	"tree_high": {"path": "res://assets/kenney/mini-forest/tree-high.glb", "collider": "cylinder", "r": 0.18, "h": 2.2},
	"pine": {"path": "res://assets/kenney/graveyard-kit/pine.glb", "collider": "cylinder", "r": 0.2, "h": 2.2},
	"pine_crooked": {"path": "res://assets/kenney/graveyard-kit/pine-crooked.glb", "collider": "cylinder", "r": 0.2, "h": 2.0},
	"pine_fall": {"path": "res://assets/kenney/graveyard-kit/pine-fall.glb", "collider": "cylinder", "r": 0.2, "h": 2.2},
	"rocks_high": {"path": "res://assets/kenney/mini-forest/rocks-high.glb", "collider": "box"},
	"rocks_tall": {"path": "res://assets/kenney/graveyard-kit/rocks-tall.glb", "collider": "box"},
	"rocks": {"path": "res://assets/kenney/graveyard-kit/rocks.glb", "collider": "box"},
	"plant": {"path": "res://assets/kenney/mini-forest/plant.glb"},
	"grass": {"path": "res://assets/kenney/mini-forest/patch-grass.glb"},
	"stones": {"path": "res://assets/kenney/mini-forest/stones.glb"},
	"trunk": {"path": "res://assets/kenney/graveyard-kit/trunk-long.glb"},
}

const GREEN_DARK := Color(0.72, 0.92, 0.7)
const GREEN := Color(1, 1, 1)
const DRY := Color(1.0, 0.92, 0.65)
const COLD := Color(0.85, 0.9, 0.85)
const GREY := Color(0.9, 0.9, 0.92)
const WHITE_BLUE := Color(0.95, 0.98, 1.05)

## Decoração por bioma: [modelo, por célula, escala mín, escala máx, cor, grande?]
const DECOR := {
	WorldData.Biome.TROPICAL_FOREST: [
		["tree_high", 16.0, 2.6, 3.8, GREEN_DARK, true],
		["tree", 10.0, 2.2, 3.2, GREEN_DARK, true],
		["plant", 26.0, 2.0, 3.6, GREEN_DARK, false],
		["grass", 10.0, 2.0, 3.0, GREEN_DARK, false],
		["trunk", 0.6, 1.2, 1.8, GREEN, false],
	],
	WorldData.Biome.FOREST: [
		["tree", 8.0, 2.2, 3.2, GREEN, true],
		["pine", 5.0, 2.4, 3.4, GREEN, true],
		["pine_fall", 1.5, 2.2, 3.0, GREEN, true],
		["plant", 10.0, 1.8, 3.0, GREEN, false],
		["grass", 10.0, 2.0, 3.0, GREEN, false],
		["stones", 1.0, 1.2, 2.0, GREY, false],
	],
	WorldData.Biome.GRASSLAND: [
		["grass", 22.0, 2.0, 3.6, Color(1.0, 0.968, 0.86), false],
		["plant", 8.0, 1.6, 2.8, Color(1.0, 0.96, 0.825), false],
		["tree", 1.2, 2.0, 3.0, Color(1.0, 0.976, 0.895), true],
		["stones", 1.0, 1.2, 2.2, GREY, false],
	],
	WorldData.Biome.DESERT: [
		["rocks", 2.0, 1.6, 3.2, DRY, true],
		["rocks_tall", 0.8, 1.6, 2.8, DRY, true],
		["stones", 3.0, 1.2, 2.4, DRY, false],
		["plant", 0.6, 1.4, 2.2, DRY, false],
		["trunk", 0.3, 1.0, 1.6, DRY, false],
	],
	WorldData.Biome.MOUNTAIN: [
		["rocks_high", 2.5, 1.6, 3.4, GREY, true],
		["rocks_tall", 2.0, 1.6, 3.0, GREY, true],
		["pine", 1.5, 2.2, 3.2, COLD, true],
		["stones", 4.0, 1.2, 2.4, GREY, false],
		["grass", 2.0, 1.8, 2.6, COLD, false],
	],
	WorldData.Biome.TUNDRA: [
		["grass", 6.0, 1.8, 2.8, Color(0.91, 0.908, 0.77), false],
		["stones", 3.0, 1.2, 2.2, GREY, false],
		["pine_crooked", 0.8, 2.0, 2.8, COLD, true],
		["rocks", 0.8, 1.4, 2.6, GREY, true],
	],
	WorldData.Biome.ICE: [
		["stones", 0.6, 1.2, 2.0, WHITE_BLUE, false],
	],
	WorldData.Biome.BEACH: [
		["plant", 1.5, 1.6, 2.6, GREEN, false],
		["grass", 2.0, 1.6, 2.4, DRY, false],
		["stones", 1.0, 1.0, 1.8, DRY, false],
		["tree", 0.4, 2.0, 2.8, GREEN, true],
	],
}


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
