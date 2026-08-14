# Scripts -- deep-orchestrator

Diretorio de scripts executaveis do deep-orchestrator. Cada script tem uma funcao
especifica no ciclo de orquestracao. A ordem de execucao e ditada pelas FASES do
orquestrador (0 a 4), com `do-context.sh` sempre rodando primeiro.

---

## Core (orquestracao)

| Script | Proposito | FASE |
|---|---|---|
| `do-context.sh` | Resolve MODE (normal/contido), BASE_DIR, BASE_BRANCH, CHILD_ROOT, BRANCH_NS e grava arquivo de estado que TODO script posterior deve sourcear. Detecta se o cwd esta dentro de uma git worktree vinculada e delimita a RAIZ-DE-MUNDO. | FASE 0 |
| `do-wt.sh` | Gerencia todo o ciclo de vida das worktrees-filhas: cria (new), faz squash-merge (merge), desfaz merge (undo), remove (remove), arquiva e apaga branch (drop-branch), encerra onda (sweep), verifica contencoes (verify), consulta status (status), altera estado de filha (mark), estagia delta da onda (stage-delta), e lista arquivos tocados (wave-files). | FASE 3-4 |

## Busca (search)

| Script | Proposito | Tier |
|---|---|---|
| **`search.sh`** | Interface UNIFICADA de busca do deep-orchestrator. Smart wrapper com cadeia de fallback automatica em 3 tiers. Interface CLI identica ao `brave-search.sh` para backward compatibility. Este e o script que sub-agentes devem usar. | T1 -> T2 -> T3 |
| `brave-search.sh` | Wrapper da Brave Search API. Exibe a funcao `search_brave_api()` como funcao sourceable (usada como Tier 2 do `search.sh`). Ainda funciona standalone com interface similar ao surf-search-normal (--task, --goal, --insights, --deliverable, --brief-file). Suporta evolucao de queries com deduplicacao por URL. | T2 |
| `check-search-credits.sh` | Verificador multi-tier pre-onda. Verifica surf-skill (Tier 1), Brave API (Tier 2) e DuckDuckGo keyless (Tier 3). Substitui `check-brave-credits.sh`. Exit codes: 0 (Tier 1 ou 2 ok), 1 (apenas Tier 3), 2 (nada disponivel). Opcoes: --fail-fast, --json. | -- |
| ~~`check-brave-credits.sh`~~ | **(DEPRECATED)** Verificador antigo exclusivo da Brave Search API. Verifica creditos via header X-Credit-Remaining, suporta deteccao de assinatura ativa e cache de 10 min. Use `check-search-credits.sh`. | -- |

## Testes

| Script | Proposito |
|---|---|
| `test-contencao.sh` | Testes de aceitacao do MODO CONTIDO (A1..A20 + A22/A25/A26, 57 assercoes — expande para A34 nas fases seguintes do plano v3.3.0). Cria fixtures (repo principal + worktree irma + worktree de terceiro) e verifica invariantes: deteccao de MODE, fronteira BASE_DIR, isolamento de worktrees, protecao contra operacoes em branches de terceiros. Portavel: resolve o path da skill dinamicamente e limpa o lab em /tmp via trap. |

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
        Fallback sem chave. Sempre funciona enquanto houver rede.
        Qualidade limitada mas garante que a busca nunca falha completamente.
```

## Verificacao pre-onda (check-search-credits.sh)

```
check-search-credits.sh
  |
  +-- [Tier 1] surf-skill disponivel? -> exit 0 (pesquisa completa)
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
