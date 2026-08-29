# Estudo e Técnica — Skill que se Auto-Evolui

> **Versão aplicada:** v3.7.0 da deep-orchestrator-agent-skill · **Data:** 2026-08-23
> **Escopo:** como uma Agent Skill aprende com cada execução, persiste o aprendizado na
> própria pasta de instalação e evolui sem repetir os mesmos erros — com pesquisa
> multi-agente (6 frentes, fontes verificadas por fetch direto), design com
> salvaguardas e validação adversarial.

---

## 1. Objetivo

Uma skill de agente roda de **qualquer projeto** (instalada por symlink). O pedido:
*"não importa onde for chamada, se ela aprender algo novo, que possa modificar as
skills dentro da pasta onde está instalada, para evoluir continuamente e não repetir
os mesmos erros — pesquise como fazer isso da maneira correta e aplique."*

A resposta implementada tem três camadas:

1. **Captura determinística** — ao fim de cada execução, o orquestrador coleta
   aprendizados (surpresas, correções, anti-padrões, falhas de gate, achados de
   revisão) e os persiste num `LEARNINGS.md` na pasta da própria skill.
2. **Memória ≠ política** — o `LEARNINGS.md` é contexto *não revisado* (commita
   direto, é reversível); a promoção ao corpo do SKILL.md é **cirúrgica**, exige
   evidência e vira diff de revisão humana.
3. **Anti-poisoning como código** — fonte obrigatória, conteúdo não-confiável nunca
   vira instrução, contradição é marcada (nunca apagada), orçamento com consolidação.

---

## 2. O estudo (pesquisa multi-agente)

**Método:** 6 sub-agentes paralelos de pesquisa (interface de busca 3-tier vigente na v3.7.0;
~135 + 252 + 326 + 12×12 resultados únicos; fontes primárias verificadas por
fetch direto — repo ECC, arXiv via export API, docs oficiais Anthropic/OpenAI/
OWASP/Microsoft). Nenhum fato foi inventado; cada relatório trouxe achados
numerados, URLs e contra-evidências.

### 2.1 As 6 frentes de pesquisa

| Frente | Pergunta | Relatório-chave |
|---|---|---|
| ECC (Everything Claude Code) | Como o `/evolve`, o continuous-learning v2 e o memory vault funcionam de verdade (no código)? | affaan-m/ECC: `skills/continuous-learning-v2/`, `commands/evolve.md`, `instinct-cli.py`, `docs/design/ecc-memory-vault.md` |
| Arquiteturas self-improving | O que a literatura prova que funciona (Voyager, Reflexion, AgentOptimizer, MemGPT, A-MEM) e o que falha? | arXiv 2305.16291, 2303.11366, 2402.11359, 2310.08560, 2502.12110, 2305.17493, 2607.07663 |
| Guardrails anti-poisoning | Como ingerir aprendizado de fontes externas sem envenenar a skill (injection, gate humano, provenance)? | Anthropic/OpenAI/OWASP/Microsoft; arXiv 2606.04329 (V-S4/V-S5), 2606.23075 (MLAS), 2602.15654, 2512.16962, 2305.16291 |
| Convenções de skill/LEARNINGS | Qual o formato canônico de skills e de memória de aprendizado, com orçamento de tokens? | spec oficial Agent Skills (anthropics/skills), agentskills.io, ECC, OKF, MindStudio, SkillReducer (arXiv 2603.29919) |
| Automação do loop | Como automatizar captura no fim da execução, git revisável, CI e semver? | claude-lesson-learned, claude-memory-compiler, cq (Mozilla), agent-memory-loop, conventional commits, Habituation at the Gate (2606.22721) |
| Modos de falha da memória | Bloat, contradição, stale, overfitting, custo, skill rot — e mitigações com evidência | ETH 2602.11988, Lost in the Middle, Context Rot, STALE, MemStrata, LatticeMind, RecMem, Skill Drift = Contract Violation |

### 2.2 Achados centrais (condensados, com fontes)

**Captura ≠ promoção (a lição nº 1).** O ECC abandonou o continuous-learning v1
porque *skills disparam 50–80% das vezes; hooks disparam 100%* — captura tem que
ser **script/hook incondicional**, não uma skill que o agente "lembra" de invocar.
A promoção de memória a regra/skill é deliberadamente **não automatizada** no ECC:
*"a shell-capable agent cannot be treated as an independent human approval
boundary"*. (ECC continuous-learning v2; docs/design/ecc-memory-vault.md)

**Unidade atômica de aprendizado.** O ECC v2 usa *instincts*: um trigger, uma
ação, `confidence` (0.3–0.9), `domain`, evidência, escopo. Confiança com **decay e
contradição**: +0.05 por confirmação, −0.1 por correção, decay temporal. Escopo
projeto→global promovido só com ≥2 projetos e confiança média ≥0.8 (anti-contaminação
entre repos). (ECC continuous-learning-v2; `commands/evolve.md`; `instinct-cli.py`)

**Auto-verificação antes de persistir (Voyager).** Skill só entra na library após
verificação por um **critic separado** (estado + tarefa → booleano + crítica).
Ablação: sem auto-verificação → **−73% de itens descobertos** (o feedback mais
importante). Ressalva: critic LLM não é ground truth — prefira checagens executáveis
(build/test/lint). (arXiv 2305.16291)

**Síntese, não log cru (Reflexion).** O sinal de erro é destilado em resumo verbal
acionável na memória episódica — "log cru não é memória". 91% pass@1 no HumanEval.
(arXiv 2303.11366)

**Evolução com rollback (AgentOptimizer).** Funções como "parâmetros aprendíveis"
com operações Add/Revise/Remove e **roll-back + early-stop** contra um gate
mensurável — a infraestrutura exata é git: branch + diff + gate. (arXiv 2402.11359)

**Memória hierárquica (MemGPT/A-MEM).** Corpo curado (RAM) + memória episódica
(disco) + consolidação agendada; *"designing an agent's memory is essentially
context engineering"*. A-MEM: novas memórias atualizam as existentes — sem
"memory evolution", raciocínio multi-hop degrada. (arXiv 2310.08560; 2502.12110)

**Conteúdo sem curadoria degrada.** Model collapse (Nature 2024): treinar em dados
gerados causa defeitos irreversíveis. Survey RSI: ficar no lado **bounded e
avaliável** (loop fechado, critérios de aceite, humano no loop), nunca RSI aberto.
(arXiv 2305.17493; 2607.07663)

**A evidência ETH (cite corretamente).** arXiv 2602.11988 (Gloaguen et al., ETH
Zurich): context files (AGENTS.md) **não melhoram** a taxa de sucesso e custam
**>20% de inferência**; instruções específicas SÃO bem seguidas; overviews genéricos
não ajudam. **Não é** "conteúdo LLM degrada o agente" — é *"mais contexto não
verificado ≠ melhor; avalie cada adição"*. (arXiv 2602.11988)

**Anti-poisoning estrutural.** Conteúdo de terceiros entra só como `tool_result`;
o modelo deve saber o que o conteúdo é e de onde veio; screening com classificador
antes de agir; **filtragem é insuficiente** (detectar injeção ≈ detectar mentira) —
a defesa primária é **contenção de impacto**: least privilege, sandbox e **gate no
estágio Commit** (é onde o ataque "vira permanente"). (docs Anthropic; openai.com
designing-agents-to-resist-prompt-injection; OWASP LLM01; MLAS arXiv 2606.23075)

**Memory poisoning é o vetor esquecido.** V-S4 (skill criada sem validação) e
**V-S5 (self-improvement as amplification)**: "executou sem erro" vira validação e
a skill envenenada *evolui para um procedimento adversarial bem otimizado*. Zombie
Agents: payload sobrevive entre sessões. Defesas de prompt injection não cobrem
memory poisoning. (arXiv 2606.04329; 2602.15654; 2512.16962)

**O gate humano degrada — CI é o gate real.** Humanos ficam **lenientes** com
mudanças de agente (aprovação 30,1%→36,8%; latência +3,5×; comentários −22% —
*Habituation at the Gate*), e a maioria dos PRs de IA **nunca é revisada** por
humano. Conclusão: CI (validação + lint + contrato) é o gate; review humano
obrigatório só para mudanças de instrução, com diffs pequenos e atômicos.
(arXiv 2606.22721; 2605.02273)

**Contradição tratada na ESCRITA.** STALE: melhor modelo acerta só 55,2% em
conflitos implícitos; a revisão deve acontecer no write, não só na leitura.
MemStrata: RAG serve valor superado 15–40% das vezes; **supersessão determinística**
(subject/relation/object) zera isso — sem LLM. LatticeMind: checks simbólicos
baratos no write + LLM só para conflitos semânticos; registrar **qual claim vence e
por quê**. (arXiv 2605.06527; 2606.26511; 2608.08236)

**Volatilidade tem duas formas.** *Decay* (expira por natureza) vs *unconfirmed
drift* (nunca reconfirmado) — remédios diferentes; *"just remember everything makes
it worse"*. ECC ignora `one_time_fixes` e `external_api_issues` na origem.
(mem0.ai; ECC v1)

**Custo: consolidação por recorrência.** Consolidação eager (a cada interação) é
cara; por **recorrência** (só quando o padrão se repete) corta até **87% do custo**
e ainda supera a acurácia SOTA. Sob orçamento apertado, consolidar ganha +48%;
sob orçamento frouxo, reter cru é melhor. (arXiv 2605.16045; 2607.17545)

**Skill rot = contrato violado.** Monitorar valores → 40% de falsos positivos;
validar **contratos** (a versão/API/path/comando de que a instrução depende) → 0
falsos alarmes em 599 casos; reparo em 1 round sobe de 10% para 78%.
(arXiv 2605.10990)

**Formato e orçamento.** Spec oficial: frontmatter `name`+`description`
obrigatórios; `version` **só em `metadata:`** (campos top-level desconhecidos
quebram loaders); progressive disclosure (metadata pré-carregado, corpo lazy);
SKILL.md <500 linhas / ~5k tokens; SkillReducer (55.315 skills): só 38,5% do corpo
é regra acionável e **comprimir descrição −48% e corpo −39% MELHORA a qualidade
+2,8%** (less-is-more). (anthropics/skills spec; code.claude.com/docs/en/skills;
arXiv 2603.29919)

**Automação.** Hooks de fim de sessão são frágeis (SessionEnd mata async, timeout
1,5s) → hook grava **spool**, aplicação posterior nunca bloqueia. cq (Mozilla):
retrospectiva `/cq:reflect` com knowledge units, HITL na criação, dedup contra
cobertura, staleness `confirm_or_decay_after_90d`. Git como memória reversível:
conventional commits, branch de review, diffs atômicos. Semver para conteúdo é
contestado — o que importa é regra determinística + changelog + rollback.
(code.claude.com/docs/en/hooks; mozilla-ai/cq; conventionalcommits.org; semver.org;
hynek.me/articles/semver-will-not-save-you)

### 2.3 Síntese: o que o estudo decidiu

1. **Captura mecânica, promoção cirúrgica** (ECC/Voyager).
2. **Memória é contexto não-revisado; corpo da skill é política** (ECC/CoALA).
3. **Anti-poisoning por código**: fonte obrigatória e classificada; UNTRUSTED nunca
   promove; **NO_SELF_VALIDATION** (V-S5).
4. **Gate no Commit**: CI + diff revisável; humano só para instrução (Habituation).
5. **Contradição na escrita, supersessão determinística, nunca apagar** (STALE/
   MemStrata/LatticeMind).
6. **Orçamento duro com GC por tamanho** (ETH/SkillReducer).
7. **Contratos executáveis contra skill rot** (Skill Drift).
8. **Escopo**: conhecimento específico não polui o global (ECC v2).
9. **Consolidação por recorrência, não a cada execução** (RecMem).
10. **Semver determinístico** (metadata.version; MAJOR só humano).

---

## 3. A técnica (design implementado)

### 3.1 Arquitetura

```
                    ┌──────────────────────────────────────────────────┐
                    │            EXECUÇÃO DO ORQUESTRADOR              │
                    └──────────────────────────────────────────────────┘
 FASE 1 (planejar)     │ passo 8.5: evolve-skill.sh search "<tema>"    │
   consulta memória ◄──┘   (aprendizados relevantes informam o plano)  │
                    ┌──────────────────────────────────────────────────┐
 FASE 4 (final)     │ passo 6.5: EVOLUÇÃO PÓS-EXECUÇÃO                 │
   COLETA (retrospectiva) → FILTRO (evolution-guide) → ADD → APPLY     │
                    └──────────────────────────────────────────────────┘
                                        │
                                        ▼
              scripts/evolve-skill.sh  (resolve o repo da skill por
              ┌────────────────────────  symlink — funciona de qualquer cwd)
              │  add ──► valida → LEARNINGS.md (memória, append-only)
              │  search ─► consulta LEARNINGS + prompts + SKILL.md
              │  diff / apply ─► só memória → commit direto
              │                     corpo → branch evolve/YYYY-MM-DD (review)
              │  consolidate ─► dedupe · contradição (marcar, nunca apagar)
              │                  · voláteis → archive · contratos (command -v)
              │                  · propostas de promoção (nunca aplica)
              │  status ─► versão, entradas, branches evolve, orçamento
              └────────────────────────
                                        │
                                        ▼
              LEARNINGS.md ◄──── probação (memória, contexto não-revisado)
              learnings_archive.md ◄── GC (overflow, voláteis, dedupe)
              SKILL.md / prompts/ ◄── promoção SÓ com evidência (≥2× ou
                                      usuário) + diff revisável + bump MINOR
```

### 3.2 O motor — `scripts/evolve-skill.sh`

CLI (bash puro, sem deps além de coreutils/git; exit codes documentados):

| Comando | O que faz |
|---|---|
| `add <arquivo\|-> [--source] [--dry-run]` | Lê candidatos (frontmatter `observacao/acao` **ou** corpo do template `- **Observação:**`), valida (source obrigatório, campos, scan de segredos), deduplica, gera `LEARNINGS.md` id `LEARN-AAAAMMDD-NNN`, anexa ao final + índice, avisa orçamento |
| `search <termo>` | grep em LEARNINGS + prompts + SKILL.md; saída `id \| data \| type \| confidence \| source \| título` |
| `diff [--stat]` | diff git das mudanças pendentes da evolução |
| `apply [--direct] [--branch <n>] [--message <m>]` | Valida (bash -n, shellcheck) → **default inteligente**: só memória → commit direto `evolve(learnings): …`; corpo/versão → branch `evolve/YYYY-MM-DD` (nunca merge sozinho). Guard: staged fora da allowlist → exit 4 sem tocar o índice |
| `consolidate [--apply] [--dry-run]` | GC: dedupe (remove do corpo, arquiva 1×), contradição (mais nova vence; antiga `~~…~~ (obsoleto DATA: motivo)` + superseded + supersedes; **ordem de confiança**: UNTRUSTED nunca supersede confiável), voláteis >90d → archive, orçamento (índice ≤30, ativas ≤100, arquivo ≤400), **contratos** (`contract:` revalidado por `command -v`), propostas de promoção (≥2 ocorrências — contando o archive como evidência — ou source=user; só texto, nunca aplica) |
| `status` | Repo, branch, versão (metadata), entradas, branches evolve abertas, orçamento |
| `--help` | Uso completo |

**Segurança como código** (não como instrução de prompt):

| Regra | Implementação |
|---|---|
| Resolução por symlink | `cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P` → `git rev-parse --show-toplevel`; cwd do chamador irrelevante |
| Instalação por cópia | sem `.git` → exit 2 "rode sync-global-skill.sh" |
| Identidade | `name: deep-orchestrator-agent-skill` no SKILL.md → exit 3 |
| Allowlist | 9 paths (LEARNINGS.md, learnings_archive.md, SKILL.md **e** `.claude/skills/…/SKILL.md` real, prompts/, docs/decisions/, README.md, scripts/README.md, check-install.sh, CHANGELOG.md); staged fora → exit 4 antes do commit, índice do usuário intacto |
| Anti-poisoning | `source` obrigatório (user\|repo-doc\|sub-agent\|web\|diff\|model-output); UNTRUSTED nunca promove nem supersede confiável |
| Segredos | scan de credenciais (`api_key=`/`secret`/`token=`…), valor nunca impresso |
| Contenção de concorrência | `flock` em add/apply/consolidate |
| Fim da execução | nunca falha a execução: sem candidatos → exit 0; erro → registrado no relatório |

### 3.3 O store — `LEARNINGS.md` (raiz da skill)

```
# LEARNINGS — deep-orchestrator-agent-skill
> Memória episódica (contexto NÃO revisado, nunca política executável). ...
## Índice                    ← ≤30 linhas; superseded SAEM do índice
- 2026-08-23 | convention | <título> [id: LEARN-20260823-001]
---
id: LEARN-AAAAMMDD-NNN
date: "AAAA-MM-DD"
type: correction | fact | antipattern | gotcha | convention
confidence: high | medium | low
source: user | repo-doc | sub-agent | web | diff | model-output
status: active | superseded
supersedes: ""            ← id que esta entrada substitui (nunca editar a antiga)
tags: [tag1, tag2]
contract: ""              ← opcional: comandos revalidados no consolidate
---
## <título imperativo>
- **Observação:** <fato específico; vago é proibido>
- **Ação:** <o que fazer/evitar>
```

O template de entrada fica **dentro de code fence** (o parser ignora) e usa
placeholders sem dígitos (nunca é confundido com entrada real). Orçamento:
ativas ≤100 linhas, arquivo ≤400 → `learnings_archive.md`.

### 3.4 O framework de decisão — `prompts/evolution-guide.md`

Para agentes: o que qualifica como aprendizado (surpresas, correções, anti-padrões,
gotchas, convenções; NÃO: óbvio, volátil, já documentado, one_time_fixes), decisão
**a→b→c** (atualizar existente / criar skill nova / descartar), hierarquia de fonte
(user > repo-doc > inferência), dual-buffer probação→promoção (≥2× ou usuário),
contradição e volatilidade, orçamento, procedimento de fim de execução e
consolidação periódica.

### 3.5 Integração no orquestrador (SKILL.md v3.7.0)

- **R8-h2**: exceção única e deliberada ao "SKILL_HOME somente leitura" — o passo
  de evolução escreve exclusivamente via `evolve-skill.sh`.
- **FASE 1, passo 8.5**: antes de planejar, `evolve-skill.sh search "<tema-central>"`
  — memória informa o plano (anti-padrões conhecidos, gotchas), nunca como verdade
  absoluta.
- **FASE 4, passo 6.5 (EVOLUÇÃO PÓS-EXECUÇÃO)**: COLETA (retrospectiva estilo
  cq:reflect → `$DO_STATE/evolution/learnings.md`) → FILTRO (evolution-guide) →
  `add` → `apply` → reporte. **NO_SELF_VALIDATION**: aprendizado desta execução
  nunca é promovido nesta mesma execução. Nunca bloqueia a execução.
- Relatório final ganha a seção "Evolução contínua".

---

## 4. Validação

### 4.1 Testes — `scripts/test-evolve.sh` (E1–E30, 139 asserções, sem rede)

Resolução por symlink de cwd estranho · identidade (exit 3) · cópia sem git (exit 2)
· source obrigatório · secret_scan (valor nunca impresso; "O token de acesso expira"
passa) · dedupe no add · ids sequenciais · parser/fence (template nunca vira
entrada) · contradição (superseded+supersedes+~~…~~, nada apagado) · dedupe no
consolidate (archive 1×) · anti-poisoning (web nunca propõe) · promoção ≥2 com
archive como evidência · orçamento · apply default (direto só memória; branch p/
corpo — inclusive via path real do SKILL.md) · staged fora da allowlist (exit 4,
índice intacto) · flock (erro com mensagem no stderr) · search · add paralelo (ids
únicos) · dry-run · apply idempotente · candidatos body-only (sem merge silencioso)
· Observação múltipla preservada.

### 4.2 Revisão adversarial (o processo paga)

| Rodada | Veredito | Achados | Resultado |
|---|---|---|---|
| Onda 2 (evolve-script) | BLOCK | commit engolia staged fora da allowlist; dedupe não removia do corpo; stderr mutado; corrida de ids; falso-positivo de segredo | fixes F1–F8 |
| Onda 2 (docs-base) | BLOCK | template do LEARNINGS parseado como entrada real (o primeiro `consolidate --apply` apagaria a especificação) | fence + placeholders sem dígitos |
| Diff integrado | WARNING | 10 achados (2 ALTA: formato de candidato × parser; SKILL.md real fora da allowlist derrotando o D8) | fixes Onda 4 (F-A1, F-A2, F-3…F-10) |
| Fixes Onda 4 | WARNING | critério ≥2 de promoção morto (dedupe × propostas); merge silencioso de body-only | fixes Onda 5 (F-11a/b) |

A **verificação de integração entre sub-agentes** (formato documentado × parser;
path real × allowlist; design doc × implementação) pegou exatamente os contratos
centrais — virou aprendizado `LEARN-20260823-002` da própria skill.

### 4.3 Gates

build (`bash -n` em 16 scripts) + lint (`shellcheck -S error`) + 4 suítes
(test-contencao 85 · test-plan-approval 151 · test-surf-gate 46 · test-evolve 139) +
`check-install.sh` 15/15 — **508 asserções verdes** no estado final, rodadas em
snapshots de integração por onda e no gate final.

---

## 5. A primeira evolução real (caso concreto)

Ao fim da PRÓPRIA execução que construiu o mecanismo, o passo 6.5 rodou em
produção pela primeira vez:

```
$ evolve-skill.sh add $DO_STATE/evolution/learnings.md
  adicionada: LEARN-20260823-001 — Limpeza de worktrees: nomes exatos do owned.tsv…
  adicionada: LEARN-20260823-002 — Revisão adversarial deve incluir integração…
  adicionada: LEARN-20260823-003 — Gate deste repo: 4 suítes + check-install…
add: 3 adicionada(s), 0 duplicada(s) ignorada(s)

$ evolve-skill.sh apply
  apenas LEARNINGS.md/learnings_archive.md mudaram — commit direto (default)
commitado — evolve(learnings): 3 aprendizado(s)   [bd82134]
```

Lições reais persistidas: (1) usar sempre os nomes exatos do `owned.tsv` na
limpeza de worktrees (nunca concatenar prefixos); (2) revisão adversarial deve
incluir integração entre sub-agentes; (3) o gate deste repo é 4 suítes +
check-install. As próximas execuções — de qualquer projeto — consultam essa memória
na FASE 1 e não repetem esses erros.

---

## 6. Como usar / estender

```bash
# consultar memória (FASE 1 faz isso sozinha)
scripts/evolve-skill.sh search "worktree"

# persistir aprendizados manualmente (ou deixar o passo 6.5 fazer)
scripts/evolve-skill.sh add candidatos.md
scripts/evolve-skill.sh diff
scripts/evolve-skill.sh apply            # memória → direto; corpo → branch evolve/
scripts/evolve-skill.sh consolidate      # GC + propostas (dry-run por default)
scripts/evolve-skill.sh status
```

Extensões naturais (registradas no design doc): recuperação por embedding
(top-k por similaridade da descrição — padrão Voyager), corpus de regressão com
rollback automático (AgentOptimizer), deprecação semver com ciclo, CI de skills em
PR (agent-skill-linter / agents-md-kit), consolidação agendada (cron/nightly).

---

## 7. Referências (verificadas por fetch direto em 2026-08-23)

**ECC:** github.com/affaan-m/ECC — `skills/continuous-learning-v2/SKILL.md`,
`commands/evolve.md`, `commands/promote.md`, `schemas/memory.schema.json`,
`docs/design/ecc-memory-vault.md`, `hooks/memory-persistence/`

**Arquiteturas:** Voyager arxiv.org/abs/2305.16291 · Reflexion arxiv.org/abs/2303.11366
· Self-Refine arxiv.org/abs/2303.17651 · AgentOptimizer arxiv.org/abs/2402.11359 ·
MemGPT arxiv.org/abs/2310.08560 · A-MEM arxiv.org/abs/2502.12110 · Model collapse
arxiv.org/abs/2305.17493 (Nature 2024) · RSI survey arxiv.org/abs/2607.07663 ·
RL for Self-Improving Agent arxiv.org/abs/2512.17102 · Self-evolving agents
arxiv.org/abs/2409.00872

**Guardrails:** Anthropic — platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks ·
anthropic.com/engineering/how-we-contain-claude · code.claude.com/docs/en/security ·
anthropic.com/engineering/claude-code-sandboxing · OpenAI —
openai.com/index/designing-agents-to-resist-prompt-injection · OWASP —
genai.owasp.org/llmrisk/llm01-prompt-injection · Microsoft —
learn.microsoft.com/en-us/security/zero-trust/sfi/manage-agentic-memory-safety ·
Memory poisoning — arxiv.org/abs/2606.04329 (V-S4/V-S5), arxiv.org/abs/2602.15654
(Zombie Agents), arxiv.org/abs/2512.16962 (MemoryGraft), arxiv.org/abs/2606.23075
(MLAS), arxiv.org/abs/2608.18066 (Fragility), arxiv.org/abs/2606.04703 (Capability
collapse) · AgentPoison NeurIPS 2024 · HITL — arxiv.org/abs/2605.02273 ·
arxiv.org/abs/2606.22721 (Habituation) · Provenance — arxiv.org/abs/2606.04990,
arxiv.org/abs/2605.11032 · OWASP Agent Memory Guard

**Convenções:** spec Agent Skills github.com/anthropics/skills/blob/main/agent_skills_spec.md ·
agentskills.io/specification · code.claude.com/docs/en/skills ·
platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices ·
SkillReducer arxiv.org/abs/2603.29919 · token budgets (microsoft/GitHub-Copilot-for-Azure) ·
MindStudio learnings.md · OKF alexop.dev/posts/open-knowledge-format-markdown-frontmatter-agent-knowledge ·
agent-skill-linter (William-Yeh) · agents-md-kit (reaatech)

**Automação:** code.claude.com/docs/en/hooks · claude-lesson-learned (rscova) ·
claude-memory-compiler (coleam00) · cq (mozilla-ai) · agent-memory-loop (zurbrick) ·
conventionalcommits.org · semver.org · skill-semver (cathy-kim) · Habituation
arxiv.org/abs/2606.22721 · closed-loop review→rule arxiv.org/abs/2607.13091

**Memória/consolidação:** ETH AGENTS.md arxiv.org/abs/2602.11988 · Lost in the
Middle arxiv.org/abs/2307.03172 · Context Rot trychroma.com/research/context-rot ·
IFScale arxiv.org/abs/2507.11538 · STALE arxiv.org/abs/2605.06527 · MemStrata
arxiv.org/abs/2606.26511 · LatticeMind arxiv.org/abs/2608.08236 · RecMem
arxiv.org/abs/2605.16045 · Retain or Consolidate arxiv.org/abs/2607.17545 ·
Skill Drift arxiv.org/abs/2605.10990 · Context Rot em dev arxiv.org/abs/2606.09090 ·
mem0.ai/blog/what-is-memory-staleness-in-ai-causes-risks-solutions ·
Agentic Context Management arxiv.org/abs/2607.21503 · Infini Memory
arxiv.org/abs/2606.10677 · FSFM arxiv.org/abs/2604.20300

**Precedentes locais:** `~/.agents/skills/meta-evolution` e `meta-consolidation`
(SKILL.md) — Voyager/Reflexion + gate humano via diff git + dual-buffer.

---

*Documento derivado da execução v3.7.0 (orquestração no-stop, 9 ondas, 13
sub-agentes, 508 asserções verdes). Fonte primária dos fatos:*
`docs/decisions/2026-08-23-auto-evolucao.md` *(D1–D11)*, `prompts/evolution-guide.md`
e `LEARNINGS.md`.
