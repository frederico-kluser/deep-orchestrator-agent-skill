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
| `sync-global-skill.sh` | Publica a skill para todos os agentes da maquina por SYMLINK: ${CLAUDE_CONFIG_DIR:-~/.claude}/skills, ~/.agents/skills (pi/jcode/opencode), ~/.jcode/skills e ~/.pi/agent/skills. Existe porque alguns agentes importam skills POR COPIA, e copia congela a versao do dia da importacao (verificado: ~/.jcode/skills/deep-orchestrator-agent-skill ficou em 3.1.0 com a skill viva em 3.4.0 -- rodar por la executava um orquestrador de duas versoes atras). Toca EXCLUSIVAMENTE a entrada `deep-orchestrator-agent-skill`; so substitui um diretorio depois de confirmar que ele tem SKILL.md com `name: deep-orchestrator-agent-skill`; guarda a copia antiga em `.bak-<data>`; nao cria diretorio-pai de agente que nao existe. Chamado pelo hook SessionStart do Claude Code. Opcoes: --quiet, --dry-run, --strict. Exit 0 sempre (1 so com --strict). |
| `check-install.sh` | Prova de que UMA INSTALACAO da skill esta COMPLETA: verifica o contrato de instalacao num diretorio (SKILL.md com `name:` correto + ferramentas executaveis `scripts/{do-context,do-wt,search,search-parallel,check-search-credits,check-plannotator,plan-approval,sync-global-skill}.sh` + `prompts/{ecc-prompts,ecc-skills,search-prompts,plan-approval-prompts}.md`). Aceita a raiz do repo OU a pasta `.claude/skills/...` (que espelha scripts/prompts por symlink). `--root <dir>` (default: a propria casa da skill), `--json`, `--quiet`. Exit 0 completo · 1 faltando itens · 2 uso. Detecta o estado "so SKILL.md, sem scripts" que faz a FASE 0 abortar com "PARE: do-context.sh nao encontrado". |

## Auto-evolucao (evolucao continua — v3.7.0)

| Script | Proposito |
|--------|-----------|
| `evolve-skill.sh` | Motor de auto-evolucao: add/search/diff/apply/consolidate/status do LEARNINGS.md da propria skill. |

`evolve-skill.sh` persiste a memoria episodica da skill (contexto NAO revisado): ao
fim de cada execucao o orquestrador coleta aprendizados (retrospectiva), filtra pelas
regras de `prompts/evolution-guide.md` e anexa via `add` — lote atomico com validacao
(campos obrigatorios, enums, scan de segredos, dedupe). `search` consulta; `diff` mostra
o pendente; `apply` commita (default inteligente: so LEARNINGS.md/learnings_archive.md
mudaram -> direto no branch atual; outro path da allowlist -> branch evolve/YYYY-MM-DD;
nunca push); `consolidate` deduplica, marca contradicoes (nunca apaga), poda volateis e
aplica o orcamento (GC). Use ao terminar uma execucao com surpresas/correcoes; promocao
ao corpo da skill exige evidencia e diff revisavel. Exit codes: 0 ok · 1 search sem
resultados · 2 uso/ambiente (candidato invalido, segredo, copia sem git, lock ocupado) ·
3 identidade errada do SKILL.md · 4 escrita fora da allowlist.

## Busca (search)

| Script | Proposito | Tier |
|---|---|---|
| **`search.sh`** | Interface UNIFICADA de busca do deep-orchestrator-agent-skill. Smart wrapper com cadeia de fallback automatica em 3 tiers. Interface CLI identica ao `brave-search.sh` para backward compatibility. Este e o script que sub-agentes devem usar. Exit codes: 0 (resultados), 1 (sem resultados em TODA a cadeia ou erro de busca), 2 (configuracao/uso). | T1 -> T2 -> T3 |
| **`search-parallel.sh`** | Buscas em PARALELO para LOTES (decisao D3): `--batch <arquivo>` (uma query por linha) ou queries posicionais multiplas; uma chamada `search.sh` por query em background (sem teto de quantidade), jitter de disparo 0-2s por job, backoff exponencial com jitter (1s/2s/4s) em HTTP 429, cache intra-run de queries identicas, e relatorio agregado DEDUPLICADO por URL (query -> tier -> URLs). Exit codes: 0 (>=1 query com resultado), 1 (todas falharam/vazias), 2 (uso). NUNCA chame search.sh em loop — use este script. | PARALELO |
| `brave-search.sh` | Wrapper da Brave Search API. Exibe a funcao `search_brave_api()` como funcao sourceable (usada como Tier 2 do `search.sh`). Ainda funciona standalone com interface similar ao surf-search-normal (--task, --goal, --insights, --deliverable, --brief-file). Suporta evolucao de queries com deduplicacao por URL. | T2 |
| `check-search-credits.sh` | Verificador multi-tier pre-onda. Verifica surf-agent-skill (Tier 1, so AVAILABLE com keys.json do surf presente e nao-vazio — senao DEGRADED), Brave API (Tier 2) e DuckDuckGo keyless (Tier 3). Substitui `check-brave-credits.sh`. Exit codes: 0 (Tier 1 ou 2 ok), 1 (apenas Tier 3), 2 (nada disponivel ou deps ausentes). Opcoes: --fail-fast, --json. | -- |
| ~~`check-brave-credits.sh`~~ | **(DEPRECATED)** Verificador antigo exclusivo da Brave Search API. Na resposta REAL da Brave o header X-Credit-Remaining nao existe (verificado 14/08/2026) — os creditos vem do 2o valor de X-RateLimit-Remaining (par "por segundo, por mes"; 2o valor = quota mensal). Suporta deteccao de assinatura ativa e cache de 10 min. Use `check-search-credits.sh`. | -- |

## Ferramentas (geracao)

| Script | Proposito | FASE |
|---|---|---|
| `—` | **[v3.6.0]** A geração do EXPLAINER.html é DELEGADA a sub-agente (fluxo html-explainer-agent-skill — brief didático + render visual-explainer; sem limite de tempo; salvo em $BASE_DIR/EXPLAINER.html). Não há script dedicado. O passo 4 do COMMIT-FINAL no SKILL.md descreve o ritual. | FASE 4 |

## Testes

| Script | Proposito |
|---|---|
| `test-contencao.sh` | Testes de aceitacao do MODO CONTIDO (A1..A20 + A22/A23/A25/A26/A27/A28/A29/A30/A31 + A32/A33/A34, 85 assercoes — plano v3.3.0 + F4-06/F4-07). Cria fixtures (repo principal + worktree irma + worktree de terceiro) e verifica invariantes: deteccao de MODE, fronteira BASE_DIR, isolamento de worktrees, protecao contra operacoes em branches de terceiros. A23: merge com CONFLITO -> resolucao na filha -> re-merge automatico (F4-07.2). A27: lab com espaco e acento no nome (ponta a ponta). A28/A29: exits 6/7/9 da FASE 0 (indice sujo, aspa simples no branch, symref corrompido, path com newline, colisao de PREFIXO do namespace). A30: flock — dois marks paralelos sem lost update. A31: kind=validation ciclo completo. A33: falha tardia de gate de snapshot (undo da 1a filha com HEAD avancado — revert exato, 2a intacta, ref de undo arquivada, re-merge restaura) — cobre o A21 do plano. A34: gate-pending bloqueia o fim de onda (sweep sai != 0 ate mark MERGED). A32 cobre o A24 do plano (wave-files apos 2 squashes). Portavel: resolve o path da skill dinamicamente e limpa os labs em /tmp via trap. |
| `test-plan-approval.sh` | Testes de aceitacao do PORTAO DE APROVACAO DO PLANO (G1..G9 + P1..P28 + DC1..DC3, 111 assercoes). Tudo mockado num PATH temporario: um `plannotator` FAKE fiel ao contrato real (usage em `annotate` sem argumento, `{"decision":"approved"|"dismissed"|"annotated"}` em uma linha, exit SEMPRE 0) e um `curl` FAKE que finge o instalador. SEM rede, SEM navegador, SEM instalar nada. Cobre: resolucao do binario (PATH, ~/.local/bin, DO_PLANNOTATOR_BIN), sonda de capacidade rejeitando binario velho, instalacao com --minimal --non-interactive, recusa de sobrescrever instalacao existente (G9), os seis exit codes de `round`, argv exato, imutabilidade do snapshot, deriva de titulo, orcamento de revisoes, PLANNOTATOR_SHARE=disabled por default, prioridade de deteccao de harness, round-trip de feedback com aspas/newline/acento/backslash, ruido antes do JSON, `annotated` com feedback vazio degradando para `dismissed`, contencao de escrita, idempotencia via `approved`, ausencia de jq E python3, e os DO_PLAN_* no ENV_FILE. |
| `test-search.sh` | Testes de aceitacao da cadeia de busca (T1..T12 + PAR-1..3, 64 assercoes — F3-05/F3-06). Tudo mockado em PATH temporario (bins fake), SEM rede: T1 argv do Tier 1 (--budget-ms, sem --timeout/--dev-mode); T2 saida parcial + falha do Tier 1 nao polui o stdout; T3 envelope --json unificado (Tier 1 normalizado); T4 --max-evolutions no Tier 2 (loop com mock, credits = 2o valor de X-RateLimit-Remaining); T5 deps ausentes -> exit 2; T6 cadeia vazia -> exit 1; T7 HTTP 403 do DDG = REACHABLE; T8 cache + --fail-fast do check-brave-credits; T9 query com '*' nao expande glob; T10 >1 posicional e '--'; T11 --timeout sem valor; T12 trap RETURN nao corrompe exit code; PAR-1 20 queries paralelas (tempo ~1-2 jobs, dedup por URL); PAR-2 backoff 429; PAR-3 cache intra-run de queries identicas. Portavel e isolado (dir proprio por caso, lab limpo via trap). |

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

## Fluxo de busca (search flow)

```
search.sh (interface unica recomendada)
  |
  +-- [Tier 1] surf-agent-skill (surf-search-normal / surf-free-skill)
  |     AI-powered multi-provider. Melhor qualidade.
  |     Se falhar ou indisponivel, cai para Tier 2.
  |
  +-- [Tier 2] Brave Search API (via search_brave_api() sourced de brave-search.sh)
  |     API direta com chave de assinatura. Qualidade boa.
  |     Se falhar ou sem creditos, cai para Tier 3.
  |
  +-- [Tier 3] DuckDuckGo Instant Answer API (keyless)
        Fallback sem chave. Conectividade garantida enquanto houver rede,
        mas COBERTURA LIMITADA: e Instant Answer, nao busca full-text —
        queries genericas costumam voltar HTTP 202 com corpo vazio
        (nesse caso o search.sh sai com exit 1 e relatorio vazio).
```

### Tier 0 — pesquisa nativa do harness (Claude Code)

Quando o harness que hospeda a skill expoe ferramentas de busca NATIVAS
(Claude Code: `WebSearch`/`WebFetch`), sub-agentes podem usa-las DIRETAMENTE —
sem chave e sem script. O `search.sh` (Tier 1 -> 2 -> 3) continua sendo a
interface unificada e o fallback deterministico para harnesses sem ferramenta
nativa (pi, jcode, opencode). O Tier 0 NAO entra no `check-search-credits.sh`:
a verificacao pre-onda cobre a cadeia propria (Tiers 1-3).

## Fluxo paralelo (search-parallel.sh)

```
search-parallel.sh --batch <arquivo> | <query1> <query2> ...
  |
  |-- dedup intra-run por hash da query (queries identicas = 1 job real)
  |-- 1 job em background POR QUERY (sem teto; cada job grava em arquivo proprio
  |     sob um dir temporario mktemp -d)
  |      job: jitter de disparo 0-2s (PARALLEL_JITTER_MAX)
  |           -> search.sh --json <query>  (fallback 3-tier interno)
  |           -> HTTP 429 no stderr? backoff exponencial 1s/2s/4s + jitter 0-1s
  |-- wait
  |-- agregacao: queries[] (query -> provider -> URLs) + results[] DEDUP por URL
  |     (com a lista de queries que trouxeram cada URL) + failures[]
  |-- exit 0 = >=1 query com resultado | 1 = todas falharam/vazias | 2 = uso
```

## Verificacao pre-onda (check-search-credits.sh)

```
check-search-credits.sh
  |
  +-- [Tier 1] surf-agent-skill disponivel?  -> exit 0 (pesquisa completa)
  |     (AVAILABLE so com ~/.config/surf/keys.json presente e nao-vazio;
  |      sem keys -> DEGRADED)
  +-- [Tier 2] Brave API funcional?    -> exit 0 (pesquisa completa)
  +-- [Tier 3] DDG keyless acessivel?  -> exit 1 (pesquisa limitada)
  +-- NADA disponivel                  -> exit 2 (erro critico)
```

## Migracao: brave-search.sh -> search.sh

- `brave-search.sh` **CONTINUA FUNCIONANDO** standalone -- nao foi removido
- `search.sh` e o substituto com **MAIS provedores** e **fallback automatico**
- Sub-agentes devem usar `search.sh` como interface unica de busca
- `check-brave-credits.sh` -> substituido por `check-search-credits.sh`
- A interface CLI do `search.sh` e identica a do `brave-search.sh` (--task, --goal, --insights, --deliverable, --brief-file, --count, --max-evolutions), garantindo backward compatibility para scripts e sub-agentes existentes

---

## Roadmap

- **Evolucao candidata do Tier 2 — Brave LLM Context endpoint:** a doc oficial
  da Brave recomenda o endpoint LLM Context (resposta token-eficiente para
  maquinas/agentes, ~$5/1K) no lugar do Web Search para uso por agentes.
  Candidato a evoluir o Tier 2 da cadeia (`brave-search.sh` /
  `search_brave_api()`): continua sendo Brave — compativel com a decisao D3
  (nenhum provedor novo entra na cadeia). FORA do escopo atual — registro
  para nao esquecer.
