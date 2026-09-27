# D33 — Pesquisa 100% Tavily: remoção do fornecedor anterior + PREMISSA de chave (v6.0.0)

- **Data:** 2026-09-27
- **Estado:** ACEITE (executada)
- **Série:** D33 da série contínua (ver NAMESPACE em `docs/decisions/README.md`).

## Contexto

O fornecedor de pesquisa anterior foi descontinuado: repositório local apagado
(a exclusão no GitHub foi adiada pelo utilizador). Toda a pesquisa passa a ser
feita pela **tavily-agent-skill** (API Tavily, rotação de chaves interna).

## Decisão

1. **Canal único = tavily-agent-skill** (`python3 <tavily-agent-skill>/scripts/tavily.py`).
   Nenhum outro buscador, fallback ou caminho.
2. **PREMISSA DE TRABALHO (novo):** antes de iniciar qualquer execução que
   exija pesquisa, o orquestrador roda `"$DO_TAVILY_GATE" premise`:
   - `TAVILY_PREMISE=ok` → segue;
   - `skill-missing` / `key-missing` / `key-invalid` → **NÃO inicia**: pausa e
     **PEDE UMA CHAVE Tavily AO USUÁRIO** (nunca aceita chave colada no chat);
     o utilizador regista com `tavily.py keys add "tvly-..."` e o orquestrador
     revalida (`premise` valida ao vivo via `/usage`, sem créditos) antes de
     trabalhar. R9 mantém-se: nunca instala nada sozinho.
3. **Mudanças de contrato (v6.0.0):**
   - `scripts/tavily-gate.sh` (substituiu o gate do fornecedor removido) (novos verbos `gate` e
     **`premise`**; veredito `TAVILY_GATE=<0|78|127>`,
     `TAVILY_CODE=<TavilySkillMissing|TavilyKeyMissing|TavilyQuotaExhausted|
     TavilyAllBanned|TavilyUnknown>`; modo `SEARCH_MODE`);
   - **`tavily-sub-agents=N`** (substituiu a flag do fornecedor removido) (`DO_TAVILY_SUB_AGENTS`);
   - `scripts/surf-gate.sh` → `scripts/tavily-gate.sh` (novos verbos `gate` e
     **`premise`**; veredito `TAVILY_GATE=<0|78|127>`,
     `TAVILY_CODE=<TavilySkillMissing|TavilyKeyMissing|TavilyQuotaExhausted|
     TavilyAllBanned|TavilyUnknown>`; modo `SEARCH_MODE`);
   - `surf-sub-agents=N` → **`tavily-sub-agents=N`** (`DO_TAVILY_SUB_AGENTS`);
   - handoff `SEARCH_STATUS: … | BLOCKED_NOKEY` (antes BLOCKED_78);
   - bloco da pergunta PESQUISA-FALHOU reescrito para comandos Tavily
     (CONTRATO.md §5.1 = `print_question` byte-a-byte);
   - casos de degradação `tavily-ausente` / `tavily-key-invalida`.
4. **Limpeza total:** todas as menções ao fornecedor anterior removidas do
   repo (vivos e históricos — nomes neutralizados para "fornecedor removido"),
   artefactos obsoletos apagados (PLANO-MELHORIAS.*, TEST-REPORT.md, EXPLAINER.html,
   PROMPT-XML-*). O mesmo varrimento é aplicado no macOS (macmini) e nesta máquina.

## Verificação

- Suíte completa: **946 asserções, 0 FAIL** (contencao 312, contrato 52, evolve
  81, flags 325, plan-approval 139, **tavily-gate 37** — suíte nova T1–T11 com
  `tavily.py` mockado: fail-closed, premise, classify anti-eco, scrub de
  chaves, pausa/retomada, bloco da pergunta byte-a-byte em 3 donos).
- varrimento por nome do fornecedor removido no repo: **0** (exceto apps não relacionados).
- `grep -ri 'surf|brave'` no repo: **0** (exceto apps não relacionados).
