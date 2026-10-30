package game

import (
	"context"
	"fmt"
	"slices"
)

// NPCs, diálogos e a apresentação do guia (fase 3.5, ADR 0043). Os textos ficam em
// npcs.json e dialogs.json e vão para o cliente pelo /content; aqui o servidor só confere os
// dados, escolhe os nomes por país e guarda o progresso da apresentação (com as tarefas
// recompensadas uma vez só).

// NPCContent é npcs.json.
type NPCContent struct {
	Roles map[string]NPCRole             `json:"roles"`
	Names map[string]map[string][]string `json:"names"`
}

// NPCRole é um papel (guia, lojista, atendente).
type NPCRole struct {
	Title     string `json:"title"`
	Character string `json:"character"`
	Accessory string `json:"accessory"`
	Tint      string `json:"tint"`
	Dialog    string `json:"dialog"`
}

// DialogContent é dialogs.json.
type DialogContent struct {
	Dialogs map[string][]DialogLine `json:"dialogs"`
	Intro   struct {
		Start string      `json:"start"`
		Tasks []IntroTask `json:"tasks"`
	} `json:"intro"`
}

// DialogLine é uma fala, com respostas opcionais.
type DialogLine struct {
	Text    string         `json:"text"`
	Options []DialogOption `json:"options,omitempty"`
}

// DialogOption é uma resposta: vai para outro diálogo e/ou pede uma ação ao jogo.
type DialogOption struct {
	Text   string `json:"text"`
	Next   string `json:"next,omitempty"`
	Action string `json:"action,omitempty"`
	Task   string `json:"task,omitempty"`
}

// IntroTask é uma tarefa guiada da apresentação: uma ação de coleta ou uma receita.
type IntroTask struct {
	ID     string `json:"id"`
	Action string `json:"action,omitempty"` // shake, chop, mine, pick
	Recipe string `json:"recipe,omitempty"`
	After  string `json:"after"` // diálogo depois de cumprir
}

var dialogActions = []string{"", "open_shop", "open_shop_sell", "open_travel", "open_passports", "intro_task", "intro_done", "intro_restart", "end"}

func (c *Content) checkDialogs() error {
	d := c.Dialogs
	if d == nil || c.NPCs == nil {
		return fmt.Errorf("dialogs.json e npcs.json são obrigatórios")
	}
	tasks := map[string]bool{}
	for _, t := range d.Intro.Tasks {
		tasks[t.ID] = true
		if _, ok := d.Dialogs[t.After]; !ok {
			return fmt.Errorf("dialogs.json: tarefa %s leva para o diálogo %s, que não existe", t.ID, t.After)
		}
		if t.Recipe != "" && c.recipes[t.Recipe] == nil {
			return fmt.Errorf("dialogs.json: tarefa %s com receita desconhecida", t.ID)
		}
	}
	if _, ok := d.Dialogs[d.Intro.Start]; !ok {
		return fmt.Errorf("dialogs.json: intro.start %s não existe", d.Intro.Start)
	}
	for id, lines := range d.Dialogs {
		if len(lines) == 0 {
			return fmt.Errorf("dialogs.json: diálogo %s vazio", id)
		}
		for _, l := range lines {
			for _, o := range l.Options {
				if o.Next != "" {
					if _, ok := d.Dialogs[o.Next]; !ok {
						return fmt.Errorf("dialogs.json: %s leva para %s, que não existe", id, o.Next)
					}
				}
				if !slices.Contains(dialogActions, o.Action) {
					return fmt.Errorf("dialogs.json: ação desconhecida %q em %s", o.Action, id)
				}
				if o.Action == "intro_task" && !tasks[o.Task] {
					return fmt.Errorf("dialogs.json: tarefa desconhecida %q em %s", o.Task, id)
				}
			}
		}
	}
	for role, r := range c.NPCs.Roles {
		if _, ok := d.Dialogs[r.Dialog]; !ok {
			return fmt.Errorf("npcs.json: %s abre o diálogo %s, que não existe", role, r.Dialog)
		}
		if len(c.NPCs.Names["default"][role]) == 0 {
			return fmt.Errorf("npcs.json: sem nomes padrão para %s", role)
		}
	}
	return nil
}

// NPCName é o nome do NPC de um papel num país (sorteio fixo pelo país).
func (c *Content) NPCName(role, country string) string {
	list := c.NPCs.Names[country][role]
	if len(list) == 0 {
		list = c.NPCs.Names["default"][role]
	}
	var h uint32 = 7
	for _, ch := range country + role {
		h = h*31 + uint32(ch)
	}
	return list[hash32(h, 3, 9)%uint32(len(list))]
}

// IntroView é o progresso da apresentação do guia.
type IntroView struct {
	Done  bool     `json:"done"`
	Tasks []string `json:"tasks"` // tarefas cumpridas (e recompensadas)
}

// Intro devolve o progresso da apresentação.
func (s *Service) Intro(ctx context.Context, p *Player) (*IntroView, error) {
	done, tasks, err := s.store.Intro(ctx, p.ID)
	if tasks == nil {
		tasks = []string{}
	}
	return &IntroView{Done: done, Tasks: tasks}, err
}

// SetIntro marca a apresentação como vista ou não vista (rever pelo F6; modo dev). Ao
// marcar como não vista, as tarefas continuam recompensadas (não pagam de novo).
func (s *Service) SetIntro(ctx context.Context, p *Player, done bool) (*IntroView, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, tasks, err := s.store.Intro(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	if err := s.store.SetIntro(ctx, p.ID, done, tasks); err != nil {
		return nil, err
	}
	return s.Intro(ctx, p)
}

// introProgress: se a ação cumpre uma tarefa da apresentação ainda não recompensada (e a
// apresentação está em andamento), marca e paga. Chamado dentro da transação da ação.
func (s *Service) introProgress(ctx context.Context, tx Store, p *Player, action, recipe string) (string, int64, error) {
	done, tasks, err := tx.Intro(ctx, p.ID)
	if err != nil || done {
		return "", 0, err
	}
	for _, t := range s.content.Dialogs.Intro.Tasks {
		if slices.Contains(tasks, t.ID) {
			continue
		}
		if (t.Action != "" && t.Action == action) || (t.Recipe != "" && t.Recipe == recipe) {
			if err := tx.SetIntro(ctx, p.ID, false, append(tasks, t.ID)); err != nil {
				return "", 0, err
			}
			reward := s.content.Economy.Rewards.IntroTask
			if _, err := s.grant(ctx, tx, p, reward, "intro", t.ID, ""); err != nil {
				return "", 0, err
			}
			return t.ID, reward, nil
		}
	}
	return "", 0, nil
}
