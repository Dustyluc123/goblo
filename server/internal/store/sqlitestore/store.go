// Package sqlitestore guarda o estado do jogo em SQLite, com o driver modernc.org/sqlite
// (Go puro, sem cgo). Implementa game.Store; as regras não sabem que é SQLite (ADR 0018).
package sqlitestore

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"

	_ "modernc.org/sqlite" // registra o driver "sqlite"
)

//go:embed migrations/*.sql
var migrations embed.FS

type querier interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// Store é a implementação SQLite de game.Store.
type Store struct {
	db *sql.DB
	q  querier
}

var _ game.Store = (*Store)(nil)

// Open abre (ou cria) o banco no caminho e aplica as migrações que faltam.
// Use ":memory:" para um banco temporário.
func Open(ctx context.Context, path string) (*Store, error) {
	dsn := "file:" + path + "?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)"
	if path == ":memory:" {
		dsn = "file::memory:?_pragma=foreign_keys(1)"
	}
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1) // um escritor só; evita "database is locked"
	s := &Store{db: db, q: db}
	if err := s.migrate(ctx); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

// Close fecha o banco.
func (s *Store) Close() error { return s.db.Close() }

// migrate aplica, em ordem, os arquivos migrations/NNNN_nome.sql ainda não aplicados.
func (s *Store) migrate(ctx context.Context) error {
	if _, err := s.db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at INTEGER NOT NULL)`); err != nil {
		return err
	}
	files, err := fs.Glob(migrations, "migrations/*.sql")
	if err != nil {
		return err
	}
	sort.Strings(files)
	for _, f := range files {
		name := strings.TrimPrefix(f, "migrations/")
		version, err := strconv.Atoi(strings.SplitN(name, "_", 2)[0])
		if err != nil {
			return fmt.Errorf("migração sem número: %s", name)
		}
		var n int
		if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM schema_migrations WHERE version = ?`, version).Scan(&n); err != nil {
			return err
		}
		if n > 0 {
			continue
		}
		body, err := migrations.ReadFile(f)
		if err != nil {
			return err
		}
		tx, err := s.db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, string(body)); err != nil {
			tx.Rollback()
			return fmt.Errorf("migração %s: %w", name, err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)`,
			version, name, time.Now().Unix()); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

// SchemaVersion é a última migração aplicada.
func (s *Store) SchemaVersion(ctx context.Context) (int, error) {
	var v sql.NullInt64
	err := s.db.QueryRowContext(ctx, `SELECT MAX(version) FROM schema_migrations`).Scan(&v)
	return int(v.Int64), err
}

// InTx roda fn numa transação. Dentro de uma transação, roda direto.
func (s *Store) InTx(ctx context.Context, fn func(game.Store) error) error {
	if _, inTx := s.q.(*sql.Tx); inTx {
		return fn(s)
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(&Store{db: s.db, q: tx}); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

func isUnique(err error, table string) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE constraint failed: "+table)
}

func notFound(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return game.ErrNotFound
	}
	return err
}

func placeholders(n int) string {
	return strings.TrimSuffix(strings.Repeat("?,", n), ",")
}

// --- Jogadores ----------------------------------------------------------------------------

func (s *Store) CreatePlayer(ctx context.Context, p *game.Player) error {
	res, err := s.q.ExecContext(ctx, `INSERT INTO players (nickname, country, token_hash, created_at, fake) VALUES (?, ?, ?, ?, ?)`,
		p.Nickname, p.Country, p.TokenHash, p.CreatedAt.Unix(), p.Fake)
	if isUnique(err, "players.nickname") {
		return game.ErrNicknameTaken
	}
	if err != nil {
		return err
	}
	p.ID, err = res.LastInsertId()
	return err
}

const playerCols = `id, nickname, country, token_hash, created_at, fake`

func scanPlayer(row interface{ Scan(...any) error }) (*game.Player, error) {
	var p game.Player
	var created int64
	if err := row.Scan(&p.ID, &p.Nickname, &p.Country, &p.TokenHash, &created, &p.Fake); err != nil {
		return nil, notFound(err)
	}
	p.CreatedAt = time.Unix(created, 0).UTC()
	return &p, nil
}

func (s *Store) PlayerByTokenHash(ctx context.Context, hash string) (*game.Player, error) {
	return scanPlayer(s.q.QueryRowContext(ctx, `SELECT `+playerCols+` FROM players WHERE token_hash = ?`, hash))
}

func (s *Store) PlayerByID(ctx context.Context, id int64) (*game.Player, error) {
	return scanPlayer(s.q.QueryRowContext(ctx, `SELECT `+playerCols+` FROM players WHERE id = ?`, id))
}

func (s *Store) PlayersByIDs(ctx context.Context, ids []int64) (map[int64]*game.Player, error) {
	out := map[int64]*game.Player{}
	if len(ids) == 0 {
		return out, nil
	}
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	rows, err := s.q.QueryContext(ctx, `SELECT `+playerCols+` FROM players WHERE id IN (`+placeholders(len(ids))+`)`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		p, err := scanPlayer(rows)
		if err != nil {
			return nil, err
		}
		out[p.ID] = p
	}
	return out, rows.Err()
}

func (s *Store) UpdatePlayerCountry(ctx context.Context, id int64, country string) error {
	_, err := s.q.ExecContext(ctx, `UPDATE players SET country = ? WHERE id = ?`, country, id)
	return err
}

func (s *Store) DeletePlayer(ctx context.Context, id int64) error {
	// As chaves estrangeiras com ON DELETE CASCADE levam lote, objetos, inventário e coletas.
	_, err := s.q.ExecContext(ctx, `DELETE FROM players WHERE id = ?`, id)
	return err
}

// --- Lotes ----------------------------------------------------------------------------------

const lotCols = `id, cell, slot, owner_id, house_level, pending_level, ready_at, house_x, house_y, house_rot`

func scanLot(row interface{ Scan(...any) error }) (*game.Lot, error) {
	var l game.Lot
	var ready int64
	if err := row.Scan(&l.ID, &l.Cell, &l.Slot, &l.OwnerID, &l.HouseLevel, &l.PendingLevel, &ready, &l.HouseX, &l.HouseY, &l.HouseRot); err != nil {
		return nil, notFound(err)
	}
	if ready > 0 {
		l.ReadyAt = time.Unix(ready, 0).UTC()
	}
	return &l, nil
}

func unixOrZero(t time.Time) int64 {
	if t.IsZero() {
		return 0
	}
	return t.Unix()
}

func (s *Store) CreateLot(ctx context.Context, l *game.Lot) error {
	_, err := s.q.ExecContext(ctx, `INSERT INTO lots (`+lotCols+`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		l.ID, l.Cell, l.Slot, l.OwnerID, l.HouseLevel, l.PendingLevel, unixOrZero(l.ReadyAt), l.HouseX, l.HouseY, l.HouseRot)
	if isUnique(err, "lots") {
		return game.ErrLotTaken
	}
	return err
}

func (s *Store) LotByOwner(ctx context.Context, owner int64) (*game.Lot, error) {
	return scanLot(s.q.QueryRowContext(ctx, `SELECT `+lotCols+` FROM lots WHERE owner_id = ?`, owner))
}

func (s *Store) LotsByCells(ctx context.Context, cells []int) ([]game.Lot, error) {
	if len(cells) == 0 {
		return nil, nil
	}
	args := make([]any, len(cells))
	for i, c := range cells {
		args[i] = c
	}
	rows, err := s.q.QueryContext(ctx, `SELECT `+lotCols+` FROM lots WHERE cell IN (`+placeholders(len(cells))+`) ORDER BY id`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []game.Lot
	for rows.Next() {
		l, err := scanLot(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *l)
	}
	return out, rows.Err()
}

func (s *Store) UpdateLot(ctx context.Context, l *game.Lot) error {
	_, err := s.q.ExecContext(ctx, `UPDATE lots SET house_level = ?, pending_level = ?, ready_at = ?, house_x = ?, house_y = ?, house_rot = ? WHERE id = ?`,
		l.HouseLevel, l.PendingLevel, unixOrZero(l.ReadyAt), l.HouseX, l.HouseY, l.HouseRot, l.ID)
	return err
}

func (s *Store) DeleteLot(ctx context.Context, id int64) error {
	_, err := s.q.ExecContext(ctx, `DELETE FROM lots WHERE id = ?`, id)
	return err
}

// --- Inventário ---------------------------------------------------------------------------

func (s *Store) Inventory(ctx context.Context, player int64) ([]game.Stack, error) {
	rows, err := s.q.QueryContext(ctx, `SELECT item, count, seq FROM inventory WHERE player_id = ? ORDER BY seq`, player)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []game.Stack
	for rows.Next() {
		var st game.Stack
		if err := rows.Scan(&st.Item, &st.Count, &st.Order); err != nil {
			return nil, err
		}
		out = append(out, st)
	}
	return out, rows.Err()
}

func (s *Store) AddItem(ctx context.Context, player int64, item string, delta int) error {
	if delta == 0 {
		return nil
	}
	var have int
	err := s.q.QueryRowContext(ctx, `SELECT count FROM inventory WHERE player_id = ? AND item = ?`, player, item).Scan(&have)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	next := have + delta
	switch {
	case next < 0:
		return game.ErrMissingMaterials
	case next == 0:
		_, err = s.q.ExecContext(ctx, `DELETE FROM inventory WHERE player_id = ? AND item = ?`, player, item)
	case have == 0:
		_, err = s.q.ExecContext(ctx, `INSERT INTO inventory (player_id, item, count, seq)
			VALUES (?, ?, ?, (SELECT COALESCE(MAX(seq), 0) + 1 FROM inventory WHERE player_id = ?))`, player, item, next, player)
	default:
		_, err = s.q.ExecContext(ctx, `UPDATE inventory SET count = ? WHERE player_id = ? AND item = ?`, next, player, item)
	}
	return err
}

func (s *Store) ClearInventory(ctx context.Context, player int64) error {
	_, err := s.q.ExecContext(ctx, `DELETE FROM inventory WHERE player_id = ?`, player)
	return err
}

// --- Coletas --------------------------------------------------------------------------------

func (s *Store) Collections(ctx context.Context, player, day int64, cells []int) ([]game.Collection, error) {
	if len(cells) == 0 {
		return nil, nil
	}
	args := []any{player, day}
	for _, c := range cells {
		args = append(args, c)
	}
	rows, err := s.q.QueryContext(ctx, `SELECT object_id, action, count FROM collections
		WHERE player_id = ? AND day = ? AND cell IN (`+placeholders(len(cells))+`) ORDER BY object_id, action`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []game.Collection
	for rows.Next() {
		var c game.Collection
		if err := rows.Scan(&c.ObjectID, &c.Action, &c.Count); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) CollectionCount(ctx context.Context, player, object int64, action string, day int64) (int, error) {
	var n int
	err := s.q.QueryRowContext(ctx, `SELECT count FROM collections WHERE player_id = ? AND object_id = ? AND action = ? AND day = ?`,
		player, object, action, day).Scan(&n)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return n, err
}

func (s *Store) AddCollection(ctx context.Context, player, object int64, cell int, action string, day int64) error {
	_, err := s.q.ExecContext(ctx, `INSERT INTO collections (player_id, object_id, cell, action, day, count) VALUES (?, ?, ?, ?, ?, 1)
		ON CONFLICT (player_id, object_id, action, day) DO UPDATE SET count = count + 1`, player, object, cell, action, day)
	return err
}

func (s *Store) ClearCollections(ctx context.Context, player int64) error {
	_, err := s.q.ExecContext(ctx, `DELETE FROM collections WHERE player_id = ?`, player)
	return err
}

// --- Objetos colocados ----------------------------------------------------------------------

func (s *Store) Placements(ctx context.Context, lots []int64) ([]game.Placement, error) {
	if len(lots) == 0 {
		return nil, nil
	}
	args := make([]any, len(lots))
	for i, l := range lots {
		args[i] = l
	}
	rows, err := s.q.QueryContext(ctx, `SELECT id, lot_id, item, x, y, rot FROM placements WHERE lot_id IN (`+placeholders(len(lots))+`) ORDER BY id`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []game.Placement
	for rows.Next() {
		var p game.Placement
		if err := rows.Scan(&p.ID, &p.LotID, &p.Item, &p.X, &p.Y, &p.Rot); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Store) PlacementByID(ctx context.Context, id int64) (*game.Placement, error) {
	var p game.Placement
	err := s.q.QueryRowContext(ctx, `SELECT id, lot_id, item, x, y, rot FROM placements WHERE id = ?`, id).
		Scan(&p.ID, &p.LotID, &p.Item, &p.X, &p.Y, &p.Rot)
	if err != nil {
		return nil, notFound(err)
	}
	return &p, nil
}

func (s *Store) CreatePlacement(ctx context.Context, p *game.Placement) error {
	res, err := s.q.ExecContext(ctx, `INSERT INTO placements (lot_id, item, x, y, rot) VALUES (?, ?, ?, ?, ?)`, p.LotID, p.Item, p.X, p.Y, p.Rot)
	if err != nil {
		return err
	}
	p.ID, err = res.LastInsertId()
	return err
}

func (s *Store) DeletePlacement(ctx context.Context, id int64) error {
	_, err := s.q.ExecContext(ctx, `DELETE FROM placements WHERE id = ?`, id)
	return err
}

func (s *Store) DeleteLotPlacements(ctx context.Context, lot int64) error {
	_, err := s.q.ExecContext(ctx, `DELETE FROM placements WHERE lot_id = ?`, lot)
	return err
}
