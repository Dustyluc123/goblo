# 0022 — Identidade por token, sem login, e país pelo IP

**Status:** aceita (fase 2)

## Contexto
O jogador precisa de identidade (inventário, lote) sem um sistema de login nesta fase, e deve nascer no país dele. O briefing sugere descobrir o país pelo IP com uma base gratuita, sem guardar o IP, e usar o idioma do sistema como alternativa.

## Decisão
- **Token secreto:** `POST /players` gera 32 bytes aleatórios (`crypto/rand`) e devolve em hexadecimal. O cliente guarda em `user://player.cfg`; o servidor guarda só o **SHA-256** do token. Quem tem o arquivo é o jogador.
- **Apelido** de 3 a 16 caracteres (letras, números, espaço, `_`, `-`), único sem diferenciar maiúsculas, com filtro de palavrões em português e inglês que pega disfarces comuns (acentos, números no lugar de letras, letras repetidas, pontuação). Palavras curtas e ambíguas ("cu", "puta") só são barradas como palavra inteira, para não recusar "Curió" ou "computador".
- **País pelo IP:** base **IP to Country Lite da DB-IP** (licença CC BY 4.0, atualizada todo mês; crédito "IP Geolocation by DB-IP"). Fica em `server/data/raw/` (fora do Git, ~4,5 MB) e é baixada por `scripts/baixar-dados.sh`. É carregada na memória (710 mil faixas, busca binária). Sem a base, o servidor funciona e o país vem só do idioma.
- **O IP não é guardado nem registrado**: é lido de `RemoteAddr`, usado na consulta e descartado. O log de requisições não tem IP.
- **Alternativa:** IP local (`127.0.0.1`, rede privada) ou desconhecido → o cliente manda `OS.get_locale()` (`pt_BR` → `BR`) e o servidor traduz o código ISO A2 para o código do mundo (ISO A3, do Natural Earth).
- A tela de primeiro acesso **mostra o país sugerido e deixa trocar** numa lista pesquisável.

## Consequências
- Perder o arquivo `user://player.cfg` = perder o jogador (não há recuperação). Um login de verdade fica para depois.
- Atrás de um proxy reverso, `RemoteAddr` é o proxy: ler `X-Forwarded-For` de um proxy confiável (há `TODO` em `remoteIP`).
- A base da DB-IP precisa ser atualizada de vez em quando (rodar o script de novo).
