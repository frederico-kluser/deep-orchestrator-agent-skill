# Análise de arquitetura — `deep-orchestrator-agent-skill` v4.1.0 (SKILL.md)

Ficheiro analisado: `.claude/skills/deep-orchestrator-agent-skill/SKILL.md` — **3 306 linhas, 220 392 bytes** (~55 mil tokens de contexto sempre carregado). Monólito XML `<orchestrator xmlns="urn:deep-orchestrator:v2">` (L56–3306) precedido de frontmatter YAML (L1–56). Leitura integral feita em blocos.

---

## 1. Mapa anatómico

| Bloco | Linhas | Tamanho | Conteúdo |
|---|---|---|---|
| Frontmatter | 1–56 | 2,8 KB | name/description (19 linhas de triggers), when_to_use, argument-hint, disallowed-tools (Write/Edit), allowed-tools, model/effort, metadata |
| `<identity>` | 57–70 | 0,8 KB | role, archetype, mantra (síntese de tudo) |
| `<rules>` | 71–549 | 37,3 KB | R1–R10 + protocolo PESQUISA-FALHOU (L288–365) |
| `<workflow>` | 550–1988 | 104,9 KB | FASE 0 (L552–807, 256 L/18,9 KB), FASE 1 (L808–933, 126 L/8,8 KB), FASE 2 (L934–1102, 169 L/12 KB), FASE 2.5 (L1103–1259, 157 L/11 KB), FASE 3 (L1260–1750, **491 L/36,3 KB**), FASE 4 (L1751–1988, 238 L/17,8 KB) |
| `<subagent-prompt-template>` | 1989–2269 | 15,8 KB | Template CDATA de feature/fix/prep: worktree, pesquisa surf, deps, handoff |
| `<adversarial-review-template>` | 2270–2317 | 2,3 KB | Revisor adversarial (veredito APPROVE/WARNING/BLOCK) |
| `<test-agent-template>` | 2318–2556 | 12,7 KB | Agente de testes + bloco "MODO e2e" (L2425–2470) |
| `<validation-agent-template>` | 2557–2667 | 5,6 KB | Validador (gate por etapa, read-only) |
| `<explainer-agent-template>` | 2668–2733 | 3,1 KB | Gerador de EXPLAINER.html |
| `<evolution-agent-template>` | 2734–2825 | 4,7 KB | Propostas de evolução (proposals.md) |
| `<final-report-template>` | 2826–2947 | 7,0 KB | Formato do relatório final (3 variantes de modo de teste) |
| `<degradation>` | 2948–3175 | 15,2 KB | 15 casos de degradação (gate-red é o maior: 58 L) |
| `<examples>` | 3176–3271 | 6,1 KB | ex1 (fluxo por ondas), ex2 (portão de aprovação) |
| `<final-note>` | 3272–3288 | 1,0 KB | Mantra de recuperação |
| `<knowledge>` | 3289–3306 | 0,9 KB | Proveniência (ECC, surf) |

Métricas transversais: **10 regras, todas `severity="FATAL"`**; 15 casos de degradação; 200 comandos `<cmd>` inline; 176 ocorrências de placeholders (54 distintos: `{{WORKTREE_PATH}}`…`{{SURF_SUB_AGENTS}}`); 79 referências cruzadas a FASE/passo; 9 blocos CDATA; 8 scripts referenciados (`do-wt.sh` 11×, `do-context.sh` 7×, `plan-approval.sh` 6×).

## 2. Inventário de regras

| ID | Título | Função (1 linha) | Local |
|---|---|---|---|
| R1 | NUNCA escreva código | Orquestrador só escreve via Bash em $DO_STATE, stubs de PREP e EXPLAINER degradado | L72–92 |
| R2 | NUNCA pergunte ao usuário | Autonomia total + 6 exceções obrigatórias + definição única de AGUARDE | L93–146 |
| R3 | Trabalho completo até COMMIT | Invariante I-MERGE: tudo termina MERGED ou listado em "Não integrado" | L147–172 |
| R4 | Worktree é a unidade de isolamento | Toda escrita em worktree criada por `do-wt.sh new`; exceção = COMMIT PREP | L173–185 |
| R5 | Squash-merge um a um | `integrate` serial, gate em paralelo no snapshot, nunca octopus | L186–201 |
| R6 | Worktree nomeada, limpeza pelo script | I-CLEAN: integrate→gate→finish; portão inter-onda; purge final | L202–235 |
| R7 | Pesquisa é só surf-agent-skill | Canal único, tabela SURF_GATE, classify, proibições absolutas | L236–287 |
| PESQUISA-FALHOU | Protocolo (não é regra) | Gatilhos g1–g3, pausa em disco, pergunta com 4 opções, retomada | L288–365 |
| R8 | RAIZ-DE-MUNDO | Fronteira absoluta + invariantes (a)–(j): owned.tsv como ledger único | L366–446 |
| R9 | Dependências congeladas na worktree | Lista fechada de comandos; HUSKY=0; gate-set install | L447–506 |
| R10 | Portão de aprovação do plano | plan=on → Plannotator na FASE 2.5; título imutável; exit codes | L507–549 |

**Redundâncias/sobreposições:**
- **R4 × R8 × R6**: o mesmo conceito de fronteira/isolamento é dito 3 vezes (L175–184, L367–379, L202–234); a mecânica integrate→gate→finish aparece em R6 (L208–216) **e** integralmente repetida na FASE 3 passo 7 (L1536–1599) **e** no caso `gate-red` (L2972–3029).
- **R7 × template do sub-agente**: as regras de pesquisa (exit codes, verbos removidos, proibições) existem em R7 (L249–286) e são reescritas quase literalmente na regra 2 do subagent-prompt-template (L2054–2146) — a alegada "tabela ÚNICA" (L254) tem efetivamente 3 encarnações (mais FASE 0 passo 6, FASE 1 passos 7–8, FASE 3 passos 0 e 4.5 e casos `surf-ausente`/`brave-key-invalida`).
- **AGUARDE** é definido 5+ vezes: R2 (L134–145), fim da R10 (L539–546), protocolo passo D (L322–324), FASE 1 passo 10 (L920–923), FASE 3 passo 8 (L1645–1649).
- **Contradição factual**: título da R7 diz "v9+" (L237) mas a FASE 0 passo 6 diz "SURF-AGENT-SKILL v8 (R7)" (L784). Também R1 proíbe escrever código (L74) mas a exceção (b) manda escrever "stubs/contratos" via Bash (L80) — fronteira difusa entre "código" e "estado".
- **Orçamentos de retry dispersos e inconsistentes**: 3 tentativas (R3 L151; subagent-failure L2957; test-subwave L3092) vs 2 (revisão adversarial L1531; gate-red fix L2997; fix-final L1798; revisão de testes L1398).

## 3. Dependências internas

**Sempre necessário (núcleo):** identity; R1–R6, R8, R9; FASE 0 inteira (é sempre o primeiro passo — 26 referências a "FASE 0"); FASE 1 passos 1–9; FASE 2 passos 1–8; FASE 3 passos 0–10 (esqueleto); FASE 4 passos 0–8; subagent-prompt-template; adversarial-review-template; final-report-template; final-note. Validation-agent-template roda nos 3 modos (L2558).

**Só em certa fase/mode:**
- **plan=on** (default DESLIGADO — L690–691): R10 (43 L) + FASE 2.5 inteira (157 L) + casos `plannotator-unavailable`/`plan-not-approved`/`plan-title-drift`/`plan-scope-expanded`/`plan-round-interrupted` (L3135–3173) + exemplo ex2 (L3221–3269) + sub-step do REPLAN L1505–1514 ≈ **350 L / 24 KB mortos** quando plan=off.
- **no-test (DO_TEST_MODE=none)**: test-agent-template (239 L), BLOCO B do passo 10 (L1684–1741), revisão de testes (L1386–1401), casos `test-subwave-failure`/`test-coverage-insufficient` e blocos [full]/[e2e] do relatório (L2869–2885) não se aplicam — a FASE 3 passo 10 diz explicitamente "BLOCO B PULADO INTEIRO" (L1687).
- **only-e2e**: fatias e2e em FASE 1 passo 9.5 (L874–893), FASE 2 passo 4.5 (L1017–1037), FASE 3 passo 10 "TROCAS" (L1715–1740), bloco "MODO e2e" do template de teste (L2425–2470), caso `e2e-runner-unavailable` (L3118–3134), tabela E2E_PORT, relatório [e2e].
- **do-question**: R2(f), FASE 1 passo 10 (L894–928), rodada de fim de onda (L1636–1649), secção "Dúvidas" do handoff (L2254–2257), relatório (L2897–2902).
- **wt= (DO_WT_ROOT)**: R8(j) (L436–445), token na FASE 0 (L645–653), push (L1875–1883), nota do relatório (L2922).
- **Evolução (salvo no-evolve)**: evolution-agent-template (92 L) + FASE 4 passos 4/7.5 (L1852–1866, L1934–1967) + secção do relatório (L2939–2944) + `evolution-guide.md` externo.
- **Pesquisa falha (g1–g3)**: protocolo PESQUISA-FALHOU (78 L) + casos `surf-ausente`/`brave-key-invalida` (L3064–3088) — só entram em ação com portão ≠ 0, mas têm de estar em memória para serem reconhecidos.
- **Externo (já lazy)**: `prompts/search-prompts.md` (39 KB), `ecc-prompts.md` (31 KB), `ecc-skills.md` (29 KB), `evolution-guide.md`, `plan-approval-prompts.md` — referenciados por path, não carregados.

Grafo de dependências central: R7→protocolo→FASE 0 passo 6→FASE 2 passo 9→FASE 3 passos 0/4.5; R10→FASE 2.5→REPLAN (FASE 3 passo 5); R6→FASE 3 passos 2/7/8→FASE 4 passo 6; R3/R6→relatório final (fonte = `"$DO_WT" ledger`, nunca memória).

## 4. Proposta de split (progressive disclosure)

Padrão-alvo: **SKILL.md fino (router) + `references/*.md` + templates em `prompts/*.md` invocados sob demanda**. Os scripts (`scripts/`, 10 630 linhas no total) já estão fora — o problema é só o Markdown.

| Módulo proposto | Conteúdo (linhas atuais) | Quando carregar | Tamanho est. |
|---|---|---|---|
| `SKILL.md` (router) | frontmatter + identity + R1–R6 resumidas + R8/R9 resumidas + índice de sintomas de degradação (1 linha/caso) + tabela de flags (L633–673) + mapa FASE→ficheiro | Sempre | ~450 L / ~32 KB |
| `references/phase0-context.md` | FASE 0 (L552–807) + invariantes R8 detalhadas | Sempre (1º passo) | 256 L / 19 KB |
| `references/research-protocol.md` | R7 + protocolo PESQUISA-FALHOU + casos surf-ausente/brave-key-invalida (L236–365, L3064–3088) | Quando houver SEARCH_REQUIRED=sim ou portão ≠ 0 | ~205 L / 15 KB |
| `references/plan-approval.md` | R10 + FASE 2.5 + 5 casos plan-* + ex2 (L507–549, L1103–1259, L3135–3173, L3221–3269) | Só com plan=on | ~290 L / 21 KB |
| `references/execute-wave.md` | FASE 3 (L1260–1750) | Ao entrar na FASE 3 | 491 L / 36 KB |
| `references/test-modes.md` | passos 4.5/9.5, políticas {{TEST_POLICY}}, mapa de jornadas, TROCAS e2e, casos test-* (L874–893, L992–1038, L1386–1442, L1684–1741, L3089–3134) | Só com full/e2e (no-test: 1 página "testes desligados") | ~340 L / 22 KB |
| `prompts/subagent-prompt.md` | L1989–2269 (já é um template fechado) | No disparo de cada sub-agente | 281 L / 16 KB |
| `prompts/adversarial-review.md` | L2270–2317 | Só no passo 6/3.5/10 | 48 L |
| `prompts/test-agent.md` · `validation-agent.md` · `explainer-agent.md` · `evolution-agent.md` | L2318–2556 · L2557–2667 · L2668–2733 · L2734–2825 | Por papel, no momento do dispatch | 239/111/66/92 L |
| `references/final-report.md` | L2826–2947 | Só na FASE 4 | 122 L |
| `references/degradation.md` | L2948–3175 (15 casos) + casos test/plan deslocados | Só em falha (lookup) | ~230 L / 15 KB |
| `references/examples.md` | L3176–3271 | Few-shot opcional (ou cortar) | 96 L |

Efeito: o contexto permanente desce de **~220 KB para ~35 KB** (−84%); plan=off + no-test (o caso "correr em frente") carrega ~40% do material atual; plan=on paga o seu bloco à parte. Custo: uma leitura extra por fase e necessidade de o router conter um índice fiável (mitigável com o `final-note` atual, L3272–3288, como "cartão de bolso").

## 5. Problemas de qualidade

1. **Inflação de FATAL**: 10/10 regras FATAL (L72–547). Sem gradação, "FATAL" deixa de sinalizar o que realmente mata a execução (R1/R8) vs o que é processo (R6/R10).
2. **Contexto monólito**: 220 KB carregados por invocação; ~60% só servem em modos específicos (ver §3).
3. **XML vs Markdown**: o XML dá estrutura greppável (`<rule id>`, `<phase id>`) e CDATA isenta os templates, mas custa ~10–15% de overhead em tags/entidades (`&lt;`, `<code>`) e é interpretado por zero ferramentas — é prosa com verniz. Markdown com headings + frontmatter por secção daria o mesmo índice com menos tokens; o que se perde é a validação de schema (que hoje ninguém faz).
4. **Instruções que deviam ser scripts**: o scan de estados pendentes (L565, one-liner de 6 linhas), o localizador de $SKILL_HOME (L702, 12 linhas de shell) e o DESCARTE DE ESTADO (L1971, 20+ linhas) são programas Bash embutidos em prosa — inuteisáveis (os `scripts/test-*.sh` não os cobrem) e frágeis a reflow de markdown.
5. **Duplicação de superfície**: pesquisa (6 lugares), AGUARDE (5), mecânica integrate/gate (3) — cada correção tem de ser replicada manualmente (o drift v8/v9 da L784 é o sintoma).
6. **Deep-nesting**: FASE 3 passo 10 tem `<substeps>` dentro de `<substep>` (L1686) com 4 níveis; navegar/extrair uma regra exige reler o contexto todo.
7. **Frontmatter**: triggers razoáveis (L15–16), mas a description (19 linhas) duplica when_to_use e argument-hint, e a proibição "NUNCA invoque para tarefas triviais" é não-verificável; `effort: xhigh` + 220 KB é a combinação mais cara possível para tarefas que podiam ser simples.
8. **Placeholders sem contrato**: `{{SURF_SUB_AGENTS}}` tem semântica definida em L965–979, colagem em L1340–1343 e consumo em L2061 — 54 placeholders sem tabela única (a tabela de flags L633–673 é o modelo a seguir).

## 6. Top 10 dores concretas

1. **Carregamento integral de 3 306 linhas/220 KB** por invocação, mesmo para `no-test plan=off` (ficheiro inteiro).
2. **10 regras FATAL** sem gradação — L72, 93, 147, 173, 186, 202, 236, 366, 447, 507.
3. **Regras de pesquisa triplicadas**: L236–287 (R7) vs L2054–2146 (template) vs L3064–3088 (degradação) — manutenção em 3 sítios.
4. **Definição de AGUARDE em 5 lugares**: L134–145, L539–546, L322–324, L920–923, L1645–1649.
5. **Drift de versão surf**: "v9+" (L237) vs "v8" (L784) — mina a confiança em toda a skill.
6. **Bash inline não testável**: L565 (pendentes), L702 (localizador de SKILL_HOME), L1971 (descarte de estado).
7. **FASE 3 com 491 linhas** (L1260–1750) e nesting de 4 níveis (L1686) — a maior dívida de navegação.
8. **~350 linhas mortas sem plan=on**: FASE 2.5 (L1103–1259) + casos plan-* (L3135–3173) + ex2 (L3221–3269), quando o default é plan=off (L690–691).
9. **Template de testes + fatias e2e (≈350 linhas) inúteis com no-test** — L2318–2556, L1684–1741, L2425–2470.
10. **Orçamentos de retry contraditórios** (3 vs 2): L151 vs L1531/L2997/L1798 — o agente não sabe qual teto vale num caso híbrido (fix de revisão após falha de sub-agente).

**Recomendação-síntese:** manter o rigor (é a parte valiosa — invariantes I-MERGE/I-CLEAN, ledger como fonte de verdade, fail-closed), mas migrar para router + `references/` + `prompts/`, transformar R7/AGUARDE/integrate em secções únicas referenciadas por ponteiro, e converter os 3 blocos de Bash inline em subcomandos de `do-wt.sh`/`do-context.sh` cobertos pelos testes existentes.
