package game

import (
	"errors"
	"fmt"
)

// Error é um erro de regra do jogo, com código estável (para o cliente), status HTTP e
// mensagem em português (para mostrar na tela).
type Error struct {
	Code    string
	Status  int
	Message string
	// Details vai junto na resposta (ex.: os objetos que atrapalham a casa). Opcional.
	Details any
}

func (e *Error) Error() string { return e.Message }

// Is compara pelo código, para errors.Is funcionar com mensagens personalizadas.
func (e *Error) Is(target error) bool {
	var t *Error
	return errors.As(target, &t) && t.Code == e.Code
}

// with devolve uma cópia com outra mensagem.
func (e *Error) with(format string, args ...any) *Error {
	return &Error{Code: e.Code, Status: e.Status, Message: fmt.Sprintf(format, args...), Details: e.Details}
}

// withDetails devolve uma cópia com detalhes para o cliente.
func (e *Error) withDetails(d any) *Error {
	c := *e
	c.Details = d
	return &c
}

// Erros das regras.
var (
	ErrUnauthorized     = &Error{"unauthorized", 401, "Jogador não identificado.", nil}
	ErrNotFound         = &Error{"not_found", 404, "Não encontrado.", nil}
	ErrInvalid          = &Error{"invalid", 400, "Pedido inválido.", nil}
	ErrNicknameInvalid  = &Error{"nickname_invalid", 400, "Apelido inválido.", nil}
	ErrNicknameTaken    = &Error{"nickname_taken", 409, "Esse apelido já tem dono.", nil}
	ErrCountry          = &Error{"country_invalid", 400, "País desconhecido.", nil}
	ErrNoLot            = &Error{"no_lot", 409, "Não há lote livre.", nil}
	ErrLotTaken         = &Error{"lot_taken", 409, "Lote ocupado.", nil}
	ErrLimit            = &Error{"daily_limit", 409, "Já chega por hoje. Volte amanhã!", nil}
	ErrNoTool           = &Error{"no_tool", 409, "Falta a ferramenta certa.", nil}
	ErrWrongAction      = &Error{"wrong_action", 400, "Não dá para fazer isso aqui.", nil}
	ErrInventoryFull    = &Error{"inventory_full", 409, "O inventário está cheio.", nil}
	ErrMissingMaterials = &Error{"missing_materials", 409, "Faltam materiais.", nil}
	ErrNotOwner         = &Error{"not_owner", 403, "Este lote não é seu.", nil}
	ErrOutOfLot         = &Error{"out_of_lot", 400, "Fora da grade do lote.", nil}
	ErrOverlap          = &Error{"overlap", 409, "Já tem alguma coisa aí.", nil}
	ErrBusy             = &Error{"busy", 409, "A obra ainda não terminou.", nil}
	ErrMaxLevel         = &Error{"max_level", 409, "A casa já está no nível máximo.", nil}
	ErrDevOnly          = &Error{"dev_only", 403, "Só no modo dev (GOBLO_DEV=1).", nil}
)
