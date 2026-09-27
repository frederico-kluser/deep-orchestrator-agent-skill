# Análise de scripts/ e prompts/ — deep-orchestrator-agent-skill v4.1.0

> Análise prévia à decomposição do SKILL.md (3 306 linhas) em sub-skills. Objetivo:
> saber o que os scripts e prompts JÁ fazem para não duplicar na refatoração.
> Referências: `scripts/README.md`, cabeçalhos dos scripts, `SKILL.md`
> (`.claude/skills/deep-orchestrator-agent-skill/SKILL.md`), testes de aceitação.

---

## 1. Scripts — responsabilidade, contrato e fase

### Core de orquestração

**`scripts/do-context.sh`** (69 900 B / 1 229 linhas) — **FASE 0**. Delimita a
"raiz-de-mundo": resolve MODE (normal/contido), BASE_DIR, BASE_BRANCH, MAIN_ROOT,
CHILD_ROOT, BRANCH_NS, SKILL_HOME e grava o **ENV_FILE** (`$DO_STATE/env`) que
todo script posterior deve sourcear (heredoc em `do-context.sh:1057-1131`; o
caminho é a ÚLTIMA linha de stdout, `do-context.sh:1229`). É o **único
validador de flags** (`--flags='<tokens>'` + `--boundary='<token>'`, tabela flag→
variável no cabeçalho `do-context.sh:20-43`); anti-stale de ENV_FILE herdado
(`do-context.sh:90-105`); cria/reentra wt-root com `wt=<nome>` (re-executa a
FASE 0 dentro, `do-context.sh:718-770`); baselines de contenção. Exporta
helpers no ENV_FILE: `gwt`, `gch`, `gstatus`, `gassert` (`do-context.sh:1116-1129`)
+ ~35 variáveis (RUN_ID, DO_STATE, DO_WT, DO_SURF_GATE, DO_PLAN_APPROVAL_SH,
DO_PREFS, DO_SURVEY, DO_TEST_MODE, DO_QUESTION, DO_SURF_SUB_AGENTS...). Exit
codes 0/2/3/4/5/6/7/8/9 documentados em `do-context.sh:54-69`.

**`scripts/do-wt.sh`** (110 503 B / 1 955 linhas) — **FASE 1, 3 e 4**. Ciclo de
vida das worktrees-filhas + contenção. 21 subcomandos no dispatch
(`do-wt.sh:1933-1955`): fluxo por tarefa (`new`, `integrate`, `gate-set`, `gate`,
`finish`, `close`, `assert-clean`, `sweep`, `purge`, `ledger`, `checklist`,
`verify`, `status`, `stage-delta`, `clean-ignored-delta`, `wave-files`) e
primitivos/reparo (`merge`, `undo`, `remove`, `drop-branch`, `mark`). Fonte de
alvos é SEMPRE o ledger `owned.tsv` (11 colunas TSV, `do-wt.sh:1-160`) sob lock
(`owned_lock`, flock ou mkdir, `do-wt.sh:277-313`). Contrato de stdout com
marcadores que o SKILL.md lê: `SNAPSHOT=<path>`, `GATE VERDE — <nome> fechado`,
`PURGE OK`, `ASSERT-CLEAN OK/FALHOU`, tabela do `ledger` + `RESUMO:`. Exit codes
semânticos: `new` 6 (sobra de onda)/1; `integrate` 1/4 (VAZIO); `gate` 0/3
(em curso)/4 (vermelho)/5; `finish` 3/4/1; `purge` 1/3 (há NEVER-MERGED/
MERGED-PARTIAL). `--help` e `checklist` funcionam SEM ENV_FILE (`do-wt.sh:215-230`).

**`scripts/surf-gate.sh`** (19 298 B / 400 linhas) — **FASE 0 passo 6, FASE 2
(pós-plano), FASE 3 passo 0 de cada onda, e sub-agentes**. Único intérprete do
estado da surf-agent-skill. `gate` (fail-closed: 0/78/127 na linha
`SURF_GATE=`, SEMPRE exit 0), `classify <exit> <out> <err>` (OK|EMPTY|
FAILED_QUOTA|FAILED_OTHER|BLOCKED_78|KILLED_143|USAGE_2), `pause` (grava
`$DO_STATE/search-pause.md` + imprime o bloco da pergunta, `surf-gate.sh:224-246`),
`resume [--probe]` (`RESUME=OK|STILL_BLOCKED`), `choose no-search|search`
(grava `$DO_STATE/search-mode` → `SURF_MODE=no-search`). Mascara chaves Brave
(`scrub`, `surf-gate.sh:72`). Serve o orquestrador E o template de sub-agente
(handoff `## SEARCH_STATUS`).

### Portão de aprovação do plano (FASE 2.5)

**`scripts/check-plannotator.sh`** (17 272 B / 427 linhas) — resolve/instala o
binário do Plannotator (versão mínima 0.19.1, sonda por `annotate` sem
argumento, `--install` só com `--minimal --non-interactive`, nunca sobrescreve,
nunca root). Exit 0/1/2. Serve o passo 2 da FASE 2.5.

**`scripts/plan-approval.sh`** (21 542 B / 474 linhas) — UMA rodada de aprovação:
snapshot imutável do `$PLAN_DOC`, título travado na rev. 1 (deriva = exit 2),
`plannotator annotate <snap> --gate --json </dev/null` sob timeout, decisão lida
do envelope JSON (nunca do texto). Travas de rede por default
(PLANNOTATOR_SHARE=disabled, PLANNOTATOR_REMOTE=0). Subcomandos: init, round,
status, feedback, doc, origin, title, approved (`plan-approval.sh:462-470`).
Exit do `round`: 0 aprovado · 10 anotado · 11 fechado · 12 timeout · 13 falha da
ferramenta · 14 orçamento · 2 uso/deriva de título. Serve a FASE 2.5 inteira.

### Auto-evolução (FASE 4 passo 7.5 e FASE 0 passo 0)

**`scripts/do-prefs.sh`** (27 335 B / 612 linhas) — motor de PREFERÊNCIAS em
`.deep-orchestrator-preferences/` (projeto: `project-config.md`, `learnings.md`,
`pending/`; skill: `global-tips.md`, `pending/`), tudo gitignored. Subcomandos:
load, add-project, add-global, pending-add, pending-list, ensure-gitignore,
status. Exit 0/2/3. Consumido por evolution-survey.sh e pelo passo 8.5 da FASE 1
(`SKILL.md:848`).

**`scripts/evolution-survey.sh`** (23 893 B / 555 linhas) — a PERGUNTA DE
EVOLUÇÃO em texto: `ask` (monta `pendente.md`), `answer "<códigos>"` (gramática
`1:b2`, "nada", `config: <texto>`), `apply` (roteia p/ do-prefs.sh; idempotente,
nunca falha a execução), `dismiss`, `status`. Exit 0/2. FASE 4 passo 7.5 (ask) e
FASE 0 passo 0 — ESTADOS PENDENTES (answer/apply, `SKILL.md:588-591`).

**`scripts/evolve-skill.sh`** (20 076 B / 489 linhas) — evolução do CORPO
(SKILL.md/prompts/docs): `search` (prefs + prompts + SKILL.md), `diff`, `apply`
(branch `evolve/YYYY-MM-DD`, NUNCA merge sozinho, allowlist de paths), `status`.
`add`/`consolidate` saíram (exit 2 apontando do-prefs.sh). FASE 1 passo 8.5.

### Libs e distribuição

**`scripts/lib/evolve-common.sh`** (327 linhas) — validadores/parsers do formato
de bloco (normalize, parse_fields, validate_candidate, secret_scan, split_entries,
next_id_for, is_untrusted_source). Fonte única de do-prefs/evolution-survey/
evolve-skill.
**`scripts/lib/plannotator-common.sh`** (161 linhas) — contrato de máquina do
Plannotator (resolve_bin, detect_harness, envelope JSON via jq/python3,
snapshot/título). Fonte única de plan-approval.sh.
**`scripts/check-install.sh`** (132 linhas) — prova de instalação completa
(SKILL.md + 8 scripts + 2 libs + 5 prompts; exit 0/1/2). Não é citado no
SKILL.md — é da distribuição/testes.

### Testes (herméticos, sem rede — 1 064 asserções, `scripts/README.md:136`)

- `test-contencao.sh` (1 281 linhas, 309 asserções A1..A56) — modo contido,
  contenção, conflito, locks, fechamento por tarefa (A35-A56 cobrem o ciclo
  integrate/gate/finish/close/purge/sweep v4.1.0).
- `test-flags.sh` (598 linhas, 307 asserções FL1..FL16) — flags da FASE 0,
  anti-stale, `--boundary`, wt=.
- `test-plan-approval.sh` (758 linhas, 139 asserções) — Plannotator FAKE; os
  seis exit codes de `round`, snapshot imutável, deriva de título.
- `test-surf-gate.sh` (801 linhas, 228 asserções G0..G13) — portão fail-closed,
  classify, pause/resume, orçamento `--sub-agents`, e **G12: contratos cruzados**
  (literais iguais em SKILL.md × scripts × prompts).
- `test-evolve.sh` (431 linhas, 81 asserções) — prefs/survey/evolve.

## 2. prompts/ — conteúdo e consumidores

| Ficheiro | Conteúdo | Quem consome |
|---|---|---|
| `ecc-prompts.md` (31 KB) | 7 templates ECC (System Prompt Base, Planning, Code Review, Security Review, Memory, Continuous Improvement, Clone-Analyze-Discard) + índice de placeholders `{{...}}` e regra de precedência do `{{TEST_POLICY}}` | Orquestrador ao montar prompts de delegação (`SKILL.md:2148`) e o revisor adversarial (categorias = template #3, `SKILL.md:2303`) |
| `ecc-skills.md` (29 KB) | 7 skills portadas (tdd-workflow, security-audit, docs-generator, research-deep-dive, memory-vault, clone-analyze, code-quality-gate) em frontmatter YAML + workflow | Testing subwave (skill #1, `SKILL.md:2387`), notas do modo e2e (`SKILL.md:2444`) e rodapé do relatório (`SKILL.md:3293-3294`) |
| `search-prompts.md` (39 KB) | Contrato de FORMULAÇÃO de query (8 categorias, refinamento, verificação); header fixa o contrato surf (exit codes, SEARCH_STATUS) | Template de sub-agente (`SKILL.md:2144`); testado contra SKILL.md em `test-surf-gate.sh:685` |
| `plan-approval-prompts.md` (13 KB) | Templates da FASE 2.5: esqueleto do `$PLAN_DOC`, título imutável, feedback, regeração | **NÃO referenciado pelo SKILL.md (0 ocorrências)** — só `check-install.sh:108` e `test-surf-gate.sh:690` |
| `evolution-guide.md` (11 KB) | Framework de decisão da evolução (o que persistir, scope project/global, memória ≠ política) | Agente de evolução (`SKILL.md:2758` "FILTRO — leia-o") + humana |

## 3. Mapa de acoplamento — duplicações SKILL.md × scripts

O `test-surf-gate.sh:673` assume explicitamente: *"Cópias literais de um mesmo
contrato vivem em arquivos de donos diferentes"*. As duplicações congeladas por
teste (G12) são as mais perigosas de partir:

1. **Tabela de flags** — existe em 4 lugares: cabeçalho do `do-context.sh:20-43`,
   `SKILL.md:601-673` (passo 1), `argument-hint` do frontmatter e README(s).
   G12 exige as 9 flags nos três.
2. **Bloco da pergunta PESQUISA-FALHOU** — texto FIXO de `surf-gate.sh:224-240`
   (título, opções [1]-[4], adendos) duplicado literalmente no protocolo do
   SKILL.md (`SKILL.md:288-360`); G12 compara linha a linha.
3. **Linha `SEARCH_STATUS:`** — idêntica em `SKILL.md:2232` e
   `search-prompts.md` (G12).
4. **Cartão/checklist da onda** — `do-wt.sh cmd_checklist` (`do-wt.sh:161-215`)
   re-encoda os `<step order>` das FASES 3 e 4 com numeração CONGELADA (teste
   B01: passos do cartão ⊆ `<step order>` do SKILL.md). Mudar um passo do
   SKILL.md exige editar um heredoc dentro de um script bash.
5. **Semântica dos subcomandos/exit codes do do-wt.sh** — descrita em 3 camadas:
   cabeçalho/--help (`do-wt.sh:1-160`), tabelas do `scripts/README.md:17-53` e
   prosa das regras R3-R6 + FASE 3 passo 7 do SKILL.md (rc 4 = VAZIO/vermelho,
   rc 6 = sobra, rc 3 = aguarde...).
6. **Contrato de máquina do Plannotator** (1 linha JSON, exit sempre 0, `--gate`
   obrigatório) — em `lib/plannotator-common.sh`, `plan-approval.sh`,
   `scripts/README.md:174-180` e `plan-approval-prompts.md`.
7. **Esqueleto do `$PLAN_DOC`** — `plan-approval-prompts.md` ("Esqueleto", título
   imutável) e `SKILL.md:1143-1165` descrevem o mesmo documento; o SKILL.md nem
   cita o ficheiro de prompts (ver §2).
8. **Filtro de evolução** ("o que persistir") — `evolution-guide.md` e o prompt do
   agente de evolução (`SKILL.md:2742-2807`) repetem os critérios.

**Scripts que fazem demais (política dentro do código):** `do-wt.sh checklist` é
instrução disfarçada de script (justificado: re-ancoragem pós-compactação, mas é
o pior ponto de sincronização). `do-wt.sh new` embute política de ondas (recusa
kind feature/fix/prep com sobra; recusa teste com DO_TEST_MODE=none) — aqui está
BEM (enforcement determinístico).

**Instrução da skill que devia ser script:** o finder de casa da skill é uma
one-liner bash embutida no SKILL.md (`SKILL.md:702`, loop DO_CTX com 6
candidatos) — lógica de infraestrutura dentro do prompt; `do-context.sh` já
deriva SKILL_HOME sozinho (`do-context.sh:884-886`). Os templates de sub-agente
do SKILL.md (`SKILL.md:1994-2810`, ~800 linhas) sobrepõem-se aos templates ECC
(o G12 até exige que "TDD Workflow" NÃO esteja no SKILL.md, mas o ecc-skills.md
mantém a skill #1 com meta de 80% — salvo pela nota de precedência do
`{{TEST_POLICY}}`).

## 4. O que já é modular vs monólitos

**Modularizado:** prompts/ (5 ficheiros temáticos), scripts/ (1 executável por
responsabilidade), libs compartilhadas (`evolve-common.sh`, `plannotator-common.sh`
— fonte única de parsers), testes separados por domínio, `docs/decisions/` com o
histórico de decisões (D1-D23). O sistema de busca próprio foi REMOVIDO na v4.0
(D23) — bom precedente de poda.

**Monólitos e candidatos a decomposição:**
- **`do-wt.sh` (1 955 linhas)** — sim, é o melhor candidato. Domínios
  identificáveis: (a) primitivas de ledger/lock/guardas (`row_get/row_set/
  owned_lock/guard_child`, `do-wt.sh:230-550`) → `lib/wt-ledger.sh`; (b) merge/
  undo/re-integração (`do-wt.sh:630-1001`) → `do-wt-merge.sh`; (c) gate/
  integrate/finish/snapshots (`do-wt.sh:1428-1816`) → `do-wt-gate.sh`;
  (d) relatório/limpeza final (ledger/purge/sweep/verify/stage-delta/checklist,
  `do-wt.sh:1147-1932`) → `do-wt-report.sh`. Os testes (A1..A56) exercitam o
  binário pelos subcomandos, o que torna a decomposição atrás do dispatch
  (`do-wt.sh:1933-1955`) de baixo risco.
- **`do-context.sh` (1 229 linhas)** — decomponível em: parsing de flags/
  boundary (`:116-330`), resolução git/MODE/placement (`:340-955`), escritor do
  ENV_FILE (`:1057-1131`), baselines/resumo (`:1132-1229`). Mas é o script mais
  sensível (anti-stale, re-exec do wt=); decomponha só depois do do-wt.sh.
- **SKILL.md (3 306 linhas)** — as ~800 linhas de templates de sub-agente
  (L1994-2810) são a extração mais natural para sub-skills.

## 5. Riscos de partir a skill — contratos frágeis a preservar

1. **`owned.tsv`**: 11 colunas TSV, lido com `awk -F'\t'` (colunas 7/8 podem ser
   vazias; `IFS read` colapsa), linha legada de 9 colunas promovida na 1ª
   reescrita (`do-wt.sh:326`, `scripts/README.md:49`). Qualquer refatoração do
   parser parte a contenção.
2. **Formato do ENV_FILE**: linhas `VAR='valor'` + funções `gwt/gch/gstatus/
   gassert` embutidas; última linha de stdout = caminho. O anti-stale depende do
   trio `DO_STATE = DO_HOME/run-$RUN_ID` (`do-context.sh:87-100`).
3. **Layout de `$DO_STATE`**: `gate/<etapa>.cmd`, `gates/<nome>.log|.rc|.tip`,
   `squashes/<nome>`, `partial/<nome>`, `search-mode`, `search-pause.md`,
   `surf-gate.last`, `plan-approval/rev-NNN.md`+`trail.tsv`, `question/pendente.md`,
   `evolution/`. Vários scripts leem ficheiros uns dos outros (surf-gate ↔
   FASE 0 ESTADOS PENDENTES; plan-approval ↔ reuso de ENV_FILE).
4. **Exit codes semânticos** citados na PROSA do SKILL.md (rc 4 = VAZIO ou
   vermelho conforme o subcomando; rc 3 do purge = parciais "de propósito";
   rc 6 do new; round 0/10/11/12/13/14; check-plannotator 0/1/2; surf-gate
   SEMPRE exit 0 com veredito na linha).
5. **Literais congelados por teste** (G12/B01): `SEARCH_STATUS: NOT_NEEDED | OK |
   EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78`, o texto da pergunta
   [1]-[4], `PURGE_RC`, `## Não integrado`, `Tarefa concluída PARCIALMENTE`,
   `MERGED-PARTIAL`, `checklist final`, `--boundary=`, numeração dos `<step
   order>`.
6. **Orçamentos do SKILL.md**: ≤ 220 000 chars, `description` ≤ 1 024, `<orchestrator>`
   tem de parsear como XML, subcomandos citados têm de existir no dispatch.
   Partir em sub-skills invalida o G12 tal como está (aponta `$SKILL_MD` único).
7. **Portabilidade bash 3.2/macOS**: sem `flock` (fallback mkdir),
   `readlink -f`, `sed -i`, `declare -A`, `mapfile`. Novos módulos têm de manter.
8. **Caminhos**: `$SKILL_HOME` derivado da localização do script (`pwd -P`);
   SKILL.md é symlink para `.claude/skills/...`; `check-install.sh` valida o
   contrato de ficheiros — sub-skills novas têm de entrar aí.
9. **Refs de arquivo** `refs/do-archive/$RUN_ID/` e namespace `BRANCH_NS` —
   recuperação pós-desastre depende deles.

## 6. Top 10 recomendações

1. **Extrair primeiro os templates de sub-agente** (`SKILL.md:1994-2810`) para
   `prompts/subagent-*.md` — é metade do monólito e tem dono claro (o
   orquestrador só precisa de "leia este ficheiro").
2. **Gerar os textos duplicados a partir de UMA fonte**: fazer `do-wt.sh
   checklist` imprimir um ficheiro `prompts/checklist.md` (ou o inverso), e
   alinhar a pergunta do `surf-gate.sh pause` com o protocolo do SKILL.md via
   extração partilhada — hoje a sincronização é manual e só o G12 a apanha.
3. **Ligar `plan-approval-prompts.md` ao SKILL.md** (FASE 2.5 passo 3 deve
   citá-lo) ou fundi-lo com a prosa de `SKILL.md:1143-1165` — hoje é um órfão
   funcional.
4. **Decompor `do-wt.sh` atrás do dispatch** em `lib/wt-ledger.sh` +
   `do-wt-merge.sh`/`do-wt-gate.sh`/`do-wt-report.sh`, mantendo o CLI e os exit
   codes; correr `test-contencao.sh` (309 asserções) como portão da migração.
5. **Criar `lib/flags.sh`** a partir do parsing de `do-context.sh:116-330` e
   tornar a tabela flag→variável gerada para o README/SKILL.md (uma fonte, três
   vistas).
6. **Congelar um "CONTRATO.md"** (exit codes, marcadores de stdout, formato do
   ENV_FILE/owned.tsv, literais G12) e fazê-lo validar pelos testes — hoje o
   contrato está espalhado por cabeçalhos de script.
7. **Atualizar o G12 para apontar aos ficheiros-partes** quando o SKILL.md
   partir (o teste assume `$SKILL_MD` único e o orçamento de 220 000 chars).
8. **Não mover política para os prompts**: regras FATAL (R1-R10) devem ficar no
   carregamento obrigatório; sub-skills só para material consultivo (templates,
   checklists, guias) — a precedência `{{TEST_POLICY}}` já mostra o padrão.
9. **Preservar o contrato anti-stale e o `--boundary`** intactos na fase 0 —
   são as invenções mais frágeis (leak de ENV_FILE, re-exec do wt=).
10. **Rodar a suíte completa** (`for t in scripts/test-*.sh; do bash "$t"; done`
    — 1 064 asserções) antes/depois de cada extração, e acrescentar um teste que
    verifique que cada sub-skill referenciada existe (estender o `check-install.sh`).
