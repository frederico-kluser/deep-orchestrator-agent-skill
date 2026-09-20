# Decisão — Limpeza por tarefa, pergunta quando a pesquisa falha e flags novas (v4.1.0)

**Data:** 2026-09-20 · **Versão alvo:** v4.0.0 → v4.1.0 (metadata.version; MINOR — absorve o `fe3a1c2`, que mudou contrato sem bump) · **Status:** aprovada
**Artefatos relacionados:** `SKILL.md` (frontmatter, identity, R2, R3, R5–R10, `<protocol id="PESQUISA-FALHOU">`, FASES 0/1/2/2.5/3/4, templates de sub-agente / revisor / teste / validação, final-report-template, degradation, examples, final-note), `scripts/do-wt.sh` (integrate, gate-set, gate, finish, close, assert-clean, ledger, checklist; merge/remove/drop-branch/sweep/purge consertados; lock sem `flock`), `scripts/do-context.sh` (`--flags=`, `DO_TEST_MODE`, `DO_QUESTION`, `DO_ORPHAN_RUNS`, reentrada do `wt=`), `scripts/surf-gate.sh` (NOVO), `scripts/check-install.sh`, `scripts/evolution-survey.sh`, `scripts/do-prefs.sh`, `scripts/test-contencao.sh` (A35–A46), `scripts/test-flags.sh` (NOVO, FL1–FL14), `scripts/test-surf-gate.sh` (G0, G9–G11), `scripts/test-plan-approval.sh`, `scripts/test-evolve.sh` (F14), `prompts/plan-approval-prompts.md`, `prompts/search-prompts.md`, `prompts/ecc-prompts.md`, `prompts/ecc-skills.md`, `README.md`, `scripts/README.md`.
**Base:** auditoria de 2026-09-20 em 7 lentes (limpeza de worktree, integração/merge, portão surf/Brave, estrutura, scripts e testes, subwaves e flags, docs e convenções), cada achado passado por um cético que tentou refutá-lo e, na maioria, reproduzido em repositório de laboratório descartável — o repositório da skill não foi tocado pelos labs. Os ids entre parênteses (WT-01, M3, SURF-01…) são os dessa auditoria; os `arquivo:linha` citados como evidência são do estado ANTERIOR (v4.0.0, commit `fe3a1c2`), salvo indicação em contrário.

---

## Contexto

O pedido do dono (2026-09-20), literal:

> essa skill tem problemas, ela nao limpa as worktrees conforme vai
> trabalhando, as vezes nem mergeia elas, nao chama para o usuario fornecer
> outra key do brave ou ajustar ele quando nao pesquisa, e acredito que ela
> tenha problemas estruturais, analise e arrume; e quero uma flag para no-test
> e outra para only-e2e (para criar apenas testes e2e)

E, em seguida:

> quero que tenha uma flag para do-question mas a pergunta da key do brave
> funciona mesmo sob bloqueio

A auditoria achou uma causa comum às três queixas: o que a skill prometia era
**prosa que o LLM tinha de lembrar**, e o script não cobrava nada. A limpeza
pós-gate era um ritual manual de 3 comandos na ida e 5 na volta por filha,
disparado por notificação assíncrona; o `sweep` aceitava sobra com rc=0 e o
passo 8 ainda mandava ignorar o rc; o `purge` final arquivava trabalho nunca
integrado e imprimia "PURGE OK"; e a parada por chave Brave era um "informe e
AGUARDE" sem mecanismo, cercada por cinco cópias de uma saída de fuga
("sem pesquisa exigida, prossiga") julgada pelo próprio orquestrador.

Princípio desta versão: **conserto, não reescrita — e o enforcement vai para o
SCRIPT** (determinístico, sobrevive à compactação de contexto), não para mais
prosa.

## Restrição de ambiente (medida em 2026-09-20)

A máquina do dono é macOS: bash 3.2.57, **sem `flock(1)`**, `sed`/`wc`/`awk`
BSD, git 2.39.5. Medido no baseline, antes de qualquer edição:
`test-contencao.sh` 75 PASS / 10 FAIL, `test-plan-approval.sh` 132 PASS /
1 FAIL (com 5 asserções que nem rodavam), `test-evolve.sh` 76 PASS / 2 FAIL.
Quase todas as falhas eram da própria suíte (GNUísmos) e mascaravam regressão
real. Todo código desta versão foi rodado nesse ambiente; ver D31.

## Decisões

### D24 — (RETROATIVA) R8j: `wt=` TERMINA EM COMMIT + PUSH, NUNCA MERGE DE VOLTA; `purge` É A REDE FINAL

- **Decisão:** registra o que o commit `fe3a1c2` (2026-09-15,
  `feat(wt,purge)!`) decidiu sem registro nem bump: com `wt=<nome>` o
  COMMIT-FINAL é APENAS commit + push em `do/wt/<nome>` — proibido
  merge/ff/rebase/PR de volta para o branch de origem; a worktree wt-root é
  persistente e nunca é purgada; e `do-wt.sh purge` substitui o `sweep` como
  rede de segurança final. A v4.1.0 absorve essa mudança e conserta o que ela
  prometia e não cumpria: `wt=<nome>` repetido **REENTRA** quando
  `<repo>.worktrees/<nome>` já é worktree deste repo no branch
  `do/wt/<nome>` (só deduplica `-2`, `-3` quando o path existe e NÃO é isso),
  e `DO_WT_ROOT`/`DO_WT_NAME` passam a ser gravados no ENV_FILE, derivados do
  fato (MODE=contido + branch `do/wt/<nome>`), não da flag.
- **Evidência:** `git describe --tags` = `v4.0.0-2-gfe3a1c2`; `SKILL.md:73`
  `version: "4.0.0"` e `:75` `updated: "2026-08-29"` com o commit datado de
  2026-09-15; `grep -c -i purge scripts/test-contencao.sh` = 0 (o `purge`
  nasceu sem nenhuma asserção); `docs/decisions/` sem registro de R8j/purge
  (DOC-03, E11). Reentrada: `scripts/do-context.sh:257-264` deduplicava sempre
  que a pasta existia — lab: 2ª invocação com `DO_WT_NAME=feat` imprimiu
  "DOCTYPE: 'proj.worktrees/feat' já existe" (typo de `DO_WT_ROOT:`) e "nome
  deduplicado -> feat-2", `BASE_BRANCH = do/wt/feat-2` nascido do HEAD de
  origem, sem o `w.txt` commitado em `feat` — contra `SKILL.md:526-529` ("O
  wt-root é PERSISTENTE … o branch do/wt/<nome> é reusado") e `README.md:339`
  ("cria — ou reentra") (F6). Com uma filha ACTIVE no `foo` da 1ª execução, a
  2ª criou `foo-2` sem DO_REUSE e a filha ficou travada e órfã (M10).
  Cobertura nova: `test-flags.sh` FL11 (cria, REENTRA, nunca `<nome>-2`).
- **Fonte:** commit `fe3a1c2`; auditoria (DOC-03, E11, F6, M10); labs em
  repositório descartável.

### D25 — LIMPEZA POR TAREFA, NO INSTANTE DO GATE VERDE, FEITA PELO SCRIPT (I-CLEAN) + LEDGER DE 11 COLUNAS

- **Decisão:** o passo 7 da FASE 3 vira `"$DO_WT" integrate <nome> "<msg>"`
  (merge + snapshot `int-<nome>` + status gate-pending, imprime
  `SNAPSHOT=<path>`) seguido de `"$DO_WT" gate <nome>` em background. O `gate`
  roda as etapas gravadas por `gate-set build|test|lint|e2e|install` no
  snapshot e, no VERDE, chama `finish` SOZINHO — arquiva o branch em
  `refs/do-archive/$RUN_ID/<nome>`, remove a worktree, apaga o branch e fecha
  os snapshots da filha — e imprime `GATE VERDE — <nome> fechado`. No VERMELHO
  não limpa nada e sai 4. Quem não será integrado fecha com
  `close <nome> [--discard "<motivo>"]`. Os 5 comandos manuais + `mark` viram
  ferramenta de reparo. O `owned.tsv` ganha as colunas 10 `parent` e 11
  `outcome` (`-` | MERGED | EMPTY | DISPOSABLE | `NEVER-MERGED:<motivo>`), lido
  sempre por `awk -F'\t'`; `ledger` imprime a tabela que alimenta o relatório
  e `checklist` imprime o CARTÃO DA ONDA (re-ancoragem após compactação de
  contexto). Sem `flock(1)`, o lock do `owned.tsv` cai para
  `mkdir "$OWNED.lock.d"` com retry e quebra de lock velho (> 30 s).
- **Evidência:** `SKILL.md:1313-1315` mandava `mark <nome> gate-pending` à mão
  e `:1332-1339` listava 5 `<cmd>` por filha (o mesmo ritual repetido em R6
  `:216-223` e no passo 3.5 `:1138-1144`); `scripts/do-wt.sh:437` — o sweep só
  removia `$9=="MERGED"`, e todo snapshot nasce ACTIVE (`:226-227`). Lab
  (merge → `new integration` → `mark gate-pending` → `mark MERGED` → sweep):
  "SWEEP: 1 sub-tarefa(s) ainda ACTIVE … int-onda1-foo kind=integration",
  `sweep rc=0`, snapshot ainda `locked` no `git worktree list` — o próprio
  caminho de recuperação documentado vazava 100% dos snapshots até o purge
  (WT-01, WT-02, E02, F3). Esquecido o `mark gate-pending`, o sweep apagava a
  filha ANTES de qualquer gate (E02, WT-11). Ledger: `do-wt.sh:95-96` tinha 9
  colunas de worktree e `:383`/`:695` gravavam REMOVED por cima de qualquer
  status — lab: depois do purge, a filha REVERTED e a nunca mergeada ficaram
  ambas `REMOVED`, indistinguíveis de uma integrada (M1). Lock:
  `do-wt.sh:117-124` só avisava e seguia sem exclusão — lab com 24 `new` em
  paralelo a um laço de `mark`: "linhas no owned.tsv=18  worktrees reais=25",
  e o `purge` seguinte saiu rc=0 com 7 worktrees travadas vivas (F2); cada
  merge ainda imprimia 9 linhas de AVISO que afogavam erros reais (WT-13).
  Remoção: `do-wt.sh:382` sem `--force` e `--artifacts` = `clean -fdXq`
  (`:378`, só ignorados, que nunca bloqueiam o `worktree remove`) — lab:
  snapshot com `?? coverage/` ⇒ "PURGE: FALHA ao remover a worktree", rc=1,
  para sempre (WT-04, F1). Na implementação: `test-contencao.sh` A35–A47,
  232 PASS / 0 FAIL (309 após a rodada final, A48–A56); um mutante SEM lock falhou A30 e A44 em 3 de 3 rodadas.
- **Fonte:** usuário ("nao limpa as worktrees conforme vai trabalhando");
  auditoria (WT-01, WT-02, WT-04, WT-11, WT-13, E02, E03, F1, F2, F3, M1,
  M12); labs.

### D26 — PORTÃO INTER-ONDA NO SCRIPT; O QUE NÃO FOI INTEGRADO NUNCA SOME EM SILÊNCIO (I-MERGE)

- **Decisão:** o passo 8 vira
  `"$DO_WT" sweep && "$DO_WT" assert-clean --wave <N+1>; "$DO_WT" verify` e o
  rc ≠ 0 NÃO é ignorável: cada sobra sai com o comando exato de conserto. O
  `new` de kind feature|fix|prep recusa (rc 6) abrir a onda N com sobra de
  onda anterior — a onda seguinte não abre nem se o LLM esquecer o passo 8. O
  `sweep` passa a falhar com gate-pending, REVERTED e feature|fix ACTIVE. O
  `merge` detecta conflito com `git merge-tree` ANTES de tocar a raiz (recusa
  sem sujar `$BASE_DIR`; resolve-se DENTRO da filha), commita com
  `--no-verify`, desfaz o índice se o commit do squash falhar, e squash SEM
  mudança NÃO marca MERGED (rc 4, "VAZIO"). Na RE-integração (fix após gate
  vermelho) de filha que não contém o próprio squash, o `merge` confere em
  memória se cada path tocado chega a `$BASE_BRANCH` idêntico ao da filha e
  RECUSA (rc 1, "PERDERIA parte do fix", com a lista) quando não — o 3-way a
  partir do base_sha antigo descartava deleção/reversão do fix em silêncio
  ("sem delta novo", rc 0, gate vermelho para sempre; achado de lab da
  integração, coberto por A47). Regra operacional: após gate VERMELHO, merge
  de `$BASE_BRANCH` na filha ANTES do fix. `drop-branch` exige squash
  registrado ou `outcome` ≠ `-`. O `purge` fecha por `finish --gate-ok` /
  `close --discard "purge"`, só imprime "PURGE OK" se ledger E realidade
  fecharam e, havendo qualquer NEVER-MERGED, imprime o bloco
  `PURGE: NUNCA INTEGRADAS (obrigatorio no relatorio final):` e sai **rc 3**.
  O relatório ganha a seção OBRIGATÓRIA "Não integrado" (fonte:
  `"$DO_WT" ledger`; "nenhum" quando vazia) e o título deixa de ser fixo:
  "Tarefa concluída" | "Tarefa concluída PARCIALMENTE". Runs anteriores vivas
  que não serão reusadas saem no bloco `DO_ORPHAN_RUNS:` da FASE 0 com o
  comando de purge de cada uma; e a FASE 4 passo 8 roda
  `clean-ignored-delta` ANTES do `rm -rf "$DO_STATE"`.
- **Evidência:** `SKILL.md:1363-1364` mandava `sweep; verify` "separados por
  `;`, NUNCA por `&&`" — o rc visto era sempre o do verify — e
  `:1367-1369` declarava que filhas ACTIVE "são apenas LISTADAS, sem falhar o
  rc"; `do-wt.sh:206-235` (`new`) não consultava sobra (WT-03). Lab: feature
  ACTIVE com commits reais + uma REVERTED + uma BLOCKED ⇒ `sweep rc=0`,
  `purge rc=0` e "PURGE OK — nenhuma worktree/branch de sub-agente desta
  execução sobrou", com três linhas idênticas "branch … apagado" (M2, E01,
  WT-06, DOC-02). `do-wt.sh:306` marcava MERGED com rc=0 um squash VAZIO —
  lab: `new feature onda1-vazia` + `merge` ⇒ "Already up to date", MERGED,
  "SWEEP OK" (M3). `mark onda1-real MERGED` à mão + sweep ⇒ "SWEEP OK", branch
  apagado e `real.txt` ausente de main (M4). Conflito com filha de 3 arquivos:
  o re-merge prescrito pelo script nunca convergia e deixava ` M b.txt` /
  `?? novo.txt` na raiz, que o `stage-delta` estagiava ("Estagiados 2
  path(s)"); o teste A23 só usava filha de UM arquivo (M5). Hook pre-commit
  falhando ⇒ "FALHA: commit do squash" e, no re-run, "RECUSADO: … mudanças
  ESTAGIADAS que não são desta execução", travando todos os merges seguintes
  (M6, WT-07). Diretório ausente ⇒ "FALHA ao apagar" seguido de "PURGE OK",
  com a entrada `locked` imune a prune/gc (WT-05). Subwave `test-` de onda
  intermediária: o passo 3.5 só olhava N-1 (`SKILL.md:1108-1109`) — lab:
  kind=test ACTIVE com commit ⇒ sweep rc=0, "PURGE OK", branch só em
  `refs/do-archive` (SUB-01). Relatório: título fixo `SKILL.md:2420`
  "## Tarefa concluída" e `:2488` "## Bloqueios (se houver)" (M7). Runs
  órfãs: `do-context.sh:110` ignorava run só com BLOCKED/ORPHANED e os 4
  blocos DO_STALE (`:120-187`) criavam run nova sem tocar na anterior — lab:
  "PURGE OK" na run nova com a worktree antiga ainda `locked` (F4, WT-08,
  E04). Ordem: `SKILL.md:1778` apagava o `$DO_STATE` e só em `:1782-1783`
  mandava o `clean-ignored-delta`, que lê o baseline de dentro dele (WT-09,
  F7). Na implementação: A38–A43; `test-flags.sh` FL10 roda o comando
  IMPRESSO no `DO_ORPHAN_RUNS` contra o `do-wt.sh` real.
- **Fonte:** usuário ("as vezes nem mergeia elas"); auditoria (WT-03, WT-05,
  WT-06, WT-07, WT-08, WT-09, M2–M7, E01, E04, F4, F7, SUB-01, DOC-02); labs.

### D27 — PROTOCOLO PESQUISA-FALHOU: PERGUNTA EM TEXTO, INCONDICIONAL; `SEARCH_STATUS`; `surf-gate.sh`; COTA ≠ 78

- **Decisão:** bloco único `<protocol id="PESQUISA-FALHOU">` logo após a R7;
  os demais pontos só o REFERENCIAM. É **INCONDICIONAL**: vale com ou sem
  `do-question` e VENCE "não me pergunte nada", autônomo, `no-stop` e
  `plan=off` — chave/cota/instalação é configuração do AMBIENTE do usuário,
  não ambiguidade da tarefa, e o orquestrador nunca decide sozinho que a
  pesquisa exigida é dispensável. Peças: (1) o portão é o script
  `"$DO_SURF_GATE"` (`scripts/surf-gate.sh`), **fail-closed** — imprime
  `SURF_GATE=<0|78|127>`, `SURF_CODE=<BraveKey…|NotInstalled>` e a mensagem do
  portão VERBATIM; sai o ramo fail-open "1 ⇒ prossiga". (2) Cota/429/402 saem
  do surf com exit **1**, igual a "não achei": `surf-gate.sh classify`
  distingue `OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78 |
  KILLED_143 | USAGE_2` por padrões ANCORADOS (nunca casando com a query
  ecoada). (3) O handoff abre com a seção obrigatória `## SEARCH_STATUS`, e o
  novo passo 4.5 da FASE 3 (TRIAGEM DE PESQUISA) a extrai de cada handoff
  ANTES de integrar. (4) Toda sub-tarefa tem `SEARCH_REQUIRED=sim|não` por
  critério objetivo (na dúvida, sim) e o PORTÃO PÓS-PLANO é o único ponto de
  decisão antes da FASE 2.5/3. (5) AGUARDE é definido UMA vez na R2: gravar
  estado (`surf-gate.sh pause` → `$DO_STATE/search-pause.md`), pergunta em
  TEXTO como última coisa da resposta — [1] adicionei/troquei a chave, [2]
  ajustei plano/cota ou esperei o cooldown, [3] seguir SEM pesquisa (premissas
  NÃO VERIFICADAS), [4] abortar — e ENCERRAR o turno; a retomada é pela FASE
  0 (ESTADOS PENDENTES) com `resume --probe`, UMA busca real de 1 crédito,
  porque a sonda grátis não enxerga cota. `BraveKeyCooling` não pergunta de
  cara: reroda o portão até 3×. (6) FASE 2.5 passo 5 e
  `prompts/plan-approval-prompts.md`: 78/127/cota ⇒ protocolo; EMPTY ⇒
  premissa NÃO VERIFICADA com motivo "busca vazia". O relatório ganha a seção
  "Pesquisa". `AskUserQuestion` segue vetado (R10/D18): a pergunta é texto.
- **Evidência:** `SKILL.md:278-280` (R7, FATAL): "1 — a operação rodou e não
  recuperou nada … siga sem aquele fato. NÃO pergunte ao usuário." No surf
  8.0.1, cota só emite `monthly quota exhausted — skipped, not retried` e 60 s
  de cooldown, sem queimar a chave (`src/lib/dispatch.mjs:363-368`, `:31`);
  `AllKeysExhausted` ⇒ `process.exit(1)` (`bin/surf-research-skill.mjs:222-227`);
  e a sonda de validação devolve `valid:true, throttled:true`
  (`src/lib/providers/brave.mjs:775-776`), então `surf doctor` sai 0 com a
  cota zerada — nesta máquina o doctor mostrava "brave 2 key(s), 1 burned" e
  "✓ ready", exit 0 (SURF-01). O portão antigo era
  `surf doctor >/dev/null 2>&1; echo "SURF_GATE=$?"` em `SKILL.md:260`, `:707`
  e `:1034`: jogava fora o diagnóstico, tratava exit 1 como "prossiga"
  (`:263-265`) e mandava a mensagem fixa "rode `surf`", que sem argumentos
  exige TTY (`bin/surf.mjs:465-469`); o 78 cobre 6 vereditos com "Fix:"
  DIFERENTES (`preflight.mjs:282-334`) (SURF-06). "PESQUISA IMPOSSÍVEL"
  aparecia UMA vez no arquivo (`:1905`) e nenhum passo do orquestrador a
  consumia (SURF-02). "Informe e AGUARDE" (`:129-130`, `:155`) não gravava
  estado nem encerrava o turno — ao contrário da R2(e), que já tinha o
  mecanismo completo (`:148-150`, `:572-595`) (SURF-03). A saída "Sem pesquisa
  exigida … prossiga sem busca" aparecia 5 vezes (`:270-271`, `:1037-1038`,
  `:2621-2622`, `:2634-2635`, `:2872-2873`) sem nenhuma definição de "EXIGE
  pesquisa" nem coluna no plano (SURF-04, DOC-01, E07). Contradição direta:
  `SKILL.md:965` e `prompts/plan-approval-prompts.md:105` / `:142-146`
  mandavam "se sair 78, mantenha a premissa e marque-a NÃO VERIFICADA"
  (SURF-05). O relatório não tinha seção de pesquisa (SURF-09). Na
  implementação: `test-surf-gate.sh` 173 asserções (228 após a rodada final; G9 classify com os textos
  REAIS do surf, G10 pause/resume, tudo mockado — 0 créditos); mutantes
  fail-open, de padrão frouxo (`429|quota` casava com "no quota was spent") e
  sem scrub da query foram todos pegos.
- **Fonte:** usuário ("nao chama para o usuario fornecer outra key do brave ou
  ajustar ele quando nao pesquisa"; "a pergunta da key do brave funciona mesmo
  sob bloqueio"); auditoria (SURF-01 a SURF-09, DOC-01, E07); código do
  pacote `surf-agent-skill@8.0.1`; labs.

### D28 — FLAG `no-test` (`DO_TEST_MODE=none`): NÃO CRIAR ≠ NÃO RODAR

- **Decisão:** `no-test` desliga a CRIAÇÃO de testes, não a execução. O BLOCO
  B do passo 10 é pulado ("Onda N: Testing Subwave DESLIGADA (no-test)",
  nunca seção PENDENTE); features recebem `{{TEST_POLICY}}` = "NÃO crie
  arquivo nem caso de teste novo; rode a suíte existente ANTES e DEPOIS;
  PERMITIDO ajustar teste EXISTENTE quebrado por mudança INTENCIONAL de
  contrato" — política que VENCE `ecc-prompts.md`, `ecc-skills.md` e o
  project-router. O gate (inclusive `GATE_TEST` na suíte existente) e a
  VALIDATION subwave CONTINUAM. Revisores: ausência de testes novos não é
  achado; o REVISOR DE PLANO é proibido de propor sub-tarefa de teste. Única
  exceção: teste pedido EXPLICITAMENTE no texto da tarefa é entregável de
  feature. Enforcement no script: `do-wt.sh new` RECUSA kind=test e nome
  `test-onda*`. Relatório: "Testes: DESLIGADOS por no-test — 0 testes novos;
  gate rodou a suíte existente: <GATE_TEST>".
- **Evidência:** `grep -rn -i "no-test|DO_TEST_MODE|only-e2e"` em SKILL.md,
  `scripts/` e `prompts/` = 0 ocorrências; a criação de testes estava
  hard-wired em ~12 pontos: `SKILL.md:1405-1407` (duas subwaves ao fim de
  TODA onda; único NO-OP = "apenas docs/configs", `:1492-1494`), `:1937-1938`
  ("Se adiciona comportamento novo, escreva testes"), `:2093-2103` (unidade
  para TODAS as funções públicas; alvo ≥ 80%), `prompts/ecc-prompts.md:198`
  ("testes ausentes" como achado HIGH do revisor) e `:146` ("Estratégia de
  teste ausente" como red flag de plano) (E13, DOC-09, DESIGN-NO-TEST). Lab
  da implementação: com `--flags='no-test'`, `new test …` ⇒ "RECUSADO:
  TEST_MODE=none (no-test)" rc 1 e `new validation …` rc 0 (A43).
- **Fonte:** usuário ("quero uma flag para no-test"); auditoria (E13, DOC-09,
  DESIGN-NO-TEST).

### D29 — FLAG `only-e2e` (`DO_TEST_MODE=e2e`): SÓ TESTES END-TO-END, POR JORNADA; `DO_TEST_MODE=full|none|e2e`

- **Decisão:** um único eixo, `DO_TEST_MODE`, com três valores; `no-test` +
  `only-e2e` juntos = exit 2 "mutuamente exclusivos" na FASE 0. Em `e2e`, as
  Testing Subwaves criam APENAS testes end-to-end — e2e = exercita o sistema
  pela MESMA porta do usuário final (UI no browser; HTTP contra o servidor de
  pé; binário CLI via processo; API pública importada como consumidor), sem
  mock interno nem import de módulo interno. Cobertura por linha vira N/A: a
  medida é de JORNADAS (≥ 1 caminho feliz + ≥ 1 erro observável por jornada),
  planejadas no MAPA DE JORNADAS (J1..Jn → onda em que FECHA → path do spec).
  FASE 1 registra `E2E_RUNNER`/`E2E_DIR`/`GATE_E2E` (`gate-set e2e`); runner
  ausente ⇒ sub-tarefa `onda1-e2e-harness` (devDependency local, nunca `-g`;
  caches do Playwright/Cypress entram nos permitidos da R9); porta por
  contexto (`E2E_PORT`), servidor só pelo ciclo de vida do runner, artefatos
  fora do commit, 2 execuções (flaky ⇒ `fixme` + relato). `GATE_E2E` roda na
  worktree do agente e2e, no snapshot do MERGE DE TESTE (`gate <nome> --e2e`),
  na validation e no gate final — NÃO nos snapshots de feature. Degradation
  nova `e2e-runner-unavailable`. No modo `full`, três consertos: é PROIBIDO
  commitar teste FALHANDO (skip/xfail/fixme nomeando o bug + relato); o título
  "TDD Workflow" do template vira "Teste pós-implementação a partir do
  CONTRATO"; e bugs reportados pelos agentes de teste da ÚLTIMA onda entram
  no FLUXO FIX-FINAL.
- **Evidência:** `grep -i 'e2e|playwright|cypress' SKILL.md` = 0; o template
  de teste só conhecia unidade/integração/borda (`SKILL.md:2093-2098`),
  proibia framework novo (`:2125-2127`), media por linha (`:2102`, `:2133`) e
  escopava por ARQUIVO (`:1451-1461`); o gate era um trio sem etapa e2e
  (`:717-722`); a R9 não listava `ms-playwright`/Cypress entre os caches
  permitidos (`:388-392`) (DESIGN-ONLY-E2E, DESIGN-CONFLITO). Teste vermelho:
  `:2132` "Testes passam (ou bugs documentados)" e `:2141` "[N] passam, [N]
  revelam bugs" liberavam commitar o vermelho, e todo snapshot seguinte nasce
  do HEAD pós-merge (SUB-03). TDD: `:2083-2086` mandava seguir
  `ecc-skills.md` skill #1 (GATE RED, implementação mínima — `:47-50`) num
  agente que "NÃO MODIFICA CÓDIGO DE PRODUÇÃO" (`:2038`) (SUB-04). Última
  onda: o FLUXO FIX-FINAL (`:1555-1557`) só era acionado pela validação; o
  substep "BUGS DOS HANDOFFS VIRAM SUB-TAREFAS DE FIX" existia apenas no 3.5
  (`:1170-1176`) (SUB-02). Lab da implementação:
  `E2E_PORT=41001 "$DO_WT" gate test-onda1-e2e-login --e2e` ⇒ log com
  "porta=41001 CI=1" e "GATE VERDE"; `test-flags.sh` FL6 (exit 2 nas duas
  ordens) e FL8 (anti-stale do TEST_MODE).
- **Fonte:** usuário ("outra para only-e2e (para criar apenas testes e2e)");
  auditoria (DESIGN-ONLY-E2E, DESIGN-CONFLITO, SUB-02, SUB-03, SUB-04).

### D30 — FLAG `do-question` (`DO_QUESTION=1`; default 0): O ORQUESTRADOR PODE PERGUNTAR — A PERGUNTA DA CHAVE BRAVE NÃO DEPENDE DELA

- **Decisão:** sem a flag, a R2 segue como era (autonomia: infere e
  documenta). Com a flag, o orquestrador PODE perguntar, pelo MESMO mecanismo
  AGUARDE da D27 (texto; estado em `$DO_STATE/question/pendente.md`; encerra o
  turno; retomada pela FASE 0), e a flag explícita VENCE gatilho de autonomia
  no texto da tarefa (precedente: `plan=on`). Onde: (i) RODADA DE DÚVIDAS
  única ao fim da FASE 1 — todas as dúvidas reais num bloco numerado, cada uma
  com opções a/b/c e um DEFAULT; resposta "1:a 2:c" ou "segue"; (ii) na FASE
  3, no máximo 1 rodada por onda, ao FIM da onda (depois de
  sweep/assert-clean — nunca pausar com filha integrada por limpar), só para
  decisão difícil de reverter ou que muda escopo. Sub-agentes NUNCA perguntam
  ao usuário: com a flag devolvem no handoff a seção
  `## Dúvidas para o usuário` e o orquestrador decide. Dúvida trivial continua
  inferida. A R2 passa a listar SEIS exceções: (a)(b) ⇒ PESQUISA-FALHOU
  [incondicional], (c) FASE 0 aborta, (d) portão do plano, (e) pergunta de
  evolução, (f) do-question. Relatório: seção "Perguntas ao usuário".
- **Evidência:** o pedido literal ("quero que tenha uma flag para do-question
  mas a pergunta da key do brave funciona mesmo sob bloqueio"); `SKILL.md:118`
  titulava a R2 "NUNCA pergunte ao usuário" (FATAL) com "CINCO exceções, e
  apenas estas" (`:121`), nenhuma delas opt-in. O único mecanismo de pergunta
  que funcionava era o da evolução — pergunta impressa, turno encerrado,
  estado no DISCO, continuação na FASE 0 (`:148-150`, `:572-595`) —, decidido
  na D18/D21 porque o Bash do harness não tem stdin interativo e
  `AskUserQuestion` não existe nos harnesses-alvo (medição de 2026-08-28;
  R10 `:466-467`) (SURF-03). Na implementação: `test-flags.sh` FL2/FL9
  (`QUESTION = 0|1` no resumo; anti-stale; chave ausente = 0).
- **Fonte:** usuário; D18/D21 (`2026-08-28-pergunta-evolucao-terminal.md`);
  auditoria (SURF-03, SURF-04).

### D31 — ESTRUTURAIS: `--flags` / ZONA DE PREFIXO, `description` ≤ 1024, FASE 0 REORDENADA, macOS / bash 3.2

- **Decisão:** (1) **Flags:** a ZONA DE PREFIXO são os tokens INICIAIS de
  `$ARGUMENTS` que casem `^[a-z][a-z0-9-]*=\S+$` ou
  `^(no|only|do)-[a-z0-9-]+$`, até o primeiro que não case ou um `--`
  literal; o LLM repassa TODOS ao script, sem julgar, em UM argv —
  `"$DO_CTX" --flags='<TOKENS>'` — e o `do-context.sh` é o ÚNICO validador
  (token desconhecido ⇒ exit 2 com apelido determinístico; flag vence env; o
  ENV_FILE grava E exporta tudo). Nunca inferir flag por linguagem natural;
  proibido `VAR=1 DO_CTX=$(...)`; conferência obrigatória do resumo da FASE 0.
  (2) **Frontmatter:** `description` ≤ 1024 caracteres (o que é, quando usar,
  triggers, invocação com TODAS as flags; histórico de versão sai),
  `argument-hint` curto, `metadata.version "4.1.0"`. (3) **FASE 0
  reordenada:** passo 0 ESTADOS PENDENTES (evolução + `search-pause.md` +
  `question/pendente.md`) → 1 PARSE DE PREFIXOS (tabela única) → 2 portão do
  plano (resultado vira token `plan=on|off`) → 3 comando único → resto como
  era; referências cruzadas por número atualizadas; lookup do `SKILL_HOME`
  cobre a instalação por symlink documentada. (4) **Contradições removidas:**
  "limpa ao fim de cada onda" × "IMEDIATAMENTE"; "PARA com exit 78" × "marque
  NÃO VERIFICADA"; R3 × pausa do protocolo; "o orquestrador NÃO pesquisa" ×
  FASE 2.5 passo 5 (exceção agora declarada); texto corrompido no template de
  relatório. (5) **Alvo macOS / bash 3.2.57:** sem arrays associativos,
  `mapfile`, `${var,,}`; array vazio sob `set -u` sempre com guarda
  `${arr[@]+"${arr[@]}"}`; nada de `sed -i` (arquivo temporário + `mv`); saída
  de `wc -l` normalizada; `--help` por marcador de fim, não por número de
  linha. Fatiar o SKILL.md em arquivos de referência fica como TRABALHO
  FUTURO (ver Fora de escopo).
- **Evidência:** Flags: `SKILL.md:484-485` "exporte DO_MAX_PARALLEL=N ANTES
  da FASE 0" (idem `:493`, `:503`, `:513-514`, `:538`), mas o comando literal
  do passo 1 (`:601`) terminava em `"$DO_CTX"` sem slot de variável e `:608`
  admitia "O shell do harness NÃO persiste entre chamadas" — lab:
  `export DO_NO_STOP=1` numa chamada e `do-context.sh` na seguinte ⇒ ENV_FILE
  com `DO_NO_STOP='0'`; `:491` casava `no-stop` "como token" em QUALQUER lugar
  do texto; `surf-sub-agents=N` estava enterrado dentro da lista de
  precedência do `plan=` (`:545-551`) e `DO_SURF_SUB_AGENTS` tinha 0
  ocorrências em `scripts/*.sh`, embora `:965` o usasse em shell (FLAG-01, F5,
  E06, DOC-05). Frontmatter: `description` media 2421 caracteres (Ruby YAML),
  com "Invocação:" no caractere 2155 e "Triggers:" no 2272; a listagem do
  harness cortava em "…(v3.8.0, substituído pela PERG…" ≈ 1535 — flags,
  triggers e o `when_to_use` inteiro nunca chegavam ao modelo (DOC-04, E05);
  hoje mede 998. FASE 0: ordem física 0, 0.1, 0.1b, 0.2, 0.5 (`:536`), 0.4
  (`:572`, "ANTES DE TUDO"), 1 — e o 0.4 usava `$BASE_DIR`, que só existe
  depois do passo 1 (DOC-06, E08); o lookup do `SKILL_HOME` (`:601`) não
  tinha `~/.claude/skills/<skill>` como candidato, a instalação que o
  `README.md:28` manda fazer (E12); `SKILL.md:2472-2473` trazia "(quando\ndois
  pontos DO_WT_ROOT=1)" (DOC-15). macOS: `evolution-survey.sh:97`
  `for b in "${CANDIDATES[@]}"` com array vazio ⇒ "unbound variable" (S2
  falhava no baseline) e `do-prefs.sh:135` idem (F8); `test-contencao.sh:110`
  e `test-plan-approval.sh:723` usavam `sed -i` GNU e
  `test-contencao.sh:99`/`:100`/`:297`/`:525` comparavam `wc -l` cru como
  string (F9); achado já na implementação: `${name^^}` (bash 4) abortava o
  laço P1..P6 do `test-plan-approval.sh` — 5 asserções sumiam sem contar.
  Tamanho: 192.136 B / 2935
  linhas sem nenhuma re-ancoragem por onda (E03) — respondido nesta versão
  pelo `checklist` (D25), não pelo fatiamento. Na implementação: o
  `<orchestrator>` INTEIRO passou a parsear como XML (no HEAD falhava com
  "mismatched tag" em `</final-note>`, por um `do/wt/<nome>` cru); suítes no
  bash 3.2.57 (rodada final, 2026-09-20): `test-contencao.sh` 309/0,
  `test-flags.sh` 307/0, `test-plan-approval.sh` 139/0,
  `test-surf-gate.sh` 228/0, `test-evolve.sh` 81/0 — 1064 asserções.
- **Fonte:** usuário ("acredito que ela tenha problemas estruturais");
  auditoria (FLAG-01, F5, F8, F9, E03, E05, E06, E08, E09, E12, DOC-04,
  DOC-05, DOC-06, DOC-15); medição direta no ambiente do dono.

## Rodada final — revisão adversarial da própria v4.1.0 e condensação do SKILL.md (2026-09-20)

A primeira implementação passou por uma revisão adversarial (um revisor por
dimensão, um cético por achado alto, tudo reproduzido em lab no macOS). Nenhum
achado alto foi refutado. O que mudou, por decisão:

- **D25/D26 (scripts):** (WT-F1) filha cujo sub-agente saiu do branch
  registrado (`git checkout --detach`, `git switch -c`) era arquivada VAZIA e o
  rescue-commit virava commit dangling — `integrate` passou a RECUSAR (rc 1, com
  o conserto) e `close`/`finish`/`purge`/`remove` arquivam também o HEAD em
  `refs/do-archive/$RUN_ID/<nome>-HEAD`; commits em `base..HEAD-da-worktree`
  nunca viram EMPTY. (WT-F2) a re-integração sobrescrevia `pre_merge_sha` e o
  `undo` só desfazia o ÚLTIMO squash — agora a col 7 é o pre do 1º squash, a
  lista vive em `$DO_STATE/squashes/<nome>` e o `undo` desfaz TODOS
  (`undo-<nome>-<k>`); `wave-files` volta a ver a onda inteira. (WT-F3)
  `purge`/`finish --gate-ok` fechavam como MERGED uma filha com gate vermelho e
  fix nunca integrado — novo outcome `MERGED-PARTIAL:<motivo>` (cauda medida
  por ÁRVORE contra `gates/<nome>.tip`), `parciais=` no ledger e bloco
  `PURGE: NUNCA INTEGRADAS / PARCIAIS` com rc 3; `--gate-ok` nunca é conserto
  de vermelho. (WT-F4) o snapshot de `test-onda(N-1)` travava `new fix
  ondaN-*` — a guarda de onda passou a seguir o kind do PARENT. (WT-F5) `gate`
  sem reentrância: `.rc` = `running <pid> <sha>`, 2º gate sai rc 3 e o veredito
  fica amarrado ao squash. (FT-03) `gate` de kind=test em `only-e2e` liga o
  e2e sozinho. (B01) `checklist` com a numeração exata dos `<step order>` da
  FASE 3 + `checklist final`. Cobertura: A48–A56.
- **D27 (pesquisa):** (SG-1) a opção [3] não valia nas ondas seguintes quando
  a falha era de cota (portão verde) — `surf-gate.sh choose no-search` grava
  `$DO_STATE/search-mode` e o portão imprime `SURF_MODE=no-search`; (SG-3) o
  cooldown só adia a pergunta no gatilho g1; (BEH-05) handoff sem
  `SEARCH_STATUS` ganha 1 re-disparo antes do probe; (SG-2/4/5/6) suíte
  hermética, classify sem casar o eco da query e sob LC_ALL=C, `resume --probe`
  sem pausa não grava estado.
- **D31 (estruturais):** (FT-01) typo de flag fora da regex da zona
  (`e2e-only`, `--no-test`) virava texto da tarefa — o token de fronteira vai
  em `--boundary='<token>'` e o script decide (apelidos num lugar só);
  (CTX-01) reuso de env anterior à v4.1.0 vinha sem `DO_SURF_GATE` — o script
  completa as chaves; (CTX-02/04/05/06/07/08) órfãs inventariadas antes do
  re-exec do `wt=`, `--flags=` repetido = exit 2, DO_WARN para `wt=<outro>`
  dentro de wt-root, validações antes de criar a worktree irmã, resumo sem
  "nenhuma interação com o usuário", re-exec por caminho absoluto.
  **Condensação:** a primeira implementação inchou o SKILL.md de 192k para
  304k caracteres (a FASE 3 dobrou), agravando o próprio achado E03. Ele foi
  condensado para 215k com o princípio "uma casa canônica por regra": a
  mecânica de integrate/gate/finish/close mora no passo 7 da FASE 3, VERMELHO/
  VÍTIMAS/FALHA TARDIA na degradation `gate-red`, e2e no template do agente de
  teste, flags na tabela da FASE 0, e o que o script já imprime (sobra +
  comando de conserto) não é reexplicado. Verificação mecânica: placeholders,
  cases e os 61 `<step order>` idênticos aos do texto anterior; G12 trava
  `<= 220000` caracteres.
- **Evidência:** `review-results.json` da revisão (labs reproduzidos), suítes
  309/307/139/228/81.

## Fora de escopo

- **Fatiar o `SKILL.md` em arquivos de referência** (templates, relatório,
  FASE 2.5, degradations carregados sob demanda) — TRABALHO FUTURO. A
  auditoria mediu que ~31% do arquivo não é necessário no carregamento (E03) e
  o arquivo CRESCEU nesta versão (2935 → ~4650 linhas), contra o orçamento da
  D4 de 2026-08-23 (`SKILL.md` < 500 linhas). Não foi feito agora porque o
  risco é alto (referências cruzadas por passo, literais verificados por
  `test-surf-gate.sh` G8) e o pedido era conserto, não reescrita; o
  `"$DO_WT" checklist` é a mitigação desta versão.
- **Regenerar o `EXPLAINER.html`** — é artefato de EXECUÇÃO orquestrada
  (gitignored), não de commit; o que está no disco parou no `16fb0ce`.
- Trabalho futuro anotado pelos implementadores, não decidido aqui:
  `gate <nome> --at-head` (hoje o snapshot de uma VÍTIMA de gate vermelho
  alheio reroda no SHA antigo e só fecha por `finish --gate-ok`); purge/gc
  automático de runs órfãs dentro do `do-context.sh` (hoje ele só IMPRIME o
  comando — pode ser sessão concorrente); classe própria no `classify` para
  exit 137; `OK_PARTIAL_QUOTA` (cota que acaba no meio de uma chamada que
  ainda sai 0).
- `AskUserQuestion` continua vetado (R10/D18): toda pergunta desta versão é
  TEXTO + estado em disco + fim de turno.
- O PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5) continua no Plannotator, e a
  pergunta de evolução (D18–D21) não muda.
