package httpapi

import (
	"math"
	"net/http"
)

// borders manda, para cada célula pedida, o país dela inteira ou os segmentos de fronteira
// que passam perto (ADR 0031). Cada segmento vai como seis números:
// lat1, lon1, lat2, lon2, índice do país em "countries" e 1 se separa dois países (linha no
// chão) ou 0 se é costa. O país fica à esquerda de 1 → 2.
//
//	GET /borders?cells=1,2,3 → {"countries": [{"code","name"}], "cells": [{"cell", "country"} | {"cell", "segs"}]}
func (s *Server) borders(w http.ResponseWriter, r *http.Request) {
	cells, err := parseCells(r)
	if err != nil {
		writeError(w, s, err)
		return
	}
	type country struct {
		Code string `json:"code"`
		Name string `json:"name"`
	}
	type cellOut struct {
		Cell    int       `json:"cell"`
		Country string    `json:"country,omitempty"`
		Segs    []float64 `json:"segs,omitempty"`
	}
	var countries []country
	index := map[int]int{}
	ref := func(ci int) int {
		if i, ok := index[ci]; ok {
			return i
		}
		c := s.Geo.Countries[ci]
		index[ci] = len(countries)
		countries = append(countries, country{c.Code, c.Name})
		return index[ci]
	}
	out := make([]cellOut, 0, len(cells))
	for _, cell := range cells {
		if cell >= len(s.World.Cells) {
			continue
		}
		cb := s.Geo.CellBorders(s.World, cell)
		co := cellOut{Cell: cell, Country: cb.Country}
		if len(cb.Segs) > 0 {
			co.Segs = make([]float64, 0, len(cb.Segs)*6)
			for _, sg := range cb.Segs {
				shared := 0.0
				if sg.Shared {
					shared = 1
				}
				co.Segs = append(co.Segs, r4(sg.A[1]), r4(sg.A[0]), r4(sg.B[1]), r4(sg.B[0]), float64(ref(sg.Country)), shared)
			}
		} else if cb.Country != "" {
			ci, _ := s.Geo.CountryIndex(cb.Country)
			ref(ci)
		}
		out = append(out, co)
	}
	if countries == nil {
		countries = []country{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"countries": countries, "cells": out})
}

func r4(x float64) float64 { return math.Round(x*1e4) / 1e4 }
