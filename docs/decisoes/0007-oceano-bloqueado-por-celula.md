# 0007 — Bloqueio do oceano pela célula à frente

**Status:** aceita (fase 1)

## Contexto
O personagem não pode entrar no oceano. A malha da terra fica 0,8 acima da água, então sair da terra para o mar seria só "cair um degrau".

## Decisão
No cliente, antes de mover, o personagem consulta a célula 0,6 unidade à frente (pela direção a partir do centro do planeta). Se for oceano, tira a parte da velocidade que aponta para aquela célula (desliza pela costa); se continuar no mar, para. Se por algum motivo já estiver no oceano, pode sair dele.

## Por quê
É a opção mais simples, usa os mesmos dados do servidor e não precisa de colisores extras.

## Consequências
- A regra roda no cliente. No multiplayer (fase 3), o servidor precisa conferir o movimento com a mesma regra, usando `World.CellAt`.
- Pontes, barcos ou "nadar" exigirão trocar a regra por um tipo de terreno "andável".
