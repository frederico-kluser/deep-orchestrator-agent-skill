# deep-orchestrator v3.3.0

![Versão](https://img.shields.io/badge/version-3.3.0-00d4ff)

Orquestrador autônomo multi-agente para Claude Code — planeja, divide em ondas **ILIMITADAS** (com recálculo dinâmico), cria worktrees isoladas, delega, revisa adversarialmente, integra via squash-merge um a um com gate em snapshot de integração (worktree efêmera `int-ondaN-*`, fora da seção crítica), verifica o sistema de busca 3-tier antes de cada onda, e commita tudo ao final **sem perguntar nada ao usuário**.

## Glossário (leia antes do resto)

| Termo | O que é |
|-------|---------|
| **`$SKILL_HOME`** | A **casa da skill**: `scripts/`, `prompts/`, `templates/`. Fica fora do projeto-alvo e é **somente leitura/execução** durante uma execução. Caminhos escritos como `$SKILL_HOME/...` são daqui; caminhos sem prefixo são do repositório-alvo. |
| **RAIZ-DE-MUNDO (`$BASE_DIR`)** | `git rev-parse --show-toplevel` no diretório de invocação. Se você invocou dentro de uma git worktree vinculada, é a **worktree** — não o projeto principal. É a fronteira de escrita. |
| **`$BASE_BRANCH`** | O branch em HEAD na raiz-de-mundo. É o **único** alvo de integração. Nunca é resolvido por convenção (main/master). |
| **`$MAIN_ROOT`** | O checkout principal do repositório. Em MODO CONTIDO é **zona proibida**. |
| **WORKTREE-FILHA** | Uma worktree por sub-agente, criada sob `$CHILD_ROOT`, com branch `$BRANCH_NS/<nome>`. |

## MODO CONTIDO

Se a skill for invocada com o cwd **dentro de uma git worktree vinculada**, ela entra em MODO CONTIDO e trata essa worktree como raiz-de-mundo:

- os squash-commits vão para o **branch da worktree**, jamais para `main`/`master`;
- nenhum arquivo é escrito no projeto principal — `do-wt.sh verify` confere ao fim de cada onda o HEAD, a working tree (incluindo arquivos ignorados, para pegar um `node_modules/` nascendo lá) e o config local contra o baseline da FASE 0. A prova é de **autoria**, não de imutabilidade: se o principal mudou mas nenhum commit desta execução é alcançável a partir do HEAD dele, é ALERTA (você trabalhando em paralelo), não violação;
- as worktrees-filhas nascem num **container irmão oculto** `<pai>/.<worktree>-do/<RUN_ID>/` (fallback automático para `<worktree>/.deep-orchestrator/worktrees/` quando o irmão cairia dentro de outro repositório git; force com `DO_FORCE_NESTED=1`);
- os branches vivem num namespace exclusivo por execução (`do/<slug>/<RUN_ID>/<nome>`), então duas orquestrações simultâneas não se apagam;
- a limpeza usa **allowlist** (`owned.tsv` + lock nativo do git), nunca varredura: `git worktree list` e `git branch --list` enxergam worktrees de outras sessões, e `git worktree prune` é proibido;
- a sujeira que já existia na worktree antes da execução é **do usuário** e nunca entra nos commits (`do-wt.sh stage-delta`).

O único vestígio compartilhado aceito é o registro administrativo das filhas em `$GIT_COMMON_DIR/worktrees/`, que o próprio git cria e é inevitável.

Em MODO NORMAL (invocação na árvore principal) valem as mesmas invariantes, com `$CHILD_ROOT` em `<pai>/<repo>-worktrees/<RUN_ID>/`.

## Novidades na v3.3.0

- **Gate em snapshot de integração (F3-01)**: o squash-merge é atômico e o gate (build + testes + linter) sai da seção crítica — roda em background numa worktree efêmera `int-ondaN-<nome>` (kind=integration, registrada no owned.tsv) criada no SHA pós-merge. Merges seguem em sequência; a limpeza de cada filha e o fim da onda aguardam o respectivo gate de snapshot (`status=gate-pending` no owned.tsv; o `do-wt.sh sweep` detecta gate-pending, avisa e sai != 0). Falha tardia: `do-wt.sh undo <nome>` reverte exatamente aquele squash com HEAD avançado, arquivando o commit em `refs/do-archive/$RUN_ID/undo-<nome>`. **Decisão D1**: builds duplicados (snapshot + validação + gate final) são esperados.
- **DO_MAX_PARALLEL (F3-02)**: prefixo `max-parallel=N` na invocação (`/deep-orchestrator max-parallel=N <tarefa>`) — o orquestrador exporta `DO_MAX_PARALLEL` antes da FASE 0; ausente, default 20 (CAP protetor; 3-5 é o ponto ótimo recomendado pela Anthropic). Orçamento: features por onda ≤ DO_MAX_PARALLEL; in-flight total ≤ 2×DO_MAX_PARALLEL; ondas maiores viram batches sequenciais com a própria barreira.
- **Gate definido uma vez (F3-03)**: a FASE 1 detecta e registra no TASK_PLAN.md o trio exato `GATE_BUILD`/`GATE_TEST`/`GATE_LINT` do projeto-alvo (package.json/Makefile/pyproject.toml/Cargo.toml/go.mod); toda invocação de gate referencia esse trio, com cwd conforme o contexto (snapshot, validação ou `$BASE_DIR` no gate final).
- **Lockfile como singleton (F3-04)**: manifesto + lockfile entram no mapa de propriedade como recurso singleton — no máximo 1 agente por onda adiciona dependências; os demais registram "deps pendentes: <pacote@versão>" no handoff e a adição acontece no COMMIT PREP da onda seguinte.
- **Tiering de modelos por papel (F3-09)**: quando o harness permite, agentes de teste e revisores adversariais rodam em modelo médio, REVISOR DE PLANO e síntese final em modelo forte, features no padrão; regra de escala: ≤2 sub-tarefas pequenas e independentes não geram fan-out extra.
- **Testes**: `scripts/test-contencao.sh` — 63 asserções (A33: falha tardia de gate com undo de HEAD avançado; A34: gate-pending bloqueia o fim de onda).

## Novidades na v3.2.0

- **MODO CONTIDO** (acima) + **FASE 0 — DELIMITAR O MUNDO**: `scripts/do-context.sh` detecta worktree vinculada, resolve a fronteira e grava o arquivo de estado que toda chamada Bash sourceia.
- **Guardas em código, não em prosa**: `scripts/do-wt.sh` concentra criação, merge, undo, remoção, limpeza e prova de contenção. Cada operação destrutiva recusa alvos que não estejam registrados nesta execução.
- **Regra de dependências (R9)**: instalação permitida se necessária, sempre com cwd na worktree-filha, em modo congelado e com `HUSKY=0` (um postinstall de husky grava `core.hooksPath` no `.git` compartilhado). Cache global do usuário é permitido; escopo global de instalação é proibido.
- **Testes de regressão**: `scripts/test-contencao.sh` — 63 asserções cobrindo detecção de modo, colocação, limpeza segura, worktrees de terceiros, preservação da sujeira do usuário, paths com acento e espaço, guarda de índice sujo, distinção entre vazamento nosso e trabalho do usuário no projeto principal, falha tardia de gate (A33) e gate-pending (A34).

## Novidades na v3.0.0

- **Ondas ilimitadas** com recálculo dinâmico — após cada onda, um sub-agente REVISOR DE PLANO analisa os handoffs e o TASK_PLAN.md, propõe novas sub-tarefas ou declara CONVERGÊNCIA. O ciclo só termina por convergência declarada, nunca por um número fixo de ondas.
- **Busca interna Brave** (`$SKILL_HOME/scripts/brave-search.sh`) — CLI próprio sobre a Brave Search API que substitui o `surf-search-normal`; não depende mais do `surf-research-skill` nem do CLI `surf-ai`.
- **Verificação de créditos** antes de cada onda (`$SKILL_HOME/scripts/check-brave-credits.sh`) — sem créditos, o orquestrador para e informa o usuário (única exceção à autonomia total).
- **ECC Prompts integrados** — 7 templates de prompt (`$SKILL_HOME/prompts/ecc-prompts.md`) + 7 skills portados do ECC (`$SKILL_HOME/prompts/ecc-skills.md`), incluindo Security Review (AgentShield), Planning Prompt (Plan First) e Prompt Defense Baseline.
- **Prompts de busca para dev** (`$SKILL_HOME/prompts/search-prompts.md`) — 8 categorias de busca, sistema de evolução de perguntas (question evolution) e prompts por domínio.
- **HTML Explainer** automático ao final de cada execução (`$SKILL_HOME/templates/html-explainer.html`) — de-para de todas as mudanças em 6 abas, salvo como `EXPLAINER.html` na raiz da worktree em que a skill foi invocada.

## Como funciona

O deep-orchestrator nunca escreve código. Ele atua como arquiteto-distribuidor: projeta o plano, divide o trabalho em ondas topológicas (quantas forem necessárias — o REVISOR DE PLANO recalcula após cada onda), cria e batiza worktrees isoladas do Git (uma por sub-agente), dispara os agentes em paralelo, aplica revisão adversarial, integra cada resultado via `git merge --squash` um a um — o gate (o trio GATE_BUILD/GATE_TEST/GATE_LINT registrado na FASE 1) roda em background numa worktree de snapshot efêmera `int-ondaN-*`, fora da seção crítica — remove worktree + branch + commits intermediários ao fim de cada onda (a limpeza de cada filha aguarda o verde do snapshot), e commita tudo ao final.

```
ANALYZE  →  PLAN  →  EXECUTE-ONDA (repeat, ILIMITADO)  →  COMMIT-FINAL
```

### Fases

| Fase | Nome | O que faz |
|------|------|-----------|
| 0 | **DELIMITAR O MUNDO** | Roda `$SKILL_HOME/scripts/do-context.sh`: detecta se o cwd está numa worktree vinculada, resolve `$BASE_DIR`, `$BASE_BRANCH`, `$MAIN_ROOT`, `$CHILD_ROOT`, `$BRANCH_NS` e `$SKILL_HOME`, e captura os baselines de contenção. Aborta com mensagem acionável se não houver branch de integração |
| 1 | **ANALYZE** | Lê o prompt, mapeia a estrutura do repositório, identifica subsistemas, classifica greenfield/brownfield, localiza golden masters, verifica que `BRAVE_API_KEY` está definida e que há créditos (`$SKILL_HOME/scripts/check-brave-credits.sh --fail-fast`) |
| 2 | **PLAN** | Decompõe a tarefa em sub-tarefas atômicas, identifica o grafo de dependências, organiza em ondas topológicas (número NÃO fixo — o plano é um ponto de partida), define o mapa de propriedade de arquivos, batiza cada worktree, escreve os prompts de delegação, publica o TASK_PLAN.md |
| 3 | **EXECUTE-ONDA** | Para cada onda: verificação de créditos → commit prep (se necessário) → cria worktrees → dispara agentes em paralelo (escalonado) → barreira → **recálculo dinâmico (REVISOR DE PLANO)** → revisão adversarial → squash-merge um a um (gate em snapshot `int-ondaN-*`, em background; limpeza aguarda o verde de cada snapshot) → remoção APENAS das worktrees-filhas e branches desta execução, por nome registrado → prova de contenção → handoff para a próxima onda. Repete até o REVISOR DE PLANO declarar CONVERGÊNCIA |
| 4 | **COMMIT-FINAL** | Remove o TASK_PLAN.md, roda o gate completo (o trio GATE_BUILD/GATE_TEST/GATE_LINT da FASE 1), commita **apenas o que esta execução produziu** (a sujeira preexistente do usuário é preservada), varredura final restrita à lista nominal registrada, **gera o EXPLAINER.html** (a partir do template `$SKILL_HOME/templates/html-explainer.html`) e produz o relatório final |

### Regras fundamentais

1. **Nunca escreve código** — delega tudo a sub-agentes
2. **Nunca pergunta ao usuário** — autonomia total, infere com confiança. Três exceções, e apenas estas: `BRAVE_API_KEY` ausente, créditos Brave esgotados, ou abort da FASE 0 (não é repositório, HEAD destacado, repo sem commits, índice sujo)
3. **Trabalho completo, do início ao commit** — nunca entrega trabalho parcial
4. **Worktree é a unidade de isolamento** — cada sub-agente trabalha em sua própria worktree Git com nome descritivo (ex.: `onda1-cache-service`)
5. **Squash-merge um a um, nunca octopus** — integração sequencial em `$BASE_BRANCH`; o gate roda em snapshot de integração `int-ondaN-*` (fora da seção crítica) e a limpeza de cada filha aguarda o verde do snapshot (decisão D1: builds duplicados são esperados)
6. **Worktree nasce nomeada e morre no fim da própria onda** — limpeza imediata após gate verde, sempre por nome registrado
7. **Verificar créditos Brave antes de cada onda** — `$SKILL_HOME/scripts/check-brave-credits.sh --fail-fast`; sem créditos, nenhuma worktree é criada e nenhum sub-agente é disparado
8. **A worktree de invocação é a raiz-de-mundo** — nada é escrito fora dela; o branch dela é o único alvo de integração; a limpeza só toca o que esta execução registrou
9. **Dependências: dentro da worktree, congeladas, nunca globais** — instale só se necessário, com cwd na filha e `HUSKY=0`; cache global do usuário é permitido

## Estrutura da casa da skill (`$SKILL_HOME`)

```
deep-orchestrator/
├── README.md                    # Este arquivo
├── SKILL.md                     # Definição do skill v3.3.0 (frontmatter YAML + XML do orquestrador)
├── scripts/
│   ├── do-context.sh            # FASE 0 — delimita a raiz-de-mundo e grava o estado
│   ├── do-wt.sh                 # ciclo de vida das worktrees-filhas (guardas de contenção)
│   ├── test-contencao.sh        # testes de regressão do MODO CONTIDO
│   ├── brave-search.sh          # CLI de busca Brave (substitui o surf-search-normal)
│   └── check-brave-credits.sh   # Verificador de créditos da Brave Search API
├── prompts/
│   ├── ecc-prompts.md           # 7 templates de prompt portados do ECC
│   ├── ecc-skills.md            # 7 skills ECC portados
│   └── search-prompts.md        # Prompts de busca otimizados para dev
└── templates/
    └── html-explainer.html      # Template do HTML explainer (6 abas, Bootstrap 5)
```

## Requisitos

- Claude Code (CLI)
- Git
- **Brave Search API key** — `export BRAVE_API_KEY=<chave>` (https://api.search.brave.com/app/keys); o plano gratuito inclui ~$5/mês de créditos
- `curl` e `jq` (usados pelos scripts de busca)
- `project-router` skill resolvido a partir da raiz-de-mundo (`<raiz>/.claude/skills/project-router/` ou `<raiz>/.agents/skills/project-router/`). Ausente, o sub-agente registra no handoff e segue — não cai para o repositório principal nem para `~/.claude`

### Dependências

Uma worktree recém-criada **não** herda `node_modules`, `.venv` ou `target`: são untracked e `git worktree add` não os copia. Se a sub-tarefa precisar deles, o sub-agente instala **dentro da worktree** (cwd na raiz da filha), em modo congelado (`npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, …), com `HUSKY=0`, nunca com flags globais e nunca no projeto principal. O cache global do usuário (`~/.npm`, `~/.cache/uv`, `~/.cargo`, `~/.m2`) é permitido e desejável: é conteúdo endereçado por hash, compartilhado pela máquina, e redirecioná-lo só forçaria re-download por agente.

## Instalação

```bash
# Clone o repositório
git clone <repo-url> ~/Projects/deep-orchestrator

# Adicione ao seu projeto como skill — copie o diretório INTEIRO,
# pois scripts/, prompts/ e templates/ são referenciados pelo SKILL.md
mkdir -p .claude/skills/deep-orchestrator
cp -r SKILL.md scripts prompts templates .claude/skills/deep-orchestrator/

# Este bloco é setup MANUAL do usuário, executado UMA VEZ, fora de qualquer
# execução da skill — NUNCA por um sub-agente. A skill não se auto-instala no
# repositório-alvo: ela é lida de $SKILL_HOME.

# Defina a chave da Brave Search API
export BRAVE_API_KEY=<chave>
```

## Uso

```
/deep-orchestrator <descrição da tarefa>
/deep-orchestrator max-parallel=N <descrição da tarefa>   # prefixo OPCIONAL
```

O prefixo `max-parallel=N` define o cap de features por onda (F3-02): o orquestrador o parseia antes da FASE 0 e exporta `DO_MAX_PARALLEL=N` (validado como inteiro positivo; inválido → aborta com mensagem clara). Ausente → default **20** — que é o **CAP protetor, não o alvo**: 3-5 é o ponto ótimo recomendado pela Anthropic. Ondas com mais features que o cap viram batches sequenciais, cada batch com a sua barreira.

### Triggers

O skill é ativado automaticamente com frases como:

- "orquestre isso"
- "divida essa tarefa"
- "coordene múltiplos agentes"
- "resolva do início ao fim"
- "não me pergunte nada"
- "autônomo"
- "toca o barco"

### Quando usar

Tarefas complexas que se beneficiam de decomposição em ondas paralelas — especialmente quando você quer uma solução completa do início ao fim sem interrupções. **Nunca use para tarefas triviais de um passo só.**

### Exemplo

```
/deep-orchestrator Adicionar endpoint de busca com cache a uma API REST
```

O orquestrador vai:

1. Analisar o repositório e identificar os subsistemas afetados (verificando `BRAVE_API_KEY` e créditos antes)
2. Criar um plano inicial com 2 ondas:
   - **Onda 1 (Fundação):** `onda1-cache-service` (CacheService genérico) + `onda1-schema-busca` (mapear schema de busca) — paralelo
   - **Onda 2 (Implementação):** `onda2-endpoint-busca` (endpoint com cache + testes)
3. Executar cada onda com barreira, recálculo dinâmico (REVISOR DE PLANO), revisão adversarial, squash-merge com gate e limpeza — ondas adicionais podem surgir se o revisor detectar novas sub-tarefas
4. Commitar tudo, gerar o `EXPLAINER.html` e entregar o relatório

Ao final, o histórico do **branch da raiz-de-mundo** (o branch da worktree em que a skill foi invocada; `main`/`master` apenas quando a invocação foi na árvore principal) terá 3 commits squash de feature — um por sub-agente —, mais um commit por testing subwave integrada (`test-onda1-*`, `test-onda2-*`) e o commit final com o `EXPLAINER.html`. Nenhuma worktree-filha nem branch desta execução sobra; worktrees e branches pré-existentes de outras sessões não são tocados.

## Versão

**3.3.0** — gate em snapshot de integração (F3-01), DO_MAX_PARALLEL (F3-02), gate definido uma vez (F3-03), lockfile singleton (F3-04), tiering de modelos por papel (F3-09).

**3.2.0** — MODO CONTIDO (worktree como raiz-de-mundo), FASE 0 de bootstrap, guardas de contenção em `do-wt.sh`, regra de dependências (R9), testes de regressão.

**3.1.0** — Testing subwaves assíncronas, enforcement do project-router.

**3.0.0** — Brave Search interno, ondas ilimitadas, ECC prompts, verificação de créditos, HTML explainer.

## Licença

MIT
