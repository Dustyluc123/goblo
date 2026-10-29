// Package data embute no binário os arquivos usados pelo servidor, para que ele rode de
// qualquer pasta sem depender de caminhos no disco.
package data

import "embed"

// NaturalEarth contém a terra (1:110m), os países e as capitais (1:50m, filtrados por
// cmd/filtra-paises) e as regiões dos biomas (Natural Earth, domínio público). Veja
// docs/DADOS.md.
//
//go:embed naturalearth/*.geojson naturalearth/*.json
var NaturalEarth embed.FS

// Game contém o conteúdo do jogo que dá para balancear sem programar: itens, receitas,
// níveis da casa e objetos interativos por bioma. Veja docs/CONTEUDO.md.
//
//go:embed game/*.json
var Game embed.FS
