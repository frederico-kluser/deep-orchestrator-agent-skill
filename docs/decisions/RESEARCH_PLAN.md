# Research Plan: Deep-Orchestrator — Suporte Completo ao Ecossistema

**Pergunta original:** Quais decisões arquiteturais e de produto o deep-orchestrator deve tomar para dar suporte a TODAS as ferramentas, modelos, APIs e plataformas do ecossistema do usuário?

**Modo:** deep | **Data:** 2026-08-03 | **Status:** CONCLUÍDO

## Ecossistema mapeado

| Categoria | Ferramentas |
|-----------|-------------|
| Harness | Claude Code (backend DeepSeek v4-pro) |
| Orquestração | deep-orchestrator |
| Terminal | claude-8000 (kitty) |
| Skills de UI | motion-plus-ui, motion-plus-animation, motion, html-explainer |
| Skills de pesquisa | surf-research-skill, surf-plan-skill, surf-free-skill |
| Skills de revisão | plannotator (annotate, last, review, setup-goal, visual-explainer, compound) |
| Skills de infra | huu_audit-and-improve-skills, huu_update-skill-docs-from-commit, worktree-dev-session |
| Outros | fast-video-convert, agent-ask-anywhere, one-prompt, dataviz |
| APIs/Busca | Brave Search API, OpenRouter |
| Protocolos | MCP, Git worktrees |

## Onda 1 — Fundação: Estado da arte + Ecossistema ✅

| Ângulo | Descrição | Fontes | Status |
|--------|-----------|--------|--------|
| 1.1 | Estado da arte multi-agent 2026 — 10 frameworks comparados | 194 | ✅ |
| 1.2 | Ecossistema de integrações (APIs, modelos, MCP, plataformas) | 239 | ✅ |
| 1.3 | Skill composition e handoff protocols | 96 | ✅ |

**Premissas refutadas na Onda 1:**
- Brave Search como única API ❌
- DeepSeek como backend único ❌
- Handoffs em markdown livre ❌

## Onda 2 — Decisões de Produto ✅

| Ângulo | Decisão que alimenta | Fontes | Status |
|--------|---------------------|--------|--------|
| 2.1 | Arquitetura de busca plugável (Tavily+Brazil+Exa) | 178+ | ✅ |
| 2.2 | Model router por dificuldade (thresholds, custo) | 197 | ✅ |
| 2.3 | Schema de handoff híbrido JSON+markdown v1 | 141 | ✅ |
| 2.4 | Isolamento em camadas (worktree→container→microVM) | 59+ | ✅ |
| 2.5 | Portabilidade SKILL.md + AGENTS.md (auditoria das ~20 skills) | 52+ | ✅ |
| 2.6 | A2A Protocol para comunicação agent↔agent | 44 | ✅ |

## REPLAN 1 (pós-Onda 1) ✅
- 6 ângulos definidos para Onda 2, cada um alimentando uma decisão concreta

## REPLAN 2 (pós-Onda 2) ✅
- **CONVERGÊNCIA** — 7/7 decisões com fundamentação suficiente

## VERIFY — Revisão Adversarial ✅
- 10 afirmações testadas: 5 confirmadas, 5 refutadas/corrigidas

## SYNTHESIZE — Resposta Final ✅
- 7 decisões de produto com timeline, esforço e evidência
- Ver `RESEARCH_ANSWER.md` (mesmo diretório)

## Correções da revisão adversarial
- **A1:** Worktree isolation virou commodity em 2026 (não é mais diferenciador isolado)
- **A2:** Loop Engineer tem TEST gated no loop (testing subwaves assíncronas paralelas ainda potencialmente único)
- **A5:** DeepSeek V4-Flash-0731 (31/jul/2026) marcou DeepSWE 54.4 vs 58.0 Opus 4.8 — muda recomendação de modelo
- **A6:** Paper Handoff Debt mostra raw trace (57-59%) > structured notes (29-44%) — handoff deve ser híbrido + trace
- **A10:** Qwen3-Coder oficial é 93.9% HumanEval (não 89.3%); uptime 72.4% exige fallback obrigatório

## Fontes totais
~1.300 fontes únicas em 9 ângulos de pesquisa + revisão adversarial
