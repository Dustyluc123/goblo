// Package data embute no binário os arquivos usados pelo servidor, para que ele rode de
// qualquer pasta sem depender de caminhos no disco.
package data

import "embed"

// NaturalEarth contém ne_110m_land.geojson e ne_110m_admin_0_countries.geojson
// (Natural Earth, escala 1:110m, domínio público). Veja docs/DADOS.md.
//
//go:embed naturalearth/*.geojson
var NaturalEarth embed.FS

// Game contém o conteúdo do jogo que dá para balancear sem programar: itens, receitas,
// níveis da casa e objetos interativos por bioma. Veja docs/CONTEUDO.md.
//
//go:embed game/*.json
var Game embed.FS
