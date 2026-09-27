# CONTRATO.md — contratos de máquina do deep-orchestrator-agent-skill (v4.2.0)

> **Fonte única de especificação dos contratos de máquina.** Os testes
> (`scripts/test-contrato.sh`, mais G12/B01 do `test-surf-gate.sh`) exigem que
> os donos reais (`scripts/*`, `SKILL.md` e módulos `references/`+`prompts/`)
> contenham estes literais **byte-a-byte**. Mudou um lado? Muda o contrato e o
> teste no MESMO commit. Nunca crie uma segunda casa para o que já está aqui.
>
> Dono funcional = onde o literal é GERADO/IMPRESSO. Este ficheiro é a
> ESPECIFICAÇÃO que os testes comparam contra o dono funcional.

---

## 1. Flags de invocação (dono funcional: `scripts/do-context.sh`, tabela do cabeçalho)

Regra: `--flags='<tokens>'` é UM argv; o `do-context.sh` é o ÚNICO validador.
Flag VENCE variável de ambiente; token ausente → env como fallback → default.

| Flag | Variável | Default | Validação |
|---|---|---|---|
| `plan=on\|off` | `DO_PLAN_APPROVAL` | off | — |
| `max-parallel=N` | `DO_MAX_PARALLEL` | 50 | inteiro > 0 |
| `surf-sub-agents=N` | `DO_SURF_SUB_AGENTS` | 10 | inteiro 1..20 |
| `wt=<nome>` | `DO_WT_ROOT=1` + `DO_WT_NAME` | — | cria/reentra worktree irmã |
| `no-stop` | `DO_NO_STOP=1` | — | — |
| `no-evolve` | `DO_EVOLUTION_SURVEY=0` | — | — |
| `no-test` | `DO_TEST_MODE=none` | full | contradiz `only-e2e` → exit 2 |
| `only-e2e` | `DO_TEST_MODE=e2e` | full | — |
| `do-question` | `DO_QUESTION=1` | — | — |

`--boundary='<token>'` (opcional, UM argv): primeiro token que fechou a zona de
prefixo; normaliza (`-` iniciais, minúsculas, `_`→`-`); flag mal escrita → exit 2
com sugestão; texto de tarefa → ignorado.

### 1.1 Concorrência (decisão D-G)

- **`max-parallel=N`** é a flag ÚNICA de concorrência global: teto de
  sub-agentes *in-flight* por onda (features + subwaves + revisores + revisor de
  plano ≤ `DO_MAX_PARALLEL`).
- **`surf-sub-agents=N`** é sub-flag da PESQUISA: teto global de buscas
  simultâneas, dividido entre as sub-tarefas que pesquisam — **nunca**
  multiplicado por `DO_MAX_PARALLEL`.
- Referência de dimensionamento (MiMo-V2.6): 100 RPM / 10M TPM por conta,
  ~46 t/s de saída → **6–12 sub-agentes simultâneos** é o realista; acima disso
  só latência e 429.

### 1.2 Modelo (decisão D-H)

**TUDO corre no mesmo modelo `mimo-v2.6-pro`** (`model: inherit` no
orquestrador e em todos os sub-agentes). PROIBIDO tiering por modelo,
`flash` ou qualquer downgrade para "tarefas mecânicas". Nenhum template pode
sugerir outro modelo.

---

## 2. Exit codes

### 2.1 `do-context.sh` (FASE 0)
`0` ok · `2` flag inválida/desconhecida/mal escrita, `--flags=` repetido,
combinação contraditória, `DO_*` inválido ou `SKILL_HOME` não resolvido ·
`3` cwd fora de repositório git · `4` HEAD destacado · `5` repo sem commits ·
`6` índice sujo · `7` path/BASE_BRANCH com caractere quebra-estado (aspas,
TAB, newline) · `8` `git rev-parse` inesperado · `9` colisão de namespace de
branch.

### 2.2 `do-wt.sh` por subcomando
| Subcomando | Exit codes semânticos |
|---|---|
| `new <kind> <nome>` | 6 = sobra de onda anterior (kind feature\|fix\|prep); 1 = falha (lock/dup) |
| `integrate <nome> "<msg>"` | 4 = VAZIO (filha sem mudança); 1 = merge falhou (rc do merge) |
| `gate <nome> [--e2e]` | 0 = verde (chama `finish` sozinho); 3 = já rodando ("AGUARDE"); 4 = vermelho (nada limpo); 5 = sem etapa configurada |
| `finish <nome> [--gate-ok]` | 3 = gate rodando; 4 = gate vermelho; 1 = falha |
| `close <nome> [--discard "<motivo>"]` | 1 = recusa (MERGED/gate-pending → "use finish"; sujo sem `--discard`) |
| `assert-clean [--wave N]` | 0 = limpo; 1 = sobra (imprime tabela com comando de conserto) |
| `purge` | 0 = "PURGE OK" (ledger E realidade fechados); 1 = falha de remoção; 3 = houve NEVER-MERGED ou MERGED-PARTIAL (bloco "PURGE: NUNCA INTEGRADAS / PARCIAIS" — obrigatório no relatório final) |
| `sweep` | 0 = ok; != 0 = gate-pending/REVERTED/feature\|fix ACTIVE (com comando de conserto) |
| `undo <nome>` | 1 = recusa (squash divergente do ledger) |
| `checklist [final]` | 0; funciona SEM ENV_FILE (igual `--help`) |

### 2.3 `surf-gate.sh`
`gate` **SEMPRE exit 0** — o veredito vem na linha `SURF_GATE=<0|78|127>`
(fail-closed: qualquer exit ≠ 0 do binário do portão → 78).
`classify` → `OK|EMPTY|FAILED_QUOTA|FAILED_OTHER|BLOCKED_78|KILLED_143|USAGE_2`.
`resume [--probe]` → `RESUME=OK|STILL_BLOCKED`.
`choose no-search|search` → grava `search-mode` (`SURF_MODE=no-search`).
`pause` → grava `$DO_STATE/search-pause.md` + imprime o bloco da pergunta (§5).

### 2.4 Portão do plano
`plan-approval.sh round`: `0` aprovado · `10` anotado · `11` fechado ·
`12` timeout · `13` falha da ferramenta · `14` orçamento · `2` uso/deriva de
título. `check-plannotator.sh`: `0` disponível · `1` ausente · `2` erro.

### 2.5 Evolução/prefs/distribuição
`do-prefs.sh`: `0/2/3` · `evolution-survey.sh`: `0/2` · `check-install.sh`:
`0` completa · `1` incompleta · `2` erro.

---

## 3. Marcadores de stdout (contrato de leitura do orquestrador)

| Marcador | Dono funcional | Semântica |
|---|---|---|
| `SNAPSHOT=<path>` | `do-wt.sh integrate` | caminho do snapshot `int-<nome>` criado |
| `GATE VERDE — <nome> fechado` | `do-wt.sh gate` | gate verde; filha+snapshot fechados pelo SCRIPT |
| `PURGE OK` | `do-wt.sh purge` | ledger e realidade fecharam |
| `PURGE: NUNCA INTEGRADAS / PARCIAIS` | `do-wt.sh purge` (rc 3) | bloco obrigatório no relatório final |
| `ASSERT-CLEAN OK` / `ASSERT-CLEAN FALHOU` | `do-wt.sh assert-clean` | portão inter-onda |
| `RESUMO:` (tabela do ledger) | `do-wt.sh ledger` | fonte da seção "## Não integrado" |
| `SURF_GATE=<rc>` [`SURF_CODE=<code>`] | `surf-gate.sh gate` | veredito fail-closed |
| `RESUME=OK\|STILL_BLOCKED` | `surf-gate.sh resume` | retomada da pesquisa |
| `SURF_MODE=no-search` | `surf-gate.sh choose` | modo sem pesquisa escolhido |
| ÚLTIMA linha de stdout = caminho do ENV_FILE | `do-context.sh` | contrato de captura |

---

## 4. Formatos de estado

### 4.1 ENV_FILE (`$DO_STATE/env`)
Linhas `VAR='valor'` + funções `gwt`/`gch`/`gstatus`/`gassert` embutidas.
Anti-stale: o trio `DO_STATE = $DO_HOME/run-$RUN_ID` identifica a execução;
ENV_FILE de outra execução é rejeitado. Carrega ≥35 variáveis (RUN_ID, DO_STATE,
DO_WT, DO_SURF_GATE, DO_PLAN_APPROVAL_SH, DO_PREFS, DO_SURVEY, DO_TEST_MODE,
DO_QUESTION, DO_SURF_SUB_AGENTS, DO_MAX_PARALLEL, ...).

### 4.2 `owned.tsv` — 11 colunas TSV (fonte ÚNICA de alvos; nunca varredura)
`1 run_id · 2 kind · 3 name · 4 branch · 5 path · 6 base_sha · 7 pre_merge_sha ·
8 post_merge_sha · 9 status · 10 parent · 11 outcome` — parent/outcome nunca
vazios (`-`). Colunas 7/8 podem ser vazias (cuidado com `IFS read`).
Outcomes: `- | MERGED | EMPTY | DISPOSABLE | MERGED-PARTIAL:<motivo> |
NEVER-MERGED:<motivo>`. Serialização por lock (`flock` ou `mkdir` — macOS).

### 4.3 Layout de `$DO_STATE`
`gate/<etapa>.cmd` · `gates/<nome>.log|.rc|.tip` · `squashes/<nome>` ·
`partial/<nome>` · `search-mode` · `search-pause.md` · `surf-gate.last` ·
`plan-approval/rev-NNN.md` + `trail.tsv` · `question/pendente.md` ·
`evolution/` · `env`.

---

## 5. Literais congelados (byte-a-byte)

| Literal | Dono funcional | Vistas que têm de casar |
|---|---|---|
| `SEARCH_STATUS: NOT_NEEDED \| OK \| EMPTY \| FAILED_QUOTA \| FAILED_OTHER \| BLOCKED_78` | handoff do sub-agente | SKILL.md/módulos + `prompts/search-prompts.md` |
| Bloco da pergunta PESQUISA-FALHOU (título `===== PESQUISA-FALHOU — …`, opções `  [1]`–`  [4]`, adendos `Rode os comandos…` / `Outros: remover chave morta…`) | `surf-gate.sh print_question` | protocolo em `references/research-protocol.md` |
| `PURGE_RC` | SKILL.md/módulos | cartão da FASE 4 |
| `## Não integrado` | template do relatório final | `references/final-report.md` |
| `Tarefa concluída PARCIALMENTE` | template do relatório final | `references/final-report.md` |
| `MERGED-PARTIAL` | `do-wt.sh` (outcome) | SKILL.md/módulos |
| `checklist final` | `do-wt.sh` (subcomando) | SKILL.md/módulos |
| `--boundary=` | `do-context.sh` | SKILL.md/módulos |
| Sequência dos 13 `<step order>` da FASE 3: `0 1 2 3 3.5 4 4.5 5 6 7 8 9 10` | FASE 3 (hoje SKILL.md; depois `references/execute-wave.md`) | cartão `do-wt.sh checklist` |
| Sequência do checklist final (FASE 4): `0 1 2 3 4 5 5.5 6 7 7.5 8` | FASE 4 (hoje SKILL.md; depois `references/commit-final.md`) | cartão `do-wt.sh checklist final` |

### 5.0 Linha SEARCH_STATUS (verbatim — byte-a-byte; os `\|` da tabela acima são só escapagem de renderização)

```
SEARCH_STATUS: NOT_NEEDED | OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78
```

### 5.1 Bloco da pergunta PESQUISA-FALHOU (verbatim)

Gerado por `surf-gate.sh print_question` (dono funcional). O protocolo em
`references/research-protocol.md` (hoje, o CDATA `question-text` do SKILL.md)
tem de conter estas linhas byte-a-byte:

```
===== PESQUISA-FALHOU — a pesquisa exigida não pôde ser feita; a decisão é SUA =====
  [1] Adicionei/troquei a chave Brave — tente de novo  (`surf-research-skill keys add --provider brave <CHAVE>` | terminal separado: `surf add`)
  [2] Ajustei o plano/cota ou esperei o cooldown — tente de novo  (`surf-research-skill keys reset --provider brave` limpa burn/cooldown em cache)
  [3] Seguir SEM pesquisa — premissas ficam marcadas NÃO VERIFICADAS no plano, handoffs e relatório
  [4] Abortar — fecho o que está aberto (purge) e entrego relatório parcial
Rode os comandos no SEU terminal e NÃO cole a chave no chat (iria para o transcript). `surf` e `surf add` exigem TTY.
Outros: remover chave morta `surf remove brave <i>` · revalidar `surf validate brave` · painel de cota https://api-dashboard.search.brave.com
```

---

## 6. Lista canónica de módulos de conteúdo da skill (para os testes)

O conteúdo da skill vive nestes ficheiros (atualizar esta lista no MESMO commit
de qualquer extração — os testes G12/B01 resolvem o conteúdo através dela):

```
.claude/skills/deep-orchestrator-agent-skill/SKILL.md   # router (sempre)
# references/*.md  e  prompts/*.md  entram aqui à medida do split v4.2.0
```
