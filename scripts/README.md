# Scripts -- deep-orchestrator

Diretorio de scripts executaveis do deep-orchestrator. Cada script tem uma funcao
especifica no ciclo de orquestracao. A ordem de execucao e ditada pelas FASES do
orquestrador (0 a 4), com `do-context.sh` sempre rodando primeiro.

---

## Core (orquestracao)

| Script | Proposito | FASE |
|---|---|---|
| `do-context.sh` | Resolve MODE (normal/contido), BASE_DIR, BASE_BRANCH, CHILD_ROOT, BRANCH_NS e grava arquivo de estado que TODO script posterior deve sourcear. Detecta se o cwd esta dentro de uma git worktree vinculada e delimita a RAIZ-DE-MUNDO. Grava DO_MAX_PARALLEL (cap de paralelismo por onda — F3-02; default 20, prefixo max-parallel=N na invocacao; exit 2 se nao for inteiro positivo). | FASE 0 |
| `do-wt.sh` | Gerencia todo o ciclo de vida das worktrees-filhas: cria (new, kinds feature/test/validation/fix/prep/integration), faz squash-merge (merge), desfaz merge (undo — funciona com HEAD avancado, para falha tardia de gate de snapshot, e arquiva o commit em refs/do-archive/$RUN_ID/undo-<nome>), remove (remove), arquiva e apaga branch (drop-branch), encerra onda (sweep — DETECTA status=gate-pending: imprime aviso e sai != 0, o fim de onda nao fecha com gate de snapshot pendente), verifica contencoes (verify), consulta status (status), altera estado de filha (mark — statuses: ACTIVE/MERGED/REMOVED/BLOCKED/ORPHANED/REVERTED/gate-pending), estagia delta da onda (stage-delta), e lista arquivos tocados pela onda (wave-files — aceita a 1a filha MERGED da onda; se a filha passada nao foi mergeada, resolve automaticamente pela filha MERGED de menor pre_merge_sha do mesmo prefixo ondaN-). | FASE 3-4 |

## Busca (search)

| Script | Proposito | Tier |
|---|---|---|
| **`search.sh`** | Interface UNIFICADA de busca do deep-orchestrator. Smart wrapper com cadeia de fallback automatica em 3 tiers. Interface CLI identica ao `brave-search.sh` para backward compatibility. Este e o script que sub-agentes devem usar. Exit codes: 0 (resultados), 1 (sem resultados em TODA a cadeia ou erro de busca), 2 (configuracao/uso). | T1 -> T2 -> T3 |
| **`search-parallel.sh`** | Buscas em PARALELO para LOTES (decisao D3): `--batch <arquivo>` (uma query por linha) ou queries posicionais multiplas; uma chamada `search.sh` por query em background (sem teto de quantidade), jitter de disparo 0-2s por job, backoff exponencial com jitter (1s/2s/4s) em HTTP 429, cache intra-run de queries identicas, e relatorio agregado DEDUPLICADO por URL (query -> tier -> URLs). Exit codes: 0 (>=1 query com resultado), 1 (todas falharam/vazias), 2 (uso). NUNCA chame search.sh em loop — use este script. | PARALELO |
| `brave-search.sh` | Wrapper da Brave Search API. Exibe a funcao `search_brave_api()` como funcao sourceable (usada como Tier 2 do `search.sh`). Ainda funciona standalone com interface similar ao surf-search-normal (--task, --goal, --insights, --deliverable, --brief-file). Suporta evolucao de queries com deduplicacao por URL. | T2 |
| `check-search-credits.sh` | Verificador multi-tier pre-onda. Verifica surf-skill (Tier 1, so AVAILABLE com keys.json do surf presente e nao-vazio — senao DEGRADED), Brave API (Tier 2) e DuckDuckGo keyless (Tier 3). Substitui `check-brave-credits.sh`. Exit codes: 0 (Tier 1 ou 2 ok), 1 (apenas Tier 3), 2 (nada disponivel ou deps ausentes). Opcoes: --fail-fast, --json. | -- |
| ~~`check-brave-credits.sh`~~ | **(DEPRECATED)** Verificador antigo exclusivo da Brave Search API. Na resposta REAL da Brave o header X-Credit-Remaining nao existe (verificado 14/08/2026) — os creditos vem do 2o valor de X-RateLimit-Remaining (par "por segundo, por mes"; 2o valor = quota mensal). Suporta deteccao de assinatura ativa e cache de 10 min. Use `check-search-credits.sh`. | -- |

## Testes

| Script | Proposito |
|---|---|
| `test-contencao.sh` | Testes de aceitacao do MODO CONTIDO (A1..A20 + A22/A25/A26 + A32/A33/A34, 63 assercoes — plano v3.3.0). Cria fixtures (repo principal + worktree irma + worktree de terceiro) e verifica invariantes: deteccao de MODE, fronteira BASE_DIR, isolamento de worktrees, protecao contra operacoes em branches de terceiros. A33: falha tardia de gate de snapshot (undo da 1a filha com HEAD avancado — revert exato, 2a intacta, ref de undo arquivada, re-merge restaura). A34: gate-pending bloqueia o fim de onda (sweep sai != 0 ate mark MERGED). Portavel: resolve o path da skill dinamicamente e limpa o lab em /tmp via trap. |
| `test-search.sh` | Testes de aceitacao da cadeia de busca (T1..T12 + PAR-1..3, 64 assercoes — F3-05/F3-06). Tudo mockado em PATH temporario (bins fake), SEM rede: T1 argv do Tier 1 (--budget-ms, sem --timeout/--dev-mode); T2 saida parcial + falha do Tier 1 nao polui o stdout; T3 envelope --json unificado (Tier 1 normalizado); T4 --max-evolutions no Tier 2 (loop com mock, credits = 2o valor de X-RateLimit-Remaining); T5 deps ausentes -> exit 2; T6 cadeia vazia -> exit 1; T7 HTTP 403 do DDG = REACHABLE; T8 cache + --fail-fast do check-brave-credits; T9 query com '*' nao expande glob; T10 >1 posicional e '--'; T11 --timeout sem valor; T12 trap RETURN nao corrompe exit code; PAR-1 20 queries paralelas (tempo ~1-2 jobs, dedup por URL); PAR-2 backoff 429; PAR-3 cache intra-run de queries identicas. Portavel e isolado (dir proprio por caso, lab limpo via trap). |

---

## Fluxo de busca (search flow)

```
search.sh (interface unica recomendada)
  |
  +-- [Tier 1] surf-skill (surf-search-normal / surf-free-skill)
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
  +-- [Tier 1] surf-skill disponivel?  -> exit 0 (pesquisa completa)
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
