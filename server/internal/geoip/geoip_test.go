package geoip

import (
	"net/netip"
	"os"
	"testing"
)

// testdata/amostra.csv tem linhas reais da base DB-IP (IP to Country Lite, outubro de
// 2026, CC BY 4.0) que cobrem os IPs abaixo.
func TestCountryFromKnownIPs(t *testing.T) {
	db, err := LoadFile("testdata/amostra.csv")
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string]string{
		"8.8.8.8":                 "US", // DNS do Google
		"200.147.67.142":          "BR", // UOL
		"177.71.128.1":            "BR",
		"81.2.69.160":             "GB",
		"1.1.1.1":                 "AU", // a DB-IP registra a faixa da Cloudflare na Austrália
		"2800:3f0:4001:80f::200e": "BR", // IPv6
		"::ffff:200.147.67.142":   "BR", // IPv4 mapeado em IPv6
		"9.9.9.9":                 "",   // fora da amostra
	}
	for ip, want := range cases {
		if got := db.Country(netip.MustParseAddr(ip)); got != want {
			t.Errorf("%s: %q, esperado %q", ip, got, want)
		}
	}
}

func TestLocalIPsHaveNoCountry(t *testing.T) {
	db, err := LoadFile("testdata/amostra.csv")
	if err != nil {
		t.Fatal(err)
	}
	for _, ip := range []string{"127.0.0.1", "::1", "192.168.0.10", "10.1.2.3", "172.16.5.4", "fe80::1"} {
		a := netip.MustParseAddr(ip)
		if !IsLocal(a) || db.Country(a) != "" {
			t.Errorf("%s deveria ser local e sem país", ip)
		}
	}
	var none *DB // sem base carregada, tudo cai no fallback
	if none.Country(netip.MustParseAddr("8.8.8.8")) != "" || none.Ranges() != 0 {
		t.Fatal("base nil deveria responder vazio")
	}
}

func TestRegionFromLocale(t *testing.T) {
	cases := map[string]string{
		"pt_BR": "BR", "en-US": "US", "pt_BR.UTF-8": "BR", "fr": "", "zh_Hans_CN": "CN", "": "", "es_419": "",
	}
	for in, want := range cases {
		if got := RegionFromLocale(in); got != want {
			t.Errorf("%q: %q, esperado %q", in, got, want)
		}
	}
}

// Com a base completa baixada (./scripts/baixar-dados.sh), confere também o arquivo real.
func TestFullDatabaseIfPresent(t *testing.T) {
	path := "../../data/raw/dbip-country-lite.csv.gz"
	if _, err := os.Stat(path); err != nil {
		t.Skip("base completa não baixada")
	}
	db, err := LoadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if db.Ranges() < 100000 {
		t.Fatalf("só %d faixas", db.Ranges())
	}
	if got := db.Country(netip.MustParseAddr("200.147.67.142")); got != "BR" {
		t.Fatalf("UOL: %q", got)
	}
}
