// Package realtime é a camada em tempo real do Goblo (fase 3, ADR 0039): uma conexão
// WebSocket por jogador, movimento validado no servidor, área de interesse, chat, emotes e
// os eventos do mundo (árvore sacudida, lote mudou) para quem está perto.
//
// O protocolo está em docs/PROTOCOLO.md. Movimento vai em binário (pequeno e frequente);
// o resto, em JSON enxuto.
package realtime

import (
	"encoding/binary"
	"errors"
	"math"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Tipos das mensagens binárias (primeiro byte).
const (
	MsgMove       = 1 // cliente → servidor: minha posição
	MsgSnapshot   = 2 // servidor → cliente: posição dos outros
	MsgCorrection = 3 // servidor → cliente: volte para cá
)

// Tamanhos das mensagens binárias.
const (
	MoveSize       = 19
	SnapshotHeader = 6
	SnapshotEntry  = 20
	CorrectionSize = 16
)

// Bits de Flags.
const (
	FlagOnFloor = 1 << 0
	FlagRunning = 1 << 1
	FlagNoclip  = 1 << 2 // voo do modo dev
	FlagPhoto   = 1 << 3
)

// Motivos de correção.
const (
	ReasonSpeed    = 1
	ReasonOcean    = 2
	ReasonBorder   = 3
	ReasonHeight   = 4
	ReasonTeleport = 5 // teleporte recusado
)

// Move é a posição que o cliente manda.
type Move struct {
	Seq   uint16
	Pos   world.Vec3
	Yaw   float64 // radianos no plano tangente (0 = leste, anti-horário; ver Facing)
	Anim  uint8   // 0 parado, 1 andando, 2 correndo, 3 no ar, 4 ação, 5 pegando, 6 pose de foto, 7 sentado
	Flags uint8
}

var errShort = errors.New("mensagem curta")

// EncodeMove monta a mensagem de movimento (19 bytes).
func EncodeMove(m Move) []byte {
	b := make([]byte, MoveSize)
	b[0] = MsgMove
	binary.LittleEndian.PutUint16(b[1:], m.Seq)
	putVec(b[3:], m.Pos)
	binary.LittleEndian.PutUint16(b[15:], uint16(yawToI16(m.Yaw)))
	b[17] = m.Anim
	b[18] = m.Flags
	return b
}

// DecodeMove lê a mensagem de movimento.
func DecodeMove(b []byte) (Move, error) {
	if len(b) < MoveSize || b[0] != MsgMove {
		return Move{}, errShort
	}
	m := Move{Seq: binary.LittleEndian.Uint16(b[1:]), Pos: getVec(b[3:]),
		Yaw: i16ToYaw(int16(binary.LittleEndian.Uint16(b[15:]))), Anim: b[17], Flags: b[18]}
	if !finite(m.Pos) {
		return Move{}, errors.New("posição inválida")
	}
	return m, nil
}

// Entry é um jogador numa foto do servidor.
type Entry struct {
	ID    int32
	Pos   world.Vec3
	Yaw   float64
	Anim  uint8
	Flags uint8
}

// EncodeSnapshot monta a foto: tempo do servidor (ms) e até 255 jogadores.
func EncodeSnapshot(serverMs uint32, list []Entry) []byte {
	if len(list) > 255 {
		list = list[:255]
	}
	b := make([]byte, SnapshotHeader+SnapshotEntry*len(list))
	b[0] = MsgSnapshot
	binary.LittleEndian.PutUint32(b[1:], serverMs)
	b[5] = byte(len(list))
	for i, e := range list {
		o := SnapshotHeader + SnapshotEntry*i
		binary.LittleEndian.PutUint32(b[o:], uint32(e.ID))
		putVec(b[o+4:], e.Pos)
		binary.LittleEndian.PutUint16(b[o+16:], uint16(yawToI16(e.Yaw)))
		b[o+18] = e.Anim
		b[o+19] = e.Flags
	}
	return b
}

// DecodeSnapshot lê a foto (bots e testes).
func DecodeSnapshot(b []byte) (uint32, []Entry, error) {
	if len(b) < SnapshotHeader || b[0] != MsgSnapshot {
		return 0, nil, errShort
	}
	n := int(b[5])
	if len(b) < SnapshotHeader+SnapshotEntry*n {
		return 0, nil, errShort
	}
	out := make([]Entry, n)
	for i := range out {
		o := SnapshotHeader + SnapshotEntry*i
		out[i] = Entry{ID: int32(binary.LittleEndian.Uint32(b[o:])), Pos: getVec(b[o+4:]),
			Yaw: i16ToYaw(int16(binary.LittleEndian.Uint16(b[o+16:]))), Anim: b[o+18], Flags: b[o+19]}
	}
	return binary.LittleEndian.Uint32(b[1:]), out, nil
}

// EncodeCorrection manda o jogador de volta para pos.
func EncodeCorrection(seq uint16, pos world.Vec3, reason byte) []byte {
	b := make([]byte, CorrectionSize)
	b[0] = MsgCorrection
	binary.LittleEndian.PutUint16(b[1:], seq)
	putVec(b[3:], pos)
	b[15] = reason
	return b
}

// DecodeCorrection lê a correção (bots e testes).
func DecodeCorrection(b []byte) (uint16, world.Vec3, byte, error) {
	if len(b) < CorrectionSize || b[0] != MsgCorrection {
		return 0, world.Vec3{}, 0, errShort
	}
	return binary.LittleEndian.Uint16(b[1:]), getVec(b[3:]), b[15], nil
}

func putVec(b []byte, v world.Vec3) {
	binary.LittleEndian.PutUint32(b[0:], math.Float32bits(float32(v.X)))
	binary.LittleEndian.PutUint32(b[4:], math.Float32bits(float32(v.Y)))
	binary.LittleEndian.PutUint32(b[8:], math.Float32bits(float32(v.Z)))
}

func getVec(b []byte) world.Vec3 {
	return world.Vec3{
		X: float64(math.Float32frombits(binary.LittleEndian.Uint32(b[0:]))),
		Y: float64(math.Float32frombits(binary.LittleEndian.Uint32(b[4:]))),
		Z: float64(math.Float32frombits(binary.LittleEndian.Uint32(b[8:]))),
	}
}

func yawToI16(y float64) int16 {
	y = math.Remainder(y, 2*math.Pi)
	return int16(math.Round(y * 10000))
}

func i16ToYaw(v int16) float64 { return float64(v) / 10000 }

func finite(v world.Vec3) bool {
	for _, x := range []float64{v.X, v.Y, v.Z} {
		if math.IsNaN(x) || math.IsInf(x, 0) || math.Abs(x) > 1e5 {
			return false
		}
	}
	return true
}

// Tangent devolve o leste e o norte locais no ponto (a mesma conta do cliente): é neles que
// o yaw é medido.
func Tangent(pos world.Vec3) (east, north world.Vec3) {
	up := pos.Normalize()
	ref := world.Vec3{Y: 1}
	if math.Abs(up.Y) > 0.999 {
		ref = world.Vec3{Z: 1}
	}
	east = ref.Cross(up).Normalize()
	north = up.Cross(east)
	return
}

// Facing é a direção (no chão) para onde o jogador olha.
func Facing(pos world.Vec3, yaw float64) world.Vec3 {
	e, n := Tangent(pos)
	return e.Scale(math.Cos(yaw)).Add(n.Scale(math.Sin(yaw)))
}
