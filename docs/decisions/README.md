# Decisões de produto — deep-orchestrator-agent-skill (histórico)

**Origem:** artefatos da pesquisa multi-agente de 2026-08-03 (2 ondas, ~1.300
fontes, revisão adversarial) que planejava a versão "v3.2" do
deep-orchestrator-agent-skill com 7 decisões priorizadas por impacto × urgência.
`RESEARCH_PLAN.md` é o plano da pesquisa; `RESEARCH_ANSWER.md` é a resposta
final com as 7 decisões (D1-D7), evidências e fontes.

**Por que docs/decisions/:** os artefatos ficaram órfãos em `research/` na
raiz — o v3.2.0 real implementou arquitetura DIFERENTE da planejada (ex.: a
busca 3-tier do repo substitui a arquitetura D2 do research, que era Adapter +
RRF + Tavily/Exa), e nada no repositório referenciava o material. A migração
(F4-05, 2026-08-14) preserva o raciocínio com o status real de cada decisão.

## Status por decisão (conferido em 2026-08-14)

| Decisão | Status na v3.2 real | Observação |
|---|---|---|
| D1 — Router de modelos 3-tier (Qwen3-Coder → DeepSeek V4-Flash → Claude) | NÃO implementada | Sem `config/router.yaml` nem módulo de roteamento no repo; a seleção de modelo continua externa (harness do usuário). As menções a "router" no repo são o project-router de repositórios-alvo, conceito distinto |
| D2 — Busca multi-provider (Adapter + RRF k=60 + Tavily/Exa) | SUPERADA pela v3.2 real | A v3.2 implementou a cadeia 3-tier interna (surf-agent-skill → Brave Search API → DuckDuckGo keyless) via `scripts/search.sh` + `scripts/search-parallel.sh` — arquitetura diferente, sem Tavily/Exa nem RRF, e sem provedor novo (decisão D3 do plano de melhorias) |
| D3 — Loop de qualidade nativo (testing subwaves assíncronas + adversarial) | IMPLEMENTADA (núcleo) | Subwaves assíncronas TESTING (`test-ondaN-*`) e VALIDATION (`val-ondaN-*`) + revisão adversarial do diff integrado, tudo no fluxo da skill; jury cross-vendor (parte v4 do plano) não |
| D4 — Handoff híbrido schema v1 (frontmatter + markdown + trace bruto) | PARCIAL | Handoffs estruturados e separação de planos existem no fluxo; o schema v1 com frontmatter YAML parseável + trace bruto anexado não foi adotado integralmente (sem WAVE_LOG.md na skill) |
| D5 — Plataforma de skills (SKILL.md + AGENTS.md dual) | PARCIAL | O formato SKILL.md foi adotado (este repositório é o exemplo, com frontmatter YAML e restrição de tools); o AGENTS.md dual não existe no repo |
| D6 — Isolamento (path containment + pre-flight; gVisor; Firecracker) | PARCIAL | Guard de contenção de path (RAIZ-DE-MUNDO / MODO CONTIDO, regra R8) + pre-flight implementados e testados (`scripts/test-contencao.sh`); gVisor (runsc) e Firecracker (v4/v5+ do plano) não |
| D7 — MCP essenciais agora; A2A em v4 | NÃO implementada | Sem evidência no repo de integração de servidores MCP nem de adoção de A2A |

## Pendências do research e destino

- **Pendência da linha 39 do RESEARCH_ANSWER.md (correção da Brave):**
  aplicada em 2026-08-14 durante a migração — a Brave é **METERED**: o plano
  gratuito (~$5/mês) foi encerrado em fev/2026 e o uso que excede a cota
  gratuita gera cobrança real (pay-as-you-go). O README da raiz ainda traz a
  afirmação antiga (linha 111); a correção dele está fora do escopo desta
  migração.
- **Artefatos de execução** (EXPLAINER.html) não pertencem a este diretório —
  ver `.gitignore` da raiz (decisão F4-05).
