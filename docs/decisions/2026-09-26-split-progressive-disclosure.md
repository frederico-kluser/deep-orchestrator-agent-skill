# D32 — Split do SKILL.md em arquitetura progressive disclosure (v5.0.0)

- **Data:** 2026-09-26
- **Estado:** ACEITE (executada)
- **Supersede:** o "Fatiar o SKILL.md em arquivos de referência — TRABALHO FUTURO"
  registado em `docs/decisions/2026-09-20-limpeza-por-tarefa-pergunta-pesquisa-flags.md`
  (fora de escopo na v4.1.0) — o trabalho foi feito agora.
- **Série:** D32 da série contínua (D12–D31 na v3.8.0–v4.1.0). Ver NAMESPACE em
  `docs/decisions/README.md` — citar sempre com o documento.

## Contexto

O SKILL.md da v4.1.0 era um monólito de 3 306 linhas / 220 KB (~35k tokens)
carregado INTEIRO por invocação — ~11× o orçamento recomendado para o corpo de
uma skill (<5k tokens; agentskills.io + guia oficial Anthropic). Auditoria com
7 subagentes (3 internas + 4 pesquisas Tavily) confirmou: ~60% do conteúdo só
servia em modos específicos (plan=on, no-test, only-e2e), a pesquisa tinha 3
encarnações, e havia drift factual (surf "v8" vs "v9+") — sintomas de "rule
soup" (Curse of Instructions).

## Decisão

**Router magro + `references/` + `prompts/` carregados sob demanda**, dentro da
MESMA skill — e não N skills separadas (cada skill paga 30–100 tokens fixos de
listagem e o skill listing do Claude Code corta descrições silenciosamente ao
transbordar 1% da janela). Layout:

- `SKILL.md` (router, ≤500 linhas): frontmatter, identity, R1–R10 (com
  severidades graduadas — FATAL só R1/R8), `<navigation>` (mapa de fases,
  cargas condicionais, índice de sintomas), ponteiros.
- `references/*.md` (1 HOP, um só nível): phase0-context, analyze-plan,
  research-protocol (canónico da pesquisa), plan-approval, execute-wave,
  commit-final, final-report, degradation, examples, placeholders.
- `prompts/*.md`: os 6 templates de sub-agente (carregam SÓ no dispatch) ao
  lado dos 5 ficheiros ECC já existentes.
- `CONTRATO.md`: fonte única dos contratos de máquina (exit codes, marcadores,
  literais congelados, flags, política de retries), validada por
  `scripts/test-contrato.sh` (52 asserções).

### Decisões de desenho (D-A…D-H do plano)

| # | Decisão |
|---|---|
| D-A | Router continua em **XML** `<orchestrator>` (evita churn do parser do teste) |
| D-B | FASEs 1+2 e 4 em ficheiros próprios (`analyze-plan.md`, `commit-final.md`) |
| D-C/D-D | Passos condicionais ficam nos módulos inteiros; cartão do `do-wt.sh checklist` mantém briefing autónomo, sincronizado por teste (A55/B01) |
| D-E | Bug de locale do `sort -n` (decimais) no G12 → comparação em ordem de ficheiro |
| D-F | Conteúdo extraído **verbatim** (muda de dono, não de texto) |
| D-G | `max-parallel=N` (→ `DO_MAX_PARALLEL`) é a flag ÚNICA de concorrência, de 1ª classe; `surf-sub-agents=N` sub-flag de pesquisa (nunca multiplicada) |
| D-H | **Modelo único `mimo-v2.6-pro` em TUDO** (`model: inherit`): TIERING por modelo removido (FASE 3 passo 3) e "modelo FORTE" removido (FASE 4); proibido flash/downgrade |

## Alternativas rejeitadas

- **N skills separadas** (task-*/knowledge-*/meta-*): custo fixo de listagem,
  risco de corte silencioso de descrições, e o material é 100% condicional à
  mesma tarefa — não tem valor autónomo (exceção futura possível: auto-evolução).
- **Converter o router para Markdown**: pouparia 10–15% em tags, mas o
  `<orchestrator>` é parseado como XML pelos testes (G12) — não justifica o risco.
- **Gerar o cartão da onda a partir de `references/execute-wave.md`**: o cartão
  é um briefing operacional autónomo (re-ancoragem pós-compactação); a
  sincronização por teste (A55/B01) é suficiente.

## Consequências

- Router: 3 306 → ~500 linhas; contexto permanente por invocação: 220 KB →
  ~45 KB; com `plan=off` + `no-test` o material carregado cai ~60%.
- Toda a extração foi verbatim e está coberta por 1 120 asserções verdes
  (6 suítes: contencao 312, contrato 52, evolve 81, flags 307, plan-approval
  139, surf-gate 229).
- Novos pontos de sincronização CONGELADOS em `CONTRATO.md`: lista canónica de
  módulos (§6), ponteiros `<phase ref=...>` (validados pelo CT9), literais
  byte-a-byte (CT2–CT7).
- Custo: uma leitura extra por fase; o `<navigation>` do router é o mapa.
- `do-wt.sh discard-state` (FASE 5) substitui a prosa do descarte de estado —
  comportamento idêntico, agora testado (A57).

## Verificação

```bash
for t in scripts/test-*.sh; do bash "$t"; done   # 1120 PASS / 0 FAIL
bash scripts/check-install.sh                     # exit 0
wc -l .claude/skills/deep-orchestrator-agent-skill/SKILL.md   # <= 500
```
