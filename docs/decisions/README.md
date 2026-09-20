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

## Status por decisão (conferido em 2026-08-14; D2 reconferida em 2026-08-29)

| Decisão | Status na v3.2 real | Observação |
|---|---|---|
| D1 — Router de modelos 3-tier (Qwen3-Coder → DeepSeek V4-Flash → Claude) | NÃO implementada | Sem `config/router.yaml` nem módulo de roteamento no repo; a seleção de modelo continua externa (harness do usuário). As menções a "router" no repo são o project-router de repositórios-alvo, conceito distinto |
| D2 — Busca multi-provider (Adapter + RRF k=60 + Tavily/Exa) | SUPERADA pela v3.2 real | A v3.2 implementou a cadeia 3-tier interna (surf-agent-skill → Brave Search API → DuckDuckGo keyless) via `scripts/search.sh` + `scripts/search-parallel.sh` — arquitetura diferente, sem Tavily/Exa nem RRF, e sem provedor novo (decisão D3 do plano de melhorias) — **SUPERADA de novo em 2026-08-29 (D23)**: a cadeia 3-tier foi REMOVIDA; a pesquisa é 100% surf-agent-skill v8 (Brave-only), e sem chave válida a execução para com exit 78. Ver `2026-08-29-surf-agent-skill-obrigatorio.md` |
| D3 — Loop de qualidade nativo (testing subwaves assíncronas + adversarial) | IMPLEMENTADA (núcleo) | Subwaves assíncronas TESTING (`test-ondaN-*`) e VALIDATION (`val-ondaN-*`) + revisão adversarial do diff integrado, tudo no fluxo da skill; jury cross-vendor (parte v4 do plano) não |
| D4 — Handoff híbrido schema v1 (frontmatter + markdown + trace bruto) | PARCIAL | Handoffs estruturados e separação de planos existem no fluxo; o schema v1 com frontmatter YAML parseável + trace bruto anexado não foi adotado integralmente (sem WAVE_LOG.md na skill) |
| D5 — Plataforma de skills (SKILL.md + AGENTS.md dual) | PARCIAL | O formato SKILL.md foi adotado (este repositório é o exemplo, com frontmatter YAML e restrição de tools); o AGENTS.md dual não existe no repo |
| D6 — Isolamento (path containment + pre-flight; gVisor; Firecracker) | PARCIAL | Guard de contenção de path (RAIZ-DE-MUNDO / MODO CONTIDO, regra R8) + pre-flight implementados e testados (`scripts/test-contencao.sh`); gVisor (runsc) e Firecracker (v4/v5+ do plano) não |
| D7 — MCP essenciais agora; A2A em v4 | NÃO implementada | Sem evidência no repo de integração de servidores MCP nem de adoção de A2A |

## Pendências do research e destino

- **Pendência da linha 39 do RESEARCH_ANSWER.md (correção da Brave):**
  **ENCERRADA em 2026-08-29 (D23).** A Brave deixou de ser gerida por esta
  skill: chave, validação, metering e rate limiting passaram todos para a
  surf-agent-skill v8. O único sinal que consumimos é o exit 78 ("não há chave
  Brave válida"). O ponteiro para "README linha 111" já estava quebrado por
  deriva de linha, e a afirmação que ele apontava deixou de ser desta skill.
  Ver `2026-08-29-surf-agent-skill-obrigatorio.md`.
- **Artefatos de execução** (EXPLAINER.html) não pertencem a este diretório —
  ver `.gitignore` da raiz (decisão F4-05).

## Decisões da v3.8.0 (2026-08-27)

`2026-08-27-questionario-evolucao.md` registra D12–D17: agente de evolução
fresco (D12), questionário sempre com página própria e sem limite de tempo
(D13), gate humano obrigatório — nada aplicado sem resposta (D14), prefs
gitignored com LEARNINGS.md removido do repo (D15), escrita só por script +
.gitignore automático (D16), nunca bloqueia (D17). A memória da skill migrou
para `.deep-orchestrator-preferences/` (projeto e skill) e o
`evolve-skill.sh` não commita mais aprendizados.

## Decisões da v3.9.0 (2026-08-28)

`2026-08-28-pergunta-evolucao-terminal.md` registra D18–D22: evolução como
PERGUNTA EM TEXTO no terminal, nunca mais um site (D18), gramática `N:XY`
com a opção escolhida virando a ação salva (D19), flag `no-evolve` pulando a
pergunta e o pós-processamento (D20), posição depois de TUDO (commit + push +
relatório) com continuação na FASE 0 passo 0.4 (D21; desde a v4.1.0 é o
passo 0 — ESTADOS PENDENTES, D31), e prefixo `mp=N` → `max-parallel=N` (D22).
O portão de aprovação do plano (FASE 2.5) continua no Plannotator.

## Decisões da v4.0.0 (2026-08-29)

`2026-08-29-surf-agent-skill-obrigatorio.md` registra D23: a pesquisa web sai
desta skill — a surf-agent-skill v8 (Brave-only) vira dependência dura, os
seis scripts de busca internos foram removidos e sem chave Brave válida a
execução para (exit 78). Dois pontos desse registro foram revistos na v4.1.0
(D27): o portão deixou de ser `surf doctor` com "1 = prossiga" (fail-open) e
virou `scripts/surf-gate.sh` (fail-closed); e a afirmação de que o cache de
validação substituía a sonda de crédito foi corrigida, com nota datada, no
próprio arquivo.

## Decisões da v4.1.0 (2026-09-20)

`2026-09-20-limpeza-por-tarefa-pergunta-pesquisa-flags.md` registra D24–D31,
resposta à auditoria de 2026-09-20 (7 lentes, achados reproduzidos em lab):
registro RETROATIVO da R8j do commit `fe3a1c2` — `wt=` termina em commit +
push, nunca merge de volta, `purge` como rede final — mais a reentrada do
`wt=<nome>` (D24); limpeza POR TAREFA no instante do gate verde, feita pelo
script (`integrate` → `gate` → `finish`; `close` para o que não integra), com
ledger `owned.tsv` de 11 colunas, `ledger`/`checklist` e lock sem `flock(1)`
(D25); portão inter-onda `sweep && assert-clean --wave <N+1>`, `new` que
recusa onda com sobra (rc 6), merge que não suja a raiz nem marca MERGED um
squash vazio, e `purge` que nunca esconde o que não foi integrado (rc 3 +
seção "Não integrado" obrigatória; título "Tarefa concluída PARCIALMENTE")
(D26); protocolo PESQUISA-FALHOU — pergunta em TEXTO, INCONDICIONAL (vence
autonomia, `no-stop` e `plan=off`), `SEARCH_STATUS` no handoff,
`SEARCH_REQUIRED` no plano, `scripts/surf-gate.sh` fail-closed com
`classify`/`pause`/`resume --probe`, porque cota/429/402 saem exit 1 e não 78
(D27); flag `no-test` — não criar ≠ não rodar (D28); flag `only-e2e` e o eixo
`DO_TEST_MODE=full|none|e2e`, com cobertura por JORNADA (D29); flag
`do-question` — o orquestrador PODE perguntar, e a pergunta da chave Brave
não depende dela (D30); e os estruturais — `--flags='<TOKENS>'` com ZONA DE
PREFIXO e o `do-context.sh` como único validador, `description` ≤ 1024, FASE
0 reordenada, alvo macOS / bash 3.2.57 (D31). Fatiar o `SKILL.md` em arquivos
de referência ficou registrado como trabalho futuro.

**Namespace:** os registros datados formam UMA série contínua — D1–D11
(`2026-08-23-auto-evolucao.md`), D12–D17, D18–D22, D23, D24–D31. Ela NÃO é a
série D1–D7 da tabela acima (research de 2026-08-03) nem a D1–D4 do
`PLANO-MELHORIAS.xml`: ao citar um D abaixo de 12, diga de qual documento (o
D23 já faz isso para os "dois D3").
