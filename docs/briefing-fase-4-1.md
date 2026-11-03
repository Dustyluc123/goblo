# Briefing — Fase 4.1: desempenho e acabamento do personagem

> Cole este arquivo inteiro no Claude Code. Salve uma cópia em `docs/briefing-fase-4-1.md` (não deixe na raiz).

## Contexto

A Fase 4.0 entregou muita coisa boa (temperatura, necessidades, comida, roupas, editor, flores). Testei e encontrei problemas no personagem e nas roupas, e **o fps ficou muito ruim**. Esta fase **não adiciona conteúdo novo**: só corrige.

Regras de sempre do `CLAUDE.md`. Sobre janelas: **nesta fase você pode abrir o jogo com janela para medir fps**, mas **avise no terminal antes** ("vou abrir o jogo na frente por X minutos para medir") e **espere eu responder "ok"**. Capturas continuam pelo `tools/sem_foco.sh`.

## Ordem

1 (desempenho) → 2 (roupas por cima da roupa original e bug da capa) → 3 (editor e encaixe na cabeça) → 4 (guarda-roupa) → 5 (ícones de líquidos) → medição final.

## 1. Desempenho (prioridade máxima)

O jogo ficou **muito mais pesado** depois da 4.0. A meta continua: **60 fps estáveis na qualidade média** e **no mínimo 45 fps na alta**, no meu Mac Intel, na janela grande, nas cenas do `medir_fps.sh` (incluindo "pampa florido" e bairro com bots).

**Primeiro meça, depois corrija.** Com a minha autorização (ver acima), rode o `medir_fps.sh` e o profiler do Godot e compare com a medição da Fase 3. Me diga o que mais pesa. Suspeitas a investigar:

- **Luzes das fogueiras:** luzes pontuais dinâmicas são caras, principalmente com sombra. Fogueira sem sombra, alcance pequeno, limite de quantas luzes acesas ao mesmo tempo e luz desligada longe da câmera.
- **Roupas em "cascas":** cada peça como malha animada separada multiplica o custo de animação e os draw calls de cada personagem. **Junte corpo, cabeça e roupas numa malha única por personagem** (já foi feito para o corpo; faça também com as roupas), refazendo só quando o visual mudar.
- **Capa:** se tiver simulação de tecido ou ossos extras, troque por um balanço simples por shader.
- **Personagens customizados únicos:** confira se cada jogador/bot não está criando materiais e texturas novos a cada quadro ou a cada atualização de rede.
- **Partículas** (vapor da respiração, suor, fogueira, neve): orçamento máximo por tipo, só perto da câmera, ligado aos presets de qualidade.
- **Flores mais densas (+24%):** distância e densidade por preset de qualidade; flores decorativas somem antes da grama.
- **Efeito de tela zonza e termômetro:** confira se algum efeito de pós-processamento está ligado o tempo todo, mesmo quando não deveria.
- **Cálculos de temperatura e necessidades** no cliente a cada quadro (devem ser poucas vezes por segundo).

Atualize a tabela de desempenho do README com **Fase 3 × antes da 4.1 × depois da 4.1**. Se alguma meta não for atingida, explique por quê e o que falta.

## 2. Roupas: substituição de verdade e bug da capa

- **A roupa original do personagem aparece por baixo da roupa equipada.** Os corpos do Mini Characters já vêm "vestidos" (camiseta, calça, sapato na própria malha). Quando eu coloco, por exemplo, uma regata, aparece a camiseta original **mais** a regata.
- Corrija para que **cada espaço equipado esconda a parte correspondente do corpo original**: com algo no espaço **corpo**, a região do tronco/braços da roupa original não aparece; o mesmo para **pernas** e **pés**. Caminhos possíveis: máscara por região de UV/cor no shader, trocar a região por "pele" ou peça base neutra, ou recortar as malhas por região. Escolha o que ficar melhor visualmente e mais leve, e registre num ADR.
- Com o espaço **vazio**, o personagem continua com a roupa original dele.
- **Bug da capa:** ao equipar a capa, o personagem inteiro fica **verde**. Provavelmente um material compartilhado sendo sobrescrito ou uma cor de vértice/atlas errada. Corrija e verifique o mesmo problema em **todas as 14 peças** (equipar e desequipar cada uma, sozinha e combinada).
- Teste automático: para cada peça, equipar e conferir que o material dos outros espaços e do corpo não mudou.
- Capturas com `sem_foco.sh`: um personagem com cada espaço preenchido, de frente e de costas.

## 3. Editor de personagem

### 3.1 Fluxo
- O editor acontece **obrigatoriamente antes de entrar no jogo** no primeiro acesso, e **substitui totalmente** a tela antiga de escolha de personagem pré-definido (remova a tela antiga).
- Continua podendo ser reaberto no espelho do lote e nas configurações.

### 3.2 Partes independentes
- Hoje, mexer na **cabeça** muda também o **cabelo** e os acessórios, porque o cabelo vem junto na malha da cabeça.
- Separe o cabelo da cabeça: **extraia o cabelo de cada uma das 12 cabeças como uma malha própria** (por exemplo, separando as faces pela região do atlas de cores/UV que corresponde ao cabelo) e gere as **cabeças sem cabelo**. Assim ficam independentes: **cabeça/rosto**, **cabelo** (12 originais + os penteados extras), **cor da pele**, **cor do cabelo**, **acessórios**.
- Se alguma cabeça não der para separar bem, me diga qual e faça a melhor alternativa só para ela.
- Isso também resolve a **troca de cor de pele e cabelo errando** em cabeças com boné ou cabelo do mesmo tom da pele (pendência da 4.0): com as malhas separadas, cada cor afeta só a sua parte. Cabeças cujo "cabelo" original é um boné viram: cabeça + boné como acessório de cabeça.

### 3.3 Chapéus e acessórios encaixando na cabeça
- Chapéus e acessórios estão **flutuando acima** da cabeça ou **deformando** a cabeça.
- Prenda-os ao **osso da cabeça** com um ponto de encaixe e um ajuste **por cabeça** (posição, escala e rotação no arquivo de dados), para encaixar no formato de cada uma das 12 cabeças.
- Chapéu nunca deforma a cabeça. Com chapéu, o cabelo usa uma versão "achatada" (ou esconde a parte de cima) para não atravessar o chapéu.
- Teste com todas as combinações cabeça × chapéu e mande uma grade de capturas.

## 4. Guarda-roupa (tecla C)

- O personagem **para de girar sozinho**.
- Ele fica parado de frente; eu giro com o mouse (arrastar) ou A/D, e posso aproximar com a roda (rosto, corpo inteiro).
- Um botão para "ver de costas" (bom para a capa) e outro para voltar à frente.
- O personagem fica numa pose neutra (sem a animação de andar) enquanto o guarda-roupa está aberto.

## 5. Ícones de tintas e líquidos

- Os ícones e modelos de **tintas**, **cantil** e **bebidas** parecem copos vazios.
- Atualize para mostrar o **líquido colorido preenchendo** o recipiente: cada tinta com a sua cor, cantil com água azulada (e indicando quantos goles restam), sucos com a cor da fruta.
- Mantenha o estilo dos outros ícones.

## Fora do escopo

Qualquer conteúdo novo, itens do `BACKLOG.md` não citados aqui, cavernas, baú, limite por item, folclore, animais, mar, veículos, interface nova, sons.

## No final

- O que o profiler mostrou, a tabela de desempenho (Fase 3 × antes × depois) e se as metas foram atingidas.
- O que mudou em cada item e como testar.
- Quais cabeças tiveram o cabelo separado e se alguma ficou de fora.
- O que ficou sem verificação visual.
