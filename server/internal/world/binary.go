package world

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"sort"
)

// Formato binário do mundo (o que o cliente baixa). Tudo little-endian, com os dados
// das células em blocos (um array por campo), o que comprime melhor e o cliente lê
// cada bloco de uma vez.
//
//	"GOBW"                  4 bytes, assinatura
//	formato                 u16 (BinaryFormatVersion)
//	reservado               u16 (0)
//	frequência              u32
//	raio                    f32
//	N (células)             u32
//	C (países)              u16, depois C × { código: 3 bytes ASCII, len: u8, nome: UTF-8 }
//	B (biomas)              u8,  depois B × { len: u8, nome: ASCII } na ordem dos valores
//	centros                 N × 3 × f32 (vetor unitário)
//	quantidade de vizinhos  N × u8 (5 ou 6)
//	vizinhos                N × 6 × u32 (0xFFFFFFFF onde não há o 6º vizinho)
//	bioma                   N × u8
//	país                    N × u16 (índice na tabela de países, 0xFFFF = nenhum)
//	altura                  N × f32
//
// Lat/lon e os cantos dos polígonos não vão no arquivo: o cliente calcula a partir dos
// centros e dos vizinhos (canto k = normalize(centro + vizinho[k-1] + vizinho[k])).
const BinaryFormatVersion = 1

var binaryMagic = [4]byte{'G', 'O', 'B', 'W'}

const noNeighbor = math.MaxUint32
const noCountry = math.MaxUint16

// MarshalBinary codifica o mundo no formato binário.
func (w *World) MarshalBinary() ([]byte, error) {
	n := len(w.Cells)
	codes := make([]string, 0, len(w.Countries))
	for code := range w.Countries {
		if len(code) != 3 {
			return nil, fmt.Errorf("código de país com tamanho inesperado: %q", code)
		}
		codes = append(codes, code)
	}
	sort.Strings(codes)
	index := make(map[string]uint16, len(codes))
	for i, c := range codes {
		index[c] = uint16(i)
	}

	var buf bytes.Buffer
	buf.Grow(64 + n*45)
	put := func(v any) { _ = binary.Write(&buf, binary.LittleEndian, v) }
	buf.Write(binaryMagic[:])
	put(uint16(BinaryFormatVersion))
	put(uint16(0))
	put(uint32(w.Frequency))
	put(float32(w.Radius))
	put(uint32(n))
	put(uint16(len(codes)))
	for _, c := range codes {
		name := w.Countries[c]
		if len(name) > 255 {
			name = name[:255]
		}
		buf.WriteString(c)
		buf.WriteByte(byte(len(name)))
		buf.WriteString(name)
	}
	buf.WriteByte(byte(len(BiomeNames)))
	for _, name := range BiomeNames {
		buf.WriteByte(byte(len(name)))
		buf.WriteString(name)
	}

	centers := make([]float32, 0, 3*n)
	counts := make([]uint8, n)
	neighbors := make([]uint32, 0, 6*n)
	biomes := make([]uint8, n)
	countries := make([]uint16, n)
	heights := make([]float32, n)
	for i, c := range w.Cells {
		centers = append(centers, float32(c.Center[0]), float32(c.Center[1]), float32(c.Center[2]))
		if len(c.Neighbors) > 6 {
			return nil, errors.New("célula com mais de 6 vizinhos")
		}
		counts[i] = uint8(len(c.Neighbors))
		for k := 0; k < 6; k++ {
			if k < len(c.Neighbors) {
				neighbors = append(neighbors, uint32(c.Neighbors[k]))
			} else {
				neighbors = append(neighbors, noNeighbor)
			}
		}
		biomes[i] = uint8(c.Biome)
		countries[i] = noCountry
		if c.Country != "" {
			countries[i] = index[c.Country]
		}
		heights[i] = float32(c.Height)
	}
	put(centers)
	put(counts)
	put(neighbors)
	put(biomes)
	put(countries)
	put(heights)
	return buf.Bytes(), nil
}

// BinaryCell é uma célula lida do formato binário (usado nos testes de ida e volta).
type BinaryCell struct {
	Center    [3]float32
	Neighbors []int
	Biome     Biome
	Country   string
	Height    float32
}

// UnmarshalBinaryCells decodifica o formato binário. Serve de referência para o leitor
// do cliente (client/scripts/world_data.gd) e para os testes.
func UnmarshalBinaryCells(data []byte) (frequency int, radius float32, cells []BinaryCell, countries map[string]string, err error) {
	r := bytes.NewReader(data)
	get := func(v any) {
		if err == nil {
			err = binary.Read(r, binary.LittleEndian, v)
		}
	}
	var magic [4]byte
	var version, reserved uint16
	var freq, n uint32
	get(&magic)
	get(&version)
	get(&reserved)
	get(&freq)
	get(&radius)
	get(&n)
	if err != nil {
		return
	}
	if magic != binaryMagic || version != BinaryFormatVersion {
		err = fmt.Errorf("formato desconhecido: %q v%d", magic, version)
		return
	}
	var nc uint16
	get(&nc)
	codes := make([]string, nc)
	countries = map[string]string{}
	for i := range codes {
		code := make([]byte, 3)
		var l uint8
		get(code)
		get(&l)
		name := make([]byte, l)
		get(name)
		codes[i] = string(code)
		countries[codes[i]] = string(name)
	}
	var nb uint8
	get(&nb)
	for i := 0; i < int(nb); i++ {
		var l uint8
		get(&l)
		skip := make([]byte, l)
		get(skip)
	}
	centers := make([]float32, 3*n)
	counts := make([]uint8, n)
	neigh := make([]uint32, 6*n)
	biomes := make([]uint8, n)
	cidx := make([]uint16, n)
	heights := make([]float32, n)
	get(centers)
	get(counts)
	get(neigh)
	get(biomes)
	get(cidx)
	get(heights)
	if err != nil {
		return
	}
	cells = make([]BinaryCell, n)
	for i := range cells {
		c := BinaryCell{Biome: Biome(biomes[i]), Height: heights[i]}
		copy(c.Center[:], centers[3*i:3*i+3])
		for k := 0; k < int(counts[i]); k++ {
			c.Neighbors = append(c.Neighbors, int(neigh[6*i+k]))
		}
		if cidx[i] != noCountry {
			c.Country = codes[cidx[i]]
		}
		cells[i] = c
	}
	return int(freq), radius, cells, countries, nil
}
