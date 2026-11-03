# Progresso — Fase 3.5: economia e gente

**Situação: encerrada** (3 de novembro de 2026), do jeito que está. Briefing em [`briefing-fase-3-5.md`](briefing-fase-3-5.md).

## Pronto

- Gobolar (G$): nome, símbolo e apelido ("goblinhos") em `economy.json`; moedinha própria no HUD e nos menus.
- Preço por país (`Service.Price`), modificadores em `countries.json`, histórico com país, preço e imposto, cofre do país sem interface (ADR 0041).
- Todo item com preço (com teste), caixa de vendas com quantidade e "vender tudo", confirmação para ferramentas e raros, loja que paga mais.
- Praça central: aeroporto novo (terminal, torre, pista, biruta, portão, carros, avião em código), loja com estoque do dia por país e exclusivos regionais (ADR 0042).
- NPCs parados (guia, lojista, atendente) com diálogo em `dialogs.json`, retrato, texto letra por letra e respostas.
- Apresentação do guia na primeira vez, com duas tarefas pagas, "Pular apresentação", F6 → Rever, ações no painel dev e progresso no servidor.
- Troca entre jogadores em tempo real, execução atômica no servidor, bots que aceitam no modo dev, testes em Go.
- Textos prontos para traduzir: o português é a chave e `client/tools/extrair_textos.py` gera `client/i18n/goblo.pot`.
- Testes: `go test ./...` e `--npc-test` passando no encerramento.

## Adiado

Os itens abaixo ficaram de fora e foram para o [`BACKLOG.md`](BACKLOG.md):

- **adiado** — ADRs 0043 (NPCs, diálogos e apresentação), 0044 (troca entre jogadores) e 0045 (textos prontos para tradução): citados no README e no `CLAUDE.md`, mas não escritos.
- **adiado** — Executáveis de macOS e Windows com a fase 3.5: os de `client/export/` foram gerados antes do cliente da 3.5.
- **adiado** — Revisão completa de que todo texto montado na interface passa por `tr()` antes do `%`.
- **adiado** — Medição de fps com a praça central e os NPCs (janela na frente).
