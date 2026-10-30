package game

import (
	"context"
	"time"
)

// Player é um jogador. Não há login: o cliente guarda um token secreto e o servidor só
// guarda o hash dele.
type Player struct {
	ID        int64
	Nickname  string
	Country   string // ISO A3
	TokenHash string
	CreatedAt time.Time
	Fake      bool   // criado pelo modo dev ("vizinhos falsos")
	Character string // um dos personagens de rules.json ("" = o padrão do cliente)
}

// Lot é um lote ocupado e a casa dele.
type Lot struct {
	ID           int64 // célula × 4 + posição (LotID)
	Cell         int
	Slot         int
	OwnerID      int64
	HouseLevel   int       // nível pronto (0 = sem casa)
	PendingLevel int       // nível em obra (0 = nenhuma obra)
	ReadyAt      time.Time // quando a obra fica pronta
	HouseX       int
	HouseY       int
	HouseRot     int
	PendingX     int // canto da casa em obra (a casa melhorada pode crescer e se deslocar)
	PendingY     int
}

// Stack é um item do inventário com a quantidade. Order guarda a ordem de chegada.
type Stack struct {
	Item  string
	Count int
	Order int64
}

// Placement é um objeto colocado num lote, na grade de quadradinhos.
type Placement struct {
	ID    int64
	LotID int64
	Item  string
	X, Y  int
	Rot   int // 0–3, de 90 em 90 graus
}

// Collection conta quantas vezes um jogador fez uma ação num objeto num dia.
type Collection struct {
	ObjectID int64
	Action   string
	Count    int
}

// PlayerRepository guarda os jogadores.
type PlayerRepository interface {
	CreatePlayer(ctx context.Context, p *Player) error // preenche p.ID; ErrNicknameTaken se o apelido existe
	PlayerByTokenHash(ctx context.Context, hash string) (*Player, error)
	PlayerByID(ctx context.Context, id int64) (*Player, error)
	PlayersByIDs(ctx context.Context, ids []int64) (map[int64]*Player, error)
	UpdatePlayerCountry(ctx context.Context, id int64, country string) error
	UpdatePlayerCharacter(ctx context.Context, id int64, character string) error
	// SetBlock bloqueia (on) ou desbloqueia outro jogador.
	SetBlock(ctx context.Context, player, other int64, on bool, at time.Time) error
	// Blocks: quem o jogador bloqueou e quem bloqueou o jogador.
	Blocks(ctx context.Context, player int64) (blocked, blockedBy []int64, err error)
	DeletePlayer(ctx context.Context, id int64) error // apaga também lote, inventário, coletas e objetos
}

// LotRepository guarda os lotes ocupados e as casas.
type LotRepository interface {
	CreateLot(ctx context.Context, l *Lot) error // ErrLotTaken se o lote ou o dono já têm lote
	LotByOwner(ctx context.Context, owner int64) (*Lot, error)
	LotsByCells(ctx context.Context, cells []int) ([]Lot, error)
	UpdateLot(ctx context.Context, l *Lot) error
	DeleteLot(ctx context.Context, id int64) error // apaga também os objetos colocados
	AllLots(ctx context.Context) ([]Lot, error)
	// MoveLot muda o lote para outra célula/posição (novo id), com a casa e os objetos.
	MoveLot(ctx context.Context, oldID, newID int64, cell, slot int) error
}

// InventoryRepository guarda o inventário.
type InventoryRepository interface {
	Inventory(ctx context.Context, player int64) ([]Stack, error) // em ordem de chegada
	AddItem(ctx context.Context, player int64, item string, delta int) error
	ClearInventory(ctx context.Context, player int64) error
}

// CollectionRepository guarda as coletas do dia (limites diários por jogador e objeto).
type CollectionRepository interface {
	Collections(ctx context.Context, player, day int64, cells []int) ([]Collection, error)
	CollectionCount(ctx context.Context, player, object int64, action string, day int64) (int, error)
	AddCollection(ctx context.Context, player, object int64, cell int, action string, day int64) error
	ClearCollections(ctx context.Context, player int64) error
}

// PlacementRepository guarda os objetos colocados nos lotes.
type PlacementRepository interface {
	Placements(ctx context.Context, lots []int64) ([]Placement, error)
	PlacementByID(ctx context.Context, id int64) (*Placement, error)
	CreatePlacement(ctx context.Context, p *Placement) error // preenche p.ID
	DeletePlacement(ctx context.Context, id int64) error
	DeleteLotPlacements(ctx context.Context, lot int64) error
}

// Transaction é uma linha do histórico de moedas.
type Transaction struct {
	ID        int64     `json:"id"`
	Delta     int64     `json:"delta"`
	Balance   int64     `json:"balance"`
	Reason    string    `json:"reason"`
	Ref       string    `json:"ref"`
	CreatedAt time.Time `json:"created_at"`
}

// WalletRepository guarda o saldo de moedas e o histórico.
type WalletRepository interface {
	Coins(ctx context.Context, player int64) (int64, error)
	// AddCoins soma delta ao saldo e grava no histórico. ErrNoCoins se o saldo ficaria
	// negativo (nada é gravado). Devolve o saldo novo.
	AddCoins(ctx context.Context, player, delta int64, reason, ref string, at time.Time) (int64, error)
	Transactions(ctx context.Context, player int64, limit int) ([]Transaction, error)
}

// PediaRecord é uma linha da Goblopédia de um jogador.
type PediaRecord struct {
	Entry     string
	FirstAt   time.Time // zero = ainda sem foto
	Country   string
	Biome     string
	Sightings int
	Friend    bool
}

// PediaRepository guarda a Goblopédia de cada jogador.
type PediaRepository interface {
	Pedia(ctx context.Context, player int64) ([]PediaRecord, error)
	// PediaSighting soma uma foto; na primeira, grava país, bioma e data e devolve first = true.
	PediaSighting(ctx context.Context, player int64, entry, country, biome string, at time.Time) (first bool, err error)
	PediaFriend(ctx context.Context, player int64, entry string) error
	ClearPedia(ctx context.Context, player int64) error
}

// Stamp é o carimbo de um país no passaporte (primeira visita).
type Stamp struct {
	Country string
	FirstAt time.Time
}

// PassportRepository guarda os passaportes comprados e os carimbos.
type PassportRepository interface {
	Passports(ctx context.Context, player int64) ([]string, error)
	AddPassport(ctx context.Context, player int64, country string, at time.Time) (added bool, err error)
	RemovePassport(ctx context.Context, player int64, country string) error
	Stamps(ctx context.Context, player int64) ([]Stamp, error)
	// AddStamp grava o carimbo se ainda não existe; added = true só na primeira vez.
	AddStamp(ctx context.Context, player int64, country string, at time.Time) (added bool, err error)
	ClearPassports(ctx context.Context, player int64) error // passaportes e carimbos
}

// Store junta os repositórios. As regras só conhecem esta interface; a implementação
// atual é SQLite (internal/store/sqlite), e dá para trocar por PostgreSQL (ADR 0018).
type Store interface {
	PlayerRepository
	LotRepository
	InventoryRepository
	CollectionRepository
	PlacementRepository
	WalletRepository
	PediaRepository
	PassportRepository
	// InTx roda fn numa transação: ou tudo é gravado, ou nada.
	InTx(ctx context.Context, fn func(Store) error) error
}
