// Package data embute no binário os arquivos geográficos usados pelo servidor,
// para que ele rode de qualquer pasta sem depender de caminhos no disco.
package data

import "embed"

// NaturalEarth contém ne_110m_land.geojson e ne_110m_admin_0_countries.geojson
// (Natural Earth, escala 1:110m, domínio público). Veja docs/DADOS.md.
//
//go:embed naturalearth/*.geojson
var NaturalEarth embed.FS
