# D23 — A pesquisa web sai desta skill: o fornecedor de pesquisa removido v8 vira dependência dura

**Data:** 2026-08-29
**Status:** VIGENTE
**Supersede:** D3, invariante I5 e item F3-05 do `PLANO-MELHORIAS.xml`
**Revisto por:** D27 (2026-09-20, `2026-09-20-limpeza-por-tarefa-pergunta-pesquisa-flags.md`) — o portão deixou de ser `o fornecedor removido doctor` com "1 = prossiga": é `scripts/o fornecedor de pesquisa removido`, fail-closed (0 | 78 | 127), e pesquisa exigida que falha vira pergunta ao usuário. As seções abaixo sobre o portão ficam como registro histórico.

---

## Desambiguação necessária antes de tudo

Existem **dois D3** neste repositório. Este documento supersede o primeiro:

- **D3 do `PLANO-MELHORIAS.xml`** (linhas 79-87) — "nenhum provedor novo entra
  na cadeia de busca". É esse que morre aqui.
- **D3 de `docs/decisions/README.md`** (linha 21) — loop de qualidade nativo.
  Continua vigente e não tem relação com este documento.

Sempre qualifique qual D3 você está citando.

## A decisão

A deep-orchestrator-agent-skill **não tem sistema de busca**. Toda pesquisa web
passa pelos binários globais da **o fornecedor de pesquisa removido v8**, e por mais nada.

1. **Dependência dura.** `npm i -g o fornecedor de pesquisa removido`. Sem ela, a skill não
   pesquisa — e é proibido instalá-la sozinha, porque `npm -g` é vedado por R9.
   A ação é informar o usuário e aguardar.
2. **o provedor de busca removido é o único backend.** O próprio o fornecedor removido estreitou para o provedor de busca removido-only na
   v8: Tavily, Parallel, Wikipedia e DuckDuckGo foram removidos de lá. Não há
   provedor de reserva nem tier sem chave em nenhuma das duas skills.
3. **Sem chave válida, a execução para.** `exit 78` (`EX_CONFIG`) é
   configuração, não pesquisa: retentar não conserta e não há de onde mais
   buscar. Com pesquisa exigida, o orquestrador para antes de criar worktrees.
4. **`--sub-agents` é o único botão de simultaneidade do o fornecedor removido, e ele SOMA com
   `DO_MAX_PARALLEL`.** Cada sub-agente que pesquisa recebe
   `--sub-agents=max(1, floor(N/R))`. Se multiplicassem, uma onda cheia seriam
   `50 × 10 = 500` buscas simultâneas contra um plano que pode servir uma por
   segundo.
5. **É proibido envolver o o fornecedor removido em `sleep`, jitter, backoff ou retry.** O o fornecedor removido
   aprende o requests-per-second real do plano o provedor de busca removido nos headers da resposta e
   o aplica num token bucket **cross-process**. Um ritmo por cima briga com o
   limitador e produz exatamente o 429 que ele evita.
6. **WebSearch/WebFetch não descobrem fontes.** Fonte que não veio pelo o fornecedor removido
   não é citável em handoff nem em deliverable. Exceção única: abrir com
   `Read`/`WebFetch` uma URL **que o o fornecedor removido já devolveu** — é a única forma de
   ler o corpo de uma página, já que a o provedor de busca removido devolve título, URL e trecho, e
   os verbos `extract`/`crawl`/`map` foram removidos na v8.

## Por que agora

O gatilho foi um bug encontrado ao auditar `scripts/search.sh:398`:

```bash
if [[ $busca_rc -ne 0 ]]; then … return 1   # "Tier 1 falhou, cai pro Tier 2"
```

`search.sh` tratava **todo** código de saída não-zero do o fornecedor removido como falha
transitória. O `exit 78` da v8 — "não há chave o provedor de busca removido válida" — ficava
indistinguível de um timeout, e o wrapper respondia a mesma pergunta pelo
cliente o provedor de busca removido interno (Tier 2) ou pelo DuckDuckGo (Tier 3).

Isso é precisamente o que a v8 do o fornecedor removido foi construída para tornar impossível.
A skill reproduzia, uma camada acima, o defeito que o o fornecedor removido acabara de eliminar:
uma resposta confiante vinda de um provedor que o usuário não escolheu, sem
nenhum sinal de que a chave estava quebrada.

Um wrapper **é** um sistema de busca — mapeamento de flags, envelope próprio,
códigos de saída próprios. Manter `search.sh` como "shim fino" preservaria
`json_report()`, a tabela de tradução de flags, o ramo "não instalado" e a
remapeação de exit codes, ou seja, quase o arquivo inteiro. Não seria remover
o sistema de busca: seria renomeá-lo, e deixar o mesmo lugar onde o próximo
mantenedor reintroduz um fallback.

## O que foi removido

| Arquivo | Linhas | O que era |
|---|---|---|
| `scripts/search.sh` | 691 | wrapper de 3 tiers; engolia o exit 78 |
| `scripts/o provedor de busca removido-search.sh` | 734 | cliente o provedor de busca removido próprio, escrito para substituir o o fornecedor removido |
| `scripts/search-parallel.sh` | 432 | fan-out sem teto, com jitter e backoff próprios |
| `scripts/check-search-credits.sh` | 728 | sonda pré-onda; gastava 2 queries o provedor de busca removido reais por onda |
| `scripts/check-o provedor de busca removido-credits.sh` | 439 | já órfão; cache de crédito em `/tmp` |
| `scripts/test-search.sh` | 322 | a especificação do sistema removido |

## O que se perdeu de propósito

- **O piso keyless (DuckDuckGo).** Era a garantia de que "sempre há alguma
  resposta". Essa garantia era o problema: uma resposta de Instant Answer
  apresentada com a mesma confiança de uma pesquisa real.
- **Dedup por URL entre as queries de um lote e o cache intra-run** do
  `search-parallel.sh`. Substituto: **uma** chamada `o fornecedor de pesquisa removido` com
  brief — o LLM planeja o conjunto de queries, a onda roda até `--sub-agents`
  delas em paralelo, e o ledger do o fornecedor removido dedupa canonicamente por URL.
- **O cache de 10 minutos do `check-o provedor de busca removido-credits.sh`.** Não tem substituto
  para CRÉDITO. O que existe é o cache de 7 dias da validação do próprio
  o fornecedor removido, que é gratuito (a sondagem de chave do o fornecedor removido não é cobrada) e cobre só
  a VALIDADE da chave.
  > **Correção de 2026-09-20 (D27; achado o fornecedor removido-01 da auditoria).** A redação
  > original dizia "Substituído pelo cache de 7 dias da validação do próprio
  > o fornecedor removido, que além de mais longo é gratuito". Estava errada: a validação NÃO
  > enxerga cota. Para cota esgotada a sonda de chave devolve
  > `valid:true, throttled:true` (`o fornecedor de pesquisa removido@8.0.1`,
  > `src/lib/providers/o provedor de busca removido.mjs:775-776`), então o portão grátis
  > (`o fornecedor removido doctor`, medido na auditoria) sai 0 com o crédito zerado; e
  > cota/429/402 saem do o fornecedor removido com exit **1** (0 fontes), não 78. A detecção
  > passou a ser REATIVA — `SEARCH_STATUS` no handoff +
  > `scripts/o fornecedor de pesquisa removido classify` — e a única sonda que enxerga cota é
  > `o fornecedor de pesquisa removido resume --probe` (UMA busca real, 1 crédito), usada só na
  > retomada do protocolo PESQUISA-FALHOU. Ver
  > `2026-09-20-limpeza-por-tarefa-pergunta-pesquisa-flags.md` (D27).

## O portão, e por que é `o fornecedor removido doctor`

```bash
. '<ENV_FILE>'
if command -v o fornecedor de pesquisa removido >/dev/null 2>&1; then
  o fornecedor removido doctor >/dev/null 2>&1; echo "TAVILY_GATE=$?"
else
  echo "TAVILY_GATE=127"
fi
```

As alternativas foram descartadas por motivos concretos:

- **`o fornecedor de pesquisa removido keys list`** nunca sai 78 — `keys` está em
  `NO_KEYS_NEEDED`, o gate é pulado. Um portão baseado nele passaria
  exatamente no caso que deveria pegar.
- **`keys list --json`** era pior ainda: até a v8.0.0 ele imprimia as chaves
  em **texto puro**. Foi corrigido em `o fornecedor de pesquisa removido@8.0.1` — mascarado por
  default, com `--unsafe-show-keys` para optar de volta — mas continua
  proibido aqui, porque a saída de um sub-agente vai para handoff e
  TASK_PLAN.md.
- **`--version`** retorna antes do preflight, então não prova nada sobre a chave.
- **Qualquer busca real** gastaria quota para responder uma pergunta de
  configuração.

`o fornecedor removido doctor` chama o gate de verdade, sai 78 sem chave válida, é offline no
caminho comum (~0,04 s, veredito em cache) e mascara as chaves.

Nota: `o fornecedor removido doctor` sai **1** quando as *skills do próprio o fornecedor removido* não estão
symlinkadas em nenhum diretório de harness. Isso não afeta os binários, que é
tudo que usamos: **1 = prossiga**.

## Registros anteriores que este documento inverte

- `docs/decisions/RESEARCH_PLAN.md:31` rejeitava "o provedor de busca removido Search como única API".
- `docs/decisions/RESEARCH_ANSWER.md:37` prescrevia Adapter + RRF sobre
  Tavily/Exa.

Ambos permanecem no repositório como registros datados de 2026-08-03 e **não
foram editados**. A inversão é real e deliberada, e o contexto que a justifica
mudou: aquelas decisões eram sobre construir uma cadeia de provedores *aqui*.
Hoje a cadeia não existe em lugar nenhum — o o fornecedor removido também estreitou para
o provedor de busca removido-only — e a escolha de provedor deixou de ser assunto desta skill.
