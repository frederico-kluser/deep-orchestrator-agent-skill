# deep-orchestrator-agent-skill v4.1.0

![Versão](https://img.shields.io/badge/version-4.1.0-00d4ff)

Orquestrador autônomo multi-agente para Claude Code — planeja, divide em ondas (com recálculo dinâmico; **até 10 ondas por padrão, ilimitadas com `no-stop`**), cria worktrees isoladas, delega, revisa adversarialmente, integra via squash-merge um a um com gate em snapshot de integração (worktree efêmera `int-<nome>`, fora da seção crítica), **limpa cada worktree no instante do gate verde dela — quem limpa é o script, não a memória do LLM** —, verifica a dependência de pesquisa antes de cada onda (**surf-agent-skill v8** — Brave é o único backend) e commita + pusha tudo ao final **sem perguntar nada sobre a tarefa**.

Durante a execução, três interações existem, e só estas. Duas só quando você pede: o **PORTÃO DE APROVAÇÃO DO PLANO** (FASE 2.5) — quando a invocação pede um plano, o plano vai para o [Plannotator](https://github.com/backnotprop/plannotator) e você aprova ou anota; cada anotação **regera o plano e abre um Plannotator NOVO**, até a aprovação, e nenhuma worktree nasce antes dela — e a flag **`do-question`**, que autoriza o orquestrador a levantar as dúvidas reais num bloco único em vez de inferir. A terceira é **incondicional**: quando a pesquisa exigida **não funciona** (sem chave Brave válida, cota esgotada, surf ausente), o orquestrador **pausa e pergunta** — trocar a chave, ajustar o plano/cota, seguir sem pesquisa ou abortar —, **mesmo com "não me pergunte nada"**: chave e cota são configuração do SEU ambiente, não ambiguidade da tarefa. Sem pedido de plano, sem `do-question` e com a pesquisa funcionando, a autonomia total continua exatamente como sempre foi.

Ao FIM da execução — depois de TUDO (commit, push e relatório) — a evolução vem como **UMA PERGUNTA EM TEXTO no terminal** (v3.9.0, nunca mais um site): cada proposta numerada com opções e escopo, e você responde com códigos (ex.: `1:b2` — opção b, fix global), ou `nada` para pular (tudo fica pendente, nada é aplicado). A flag `no-evolve` na invocação pula a pergunta **e** a análise do histórico.

## Glossário (leia antes do resto)

| Termo | O que é |
|-------|---------|
| **`$SKILL_HOME`** | A **casa da skill**: `scripts/` e `prompts/`. Fica fora do projeto-alvo e é **somente leitura/execução** durante uma execução. Caminhos escritos como `$SKILL_HOME/...` são daqui; caminhos sem prefixo são do repositório-alvo. |
| **RAIZ-DE-MUNDO (`$BASE_DIR`)** | `git rev-parse --show-toplevel` no diretório de invocação. Se você invocou dentro de uma git worktree vinculada, é a **worktree** — não o projeto principal. É a fronteira de escrita. |
| **`$BASE_BRANCH`** | O branch em HEAD na raiz-de-mundo. É o **único** alvo de integração. Nunca é resolvido por convenção (main/master). |
| **`$MAIN_ROOT`** | O checkout principal do repositório. Em MODO CONTIDO é **zona proibida**. |
| **WORKTREE-FILHA** | Uma worktree por sub-agente, criada sob `$CHILD_ROOT`, com branch `$BRANCH_NS/<nome>`. |
| **LEDGER (`owned.tsv`)** | O registro desta execução: uma linha por worktree-filha, 11 colunas TSV — `status` (ciclo de vida: `ACTIVE`, `gate-pending`, `MERGED`, `REVERTED`, `BLOCKED`, `ORPHANED`, `REMOVED`) e `outcome` (destino: `MERGED`, `MERGED-PARTIAL:<motivo>`, `EMPTY`, `DISPOSABLE`, `NEVER-MERGED:<motivo>`). É a **única** fonte de alvos de limpeza e a fonte do relatório final (`do-wt.sh ledger`). |
| **`.deep-orchestrator-preferences/`** | Memória consultiva da skill e do projeto (contexto **NÃO revisado**, nunca política executável, **gitignored**). Do projeto: `project-config.md` + `learnings.md` + `pending/`; da skill: `global-tips.md` + `pending/`. Escrita por `scripts/do-prefs.sh` (validada, deduplicada) com o voto do usuário na pergunta de evolução (`scripts/evolution-survey.sh`); consultada pela FASE 1 antes de planejar. |
| **`prompts/evolution-guide.md`** | Framework de decisão da evolução: o que qualifica, como classificar project vs global, e o caminho das prefs ao corpo da skill. |

## Instalação (o contrato)

A skill é distribuída como um repositório git; a **casa da skill (`$SKILL_HOME`)** é a **raiz** do repositório — o diretório que contém `SKILL.md`, `scripts/` e `prompts/`. Instalação incompleta = FASE 0 aborta com `PARE: do-context.sh nao encontrado`.

- O `SKILL.md` da raiz é um **symlink** para `./.claude/skills/deep-orchestrator-agent-skill/SKILL.md` (padrão Claude Code). Desde a v3.5.1, `scripts/` e `prompts/` são espelhados **por symlink** dentro de `.claude/skills/deep-orchestrator-agent-skill/` — assim **qualquer** dos dois alvos (a raiz ou a pasta `.claude`) é uma casa válida, e um harness que resolva `SKILL_HOME` para a pasta interna não fica sem scripts. `templates/` existiu até a v3.6.0 e foi removido.
- **Instalar**: a skill NÃO assume onde cada agente vive — crie UMA entrada onde o SEU harness descobre skills (um symlink para a raiz do repo, não a pasta interna; ex.: `ln -s /caminho/do/repo <diretório-de-skills-do-seu-harness>/deep-orchestrator-agent-skill`). Confira a doc do seu harness para o caminho de descoberta. Qualquer casa é válida — a FASE 0 resolve `$SKILL_HOME` pela localização dos próprios scripts, nunca por um caminho fixo. Depois verifique com `./scripts/check-install.sh --root <casa>`.
- **Harnesses** (Claude Code, DSH, pi, jcode, opencode...): cada um descobre skills à sua maneira — crie o symlink no caminho que o SEU usa (a FASE 0 testa primeiro as variáveis do harness, ex. `$CLAUDE_SKILL_DIR`, e depois alguns diretórios comuns apenas como última tentativa). Sem script de "publicação global": instalar é um comando seu, um symlink, e pronto.
- **Verificar** uma instalação: `./scripts/check-install.sh [--root <dir>]` — exit 0 = completo (SKILL.md + ferramentas executáveis + prompts), 1 = faltando itens, 2 = uso inválido. Rode depois de qualquer instalação/atualização.
- Um clone legado por **cópia** (ex.: `~/.local/share/deep-orchestrator/`) congela a versão do dia — prefira o symlink (recrie o link apontando para a raiz do repo).

## MODO CONTIDO

Se a skill for invocada com o cwd **dentro de uma git worktree vinculada**, ela entra em MODO CONTIDO e trata essa worktree como raiz-de-mundo:

- os squash-commits vão para o **branch da worktree**, jamais para `main`/`master`;
- nenhum arquivo é escrito no projeto principal — `do-wt.sh verify` confere ao fim de cada onda o HEAD, a working tree (incluindo arquivos ignorados, para pegar um `node_modules/` nascendo lá) e o config local contra o baseline da FASE 0. A prova é de **autoria**, não de imutabilidade: se o principal mudou mas nenhum commit desta execução é alcançável a partir do HEAD dele, é ALERTA (você trabalhando em paralelo), não violação;
- as worktrees-filhas nascem num **container irmão oculto** `<pai>/.<worktree>-do/<RUN_ID>/` (fallback automático para `<worktree>/.deep-orchestrator/worktrees/` quando o irmão cairia dentro de outro repositório git; force com `DO_FORCE_NESTED=1`);
- os branches vivem num namespace exclusivo por execução (`do/<slug>/<RUN_ID>/<nome>`), então duas orquestrações simultâneas não se apagam;
- a limpeza usa **allowlist** (o ledger `owned.tsv` + lock nativo do git), nunca varredura: `git worktree list` e `git branch --list` enxergam worktrees de outras sessões, e `git worktree prune` é proibido. Quem limpa é o **script**, por tarefa (`do-wt.sh gate` → `finish` no gate verde), e todo branch é arquivado em `refs/do-archive/$RUN_ID/` antes de ser apagado;
- a sujeira que já existia na worktree antes da execução é **do usuário** e nunca entra nos commits (`do-wt.sh stage-delta`).

O único vestígio compartilhado aceito é o registro administrativo das filhas em `$GIT_COMMON_DIR/worktrees/`, que o próprio git cria e é inevitável.

Em MODO NORMAL (invocação na árvore principal) valem as mesmas invariantes, com `$CHILD_ROOT` em `<pai>/<repo>-worktrees/<RUN_ID>/`.

## Novidades na v4.1.0

Release de **conserto**, não de reescrita. O defeito de fundo era um só: regras escritas em prosa que o LLM esquecia no meio de uma execução longa — worktrees que não eram limpas conforme o trabalho avançava, filhas que nunca chegavam a ser mergeadas e ninguém ficava sabendo, e uma pesquisa que falhava sem que o usuário fosse chamado para trocar a chave Brave. A v4.1.0 move o enforcement **da prosa para o script** (determinístico) e absorve o commit `fe3a1c2`, que tinha mudado o contrato (`wt=` termina em commit + push; purge final) sem versão.

- **LIMPEZA POR TAREFA, FEITA PELO SCRIPT (invariante I-CLEAN)**: integrar uma filha passou a ser **dois comandos** — `do-wt.sh integrate <nome> "<msg>"` (squash-merge + snapshot `int-<nome>` no SHA pós-merge + status `gate-pending`) e `do-wt.sh gate <nome>` em background (install → build → test → lint, no snapshot, com `HUSKY=0 CI=1`). **Gate verde → o próprio `gate` chama `finish`** e imprime `GATE VERDE — <nome> fechado`: salva restos da árvore da filha, arquiva o branch em `refs/do-archive/$RUN_ID/<nome>`, remove a worktree, apaga o branch e fecha **todos** os snapshots dela. A limpeza acontece no instante do verde, mesmo que ele chegue depois dos merges seguintes — **sem depender de o LLM lembrar**. Gate vermelho (rc 4) → nada é limpo: o branch segue como backup para o fix. Os comandos do gate são gravados **uma vez** na FASE 1 (`do-wt.sh gate-set build|test|lint|install|e2e "<comando>"`). Quem **não** será integrado fecha com `do-wt.sh close <nome> [--discard "<motivo>"]`. Os antigos 5 comandos manuais (`mark`/`remove`/`drop-branch`) ficam só como ferramenta de reparo — e o `drop-branch` não apaga mais trabalho não integrado depois de um `mark MERGED` manual.
- **PORTÃO INTER-ONDA**: o fim de onda virou `do-wt.sh sweep && do-wt.sh assert-clean --wave <N+1>; do-wt.sh verify`, e o rc **não é ignorável** — cada sobra sai listada com o **comando exato de conserto**. O `sweep` agora falha com `feature`/`fix` ainda `ACTIVE` (não integrada), `gate-pending` ou `REVERTED`, e fecha sozinho snapshot órfão. E, de qualquer jeito, o `do-wt.sh new` **recusa (rc 6)** criar `feature|fix|prep` da onda N enquanto houver sobra de onda anterior — inclusive `test-`/`val-` de duas ondas atrás: teste de onda intermediária esquecido não existe mais. `do-wt.sh checklist` imprime o **CARTÃO DA ONDA** (a sequência com os comandos exatos), para re-ancorar depois de uma compactação de contexto.
- **"NUNCA EM SILÊNCIO" (invariante I-MERGE)**: toda filha `feature|fix|test` termina a execução **integrada** ou **listada no relatório final com o motivo**. O ledger `owned.tsv` ganhou duas colunas (11 no total): `parent` (de qual filha é o snapshot) e `outcome` (`MERGED` · `EMPTY` · `DISPOSABLE` · `NEVER-MERGED:<motivo>`); `do-wt.sh ledger` imprime a tabela `NOME KIND ONDA STATUS OUTCOME ARCHIVE_REF`, fonte da seção **"Não integrado"** — agora **obrigatória** no relatório ("nenhum" quando vazia) — e o título deixa de ser fixo: **"Tarefa concluída"** ou **"Tarefa concluída PARCIALMENTE"**. O `purge` só imprime `PURGE OK` se o ledger **e a realidade** (diretórios em `$CHILD_ROOT`, refs em `$BRANCH_NS/`) fecharam, e sai **rc 3** com o bloco `PURGE: NUNCA INTEGRADAS / PARCIAIS` quando algo foi arquivado sem integrar — inclusive **`MERGED-PARTIAL:<motivo>`**: o squash está em `$BASE_BRANCH`, mas a filha fechou com gate vermelho ou com fix commitado e nunca integrado (cauda só no arquivo). Squash **vazio** não vira mais `MERGED` (rc 4, `VAZIO: ...`). Conflito de squash é detectado **antes de tocar a raiz** (`git merge-tree`, git ≥ 2.38): a raiz-de-mundo fica intacta e a resolução acontece dentro da filha. **Re-integração** (fix após gate vermelho) que perderia deleção/reversão do fix — o 3-way parte do `base_sha` antigo e ficava com a versão que já estava em `$BASE_BRANCH`, dizendo "sem delta novo" — agora é **recusada** (rc 1, com a lista de paths): merge de `$BASE_BRANCH` na filha **antes** do fix. Execução anterior abandonada com worktrees vivas sai anunciada na FASE 0 (`DO_ORPHAN_RUNS:`) com o comando exato de purge de cada uma.
- **`wt=` TERMINA EM COMMIT + PUSH (R8j) + PURGE FINAL** (retroativo — é o `fe3a1c2`, que saíra sem versão): com `wt=<nome>`, o COMMIT-FINAL é commit + push no branch do próprio wt (`do/wt/<nome>`), **nunca** merge de volta para o branch de origem — integrar o wt é decisão exclusiva do usuário. E toda execução termina em `do-wt.sh purge`, agora como **rede de segurança** da limpeza por tarefa (ver [Uso](#uso)).
- **PERGUNTA DA CHAVE BRAVE — INCONDICIONAL (protocolo PESQUISA-FALHOU)**: quando a pesquisa **exigida** não funciona, o orquestrador **pausa e pergunta** em vez de parar mudo ou seguir calado — e isso **vence** "não me pergunte nada", "autônomo", `no-stop` e `plan=off`, e **não depende** de `do-question`. O portão passa a ser o novo `scripts/surf-gate.sh`, **fail-closed** (`SURF_GATE=0|78|127` + `SURF_CODE` + a mensagem do surf **verbatim**; o antigo `surf doctor … >/dev/null` jogava a mensagem fora e lia exit 1 como "prossiga"). Cota esgotada/429 **não** sai 78 no surf — sai exit 1, igual a "busca vazia" —, então toda chamada é classificada (`surf-gate.sh classify` → `OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78 | …`). O plano marca cada sub-tarefa com `SEARCH_REQUIRED=sim|nao`, todo handoff abre com `## SEARCH_STATUS`, e a **TRIAGEM DE PESQUISA** (FASE 3, passo 4.5) lê isso **antes** de integrar. A pergunta tem 4 opções — troquei a chave · ajustei plano/cota ou esperei o cooldown · seguir **sem** pesquisa (premissas marcadas NÃO VERIFICADAS) · abortar —, o estado fica em disco (`search-pause.md`) e a retomada é na mensagem seguinte. Detalhes em [Quando a pesquisa falha](#quando-a-pesquisa-falha--o-protocolo-pesquisa-falhou).
- **FLAG `no-test`** (`DO_TEST_MODE=none`): **não cria** testes — nenhuma sub-tarefa de teste, Testing Subwave desligada, e o `do-wt.sh new` recusa worktree de teste. **Não criar ≠ não rodar**: o gate (com a suíte existente) e a Validation Subwave continuam.
- **FLAG `only-e2e`** (`DO_TEST_MODE=e2e`): as Testing Subwaves criam **apenas testes end-to-end**, por **jornada** do usuário (cobertura de jornadas no lugar de cobertura de linha). Mutuamente exclusiva com `no-test`.
- **FLAG `do-question`** (`DO_QUESTION=1`): autoriza o orquestrador a **perguntar** — uma RODADA DE DÚVIDAS única antes do plano e no máximo uma por onda, ao fim dela. A pergunta da chave Brave **não** depende desta flag.
- **`--flags` E ZONA DE PREFIXO**: os prefixos da invocação viajam num único argumento, `do-context.sh --flags='<tokens>'`, e o **script é o único validador**. Typo (`no-tests`, `e2e-only`, `mp=8`) sai **exit 2 com a sugestão** em vez de virar texto da tarefa e inverter o pedido em silêncio; `no-test` + `only-e2e` sai exit 2. `surf-sub-agents=N` agora é validado (1..20) e gravado no ENV_FILE. `wt=<nome>` repetido **reentra** na mesma worktree (antes criava `<nome>-2`).
- **macOS / bash 3.2**: o lock do `owned.tsv` tem fallback `mkdir` atômico para máquinas sem `flock(1)` (com quebra de lock velho); saíram os `sed -i` GNU, as comparações de `wc -l` cru, `${var^^}` e a iteração de array vazio sob `set -u` (que derrubava `do-prefs.sh` e `evolution-survey.sh`). As cinco suítes rodam **verdes no macOS** (bash 3.2.57, BSD sed/wc, git 2.39) — antes, `test-contencao.sh` dava 75/10 ali.
- **Estruturais**: a `description` do frontmatter coube em ≤ 1024 caracteres (eram 2421 — a listagem de skills truncava e escondia flags e triggers); a FASE 0 foi reordenada (passo 0 **ESTADOS PENDENTES** → 1 parse de prefixos → 2 portão do plano → 3 comando único); "AGUARDE" passou a ter definição única (grava estado, a pergunta é a última coisa da resposta, encerra o turno); e o `<orchestrator>` do SKILL.md voltou a parsear como XML inteiro.
- **REVISÃO ADVERSARIAL DA PRÓPRIA v4.1.0 (rodada final)**: uma revisão com céticos por achado, reproduzidos em lab, corrigiu o que a primeira implementação errou — (1) filha cujo sub-agente saiu do branch registrado (`git switch -c`, HEAD destacado) era arquivada **vazia** e o trabalho ficava dangling: agora `integrate` **recusa** (rc 1, com o conserto) e `close`/`finish`/`purge` arquivam também o HEAD em `refs/do-archive/$RUN_ID/<nome>-HEAD`; (2) `undo` só desfazia o **último** squash de uma filha re-integrada: agora desfaz **todos** (`undo-<nome>-<k>`) e o `pre` do 1º squash é preservado (`wave-files` volta a ver a onda inteira); (3) `purge`/`finish --gate-ok` fechavam como `MERGED` uma filha com gate vermelho e fix nunca integrado: agora é `MERGED-PARTIAL` e vai ao relatório; (4) o snapshot de `test-onda(N-1)` travava `new fix ondaN-*` (rc 6): a guarda passou a seguir o kind do parent; (5) dois `gate` no mesmo nome se atropelavam: o 2º sai rc 3 e o veredito fica amarrado ao squash; (6) `gate` de `test-*` em `only-e2e` ligava o e2e só com `--e2e`: agora liga sozinho; (7) `do-wt.sh checklist` usa a numeração exata dos passos da FASE 3 e ganhou `checklist final` (FASE 4); (8) a opção [3] do protocolo ("seguir sem pesquisa") não valia nas ondas seguintes quando a falha era de cota: `surf-gate.sh choose no-search` grava o estado e o portão imprime `SURF_MODE=no-search`; (9) typo de flag fora da regex da zona (`e2e-only`, `--no-test`) virava texto da tarefa: o token de fronteira vai em `--boundary='<token>'` e o script decide; (10) reuso de execução anterior à v4.1.0 vinha sem `DO_SURF_GATE`: o script completa o env antigo. E o **SKILL.md foi condensado de 304k para 215k caracteres** (a primeira implementação o tinha inchado a partir dos 192k da v4.0.0): cada regra tem **uma casa canônica** e o que o script já imprime (sobra + comando de conserto) não é reexplicado.
- **Testes**: `test-contencao.sh` 85 → **309** asserções (A35–A56: integrate/gate/finish/close, purge, sweep, assert-clean, lock sem flock, ledger, re-integração, HEAD fora do branch, undo de todos os squashes, MERGED-PARTIAL, reentrância do gate, e2e automático, cartões); nova suíte `test-flags.sh` (**307**, FL1–FL16: `--boundary`, env antigo completado, órfãs com `wt=`); `test-surf-gate.sh` 46 → **228** (G0, G9–G12: classify, pause/resume, `choose`, fail-closed, contrato cruzado SKILL.md × scripts × prompts, orçamento ≤ 220k chars); `test-plan-approval.sh` **139**; `test-evolve.sh` **81** — **1064 asserções, todas verdes**. Decisões D24–D31 em `docs/decisions/2026-09-20-limpeza-por-tarefa-pergunta-pesquisa-flags.md`.

## Novidades na v4.0.0

A skill deixou de ter um sistema de busca. O gatilho foi um bug: `search.sh`
tratava **todo** exit code não-zero do `surf` como falha transitória, então o
`exit 78` da v8 — "não há chave Brave válida" — ficava indistinguível de um
timeout, e o wrapper respondia a mesma pergunta pelo cliente Brave interno ou
pelo DuckDuckGo. A skill reproduzia, uma camada acima, exatamente o defeito que
o surf v8 acabara de eliminar: uma resposta confiante vinda de um provedor que
o usuário não escolheu, sem nenhum sinal de que a chave estava quebrada.

Manter um "shim fino" em volta do surf não resolveria: um shim **é** um sistema
de busca (mapeamento de flags, envelope próprio, códigos de saída próprios), e
é exatamente onde o próximo mantenedor reintroduz um fallback. Por isso os seis
scripts foram apagados, e o SKILL.md manda o sub-agente chamar os binários
globais direto.

O que se perdeu de propósito: o piso keyless (uma resposta de Instant Answer
apresentada com a mesma confiança de uma pesquisa real), a dedup por URL entre
queries de um lote e o cache intra-run — todos substituídos por **uma** chamada
`surf-search-normal` com brief, que planeja o conjunto de queries por LLM, roda
até `--sub-agents` delas em paralelo e dedupa canonicamente no ledger.

Ver `docs/decisions/2026-08-29-surf-agent-skill-obrigatorio.md`.

## Novidades na v3.9.0

- **EVOLUÇÃO COMO PERGUNTA NO TERMINAL (nunca mais um site)**: o questionário Plannotator acabou — depois de TUDO (commit, push e relatório), o orquestrador imprime **uma pergunta em texto** com as propostas do agente de evolução, cada uma numerada com opções e escopo:
  ```
  1 - Toda vez que criamos uma worktree precisamos instalar as dependências
     como resolver definitivamente?
     a: usar symlinks para as dependências
     b: merge para principal e testar
     c: Não fazer nada (descartar)
     (1 = fix local · 2 = fix global — qual config você quer? ex.: 1:b2)
  ```
  Você responde na próxima mensagem com códigos (`1:b2`, `nada` para pular, `config: <texto>` para preferências livres). A opção escolhida **vira a ação salva** (a/b = salvar no escopo indicado; c = descartar). Sem resposta → tudo fica pendente, nada é aplicado (`scripts/evolution-survey.sh` ask/answer/apply/dismiss).
- **FLAG `no-evolve`**: na invocação (`/deep-orchestrator-agent-skill no-evolve <tarefa>`), pula a pergunta **e** o pós-processamento — o agente de evolução que lê todo o histórico (handoffs + transcripts + TASK_PLAN.md) nem roda.
- **PUSH NO COMMIT-FINAL**: o passo final agora commita **e** faz push do `$BASE_BRANCH` (nunca bloqueia; sem remote → registra e segue) — a pergunta de evolução vem depois de TUDO, incluindo o push.
- **Prefixo `max-parallel=N`**: `mp=N` virou `max-parallel=N` na invocação (`DO_MAX_PARALLEL`, default 50) — mesmo cap de concorrência, nome explícito. Decisões D18–D22 em `docs/decisions/2026-08-28-pergunta-evolucao-terminal.md`.

## Novidades na v3.8.0

- **QUESTIONÁRIO DE EVOLUÇÃO PÓS-EXECUÇÃO (substituído pela v3.9.0)**: ao fim de cada execução, UM sub-agente fresco analisa o histórico completo (handoffs de todas as ondas + transcripts do harness quando existem) e sobe um questionário próprio no Plannotator (só as perguntas, SEM limite de tempo): o usuário decide por proposta **salvar/não salvar** e o escopo **projeto ou global** (`scripts/evolution-survey.sh` round/answers/apply). Fechou sem responder → tudo fica PENDENTE e nada é aplicado.
- **PREFS POR PROJETO (`.deep-orchestrator-preferences/`)**: configs e aprendizados do projeto ficam no PRÓPRIO projeto (carregados na FASE 1, salvo quando o usuário decide salvar); dicas globais ficam na MESMA pasta dentro da skill — tudo **gitignored** (memória consultiva, nunca política). `ensure-gitignore` acrescenta a linha no `.gitignore` de cada projeto automaticamente.
- **LEARNINGS.md REMOVIDO DO REPO**: as 59 entradas antigas foram reclassificadas — as globais migraram para `global-tips.md`; as de projeto específico saíram (git history preserva). `evolve-skill.sh` não commita mais memória (`add`/`consolidate` saem com mensagem de migração); o `apply` de CORPO vai sempre para branch `evolve/YYYY-MM-DD` + diff, nunca merge sozinho.
- **A FASE 1 consulta prefs + memória** antes de planejar (`do-prefs.sh load` + `evolve-skill.sh search`) — evita repetir erros e respeita as preferências declaradas do projeto. Decisões D12–D17 em `docs/decisions/2026-08-27-questionario-evolucao.md`. Testes: `scripts/test-evolve.sh` (suíte nova — hoje F1–F14, S1–S10 e E1–E6, 81 asserções).

## Novidades na v3.7.0

- **AUTO-EVOLUÇÃO CONTÍNUA (substituída pela v3.8.0)**: retrospectiva do orquestrador + `evolve-skill.sh add` no `LEARNINGS.md` commitado. Esse mecanismo foi substituído pelo questionário + prefs gitignored — o `LEARNINGS.md` não existe mais no repo.

## Novidades na v3.6.0

- **HTML Explainer v3.6.0 (novo fluxo)**: o EXPLAINER.html do COMMIT-FINAL deixa de ser gerado pelo script `scripts/generate-explainer.sh` + template `templates/html-explainer.html` (ambos REMOVIDOS). Agora o orquestrador delega a um sub-agente que segue a skill `html-explainer-agent-skill` (brief didático: leitor, portão de complexidade, buzzwords, figuras com afirmação na legenda e arestas rotuladas, andaime dobrado) e renderiza com `visual-explainer`/`plannotator-visual-explainer` — SEM limite de tempo (a geração pode demorar o quanto precisar) e SALVANDO NO LUGAR em `EXPLAINER.html` na raiz da raiz-de-mundo (a UI do Plannotator é opcional e nunca substitui o arquivo). Degradação documentada: se o fluxo falhar, o orquestrador grava um EXPLAINER.html mínimo via Bash (exceção R1-c) e registra no relatório.
- Contrato de instalação atualizado: `scripts/check-install.sh` não exige mais `generate-explainer.sh` nem `templates/`.
- **Plannotator como runtime do EXPLAINER (auto-instalado)**: o novo fluxo do EXPLAINER usa o backend de render/anotação do Plannotator — o `html-explainer-agent-skill` delega a renderização ao `plannotator-visual-explainer` (tokens de tema do Plannotator aplicados ao arquivo final). O binário é instalado automaticamente quando ausente (`scripts/check-plannotator.sh --install`, modo `--minimal` → só `~/.local/bin`; mínima 0.19.1) e foi verificado na máquina de referência em v0.27.6. A entrega continua sendo o ARQUIVO `EXPLAINER.html` salvo no lugar — a UI de anotação é opcional e nunca substitui o arquivo.

## Novidades na v3.5.1

- **Instalação à prova de alvo errado (bugfix do contrato)**: a pasta `.claude/skills/deep-orchestrator-agent-skill/` (padrão Claude Code) passou a **espelhar `scripts/`, `prompts/` e `templates/` por symlink** para a raiz — antes ela continha apenas o `SKILL.md`, e qualquer harness que resolvesse `$SKILL_HOME` para ela rodava FASE 0 e abortava com `PARE: do-context.sh nao encontrado` (era o estado da instalação do DSH após o rebrand). Agora **qualquer** alvo de instalação é uma casa válida, e instalações existentes apontadas para a pasta interna passam a funcionar sem repontar symlink.
- **FASE 0 mais abrangente**: a busca do `do-context.sh` ganhou o candidato `${DSH_HOME:-$HOME/.dsh}/skills/deep-orchestrator-agent-skill` (raiz de skills do usuário no DeepSeek Harness).
- **`scripts/check-install.sh`**: nova prova de instalação completa (SKILL.md + ferramentas executáveis + prompts + template; exit 0/1/2; `--root`, `--json`, `--quiet`) — detecta o estado "só SKILL.md, sem scripts" antes de qualquer execução.
- **README**: nova seção "Instalação (o contrato)" com o layout aceito, o DSH (ambas as raízes) e o passo de verificação.

## Novidades na v3.5.0

- **Flag `no-stop` (DO_NO_STOP)**: remove o **teto de 10 ondas por execução**. Quando presente, a execução dura **quantas ondas forem necessárias** até o REVISOR DE PLANO declarar convergência — ideal para quem quer qualidade máxima sem teto arbitrário de rodadas. A válvula anti-loop **permanece ativa** mesmo com `no-stop`: 2 REPLANs consecutivos sem novas sub-tarefas ACEITAS forçam a convergência (documentada no relatório final), então a execução nunca itera para sempre sem progresso. Invocação: `/deep-orchestrator-agent-skill no-stop <tarefa>`. Ausente → default `0` (teto histórico de 10 ondas preservado).
- **Validação e guarda no `do-context.sh`**: a flag é parseada antes da FASE 0 e exportada como `DO_NO_STOP` (valores `0/1/on/off/yes/no/true/false`; inválido → `die 2` com mensagem clara), gravada no ENV_FILE, exportada, exibida no resumo da FASE 0 (`NO_STOP = ON/OFF`), e protegida por **guarda anti-stale no caminho DO_REUSE** (espelhando o guarda de `DO_PLAN_APPROVAL`) — reaproveitar um env com valor divergente cria execução nova em vez de inverter a flag em silêncio.

## Novidades na v3.4.0

- **PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5, R10)**: quando a invocação **pede um plano**, o plano vai para o [Plannotator](https://github.com/backnotprop/plannotator) e o usuário aprova ou anota, no navegador. **Cada anotação REGERA o plano e abre um Plannotator inteiramente NOVO** (processo novo, servidor novo, aba nova) — nunca um remendo na sessão anterior — até a aprovação ou até o orçamento de revisões acabar. Nenhuma worktree, branch ou commit existe antes do APROVADO, e é justamente por isso que o portão fica aqui: recusar o plano não custa rollback nenhum.
- **Ligado só quando pedido**: `DO_PLAN_APPROVAL` é resolvido uma vez na FASE 0 (passo 2 desde a v4.1.0; era o 0.5) por precedência — prefixo `plan=on`/`plan=off` > variável de ambiente > gatilhos negativos ("não me pergunte nada", "autônomo", "toca o barco") > gatilhos positivos ("faça um plano", "quero aprovar antes", "revisar o plano") > **default OFF**. Quem nunca falou em plano tem exatamente o comportamento autônomo de sempre: nenhum navegador abre.
- **Instalação automática do Plannotator**: `scripts/check-plannotator.sh --install` resolve o executável (`$DO_PLANNOTATOR_BIN` → PATH → `~/.local/bin`, que quase nunca está no PATH de um shell não-interativo), confere a versão (mínima 0.19.1) e **sonda a capacidade** rodando `annotate` sem argumento — que só imprime o usage, sem abrir navegador. Ausente, instala com `--minimal`: **só o binário**, sem encostar em `~/.claude`, `~/.codex`, `~/.gemini`, `~/.kiro` ou `~/.config/opencode`. Uma instalação existente nunca é sobrescrita. Nunca `sudo`, nunca `npm -g`.
- **Independente do agente**: o portão é **uma chamada Bash** — o menor denominador comum entre Claude Code, pi coding agent, jcode e opencode. Nada de hook de plan-mode, `ExitPlanMode` ou plugin de um agente específico, porque nada disso existe nos quatro. O harness é detectado (Claude Code > pi > jcode > opencode) só para carimbar `PLANNOTATOR_ORIGIN` na UI; a detecção jamais bloqueia o portão.
- **Título imutável**: o Plannotator rastreia revisões do **mesmo** plano pelo primeiro `#` do documento. `plan-approval.sh` **recusa** (exit 2) a rodada cujo título mudou, com o título travado na mensagem — é a mesma regra que o próprio Plannotator impõe (*"Do NOT change the plan title"*).
- **Decisão por exit code, nunca por texto**: `plan-approval.sh round` devolve 0 aprovado · 10 anotado · 11 fechado · 12 timeout · 13 falha da ferramenta · 14 orçamento esgotado. Cada rodada deixa um snapshot **imutável** (`rev-NNN.md`, somente leitura), o feedback (`rev-NNN.feedback.md`) e uma linha no `trail.tsv`.
- **O plano aprovado vira restrição**: o REVISOR DE PLANO da FASE 3 passa a classificar cada proposta em DENTRO ou FORA do escopo aprovado. FORA reabre o portão uma vez (consumindo do mesmo orçamento); sem orçamento, a proposta é registrada como `FORA-DO-ESCOPO-NÃO-APROVADA` e o escopo aprovado é respeitado.
- **O plano nunca sai da máquina sozinho** — duas travas independentes, ambas ligadas por default:
  - `PLANNOTATOR_SHARE=disabled` impede o **upload** do texto do plano para o serviço de paste, que o Plannotator faria em sessão remota. Libere com `DO_PLAN_SHARE=1`.
  - `PLANNOTATOR_REMOTE=0` mantém o servidor em **127.0.0.1**. Sem isso, qualquer shell com `SSH_TTY`/`SSH_CONNECTION` no ambiente — o caso normal de um servidor de desenvolvimento — faria o Plannotator escutar em `0.0.0.0:19432`; e como `/api/approve` **não tem autenticação**, qualquer pessoa que alcançasse a máquina leria o plano e poderia **aprová-lo por você**, levando o orquestrador a criar worktrees e commitar. Para revisar por SSH, use um túnel: `ssh -L 19432:127.0.0.1:19432 <host>`. `DO_PLAN_REMOTE=1` expõe na rede de propósito, com aviso em voz alta.
- **Testes**: `scripts/test-plan-approval.sh` — 133 asserções na época (**139** na v4.1.0, todas verdes na máquina de referência: macOS, bash 3.2.57, com o `timeout` do coreutils instalado — o caso P4 depende de um `timeout(1)` no PATH), tudo mockado (binário e instalador falsos num PATH temporário), **sem rede, sem navegador e sem instalar nada**.

## Novidades na v3.3.0

- **Sistema de busca 3-tier (F1-03)** — **SUPERADO na v4.0.0**: o sistema de busca interno foi REMOVIDO; a pesquisa é 100% surf-agent-skill v8 (ver `docs/decisions/2026-08-29-surf-agent-skill-obrigatorio.md`). Descrição histórica: `scripts/search.sh` — surf-agent-skill (Tier 1, multi-provider AI-powered) → Brave Search API (Tier 2, via `search_brave_api()` do `brave-search.sh`) → DuckDuckGo keyless (Tier 3, Instant Answer, cobertura limitada). Verificação de tiers antes de cada onda via `scripts/check-search-credits.sh` (exit 0 = Tier 1/2 disponível; exit 1 = só Tier 3, degradado; exit 2 = nada disponível) e lotes paralelos via `scripts/search-parallel.sh` (uma chamada por lote, nunca loop). O surf-agent-skill voltou como Tier 1 — a busca Brave interna da v3.0.0 não o substitui mais.
- **Subwaves duplas (F2-02/F2-04)**: TESTING (`test-ondaN-*`, máximo 3 worktrees de teste por onda — contam no teto DO_MAX_PARALLEL) e VALIDATION (`val-ondaN-*`, gate completo + revisão adversarial do diff integrado) rodam em background após cada onda e são integradas na onda seguinte (passo 3.5) ou no COMMIT-FINAL — nunca bloqueiam o disparo das ondas de feature.
- **Correções críticas da Fase 1 (F1-01 a F1-03)**: `do-wt.sh undo` seguro (reset --hard só com working tree exclusivamente untracked; o commit desfeito é arquivado em `refs/do-archive/$RUN_ID/undo-<nome>`), baseline de ignorados na FASE 0 + `clean-ignored-delta` no lugar do `git clean -fdXq` genérico (nunca apaga ignorados pré-existentes do usuário), `stage-delta` com `-uall` nos dois lados (arquivos novos dentro de dirs untracked do usuário entram no commit; a sujeira preexistente continua fora) e `--budget-ms` no Tier 1 do search.sh (`--timeout` em segundos vira milissegundos para o surf-search-normal — o `--budget-ms` do surf continua em MILISSEGUNDOS, e na v8 o `--timeout` também).
- **Gate em snapshot de integração (F3-01)**: o squash-merge é atômico e o gate (build + testes + linter) sai da seção crítica — roda em background numa worktree efêmera `int-ondaN-<nome>` (kind=integration, registrada no owned.tsv) criada no SHA pós-merge. Merges seguem em sequência; a limpeza de cada filha e o fim da onda aguardam o respectivo gate de snapshot (`status=gate-pending` no owned.tsv; o `do-wt.sh sweep` detecta gate-pending, avisa e sai != 0). Falha tardia: `do-wt.sh undo <nome>` reverte exatamente aquele squash com HEAD avançado, arquivando o commit em `refs/do-archive/$RUN_ID/undo-<nome>`. **Decisão D1**: builds duplicados (snapshot + validação + gate final) são esperados. **Na v4.1.0** esse ritual manual (criar o snapshot, `mark gate-pending`, limpar no verde) virou dois comandos do script — `do-wt.sh integrate` + `do-wt.sh gate` —, e o snapshot se chama `int-<nome>`.
- **DO_MAX_PARALLEL (F3-02)**: prefixo `max-parallel=N` na invocação (`/deep-orchestrator-agent-skill max-parallel=N <tarefa>`) — o orquestrador exporta `DO_MAX_PARALLEL` antes da FASE 0; ausente, default 50. Orçamento: features por onda ≤ DO_MAX_PARALLEL; in-flight total ≤ DO_MAX_PARALLEL (features + worktrees de teste/validação das subwaves + revisores + REVISOR DE PLANO — tudo no mesmo teto); ondas maiores viram batches sequenciais com a própria barreira.
- **Gate definido uma vez (F3-03)**: a FASE 1 detecta e registra no TASK_PLAN.md o trio exato `GATE_BUILD`/`GATE_TEST`/`GATE_LINT` do projeto-alvo (package.json/Makefile/pyproject.toml/Cargo.toml/go.mod); toda invocação de gate referencia esse trio, com cwd conforme o contexto (snapshot, validação ou `$BASE_DIR` no gate final).
- **Lockfile como singleton (F3-04)**: manifesto + lockfile entram no mapa de propriedade como recurso singleton — no máximo 1 agente por onda adiciona dependências; os demais registram "deps pendentes: <pacote@versão>" no handoff e a adição acontece no COMMIT PREP da onda seguinte.
- **Tiering de modelos por papel (F3-09)**: quando o harness permite, agentes de teste e revisores adversariais rodam em modelo médio, REVISOR DE PLANO e síntese final em modelo forte, features no padrão; regra de escala: ≤2 sub-tarefas pequenas e independentes não geram fan-out extra.
- **Testes**: `scripts/test-contencao.sh` — 85 asserções na época, 309 na v4.1.0 (A33: falha tardia de gate com undo de HEAD avançado; A34: gate-pending bloqueia o fim de onda).

## Novidades na v3.2.0

- **MODO CONTIDO** (acima) + **FASE 0 — DELIMITAR O MUNDO**: `scripts/do-context.sh` detecta worktree vinculada, resolve a fronteira e grava o arquivo de estado que toda chamada Bash sourceia.
- **Guardas em código, não em prosa**: `scripts/do-wt.sh` concentra criação, merge, undo, remoção, limpeza e prova de contenção. Cada operação destrutiva recusa alvos que não estejam registrados nesta execução.
- **Regra de dependências (R9)**: instalação permitida se necessária, sempre com cwd na worktree-filha, em modo congelado e com `HUSKY=0` (um postinstall de husky grava `core.hooksPath` no `.git` compartilhado). Cache global do usuário é permitido; escopo global de instalação é proibido.
- **Testes de regressão**: `scripts/test-contencao.sh` — 85 asserções na época (309 na v4.1.0) cobrindo detecção de modo, colocação, limpeza segura, worktrees de terceiros, preservação da sujeira do usuário, paths com acento e espaço, guarda de índice sujo, distinção entre vazamento nosso e trabalho do usuário no projeto principal, conflito e re-merge (A23), exits da FASE 0 (A28/A29), flock (A30), kind=validation (A31), falha tardia de gate (A33) e gate-pending (A34).

## Novidades na v3.0.0

- **Ondas ilimitadas** com recálculo dinâmico — após cada onda, um sub-agente REVISOR DE PLANO analisa os handoffs e o TASK_PLAN.md, propõe novas sub-tarefas ou declara CONVERGÊNCIA. O ciclo só termina por convergência declarada, nunca por um número fixo de ondas.
- **Busca interna Brave** (`$SKILL_HOME/scripts/brave-search.sh`) — CLI próprio sobre a Brave Search API que substituía o `surf-search-normal` e não dependia mais do `surf-research-skill` nem do CLI `surf-ai`. **SUPERADA na v3.3.0**: o surf-agent-skill voltou como **Tier 1** do sistema de busca 3-tier (`search.sh`); a Brave API virou o Tier 2 e o DuckDuckGo keyless o Tier 3.
- **Verificação de créditos** antes de cada onda (`$SKILL_HOME/scripts/check-brave-credits.sh`) — sem créditos, o orquestrador para e informa o usuário (única exceção à autonomia total). **SUPERADA na v3.3.0**: o verificador agora é `check-search-credits.sh` (3 tiers; exit 2 = TODOS os tiers fora) — `check-brave-credits.sh` está DEPRECATED.
- **ECC Prompts integrados** — 7 templates de prompt (`$SKILL_HOME/prompts/ecc-prompts.md`) + 7 skills portados do ECC (`$SKILL_HOME/prompts/ecc-skills.md`), incluindo Security Review (AgentShield), Planning Prompt (Plan First) e Prompt Defense Baseline.
- **Prompts de busca para dev** (`$SKILL_HOME/prompts/search-prompts.md`) — 8 categorias de busca, sistema de evolução de perguntas (question evolution) e prompts por domínio.
- **HTML Explainer** automático ao final de cada execução (pelo template próprio da época — removido na v3.6.0) — de-para de todas as mudanças em 6 abas, salvo como `EXPLAINER.html` na raiz da worktree em que a skill foi invocada (mecânica substituída na v3.6.0 — ver Novidades na v3.6.0).

## Como funciona

O deep-orchestrator-agent-skill nunca escreve código. Ele atua como arquiteto-distribuidor: projeta o plano, divide o trabalho em ondas topológicas (o REVISOR DE PLANO recalcula após cada onda; o teto é de 10 ondas por execução, removido por `no-stop`), cria e batiza worktrees isoladas do Git (uma por sub-agente), dispara os agentes em paralelo, aplica revisão adversarial e integra cada resultado via `git merge --squash` um a um (`do-wt.sh integrate`) — o gate (as etapas install/build/test/lint registradas na FASE 1 com `do-wt.sh gate-set`) roda em background numa worktree de snapshot efêmera `int-<nome>`, fora da seção crítica. **No instante do gate verde o próprio script fecha a tarefa**: arquiva e apaga o branch, remove a worktree e os snapshots dela — os commits intermediários do sub-agente saem da história. A onda seguinte só abre com o **portão inter-onda** verde (`assert-clean`), e ao final ele commita, pusha e relata **o que não foi integrado**.

```
DELIMITAR  →  ANALYZE  →  PLAN  →  (APROVAR)  →  EXECUTE-ONDA (repeat — até 10 ondas; sem teto com no-stop)  →  COMMIT-FINAL
```

### Fases

| Fase | Nome | O que faz |
|------|------|-----------|
| 0 | **DELIMITAR O MUNDO** | Passo 0 — **ESTADOS PENDENTES**: retoma, do disco, uma pausa de pesquisa (`search-pause.md`), uma rodada `do-question` ou uma pergunta de evolução que ficou esperando resposta. Depois separa a **zona de prefixo** da invocação, resolve o portão do plano e roda, num comando único, `$SKILL_HOME/scripts/do-context.sh --flags='<tokens>'`: o script **valida as flags** (token desconhecido ou contraditório = exit 2, com sugestão), detecta se o cwd está numa worktree vinculada, resolve `$BASE_DIR`, `$BASE_BRANCH`, `$MAIN_ROOT`, `$CHILD_ROOT`, `$BRANCH_NS` e `$SKILL_HOME`, captura os baselines de contenção e grava o ENV_FILE. O orquestrador **confere o resumo** (`TEST_MODE = …`, `QUESTION = …`, `NO_STOP = …`) contra o que foi digitado, roda o purge de cada execução abandonada que o script anunciar (`DO_ORPHAN_RUNS:`) e **registra** o veredito do portão da surf (`scripts/surf-gate.sh`) — sem parar aqui: ainda não há plano. Aborta com mensagem acionável se não houver branch de integração |
| 1 | **ANALYZE** | Lê o prompt, mapeia a estrutura do repositório, identifica subsistemas, classifica greenfield/brownfield, localiza golden masters, consulta as prefs do projeto e **grava o gate uma única vez** (`do-wt.sh gate-set build\|test\|lint\|install "<comando>"`). Com `only-e2e`, detecta o runner e2e (`gate-set e2e`). Com `do-question`, fecha com a **RODADA DE DÚVIDAS** (um bloco numerado, opções a/b/c, um default por dúvida) |
| 2 | **PLAN** | Decompõe a tarefa em sub-tarefas atômicas, identifica o grafo de dependências, organiza em ondas topológicas (número NÃO fixo — o plano é um ponto de partida), marca cada sub-tarefa com **`SEARCH_REQUIRED=sim\|nao`**, planeja os testes conforme o `TEST_MODE` (com `only-e2e`: o MAPA DE JORNADAS), define o mapa de propriedade de arquivos, batiza cada worktree, escreve os prompts de delegação e publica o TASK_PLAN.md. Fecha no **PORTÃO PÓS-PLANO**: portão da surf != 0 **e** alguma sub-tarefa exige pesquisa → protocolo PESQUISA-FALHOU (pergunta ao usuário) **antes** de qualquer worktree |
| 2.5 | **APROVAR O PLANO** | *Só quando `PLAN_APPROVAL=1`.* Garante o Plannotator na máquina (`check-plannotator.sh --install`), escreve o plano legível em `$PLAN_DOC` e roda `plan-approval.sh round`: aprovado → FASE 3; anotado → **regera o plano e abre um Plannotator NOVO** (até `DO_PLAN_MAX_REVISIONS`); fechado/timeout/orçamento → para limpo, sem nenhuma worktree criada. Desligado (o default), a fase é pulada inteira |
| 3 | **EXECUTE-ONDA** | Para cada onda: re-ancoragem (`do-wt.sh checklist`) + portão da surf (`surf-gate.sh`) → commit prep (se necessário) → **portão inter-onda** (`assert-clean --wave N`) + cria worktrees (`new` recusa, rc 6, se sobrou algo de onda anterior) → dispara agentes em paralelo (escalonado) → fecha as subwaves da onda anterior (o gatilho é o ledger: `test-*` integra como feature, `val-*` fecha com `close`) → barreira → **TRIAGEM DE PESQUISA** (o `SEARCH_STATUS` de cada handoff; falhou → pergunta ao usuário **antes** de integrar as bloqueadas) → **recálculo dinâmico (REVISOR DE PLANO)** → revisão adversarial → por tarefa aprovada, `integrate` + `gate` em background (**gate verde = o script fecha filha, branch e snapshot**; vermelho = nada é limpo, fix na mesma worktree e re-integrate) → **fim de onda**: `sweep && assert-clean --wave N+1; verify` (rc != 0 não é ignorável) → handoff → subwaves pós-onda conforme o `TEST_MODE`. Repete até o REVISOR DE PLANO declarar CONVERGÊNCIA, o teto de 10 ondas (sem `no-stop`) ou a válvula anti-loop |
| 4 | **COMMIT-FINAL** | Na ordem: fecha as últimas subwaves (bugs confirmados pelos agentes de teste entram no FIX-FINAL) → descarta o TASK_PLAN.md → roda o **gate completo** em `$BASE_DIR` (as mesmas etapas gravadas na FASE 1; com `only-e2e`, também a e2e) → **gera o EXPLAINER.html** pelo fluxo `html-explainer-agent-skill` (sub-agente delegado, sem limite de tempo; antes do commit, porque entra nele) → commita **apenas o que esta execução produziu** (a sujeira preexistente do usuário é preservada) → **push** → **`do-wt.sh purge`** (nada desta execução sobrevive; rc 3 = houve filha nunca integrada) + `assert-clean` + `ledger` → **relatório final** (título "Tarefa concluída" ou "PARCIALMENTE", seção "Não integrado" obrigatória) → pergunta de evolução → só então descarta o estado (`clean-ignored-delta` antes do `rm -rf` de `$DO_STATE`) |

### Regras fundamentais

1. **Nunca escreve código** — delega tudo a sub-agentes
2. **Nunca pergunta ao usuário — salvo seis exceções, que são obrigatórias** — autonomia total: falta informação → infere com confiança e documenta a premissa. As exceções: (a) a **surf-agent-skill não está instalada** (`SURF_GATE=127`) e existe sub-tarefa com `SEARCH_REQUIRED=sim` — instalar é `npm -g`, vedado por R9, então quem instala é o usuário; (b) a **pesquisa exigida falhou** por configuração do ambiente — portão `SURF_GATE=78` (sem chave Brave válida) ou handoff com `SEARCH_STATUS` `BLOCKED_78`/`FAILED_QUOTA`/`FAILED_OTHER`/ausente. (a) e (b) executam o **protocolo PESQUISA-FALHOU** e são **incondicionais**: vencem "não me pergunte nada", "autônomo", `no-stop` e `plan=off`, e não dependem de `do-question`; (c) abort da FASE 0 (não é repositório, HEAD destacado, repo sem commits, índice sujo, flag inválida); (d) o **portão de aprovação do plano** está ativo (`PLAN_APPROVAL=1`) — aí a interação é a entrega pedida, acontece no navegador (nunca por pergunta em texto) e só na FASE 2.5; (e) a **pergunta de evolução** ao fim de tudo (desligada por `no-evolve`); (f) a flag **`do-question`** está ativa. Toda pergunta segue o mesmo rito (**AGUARDE**): grava o estado em `$DO_STATE`, é a **última coisa** da resposta, em texto, e **encerra o turno** — a retomada lê o disco, no passo 0 da FASE 0
3. **Trabalho completo, do início ao commit — e nada some em silêncio** — nunca entrega trabalho parcial disfarçado: toda sub-tarefa termina **integrada** ou **listada na seção "Não integrado" do relatório final com o motivo** e a ref de arquivo do branch (invariante I-MERGE); havendo alguma, o título do relatório vira "Tarefa concluída PARCIALMENTE". A pausa do protocolo PESQUISA-FALHOU **não** é trabalho parcial — seguir calado sem a pesquisa exigida é que violaria esta regra. Saída antecipada legítima: o portão do plano terminar sem aprovação — e aí nada foi construído, então o repositório fica exatamente como estava
4. **Worktree é a unidade de isolamento** — cada sub-agente trabalha em sua própria worktree Git com nome descritivo (ex.: `onda1-cache-service`)
5. **Squash-merge um a um, nunca octopus** — integração sequencial em `$BASE_BRANCH` por `do-wt.sh integrate`; conflito é recusado **sem sujar a raiz** (resolve-se dentro da filha) e squash vazio não conta como integrado (rc 4). O gate roda em snapshot de integração `int-<nome>`, fora da seção crítica (decisão D1: builds duplicados são esperados)
6. **Worktree nasce nomeada e morre no gate verde da própria tarefa — quem limpa é o script** — `gate` verde chama `finish` sozinho; quem não será integrado fecha com `close`; a onda N+1 **não abre** com sobra da onda N (`assert-clean`, e o `new` recusa com rc 6). Duas sobrevidas por construção: sub-tarefa bloqueada, só dentro da própria onda, e `test-*`/`val-*`, que rodam em background por **uma** onda. No fim, o `purge` fecha tudo — sempre por nome registrado, sempre arquivando o branch antes
7. **Verificar a dependência de pesquisa antes de cada onda** — o portão é `scripts/surf-gate.sh` (**fail-closed**): `SURF_GATE=0` pronto · **78** sem chave Brave válida (configuração; retentar é inútil) · **127** pacote ausente — com `SURF_CODE` e a mensagem do surf verbatim. Em 78/127 com alguma sub-tarefa pendente `SEARCH_REQUIRED=sim`, nenhum pesquisador é disparado e o orquestrador **pergunta ao usuário** (protocolo PESQUISA-FALHOU); com todas as pendentes em `SEARCH_REQUIRED=nao`, a execução prossegue sem busca, com registro. É proibido rebaixar `SEARCH_REQUIRED` depois de um portão vermelho para fugir da pausa
8. **A worktree de invocação é a raiz-de-mundo** — nada é escrito fora dela; o branch dela é o único alvo de integração; a limpeza só toca o que esta execução registrou
9. **Dependências: dentro da worktree, congeladas, nunca globais** — instale só se necessário, com cwd na filha e `HUSKY=0`; cache global do usuário é permitido
10. **Só executa plano que o usuário aprovou** — quando o portão está ativo, nenhuma worktree nasce antes do APROVADO; o título do plano é imutável entre revisões; cada anotação regera o plano num Plannotator novo; e o feedback do usuário é correção **do plano**, nunca tarefa de implementação

## Técnicas e fundamentos

O deep-orchestrator-agent-skill não inventa orquestração do zero: ele compõe técnicas documentadas e verificadas (pesquisa profunda com fontes, agosto/2026) em cima do que o harness já oferece. As três colunas abaixo — ECC, busca em camadas e sub-agentes nativos — explicam de onde vem cada peça.

### ECC — Everything Claude Code (a técnica-mãe)

O [ECC — Everything Claude Code](https://github.com/affaan-m/ECC) (MIT) é um sistema massivo de otimização de harness de agentes: **67 agents, 281 skills, 94 commands**, além de hooks, Memory Vault, Continuous Learning e AgentShield (auditoria de segurança do próprio harness). O deep-orchestrator-agent-skill não o copia — **porta e adapta** o que ele faz de melhor, no fluxo `plan → test → implement → review → verify → remember → improve`:

- `prompts/ecc-prompts.md` — **7 templates de prompt** portados: System Prompt Base, Planning Prompt (Plan First), Code Review (método de confiança + veredito APPROVE/WARNING/BLOCK), Security Review (AgentShield + checklist OWASP), Memory Persistence, Continuous Improvement (instincts com scoring de confiança 0.3–0.9) e Clone-Analyze-Discard.
- `prompts/ecc-skills.md` — **7 skills** portadas no formato ECC (frontmatter YAML + workflow em passos): `tdd-workflow` (TDD gated RED→GREEN→REFACTOR com evidência e cobertura ≥ 80%), `security-audit` (checklist OWASP de 10 pontos + revisão do harness), `doc-generator` (docs/ADRs a partir do diff), `research-deep-dive` (search-first com matriz Adotar/Estender/Compor/Construir), `memory-vault` (handoffs entre ondas e sessões), `clone-and-analyze` (portar o melhor de repos de referência em worktree isolada) e `code-quality-gate` (gate mecânico determinístico — o braço de execução do gate pós-squash).

Princípio transversal herdado: **entrada NÃO confiável** — planos, diffs e repos clonados são lidos como texto não confiável; comandos embutidos só rodam após sanitização contra whitelist (test, lint, typecheck, coverage).

### Pesquisa — surf-agent-skill v9+ (dependência dura)

**Esta skill não tem sistema de busca.** Desde a v4.0.0 (decisão D23), toda
pesquisa web passa pelos binários globais da
[surf-agent-skill v9+](https://www.npmjs.com/package/surf-agent-skill), e por
mais nada. Não há tabela de tiers porque não há cadeia: há um backend.

```bash
npm i -g surf-agent-skill    # dependência dura
surf                         # adiciona a chave Brave — validá-la é grátis
```

| Binário | Quando |
|---|---|
| `surf-search-normal "<pergunta>" --sub-agents=N` | uma onda; o caminho padrão |
| `surf-search-unlimit "<pergunta>" --sub-agents=N --max-depth 3` | pergunta aberta que precisa descer em várias ondas |
| `surf-research-skill search-parallel "q1" "q2" --sub-agents=N --json` | lote de perguntas cruas, sem síntese |
| `"$DO_SURF_GATE"` (= `$SKILL_HOME/scripts/surf-gate.sh`) | **o portão** — FASE 0, PORTÃO PÓS-PLANO e passo 0 de cada onda |
| `surf doctor` | só para **registrar** os blocos de diagnóstico na FASE 0; o exit code dele não é interpretado |

**Brave é o único backend.** Não existe Tavily, Parallel, Wikipedia,
DuckDuckGo, provedor de reserva nem tier sem chave — o próprio surf estreitou
para Brave-only na v8. **Não existe modo degradado automático**: ou há chave
válida e a pesquisa funciona, ou o orquestrador **pausa e pergunta** — seguir
sem a pesquisa exigida é uma escolha que só o **usuário** faz.

**O portão é fail-closed.** `surf-gate.sh` roda `surf-research-skill gate`
(grátis — não gasta crédito), conta **qualquer** saída != 0 como 78 e imprime
o veredito em linhas `CHAVE=valor` — o script sempre sai 0; o veredito é a
linha, não o exit code:

| Linha | Significado |
|---|---|
| `SURF_GATE=0` | pronto |
| `SURF_GATE=78` | não há chave Brave válida — ausente, queimada, em cooldown, inválida, inalcançável ou não provada |
| `SURF_GATE=127` | a surf-agent-skill não está instalada (`surf-research-skill` ou `surf-search-normal` fora do PATH) |
| `SURF_CODE=…` | `BraveKeyMissing` · `BraveKeyBurned` · `BraveKeyCooling` · `BraveKeyInvalid` · `BraveKeyUnverified` · `BraveKeyUnproven` · `BraveKeyUnknown` · `NotInstalled` |
| *(mensagem)* | a mensagem do surf **verbatim**, com o "Fix:" do caso — nunca uma chave (tokens com cara de chave saem mascarados). Fica salva em `$DO_STATE/surf-gate.last` |

O portão antigo (`surf doctor` com a saída em `/dev/null` + `echo $?`) jogava
fora a mensagem que o usuário precisa ler e era fail-open no exit 1 — montar o
portão à mão é proibido.

**Códigos de saída dos binários surf** (o orquestrador e todo sub-agente
ramificam neles — depois de **classificar**):

| Código | Significado | Ação |
|---|---|---|
| 0 | funcionou | cite as URLs que o surf devolveu |
| 1 | terminou com **0 fontes** — duas causas opostas que o exit code não separa | **classifique**: `EMPTY` = a busca funcionou e não achou nada → registre o vazio, marque o fato como NÃO VERIFICADO ("busca vazia") e siga, **sem** trocar de ferramenta; `FAILED_QUOTA` / `FAILED_OTHER` = a pesquisa **não funcionou** (cota, 429, billing, todas as chaves esgotadas) → protocolo PESQUISA-FALHOU |
| 2 | o comando está errado | corrija o comando — nunca vira pergunta ao usuário |
| **78** | **sem chave Brave válida** (`EX_CONFIG`) | É configuração, não pesquisa: retentar não conserta e não há de onde mais buscar. Sub-agente: **para de pesquisar**, termina só o que não depende do fato e reporta `SEARCH_STATUS: BLOCKED_78`. Orquestrador: **protocolo PESQUISA-FALHOU** |
| 143 | o harness matou por timeout | refaça com `surf-search-normal`, que se auto-orça — nunca vira pergunta ao usuário |

Cota esgotada, 429 e 402 **não** viram 78 no surf: saem **1**, iguais a uma
busca vazia. Por isso toda chamada surf redireciona stdout e stderr para
arquivo e é classificada por
`surf-gate.sh classify <exit> <stdout-file> <stderr-file>`, que imprime **um**
de `OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78 | KILLED_143 |
USAGE_2`. Os padrões são **ancorados** na saída do surf — uma pergunta que
contenha "429" ou "quota" não vira `FAILED_QUOTA`.

#### Quando a pesquisa falha — o protocolo PESQUISA-FALHOU

Chave, cota e instalação são **configuração do ambiente do usuário**, não
ambiguidade da tarefa — então o orquestrador **nunca decide sozinho** que a
pesquisa exigida é dispensável. O protocolo é **incondicional**: vale com ou
sem `do-question` e vence "não me pergunte nada", "autônomo", "toca o barco",
`no-stop` e `plan=off`.

Como ele sabe que a pesquisa era **exigida**: na FASE 2 cada sub-tarefa recebe
`SEARCH_REQUIRED=sim|nao` por critério objetivo (API/lib/serviço externo ao
repo, "mais recente/atual/docs/compare/escolha", dependência nova, migração de
versão — **na dúvida, sim**), e todo handoff de sub-agente abre com a seção
`## SEARCH_STATUS` (`NOT_NEEDED | OK | EMPTY | FAILED_QUOTA | FAILED_OTHER |
BLOCKED_78`).

| Gatilho | Quando |
|---|---|
| **g1** | o portão devolveu `SURF_GATE != 0` **e** existe sub-tarefa pendente com `SEARCH_REQUIRED=sim` (PORTÃO PÓS-PLANO da FASE 2; passo 0 de cada onda) |
| **g2** | um handoff voltou com `SEARCH_STATUS` `BLOCKED_78`, `FAILED_QUOTA` ou `FAILED_OTHER` — ou **sem** a seção, numa sub-tarefa que exigia pesquisa (TRIAGEM DE PESQUISA, FASE 3 passo 4.5) |
| **g3** | 2 ou mais handoffs `EMPTY` na mesma onda → `surf-gate.sh resume --probe` (uma busca real barata, **1 crédito** — a sonda grátis não enxerga cota); só pausa se continuar bloqueado |

`BraveKeyCooling` (cooldown de 60 s) não vira pergunta de cara: o orquestrador
segue com o trabalho que não pesquisa e reroda o portão até 3 vezes, sem
`sleep`; persistiu → pergunta.

O que acontece: (A) nenhum pesquisador novo é disparado; as sub-tarefas **não**
bloqueadas são revisadas, integradas e **limpas** normalmente — nunca se
atravessa um fim de turno com filha integrada por limpar —, e as bloqueadas
ficam `ACTIVE`, **sem** merge; (B) o portão roda de novo, visível; (C)
`surf-gate.sh pause <onda> "<sub-tarefas>" "<motivo>"` grava
`$DO_STATE/search-pause.md`; (D) a pergunta sai em **texto**, como a última
coisa da resposta, e o turno **encerra**:

```
===== PESQUISA-FALHOU — a pesquisa exigida não pôde ser feita; a decisão é SUA =====
...
Responda com o NÚMERO da opção:
  [1] Adicionei/troquei a chave Brave — tente de novo  (`surf-research-skill keys add --provider brave <CHAVE>` | terminal separado: `surf add`)
  [2] Ajustei o plano/cota ou esperei o cooldown — tente de novo  (`surf-research-skill keys reset --provider brave` limpa burn/cooldown em cache)
  [3] Seguir SEM pesquisa — premissas ficam marcadas NÃO VERIFICADAS no plano, handoffs e relatório
  [4] Abortar — fecho o que está aberto (purge) e entrego relatório parcial
```

Rode os comandos de chave **no seu terminal** e **não cole a chave no chat**
(iria para o transcript). Na mensagem seguinte, o passo 0 da FASE 0 acha o
`search-pause.md` e retoma: **[1]/[2]** → `surf-gate.sh resume --probe`;
`RESUME=OK` re-delega só as bloqueadas, **na mesma worktree**;
`RESUME=STILL_BLOCKED` repete a pergunta, sem limite de rodadas — quem decide
sair por [3] ou [4] é você. **[3]** → as bloqueadas são re-delegadas com
"NÃO PESQUISE", e toda premissa externa sai marcada NÃO VERIFICADA na seção
**Pesquisa** do relatório final. **[4]** → `purge` (os branches ficam
arquivados) e relatório parcial.

**`--sub-agents` é o único botão de simultaneidade, e ele SOMA com
`DO_MAX_PARALLEL`.** Seja `N` o teto global (`surf-sub-agents=N` na invocação,
default 10, faixa 1..20) e `R` a quantidade de sub-agentes da onda que
pesquisam: cada um recebe `--sub-agents=max(1, floor(N / R))`, de modo que a
soma da onda nunca passa de `N`. Se multiplicassem, uma onda cheia seria
`50 × 10 = 500` buscas simultâneas contra um plano Brave que pode servir uma
por segundo. `R` é a contagem de sub-tarefas `SEARCH_REQUIRED=sim` da onda; com
`R = 0` ninguém pesquisa (não há `floor(N/0)`). O `N` é validado e gravado no
ENV_FILE pelo `do-context.sh` (`DO_SURF_SUB_AGENTS`; fora de 1..20 = exit 2).

**É proibido envolver o surf em `sleep`, jitter, backoff ou retry.** Ele
aprende o requests-per-second real do plano Brave nos headers da resposta e o
aplica num token bucket **cross-process**, compartilhado por todos os processos
surf da máquina. Um ritmo por cima briga com o limitador e provoca exatamente
o 429 que ele evita.

**WebSearch/WebFetch do harness não descobrem fontes.** Fonte que não veio pelo
surf não pode ser citada em handoff nem em deliverable. Uso legítimo, único:
abrir com `Read`/`WebFetch` uma URL **que o surf já devolveu** — é a única
forma de ler o corpo de uma página, já que a Brave devolve título, URL e
trecho, e os verbos `extract`/`crawl`/`map` foram removidos no surf v8.

**Histórico:** o surf foi o provedor original (v3.0.0), foi substituído por uma
busca Brave interna, voltou como Tier 1 na v3.3.0, e na v4.0.0 virou a
dependência única — os Tiers 2 (Brave direto) e 3 (DDG keyless) desta skill
foram removidos. O gatilho está registrado no D23: `search.sh` tratava todo
exit code não-zero do surf como falha transitória, então o `exit 78` da v8
ficava indistinguível de um timeout e o wrapper respondia a mesma pergunta pelo
DuckDuckGo — reproduzindo, uma camada acima, o defeito que o surf acabara de
eliminar. Na v4.1.0 o portão deixou de ser o `surf doctor` montado à mão e
virou `scripts/surf-gate.sh` (fail-closed), e o `exit 78` deixou de ser uma
parada muda: virou a pergunta do protocolo PESQUISA-FALHOU.

### Sub-agentes no Claude Code — nativos, nenhum plugin necessário

**Resposta curta da pesquisa profunda (25 claims verificadas adversarialmente contra as docs oficiais, 0 refutadas, 2026-08-18): o Claude Code já tem sub-agentes nativos. Não existe plugin a instalar para isso — e não há nada para abrir em outro terminal.** Plugins são um canal **opcional** de distribuição, não um requisito.

- **O que são**: arquivos Markdown com frontmatter YAML em `.claude/agents/` (projeto) ou `~/.claude/agents/` (usuário — vale em todos os projetos, sem configuração extra). O frontmatter define `name`, `description`, `tools`, `model`, `permissionMode`, `skills`, `memory`, `background`, `isolation`; o corpo do arquivo vira o system prompt.
- **Como são disparados**: pela ferramenta **Agent** (renomeada da Task na v2.1.63; `Task(...)` continua como alias), que roda o sub-agente em contexto próprio — em paralelo ou em background — e devolve um único resultado ao pai. Sub-agentes começam com **contexto zero**: prompts precisam ser autocontidos (é exatamente o que o template de delegação do SKILL.md faz).
- **Tipos embutidos**: `Explore` (busca/análise read-only; pula CLAUDE.md e o git status do pai por velocidade), `Plan`, `general-purpose`, `claude`, `statusline-setup`, `claude-code-guide`. É o `general-purpose` que o orquestrador usa nas ondas.
- **Paralelismo**: nativo, com teto de **20 sub-agentes concorrentes por sessão** (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, v2.1.217+) e até 3 níveis de profundidade de spawn — o teto efetivo das ondas do orquestrador é `min(DO_MAX_PARALLEL, 20)`: o default do DO_MAX_PARALLEL virou **50**, mas o harness impõe 20 concorrentes reais por sessão (filas do resto), então na prática as ondas raramente passam de ~20 em voo.
- **Terminal novo**: agentes de usuário em `~/.claude/agents/` persistem em todos os projetos. Prioridade de resolução de nomes: managed settings (org) > flag `--agents` (JSON, vale só na sessão) > `.claude/agents/` (projeto) > `~/.claude/agents/` (usuário) > `agents/` de plugins. Desde a v2.1.198 o `/agents` não abre mais wizard — imprime onde editar os arquivos.
- **Plugins (aditivos, opcionais)**: o sistema `/plugin` empacota skills, hooks, MCP e **também agentes prontos** (pasta `agents/` do plugin; invocados por @-mention escopado `plugin:agente`). Marketplaces: o oficial `anthropics/claude-plugins-official` (adicionado automaticamente na primeira execução; ex.: `pr-review-toolkit`, com 6 agentes de revisão de PR) e o comunitário `anthropics/claude-plugins-community` (com triagem de segurança da Anthropic — que **só** vale para ele: plugins de URLs git arbitrárias ou diretórios locais não passam por triagem). Coleções grandes de terceiros existem (ex.: `wshobson/agents`, 200+ agentes) — **nenhuma é necessária** para o que este projeto faz.
- **Equipes nativas** (`agent teams`): existem no harness, mas são **experimentais e desabilitadas por padrão** — o sistema de ondas com worktrees do deep-orchestrator-agent-skill segue sendo a abordagem de produção.
- **Nota**: o harness também tem `claude --worktree <nome>` para sessões paralelas isoladas; o deep-orchestrator-agent-skill mantém o sistema próprio (R6/R8, `do-wt.sh`) porque precisa de nomes, branches e limpeza controlados por registro (`owned.tsv`) — isolamento real por worktree, não apenas por sessão.

Fontes primárias: [subagents](https://code.claude.com/docs/en/subagents) · [agents — run in parallel](https://code.claude.com/docs/en/agents) · [discover-plugins](https://code.claude.com/docs/en/discover-plugins) · [claude-plugins-official](https://github.com/anthropics/claude-plugins-official) · [claude-plugins-community](https://github.com/anthropics/claude-plugins-community). Fatos version-sensitive (v2.1.63 / v2.1.186 / v2.1.198 / v2.1.217+) devem ser conferidos contra a versão do Claude Code instalada.

## Estrutura da casa da skill (`$SKILL_HOME`)

```
deep-orchestrator-agent-skill/
├── README.md                    # Este arquivo
├── SKILL.md                     # Definição do skill (frontmatter YAML + XML do orquestrador; a versão vive em metadata.version) — symlink para .claude/skills/deep-orchestrator-agent-skill/SKILL.md
├── scripts/
│   ├── README.md                # Índice de todos os scripts
│   ├── do-context.sh            # FASE 0 — valida as flags (--flags='…'), delimita a raiz-de-mundo e grava o estado
│   ├── do-wt.sh                 # ciclo de vida das worktrees-filhas: integrate/gate/finish/close, portão inter-onda (assert-clean), ledger, purge (guardas de contenção)
│   ├── surf-gate.sh             # portão FAIL-CLOSED da surf + protocolo PESQUISA-FALHOU (gate/classify/pause/resume) — v4.1.0
│   ├── evolve-skill.sh          # evolução do CORPO da skill: search (prefs+prompts)/diff/apply (branch evolve/*, nunca merge sozinho)/status
│   ├── do-prefs.sh              # motor de prefs: .deep-orchestrator-preferences/ do projeto e da skill (load/add-project/add-global/pending/ensure-gitignore/status)
│   ├── evolution-survey.sh      # PERGUNTA de evolução em texto no terminal (ask/answer/apply/dismiss — v3.9.0, sem Plannotator)
│   ├── lib/evolve-common.sh     # parsers/validadores compartilhados do formato de bloco
│   ├── lib/plannotator-common.sh # contrato do Plannotator compartilhado (plan-approval.sh — o portão de plano continua no Plannotator)
│   ├── check-install.sh         # prova de instalação completa
│   ├── check-plannotator.sh     # FASE 2.5 — resolve/instala o Plannotator (exit 0/1/2)
│   ├── plan-approval.sh         # FASE 2.5 — uma rodada de aprovação no Plannotator
│   ├── test-contencao.sh        # MODO CONTIDO + fechamento por tarefa (309 asserções, A1–A56)
│   ├── test-flags.sh            # flags da FASE 0: --flags, apelidos, anti-stale, DO_ORPHAN_RUNS, wt=, --boundary (307 asserções, FL1–FL16) — v4.1.0
│   ├── test-surf-gate.sh        # portão da surf, classify, pause/resume, orçamento --sub-agents, choose (228 asserções, G0–G12, mockado)
│   ├── test-evolve.sh           # motor de prefs/pergunta de evolução (81 asserções, F1–F14 · S1–S10 · E1–E6)
│   └── test-plan-approval.sh    # portão de aprovação do plano (139 asserções, mockado)
├── prompts/
│   ├── ecc-prompts.md           # 7 templates de prompt portados do ECC
│   ├── ecc-skills.md            # 7 skills ECC portados
│   ├── search-prompts.md        # Prompts de busca otimizados para dev
│   ├── plan-approval-prompts.md # Templates da FASE 2.5 (documento, feedback, regeração)
│   └── evolution-guide.md       # Framework de decisão da evolução (o que qualifica, project vs global)
```

As cinco suítes rodam sem rede, sem navegador e sem gastar crédito de busca
(tudo mockado ou em repositórios descartáveis de `mktemp -d`), e estão verdes
no macOS (bash 3.2.57, BSD sed/wc, sem `flock`): `for t in scripts/test-*.sh; do bash "$t"; done`.

## Requisitos

- Claude Code (CLI)
- Git
- **Node.js ≥ 18 + npm** — para instalar a surf-agent-skill
- **surf-agent-skill v9+** — **OBRIGATÓRIA** sempre que a tarefa exigir pesquisa (a v9 é a primeira que traz o verbo `surf-research-skill gate`, em que o portão desta skill se apoia): `npm i -g surf-agent-skill`, depois `surf` para adicionar a chave. Sem ela, o orquestrador **pausa e pergunta** (nunca instala sozinho: `npm -g` é vedado pela regra R9)
- **Chave Brave Search** — **OBRIGATÓRIA** (https://api-dashboard.search.brave.com). Não há tier sem chave: sem ela todo comando `surf` sai **78**, e o orquestrador pausa e pede a você que troque/ajuste a chave — ou que autorize seguir sem pesquisa (protocolo PESQUISA-FALHOU). Validá-la é **grátis** e o surf faz isso sozinho a cada invocação (veredito em cache por 7 dias). Uma **segunda** chave não é redundância — cada uma carrega o próprio orçamento de requisições por segundo, então duas dobram o paralelismo real
- **Chave OpenRouter** — *recomendada* (`surf-research-skill ai-setup`): sem ela o surf ainda faz buscas reais, mas devolve evidência crua em vez de síntese
- `curl` (instalação automática do Plannotator, em `check-plannotator.sh`) e `jq` **ou** `python3` (leitura do envelope JSON em `plan-approval.sh` e `evolution-survey.sh`). Os scripts de busca que os usavam foram removidos na v4.0.0
- **bash ≥ 3.2** — os scripts rodam no bash de fábrica do macOS (3.2.57), com BSD sed/wc e **sem** `flock(1)` (o lock do ledger cai para `mkdir` atômico)
- `project-router` skill resolvido a partir da raiz-de-mundo (`<raiz>/.claude/skills/project-router/` ou `<raiz>/.agents/skills/project-router/`). Ausente, o sub-agente registra no handoff e segue — não cai para o repositório principal nem para `~/.claude`
- **Plannotator** — **AUTO-INSTALADO** se ausente (`scripts/check-plannotator.sh --install`; binário `--minimal` em `~/.local/bin`, mínimo 0.19.1). Usado pela UI de anotação do EXPLAINER final (opcional — o arquivo é a entrega) e pelo PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5). Verificado na v3.6.0 em 0.27.6.

### Dependências

Uma worktree recém-criada **não** herda `node_modules`, `.venv` ou `target`: são untracked e `git worktree add` não os copia. Se a sub-tarefa precisar deles, o sub-agente instala **dentro da worktree** (cwd na raiz da filha), em modo congelado (`npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, …), com `HUSKY=0`, nunca com flags globais e nunca no projeto principal. O cache global do usuário (`~/.npm`, `~/.cache/uv`, `~/.cargo`, `~/.m2`) é permitido e desejável: é conteúdo endereçado por hash, compartilhado pela máquina, e redirecioná-lo só forçaria re-download por agente. Com `only-e2e`, entram na mesma lista os caches de browser dos runners (`~/Library/Caches/ms-playwright`, `~/.cache/ms-playwright`, `~/.cache/Cypress`) — o runner em si é devDependency local, nunca `-g`, e `npx playwright install` roda **sem** `--with-deps`.

## Instalação (passo a passo)

O contrato está em [Instalação (o contrato)](#instalação-o-contrato), no topo: **symlink para a raiz do repo, nunca cópia** — uma cópia congela a versão do dia (um `git pull` não chega nela), e o `SKILL.md` da raiz é um symlink relativo, que copiado para outro diretório vira link quebrado.

```bash
# 1. Clone o repositório (a casa da skill, $SKILL_HOME, é a RAIZ dele)
git clone <repo-url> ~/Projects/deep-orchestrator-agent-skill

# 2. UM symlink onde o SEU harness descobre skills, apontando para a RAIZ do
#    repo (ex. Claude Code: ~/.claude/skills; confira a doc do seu harness)
ln -s ~/Projects/deep-orchestrator-agent-skill ~/.claude/skills/deep-orchestrator-agent-skill

# 3. Prove que a instalação está completa (exit 0 = completa)
~/Projects/deep-orchestrator-agent-skill/scripts/check-install.sh --root ~/.claude/skills/deep-orchestrator-agent-skill

# Este bloco é setup MANUAL do usuário, executado UMA VEZ, fora de qualquer
# execução da skill — NUNCA por um sub-agente. A skill não se auto-instala no
# repositório-alvo: ela é lida de $SKILL_HOME.

# OBRIGATÓRIO se a tarefa exigir pesquisa — a skill não tem busca própria:
npm i -g surf-agent-skill
surf                                  # interativo (exige TTY): chave Brave (validação grátis)
# …ou, não-interativo:
surf-research-skill keys add --provider brave <CHAVE>   # valida ao vivo, grátis; aceita --stdin
export BRAVE_API_KEY=<chave>          # https://api-dashboard.search.brave.com
export OPENROUTER_API_KEY=<chave>     # recomendada: liga a síntese do surf-ai
```

Chave queimada, em cooldown ou com a cota esgotada no meio de uma execução? O orquestrador pausa e pergunta — ver [Quando a pesquisa falha](#quando-a-pesquisa-falha--o-protocolo-pesquisa-falhou).

## Uso

```
/deep-orchestrator-agent-skill <descrição da tarefa>
/deep-orchestrator-agent-skill plan=on <descrição da tarefa>            # prefixo OPCIONAL — força o portão de aprovação do plano
/deep-orchestrator-agent-skill plan=off faça um plano e execute         # prefixo OPCIONAL — força a autonomia total (sem portão)
/deep-orchestrator-agent-skill max-parallel=N <descrição da tarefa>     # prefixo OPCIONAL — cap de concorrência (default 50)
/deep-orchestrator-agent-skill surf-sub-agents=N <descrição da tarefa>  # prefixo OPCIONAL — teto global de buscas simultâneas do surf (1..20, default 10)
/deep-orchestrator-agent-skill wt=on <descrição da tarefa>              # prefixo OPCIONAL — worktree irmã nomeada como raiz-de-mundo
/deep-orchestrator-agent-skill wt=feature-x <descrição da tarefa>       # prefixo OPCIONAL — com nome explícito (mesmo nome = reentra)
/deep-orchestrator-agent-skill no-stop <descrição da tarefa>            # prefixo OPCIONAL — remove o teto de 10 ondas
/deep-orchestrator-agent-skill no-evolve <descrição da tarefa>          # prefixo OPCIONAL — pula a pergunta de evolução e a análise
/deep-orchestrator-agent-skill no-test <descrição da tarefa>            # prefixo OPCIONAL — NÃO cria testes (o gate e a suíte existente continuam rodando)
/deep-orchestrator-agent-skill only-e2e <descrição da tarefa>           # prefixo OPCIONAL — cria APENAS testes end-to-end, por jornada
/deep-orchestrator-agent-skill do-question <descrição da tarefa>        # prefixo OPCIONAL — autoriza o orquestrador a perguntar as dúvidas reais
/deep-orchestrator-agent-skill max-parallel=8 no-test plan=off <tarefa> # os prefixos combinam, em qualquer ordem, ANTES da tarefa
```

**Zona de prefixo (v4.1.0).** Flags são os tokens **iniciais** da invocação que têm cara de flag (`chave=valor`, ou `no-…` / `only-…` / `do-…`), até o primeiro token que não tenha — o resto é o texto da tarefa. O orquestrador **não julga** os tokens: repassa todos, num argumento só, para `do-context.sh --flags='<tokens>'`, e o **script é o único validador**. Consequências práticas:

- typo não vira texto da tarefa: `no-tests`, `e2e-only`, `mp=8`, `ask` saem **exit 2** com a sugestão ("quis dizer `no-test`?") — antes, a flag errada era engolida e o pedido se invertia em silêncio;
- token igual **no meio** da frase é texto ("adicione uma flag no-test ao CLI" não liga `no-test`), e flag **nunca** é inferida por linguagem natural — a única decisão por linguagem natural é o portão do plano;
- a tarefa começa com algo que parece flag (`no-reply …`)? Separe com `--`: `/deep-orchestrator-agent-skill no-test -- no-reply vira o remetente padrão`;
- `no-test` + `only-e2e` juntos → exit 2 ("mutuamente exclusivos"); o mesmo para `plan=on` + `plan=off`;
- a flag **vence** a variável de ambiente equivalente (`DO_TEST_MODE`, `DO_QUESTION`, `DO_NO_STOP`, …), que continua valendo como fallback;
- o resumo da FASE 0 imprime o que ficou valendo (`TEST_MODE = none`, `QUESTION = 1`, `NO_STOP       = ON`, `WT_ROOT = ON (<nome>)`, …) e o orquestrador o confere contra o digitado; retomar uma execução pendente com `TEST_MODE` ou `QUESTION` diferente cria uma execução **nova** (anti-stale) em vez de inverter a flag.

O prefixo `wt=` (WT-ROOT; chegou junto com a v3.5.0 — a regra de fim R8j e a reentrada são da v4.1.0) cria — ou reentra — uma worktree **irmã verdadeira** do projeto em `<pai>/<repo>.worktrees/<nome>` e faz **todo** o trabalho **dentro dela**, preservando o checkout principal intacto. O fluxo:

1. A pasta irmã `<pai>/<repo>.worktrees/` é criada se faltar, ou reusada se já existir (nunca recriada).
2. O nome do diretório da worktree é o `<nome>` passado (`wt=feature-x`), ou um slug derivado do prompt da tarefa se você usar `wt=on` sem valor (é o orquestrador que troca `wt=on` pelo slug — o script recusa `wt=on` cru). **Mesmo nome = mesma worktree**: se `<repo>.worktrees/<nome>` já é a worktree deste repo no branch `do/wt/<nome>`, a FASE 0 **reentra** nela (`DO_WT_ROOT: REENTRANDO …`) e uma execução pendente lá dentro é retomada. O nome só é **deduplicado** (`-2`, `-3`, …) quando o path existe e **não** é isso — um diretório qualquer, ou uma worktree em outro branch.
3. A `FASE 0` **re-executa com o cwd dentro da worktree**: o resto é o MODO CONTIDO já existente — ondas, sub-agentes, merges via squash, gates, subwaves de teste/validação e o COMMIT-FINAL aterrissam **lá dentro**, e o checkout principal é `$MAIN_ROOT`, zona proibida.
4. **Fim com wt= (R8j):** o COMMIT-FINAL é **apenas commit + push no branch do próprio wt** (`do/wt/<nome>`). É **proibido** mergear esse branch de volta para o branch de origem (main/master), fazer fast-forward/rebase nele, abrir PR ou pushar qualquer outro branch — a integração do wt no branch principal é decisão **exclusiva do usuário**, feita quando ele quiser.
5. **Purge final:** em toda execução (com ou sem `wt=`), o fim roda `do-wt.sh purge` — a **rede de segurança**, não mais o mecanismo principal: desde a v4.1.0 cada tarefa já foi limpa no gate verde dela. O purge fecha TODAS as linhas ainda abertas do ledger — inclusive worktrees kind=test/validation, snapshots `int-*` e linhas BLOCKED/ORPHANED —: as integradas por `finish --gate-ok`, o resto por `close --discard "purge"`, sempre salvando restos não commitados e arquivando cada branch em `refs/do-archive/$RUN_ID/` antes de apagá-lo. Só imprime `PURGE OK` se o ledger **e a realidade** (diretórios em `$CHILD_ROOT`, refs em `$BRANCH_NS/`) fecharam. **rc 1** = alguma remoção falhou (conserte e rode de novo); **rc 3** = limpou tudo, **mas** houve filha nunca integrada ou integrada só em parte (`MERGED-PARTIAL`) — o bloco `PURGE: NUNCA INTEGRADAS / PARCIAIS` vai literal para a seção "Não integrado" do relatório, e o título vira "Tarefa concluída PARCIALMENTE" (rodar o purge de novo não "conserta" o rc 3). Zero worktrees/branches de sub-agente sobrevivem; a única exceção é a própria worktree wt-root, persistente por design. Nada se perde: `git branch resgate/<nome> refs/do-archive/<RUN_ID>/<nome>` traz de volta qualquer branch arquivado.

A worktree irmã é **persistente** (ao contrário das worktrees-filhas, que morrem no gate verde da própria tarefa): o branch `do/wt/<nome>` é reusado entre execuções. Variáveis gravadas no ENV_FILE: `DO_WT_ROOT` (`1` quando a raiz-de-mundo **é** um wt-root — derivado do fato, não da flag) e `DO_WT_NAME` (o nome resolvido); `DO_WT_ROOT_ENTERED` é o sentinel interno de re-entrada. Com `wt=`, o estado da execução vive **dentro** da worktree irmã (`<repo>.worktrees/<nome>/.deep-orchestrator/`).

O prefixo `max-parallel=N` (antigo `mp=N` — o nome antigo sai exit 2 com a sugestão) define o cap de concorrência (F3-02): vira `DO_MAX_PARALLEL=N` no ENV_FILE (validado pelo `do-context.sh` como inteiro positivo; inválido → exit 2 com mensagem clara). Ausente → default **50**. O teto vale para TUDO em voo — features da onda, worktrees de teste/validação das subwaves (incluindo as até 3 worktrees de teste por onda — que não existem com `no-test`), revisores e REVISOR DE PLANO. Ondas com mais features que o cap viram batches sequenciais, cada batch com a sua barreira. Nota: o harness do Claude Code impõe um teto próprio de ~20 sub-agentes concorrentes por sessão (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), então com `max-parallel=` acima de 20 a concorrência real fica limitada pelo harness (o resto espera em fila) — o `max-parallel=` continua servindo para dimensionar as ondas/batches.

O prefixo `surf-sub-agents=N` define o **teto global de buscas simultâneas do surf** nesta execução (`DO_SURF_SUB_AGENTS`; inteiro de 1 a 20 — o próprio surf rejeita fora disso —, default **10**; inválido → exit 2). Ele **não** é multiplicado por `max-parallel`: é **dividido** entre as sub-tarefas da onda que pesquisam — cada uma recebe `--sub-agents=max(1, floor(N / R))` (ver [Pesquisa](#pesquisa--surf-agent-skill-v8-dependência-dura)). Baixe-o se o seu plano Brave serve poucas requisições por segundo.

O prefixo `no-stop` (booleano, sem valor) remove o **teto de 10 ondas por execução**: vira `DO_NO_STOP=1` no ENV_FILE (a variável de ambiente aceita 0/1/on/off/yes/no/true/false; inválido → exit 2 com mensagem clara). Ausente → default `0`, que preserva o comportamento histórico (máximo de 10 ondas). Com `no-stop`, a execução dura **quantas ondas forem necessárias** até o REVISOR DE PLANO declarar convergência — ideal para tarefas que exigem qualidade máxima sem teto arbitrário de rodadas. A válvula anti-loop **permanece ativa** mesmo com `no-stop`: 2 REPLANs consecutivos sem novas sub-tarefas aceitas forçam a convergência (documentada no relatório final), garantindo que a execução nunca itere para sempre sem progresso.

O prefixo `no-evolve` (booleano) pula o passo de evolução inteiro (`DO_EVOLUTION_SURVEY=0`): o agente que lê o histórico da execução não é disparado, a pergunta não é feita e nada é aplicado. Ausente → a pergunta de evolução **sempre** aparece ao fim, mesmo com "não me pergunte nada".

O prefixo `no-test` (booleano; `DO_TEST_MODE=none`) faz a execução **não criar testes**: nenhuma sub-tarefa de teste no plano, Testing Subwave desligada (o handoff registra "Onda N: Testing Subwave DESLIGADA (no-test)") e o `do-wt.sh new` **recusa** worktree de teste (`RECUSADO: TEST_MODE=none`) — a regra está no script, não na memória do LLM. **Não criar ≠ não rodar**: o gate continua rodando a suíte **existente** (`GATE_TEST`) e a Validation Subwave continua. Os sub-agentes de feature rodam a suíte antes e depois, e **podem** ajustar um teste existente quebrado por mudança **intencional** de contrato (registrando no handoff); os revisores não tratam "faltou teste" como achado, e o REVISOR DE PLANO é proibido de propor sub-tarefa de teste. Exceção: teste pedido **explicitamente** no texto da tarefa é entregável de feature. O relatório final sai com "Testes: DESLIGADOS por no-test — 0 testes novos; gate rodou a suíte existente".

O prefixo `only-e2e` (booleano; `DO_TEST_MODE=e2e`) faz as Testing Subwaves criarem **apenas testes end-to-end** — os que exercitam o sistema **pela mesma porta do usuário final** (UI no browser, HTTP contra o servidor de pé, binário CLI via processo, API pública importada como consumidor), sem mock interno nem import de módulo interno. Unit, integration e snapshot de componente **novos** são proibidos; cobertura por linha vira N/A e dá lugar à **cobertura de JORNADAS** (por jornada: ≥ 1 caminho feliz + ≥ 1 erro observável). A FASE 1 detecta o runner (Playwright, Cypress, script `test:e2e`, pytest `-m e2e`, supertest/httpx, bats…) e grava o comando com `do-wt.sh gate-set e2e`; sem runner, o plano ganha a sub-tarefa `onda1-e2e-harness`. A FASE 2 monta o **MAPA DE JORNADAS** (J1..Jn → onda em que a jornada **fecha** → path do spec), e só jornada fechada na onda ganha teste (worktrees `test-ondaN-e2e-<jornada>`; nenhuma fechou → "e2e adiado"). Cada contexto roda numa porta própria (`CI=1 E2E_PORT=<p>`), o servidor sobe **só** pelo ciclo de vida do runner (nada de `npm run dev &`), artefatos do runner ficam fora do commit e cada spec roda 2× (flaky → `fixme` + relato, nunca retry em laço). A suíte e2e roda na worktree do agente, no snapshot do **merge de teste** (`do-wt.sh gate <nome> --e2e`), na validação e no gate final — **não** nos snapshots de feature. Relatório: tabela "Testes e2e (only-e2e)" + "Jornadas sem cobertura". Mutuamente exclusivo com `no-test`.

Sem nenhuma das duas (`DO_TEST_MODE=full`, o default) vale o comportamento de sempre — Testing + Validation Subwaves —, com dois consertos da v4.1.0: é **proibido commitar teste falhando** (teste que revela bug vai como `skip`/`xfail`/`fixme` nomeando o bug + relato no handoff — senão o squash envenena os gates seguintes), e os bugs confirmados pelos agentes de teste da **última** onda entram no FIX-FINAL.

O prefixo `do-question` (booleano; `DO_QUESTION=1`, default `0`) **autoriza o orquestrador a perguntar** — sem ele, vale a autonomia: infere e documenta a premissa. A flag explícita **vence** gatilho de autonomia no texto da tarefa (mesmo precedente do `plan=on`). São só dois pontos: (i) a **RODADA DE DÚVIDAS** única ao fim da FASE 1, antes do plano — todas as dúvidas reais num bloco numerado, cada uma com opções a/b/c e um **default recomendado**; você responde `1:a 2:c`, ou `segue` para aceitar todos os defaults; (ii) durante a execução, no máximo **uma** rodada por onda, ao **fim** da onda (depois do portão inter-onda — nunca com filha integrada por limpar), só para decisão difícil de reverter ou dúvida que muda o escopo. Dúvida trivial continua sendo inferida: pergunta tem custo. Sub-agentes **nunca** perguntam — devolvem a seção `## Dúvidas para o usuário` no handoff e o orquestrador decide. O mecanismo é o mesmo de toda pergunta (texto, estado em `$DO_STATE/question/pendente.md`, fim de turno, retomada na mensagem seguinte), e o relatório ganha a seção "Perguntas ao usuário". **A pergunta da chave Brave não depende desta flag**: ela é incondicional.

### O portão de aprovação do plano

O prefixo `plan=on|off` liga ou desliga a FASE 2.5. Sem ele, a decisão vem dos gatilhos, nesta ordem (FASE 0, passo 2 — é a **única** flag que também se decide por linguagem natural; o resultado vira o token `plan=on|off` repassado ao script). Gatilho de autonomia desliga o **portão do plano** — não desliga a pergunta da chave Brave nem vence um `do-question` explícito:

| Precedência | Sinal | Resultado |
|---|---|---|
| 1 | prefixo `plan=on` / `plan=off` | vence tudo |
| 2 | `DO_PLAN_APPROVAL` no ambiente | respeitado |
| 3 | gatilho **negativo**: "não me pergunte nada", "autônomo", "toca o barco", "sem interrupção" | **OFF** (vence o positivo) |
| 4 | gatilho **positivo**: "faça um plano", "planeje", "quero aprovar antes", "revisar o plano", "plannotator" | **ON** |
| 5 | nada disso | **OFF** — o default |

Variáveis do portão (todas com default, validadas na FASE 0):

| Variável | Default | O que faz |
|---|---|---|
| `DO_PLAN_APPROVAL` | `0` | liga a FASE 2.5 |
| `DO_PLAN_MAX_REVISIONS` | `5` | teto de rodadas no Plannotator |
| `DO_PLAN_TIMEOUT` | `3600` | segundos de espera pela decisão, por rodada |
| `DO_PLAN_SHARE` | `0` | `1` permite o compartilhamento externo do Plannotator |
| `DO_PLANNOTATOR_BIN` | — | caminho explícito do executável |
| `DO_PLANNOTATOR_INSTALL` | `1` | `0` proíbe a instalação automática |
| `DO_PLAN_REMOTE` | `0` | `1` deixa o Plannotator escutar em `0.0.0.0` (revisão remota). Leia o aviso de segurança acima antes |

O trail de cada execução fica em `$DO_STATE/plan-approval/`: um snapshot imutável e um arquivo de feedback por rodada, mais o `trail.tsv`. Como `$DO_STATE` é apagado no fim, a tabela de revisões é copiada para o relatório final antes da limpeza.

Se o navegador não abrir sozinho, `plannotator sessions --open 1` reabre a sessão ativa.

Uma rodada interrompida (Ctrl-C, máquina suspensa, processo morto) **não trava o portão**: a numeração de revisões considera o que existe em disco, então a tentativa abortada fica preservada com o número dela e a próxima entra na seguinte. Se a rodada morreu depois de você decidir, a decisão está em `rev-NNN.stdout`.

### Triggers

O skill é ativado automaticamente com frases como (são as que a `description` do frontmatter anuncia):

- "orquestre isso"
- "divida essa tarefa"
- "resolva do início ao fim"
- "não me pergunte nada"
- "quero aprovar o plano antes"

Com a skill **já invocada**, estas frases no texto da tarefa decidem o portão de aprovação (FASE 2.5):

- ligam: "faça um plano", "planeje isso", "quero aprovar o plano antes", "revisar o plano", "plannotator"
- desligam (e vencem as de cima): "não me pergunte nada", "autônomo", "toca o barco", "sem interrupção"

"faça um plano" **sozinho** não ativa esta skill (é gatilho de skills de planejamento) — aqui ele só liga o portão de uma orquestração que você já pediu.

### Quando usar

Tarefas complexas que se beneficiam de decomposição em ondas paralelas — especialmente quando você quer uma solução completa do início ao fim sem interrupções. **Nunca use para tarefas triviais de um passo só.**

### Exemplo

```
/deep-orchestrator-agent-skill Adicionar endpoint de busca com cache a uma API REST
```

O orquestrador vai:

1. Analisar o repositório e identificar os subsistemas afetados (registrando antes o veredito do portão da surf — sem chave Brave válida **e** com sub-tarefa que exige pesquisa, ele pausa no PORTÃO PÓS-PLANO e pergunta a você, antes de criar qualquer worktree)
2. Criar um plano inicial com 2 ondas:
   - **Onda 1 (Fundação):** `onda1-cache-service` (CacheService genérico) + `onda1-schema-busca` (mapear schema de busca) — paralelo
   - **Onda 2 (Implementação):** `onda2-endpoint-busca` (endpoint com cache + testes)
3. Executar cada onda com barreira, triagem de pesquisa, recálculo dinâmico (REVISOR DE PLANO), revisão adversarial e, por tarefa, `integrate` + `gate` — cada worktree some no gate verde dela, e a onda seguinte só abre com o portão inter-onda verde. Ondas adicionais podem surgir se o revisor detectar novas sub-tarefas
4. Rodar o gate final, gerar o `EXPLAINER.html`, commitar, pushar, rodar o purge e entregar o relatório — com a seção "Não integrado" dizendo "nenhum" ou listando o que ficou de fora e por quê

Ao final, o histórico do **branch da raiz-de-mundo** (o branch da worktree em que a skill foi invocada; `main`/`master` apenas quando a invocação foi na árvore principal) terá 3 commits squash de feature — um por sub-agente —, um squash commit por worktree de teste das testing subwaves (até 3 por subwave; `test-onda1-*`, `test-onda2-*`), os fixes das validation subwaves (`val-ondaN-*`) e o commit final com o `EXPLAINER.html`. Com `no-test` não há squash de teste; com `only-e2e` eles se chamam `test-ondaN-e2e-<jornada>`. Nenhuma worktree-filha nem branch desta execução sobra — e nada some em silêncio: o que não foi integrado está no relatório, com o motivo e a ref em `refs/do-archive/<RUN_ID>/` de onde o branch pode ser resgatado. Worktrees e branches pré-existentes de outras sessões não são tocados.

## Versão

**4.1.0** — **limpeza por tarefa pelo script, "nunca em silêncio" e a pergunta
da chave Brave** (MINOR; absorve o `fe3a1c2`, que mudara o contrato sem
versão). `do-wt.sh` ganha `integrate` / `gate-set` / `gate` / `finish` /
`close` / `assert-clean` / `ledger` / `checklist`: o gate verde chama `finish`
sozinho e a worktree morre **no gate verde da própria tarefa**; o fim de onda é
`sweep && assert-clean --wave <N+1>; verify` e o `new` recusa (rc 6) abrir onda
com sobra da anterior. Ledger `owned.tsv` de **11 colunas** (`parent`,
`outcome`); relatório com seção **"Não integrado"** obrigatória e título
"Tarefa concluída" | "Tarefa concluída PARCIALMENTE"; `purge` sai **rc 3** com
o bloco `PURGE: NUNCA INTEGRADAS`; squash vazio = rc 4; conflito detectado por
`git merge-tree` **sem sujar a raiz**; `DO_ORPHAN_RUNS` na FASE 0. Novo
`scripts/surf-gate.sh` (portão **fail-closed** `SURF_GATE`/`SURF_CODE`,
`classify`, `pause`, `resume --probe`) e o protocolo **PESQUISA-FALHOU**:
pesquisa exigida que falha (78, 127, cota/429) vira **pergunta em texto,
incondicional** — vence "não me pergunte nada", `no-stop` e `plan=off` —, com
`SEARCH_REQUIRED` no plano, `## SEARCH_STATUS` no handoff e a TRIAGEM DE
PESQUISA (FASE 3, passo 4.5). Flags novas **`no-test`**, **`only-e2e`**
(`DO_TEST_MODE=full|none|e2e`) e **`do-question`** (`DO_QUESTION`); todas as
flags viajam por `do-context.sh --flags='…'` (o script é o único validador —
typo = exit 2 com sugestão); `surf-sub-agents` entra no ENV_FILE; `wt=<nome>`
repetido **reentra**. Portabilidade **macOS / bash 3.2** (lock `mkdir` sem
`flock`, BSD sed/wc). Estruturais: `description` ≤ 1024 caracteres, FASE 0
reordenada (passo 0 ESTADOS PENDENTES), "AGUARDE" com definição única. Suítes:
contenção **309**, flags **307** (nova), surf-gate **228**, plan-approval
**139**, evolve **81** — 1064 asserções, todas verdes. O SKILL.md foi
condensado (304k → 215k caracteres) após a revisão adversarial da rodada final. Decisões **D24–D31** em
`docs/decisions/2026-09-20-limpeza-por-tarefa-pergunta-pesquisa-flags.md`.

**4.0.0** — **fim do sistema de busca interno.** `search.sh`,
`search-parallel.sh`, `check-search-credits.sh`, `brave-search.sh`,
`check-brave-credits.sh` e `test-search.sh` REMOVIDOS (3.346 linhas). A
pesquisa é 100% **surf-agent-skill v9+** — dependência obrigatória
(`npm i -g surf-agent-skill`), Brave como único backend, sem tier sem chave e
sem provedor de reserva. **`exit 78` = configuração** (sem chave Brave válida):
o orquestrador PARA, informa e aguarda; retentar não conserta. Portão passa a
ser `surf doctor`, na FASE 0 e no passo 0 de cada onda (na v4.1.0: o portão
virou `scripts/surf-gate.sh` e o 78 virou a pergunta do PESQUISA-FALHOU). **`--sub-agents` é o
único teto de simultaneidade do surf e SOMA com `DO_MAX_PARALLEL`**: cada
sub-agente que pesquisa recebe `max(1, floor(N/R))`, prefixo `surf-sub-agents=N`
na invocação (default 10, faixa 1..20). É proibido envolver o surf em
jitter/backoff — ele já ritma pelo plano Brave, cross-process. WebSearch e
WebFetch deixam de descobrir fontes (só abrem URL que o surf devolveu). Nova
suíte `test-surf-gate.sh` (46 asserções) substitui `test-search.sh`. Decisão
**D23** em `docs/decisions/2026-08-29-surf-agent-skill-obrigatorio.md`.

**3.9.0** — evolução como **PERGUNTA EM TEXTO no terminal** (fim do questionário Plannotator): depois de TUDO (commit, push, relatório) cada proposta vem numerada com opções a/b/c + escopo 1/2 (ex.: "1:b2"); o usuário responde com códigos na próxima mensagem e a opção escolhida vira a ação salva (`evolution-survey.sh` ask/answer/apply/dismiss); flag **`no-evolve`** pula a pergunta e o agente de análise; **push** explícito no COMMIT-FINAL (nunca bloqueia); prefixo `mp=N` → **`max-parallel=N`**; continuação da pergunta pendente na FASE 0 (passo 0.4 — desde a v4.1.0, o passo 0 ESTADOS PENDENTES); testes S1–S10 reescritos (78 PASS). Decisões D18–D22 em `docs/decisions/2026-08-28-pergunta-evolucao-terminal.md`.

**3.8.0** — questionário de evolução pós-execução (substituído pela v3.9.0): agente de evolução + prefs por projeto em `.deep-orchestrator-preferences/` (gitignored), `evolution-survey.sh` (round no Plannotator), `do-prefs.sh`, `evolve-skill.sh` sem `add`, decisões D12–D17.

**3.7.0** — auto-evolução contínua (substituída pela v3.8.0): `evolve-skill.sh add` + `LEARNINGS.md`.

**3.6.0** — HTML Explainer novo fluxo: fim do gerador/template antigos (scripts/generate-explainer.sh + templates/html-explainer.html removidos); geração delegada a sub-agente seguindo html-explainer-agent-skill + visual-explainer, sem limite de tempo, salvo em EXPLAINER.html no lugar; contrato de instalação (check-install.sh) atualizado.

**3.5.1** — bugfix do contrato de instalação: `.claude/skills/deep-orchestrator-agent-skill/` passa a espelhar `scripts/` e `prompts/` por symlink (qualquer alvo de instalação é uma casa válida); novo `scripts/check-install.sh`; candidato `~/.dsh/skills` na busca da FASE 0.

**3.5.0** — flag `no-stop` (DO_NO_STOP): remove o teto de 10 ondas por execução (ondas ilimitadas até a convergência); validação/export/resumo no `do-context.sh` + guarda anti-stale no caminho DO_REUSE; documentada no SKILL.md (frontmatter + FASE 0 + repeat + REPLAN + relatório) e no README. Na mesma versão chegou o prefixo `wt=<nome>` (WT-ROOT: worktree irmã persistente como raiz-de-mundo).

**3.4.0** — PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5, R10): plano aprovado no Plannotator, regerado a cada anotação num Plannotator novo; ligado só quando pedido (`plan=on|off` > env > gatilhos; default OFF); `check-plannotator.sh` (instalação `--minimal`), `plan-approval.sh` (decisão por exit code, título imutável, snapshots imutáveis) e `test-plan-approval.sh`.

**3.3.0** — sistema de busca 3-tier (search.sh + check-search-credits.sh + search-parallel.sh), subwaves duplas (TESTING + VALIDATION), gate em snapshot de integração (F3-01), DO_MAX_PARALLEL (F3-02), gate definido uma vez (F3-03), lockfile singleton (F3-04), tiering de modelos por papel (F3-09), correções críticas da Fase 1 (F1-01 a F1-04).

**3.2.0** — MODO CONTIDO (worktree como raiz-de-mundo), FASE 0 de bootstrap, guardas de contenção em `do-wt.sh`, regra de dependências (R9), testes de regressão.

**3.1.0** — Testing subwaves assíncronas, enforcement do project-router.

**3.0.0** — Brave Search interno, ondas ilimitadas, ECC prompts, verificação de créditos, HTML explainer.

## Licença

MIT
