# Decisão — Auto-evolução contínua da skill (v3.7.0)

**Data:** 2026-08-23 · **Versão alvo:** v3.6.0 → v3.7.0 (metadata.version) · **Status:** aprovada (onda 2 — docs-base)
**Artefatos relacionados:** `LEARNINGS.md` (raiz, memória episódica), `scripts/evolve-skill.sh` (implementação em onda paralela), `docs/decisions/README.md` (histórico)

---

## Contexto

A skill roda de qualquer projeto do usuário: a casa é resolvida por symlink
(`SKILL.md` → `.claude/skills/deep-orchestrator-agent-skill/SKILL.md`) e a pasta
instalada fica em `~/.agents/skills/`. O usuário pediu que a skill **aprenda com
cada execução** e possa **modificar as próprias skills na pasta instalada** — sem
repetir erros, sem acumular lixo, sem aprendizado virando política executável não
revisada.

O problema tem três faces: (1) **captura** — registrar aprendizados de forma
determinística ao fim de cada execução; (2) **segurança** — impedir que conteúdo
não-confiável (web, sub-agente, diff, saída de modelo) envenene a memória ou o
corpo da skill; (3) **governança** — orçamento de tokens, contradições, semver,
commit e resolução de `SKILL_HOME` (instalação por symlink ou por cópia).

## Método

Pesquisa multi-agente dedicada (2026-08-23): **6 relatórios** cobrindo memória e
evolução contínua de agentes (ECC, Voyager, Reflexion, MemGPT, A-MEM, model
collapse), custo de contexto (ETH AGENTS.md, Context Rot, SkillReducer),
segurança de memória (Anthropic, OpenAI, OWASP LLM01, MLAS, V-S4/V-S5,
Microsoft), contradição/consolidação (STALE, MemStrata, LatticeMind, RecMem,
cq/Mozilla), drift (Skill Drift, Habituation) e a spec oficial de Agent Skills.
As fontes foram verificadas por fetch direto pelos pesquisadores; nenhuma URL
abaixo é inferida.

## Decisões

### D1 — CAPTURA ≠ PROMOÇÃO

- **Decisão:** a captura é **determinística** e acontece no fim de cada execução
  via **script** (`scripts/evolve-skill.sh add`), NÃO via instrução de skill — hooks
  disparam 100% das vezes, instruções de skill 50–80%. A promoção ao corpo da
  skill é **cirúrgica**: exige evidência (≥2 ocorrências da mesma surpresa OU
  confirmação explícita do usuário), gera diff git revisável e **nunca** se
  auto-mergeia.
- **Evidência:** ECC `continuous-learning-v2` separa captura (append-only) de
  promoção (review); o precedente local `meta-evolution`/`meta-consolidation` já
  exige diff para humano e nunca persiste instrução de conteúdo não-confiável.
- **Fonte:** github.com/affaan-m/ECC (continuous-learning-v2); ~/.agents/skills/meta-evolution e meta-consolidation (SKILL.md).

### D2 — ANTI-POISONING COMO CÓDIGO

- **Decisão:** `source` é campo **obrigatório** em toda entrada
  (`user | repo-doc | sub-agent | web | diff | model-output`); sem source a entrada
  é **rejeitada**. `web`, `sub-agent`, `diff` e `model-output` são classificados
  **UNTRUSTED** e **nunca promovem** ao corpo da skill. O `add` roda scan de
  segredos antes de persistir.
- **Evidência:** Anthropic trata poisoning como problema **estrutural** (defesa em
  profundidade, não filtro); OpenAI mostra filtragem insuficiente contra prompt
  injection; OWASP LLM01 o classifica como risco top-1; MLAS e V-S4/V-S5 atacam
  memory poisoning; Microsoft exige origem rastreável na memória de agente.
- **Fonte:** platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks;
  openai.com/index/designing-agents-to-resist-prompt-injection;
  genai.owasp.org/llmrisk/llm01-prompt-injection; arxiv.org/abs/2606.23075 (MLAS);
  arxiv.org/abs/2606.04329 (V-S4/V-S5);
  learn.microsoft.com/en-us/security/zero-trust/sfi/manage-agentic-memory-safety (Microsoft — Manage AI memory safety in agentic systems).

### D3 — NO_SELF_VALIDATION

- **Decisão:** aprendizado derivado da própria execução **nunca se auto-promove** —
  "executou sem erro" não valida conhecimento. A validação vem de fonte externa
  (usuário, repo-doc) ou de recorrência observada em execuções independentes.
- **Evidência:** V-S4/V-S5 incluem `NO_SELF_VALIDATION` entre as defesas contra
  poisoning de memória; auto-avaliação sem âncora externa é o vetor clássico de
  self-consistency falha.
- **Fonte:** arxiv.org/abs/2606.04329 (V-S4/V-S5).

### D4 — ORÇAMENTO

- **Decisão:** `LEARNINGS.md` com **índice ≤ 30 linhas**, **entradas ativas ≤ 100
  linhas somadas**, **arquivo ≤ 400 linhas**; `SKILL.md` < 500 linhas / ~5k tokens;
  overflow → `learnings_archive.md`; `consolidate` é **obrigatório** ao atingir o
  teto. Memória é carregada sob demanda (progressive disclosure).
- **Evidência:** ETH Zurich (AGENTS.md) mede context files a **+20% de tokens sem
  ganho**, mas instruções específicas SÃO seguidas — manter o arquivo enxuto e
  específico; SkillReducer mostra less-is-more (+2,8%); Context Rot mostra
  degradação sem curadoria.
- **Fonte:** arxiv.org/abs/2602.11988; arxiv.org/abs/2603.29919 (SkillReducer);
  trychroma.com/research/context-rot.

### D5 — CONTRADIÇÃO NA ESCRITA

- **Decisão:** em contradição, **a mais nova vence na hora da escrita**: a antiga
  vira `status: superseded`, ganha `supersedes: "<id da nova>"` e o corpo é marcado
  `~~…~~ (obsoleto AAAA-MM-DD: motivo)`. A detecção é **determinística** no
  consolidate por `type + tags + título` (checks simbólicos; LLM só para
  ambiguidade semântica residual).
- **Evidência:** STALE mostra revisão na escrita superando revisão tardia (55,2%);
  MemStrata mostra RAG servindo valor superado em 15–40% sem supersessão
  determinística; LatticeMind usa checks simbólicos + LLM só no estrato semântico.
- **Fonte:** arxiv.org/abs/2605.06527 (STALE); arxiv.org/abs/2606.26511 (MemStrata);
  arxiv.org/abs/2608.08236 (LatticeMind).

### D6 — ESCOPO

- **Decisão:** conhecimento específico de repo **não polui** o global: o corpo da
  skill só recebe conhecimento **geral verificado**. Aprendizado project-scoped
  fica no `LEARNINGS.md` do projeto; promoção global exige generalização
  demonstrada.
- **Evidência:** ECC v2 promove para o global só com **≥2 projetos** e confiança
  **≥0.8**; "What Fits Doesn't Overfit" mostra que conhecimento compressível
  (geral) é o que generaliza.
- **Fonte:** github.com/affaan-m/ECC (continuous-learning-v2).

### D7 — CONTRATO EXECUTÁVEL

- **Decisão:** toda entrada promovida carrega **contrato** (comando/versão/path) e
  o consolidate **revalida** o contrato com checks determinísticos (`command -v`,
  `grep`). Validar contratos = **0 falsos positivos** vs **40%** monitorando
  valores de saída.
- **Evidência:** "Skill Drift Is Contract Violation" mostra que drift é violação
  de contrato e que a validação determinística do contrato (o que existe/roda)
  supera a validação por valor observado.
- **Fonte:** arxiv.org/abs/2605.10990 (Skill Drift).

### D8 — COMMIT

- **Decisão:** `apply` sem flags usa um **default inteligente**: se as **únicas**
  mudanças forem em `LEARNINGS.md`/`learnings_archive.md` → **commit direto** no
  branch atual com mensagem convencional `evolve(learnings): …` (memória é
  contexto, reversível por git); se tocar `SKILL.md`/`prompts`/`docs`/`README`/
  `check-install`/`CHANGELOG` → **branch** `evolve/YYYY-MM-DD` + diff para
  revisão humana. `--direct`/`--branch` **forçam** o modo. CI (`bash -n` +
  `shellcheck -S error` + suíte de testes) é o gate real de qualidade.
- **Evidência:** Habituation at the Gate mostra humanos lenientes em review
  (30,1→36,8%) — PRs de IA não revisados degradam; Voyager opera
  write-verify-store com verificação automática.
- **Fonte:** arxiv.org/abs/2606.22721 (Habituation); arxiv.org/abs/2305.16291 (Voyager).

### D9 — FREQUÊNCIA

- **Decisão:** **não evoluir a cada run** sem candidato qualificado. O passo de
  evolução é **idempotente** e **nunca falha a execução**: sem candidato, exit 0
  sem mudanças.
- **Evidência:** cq (Mozilla) só evolui com retrospectiva + sinal de
  generalizabilidade; RecMem mostra consolidação por recorrência com **−87% de
  custo** versus consolidar a cada passo.
- **Fonte:** github.com/mozilla-ai/cq; arxiv.org/abs/2605.16045 (RecMem).

### D10 — SEMVER

- **Decisão:** `metadata.version` **3.6.0 → 3.7.0** no formato exato
  `  version: "X.Y.Z"` — o que o `scripts/sync-global-skill.sh` parseia com `sed`
  (linha 82). Regras: **MAJOR** = quebra de contrato (raro, humano); **MINOR** =
  capacidade nova; **PATCH** = fix. Pela spec de Agent Skills, `version` vive
  **somente** no bloco `metadata` — campos top-level desconhecidos quebram loaders.
- **Evidência:** `scripts/sync-global-skill.sh` (sed parse da versão, confirmado no
  repo); spec Agent Skills (metadata-only version).
- **Fonte:** github.com/anthropics/skills/blob/main/agent_skills_spec.md;
  agentskills.io/specification; scripts/sync-global-skill.sh (repo).

### D11 — RESOLUÇÃO

- **Decisão:** o script resolve `SKILL_HOME` pela **própria localização**:
  `cd "$(dirname "$BASH_SOURCE")" && pwd -P` (resolver o symlink) →
  `git rev-parse --show-toplevel` (achar a raiz do repo). Instalação por **cópia
  sem `.git`** → **recusa** com instrução (rodar `sync-global-skill.sh` para
  converter em symlink). `flock` no apply para evitar corrida entre execuções
  paralelas.
- **Evidência:** a própria skill resolve a casa por `pwd -P` (symlink
  `SKILL.md` → `.claude/skills/...`); `sync-global-skill.sh` já instala por symlink.
- **Fonte:** repo (SKILL.md symlink; scripts/sync-global-skill.sh).

---

## Referências (pesquisa multi-agente, 2026-08-23)

- ECC: github.com/affaan-m/ECC (continuous-learning-v2, docs/design/ecc-memory-vault.md, schemas/memory.schema.json, commands/evolve.md)
- Voyager: arxiv.org/abs/2305.16291 · Reflexion: arxiv.org/abs/2303.11366 · AgentOptimizer: arxiv.org/abs/2402.11359 · MemGPT: arxiv.org/abs/2310.08560 · A-MEM: arxiv.org/abs/2502.12110 · Model collapse (Nature 2024): arxiv.org/abs/2305.17493
- ETH Zurich AGENTS.md: arxiv.org/abs/2602.11988 · STALE: arxiv.org/abs/2605.06527 · MemStrata: arxiv.org/abs/2606.26511 · LatticeMind: arxiv.org/abs/2608.08236 · RecMem: arxiv.org/abs/2605.16045 · Skill Drift: arxiv.org/abs/2605.10990 · Habituation: arxiv.org/abs/2606.22721 · MLAS: arxiv.org/abs/2606.23075 · V-S4/V-S5: arxiv.org/abs/2606.04329 · RSI survey: arxiv.org/abs/2607.07663 · SkillReducer: arxiv.org/abs/2603.29919 · Context Rot: trychroma.com/research/context-rot
- Anthropic: platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks · anthropic.com/engineering/how-we-contain-claude · code.claude.com/docs/en/skills · code.claude.com/docs/en/memory
- Microsoft: learn.microsoft.com/en-us/security/zero-trust/sfi/manage-agentic-memory-safety (Manage AI memory safety in agentic systems — zero-trust)
- OpenAI: openai.com/index/designing-agents-to-resist-prompt-injection · OWASP: genai.owasp.org/llmrisk/llm01-prompt-injection
- Spec Agent Skills: github.com/anthropics/skills/blob/main/agent_skills_spec.md · agentskills.io/specification
- cq (Mozilla): github.com/mozilla-ai/cq · claude-memory-compiler: github.com/coleam00/claude-memory-compiler · lesson-learned: github.com/rscova/claude-lesson-learned · agent-memory-loop: github.com/zurbrick/agent-memory-loop
- Precedentes locais: ~/.agents/skills/meta-evolution e meta-consolidation (SKILL.md)
