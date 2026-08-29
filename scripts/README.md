# Scripts -- deep-orchestrator-agent-skill

Diretorio de scripts executaveis do deep-orchestrator-agent-skill. Cada script tem uma funcao
especifica no ciclo de orquestracao. A ordem de execucao e ditada pelas FASES do
orquestrador (0 a 4), com `do-context.sh` sempre rodando primeiro.

---

## Core (orquestracao)

| Script | Proposito | FASE |
|---|---|---|
| `do-context.sh` | Resolve MODE (normal/contido), BASE_DIR, BASE_BRANCH, CHILD_ROOT, BRANCH_NS e grava arquivo de estado que TODO script posterior deve sourcear. Detecta se o cwd esta dentro de uma git worktree vinculada e delimita a RAIZ-DE-MUNDO. Grava tambem DO_PLAN_APPROVAL / DO_PLAN_MAX_REVISIONS / DO_PLAN_TIMEOUT / PLAN_APPROVAL_DIR / PLAN_DOC / DO_PLAN_APPROVAL_SH (FASE 2.5 -- portao de aprovacao; DO_PLAN_APPROVAL default 0, aceita 0/1/on/off/yes/no/true/false, exit 2 fora disso). Grava DO_MAX_PARALLEL (cap de paralelismo por onda — F3-02; default 50, prefixo mp=N na invocacao; exit 2 se nao for inteiro positivo). **WT-ROOT (flag wt=<nome>, FASE 0 passo 0.2):** quando DO_WT_ROOT=1 e o cwd e o checkout principal, cria/entra uma worktree IRMA VERDADEIRA do projeto em `<pai>/<repo>.worktrees/<nome>` e RE-EXECUTA este script com o cwd dentro dela — caindo em MODE=contido, de modo que TODO o trabalho (ondas, sub-agentes, merges, gates, COMMIT-FINAL) acontece dentro da worktree e o checkout principal fica INTOCADO. O nome e deduplicado contra o que ja existir dentro da pasta irma (colisao ganha -2, -3...) e a pasta .worktrees/ existente e REUSADA (nao recriada). A worktree e PERSISTENTE: o branch `do/wt/<nome>` e reusado entre execucoes (ao contrario das filhas efemeras de CHILD_ROOT). Variaveis: DO_WT_ROOT, DO_WT_NAME, DO_WT_ROOT_ENTERED (sentinel de re-entrada, evita loop). | FASE 0 |
| `do-wt.sh` | Gerencia todo o ciclo de vida das worktrees-filhas: cria (new, kinds feature/test/validation/fix/prep/integration), faz squash-merge (merge — merges SAO SERIAIS: toda reescrita do owned.tsv e serializada por flock (F4-07.1), sem lost update entre do-wt.sh paralelos; conflito de squash: resolva DENTRO da filha e re-execute — o indice residual e limpo automaticamente no re-merge (F4-07.2)), desfaz merge (undo — funciona com HEAD avancado, para falha tardia de gate de snapshot, e arquiva o commit em refs/do-archive/$RUN_ID/undo-<nome>), remove (remove), arquiva e apaga branch (drop-branch — so se MERGED/REMOVED; REVERTED: rode remove antes), encerra onda (sweep — DETECTA status=gate-pending: imprime aviso e sai != 0, o fim de onda nao fecha com gate de snapshot pendente; LISTA filhas REVERTED), verifica contencoes (verify — inclui chaves de config perigosas: include/includeIf, excludesFile/attributesFile, filter, sshCommand), consulta status (status), altera estado de filha (mark — com validacao de nome e status; statuses: ACTIVE/MERGED/REMOVED/BLOCKED/ORPHANED/REVERTED/gate-pending), estagia delta da onda (stage-delta), e lista arquivos tocados pela onda (wave-files — aceita a 1a filha MERGED da onda; se a filha passada nao foi mergeada, resolve automaticamente pela filha MERGED de menor pre_merge_sha do mesmo prefixo ondaN-). | FASE 3-4 |

## Portao de aprovacao do plano (FASE 2.5)

| Script | Proposito | FASE |
|--------|-----------|------|
| `check-plannotator.sh` | Verificador pre-fase. Resolve o executavel do Plannotator ($DO_PLANNOTATOR_BIN -> PATH -> ~/.local/bin -> %LOCALAPPDATA%/%USERPROFILE% no Git-Bash), confere a versao (minima 0.19.1) e SONDA a capacidade rodando `annotate` sem argumento -- que so imprime o usage, sem abrir navegador nem subir servidor. Com `--install`, instala o binario quando AUSENTE via `curl -fsSL https://plannotator.ai/install.sh | bash -s -- --minimal --non-interactive`: `--minimal` grava SO o binario em ~/.local/bin e nao escreve uma linha em ~/.claude, ~/.codex, ~/.gemini, ~/.kiro ou ~/.config/opencode. Uma instalacao EXISTENTE nunca e sobrescrita (o instalador oficial nao sabe atualizar: sempre rebaixa ~150 MB e sobrescreve, e um --minimal por cima de uma instalacao completa deixaria as integracoes de agente numa versao e o binario em outra). Recusa instalar como root (o instalador nao tem guarda de EUID e iria para /root/.local/bin, invisivel ao usuario real). Nunca sudo, nunca npm -g. Exit codes: 0 (disponivel), 1 (ausente mas instalavel), 2 (ausente e nao instalavel). Opcoes: --install, --json, --quiet, --min-version. | FASE 2.5 |
| `plan-approval.sh` | UMA rodada de aprovacao do plano no Plannotator. Fotografa o documento num snapshot IMUTAVEL (chmod a-w) antes de manda-lo ao navegador, resolve o numero da revisao pelo MAIOR entre o trail e o que ja existe em disco (uma rodada interrompida deixa um rev-NNN.md sem linha no trail; contando so o trail, a rodada seguinte reusaria o numero e esbarraria no snapshot somente-leitura, travando o portao pelo resto da execucao), trava o TITULO na revisao 1 e RECUSA a rodada se ele mudar (o Plannotator rastreia versoes do MESMO plano pelo primeiro `#`; e regra do proprio Plannotator), roda `plannotator annotate <snap> --gate --json </dev/null` sob `timeout(1)` -- o `</dev/null` e obrigatorio: o dispatch do Plannotator cai num else final que LE STDIN como evento de hook -- e le a decisao do envelope --json (jq ou python3), nunca do texto humano. Forca DUAS travas de rede por default: `PLANNOTATOR_SHARE=disabled` (em sessao SSH o Plannotator publicaria o texto do plano num servico de paste) e `PLANNOTATOR_REMOTE=0` (sem isso, qualquer shell com SSH_TTY/SSH_CONNECTION faria o servidor escutar em 0.0.0.0:19432 -- e como /api/approve NAO tem autenticacao, qualquer um na rede leria o plano e poderia APROVA-LO, levando o orquestrador a criar worktrees e commitar; para revisar por SSH use um tunel `ssh -L 19432:127.0.0.1:19432 <host>`). Liberam-se com DO_PLAN_SHARE=1 e DO_PLAN_REMOTE=1, este ultimo com aviso em voz alta. Detecta o harness (claude-code > pi > jcode > opencode) so para carimbar PLANNOTATOR_ORIGIN. Subcomandos: init, round, status, feedback [N], doc [N], origin, title, approved. Exit codes de `round`: 0 aprovado, 10 anotado, 11 fechado, 12 timeout, 13 falha da ferramenta, 14 orcamento esgotado, 2 uso/ambiente (inclui deriva de titulo). | FASE 2.5 |

## Distribuicao

| Script | Proposito |
|--------|-----------|
| `check-install.sh` | Prova de que UMA INSTALACAO da skill esta COMPLETA: verifica o contrato de instalacao num diretorio (SKILL.md com `name:` correto + ferramentas executaveis `scripts/{do-context,do-wt,check-plannotator,plan-approval,evolve-skill,do-prefs,evolution-survey}.sh` + `scripts/lib/{evolve-common,plannotator-common}.sh` + `prompts/{ecc-prompts,ecc-skills,search-prompts,plan-approval-prompts,evolution-guide}.md`). Aceita a raiz do repo OU a pasta `.claude/skills/...` (que espelha scripts/prompts por symlink). `--root <dir>` (default: a propria casa da skill), `--json`, `--quiet`. Exit 0 completo · 1 faltando itens · 2 uso. Detecta o estado "so SKILL.md, sem scripts" que faz a FASE 0 abortar com "PARE: do-context.sh nao encontrado". |

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
| `surf doctor` | O PORTAO. Exit 0/1 = prossiga, 78 = sem chave Brave valida, 127 = pacote ausente |

Brave e o unico backend: nao ha Tavily, Parallel, Wikipedia, DuckDuckGo,
provedor de reserva nem tier sem chave. Nao existe modo degradado -- ou ha
chave valida e a pesquisa funciona, ou a execucao para.

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
| `test-contencao.sh` | Testes de aceitacao do MODO CONTIDO (A1..A20 + A22/A23/A25/A26/A27/A28/A29/A30/A31 + A32/A33/A34, 85 assercoes — plano v3.3.0 + F4-06/F4-07). Cria fixtures (repo principal + worktree irma + worktree de terceiro) e verifica invariantes: deteccao de MODE, fronteira BASE_DIR, isolamento de worktrees, protecao contra operacoes em branches de terceiros. A23: merge com CONFLITO -> resolucao na filha -> re-merge automatico (F4-07.2). A27: lab com espaco e acento no nome (ponta a ponta). A28/A29: exits 6/7/9 da FASE 0 (indice sujo, aspa simples no branch, symref corrompido, path com newline, colisao de PREFIXO do namespace). A30: flock — dois marks paralelos sem lost update. A31: kind=validation ciclo completo. A33: falha tardia de gate de snapshot (undo da 1a filha com HEAD avancado — revert exato, 2a intacta, ref de undo arquivada, re-merge restaura) — cobre o A21 do plano. A34: gate-pending bloqueia o fim de onda (sweep sai != 0 ate mark MERGED). A32 cobre o A24 do plano (wave-files apos 2 squashes). Portavel: resolve o path da skill dinamicamente e limpa os labs em /tmp via trap. |
| `test-plan-approval.sh` | Testes de aceitacao do PORTAO DE APROVACAO DO PLANO (G1..G9 + P1..P28 + DC1..DC3, 133 assercoes — 3 falhas de ambiente macOS conhecidas: timeout(1) ausente). Tudo mockado num PATH temporario: um `plannotator` FAKE fiel ao contrato real (usage em `annotate` sem argumento, `{"decision":"approved"|"dismissed"|"annotated"}` em uma linha, exit SEMPRE 0) e um `curl` FAKE que finge o instalador. SEM rede, SEM navegador, SEM instalar nada. Cobre: resolucao do binario (PATH, ~/.local/bin, DO_PLANNOTATOR_BIN), sonda de capacidade rejeitando binario velho, instalacao com --minimal --non-interactive, recusa de sobrescrever instalacao existente (G9), os seis exit codes de `round`, argv exato, imutabilidade do snapshot, deriva de titulo, orcamento de revisoes, PLANNOTATOR_SHARE=disabled por default, prioridade de deteccao de harness, round-trip de feedback com aspas/newline/acento/backslash, ruido antes do JSON, `annotated` com feedback vazio degradando para `dismissed`, contencao de escrita, idempotencia via `approved`, ausencia de jq E python3, e os DO_PLAN_* no ENV_FILE. |
| `test-surf-gate.sh` | Testes do PORTAO DA SURF e do orcamento `--sub-agents` (G1..G8, 46 assercoes). Substitui o `test-search.sh`, que testava o sistema de busca removido. Tudo mockado em PATH temporario, SEM rede, SEM quota, SEM chave: G1 surf ausente -> SURF_GATE=127; G2 `surf doctor` saindo 78, distinto de 1 e 2; G3 exit 1 (skills do surf nao symlinkadas) = prossiga; G4 portao verde; G5 aritmetica `max(1, floor(N/R))` e a prova de que a soma da onda nunca passa de N; G6 `--sub-agents` fora de 1..20 -> exit 2; G7 regressao de arquitetura (nenhuma referencia viva aos scripts removidos, a DDG, a `surf-free-skill` ou as flags que nao existem); G8 o SKILL.md ainda declara o contrato que a suite testa. |

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
              +-- exit 1   rodou e nao achou nada (registre o vazio, siga)
              +-- exit 2   o comando esta errado (corrija)
              +-- exit 78  sem chave Brave valida -> PARA (e configuracao)
              +-- exit 143 o harness matou por timeout
```

O orquestrador roda o PORTAO antes de cada onda:

```bash
. '<ENV_FILE>'
if command -v surf-search-normal >/dev/null 2>&1; then
  surf doctor >/dev/null 2>&1; echo "SURF_GATE=$?"
else
  echo "SURF_GATE=127"
fi
```

`surf doctor` e o portao certo porque `keys list` nunca sai 78 (o gate e
pulado para ele) e `--version` retorna antes do preflight. Ele e offline no
caminho comum (~0,04 s; o veredito do surf fica em cache por 7 dias) e mascara
as chaves. **Nunca** use `surf-research-skill keys list --json` como
diagnostico.

### Orcamento de simultaneidade: os dois tetos SOMAM

Seja `N` o teto global do surf (`surf-sub-agents=N` na invocacao, default 10,
faixa 1..20) e `R` a quantidade de sub-agentes da onda que pesquisam. Cada um
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

