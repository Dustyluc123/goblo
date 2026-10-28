package world

import (
	"fmt"
	"math"
)

// Biome é o bioma de uma célula. Os valores numéricos fazem parte do formato binário
// do mundo: só acrescente no fim.
type Biome uint8

const (
	BiomeOcean Biome = iota
	BiomeBeach
	BiomeTropicalForest
	BiomeForest
	BiomeGrassland
	BiomeDesert
	BiomeMountain
	BiomeTundra
	BiomeIce
)

// BiomeNames lista os nomes na ordem dos valores.
var BiomeNames = []string{
	"ocean", "beach", "tropical_forest", "forest", "grassland", "desert", "mountain", "tundra", "ice",
}

func (b Biome) String() string {
	if int(b) < len(BiomeNames) {
		return BiomeNames[b]
	}
	return fmt.Sprintf("biome(%d)", b)
}

func (b Biome) MarshalText() ([]byte, error) { return []byte(b.String()), nil }

func (b *Biome) UnmarshalText(text []byte) error {
	for i, n := range BiomeNames {
		if n == string(text) {
			*b = Biome(i)
			return nil
		}
	}
	return fmt.Errorf("bioma desconhecido: %q", text)
}

// Alturas (em unidades do jogo, acima do nível do mar). O personagem sobe 0,4 andando e
// pula 1,3: praia → campo se anda, campo → colina se pula, e montanha se escala pulando
// degrau por degrau.
const (
	heightBeach        = 0.4
	heightLowland      = 0.8
	heightHill         = 0.6 // somado às terras baixas em colinas e dunas
	heightMountainBase = 1.4
	heightMountainStep = 1.2
	mountainMaxRings   = 8
	heightIce          = 1.4
	heightIceInland    = 0.6 // somado ao gelo longe da costa
)

// baseBiome decide o bioma de uma célula de terra pelo centro, antes de olhar os vizinhos.
// Ordem: gelo > montanha > deserto > tundra > tropical > campo > regras de latitude.
func baseBiome(lat float64, country string, hits regionHits) Biome {
	alat := math.Abs(lat)
	switch {
	case country == "ATA" || country == "GRL" || lat > 80:
		return BiomeIce
	case hits[regionMountain]:
		return BiomeMountain
	case hits[regionDesert]:
		return BiomeDesert
	case hits[regionTundra] || lat > 66 || lat < -50:
		return BiomeTundra
	case hits[regionTropical]:
		return BiomeTropicalForest
	case hits[regionGrassland]:
		return BiomeGrassland
	case alat < 12:
		return BiomeTropicalForest
	case alat < 35:
		return BiomeGrassland
	default:
		return BiomeForest
	}
}

// assignBiomes completa os biomas e as alturas de todas as células, usando a vizinhança:
// praias na costa quente, anéis de montanha e de gelo e manchas de colinas.
func assignBiomes(cells []Cell, base []Biome, hills []bool) {
	n := len(cells)
	coastal := make([]bool, n)
	for i := range cells {
		if cells[i].Terrain != Land {
			continue
		}
		for _, nb := range cells[i].Neighbors {
			if cells[nb].Terrain == Ocean {
				coastal[i] = true
				break
			}
		}
	}

	biomes := make([]Biome, n)
	copy(biomes, base)
	for i := range cells {
		switch biomes[i] {
		case BiomeTropicalForest, BiomeForest, BiomeGrassland, BiomeDesert:
			if coastal[i] && math.Abs(cells[i].Lat) < 42 {
				biomes[i] = BiomeBeach
			}
		case BiomeIce:
			if coastal[i] && cells[i].Country == "GRL" {
				biomes[i] = BiomeTundra // a costa da Groenlândia não é toda gelo
			}
		}
	}

	mountainRing := ringDistance(cells, biomes, BiomeMountain)
	iceRing := ringDistance(cells, biomes, BiomeIce)
	for i := range cells {
		b := biomes[i]
		h := 0.0
		switch b {
		case BiomeOcean:
		case BiomeBeach:
			h = heightBeach
		case BiomeMountain:
			h = heightMountainBase + heightMountainStep*float64(min(mountainRing[i], mountainMaxRings)-1)
		case BiomeIce:
			h = heightIce
			if iceRing[i] >= 2 {
				h += heightIceInland
			}
		default:
			h = heightLowland
			if hills[i] {
				h += heightHill
			}
		}
		cells[i].Biome = b
		cells[i].Height = h
	}
}

// ringDistance devolve, para cada célula do bioma b, a distância em células até a borda
// do bioma (1 = encosta em outro bioma). Células de outros biomas ficam com 0.
func ringDistance(cells []Cell, biomes []Biome, b Biome) []int {
	dist := make([]int, len(cells))
	var queue []int
	for i := range cells {
		if biomes[i] != b {
			continue
		}
		for _, nb := range cells[i].Neighbors {
			if biomes[nb] != b {
				dist[i] = 1
				queue = append(queue, i)
				break
			}
		}
	}
	for len(queue) > 0 {
		cur := queue[0]
		queue = queue[1:]
		for _, nb := range cells[cur].Neighbors {
			if biomes[nb] == b && dist[nb] == 0 {
				dist[nb] = dist[cur] + 1
				queue = append(queue, nb)
			}
		}
	}
	return dist
}

// isHilly diz se uma célula de terras baixas vira colina (ou duna): dentro de uma
// cordilheira pequena, ou numa mancha de ruído.
func isHilly(center Vec3, hits regionHits) bool {
	return hits[regionHills] || noise3(center.Scale(9)) > 0.68
}
