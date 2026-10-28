package world

import "math"

// Vec3 é um vetor 3D. No Goblo, o planeta fica na origem e o eixo Y aponta para o polo norte
// (mesma convenção do Godot). Veja LatLonToVec para a convenção completa.
type Vec3 struct{ X, Y, Z float64 }

func (a Vec3) Add(b Vec3) Vec3      { return Vec3{a.X + b.X, a.Y + b.Y, a.Z + b.Z} }
func (a Vec3) Sub(b Vec3) Vec3      { return Vec3{a.X - b.X, a.Y - b.Y, a.Z - b.Z} }
func (a Vec3) Scale(s float64) Vec3 { return Vec3{a.X * s, a.Y * s, a.Z * s} }
func (a Vec3) Dot(b Vec3) float64   { return a.X*b.X + a.Y*b.Y + a.Z*b.Z }
func (a Vec3) Len() float64         { return math.Sqrt(a.Dot(a)) }

func (a Vec3) Cross(b Vec3) Vec3 {
	return Vec3{a.Y*b.Z - a.Z*b.Y, a.Z*b.X - a.X*b.Z, a.X*b.Y - a.Y*b.X}
}

func (a Vec3) Normalize() Vec3 {
	l := a.Len()
	if l == 0 {
		return a
	}
	return a.Scale(1 / l)
}

// LatLonToVec converte latitude/longitude (graus) em vetor unitário.
//
//	x = cos(lat)·sin(lon), y = sin(lat), z = cos(lat)·cos(lon)
//
// Assim, (0°, 0°) fica em +Z, (0°, 90°L) em +X e o polo norte em +Y. Olhando o globo de fora,
// com o norte para cima, o leste fica à direita (o mapa não sai espelhado).
func LatLonToVec(lat, lon float64) Vec3 {
	la, lo := lat*math.Pi/180, lon*math.Pi/180
	return Vec3{math.Cos(la) * math.Sin(lo), math.Sin(la), math.Cos(la) * math.Cos(lo)}
}

// VecToLatLon faz o caminho inverso de LatLonToVec. O vetor não precisa ser unitário.
func VecToLatLon(v Vec3) (lat, lon float64) {
	v = v.Normalize()
	lat = math.Asin(math.Max(-1, math.Min(1, v.Y))) * 180 / math.Pi
	lon = math.Atan2(v.X, v.Z) * 180 / math.Pi
	return lat, lon
}
