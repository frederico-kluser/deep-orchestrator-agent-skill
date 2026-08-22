# Plano de Produto — deep-orchestrator-agent-skill v3.2 → v4

**7 Decisões de Engenharia Priorizadas** | Data: 2026-08-03 | Base: pesquisa multi-agente com revisão adversarial (~1.300 fontes)

---

## Sumário executivo

O deep-orchestrator-agent-skill (v3.1.0) já entrega o pacote raro de **worktree isolation + revisão adversarial + testing subwave** em um único fluxo autônomo (ANALYZE → PLAN → EXECUTE-ONDA ilimitado → COMMIT-FINAL). O plano abaixo responde à pergunta "de suporte a tudo que usamos" com 7 decisões ordenadas por impacto × urgência:

| # | Decisão | Timeline | Esforço | Impacto |
|---|---------|----------|---------|---------|
| D1 | Router de modelos 3-tier (Qwen3-Coder → DeepSeek V4-Flash → Claude) | v3.2 | 3-5 dias | **−89,7% de custo** ($57,76 vs $562,50/mês) |
| D2 | Busca multi-provider (Adapter + RRF k=60 + circuit breaker) | v3.2 | 2-4 dias | Remove lock-in, cria benchmark próprio |
| D3 | Loop de qualidade nativo: testing subwaves assíncronas (único) + adversarial no padrão externo (gap) | v3.2 (+ v4) | 1-2 semanas | **Moat estratégico** |
| D4 | Handoff híbrido schema v1 (frontmatter + markdown + trace bruto) | v3.2 | 3-5 dias | −57-59% custo de contexto |
| D5 | Plataforma de skills: SKILL.md + AGENTS.md dual, migração das ~20 skills | v3.2 | 2-3 dias | Portabilidade universal |
| D6 | Isolamento: path containment + pre-flight agora; gVisor v4; Firecracker v5+ | v3.2 + v4 | 2-4d (v3.2), 2-3sem (v4) | Segurança para código não-confiável |
| D7 | MCP essenciais agora; A2A Protocol em v4 | v3.2 + v4 | 2-3d (v3.2), 2-3sem (v4) | Integração com ecossistema |

**Vetores:** (1) *economia* — D1+D2 pagam a operação contínua; (2) *moat* — D3 é a única combinação que o ecossistema não replica; (3) *plataforma* — D4+D5+D6+D7 fazem do orquestrador o centro de "tudo que usamos" (20+ skills, MCP, A2A no futuro).

---

## D1 — Router de modelos 3-tier com fallback obrigatório

- **Decisão:** Implementar roteamento de modelos em 3 camadas, 100% externalizado em config (não em código): **L1** Qwen3-Coder-480B (OpenRouter free) → **L2** DeepSeek V4-Flash ($0,11/$0,22) → **L3** Claude (frontier, $3/$15). Roteamento por heurística leve (files modificados + lines changed — 96,9% das tasks fáceis são single-file) e fallback encadeado L1→L2→L3 em qualquer falha.
- **Evidência:** DeepSeek V4-Flash-0731 (31/jul/2026) marca DeepSWE 54.4 vs 58.0 do Opus 4.8 a ~1/90 do preço [5]; Claude Sonnet 5 segue como sweet spot qualidade/custo (85,2% SWE-bench a $2/$10) [6]; Qwen3-Coder tem 93,9% HumanEval oficial mas uptime ~72,4% e erro tool-call ~2,63% — fallback não é opcional [7]. Economia: ~89,7% vs always-frontier ($57,76 vs $562,50/mês para 50 tasks/dia) [8].
- **Ação concreta:** criar `config/router.yaml` (modelos, preços, thresholds da heurística, política de fallback); módulo de roteamento com circuit breaker por provider; métricas de fallback rate e custo por onda no EXPLAINER.html; testes com os 4 perfis (fácil/única-arquivo, média, complexa, failed-L1).
- **Esforço:** 3-5 dias (médio).
- **Timeline:** **v3.2** — imediato. É o maior ganho quantificado do plano.

---

## D2 — Busca multi-provider: Adapter + RRF + circuit breaker + cache

- **Decisão:** Generalizar a busca interna atual (que hoje é Brave-only em `scripts/brave-search.sh`) para um Adapter pattern com Tavily, Brave e Exa, fusão por **Reciprocal Rank Fusion (RRF k=60)**, circuit breaker por provider e cache de 24h para dev. **Não fixar provider primário em código** — a primária sai de benchmark próprio com queries do domínio dev.
- **Evidência:** AIMultiple: Brave 14.89 > Exa 14.39 > Tavily 13.67 [3]; Tavily é RAG-native com SimpleQA 93,3% mas foi adquirida pela Nebius ($275M, fev/2026) — free tier 1K/mês sob risco [2]; Exa é a mais rápida (<425ms) com MCP server oficial [4]. Custo alvo: $0-30/mês para uso dev (10-100 queries/dia) [19].
- **Ação concreta:** extrair interface `search-provider` (search + credits-check) de `brave-search.sh`; adapters Tavily/Exa; fusão RRF k=60; cache 24h; harness de benchmark (`bench/query-set-dev.yaml` com ~50 queries de dev) rodado trimestralmente; generalizar `check-brave-credits.sh` para credits-check multi-provider; **correção de informação (aplicada em 2026-08-14, migração F4-05):** a Brave é METERED — o "plano gratuito ~$5/mês" (afirmação que o README do repo ainda carrega, hoje na linha 111) foi encerrado em fev/2026, e o uso que excede a cota gratuita gera cobrança real (pay-as-you-go) [3].
- **Esforço:** 2-4 dias (médio).
- **Timeline:** **v3.2** — junto com D1 (compartilham circuit breaker e métricas).

---

## D3 — Loop de qualidade nativo: testing subwaves assíncronas + adversarial no padrão do ecossistema

- **Decisão:** Dobrar no que é potencialmente único — **testing subwaves ASSÍNCRONAS PARALELAS** (vs test stage single-shot serial dos concorrentes) — e fechar o gap da revisão adversarial, que hoje existe nativamente mas abaixo do padrão externo (ai-jury, Comfy, MMAR, rev4nchist, Aris). Torna-se o produto: um **quality loop integrado e plugável** (testing paralelo → revisão adversarial → re-delegação).
- **Evidência:** Loop Engineer (npm) tem TEST gated no loop (ANALYZE → PLAN → IMPLEMENT → TEST → REVIEW → DECIDE) e @pi-agents/orchid tem tester dedicado — mas ambos seriais [10]; nenhum dos 10 frameworks principais tem revisão adversarial, e o ecossistema externo robusto (ai-jury: jury cross-vendor com debate; Comfy: 4 labs, 8 reviews/PR, ~$200/mês) existe como **cola externa**, não nativa [11].
- **Ação concreta:** (a) testing subwaves: sharding de testes por arquivo/subsistema rodando em paralelo nas worktrees, falhas vão para re-delegação em subwave própria, gate só fecha com o conjunto verde; (b) adversarial: protocolo em camadas — 1 revisor padrão (custo zero extra) + modo opcional "jury" cross-vendor (2-3 revisores, possível com L1/L2 do router D1, evitando o custo Comfy) + checklist por tipo de mudança; (c) métricas públicas por execução: testes executados/falhas detectadas pelo adversarial/re-trabalho evitado.
- **Esforço:** 1-2 semanas (alto).
- **Timeline:** **v3.2** — núcleo (sharding + protocolo 1 revisor + métricas); **v4** — jury cross-vendor plugável e políticas configuráveis. É o norte estratégico do plano: *não vender worktree, vender o loop completo*.

---

## D4 — Handoff híbrido: schema v1 (frontmatter + markdown + trace bruto)

- **Decisão:** Padronizar os handoffs dos sub-agentes em schema v1 **híbrido**: YAML frontmatter parseável (13-15 campos: 6 semânticos — goal, completed_work, evidence, uncertainty, next_action, human_summary — + ~9 metadados) + corpo markdown + **trace bruto anexado**. Manter WAVE_LOG.md separado do TASK_PLAN.md. Migração backward-compat em 3 fases (Expand-Migrate-Contract).
- **Evidência:** Paper "Handoff Debt" (arXiv 2606.02875): trace bruto reduz custo de handoff em 57-59% vs structured notes (29-44%) — recomendação é híbrido estruturado + trace, não só estruturado [1]; YAML frontmatter + markdown custa 16-54% menos tokens que JSON equivalente [17]; WAVE_LOG.md separado corta ~94% do contexto vs TASK_PLAN monolítico [17].
- **Ação concreta:** definir `docs/handoff-schema-v1.md` (campos obrigatórios/opcionais); template de handoff nos prompts de delegação; rotina do REVISOR DE PLANO passa a ler frontmatter via parser (não só markdown); append do trace bruto do sub-agente ao WAVE_LOG.md; Fase 1 (expand: escrever novo formato sem quebrar parser antigo) → Fase 2 (migrar leitores) → Fase 3 (contract: remover suporte legado).
- **Esforço:** 3-5 dias (médio).
- **Timeline:** **v3.2**.

---

## D5 — Plataforma de skills: SKILL.md + AGENTS.md dual, migração das ~20 skills

- **Decisão:** Adotar o dual padrão do mercado — **SKILL.md** (capacidades on-demand) + **AGENTS.md** (contexto sempre-on de projeto) — e migrar as ~20 skills do usuário, corrigindo os 7 problemas de portabilidade detectados. Para Claude Code (única ferramenta que não lê AGENTS.md nativamente), injetar `@AGENTS.md` no CLAUDE.md.
- **Evidência:** SKILL.md é adotado por 25-30+ produtos (formato universal); AGENTS.md por 20+ ferramentas sob a Linux Foundation; Claude Code é a única exceção na leitura nativa de AGENTS.md [14]. Auditoria: 7 skills com problemas (1 YAML quebrado, 2 com underscore no nome, 4 com description >1024 chars); migração estimada em 1-2 dias [15].
- **Ação concreta:** corrigir o frontmatter YAML quebrado; renomear underscores para kebab-case; encurtar descriptions para ≤1024 chars (validar com lint de frontmatter em CI); gerar AGENTS.md de projeto (ou `@AGENTS.md` no CLAUDE.md); documentar o dual no README do deep-orchestrator-agent-skill como padrão a propagar nos repositórios-alvo.
- **Esforço:** 2-3 dias (baixo).
- **Timeline:** **v3.2**.

---

## D6 — Isolamento: path containment + pre-flight agora; gVisor v4; Firecracker v5+

- **Decisão:** Endurecer o isolamento em 3 camadas temporais: **(v3.2)** path containment guard (estilo fix do CVE-2026-55607) + pre-flight checks de readiness no estilo Factory antes de disparar sub-agentes; **(v4)** gVisor (runsc) para código não-confiável; **(v5+)** Firecracker microVM apenas para multitenant externo. **Não usar Docker** (kernel compartilhado, baixo ganho de segurança).
- **Evidência:** Path containment guard no padrão do fix do CVE-2026-55607 é o baseline mínimo para agentes que editam arquivos [16]; gVisor (runsc) é a camada recomendada para código não-confiável e Firecracker para multitenant; Docker não adiciona fronteira de kernel [18]. Worktree em si virou commodity [9] — o valor está no pacote com guard e pre-flight.
- **Ação concreta:** (v3.2) guard de path no momento do squash-merge: rejeitar qualquer diff que saia do mapa de propriedade de arquivos do plano; `/readiness-report` no estilo Factory (branch limpa, build ok, credenciais ok) antes de cada onda; (v4) integração opcional runsc para execução de testes de código não-confiável.
- **Esforço:** 2-4 dias (v3.2); 2-3 semanas (v4, gVisor).
- **Timeline:** **v3.2** (guard + pre-flight) → **v4** (gVisor) → **v5+** (Firecracker, somente se houver multitenancy).

---

## D7 — MCP essenciais agora; A2A Protocol em v4

- **Decisão:** Integrar os servidores MCP essenciais ao fluxo já em v3.2 (Filesystem, GitHub MCP, Git, Playwright, Context7, Firecrawl, Tavily/Exa MCP, PostgreSQL/SQLite, Sequential Thinking) e **adotar A2A apenas em v4** — handoffs inline + MCP cobrem 100% do caso de uso atual.
- **Evidência:** MCP é o padrão de tools: 18.032 servidores no registry oficial (jul/2026), 110M downloads SDK/mês, 177K tools [12]. A2A v1.0 estável desde mar/2026 com 150+ orgs em produção (PayPal, Oracle, SAP) e 5 SDKs oficiais [13], mas a adoção é custo de integração sem retorno imediato para um orquestrador single-machine.
- **Ação concreta:** (v3.2) documentar no SKILL.md quais MCP servers o orquestrador assume/fornece aos sub-agentes; mapear queries de busca dev para o MCP de Tavily/Exa (reforça D2); (v4) prova de conceito A2A: sub-agente remoto via SDK oficial, avaliação em 2 SDKs, decision gate com critérios (latência de handoff, custo, confiabilidade). MCP e A2A são complementares: MCP para tools, A2A para comunicação entre agentes.
- **Esforço:** 2-3 dias (v3.2); 2-3 semanas (v4).
- **Timeline:** **v3.2** (MCP) → **v4** (A2A PoC).

---

## Diferenciais reais vs percebidos

| Item | Percebido (commodity) | Real | Implicação |
|------|----------------------|------|------------|
| Worktree isolation | Virou commodity: Gemini CLI, Loop Engineer, WLP, girelay, Koi, hort, Unstoppable Code; "Isolate" (base JJ) mostra que worktrees quebram com 4+ agentes [9] | Pacote **integrado** worktree + adversarial + testing em um fluxo autônomo que commita sem perguntar | Não vender worktree; vender o loop completo e a autonomia |
| Test no loop | Loop Engineer tem TEST gated (ANALYZE → PLAN → IMPLEMENT → TEST → REVIEW → DECIDE); @pi-agents/orchid tem tester dedicado — ambos **seriais** [10] | Testing subwaves **assíncronas paralelas** (vs single-shot serial) — potencialmente único [10] | Aprofundar (D3): sharding paralelo + re-delegação por falha |
| Revisão adversarial | Ausente nos 10 frameworks principais; externamente robusto como **cola externa** (ai-jury, Comfy 4 labs/8 reviews/PR, MMAR, rev4nchist, Aris) [11] | deep-orchestrator-agent-skill já tem adversarial **nativo**, mas abaixo do padrão externo | Fechar o gap (D3): jury cross-vendor e multi-review opcionais nativos |
| Handoff estruturado | Structured notes reduzem custo em só 29-44% [1] | Trace bruto reduz 57-59% [1]; híbrido frontmatter+markdown+trace é o ponto ótimo | Adotar schema híbrido (D4) |

**Resumo:** o único diferencial potencialmente inimitável hoje é o testing subwave assíncrono paralelo; o adversarial nativo é o gap mais curto de fechar; worktree isoladamente não vale mais como argumento de venda.

---

## Riscos e monitoramento

| Risco | Trigger / métrica | Mitigação | Frequência |
|-------|-------------------|-----------|------------|
| Volatilidade DeepSeek (preços/modelos) | V4-Flash a 1/90 do preço; preços e benchmarks mudam rápido [5] | Router 100% externalizado em config (D1); alerta se fallback rate L1 > 20% ou custo/onda sobe >30% | Mensal |
| Tavily pós-aquisição Nebius | Free tier 1K/mês sob risco; Brave já matou o free tier em fev/2026 [2][3] | Adapter multi-provider (D2) torna a troca uma mudança de config; benchmark trimestral | Trimestral (benchmark) |
| Qwen3-Coder indisponível | Uptime ~72,4%, erro tool-call ~2,63%, latência ~20,9s [7] | Fallback L1→L2→L3 **obrigatório** e testado; métricas de disponibilidade por provider | Contínuo (automatizado) |
| Fragmentação SKILL.md/AGENTS.md | 7/20 skills com problemas de portabilidade; 25-30+ produtos sem consenso total [14][15] | Lint de frontmatter em CI; dual SKILL.md+AGENTS.md; workaround `@AGENTS.md` no CLAUDE.md | A cada skill nova |
| A2A imaturo | Spec v1.0 de mar/2026 com 150+ orgs, mas ecossistema em consolidação [13] | Adiar para v4; reavaliar a cada 6 meses com decision gate (latência, custo, confiabilidade) | Semestral |
| Viés de benchmark de busca | Ranking Brave 14.89 > Exa 14.39 > Tavily 13.67 depende do conjunto de queries [3][2] | Benchmark próprio com queries reais de dev; provider primário nunca fixo em código | Trimestral |
| Regressão na migração de handoff | Migração backward-compat em 3 fases (Expand-Migrate-Contract) [17] | Fase Expand antes de tocar leitores; parser com fallback; testes de golden handoffs | Durante D4 |

---

## Fontes

| # | Fonte | Referência |
|---|-------|------------|
| [1] | "Handoff Debt" — arXiv 2606.02875 | https://arxiv.org/abs/2606.02875 |
| [2] | Tavily — SimpleQA 93,3%, free tier 1K/mês | tavily.com |
| [3] | Brave Search — $5/1K, free tier encerrado fev/2026; AIMultiple benchmark | api.search.brave.com |
| [4] | Exa — $7/1K, <425ms, MCP server oficial | exa.ai |
| [5] | DeepSeek V4-Flash-0731 (31/jul/2026) — DeepSWE 54.4 vs Opus 4.8 (58.0) | deepseek.com |
| [6] | Claude Sonnet 5 — 85,2% SWE-bench a $2/$10 | anthropic.com |
| [7] | Qwen3-Coder-480B — 93,9% HumanEval; uptime ~72,4% | OpenRouter / Alibaba |
| [8] | Análise de custo router 3-tier | Simulação do plano (50 tasks/dia) |
| [9] | Worktree isolation commodity | Gemini CLI, Loop Engineer, WLP, girelay, Koi, hort |
| [10] | Loop Engineer (npm), @pi-agents/orchid | npm / GitHub |
| [11] | Ecossistema adversarial externo | ai-jury, Comfy, MMAR, rev4nchist, Aris |
| [12] | MCP — 18.032 servidores, 110M downloads/mês | modelcontextprotocol.io |
| [13] | A2A Protocol — v1.0, 150+ orgs, 5 SDKs | google.github.io/A2A |
| [14] | SKILL.md (25-30+ produtos); AGENTS.md (20+) | agentskills.io / agents.md |
| [15] | Auditoria das ~20 skills do usuário | Empírica (2026-08-03) |
| [16] | CVE-2026-55607 — path containment | Anthropic security advisory |
| [17] | Handoff schema v1 + WAVE_LOG.md | Design do plano |
| [18] | gVisor / Firecracker / Docker analysis | gvisor.dev / firecracker |
| [19] | Arquitetura de busca multi-provider | Adapter + RRF k=60 + circuit breaker |

---

*Pesquisa conduzida em 2026-08-03. Metodologia: 2 ondas de pesquisa multi-agente (9 ângulos, ~1.300 fontes), revisão adversarial com 10 afirmações testadas (5 confirmadas, 5 corrigidas), e síntese orientada a decisões de produto.*
