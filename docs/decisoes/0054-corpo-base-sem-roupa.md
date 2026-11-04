# 0054 — Corpo base "sem roupa" onde a pele aparece

**Fase 4.5.** Corrige a 0052/0053 (roupas por região).

## Contexto

As roupas do pacote de personagens vêm desenhadas no próprio corpo: mangas, punhos, barras da calça e sapatos são volumes da malha. Na 4.1/4.2 uma peça trocava só a **cor** da região. Com a regata, o braço inteiro virava pele, mas com o formato da manga (punho largo, ombro bufante); com o short, a canela tinha a barra da calça; com a sandália, o pé tinha a forma do sapato.

Também havia, só na Personagem 1, um objeto azul na mão (parte da malha do corpo), que aparecia no editor sem nome nenhum.

## Decisão

- **Corpo base medido em cada corpo** (`CharacterLook._bare_body`, um por tipo de corpo, sem arquivo novo): a malha é separada em ilhas (pedaços soltos, vértices na mesma posição contam como ligados). Nos braços, a ilha que chega na ponta da mão é a **mão**; o resto é **manga**. Nas pernas, a ilha que toca o chão é o **sapato**; o resto é a **calça**. Das medidas saem caixas presas ao mesmo osso (peso 1), no estilo do pacote:
  - braço: do ombro até dentro da mão, com 80% da seção da mão;
  - perna: a seção da coxa, do pé ao quadril;
  - pé: o comprimento e a largura do sapato, mais baixo.
- **Só onde a peça deixa a pele à mostra:** regata (as mangas saem e entram os braços base, com a mão original), short (a calça sai e entram as pernas base: pele embaixo, a cor do short em cima) e sandália (o sapato sai e entra o pé base, com a sola). As outras peças continuam pintando a forma original.
- A pele das caixas usa o mesmo tom e a mesma referência (UV e UV2) da pele da parte, como o resto da pele.
- **Objeto da mão:** o que passa da ponta da mão dos 12 corpos (`HAND_END`) e não é tronco nem pele sai da malha, com as outras peças da mesma cor no braço.

## Consequências

- `tests/test_roupas.gd` confere que os 12 corpos têm dois braços, duas pernas e dois pés base e que nada passa da ponta da mão; as regras de região continuam valendo (a regata só muda a região do corpo; o short e a sandália, a das pernas).
- Foto de conferência: `tools/sem_foco.sh -s tools/foto_corpo_base.gd -- --foto=/tmp/corpo.png`.
- Corpo novo do pacote entra sozinho se as mãos e os sapatos forem ilhas separadas; se a mão estiver grudada na manga, a regata pinta a manga de pele (como antes).
