// Package geoip descobre o país de um IP com a base gratuita "IP to Country Lite" da
// DB-IP (https://db-ip.com, licença CC BY 4.0). O IP só é usado para a consulta: não é
// guardado nem registrado em log.
package geoip

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"net/netip"
	"os"
	"sort"
	"strings"
)

// Attribution é o crédito exigido pela licença CC BY 4.0 da DB-IP.
const Attribution = "IP Geolocation by DB-IP (https://db-ip.com), CC BY 4.0"

// DB é a base carregada na memória: faixas ordenadas de IPv4 e IPv6 → código ISO A2.
type DB struct {
	v4 []rangeV4
	v6 []rangeV6
}

type rangeV4 struct {
	start, end uint32
	cc         [2]byte
}

type rangeV6 struct {
	start, end [16]byte
	cc         [2]byte
}

// LoadFile lê o CSV da DB-IP (pode estar em .gz).
func LoadFile(path string) (*DB, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return Load(f)
}

// Load lê o CSV "ip_inicial,ip_final,país" (com ou sem gzip).
func Load(r io.Reader) (*DB, error) {
	br := bufio.NewReaderSize(r, 1<<16)
	if magic, _ := br.Peek(2); bytes.Equal(magic, []byte{0x1f, 0x8b}) {
		gz, err := gzip.NewReader(br)
		if err != nil {
			return nil, err
		}
		defer gz.Close()
		br = bufio.NewReaderSize(gz, 1<<16)
	}
	cr := csv.NewReader(br)
	cr.FieldsPerRecord = 3
	cr.ReuseRecord = true
	db := &DB{}
	for line := 1; ; line++ {
		rec, err := cr.Read()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("geoip linha %d: %w", line, err)
		}
		start, err1 := netip.ParseAddr(rec[0])
		end, err2 := netip.ParseAddr(rec[1])
		if err1 != nil || err2 != nil || len(rec[2]) != 2 {
			return nil, fmt.Errorf("geoip linha %d: registro inválido", line)
		}
		cc := [2]byte{rec[2][0], rec[2][1]}
		if start.Is4() {
			db.v4 = append(db.v4, rangeV4{u32(start), u32(end), cc})
		} else {
			db.v6 = append(db.v6, rangeV6{start.As16(), end.As16(), cc})
		}
	}
	sort.Slice(db.v4, func(i, j int) bool { return db.v4[i].start < db.v4[j].start })
	sort.Slice(db.v6, func(i, j int) bool { return bytes.Compare(db.v6[i].start[:], db.v6[j].start[:]) < 0 })
	return db, nil
}

// Ranges diz quantas faixas foram carregadas.
func (db *DB) Ranges() int {
	if db == nil {
		return 0
	}
	return len(db.v4) + len(db.v6)
}

func u32(a netip.Addr) uint32 {
	b := a.As4()
	return uint32(b[0])<<24 | uint32(b[1])<<16 | uint32(b[2])<<8 | uint32(b[3])
}

// IsLocal diz se o IP é da própria máquina ou de rede privada (não dá para saber o país).
func IsLocal(ip netip.Addr) bool {
	return !ip.IsValid() || ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified()
}

// Country devolve o código ISO A2 do IP ("" se não souber: base ausente, IP local ou
// desconhecido).
func (db *DB) Country(ip netip.Addr) string {
	if db == nil || IsLocal(ip) {
		return ""
	}
	ip = ip.Unmap()
	var cc [2]byte
	if ip.Is4() {
		x := u32(ip)
		i := sort.Search(len(db.v4), func(i int) bool { return db.v4[i].start > x }) - 1
		if i < 0 || x > db.v4[i].end {
			return ""
		}
		cc = db.v4[i].cc
	} else {
		x := ip.As16()
		i := sort.Search(len(db.v6), func(i int) bool { return bytes.Compare(db.v6[i].start[:], x[:]) > 0 }) - 1
		if i < 0 || bytes.Compare(x[:], db.v6[i].end[:]) > 0 {
			return ""
		}
		cc = db.v6[i].cc
	}
	code := string(cc[:])
	if code == "ZZ" {
		return ""
	}
	return code
}

// RegionFromLocale tira o país do idioma do sistema: "pt_BR" → "BR", "en-US" → "US",
// "pt_BR.UTF-8" → "BR". Sem região ("pt"), devolve "".
func RegionFromLocale(locale string) string {
	locale, _, _ = strings.Cut(locale, ".")
	locale, _, _ = strings.Cut(locale, "@")
	parts := strings.FieldsFunc(locale, func(r rune) bool { return r == '_' || r == '-' })
	for _, p := range parts[min(1, len(parts)):] {
		if len(p) == 2 {
			return strings.ToUpper(p)
		}
	}
	return ""
}
