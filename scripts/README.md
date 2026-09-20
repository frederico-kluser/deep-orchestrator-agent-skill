# Scripts -- deep-orchestrator-agent-skill

Diretorio de scripts executaveis do deep-orchestrator-agent-skill. Cada script tem uma funcao
especifica no ciclo de orquestracao. A ordem de execucao e ditada pelas FASES do
orquestrador (0 a 4), com `do-context.sh` sempre rodando primeiro.

---

## Core (orquestracao)

| Script | Proposito | FASE |
|---|---|---|
| `do-context.sh` | Resolve MODE (normal/contido), BASE_DIR, BASE_BRANCH, CHILD_ROOT, BRANCH_NS e grava o arquivo de estado (ENV_FILE) que TODO script posterior deve sourcear. Detecta se o cwd esta dentro de uma git worktree vinculada e delimita a RAIZ-DE-MUNDO. **FLAGS (v4.1.0): `--flags='<tokens separados por espaco>'`, UM argv so** -- o orquestrador repassa TODOS os tokens da zona de prefixo da invocacao e NAO julga; este script e o UNICO validador. Tabela flag -> variavel: `plan=on\|off` -> DO_PLAN_APPROVAL; `max-parallel=N` -> DO_MAX_PARALLEL (inteiro positivo, default 50); `surf-sub-agents=N` -> DO_SURF_SUB_AGENTS (1..20, default 10); `wt=<nome>` -> DO_WT_ROOT=1 + DO_WT_NAME; `no-stop` -> DO_NO_STOP=1; `no-evolve` -> DO_EVOLUTION_SURVEY=0; `no-test` -> DO_TEST_MODE=none; `only-e2e` -> DO_TEST_MODE=e2e; `do-question` -> DO_QUESTION=1. Flag VENCE a variavel de ambiente; token ausente -> a variavel de ambiente vale como fallback -> senao o default. `--flags=''` e a forma canonica sem flags; a forma em dois argv (`--flags <valor>`) e recusada; `--flags=` repetido = exit 2; um `--` literal dentro de --flags encerra a zona. **`--boundary='<token>'`** (UM argv): o PRIMEIRO token que encerrou a zona de prefixo -- o script normaliza (tira `-` iniciais, minusculas, `_`->`-`) e, se for flag mal escrita ou apelido (`e2e-only`, `--no-test`, `notest`), sai exit 2 com a forma certa; senao ignora (e texto da tarefa). **Exit 2, antes de criar qualquer coisa em disco**: token desconhecido (com sugestao deterministica para os apelidos: `no-tests`/`notest`/`skip-tests` -> `no-test`; `e2e-only`/`e2e` -> `only-e2e`; `mp=N` -> `max-parallel=N`; `ask`/`question`/`do-questions` -> `do-question`), `wt=on` cru (o orquestrador troca por `wt=<slug>` antes), `no-test` + `only-e2e` ("mutuamente exclusivos"), `plan=on` + `plan=off`, ou variavel invalida no ambiente (DO_TEST_MODE fora de full/none/e2e, DO_QUESTION fora de 0/1, DO_SURF_SUB_AGENTS fora de 1..20, DO_MAX_PARALLEL nao inteiro positivo, DO_NO_STOP/DO_PLAN_APPROVAL fora de 0/1/on/off/yes/no/true/false). **ENV_FILE grava E exporta**: alem das variaveis de fronteira, DO_WT, DO_SURF_GATE (= $SKILL_HOME/scripts/surf-gate.sh), DO_MAX_PARALLEL, DO_PLAN_APPROVAL / DO_PLAN_MAX_REVISIONS / DO_PLAN_TIMEOUT / PLAN_APPROVAL_DIR / PLAN_DOC / DO_PLAN_APPROVAL_SH (FASE 2.5), DO_NO_STOP, DO_EVOLUTION_SURVEY, DO_TEST_MODE, DO_QUESTION, DO_SURF_SUB_AGENTS, DO_WT_ROOT, DO_WT_NAME e os caminhos de prefs. O resumo impresso traz uma linha por flag (`TEST_MODE = full\|none\|e2e`, `QUESTION = 0\|1`, `SURF_SUB_AGENTS = N`, `WT_ROOT = ON (<nome>)\|OFF`, `NO_STOP = ...`, `PLAN_APPROVAL = ...`, `EVOLUTION = ...`) -- a FASE 0 do SKILL.md manda conferi-lo contra o que foi digitado. **Reuso e anti-stale**: execucao pendente na mesma raiz e REAPROVEITADA (`DO_REUSE`), salvo se PLAN_APPROVAL, NO_STOP, EVOLUTION_SURVEY, TEST_MODE ou QUESTION divergirem desta invocacao (`DO_STALE` -> execucao nova; chave ausente em env antigo = full / 0). Env de execucao anterior a v4.1.0 reaproveitado e COMPLETADO com as chaves que faltam (DO_TEST_MODE, DO_QUESTION, DO_SURF_SUB_AGENTS, DO_WT_ROOT, DO_WT_NAME, DO_SURF_GATE). **`DO_ORPHAN_RUNS:`** -- toda execucao anterior com linha viva no ledger que NAO sera reusada (DO_STALE, --new-run, so BLOCKED/ORPHANED, preterida) sai listada com `run=<id> vivas=<n> motivo=<...>` e o comando exato `( . '<env antigo>'; "$DO_WT" purge )`; o script NAO purga sozinho (pode ser sessao concorrente). Com `wt=` a partir do checkout principal, o inventario roda ANTES do re-exec. Cria o `owned.tsv` com cabecalho de 11 colunas; linhas vivas sao contadas por awk na coluna 9. **WT-ROOT (flag `wt=<nome>`):** quando o cwd e o checkout principal, cria -- ou REENTRA -- uma worktree IRMA VERDADEIRA do projeto em `<pai>/<repo>.worktrees/<nome>` e RE-EXECUTA este script com o cwd dentro dela, caindo em MODE=contido: TODO o trabalho (ondas, sub-agentes, merges, gates, COMMIT-FINAL) acontece dentro da worktree e o checkout principal fica INTOCADO. Mesmo nome = mesma worktree: se o path ja e worktree DESTE repo no branch `do/wt/<nome>`, REENTRA (`DO_WT_ROOT: REENTRANDO ...`); so deduplica (-2, -3...) quando o path existe e NAO e isso. A worktree e PERSISTENTE (ao contrario das filhas de CHILD_ROOT). DO_WT_ROOT/DO_WT_NAME no ENV_FILE sao derivados do FATO (MODE=contido + branch `do/wt/<nome>`); DO_WT_ROOT_ENTERED e o sentinel de re-entrada (evita loop). Outras opcoes: `--new-run`, `--force-nested`, `--quiet`, `--help` (imprime o cabecalho inteiro). Exit: 0 ok; 2 flag/variavel invalida ou SKILL_HOME nao resolvido; 3 nao e repo; 4 HEAD destacado; 5 repo sem commits; 6 indice sujo; 7 caractere proibido em path/branch; 8 git inesperado; 9 colisao de namespace. | FASE 0 |
| `do-wt.sh` | Ciclo de vida das worktrees-filhas, com guardas de contencao: todo subcomando recusa alvo que nao esteja no `owned.tsv` DESTA execucao, sob CHILD_ROOT e com o lock desta execucao, e arquiva o branch em `refs/do-archive/$RUN_ID/` antes de apaga-lo. **v4.1.0: a limpeza e POR TAREFA, no gate verde, feita pelo SCRIPT** -- `integrate` -> `gate` (background) -> `finish` automatico; `close` para quem nao sera integrado; `assert-clean` como portao inter-onda; `ledger` como fonte do relatorio. Tabela de subcomandos e codigos de saida logo abaixo. Toda reescrita do `owned.tsv` e serializada por lock: `flock(1)` quando existe; senao `mkdir "$OWNED.lock.d"` atomico com retry e quebra de lock velho (dono morto ou > 30 s) -- macOS nao tem flock. kinds: feature, test, validation, fix, prep, integration. `--help` e `checklist` funcionam SEM ENV_FILE. | FASE 1, 3-4 |
| `surf-gate.sh` | **[v4.1.0]** PORTAO DA SURF (R7) e protocolo PESQUISA-FALHOU, deterministicos. E o UNICO lugar que interpreta o estado da surf-agent-skill; o SKILL.md so le as linhas `CHAVE=valor`. `surf-gate.sh [gate]`: FAIL-CLOSED -- sem `surf-research-skill` ou `surf-search-normal` no PATH => `SURF_GATE=127`; senao roda `surf-research-skill gate` (gratis) e QUALQUER saida != 0 conta como 78. Imprime `SURF_GATE=<0\|78\|127>`; quando != 0 tambem `SURF_CODE=<BraveKeyMissing\|BraveKeyBurned\|BraveKeyCooling\|BraveKeyInvalid\|BraveKeyUnverified\|BraveKeyUnproven\|BraveKeyUnknown\|NotInstalled>` e a mensagem do portao VERBATIM (token com cara de chave Brave sai mascarado). Grava a mesma saida em `$DO_STATE/surf-gate.last`. SEMPRE exit 0: o veredito e a linha, nao o exit code. `classify <exit> <stdout-file> <stderr-file>`: imprime UM de `OK \| EMPTY \| FAILED_QUOTA \| FAILED_OTHER \| BLOCKED_78 \| KILLED_143 \| USAGE_2` -- cota/429/402 NAO sai 78 no surf, sai exit 1 (0 fontes), igual a busca vazia; os padroes sao ANCORADOS e o eco da query e removido antes do grep (query com "429"/"quota" nao vira FAILED_QUOTA). `pause <onda> "<sub-tarefas>" "<motivo>"`: grava `$DO_STATE/search-pause.md` e imprime `PAUSE_FILE=<path>` + o BLOCO DA PERGUNTA (4 opcoes com os comandos exatos de chave) para colar como ULTIMA coisa da resposta. `resume [--probe]`: reroda o portao; `--probe` faz UMA busca real barata (1 credito -- a sonda gratis nao enxerga cota), so com o portao verde, e classifica; imprime `RESUME=OK` (apaga search-pause.md) ou `RESUME=STILL_BLOCKED` + a pergunta de novo. `choose no-search`: grava `$DO_STATE/search-mode` (opcao [3] do usuario) e apaga o search-pause.md -- dai o `gate` imprime TAMBEM `SURF_MODE=no-search`, mesmo com SURF_GATE=0; `choose search` apaga o arquivo. `classify` roda sob LC_ALL=C (byte invalido nao vira EMPTY); `resume --probe` sem pausa previa NAO grava pause nem imprime pergunta. NUNCA le `~/.config/surf/keys.json` nem roda `keys list --json`. O chamador sourceia o ENV_FILE antes (DO_STATE e RUN_ID vem dele); no ENV_FILE o script e `$DO_SURF_GATE`. Exit: 0 rodou (leia o veredito na saida); 2 erro de uso (ou `pause` sem DO_STATE gravavel -- a pergunta sai mesmo assim). | FASE 0, 2, 2.5, 3 |

### do-wt.sh -- subcomandos (v4.1.0)

Fluxo por tarefa (o caminho normal):

| Subcomando | O que faz | Exit |
|---|---|---|
| `new <kind> <nome>` | Cria a filha, trava (lock nativo do git) e registra no ledger (11 colunas). Valida kind e nome (sem whitespace; nome ja usado na execucao => use `<nome>-r2`). RECUSA kind feature/fix/prep da onda N enquanto houver sobra de onda anterior (mesma tabela do `assert-clean --wave N`). RECUSA kind=test e nome `test-onda*` com DO_TEST_MODE=none (`RECUSADO: TEST_MODE=none (no-test)`). Falha ao travar => desfaz e falha. | 6 = sobra de onda anterior; 1 = demais recusas |
| `integrate <nome> "<msg>"` | = `merge` (mesmas guardas) + snapshot kind=integration `int-<nome>` (`-r2`, `-r3`... se o nome ja existir; parent=<nome>) no SHA pos-merge + filha=gate-pending. Ultima linha: `SNAPSHOT=<path>`. Merge falhou => nada de snapshot. RECUSA (rc 1, com o conserto: `git -C <wt> switch <br> && git merge <sha>`) filha cujo HEAD saiu do branch registrado (`git switch -c`, HEAD destacado): o squash nao veria esse trabalho. | 1 = conflito ou recusa; 4 = VAZIO (squash sem mudanca) |
| `gate-set <etapa> "<cmd>"` | etapa = build, test, lint, e2e ou install. Grava o comando CRU em `$DO_STATE/gate/<etapa>.cmd` (string vazia remove = "sem <etapa>"). FASE 1, uma unica vez. | 2 = uso |
| `gate <nome> [--e2e]` | Roda no snapshot vivo de <nome> (cwd = snapshot, HUSKY=0 CI=1; herda o ambiente de quem chama, ex. E2E_PORT): install -> build -> test -> lint (-> e2e). Log e rc em `$DO_STATE/gates/<nome>.log` e `.rc` (`running <pid> <post_sha>` no inicio; `<rc> <post_sha>` no fim -- o veredito vale SO para o squash em que rodou). 2o `gate` com o 1o vivo => rc 3 `AGUARDE`, sem tocar log/rc. Gate de kind=test com DO_TEST_MODE=e2e e etapa e2e registrada roda o e2e SOZINHO (`--e2e` segue aceito). VERDE => chama `finish` SOZINHO e imprime `GATE VERDE -- <nome> fechado` (travessao no literal real). VERMELHO => NAO limpa nada, imprime a etapa que falhou + as ultimas 40 linhas do log. Sem snapshot vivo (filha MERGED por `merge` legado) recria o snapshot a partir do post_merge_sha. Feito para rodar em background. | 0 = verde e fechado; 3 = ja esta rodando; 4 = vermelho; 5 = uso (nenhuma etapa configurada, filha nao integrada, `--e2e` sem etapa e2e); 1 = falha de fechamento |
| `finish <nome> [--gate-ok]` | Fecha filha INTEGRADA (MERGED ou gate-pending): salva restos da arvore (commit `--no-verify`) -> arquiva o branch em `refs/do-archive/$RUN_ID/<nome>` -> remove a worktree -> apaga o branch -> fecha TODOS os snapshots com parent=<nome> -> status REMOVED, outcome MERGED. gate-pending exige `gates/<nome>.rc` == 0 (do squash ATUAL) OU `--gate-ok` (o orquestrador rodou o gate por fora e atesta o verde; ou vitima coberta por um verde posterior -- `covered`). Cauda NAO integrada (tip da filha com conteudo novo apos o ultimo squash -- compara arvores, `gates/<nome>.tip`) e/ou gate VERMELHO no fechamento => outcome `MERGED-PARTIAL:<motivo>` (vai ao bloco do purge). HEAD da filha fora do branch registrado e arquivado TAMBEM em `refs/do-archive/$RUN_ID/<nome>-HEAD`. Idempotente. | 3 = gate rodando ou nunca rodou; 4 = gate vermelho (nada limpo); 1 = recusa |
| `close <nome> [--discard "<motivo>"]` | Fecha quem NAO sera integrado. kind integration/validation: sempre (outcome DISPOSABLE). Demais: com squash registrado RECUSA ("use finish"); commits a frente do base_sha OU arvore suja => exige `--discard` (salva restos, arquiva, remove, outcome `NEVER-MERGED:<motivo>`); vazia e limpa => outcome EMPTY -- commits em `base..HEAD-da-worktree` (HEAD destacado / `switch -c`) NUNCA viram EMPTY: exigem `--discard` e o HEAD e arquivado em `<nome>-HEAD`; branch criado fora do namespace e LISTADO no aviso, nunca apagado. Sempre REMOVED ao fim. Idempotente. | 1 = recusa; 2 = uso |
| `assert-clean [--wave N]` | PORTAO INTER-ONDA. Lista CADA sobra + o comando exato de conserto: (a) feature/fix/prep/integration de onda < N nao-REMOVED (BLOCKED/ORPHANED inclusive; snapshot herda a REGRA DO KIND DO PARENT -- o de um test-onda(N-1) vale como test, entao nao trava `new fix ondaN-*`; o conserto de snapshot com parent vivo e o do parent); (b) test/validation de onda < N-1 nao-REMOVED (a subwave da onda N-1 pode estar em voo); (c) realidade x ledger, so do que e provadamente nosso (diretorio em CHILD_ROOT sem linha; linha REMOVED com diretorio; ref em BRANCH_NS/ sem linha viva). Sem `--wave`: exige TUDO fechado (fim da execucao). Imprime `ASSERT-CLEAN OK ...` ou `ASSERT-CLEAN FALHOU ...`. | 1 = ha sobra; 2 = uso |
| `sweep` | Fim de onda: fecha MERGED (via `finish`) e os snapshots cujo parent ja fechou. Falha com gate-pending, REVERTED ou feature/fix ainda ACTIVE (nao integrada), cada um com o comando de conserto; test/validation ACTIVE so sao listadas (subwave em voo). Uso no passo 8: `sweep && assert-clean --wave <N+1>; verify`. | != 0 = a onda NAO fecha |
| `purge` | COMMIT-FINAL: garantia final -- NADA desta execucao sobrevive. Por linha nao-REMOVED: MERGED/gate-pending => `finish --gate-ok`; resto => `close --discard "purge"` (branch SEMPRE arquivado antes). `PURGE OK` so se ledger E realidade fecharam. Havendo NEVER-MERGED ou MERGED-PARTIAL na execucao, imprime o bloco `PURGE: NUNCA INTEGRADAS / PARCIAIS (obrigatorio no relatorio final):`. Nunca toca no branch da raiz-de-mundo nem em alvos fora do ledger. | 1 = falha de remocao; 3 = limpou tudo mas houve NEVER-MERGED/MERGED-PARTIAL (repete a cada purge, de proposito) |
| `ledger` | Tabela `NOME KIND ONDA STATUS OUTCOME ARCHIVE_REF` + rodape `RESUMO: integradas=N nunca-integradas=N vazias=N descartaveis=N parciais=N abertas=N sem-destino=N`. Fonte da secao "Nao integrado" e do titulo (concluida x PARCIALMENTE) do relatorio final. | 0 |
| `checklist` / `checklist final` | CARTAO DA ONDA (FASE 3) com EXATAMENTE a numeracao dos `<step order>` do SKILL.md (0, 1, 2, 3, 3.5, 4, 4.5, 5, 6, 7, 8, 9, 10) e CHECKLIST FINAL (FASE 4, passos 0-8, uma linha cada); ambos texto fixo, <= 30 linhas, sem ENV_FILE. Com DO_QUESTION=1 o cartao ganha a linha da rodada de pergunta. Re-ancoragem apos compactacao de contexto. | 0 |
| `verify` | Prova de contencao (roda a cada onda): HEAD, working tree e config local do checkout principal contra o baseline da FASE 0; inclui chaves de config perigosas (include/includeIf, excludesFile/attributesFile, filter, sshCommand). | != 0 = violacao |
| `status` | Tabela do ledger (gatilho do passo 3.5: mostra test-/val- ACTIVE da onda anterior). | 0 |
| `stage-delta` / `clean-ignored-delta` | COMMIT-FINAL: estagia SO o que e nosso / remove SO os ignorados criados depois da FASE 0 (roda ANTES do `rm -rf` do estado). | -- |
| `wave-files <nome-da-1a-filha>` | Arquivos tocados pela onda. Considera as filhas com squash registrado e nao REVERTED (com o fechamento por tarefa a filha integrada ja esta REMOVED). | -- |

Primitivos / reparo (continuam compativeis; NAO sao o caminho normal):

| Subcomando | O que faz |
|---|---|
| `merge <nome> "<msg>"` | Squash-merge guardado na raiz-de-mundo; merges SAO SERIAIS. CONFLITO e detectado ANTES de tocar a arvore (`git merge-tree --write-tree`, git >= 2.38): rc 1, raiz intacta -- resolva DENTRO da filha (`git -C <wt> merge "$BASE_BRANCH"`) e re-execute. Commits internos (wip e squash) usam `--no-verify` (hook do repo-alvo nao trava a orquestracao; a qualidade e do gate). Commit do squash falhou => indice desfeito, re-merge possivel. Squash SEM mudanca => NAO vira MERGED: rc 4, `VAZIO: ...`. RE-integracao (fix apos gate vermelho) de filha que NAO contem o proprio squash: o script confere em memoria se cada path tocado chega a `$BASE_BRANCH` identico ao da filha; se nao, RECUSA rc 1 (`PERDERIA parte do fix` + lista de paths) -- o 3-way a partir do base_sha antigo descartaria delecao/reversao em silencio. Conserto: merge de `$BASE_BRANCH` na filha, reaplicar o fix nesses paths, commitar e repetir. Regra: apos gate VERMELHO, o merge do BASE na filha vem ANTES do fix. Fix so aditivo passa direto. |
| `undo <nome>` | Desfaz TODOS os squashes VIVOS da filha (o original e o de cada fix re-integrado; lista em `$DO_STATE/squashes/<nome>`, truncada apos o undo) -- revert do mais novo ao mais antigo; reset --hard so sob guarda (pre..HEAD = exatamente a lista, working tree sem modificacao tracked). Funciona com HEAD avancado (falha tardia) e arquiva cada squash em `refs/do-archive/$RUN_ID/undo-<nome>-<k>`. A re-integracao preserva a col 7 (pre do 1o squash): `wave-files` ve a onda inteira. |
| `remove <nome> [--artifacts]` | Remove a filha (guardas de posse). Nome inexistente => erro claro. Diretorio sumiu com registro travado => desregistra SO aquela entrada (nunca `worktree prune`). HEAD fora do branch registrado e arquivado em `<nome>-HEAD` antes. Grava o outcome ao marcar REMOVED. |
| `drop-branch <nome>` | Arquiva e apaga o branch (so MERGED/REMOVED). kind feature/fix/test/prep exige squash registrado (post_merge_sha) OU outcome != `-`: um `mark MERGED` manual nao apaga trabalho nao integrado. REVERTED: rode `remove` antes. |
| `mark <nome> <STATUS>` | ACTIVE, MERGED, REMOVED, BLOCKED, ORPHANED, REVERTED ou gate-pending (valida nome e status). |

Ledger `owned.tsv` -- 11 colunas TSV: run_id, kind, name, branch, path, base_sha, pre_merge_sha, post_merge_sha, status, parent, outcome. parent/outcome nunca vazios (placeholder `-`); linha antiga de 9 colunas vale `-` nas duas e e promovida na 1a reescrita. outcome: `-`, MERGED, `MERGED-PARTIAL:<motivo>`, EMPTY, DISPOSABLE ou `NEVER-MERGED:<motivo>`. Leia SEMPRE por `awk -F'\t'` (as colunas 7/8 podem ser vazias e `IFS=$'\t' read` colapsa campos vazios).

Estado novo sob `$DO_STATE`: `gate/<etapa>.cmd`, `gates/<nome>.log`, `gates/<nome>.rc` (`running <pid> <sha>`, ou `<rc> <sha>`), `gates/<nome>.tip` (tip integrado), `squashes/<nome>` (squashes vivos), `partial/<nome>` (motivo do MERGED-PARTIAL), `search-mode` (opcao [3]), `owned.tsv.lock.d/`, `.flock-aviso` (o aviso do fallback sem flock sai 1x por execucao), `surf-gate.last`, `search-pause.md`, `question/pendente.md`.

Knobs de diagnostico/teste: `DO_WT_MERGE_TREE=0` forca o fluxo antigo de conflito (com rollback imediato por `reset --merge`); `DO_WT_NO_FLOCK=1` forca o lock por mkdir mesmo com flock no PATH.

## Portao de aprovacao do plano (FASE 2.5)

| Script | Proposito | FASE |
|--------|-----------|------|
| `check-plannotator.sh` | Verificador pre-fase. Resolve o executavel do Plannotator ($DO_PLANNOTATOR_BIN -> PATH -> ~/.local/bin -> %LOCALAPPDATA%/%USERPROFILE% no Git-Bash), confere a versao (minima 0.19.1) e SONDA a capacidade rodando `annotate` sem argumento -- que so imprime o usage, sem abrir navegador nem subir servidor. Com `--install`, instala o binario quando AUSENTE via `curl -fsSL https://plannotator.ai/install.sh \| bash -s -- --minimal --non-interactive`: `--minimal` grava SO o binario em ~/.local/bin e nao escreve uma linha em ~/.claude, ~/.codex, ~/.gemini, ~/.kiro ou ~/.config/opencode. Uma instalacao EXISTENTE nunca e sobrescrita (o instalador oficial nao sabe atualizar: sempre rebaixa ~150 MB e sobrescreve, e um --minimal por cima de uma instalacao completa deixaria as integracoes de agente numa versao e o binario em outra). Recusa instalar como root (o instalador nao tem guarda de EUID e iria para /root/.local/bin, invisivel ao usuario real). Nunca sudo, nunca npm -g. Exit codes: 0 (disponivel), 1 (ausente mas instalavel), 2 (ausente e nao instalavel). Opcoes: --install, --json, --quiet, --min-version. | FASE 2.5 |
| `plan-approval.sh` | UMA rodada de aprovacao do plano no Plannotator. Fotografa o documento num snapshot IMUTAVEL (chmod a-w) antes de manda-lo ao navegador, resolve o numero da revisao pelo MAIOR entre o trail e o que ja existe em disco (uma rodada interrompida deixa um rev-NNN.md sem linha no trail; contando so o trail, a rodada seguinte reusaria o numero e esbarraria no snapshot somente-leitura, travando o portao pelo resto da execucao), trava o TITULO na revisao 1 e RECUSA a rodada se ele mudar (o Plannotator rastreia versoes do MESMO plano pelo primeiro `#`; e regra do proprio Plannotator), roda `plannotator annotate <snap> --gate --json </dev/null` sob `timeout(1)` -- o `</dev/null` e obrigatorio: o dispatch do Plannotator cai num else final que LE STDIN como evento de hook -- e le a decisao do envelope --json (jq ou python3), nunca do texto humano. Forca DUAS travas de rede por default: `PLANNOTATOR_SHARE=disabled` (em sessao SSH o Plannotator publicaria o texto do plano num servico de paste) e `PLANNOTATOR_REMOTE=0` (sem isso, qualquer shell com SSH_TTY/SSH_CONNECTION faria o servidor escutar em 0.0.0.0:19432 -- e como /api/approve NAO tem autenticacao, qualquer um na rede leria o plano e poderia APROVA-LO, levando o orquestrador a criar worktrees e commitar; para revisar por SSH use um tunel `ssh -L 19432:127.0.0.1:19432 <host>`). Liberam-se com DO_PLAN_SHARE=1 e DO_PLAN_REMOTE=1, este ultimo com aviso em voz alta. Detecta o harness (claude-code > pi > jcode > opencode) so para carimbar PLANNOTATOR_ORIGIN. Subcomandos: init, round, status, feedback [N], doc [N], origin, title, approved. Exit codes de `round`: 0 aprovado, 10 anotado, 11 fechado, 12 timeout, 13 falha da ferramenta, 14 orcamento esgotado, 2 uso/ambiente (inclui deriva de titulo). | FASE 2.5 |

## Distribuicao

| Script | Proposito |
|--------|-----------|
| `check-install.sh` | Prova de que UMA INSTALACAO da skill esta COMPLETA: verifica o contrato de instalacao num diretorio (SKILL.md com `name:` correto + ferramentas executaveis `scripts/{do-context,do-wt,surf-gate,check-plannotator,plan-approval,evolve-skill,do-prefs,evolution-survey}.sh` + `scripts/lib/{evolve-common,plannotator-common}.sh` + `prompts/{ecc-prompts,ecc-skills,search-prompts,plan-approval-prompts,evolution-guide}.md`). Aceita a raiz do repo OU a pasta `.claude/skills/...` (que espelha scripts/prompts por symlink). `--root <dir>` (default: a propria casa da skill), `--json`, `--quiet`. Exit 0 completo · 1 faltando itens · 2 uso. Detecta o estado "so SKILL.md, sem scripts" que faz a FASE 0 abortar com "PARE: do-context.sh nao encontrado". |

## Auto-evolucao (PERGUNTA de evolucao + prefs — v3.9.0)

| Script | Proposito |
|--------|-----------|
| `do-prefs.sh` | Motor de PREFERENCIAS: le/cria/apenda a memoria consultiva em `.deep-orchestrator-preferences/` do projeto (`project-config.md`, `learnings.md`, `pending/proposals.md`) e da skill (`global-tips.md`, `pending/proposals.md`). Tudo gitignored, NUNCA versionado. Subcomandos: load, add-project, add-global, pending-add, pending-list, ensure-gitignore, status. Exit: 0 ok · 2 lote invalido/uso · 3 escrita fora da raiz de prefs. |
| `evolution-survey.sh` | A PERGUNTA DE EVOLUCAO em TEXTO no terminal (FASE 4, passo 7.5 — v3.9.0, nunca mais um site): `ask` monta a pergunta numerada (cada proposta com observacao + opcoes a/b/c + escopo "1 = fix local · 2 = fix global") em `pendente.md` e imprime o bloco; `answer "<codigos>"` parseia a resposta (`1:b2` — opcao + escopo; "nada" = tudo pendente; `config: <texto>` = preferencias livres) para answers.json; `apply` roteia para do-prefs.sh (salvar projeto/global com a ACAO da opcao escolhida, descartar, pendente) — idempotente, nunca falha a execucao (D9); `dismiss` = sem resposta (tudo pendente); `status` = trail. Exit: 0 ok · 2 uso/gramatica invalida. |
| `evolve-skill.sh` | Evolucao do CORPO da skill (SKILL.md/prompts/docs): search (agora varre as prefs + prompts + SKILL.md), diff/apply (qualquer mudanca de corpo -> branch evolve/YYYY-MM-DD + diff, nunca merge sozinho), status. `add`/`consolidate` FORA (exit 2 apontando para do-prefs.sh): a memoria nao e mais commitada — o LEARNINGS.md foi removido do repo na v3.8.0. |
| `lib/evolve-common.sh` | Validadores/parsers COMPARTILHADOS do formato de bloco (normalize, sha_of, now_iso, parse_fields — incluindo opcao_a/b/c —, validate_candidate, secret_scan, split_entries, next_id_for) — fonte unica usada por do-prefs.sh, evolution-survey.sh e evolve-skill.sh. |
| `lib/plannotator-common.sh` | Contrato de maquina do Plannotator compartilhado (resolve_bin, detect_harness, envelope --json via jq/python3, snapshot/titulo) — fonte unica usada por plan-approval.sh (o portao de aprovacao do plano CONTINUA no Plannotator). |

Fluxo v3.9.0: ao fim de cada execucao — DEPOIS de commit, push e relatorio — o
orquestrador dispara um AGENTE DE EVOLUCAO fresco que analisa o historico completo
(TASK_PLAN.md + transcripts do harness quando existem) e produz propostas com
opcoes a/b/c. A evolucao vem como UMA PERGUNTA EM TEXTO no terminal: o usuario
responde com codigos (ex.: "1:b2" — opcao b, fix global) na proxima mensagem e as
respostas viram escrita em prefs — gitignored, memoria CONSULTIVA, nunca politica.
Respondeu "nada" ou seguiu em frente -> NADA e aplicado: as propostas ficam
PENDENTES para a proxima execucao. A flag `no-evolve` na invocacao pula a pergunta
E o agente de analise. Nada e promovido ao corpo da skill automaticamente.

## Busca (search)

**Nao existe.** Removido na v4.0.0 (decisao D23).

`search.sh`, `search-parallel.sh`, `brave-search.sh`, `check-search-credits.sh`
e `check-brave-credits.sh` foram APAGADOS -- 3.346 linhas de sistema de busca
proprio. A pesquisa web e 100% **surf-agent-skill v8**, pelos binarios globais:

| Binario | Quando |
|---|---|
| `surf-search-normal "<pergunta>" --sub-agents=N` | uma onda; o caminho padrao |
| `surf-search-unlimit "<pergunta>" --sub-agents=N --max-depth 3` | pergunta aberta que precisa descer |
| `surf-research-skill search-parallel "q1" "q2" --sub-agents=N --json` | lote de perguntas cruas, sem sintese |
| `"$DO_SURF_GATE"` (= `scripts/surf-gate.sh`) | O PORTAO (v4.1.0), fail-closed. `SURF_GATE=0` = prossiga, 78 = sem chave Brave valida, 127 = pacote ausente. NAO existe veredito 1 |
| `surf doctor` | So para REGISTRAR os blocos de diagnostico na FASE 0 (passo 6); o exit code dele NAO e interpretado |

Brave e o unico backend: nao ha Tavily, Parallel, Wikipedia, DuckDuckGo,
provedor de reserva nem tier sem chave. Nao existe modo degradado AUTOMATICO --
ou ha chave valida e a pesquisa funciona, ou o orquestrador PAUSA E PERGUNTA ao
usuario (protocolo PESQUISA-FALHOU, `surf-gate.sh pause`): seguir sem a pesquisa
exigida e escolha do usuario, nunca do orquestrador. A pergunta e INCONDICIONAL:
vale com ou sem `do-question` e vence "nao me pergunte nada", no-stop e plan=off.

E PROIBIDO envolver o surf em `sleep`, jitter, backoff ou retry: ele ja ritma
cada requisicao pelo limite real do plano Brave, num token bucket
CROSS-PROCESS compartilhado por todos os processos surf da maquina. Um ritmo
por cima briga com o limitador e provoca o 429 que ele evita.

Ver `docs/decisions/2026-08-29-surf-agent-skill-obrigatorio.md` e a regra R7
do SKILL.md.


## Ferramentas (geracao)

| Script | Proposito | FASE |
|---|---|---|
| `—` | **[v3.6.0]** A geração do EXPLAINER.html é DELEGADA a sub-agente (fluxo html-explainer-agent-skill — brief didático + render visual-explainer; sem limite de tempo; salvo em $BASE_DIR/EXPLAINER.html). Não há script dedicado. O passo 4 do COMMIT-FINAL no SKILL.md descreve o ritual. | FASE 4 |

## Testes

| Script | Proposito |
|---|---|
| `test-contencao.sh` | Testes de aceitacao do MODO CONTIDO e do fechamento por tarefa (A1..A20 + A22/A23/A25..A34 + A35..A56, **309 assercoes**). Cria fixtures em `mktemp -d` (repo principal + worktree irma + worktree de terceiro) e verifica invariantes: deteccao de MODE, fronteira BASE_DIR, isolamento de worktrees, protecao contra operacoes em branches de terceiros. A23: merge com CONFLITO recusado SEM sujar a raiz -> resolucao na filha -> re-merge (A23b = fluxo antigo com rollback). A27: lab com espaco e acento no nome (ponta a ponta). A28/A29: exits 6/7/9 da FASE 0. A30: lock -- dois marks paralelos sem lost update. A31: kind=validation ciclo completo. A32 cobre o A24 do plano (wave-files apos 2 squashes). A33: falha tardia de gate de snapshot (undo com HEAD avancado) -- cobre o A21. A34: gate-pending bloqueia o fim de onda. **v4.1.0:** A35 integrate + gate verde fecha filha e snapshot; A36 gate vermelho rc 4, finish rc 3/4/--gate-ok; A37 close (validation, --discard/NEVER-MERGED, EMPTY); A38 squash vazio rc 4 e `mark MERGED` manual nao apaga trabalho; A39 hook que falha e rollback do indice; A40/A41 purge (arvore suja, rc 3 + bloco, diretorio ausente, sem OK falso) e ledger; A42 sweep (snapshot orfao, feature ACTIVE); A43 assert-clean --wave, new rc 6, DO_TEST_MODE=none; A44 lock por mkdir sem flock; A45 ledger de 9 colunas, --help, checklist; A46 path com espaco/acento (gate sobre MERGED legado, snapshot -r2, undo+remove no ledger); A47 guarda de re-integracao; **rodada final:** A48 HEAD destacado / `switch -c` (integrate recusa; close arquiva `<nome>-HEAD`, nunca EMPTY); A49 re-integracao preserva o pre do 1o squash, undo desfaz TODOS, wave-files ve a onda inteira; A50 undo com squash alheio no meio; A51 gate vermelho + cauda => MERGED-PARTIAL, `parciais=`, purge rc 3 com o bloco novo; A52 snapshot de test-onda(N-1) nao trava `new fix`; A53 2o gate concorrente rc 3 sem tocar log/rc; A54 gate de kind=test em e2e roda o e2e sozinho; A55 cartoes = `<step order>` do SKILL.md; A56 gate sobre MERGED legado vira gate-pending. Portavel para macOS (bash 3.2, BSD sed/wc, sem flock); limpa os labs via trap. |
| `test-flags.sh` | **[v4.1.0]** Testes de aceitacao das FLAGS da FASE 0 (`do-context.sh --flags='...'`) -- FL1..FL16, **307 assercoes**. SEM rede, SEM surf, SEM Plannotator: so do-context.sh (e, no FL10e/FL14, o purge real do do-wt.sh) contra repositorios descartaveis em `mktemp -d`. FL1 defaults e export das variaveis novas; FL2 cada flag -> variavel no ENV_FILE + linha no resumo; FL3 flag VENCE env; FL4 env sozinha ainda funciona (valor invalido = exit 2); FL5 token desconhecido = exit 2 com sugestao deterministica, sem residuo em disco, glob nao expande; FL6 no-test + only-e2e e plan=on + plan=off = exit 2; FL7 surf-sub-agents fora de 1..20; FL8/FL9 anti-stale de TEST_MODE e QUESTION; FL10 DO_ORPHAN_RUNS (o comando impresso, rodado de verdade, fecha a worktree abandonada); FL11 wt=<nome> cria, REENTRA (nunca <nome>-2), sobrevive ao re-exec; FL12 owned.tsv de 11 colunas, vivas contadas pela coluna 9; FL13 --help inteiro; FL14 path com espaco e acento; **rodada final:** FL15 `--boundary` (apelidos e `--no-test` = exit 2 com a forma certa; texto e ignorado), `--flags=` repetido = exit 2, env antigo completado no DO_REUSE, orfas inventariadas antes do re-exec do `wt=`, resumo sem "nenhuma interacao"; FL16 wt=<outro> dentro de wt-root = DO_WARN, validacoes antes de criar a worktree irma. |
| `test-plan-approval.sh` | Testes de aceitacao do PORTAO DE APROVACAO DO PLANO (G1..G9 + P1..P29 + DC1..DC4 + R1..R7, **139 assercoes**, todas verdes no macOS com `timeout` do coreutils no PATH). Tudo mockado num PATH temporario: um `plannotator` FAKE fiel ao contrato real (usage em `annotate` sem argumento, `{"decision":"approved"\|"dismissed"\|"annotated"}` em uma linha, exit SEMPRE 0) e um `curl` FAKE que finge o instalador. SEM rede, SEM navegador, SEM instalar nada. Cobre: resolucao do binario (PATH, ~/.local/bin, DO_PLANNOTATOR_BIN), sonda de capacidade rejeitando binario velho, instalacao com --minimal --non-interactive, recusa de sobrescrever instalacao existente (G9), os seis exit codes de `round`, argv exato, imutabilidade do snapshot, deriva de titulo, orcamento de revisoes, PLANNOTATOR_SHARE=disabled por default, prioridade de deteccao de harness, round-trip de feedback com aspas/newline/acento/backslash, ruido antes do JSON, `annotated` com feedback vazio degradando para `dismissed`, contencao de escrita, idempotencia via `approved`, ausencia de jq E python3, portabilidade do timeout(1) (GNU, BSD, ausente -- P29) e os DO_PLAN_* no ENV_FILE. |
| `test-surf-gate.sh` | Testes do PORTAO DA SURF (`surf-gate.sh`) e do orcamento `--sub-agents` (G0..G12, **228 assercoes**). Substitui o `test-search.sh`, que testava o sistema de busca removido. Tudo mockado em PATH temporario, SEM rede, SEM quota, SEM chave -- o surf REAL nunca e alcancado, nem pela sonda do `resume --probe`: G0 isolamento do PATH; G1 surf ausente -> SURF_GATE=127 / NotInstalled; G2 chave invalida -> 78 + SURF_CODE=BraveKey* + mensagem VERBATIM; G3 FAIL-CLOSED: exit 1/2/143 do binario do portao vira 78 (nunca "prossiga"); G4 portao verde, surf-gate.last, chave nunca impressa; G5 aritmetica `max(1, floor(N/R))` e a prova de que a soma da onda nunca passa de N; G6 `--sub-agents` fora de 1..20 -> exit 2; G7 regressao de arquitetura (nenhuma referencia viva aos scripts removidos, a DDG, a `surf-free-skill` ou as flags que nao existem); G8 o SKILL.md ainda declara o contrato que a suite testa (e o portao fail-open antigo SAIU); G9 classify -- cada classe, e query com "429"/"quota" nao vira FAILED_QUOTA; G10 pause/resume com DO_STATE temporario, `choose no-search|search` e `SURF_MODE`; G11 instalacao (check-install.sh) e higiene bash 3.2; G12 contrato cruzado (pergunta do `pause` LITERAL no SKILL.md, linha SEARCH_STATUS igual em SKILL.md e prompts, todo subcomando citado existe no dispatch, 9 flags x do-context x README, description <= 1024, XML parseia, SKILL.md <= 220000 chars, cartao = `<step order>` da FASE 3). Suite hermetica: nao herda DO_STATE/RUN_ID de um ENV_FILE sourceado. |
| `test-evolve.sh` | Testes do motor de prefs / PERGUNTA de evolucao / evolve-skill (F1..F14 + S1..S10 + E1..E6, **81 assercoes**). Cada caso roda isolado num repo fake da skill, com HOME/tmp proprios, SEM rede. F14 (v4.1.0): bash 3.2 + `set -u` -- do-prefs.sh sem subcomando sai com o uso (exit 2), nunca `unbound variable` (array vazio). |

Rodar tudo (sem rede, sem navegador, sem gastar credito de busca): `for t in scripts/test-*.sh; do bash "$t"; done`. Contagens medidas em 2026-09-20 no macOS (bash 3.2.57, BSD sed/wc, git 2.39.5, sem flock): 309 + 307 + 139 + 228 + 81 = 1064 assercoes, 0 falhas.

---

## Fluxo do portao de aprovacao (FASE 2.5)

```
                     FASE 2 termina: plano publicado em $PLAN_FILE
                                      |
                     DO_PLAN_APPROVAL = 1 ?  --nao-->  FASE 3 (autonomia total)
                                      | sim
                     plan-approval.sh approved ? --sim--> FASE 3 (ja aprovado,
                                      |                    reuso de ENV_FILE)
                                      | nao
                     check-plannotator.sh --install
                       exit 0 -> segue | exit 1 -> 1 retry | exit 2 -> PARA (R2d)
                                      |
        +------------> escreve $PLAN_DOC (TITULO IMUTAVEL)
        |                             |
        |             plan-approval.sh round "$PLAN_DOC"
        |                             |
        |          +----------+-------+--------+-----------+-----------+
        |          |          |                |           |           |
        |         rc=0      rc=10            rc=11/12     rc=13       rc=14
        |      APROVADO   ANOTADO          FECHADO/TO    FALHA     ORCAMENTO
        |          |          |                |           |           |
        |       FASE 3        |              PARA        retry        PARA
        |                     |                            |
        +---- REGERA o plano <+                        (1x, depois
              (feedback = correcao DO PLANO,            trata como
               nunca tarefa de codigo)                    exit 2)
```

Cada volta do laco e um Plannotator INTEIRAMENTE NOVO -- processo novo, servidor
novo, aba nova. A rodada anterior fica preservada no trail
($DO_STATE/plan-approval/rev-NNN.md, somente leitura, mais rev-NNN.feedback.md e
uma linha no trail.tsv).

Contrato de maquina do Plannotator (verificado no binario 0.19.17):
`annotate <arquivo> --gate --json` imprime UMA linha em stdout --
`{"decision":"approved"}`, `{"decision":"dismissed"}` ou
`{"decision":"annotated","feedback":"<markdown>"}` -- e sai SEMPRE 0. Nunca
ramifique pelo exit code do Plannotator: e o `plan-approval.sh` que traduz a
decisao para exit codes distintos. `--gate` e obrigatorio: sem ele a UI nao
mostra o botao Approve e o usuario fisicamente nao consegue aprovar.

## Fluxo de busca

```
sub-agente
  |
  +-- surf-search-normal / surf-search-unlimit / surf-research-skill
        |
        +-- Brave /web/search  <- o unico backend. Nao ha tier abaixo.
              |
              +-- exit 0   respondeu
              +-- exit 1   0 fontes -- CLASSIFIQUE (surf-gate.sh classify):
              |              EMPTY        busca vazia: registre, marque NAO VERIFICADO, siga
              |              FAILED_QUOTA cota/429/billing  -> PESQUISA-FALHOU
              |              FAILED_OTHER todas as chaves esgotadas etc. -> PESQUISA-FALHOU
              +-- exit 2   o comando esta errado (corrija; nunca vira pergunta)
              +-- exit 78  sem chave Brave valida (BLOCKED_78) -> PESQUISA-FALHOU
              +-- exit 143 o harness matou por timeout (refaca com surf-search-normal)
```

Todo sub-agente roda o surf redirecionando stdout/stderr para arquivo na
propria worktree (`<worktree>/.deep-orchestrator/surf/`), classifica com
`$SKILL_HOME/scripts/surf-gate.sh classify "$rc" <out> <err>` e abre o handoff
com a secao `## SEARCH_STATUS` (`NOT_NEEDED | OK | EMPTY | FAILED_QUOTA |
FAILED_OTHER | BLOCKED_78`). Em BLOCKED_78/FAILED_*: para de pesquisar, NAO usa
WebSearch, termina so o que nao depende do fato, commita o wip e reporta.

O orquestrador roda o PORTAO na FASE 0 (so registra), no PORTAO POS-PLANO da
FASE 2 e no passo 0 de cada onda:

```bash
. '<ENV_FILE>'; "$DO_SURF_GATE"
# SURF_GATE=0            -> prossiga
# SURF_GATE=78 | 127     -> ha sub-tarefa pendente SEARCH_REQUIRED=sim?
#                           sim: protocolo PESQUISA-FALHOU (pause -> pergunta -> fim de turno)
#                           nao: registre no TASK_PLAN.md e prossiga sem busca
```

O portao antigo (`surf doctor >/dev/null 2>&1; echo "SURF_GATE=$?"`) SAIU na
v4.1.0: jogava fora a mensagem que o usuario precisa ler e era fail-open no
exit 1 (o doctor sai 1 tanto por "faltam symlinks das skills do surf" quanto por
qualquer quebra). `surf-gate.sh` usa `surf-research-skill gate` (gratis, nao
gasta credito) e conta qualquer saida != 0 como 78. **Nunca** use
`surf-research-skill keys list --json` nem leia `~/.config/surf/keys.json` como
diagnostico.

### Protocolo PESQUISA-FALHOU (resumo operacional)

| Passo | Comando / acao |
|---|---|
| A | Nao dispara pesquisador novo; conclui revisao -> integrate -> gate -> finish das sub-tarefas NAO bloqueadas; as bloqueadas ficam ACTIVE, sem merge |
| B | `. '<ENV_FILE>'; "$DO_SURF_GATE"` (diagnostico gratis e visivel) |
| C | `. '<ENV_FILE>'; "$DO_SURF_GATE" pause <onda> "<sub-tarefas>" "<motivo>"` -> grava `$DO_STATE/search-pause.md` |
| D | Cola o bloco impresso como ULTIMA coisa da resposta e ENCERRA o turno. Opcoes: [1] troquei a chave, [2] ajustei plano/cota ou esperei o cooldown, [3] seguir SEM pesquisa (premissas NAO VERIFICADAS), [4] abortar (purge + relatorio parcial) |
| E | Retomada (FASE 0 passo 0 acha o search-pause.md): [1]/[2] -> `"$DO_SURF_GATE" resume --probe`; `RESUME=OK` re-delega as bloqueadas na MESMA worktree; `RESUME=STILL_BLOCKED` repete a pergunta |

Gatilhos: g1 portao != 0 com sub-tarefa pendente SEARCH_REQUIRED=sim; g2 handoff
com SEARCH_STATUS BLOCKED_78 / FAILED_QUOTA / FAILED_OTHER / ausente; g3 duas ou
mais EMPTY na mesma onda (`resume --probe`; so pausa se STILL_BLOCKED).
`SURF_CODE=BraveKeyCooling` (cooldown de 60 s): reroda o portao ate 3x, sem
sleep, antes de perguntar. Comandos de chave (quem roda e o USUARIO, no
terminal dele -- nunca cole a chave no chat): `surf-research-skill keys add
--provider brave <CHAVE>` (aceita `--stdin`), `surf add` (exige TTY),
`surf-research-skill keys reset --provider brave`, `surf remove brave <i>`,
`surf validate brave`.

### Orcamento de simultaneidade: os dois tetos SOMAM

Seja `N` o teto global do surf (`surf-sub-agents=N` na invocacao, default 10,
faixa 1..20 -- validado e gravado no ENV_FILE como DO_SURF_SUB_AGENTS) e `R` a
quantidade de sub-tarefas da onda com SEARCH_REQUIRED=sim (R = 0: ninguem
pesquisa, nao ha floor(N/0)). Cada um
recebe `--sub-agents=max(1, floor(N / R))`, de modo que a soma da onda
(`R x floor(N/R)`) nunca passa de `N`.

Se multiplicassem, uma onda cheia seria `DO_MAX_PARALLEL x 10 = 500` buscas
simultaneas contra um plano Brave que pode servir uma por segundo.

### Ferramentas nativas do harness (WebSearch/WebFetch)

**Nao sao caminho de pesquisa.** Fonte que nao veio pelo surf nao pode ser
citada em handoff nem em deliverable. Uso legitimo, unico: abrir com
`Read`/`WebFetch` uma URL **que o surf ja devolveu** -- e a unica forma de ler
o corpo de uma pagina, ja que a Brave devolve titulo, URL e trecho, e os verbos
`extract`/`crawl`/`map` foram removidos no surf v8.

