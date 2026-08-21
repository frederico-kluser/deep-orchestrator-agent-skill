# deep-orchestrator v3.4.0

![Versão](https://img.shields.io/badge/version-3.4.0-00d4ff)

Orquestrador autônomo multi-agente para Claude Code — planeja, divide em ondas **ILIMITADAS** (com recálculo dinâmico), cria worktrees isoladas, delega, revisa adversarialmente, integra via squash-merge um a um com gate em snapshot de integração (worktree efêmera `int-ondaN-*`, fora da seção crítica), verifica o sistema de busca 3-tier antes de cada onda (`scripts/search.sh`: surf-skill → Brave Search API → DuckDuckGo keyless, com `check-search-credits.sh` e lotes via `search-parallel.sh`), e commita tudo ao final **sem perguntar nada ao usuário**.

A única exceção — e ela só existe quando você pede — é o **PORTÃO DE APROVAÇÃO DO PLANO** (FASE 2.5): quando a invocação pede um plano, o plano vai para o [Plannotator](https://github.com/backnotprop/plannotator) e você aprova ou anota. Cada anotação **regera o plano e abre um Plannotator NOVO**, até a aprovação — e nenhuma worktree nasce antes dela. Sem pedido de plano, a autonomia total continua exatamente como sempre foi.

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

## Novidades na v3.4.0

- **PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5, R10)**: quando a invocação **pede um plano**, o plano vai para o [Plannotator](https://github.com/backnotprop/plannotator) e o usuário aprova ou anota, no navegador. **Cada anotação REGERA o plano e abre um Plannotator inteiramente NOVO** (processo novo, servidor novo, aba nova) — nunca um remendo na sessão anterior — até a aprovação ou até o orçamento de revisões acabar. Nenhuma worktree, branch ou commit existe antes do APROVADO, e é justamente por isso que o portão fica aqui: recusar o plano não custa rollback nenhum.
- **Ligado só quando pedido**: `DO_PLAN_APPROVAL` é resolvido uma vez na FASE 0 (passo 0.5) por precedência — prefixo `plan=on`/`plan=off` > variável de ambiente > gatilhos negativos ("não me pergunte nada", "autônomo", "toca o barco") > gatilhos positivos ("faça um plano", "quero aprovar antes", "revisar o plano") > **default OFF**. Quem nunca falou em plano tem exatamente o comportamento autônomo de sempre: nenhum navegador abre.
- **Instalação automática do Plannotator**: `scripts/check-plannotator.sh --install` resolve o executável (`$DO_PLANNOTATOR_BIN` → PATH → `~/.local/bin`, que quase nunca está no PATH de um shell não-interativo), confere a versão (mínima 0.19.1) e **sonda a capacidade** rodando `annotate` sem argumento — que só imprime o usage, sem abrir navegador. Ausente, instala com `--minimal`: **só o binário**, sem encostar em `~/.claude`, `~/.codex`, `~/.gemini`, `~/.kiro` ou `~/.config/opencode`. Uma instalação existente nunca é sobrescrita. Nunca `sudo`, nunca `npm -g`.
- **Independente do agente**: o portão é **uma chamada Bash** — o menor denominador comum entre Claude Code, pi coding agent, jcode e opencode. Nada de hook de plan-mode, `ExitPlanMode` ou plugin de um agente específico, porque nada disso existe nos quatro. O harness é detectado (Claude Code > pi > jcode > opencode) só para carimbar `PLANNOTATOR_ORIGIN` na UI; a detecção jamais bloqueia o portão.
- **Título imutável**: o Plannotator rastreia revisões do **mesmo** plano pelo primeiro `#` do documento. `plan-approval.sh` **recusa** (exit 2) a rodada cujo título mudou, com o título travado na mensagem — é a mesma regra que o próprio Plannotator impõe (*"Do NOT change the plan title"*).
- **Decisão por exit code, nunca por texto**: `plan-approval.sh round` devolve 0 aprovado · 10 anotado · 11 fechado · 12 timeout · 13 falha da ferramenta · 14 orçamento esgotado. Cada rodada deixa um snapshot **imutável** (`rev-NNN.md`, somente leitura), o feedback (`rev-NNN.feedback.md`) e uma linha no `trail.tsv`.
- **O plano aprovado vira restrição**: o REVISOR DE PLANO da FASE 3 passa a classificar cada proposta em DENTRO ou FORA do escopo aprovado. FORA reabre o portão uma vez (consumindo do mesmo orçamento); sem orçamento, a proposta é registrada como `FORA-DO-ESCOPO-NÃO-APROVADA` e o escopo aprovado é respeitado.
- **O plano nunca sai da máquina sozinho** — duas travas independentes, ambas ligadas por default:
  - `PLANNOTATOR_SHARE=disabled` impede o **upload** do texto do plano para o serviço de paste, que o Plannotator faria em sessão remota. Libere com `DO_PLAN_SHARE=1`.
  - `PLANNOTATOR_REMOTE=0` mantém o servidor em **127.0.0.1**. Sem isso, qualquer shell com `SSH_TTY`/`SSH_CONNECTION` no ambiente — o caso normal de um servidor de desenvolvimento — faria o Plannotator escutar em `0.0.0.0:19432`; e como `/api/approve` **não tem autenticação**, qualquer pessoa que alcançasse a máquina leria o plano e poderia **aprová-lo por você**, levando o orquestrador a criar worktrees e commitar. Para revisar por SSH, use um túnel: `ssh -L 19432:127.0.0.1:19432 <host>`. `DO_PLAN_REMOTE=1` expõe na rede de propósito, com aviso em voz alta.
- **`scripts/sync-global-skill.sh`**: publica a skill para todos os agentes por **symlink**, trocando as importações por cópia que congelam a versão (o jcode importa copiando: uma cópia de meses atrás roda um orquestrador de duas versões atrás). Só mexe na entrada `deep-orchestrator`, só substitui um diretório depois de confirmar que ele é uma cópia desta mesma skill, guarda backup, e não cria diretório de agente que não existe.
- **Testes**: `scripts/test-plan-approval.sh` — 111 asserções, tudo mockado (binário e instalador falsos num PATH temporário), **sem rede, sem navegador e sem instalar nada**.

## Novidades na v3.3.0

- **Sistema de busca 3-tier (F1-03)**: `scripts/search.sh` — surf-skill (Tier 1, multi-provider AI-powered) → Brave Search API (Tier 2, via `search_brave_api()` do `brave-search.sh`) → DuckDuckGo keyless (Tier 3, Instant Answer, cobertura limitada). Verificação de tiers antes de cada onda via `scripts/check-search-credits.sh` (exit 0 = Tier 1/2 disponível; exit 1 = só Tier 3, degradado; exit 2 = nada disponível) e lotes paralelos via `scripts/search-parallel.sh` (uma chamada por lote, nunca loop). O surf-skill voltou como Tier 1 — a busca Brave interna da v3.0.0 não o substitui mais.
- **Subwaves duplas (F2-02/F2-04)**: TESTING (`test-ondaN-*`, máximo 3 worktrees de teste por onda — contam no teto DO_MAX_PARALLEL) e VALIDATION (`val-ondaN-*`, gate completo + revisão adversarial do diff integrado) rodam em background após cada onda e são integradas na onda seguinte (passo 3.5) ou no COMMIT-FINAL — nunca bloqueiam o disparo das ondas de feature.
- **Correções críticas da Fase 1 (F1-01 a F1-04)**: `do-wt.sh undo` seguro (reset --hard só com working tree exclusivamente untracked; o commit desfeito é arquivado em `refs/do-archive/$RUN_ID/undo-<nome>`), baseline de ignorados na FASE 0 + `clean-ignored-delta` no lugar do `git clean -fdXq` genérico (nunca apaga ignorados pré-existentes do usuário), `stage-delta` com `-uall` nos dois lados (arquivos novos dentro de dirs untracked do usuário entram no commit; a sujeira preexistente continua fora) e `--budget-ms` no Tier 1 do search.sh (`--timeout` em segundos vira milissegundos para o surf-search-normal).
- **Gate em snapshot de integração (F3-01)**: o squash-merge é atômico e o gate (build + testes + linter) sai da seção crítica — roda em background numa worktree efêmera `int-ondaN-<nome>` (kind=integration, registrada no owned.tsv) criada no SHA pós-merge. Merges seguem em sequência; a limpeza de cada filha e o fim da onda aguardam o respectivo gate de snapshot (`status=gate-pending` no owned.tsv; o `do-wt.sh sweep` detecta gate-pending, avisa e sai != 0). Falha tardia: `do-wt.sh undo <nome>` reverte exatamente aquele squash com HEAD avançado, arquivando o commit em `refs/do-archive/$RUN_ID/undo-<nome>`. **Decisão D1**: builds duplicados (snapshot + validação + gate final) são esperados.
- **DO_MAX_PARALLEL (F3-02)**: prefixo `mp=N` na invocação (`/deep-orchestrator mp=N <tarefa>`) — o orquestrador exporta `DO_MAX_PARALLEL` antes da FASE 0; ausente, default 50. Orçamento: features por onda ≤ DO_MAX_PARALLEL; in-flight total ≤ DO_MAX_PARALLEL (features + worktrees de teste/validação das subwaves + revisores + REVISOR DE PLANO — tudo no mesmo teto); ondas maiores viram batches sequenciais com a própria barreira.
- **Gate definido uma vez (F3-03)**: a FASE 1 detecta e registra no TASK_PLAN.md o trio exato `GATE_BUILD`/`GATE_TEST`/`GATE_LINT` do projeto-alvo (package.json/Makefile/pyproject.toml/Cargo.toml/go.mod); toda invocação de gate referencia esse trio, com cwd conforme o contexto (snapshot, validação ou `$BASE_DIR` no gate final).
- **Lockfile como singleton (F3-04)**: manifesto + lockfile entram no mapa de propriedade como recurso singleton — no máximo 1 agente por onda adiciona dependências; os demais registram "deps pendentes: <pacote@versão>" no handoff e a adição acontece no COMMIT PREP da onda seguinte.
- **Tiering de modelos por papel (F3-09)**: quando o harness permite, agentes de teste e revisores adversariais rodam em modelo médio, REVISOR DE PLANO e síntese final em modelo forte, features no padrão; regra de escala: ≤2 sub-tarefas pequenas e independentes não geram fan-out extra.
- **Testes**: `scripts/test-contencao.sh` — 85 asserções (A33: falha tardia de gate com undo de HEAD avançado; A34: gate-pending bloqueia o fim de onda).

## Novidades na v3.2.0

- **MODO CONTIDO** (acima) + **FASE 0 — DELIMITAR O MUNDO**: `scripts/do-context.sh` detecta worktree vinculada, resolve a fronteira e grava o arquivo de estado que toda chamada Bash sourceia.
- **Guardas em código, não em prosa**: `scripts/do-wt.sh` concentra criação, merge, undo, remoção, limpeza e prova de contenção. Cada operação destrutiva recusa alvos que não estejam registrados nesta execução.
- **Regra de dependências (R9)**: instalação permitida se necessária, sempre com cwd na worktree-filha, em modo congelado e com `HUSKY=0` (um postinstall de husky grava `core.hooksPath` no `.git` compartilhado). Cache global do usuário é permitido; escopo global de instalação é proibido.
- **Testes de regressão**: `scripts/test-contencao.sh` — 85 asserções cobrindo detecção de modo, colocação, limpeza segura, worktrees de terceiros, preservação da sujeira do usuário, paths com acento e espaço, guarda de índice sujo, distinção entre vazamento nosso e trabalho do usuário no projeto principal, conflito e re-merge (A23), exits da FASE 0 (A28/A29), flock (A30), kind=validation (A31), falha tardia de gate (A33) e gate-pending (A34).

## Novidades na v3.0.0

- **Ondas ilimitadas** com recálculo dinâmico — após cada onda, um sub-agente REVISOR DE PLANO analisa os handoffs e o TASK_PLAN.md, propõe novas sub-tarefas ou declara CONVERGÊNCIA. O ciclo só termina por convergência declarada, nunca por um número fixo de ondas.
- **Busca interna Brave** (`$SKILL_HOME/scripts/brave-search.sh`) — CLI próprio sobre a Brave Search API que substituía o `surf-search-normal` e não dependia mais do `surf-research-skill` nem do CLI `surf-ai`. **SUPERADA na v3.3.0**: o surf-skill voltou como **Tier 1** do sistema de busca 3-tier (`search.sh`); a Brave API virou o Tier 2 e o DuckDuckGo keyless o Tier 3.
- **Verificação de créditos** antes de cada onda (`$SKILL_HOME/scripts/check-brave-credits.sh`) — sem créditos, o orquestrador para e informa o usuário (única exceção à autonomia total). **SUPERADA na v3.3.0**: o verificador agora é `check-search-credits.sh` (3 tiers; exit 2 = TODOS os tiers fora) — `check-brave-credits.sh` está DEPRECATED.
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
| 1 | **ANALYZE** | Lê o prompt, mapeia a estrutura do repositório, identifica subsistemas, classifica greenfield/brownfield, localiza golden masters e verifica o sistema de busca 3-tier (`$SKILL_HOME/scripts/check-search-credits.sh --fail-fast` — exit 0 = Tier 1/2, exit 1 = só Tier 3 keyless, exit 2 = nada disponível) |
| 2 | **PLAN** | Decompõe a tarefa em sub-tarefas atômicas, identifica o grafo de dependências, organiza em ondas topológicas (número NÃO fixo — o plano é um ponto de partida), define o mapa de propriedade de arquivos, batiza cada worktree, escreve os prompts de delegação, publica o TASK_PLAN.md |
| 2.5 | **APROVAR O PLANO** | *Só quando `PLAN_APPROVAL=1`.* Garante o Plannotator na máquina (`check-plannotator.sh --install`), escreve o plano legível em `$PLAN_DOC` e roda `plan-approval.sh round`: aprovado → FASE 3; anotado → **regera o plano e abre um Plannotator NOVO** (até `DO_PLAN_MAX_REVISIONS`); fechado/timeout/orçamento → para limpo, sem nenhuma worktree criada. Desligado (o default), a fase é pulada inteira |
| 3 | **EXECUTE-ONDA** | Para cada onda: verificação de tiers de busca (`check-search-credits.sh`) → commit prep (se necessário) → cria worktrees → dispara agentes em paralelo (escalonado) → barreira → **recálculo dinâmico (REVISOR DE PLANO)** → revisão adversarial → squash-merge um a um (gate em snapshot `int-ondaN-*`, em background; limpeza aguarda o verde de cada snapshot) → remoção APENAS das worktrees-filhas e branches desta execução, por nome registrado → prova de contenção → handoff para a próxima onda. Repete até o REVISOR DE PLANO declarar CONVERGÊNCIA |
| 4 | **COMMIT-FINAL** | Remove o TASK_PLAN.md, roda o gate completo (o trio GATE_BUILD/GATE_TEST/GATE_LINT da FASE 1), commita **apenas o que esta execução produziu** (a sujeira preexistente do usuário é preservada), varredura final restrita à lista nominal registrada, **gera o EXPLAINER.html** (a partir do template `$SKILL_HOME/templates/html-explainer.html`) e produz o relatório final |

### Regras fundamentais

1. **Nunca escreve código** — delega tudo a sub-agentes
2. **Nunca pergunta ao usuário** — autonomia total, infere com confiança. Quatro exceções, e apenas estas: (a) `BRAVE_API_KEY` não definida E a tarefa exige pesquisa de alta qualidade (só o Tier 3 keyless não basta); (b) `check-search-credits.sh` retorna exit 2 (todos os tiers de busca indisponíveis) E a tarefa ou alguma sub-tarefa exige pesquisa; (c) abort da FASE 0 (não é repositório, HEAD destacado, repo sem commits, índice sujo); (d) o **portão de aprovação do plano** está ativo (`PLAN_APPROVAL=1`) — aí a interação é a entrega pedida, acontece no navegador (nunca por pergunta em texto) e só na FASE 2.5
3. **Trabalho completo, do início ao commit** — nunca entrega trabalho parcial. Única saída antecipada legítima: o portão terminar sem aprovação — e aí nada foi construído, então o repositório fica exatamente como estava
4. **Worktree é a unidade de isolamento** — cada sub-agente trabalha em sua própria worktree Git com nome descritivo (ex.: `onda1-cache-service`)
5. **Squash-merge um a um, nunca octopus** — integração sequencial em `$BASE_BRANCH`; o gate roda em snapshot de integração `int-ondaN-*` (fora da seção crítica) e a limpeza de cada filha aguarda o verde do snapshot (decisão D1: builds duplicados são esperados)
6. **Worktree nasce nomeada e morre no fim da própria onda** — limpeza imediata após gate verde, sempre por nome registrado
7. **Verificar o sistema de busca 3-tier antes de cada onda** — `$SKILL_HOME/scripts/check-search-credits.sh --fail-fast`; exit 0 = Tier 1/2 disponível (pesquisa completa), exit 1 = só Tier 3 keyless (degradado — registre no TASK_PLAN.md e prossiga), exit 2 = nada disponível: se a tarefa exige pesquisa, nenhuma worktree é criada e nenhum sub-agente é disparado; sem pesquisa exigida, a execução prossegue sem busca, com registro
8. **A worktree de invocação é a raiz-de-mundo** — nada é escrito fora dela; o branch dela é o único alvo de integração; a limpeza só toca o que esta execução registrou
9. **Dependências: dentro da worktree, congeladas, nunca globais** — instale só se necessário, com cwd na filha e `HUSKY=0`; cache global do usuário é permitido
10. **Só executa plano que o usuário aprovou** — quando o portão está ativo, nenhuma worktree nasce antes do APROVADO; o título do plano é imutável entre revisões; cada anotação regera o plano num Plannotator novo; e o feedback do usuário é correção **do plano**, nunca tarefa de implementação

## Técnicas e fundamentos

O deep-orchestrator não inventa orquestração do zero: ele compõe técnicas documentadas e verificadas (pesquisa profunda com fontes, agosto/2026) em cima do que o harness já oferece. As três colunas abaixo — ECC, busca em camadas e sub-agentes nativos — explicam de onde vem cada peça.

### ECC — Everything Claude Code (a técnica-mãe)

O [ECC — Everything Claude Code](https://github.com/affaan-m/ECC) (MIT) é um sistema massivo de otimização de harness de agentes: **67 agents, 281 skills, 94 commands**, além de hooks, Memory Vault, Continuous Learning e AgentShield (auditoria de segurança do próprio harness). O deep-orchestrator não o copia — **porta e adapta** o que ele faz de melhor, no fluxo `plan → test → implement → review → verify → remember → improve`:

- `prompts/ecc-prompts.md` — **7 templates de prompt** portados: System Prompt Base, Planning Prompt (Plan First), Code Review (método de confiança + veredito APPROVE/WARNING/BLOCK), Security Review (AgentShield + checklist OWASP), Memory Persistence, Continuous Improvement (instincts com scoring de confiança 0.3–0.9) e Clone-Analyze-Discard.
- `prompts/ecc-skills.md` — **7 skills** portadas no formato ECC (frontmatter YAML + workflow em passos): `tdd-workflow` (TDD gated RED→GREEN→REFACTOR com evidência e cobertura ≥ 80%), `security-audit` (checklist OWASP de 10 pontos + revisão do harness), `doc-generator` (docs/ADRs a partir do diff), `research-deep-dive` (search-first com matriz Adotar/Estender/Compor/Construir), `memory-vault` (handoffs entre ondas e sessões), `clone-and-analyze` (portar o melhor de repos de referência em worktree isolada) e `code-quality-gate` (gate mecânico determinístico — o braço de execução do gate pós-squash).

Princípio transversal herdado: **entrada NÃO confiável** — planos, diffs e repos clonados são lidos como texto não confiável; comandos embutidos só rodam após sanitização contra whitelist (test, lint, typecheck, coverage).

### Busca em camadas — o caso surf-skill e a pesquisa nativa do harness

A pesquisa externa segue uma cadeia com fallback automático (`scripts/search.sh`), verificada antes de cada onda (`check-search-credits.sh`) e processada em lotes paralelos (`search-parallel.sh`):

| Tier | Provedor | Notas |
|------|----------|-------|
| 0 | **Pesquisa nativa do harness** (Claude Code: `WebSearch`/`WebFetch`) | quando o harness que hospeda a skill expõe ferramentas de busca próprias, usamos a dele — sem chave, sem script |
| 1 | surf-skill (`surf-search-normal`) | multi-provider AI-powered; qualidade máxima; exige o CLI surf-ai |
| 2 | Brave Search API (`brave-search.sh` + `BRAVE_API_KEY`) | API direta; atenção ao modelo metered da Brave (fev/2026) — créditos mensais |
| 3 | DuckDuckGo Instant Answer | keyless, disponível enquanto houver rede; cobertura limitada (não é full-text) |

**O caso surf-skill**: o surf-skill foi o provedor original da busca, substituído por uma busca Brave interna na v3.0.0, e **voltou como Tier 1 na v3.3.0** — a cadeia ficou em 3 tiers de novo (a busca Brave virou Tier 2). A regra do Tier 0 é a do harness: **se o agente que está rodando a skill já tem pesquisa nativa (o Claude Code tem `WebSearch`/`WebFetch`), usamos a dele**; o `search.sh` continua sendo a interface unificada e o fallback determinístico para harnesses sem ferramenta de busca (pi, jcode, opencode) e para sub-agentes sem acesso a ela. No template de delegação do SKILL.md, o sub-agente usa `{{SKILL_HOME}}/scripts/search.sh` — e, no Claude Code, pode usar as ferramentas nativas do harness quando disponíveis.

### Sub-agentes no Claude Code — nativos, nenhum plugin necessário

**Resposta curta da pesquisa profunda (25 claims verificadas adversarialmente contra as docs oficiais, 0 refutadas, 2026-08-18): o Claude Code já tem sub-agentes nativos. Não existe plugin a instalar para isso — e não há nada para abrir em outro terminal.** Plugins são um canal **opcional** de distribuição, não um requisito.

- **O que são**: arquivos Markdown com frontmatter YAML em `.claude/agents/` (projeto) ou `~/.claude/agents/` (usuário — vale em todos os projetos, sem configuração extra). O frontmatter define `name`, `description`, `tools`, `model`, `permissionMode`, `skills`, `memory`, `background`, `isolation`; o corpo do arquivo vira o system prompt.
- **Como são disparados**: pela ferramenta **Agent** (renomeada da Task na v2.1.63; `Task(...)` continua como alias), que roda o sub-agente em contexto próprio — em paralelo ou em background — e devolve um único resultado ao pai. Sub-agentes começam com **contexto zero**: prompts precisam ser autocontidos (é exatamente o que o template de delegação do SKILL.md faz).
- **Tipos embutidos**: `Explore` (busca/análise read-only; pula CLAUDE.md e o git status do pai por velocidade), `Plan`, `general-purpose`, `claude`, `statusline-setup`, `claude-code-guide`. É o `general-purpose` que o orquestrador usa nas ondas.
- **Paralelismo**: nativo, com teto de **20 sub-agentes concorrentes por sessão** (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, v2.1.217+) e até 3 níveis de profundidade de spawn — o teto efetivo das ondas do orquestrador é `min(DO_MAX_PARALLEL, 20)`: o default do DO_MAX_PARALLEL virou **50**, mas o harness impõe 20 concorrentes reais por sessão (filas do resto), então na prática as ondas raramente passam de ~20 em voo.
- **Terminal novo**: agentes de usuário em `~/.claude/agents/` persistem em todos os projetos. Prioridade de resolução de nomes: managed settings (org) > flag `--agents` (JSON, vale só na sessão) > `.claude/agents/` (projeto) > `~/.claude/agents/` (usuário) > `agents/` de plugins. Desde a v2.1.198 o `/agents` não abre mais wizard — imprime onde editar os arquivos.
- **Plugins (aditivos, opcionais)**: o sistema `/plugin` empacota skills, hooks, MCP e **também agentes prontos** (pasta `agents/` do plugin; invocados por @-mention escopado `plugin:agente`). Marketplaces: o oficial `anthropics/claude-plugins-official` (adicionado automaticamente na primeira execução; ex.: `pr-review-toolkit`, com 6 agentes de revisão de PR) e o comunitário `anthropics/claude-plugins-community` (com triagem de segurança da Anthropic — que **só** vale para ele: plugins de URLs git arbitrárias ou diretórios locais não passam por triagem). Coleções grandes de terceiros existem (ex.: `wshobson/agents`, 200+ agentes) — **nenhuma é necessária** para o que este projeto faz.
- **Equipes nativas** (`agent teams`): existem no harness, mas são **experimentais e desabilitadas por padrão** — o sistema de ondas com worktrees do deep-orchestrator segue sendo a abordagem de produção.
- **Nota**: o harness também tem `claude --worktree <nome>` para sessões paralelas isoladas; o deep-orchestrator mantém o sistema próprio (R6/R8, `do-wt.sh`) porque precisa de nomes, branches e limpeza controlados por registro (`owned.tsv`) — isolamento real por worktree, não apenas por sessão.

Fontes primárias: [subagents](https://code.claude.com/docs/en/subagents) · [agents — run in parallel](https://code.claude.com/docs/en/agents) · [discover-plugins](https://code.claude.com/docs/en/discover-plugins) · [claude-plugins-official](https://github.com/anthropics/claude-plugins-official) · [claude-plugins-community](https://github.com/anthropics/claude-plugins-community). Fatos version-sensitive (v2.1.63 / v2.1.186 / v2.1.198 / v2.1.217+) devem ser conferidos contra a versão do Claude Code instalada.

## Estrutura da casa da skill (`$SKILL_HOME`)

```
deep-orchestrator/
├── README.md                    # Este arquivo
├── SKILL.md                     # Definição do skill v3.4.0 (frontmatter YAML + XML do orquestrador)
├── scripts/
│   ├── README.md                # Índice de todos os scripts e o fluxo de busca 3-tier
│   ├── do-context.sh            # FASE 0 — delimita a raiz-de-mundo e grava o estado
│   ├── do-wt.sh                 # ciclo de vida das worktrees-filhas (guardas de contenção)
│   ├── search.sh                # interface única de busca 3-tier (surf-skill → Brave → DDG keyless)
│   ├── search-parallel.sh       # busca em lote paralelo (uma chamada por lote, nunca loop)
│   ├── check-search-credits.sh  # verificador multi-tier pré-onda (exit 0/1/2)
│   ├── check-plannotator.sh     # FASE 2.5 — resolve/instala o Plannotator (exit 0/1/2)
│   ├── plan-approval.sh         # FASE 2.5 — uma rodada de aprovação no Plannotator
│   ├── sync-global-skill.sh     # publica a skill por symlink para todos os agentes
│   ├── brave-search.sh          # fonte da função search_brave_api() — Tier 2
│   ├── check-brave-credits.sh   # (DEPRECATED) — use check-search-credits.sh
│   ├── generate-explainer.sh    # gera o EXPLAINER.html a partir do template (COMMIT-FINAL)
│   ├── test-contencao.sh        # testes de regressão do MODO CONTIDO (85 asserções)
│   ├── test-search.sh           # testes da cadeia de busca 3-tier (64 asserções)
│   └── test-plan-approval.sh    # testes do portão de aprovação (111 asserções, mockado)
├── prompts/
│   ├── ecc-prompts.md           # 7 templates de prompt portados do ECC
│   ├── ecc-skills.md            # 7 skills ECC portados
│   ├── search-prompts.md        # Prompts de busca otimizados para dev
│   └── plan-approval-prompts.md # Templates da FASE 2.5 (documento, feedback, regeração)
└── templates/
    └── html-explainer.html      # Template do HTML explainer (6 abas, Bootstrap 5)
```

## Requisitos

- Claude Code (CLI)
- Git
- **Brave Search API key** — `export BRAVE_API_KEY=<chave>` (https://api.search.brave.com/app/keys) — **OPCIONAL**: habilita o Tier 2. Sem ela, a busca segue funcional em modo degradado (Tier 3 DuckDuckGo keyless, Instant Answer com cobertura limitada) e o Tier 1 (surf-skill) dispensa a chave. **Modelo metered da Brave (desde fev/2026)**: os planos dão créditos mensais e passam a COBRAR pelo uso que excede a quota — a verificação pré-onda (`check-search-credits.sh`) é também proteção financeira
- **`surf-search-normal` (surf-skill)** — **OPCIONAL**: habilita o Tier 1 (multi-provider AI-powered). Ausente, a busca cai direto para os Tiers 2/3
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

# OPCIONAL — defina a chave da Brave Search API (habilita o Tier 2); sem ela,
# a busca segue via Tier 1 (surf-skill) e/ou Tier 3 (DDG keyless)
export BRAVE_API_KEY=<chave>
```

## Uso

```
/deep-orchestrator <descrição da tarefa>
/deep-orchestrator mp=N <descrição da tarefa>            # prefixo OPCIONAL
/deep-orchestrator plan=on <descrição da tarefa>          # prefixo OPCIONAL — força o portão
/deep-orchestrator plan=off faça um plano e execute       # força a autonomia total
/deep-orchestrator wt=on <descrição da tarefa>            # prefixo OPCIONAL — worktree irmã nomeada como raiz-de-mundo
/deep-orchestrator wt=feature-x <descrição da tarefa>     # prefixo OPCIONAL — com nome explícito
```

O prefixo `wt=` (WT-ROOT) é o fato novo desta versão. Ele cria — ou reentra — uma worktree **irmã verdadeira** do projeto em `<pai>/<repo>.worktrees/<nome>` e faz **todo** o trabalho **dentro dela**, preservando o checkout principal intacto. O fluxo:

1. A pasta irmã `<pai>/<repo>.worktrees/` é criada se faltar, ou **reentrada** se já existir (nunca recriada).
2. O nome do diretório da worktree é o `<nome>` passado (`wt=feature-x`), ou um slug derivado do prompt da tarefa se você usar `wt=on` sem valor. O nome é **deduplicado** contra o que já existe dentro da pasta irmã: colisão com um diretório de uma feature anterior ganha `-2`, `-3`, … até achar um livre.
3. A `FASE 0` **re-executa com o cwd dentro da worktree**: o resto é o MODO CONTIDO já existente — ondas, sub-agentes, merges via squash, gates, subwaves de teste/validação e o COMMIT-FINAL aterrissam **lá dentro**, e o checkout principal é `$MAIN_ROOT`, zona proibida.

A worktree irmã é **persistente** (ao contrário das worktrees-filhas efêmeras por onda): o branch `do/wt/<nome>` é reusado entre execuções. Variáveis: `DO_WT_ROOT` (`1` quando ativo), `DO_WT_NAME` (o slug/nome resolvido), `DO_WT_ROOT_ENTERED` (sentinel interno de re-entrada).

O prefixo `mp=N` define o cap de concorrência (F3-02): o orquestrador o parseia antes da FASE 0 e exporta `DO_MAX_PARALLEL=N` (validado como inteiro positivo; inválido → aborta com mensagem clara). Ausente → default **50**. O teto vale para TUDO em voo — features da onda, worktrees de teste/validação das subwaves (incluindo as até 3 worktrees de teste por onda), revisores e REVISOR DE PLANO. Ondas com mais features que o cap viram batches sequenciais, cada batch com a sua barreira. Nota: o harness do Claude Code impõe um teto próprio de ~20 sub-agentes concorrentes por sessão (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), então o com `mp=` acima de 20 a concorrência real fica limitada pelo harness (o resto espera em fila) — o `mp=` continua servindo para dimensionar as ondas/batches.

### O portão de aprovação do plano

O prefixo `plan=on|off` liga ou desliga a FASE 2.5. Sem ele, a decisão vem dos gatilhos, nesta ordem:

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

O skill é ativado automaticamente com frases como:

- "orquestre isso"
- "divida essa tarefa"
- "coordene múltiplos agentes"
- "resolva do início ao fim"
- "não me pergunte nada"
- "autônomo"
- "toca o barco"

E, para a FASE 2.5 (portão de aprovação):

- "faça um plano"
- "planeje isso"
- "quero aprovar o plano antes"
- "revisar o plano"

### Quando usar

Tarefas complexas que se beneficiam de decomposição em ondas paralelas — especialmente quando você quer uma solução completa do início ao fim sem interrupções. **Nunca use para tarefas triviais de um passo só.**

### Exemplo

```
/deep-orchestrator Adicionar endpoint de busca com cache a uma API REST
```

O orquestrador vai:

1. Analisar o repositório e identificar os subsistemas afetados (verificando os tiers de busca antes — `check-search-credits.sh`)
2. Criar um plano inicial com 2 ondas:
   - **Onda 1 (Fundação):** `onda1-cache-service` (CacheService genérico) + `onda1-schema-busca` (mapear schema de busca) — paralelo
   - **Onda 2 (Implementação):** `onda2-endpoint-busca` (endpoint com cache + testes)
3. Executar cada onda com barreira, recálculo dinâmico (REVISOR DE PLANO), revisão adversarial, squash-merge com gate e limpeza — ondas adicionais podem surgir se o revisor detectar novas sub-tarefas
4. Commitar tudo, gerar o `EXPLAINER.html` e entregar o relatório

Ao final, o histórico do **branch da raiz-de-mundo** (o branch da worktree em que a skill foi invocada; `main`/`master` apenas quando a invocação foi na árvore principal) terá 3 commits squash de feature — um por sub-agente —, um squash commit por worktree de teste das testing subwaves (até 3 por subwave; `test-onda1-*`, `test-onda2-*`), os fixes das validation subwaves (`val-ondaN-*`) e o commit final com o `EXPLAINER.html`. Nenhuma worktree-filha nem branch desta execução sobra; worktrees e branches pré-existentes de outras sessões não são tocados.

## Versão

**3.3.0** — sistema de busca 3-tier (search.sh + check-search-credits.sh + search-parallel.sh), subwaves duplas (TESTING + VALIDATION), gate em snapshot de integração (F3-01), DO_MAX_PARALLEL (F3-02), gate definido uma vez (F3-03), lockfile singleton (F3-04), tiering de modelos por papel (F3-09), correções críticas da Fase 1 (F1-01 a F1-04).

**3.2.0** — MODO CONTIDO (worktree como raiz-de-mundo), FASE 0 de bootstrap, guardas de contenção em `do-wt.sh`, regra de dependências (R9), testes de regressão.

**3.1.0** — Testing subwaves assíncronas, enforcement do project-router.

**3.0.0** — Brave Search interno, ondas ilimitadas, ECC prompts, verificação de créditos, HTML explainer.

## Licença

MIT
