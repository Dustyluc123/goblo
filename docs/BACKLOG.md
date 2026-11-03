# Backlog

Itens que ficaram de fora de alguma fase. O autor decide em qual fase cada um entra.

## Da Fase 3.5 (adiados no encerramento)

Feitos na fase 4.0: os ADRs 0043, 0044 e 0045, a revisão do `tr()` e os executáveis atualizados. Continua aqui só a medição de fps da praça.

- **ADRs 0043, 0044 e 0045:** escrever as decisões de NPCs/diálogos/apresentação, troca entre jogadores e textos para tradução. O README e o `CLAUDE.md` já apontam para esses arquivos, que não existem.
- **Executáveis atualizados:** gerar de novo `client/export/Goblo-macOS.zip` e `client/export/windows/Goblo.exe` (os atuais são de antes do cliente da 3.5) e conferir no modo headless.
- **Revisão da tradução:** conferir que todo texto montado com `%` na interface passa por `tr()` no modelo, para o `.pot` cobrir tudo.
- **Medição de fps da praça central:** medir com `--perf-test` (janela na frente) na praça com loja, NPCs e aeroporto, nas qualidades média e alta.
