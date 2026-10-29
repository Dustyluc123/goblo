package game

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

// Limites do apelido.
const (
	NicknameMin = 3
	NicknameMax = 16
)

// blockedParts são pedaços que não podem aparecer em nenhum lugar do apelido.
var blockedParts = []string{
	"porra", "caralh", "merda", "putari", "buceta", "boceta", "viado", "foder", "fodase",
	"cacete", "piroca", "bosta", "arrombad", "cuzao", "vagabund", "xoxota", "punheta",
	"boquete", "estupr", "pedofil", "fuck", "shit", "bitch", "nigg", "cunt",
	"whore", "slut", "nazi", "hitler", "retard", "fagg", "pussy", "asshole", "penis",
	"vadia", "piranha", "corno", "babaca", "otario", "imbecil", "idiota", "retardad",
}

// blockedWords só são barradas como palavra inteira (são curtas e aparecem dentro de
// palavras inocentes, como "cu" em "curió").
var blockedWords = []string{"cu", "pau", "fdp", "vsf", "pqp", "tnc", "krl", "crl", "ass", "sex", "puta", "puto", "putas", "putos"}

// ValidateNickname confere o apelido: tamanho, caracteres e filtro de palavrões.
// Devolve o apelido limpo (sem espaços nas pontas nem espaços duplos).
func ValidateNickname(raw string) (string, error) {
	nick := strings.Join(strings.Fields(raw), " ")
	n := utf8.RuneCountInString(nick)
	if n < NicknameMin || n > NicknameMax {
		return "", ErrNicknameInvalid.with("O apelido precisa ter de %d a %d letras.", NicknameMin, NicknameMax)
	}
	for _, r := range nick {
		if !(unicode.IsLetter(r) || unicode.IsDigit(r) || r == ' ' || r == '_' || r == '-') {
			return "", ErrNicknameInvalid.with("Use só letras, números, espaço, _ e -.")
		}
	}
	if IsProfane(nick) {
		return "", ErrNicknameInvalid.with("Esse apelido não é permitido. Que tal outro?")
	}
	return nick, nil
}

// IsProfane diz se o texto tem palavrão, mesmo disfarçado (acentos, números no lugar de
// letras, separadores: "P0rr@", "m.e.r.d.a").
func IsProfane(s string) bool {
	words := strings.FieldsFunc(normalizeLeet(s), func(r rune) bool { return r == ' ' || r == '_' || r == '-' })
	joined := strings.Join(words, "")
	squeezed := squeeze(joined)
	for _, p := range blockedParts {
		if strings.Contains(joined, p) || strings.Contains(squeezed, p) {
			return true
		}
	}
	for _, w := range words {
		for _, b := range blockedWords {
			if w == b || squeeze(w) == b {
				return true
			}
		}
	}
	return false
}

var leet = map[rune]rune{'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's', '!': 'i'}

var accents = map[rune]rune{
	'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e',
	'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
	'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n',
}

// normalizeLeet passa para minúsculas, tira acentos, troca números por letras e remove
// pontuação (mantém espaço, _ e - como separadores).
func normalizeLeet(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if a, ok := accents[r]; ok {
			r = a
		}
		if l, ok := leet[r]; ok {
			r = l
		}
		switch {
		case r >= 'a' && r <= 'z', r == ' ', r == '_', r == '-':
			b.WriteRune(r)
		}
	}
	return b.String()
}

// squeeze junta letras repetidas ("merrrda" → "merda").
func squeeze(s string) string {
	var b strings.Builder
	var last rune
	for _, r := range s {
		if r != last {
			b.WriteRune(r)
		}
		last = r
	}
	return b.String()
}
