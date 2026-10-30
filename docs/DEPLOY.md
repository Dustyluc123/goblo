# Jogar com amigos: servidor na internet e o jogo para baixar

> **Nada foi contratado nem publicado.** Este guia junta as opções para quando o autor decidir. Tudo aqui foi preparado na fase 3 e testado só localmente: o binário para Linux compila, mas a imagem Docker não foi gerada (o Docker não está instalado no Mac do autor).

## O que o servidor precisa

- **Um processo só**, o `goblo-server`: mundo, regras, banco e tempo real. Não há outro serviço.
- **WebSocket** (`GET /ws`) passando pelo proxy da hospedagem. É o motivo de alguns planos grátis não servirem.
- **Disco persistente** para o SQLite (`GOBLO_DB`, ~100 KB por jogador) ou um PostgreSQL. O SQLite é o mais simples e aguenta bem um grupo de amigos. A troca para o PostgreSQL já está prevista: o servidor só conhece a interface `game.Store` (ADR 0018).
- **Memória:** ~135 MB parado (o mundo e as fronteiras ficam na memória), com quase nada a mais por jogador.
- **CPU:** 100 jogadores na mesma região usaram ~75% de um núcleo do i7 do autor, com os bots rodando na mesma máquina (README, "Teste de carga"). Para um grupo de amigos, 1 vCPU sobra.
- **Banda:** ~12 KB/s por jogador com 40 outros por perto, e bem menos com poucos.
- **HTTPS.** O jogo troca `https://` por `wss://` sozinho. Sem TLS (só `http://`) também funciona, mas a conexão fica aberta.

Variáveis: `GOBLO_ADDR` (padrão `:8080`) e `GOBLO_DB` (padrão `goblo.db`). **Não** ligue `GOBLO_DEV=1` na internet: o modo dev deixa qualquer um dar itens, moedas e teleportes.

## Imagem Docker

```bash
docker build -t goblo-server server/
docker run -d --name goblo -p 8080:8080 -v goblo-dados:/data --restart unless-stopped goblo-server
curl http://localhost:8080/health   # {"status":"ok"}
```

A base de IP → país (`data/raw/dbip-country-lite.csv.gz`) é opcional. Sem ela, o país sugerido na primeira tela vem do idioma do sistema do jogador.

## Onde hospedar (barato, com WebSocket e disco)

| Opção | Custo aproximado | Como fica o banco | Observações |
| --- | --- | --- | --- |
| **VPS pequena** (Hetzner CX22, DigitalOcean, Oracle Cloud Free) | 0 (Oracle Free) a ~5 €/mês | SQLite num diretório da VPS | Mais controle e mais barata. Docker mais o Caddy na frente para o HTTPS automático. Exige cuidar de atualizações e backup (copiar o `goblo.db`). |
| **Fly.io** | poucos dólares/mês para 1 máquina pequena e 1 GB de volume | SQLite num volume do Fly | WebSocket funciona direto. `fly launch` lê o Dockerfile. Uma máquina só, porque o SQLite não divide o disco entre máquinas. |
| **Railway** | plano de entrada pago, com uso | SQLite num volume, ou o PostgreSQL deles | Simples de subir pelo GitHub. O PostgreSQL deles serve quando houver a implementação `game.Store` para ele. |
| **Render** | plano pago para ter disco | SQLite com disco persistente (pago) | O plano grátis dorme e não tem disco: não serve para o jogo. |

**Sugestão para começar:** uma VPS com Docker e Caddy, ou o Fly.io com um volume. Nos dois, faça backup diário do `goblo.db` (é um arquivo só).

Exemplo do Caddy (HTTPS automático, WebSocket incluído):

```
goblo.seudominio.com {
    reverse_proxy localhost:8080
}
```

## O jogo para os amigos

### Exportar (no Mac do autor)

1. Instale os modelos de exportação do Godot 4.7.2. Pelo editor: **Editor → Gerenciar modelos de exportação → Baixar**. Ou baixe o arquivo `.tpz` do site do Godot.
2. Exporte com os presets que já estão em `client/export_presets.cfg` ("macOS" e "Windows"):

```bash
cd client
godot --headless --export-release "macOS" export/Goblo-macOS.zip
godot --headless --export-release "Windows" export/windows/Goblo.exe
```

3. Coloque ao lado do jogo um arquivo **`goblo-servidor.txt`** com o endereço do servidor (uma linha, por exemplo `https://goblo.seudominio.com`):
   - **Windows:** na mesma pasta do `Goblo.exe`;
   - **macOS:** dentro do app, em `Goblo.app/Contents/MacOS/`, ou o amigo digita o endereço no jogo (veja abaixo).
4. Mande um `.zip` para os amigos.

### Endereço do servidor no jogo

O endereço vem, nesta ordem, de:

1. `--server=URL` na linha de comando;
2. a variável `GOBLO_SERVER_URL`;
3. o `goblo-servidor.txt` ao lado do executável (só no jogo exportado);
4. o que o jogador digitou antes (salvo em `settings.cfg`);
5. o padrão `http://127.0.0.1:8080`.

Se o jogo não achar o servidor ao abrir, aparece a janela **"Endereço do servidor"** para colar o endereço. Ele fica salvo para as próximas vezes.

### Como um amigo instala

**Windows:**

1. Descompacte o `.zip` numa pasta (por exemplo, `Documentos\Goblo`).
2. Abra o `Goblo.exe`. O Windows pode avisar "O Windows protegeu o computador" (SmartScreen), porque o jogo não tem assinatura digital. Clique em **Mais informações → Executar assim mesmo**.

**macOS:**

1. Descompacte o `.zip` e arraste o **Goblo.app** para a pasta Aplicativos.
2. Na primeira vez, o macOS diz que o app "não pode ser aberto porque é de um desenvolvedor não identificado" (o jogo tem só a assinatura local, sem a notarização paga da Apple). Abra assim:
   - clique com o **botão direito** (ou Control + clique) no Goblo.app → **Abrir** → **Abrir** de novo no aviso;
   - no macOS 15 ou mais novo, se não aparecer o botão: tente abrir uma vez, depois vá em **Ajustes do Sistema → Privacidade e Segurança**, role até "Goblo foi bloqueado" e clique em **Abrir Mesmo Assim**.
3. Depois da primeira vez, abre normalmente.

Os dois baixam o mundo do servidor na primeira vez (alguns segundos) e guardam em cache.

## Antes de chamar os amigos

- [ ] O servidor está **sem** `GOBLO_DEV=1`.
- [ ] HTTPS na frente (Caddy, ou o da hospedagem).
- [ ] Backup do `goblo.db` (cópia diária).
- [ ] Testado com dois jogos ao mesmo tempo (`client/tools/dois_clientes.sh https://seu-servidor`, que precisa do modo dev; ou duas janelas com `--profile` diferentes).
