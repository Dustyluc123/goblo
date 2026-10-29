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
	Fake      bool // criado pelo modo dev ("vizinhos falsos")
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
	DeletePlayer(ctx context.Context, id int64) error // apaga também lote, inventário, coletas e objetos
}

// LotRepository guarda os lotes ocupados e as casas.
type LotRepository interface {
	CreateLot(ctx context.Context, l *Lot) error // ErrLotTaken se o lote ou o dono já têm lote
	LotByOwner(ctx context.Context, owner int64) (*Lot, error)
	LotsByCells(ctx context.Context, cells []int) ([]Lot, error)
	UpdateLot(ctx context.Context, l *Lot) error
	DeleteLot(ctx context.Context, id int64) error // apaga também os objetos colocados
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

// Store junta os repositórios. As regras só conhecem esta interface; a implementação
// atual é SQLite (internal/store/sqlite), e dá para trocar por PostgreSQL (ADR 0018).
type Store interface {
	PlayerRepository
	LotRepository
	InventoryRepository
	CollectionRepository
	PlacementRepository
	// InTx roda fn numa transação: ou tudo é gravado, ou nada.
	InTx(ctx context.Context, fn func(Store) error) error
}
