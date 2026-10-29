# 0025 — Modelos juntados numa malha, com LOD e pré-carregamento

**Status:** aceita (fase 2)

## Contexto
Os modelos do Ultimate Nature Pack não têm textura: cada árvore tem 2 a 4 materiais de cor sólida, ou seja, 2 a 4 draw calls por MultiMesh. Têm também mais triângulos que os da Kenney (1.500 a 3.000 por árvore). Na primeira medição, a média ficou em 60 fps, mas houve travadas de até 133 ms: cada modelo novo era carregado e processado no thread principal na primeira vez que aparecia.

## Decisão
- A `ModelLibrary` (`client/scripts/model_library.gd`) carrega cada modelo e **junta tudo numa superfície só**: a cor de cada material vira cor por vértice, com um material compartilhado. Modelos com textura (Kenney) juntam as superfícies que têm o mesmo material. A cor por instância (tom do bioma) continua multiplicando por cima.
- Os **níveis de detalhe (LOD)** são gerados de novo para a malha juntada (`ImporterMesh.generate_lods`).
- Na entrada do jogo, todos os modelos que podem aparecer (lista mandada pelo servidor em `object_models`, mais grama, itens e casas) são **pré-carregados em paralelo** no `WorkerThreadPool` (~1,8 s), sem travar a tela.
- As casas também viram uma malha só (1 draw call por casa).

## Consequências
- Medido na floresta tropical, qualidade média: **60 fps** de média, 1% piores 58,7 fps, pior quadro 17 ms, GPU 10 ms (antes do pré-carregamento: 1% piores 31 fps, pior quadro 133 ms).
- A entrada do jogo ganhou ~1,8 s. Dá para guardar as malhas prontas em cache no disco se isso incomodar.
- Um modelo novo nos JSON precisa existir em `client/assets/quaternius/ultimate-nature/` (ou ser um caminho `res://`); se faltar, o erro aparece no console e o objeto não é desenhado.
