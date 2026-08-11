# Phial

Um pequeno laboratório de agentes em Elixir usando
[Jido](https://github.com/agentjido/jido) e
[Jido.AI](https://github.com/agentjido/jido_ai). Ele contém um agente
determinístico e um agente conversacional ReAct capaz de selecionar e executar a
action `greet` como ferramenta. Também inclui uma swarm em que agentes são
processos BEAM supervisionados de verdade.

## O fluxo

```text
Phial.greet/2
  -> Jido.Signal ("greet")
  -> Phial.GreeterAgent
  -> Phial.Actions.Greet
  -> estado atualizado

Phial.chat/2
  -> Phial.ChatAgent (ReAct)
  -> modelo via ReqLLM
  -> tool call opcional: Greet ou DelegateToSwarm
  -> resposta final
```

## Requisitos

- Elixir 1.17 ou superior
- Erlang/OTP 26 ou superior

## Rodar localmente

```bash
mix deps.get
mix test
mix phial.greet Ada Lovelace
```

Saída esperada:

```text
Olá, Ada Lovelace! Você é a visita número 1.
```

Também é possível experimentar um processo persistente no IEx:

```elixir
iex -S mix
{:ok, pid} = Phial.start_agent("demo")
{:ok, first} = Phial.greet(pid, "Ada")
{:ok, second} = Phial.greet(pid, "Grace")
second.state.greeting_count
# 2
```

## Agente conversacional

Copie `.env.example` para `.env` e preencha somente a chave do provedor que
pretende usar. O arquivo `.env` é ignorado pelo Git e carregado automaticamente
pelo ReqLLM.

```dotenv
PHIAL_MODEL=openai:gpt-5-mini
OPENAI_BASE_URL=http://localhost:8000/v1
OPENAI_API_KEY=local
```

`OPENAI_BASE_URL` ativa o modo OpenAI-compatible. O Phial monta um model spec
explícito com `provider: :openai`, o ID extraído de `PHIAL_MODEL` e a URL
informada. Inclua `/v1` quando esse for o prefixo esperado pelo servidor.

Para um proxy autenticado, substitua `local` pelo token exigido pelo endpoint.
Se `OPENAI_BASE_URL` não estiver presente, o ReqLLM usa o endpoint normal do
provider selecionado.

Também são aceitos, por exemplo, modelos Anthropic e Google:

```dotenv
PHIAL_MODEL=anthropic:claude-haiku-4-5
ANTHROPIC_API_KEY=...
```

```dotenv
PHIAL_MODEL=google:gemini-2.5-flash
GOOGLE_API_KEY=...
```

Execute um único turno:

```bash
mix phial.chat "Cumprimente Ada"
```

Ou abra uma conversa persistente, encerrando com `/sair`:

```bash
mix phial.chat
```

O comando restringe explicitamente as ferramentas disponíveis a `greet`,
`delegate_to_search` e `delegate_to_swarm`. As chaves nunca são recebidas como
argumento nem registradas no estado do agente.

### Runtime inspector no navegador

Inicie a interface Phoenix LiveView:

```bash
mix phx.server
```

Abra [http://localhost:4000](http://localhost:4000). A página combina o chat
com a árvore real de processos BEAM e o stream de eventos da missão. Ela mostra
PIDs, estados, relações parent/children, mensagens A2A, tool calls e restarts em
tempo real, sem polling ou SPA separada.

Para uma demonstração determinística, peça explicitamente para usar a swarm:

```text
Use a swarm para comparar PostgreSQL, SQLite e DynamoDB para um SaaS multi-tenant.
```

Durante a execução, o botão **Kill** de um worker encerra aquele processo. O
supervisor o recria com outro PID e a missão continua. O orchestrator ainda não
tem botão de kill: orphan/adoption será uma etapa posterior do runtime.

### Usar a swarm dentro do chat

Abra o chat normalmente:

```bash
mix phial.chat
```

Então faça uma pergunta que justifique perspectivas paralelas, por exemplo:

```text
você> Compare PostgreSQL, SQLite e DynamoDB para um SaaS multi-tenant e me recomende um.
```

O `Phial.ChatAgent` decide chamar `delegate_to_swarm`. A tool cria researcher,
critic e scout como processos BEAM supervisionados, aguarda os três pareceres e
devolve a recomendação ao ReAct loop. O chat apresenta a resposta no mesmo turno
e continua vivo para perguntas seguintes.

## Swarm: agents are processes

O orchestrator cria três `Jido.AgentServer` independentes em paralelo:

```text
orchestrator
├── researcher
├── critic
└── scout
```

Cada worker executa seu próprio loop ReAct, envia o resultado ao pai por um
signal e é encerrado normalmente quando termina. A missão original permanece no
estado do pai. Se um worker morrer de forma anormal, a supervisão transitória o
reinicia com outro PID e o evento `child.started` faz o pai reenviar a missão.

Execute uma missão:

```bash
mix phial.swarm "Descubra qual banco usar para um SaaS multi-tenant e recomende um"
```

O terminal mostra a árvore de processos, status, mensagens e restarts. Para
demonstrar recuperação deliberadamente, mate um worker durante o raciocínio:

```bash
mix phial.swarm --kill researcher --kill-after 1500 "Compare PostgreSQL, SQLite e DynamoDB"
```

O fluxo termina com os três pareceres e uma recomendação sintetizada pelo
orchestrator. `--timeout` controla o limite total em milissegundos (padrão: 5
minutos). `PHIAL_ACTION_TIMEOUT_MS` controla o teto de cada Action/loop ReAct
(padrão: 5 minutos), importante para endpoints locais ou modelos lentos.

### SearchAgent dedicado com Firecrawl

O `Phial.ChatAgent` decide semanticamente quando uma resposta exige informação
externa ou mutável e chama `delegate_to_search`. Não existe classificador por
palavras-chave. A tool cria um `Phial.SearchAgent` em seu próprio processo BEAM;
esse agente possui somente `web_search(query, limit)` e sempre pesquisa antes de
responder. Ao terminar, o processo desaparece.

A capability usa o SDK oficial Elixir do Firecrawl para devolver títulos, URLs,
descrições e trechos Markdown ao ReAct loop. Os workers Researcher, Critic e
Scout não recebem acesso direto à web. Quando uma tarefa exige busca e análise
paralela, o ChatAgent pesquisa primeiro e pode enviar as evidências à swarm.

Configure no `.env`:

```dotenv
FIRECRAWL_API_KEY=fc-YOUR-API-KEY
```

Cada chamada aceita entre 1 e 5 resultados. O Phial limita o Markdown de cada
fonte para não inundar o contexto do modelo, orienta o SearchAgent a citar URLs e
registra input, output, duração e status no Event Stream. Para uma instalação
self-hosted, defina também `FIRECRAWL_BASE_URL` incluindo o prefixo `/v2`.

## Rodar com Docker

Se Elixir não estiver instalado no host:

```bash
docker run --rm -v "${PWD}:/app" --mount type=volume,source=phial_deps,target=/app/deps --mount type=volume,source=phial_build,target=/app/_build -w /app hexpm/elixir:1.18.4-erlang-27.3.4.15-alpine-3.21.7 sh -lc "mix local.hex --force && mix local.rebar --force && mix deps.get && mix test"
```

## Estrutura

- `Phial.GreeterAgent`: declara estado e roteamento de sinais determinísticos.
- `Phial.ChatAgent`: agente ReAct conversacional com tool calling.
- `Phial.SearchAgent`: processo ReAct efêmero dedicado exclusivamente à busca web.
- `Phial.Swarm.OrchestratorAgent`: mantém missão, PIDs, resultados e lifecycle.
- `Phial.Swarm.*Agent`: workers BEAM isolados por papel.
- `Phial.Swarm.Inspector`: visão textual da árvore viva.
- `Phial.Actions.Greet`: valida a entrada e transforma o estado.
- `Phial.Actions.DelegateToSearch`: cria, consulta e encerra um SearchAgent.
- `Phial.Actions.DelegateToSwarm`: expõe a swarm supervisionada como tool do chat.
- `Phial.Jido`: instância supervisionada do runtime Jido.
- `Phial`: pequena API pública para iniciar e chamar o agente.

Os testes validam estado, roteamento, registro da ferramenta e resolução do
modelo sem fazer chamadas externas. O comando `phial.chat` é o caminho de
validação ao vivo e requer a chave do provedor escolhido.
