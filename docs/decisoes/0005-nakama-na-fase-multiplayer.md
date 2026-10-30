# 0005 — Nakama será avaliado na fase de multiplayer

**Status:** decidida na fase 3: servidor próprio, sem o Nakama ([ADR 0039](0039-tempo-real-no-servidor-proprio.md))

## Contexto
A fase 3 traz multiplayer em tempo real com interesse por área (cada jogador recebe só quem está perto). Fases seguintes trazem contas, moeda e troca entre jogadores.

## Decisão
Não usar nada disso na fase 1. Na fase 3, avaliar o [Nakama](https://heroiclabs.com/nakama/) (servidor de jogos em Go, código aberto, com contas, partidas autoritativas, chat, armazenamento e cliente oficial para Godot) contra continuar com o servidor próprio em Go.

## Critérios da avaliação
- Como encaixar a grade geodésica e o "interesse por célula" numa partida autoritativa.
- Custo de operar (Postgres/CockroachDB, memória, deploy).
- Quanto do que já existe em `server/internal/world` dá para reaproveitar como módulo Go do Nakama.

## Consequências
Até lá, o servidor continua simples (HTTP + JSON) e o cliente fala com ele por uma URL configurável.
