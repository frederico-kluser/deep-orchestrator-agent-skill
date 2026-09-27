# Relatório de análise — deep-orchestrator-agent-skill v4.1.0: evolução, decisões e modularização

> Análise de produto/engenharia sobre o repo `deep-orchestrator-agent-skill`. Fontes: `PLANO-MELHORIAS.xml`, `docs/decisions/*.md`, `docs/estudo-auto-evolucao.md`, `README.md`, `TEST-REPORT.md`, `git log`, `.deep-orchestrator-preferences/`. Estado atual: **SKILL.md monolítico de 220.392 bytes / 3.306 linhas** (`.claude/skills/deep-orchestrator-agent-skill/SKILL.md`, symlinkado pela raiz).

---

## 1. Linha do tempo da evolução (v3.x → v4.1.0)

| Versão | O que tentou resolver |
|---|---|
| **v3.0.0** (`README.md` "Novidades na v3.0.0") | Ondas ilimitadas com REVISOR DE PLANO (fim por convergência, não por contagem) e **busca Brave interna** (`brave-search.sh`) + verificação de créditos — "única exceção à autonomia total". |
| **v3.2.0** | **MODO CONTIDO** + FASE 0 "DELIMITAR O MUNDO": worktree de invocação como raiz-de-mundo (R8), guardas em script (`do-wt.sh`), regra de dependências (R9), suíte `test-contencao.sh`. Nasce daqui a obsessão por **contenção e limpeza segura**. |
| **v3.3.0** | Implementação das 4 fases do `PLANO-MELHORIAS.xml` (commits `f1-*`…`f4-*`): bugs críticos de undo/stage-delta, subwaves duplas assíncronas (TESTING/VALIDATION), gate em snapshot `int-*` fora da seção crítica, `DO_MAX_PARALLEL`, lockfile singleton, tiering de modelos. |
| **v3.4.0** | **Portão de aprovação do plano** (FASE 2.5, R10) no Plannotator: nenhuma worktree nasce antes do APROVADO; título imutável; decisão por exit code; plano nunca sai da máquina (travas `PLANNOTATOR_SHARE/REMOTE`). |
| **v3.5.0 / v3.5.1** | Flag `no-stop` (remove teto de 10 ondas, mantendo válvula anti-loop) e correção do contrato de instalação (`check-install.sh`, symlinks espelhados). |
| **v3.6.0** | EXPLAINER.html deixa de ser gerado por script+template: delegação a sub-agente `html-explainer-agent-skill`, sem limite de tempo, Plannotator como runtime de render. |
| **v3.7.0** | **Auto-evolução contínua**: `evolve-skill.sh` + `LEARNINGS.md`, com design D1–D11 (`docs/decisions/2026-08-23-auto-evolucao.md`) e `docs/estudo-auto-evolucao.md` (6 frentes de pesquisa). |
| **v3.8.0** | Questionário de evolução pós-execução (D12–D17) + **prefs por projeto** em `.deep-orchestrator-preferences/` (gitignored); `LEARNINGS.md` sai do repo. |
| **v3.9.0** | A evolução vira **pergunta em texto no terminal** (D18–D22), nunca mais site; flags `no-evolve` e `max-parallel=N`; push no COMMIT-FINAL. |
| **v4.0.0** | **Fim do sistema de busca interno** (D23): 6 scripts apagados; pesquisa 100% via `surf-agent-skill` (v8 na altura; v9+ desde `7114a17`). Gatilho: bug em que `exit 78` do surf era tratado como falha transitória e o fallback respondia por um provedor que o usuário não escolheu. |
| **v4.1.0** (2026-09-20, D24–D31) | Resposta à queixa do dono ("não limpa worktrees, às vezes nem mergeia, não pergunta pela chave Brave"): **limpeza por tarefa feita pelo script** (I-CLEAN), **portão inter-onda** (`sweep && assert-clean`), **"nada some em silêncio"** (I-MERGE, ledger de 11 colunas, seção "Não integrado" obrigatória), **protocolo PESQUISA-FALHOU** (pergunta incondicional), flags `no-test`/`only-e2e`/`do-question`, `--flags` validado pelo script, alvo macOS/bash 3.2, e condensação do SKILL.md (304k → 215k → 220k chars). |

Ritmo do `git log`: agosto/2026 foi de construção intensa (v3.3→v3.9 em ~3 semanas, muitos commits `evolve(learnings)`); setembro tem dois picos — `fe3a1c2` (15/09) e a rodada v4.1.0 (20/09, auditada adversarialmente). O padrão é claro: **cada versão responde a uma dor observada em execução real**, documentada em `docs/decisions/` antes ou junto do código.

---

## 2. O que o PLANO-MELHORIAS propõe e em que estado está

`PLANO-MELHORIAS.xml` (gerado 2026-08-14, `versao-atual="3.2.0"` → `versao-alvo="3.3.0"`) é um plano de AÇÃO de **35 itens em 4 fases**, com 4 decisões do usuário (D1–D4 do plano — atenção ao *namespace*: não confundir com as séries D1–D11/D12–D31 de `docs/decisions/`) e 5 invariantes (R8, testes 100% verdes, coerência SKILL.md×frontmatter×README, docs atualizadas no mesmo commit, nenhum provedor de busca novo).

- **Fase 1 "Estancar os críticos"** (F1-01…06: undo seguro, baseline de ignorados, `--budget-ms`, stage-delta `-uall`, template do EXPLAINER, testes portáteis) — **implementada** (commits `e7118c3`…`c1cde90`).
- **Fase 2 "Redesenhar o fim de onda"** (F2-01…09: subwaves pós-onda assíncronas, FIX-FINAL, loop de bugs, REPLAN em background, válvula de convergência) — **implementada** (`3f003dd`, `a65904a`, `ff1cf6e`); é o núcleo do fluxo atual.
- **Fase 3 "Paralelismo estrutural + busca"** (F3-01…11: gate em snapshot, DO_MAX_PARALLEL, lockfile singleton, `search-parallel.sh`, tiering de modelos) — **implementada** (`7e8bfa3`, `b5ccbee`, `aeac616`), com duas exceções registadas como futuras: **F3-11 dispatch-on-ready** e **F4-09 Brave LLM Context** (roadmap).
- **Fase 4 "Docs, prompts e regressão"** (F4-01…09) — **implementada** (`ceb0066`…`2ac0161`).

**Estado atual das propostas — várias foram SUPERADAS depois:**
- Itens de busca (F1-03, F3-05, F3-06, D3 do plano "nenhum provedor novo") — **superados pela v4.0.0 (D23)**: a cadeia 3-tier inteira foi apagada; hoje há um único backend (`surf-agent-skill v9+`, `README.md` "Pesquisa — surf-agent-skill v9+ (dependência dura)").
- Template/gerador do EXPLAINER (F1-05, F4-04) — **removidos na v3.6.0** em favor da delegação a sub-agente.
- F3-01 (gate em snapshot) — **evoluído na v4.1.0** para os dois comandos `do-wt.sh integrate` + `do-wt.sh gate`, com limpeza automática no gate verde.
- O item explicitamente **não feito e ainda relevante** é a fragmentação do SKILL.md — ver secção 5.

---

## 3. Decisões de design que uma refatoração NÃO pode contradizer

1. **Pesquisa só via surf-agent-skill v9+** (D23, `2026-08-29-surf-agent-skill-obrigatorio.md`): nenhum sistema de busca próprio, nenhum fallback silencioso, nenhum shim. Falha de pesquisa exigida → **protocolo PESQUISA-FALHOU** (D27): pergunta em TEXTO, incondicional (vence "não me pergunte nada", `no-stop`, `plan=off`), estado em disco (`search-pause.md`), retomada no passo 0 da FASE 0. O portão `scripts/surf-gate.sh` é **fail-closed** e cota/429 ≠ exit 78 (`classify`).
2. **Portão Plannotator (FASE 2.5, R10)**: só quando `PLAN_APPROVAL=1`; nenhuma worktree antes do APROVADO; título imutável; cada anotação regera plano + Plannotator novo; decisão por exit code; plano nunca sai da máquina por default; **`AskUserQuestion` vetado — pergunta é texto + estado em disco + fim de turno (rito AGUARDE)**.
3. **Auto-evolução com gate humano** (D1–D11 + D12–D22): captura determinística por script, anti-poisoning por campo `source`, **NO_SELF_VALIDATION**, promoção só com diff revisável e nunca auto-merge, memória **gitignored** (`.deep-orchestrator-preferences/`), pergunta de evolução no terminal depois de TUDO, `no-evolve` para pular. D4 fixa orçamento: `SKILL.md` < 500 linhas / ~5k tokens, memória carregada **sob demanda** (progressive disclosure).
4. **Modo contido / R8**: nada fora da raiz-de-mundo; limpeza só por nome no ledger `owned.tsv`; `git worktree prune` proibido; `wt=` termina em commit+push no próprio branch, **nunca merge de volta** (D24).
5. **I-CLEAN / I-MERGE** (D25/D26): quem limpa é o **script**, no instante do gate verde (`integrate`→`gate`→`finish`/`close`); **nada nunca integrado some em silêncio** — relatório obrigatório "Não integrado", `purge` com rc 3, título "PARCIALMENTE" quando aplicável.
6. **R1/R3/R9**: o orquestrador nunca escreve código (delega tudo); autonomia total com 6 exceções obrigatórias de pergunta; dependências só dentro da worktree, congeladas, `HUSKY=0`, nunca globais.
7. **"Uma casa canônica por regra"** (condensação v4.1.0) e invariantes do plano: SKILL.md × frontmatter × README contam a mesma história; docs mudam no mesmo commit do código; testes (`test-surf-gate.sh` G8/G12) verificam literais e teto ≤ 220k chars.

---

## 4. Padrões de problemas recorrentes

- **Prosa que o LLM esquece** — a causa-comum das queixas de 2026-09-20 (`2026-09-20-...md`, Contexto): regras de limpeza/merge/pergunta escritas como instrução eram ignoradas em execuções longas (contexto compactado). A cura recorrente é **mover enforcement para o script determinístico** — tendência que qualquer refatoração deve continuar.
- **Crescimento e peso do SKILL.md** — achado E03 da auditoria: **~31% do arquivo não é necessário no carregamento**; o arquivo **cresceu** (2935 → ~4650 linhas na 1ª implementação da v4.1.0, condensado depois), contra o orçamento D4 (< 500 linhas). Há tensão explícita entre completude e context rot (D4 cita ETH Zurich/Context Rot/SkillReducer).
- **Deriva documental e de testes** — `TEST-REPORT.md` mostra asserts com referências de linha já derivadas e greps que casam changelog ("caveat do assert g"); o header do próprio TEST-REPORT está marcado como histórico/stale. Handoffs citam invariantes e `file:line` inventados (`.deep-orchestrator-preferences/pending/proposals.md`, P-20260924-002) — revisão tem de grepAR cada citação.
- **Flags e parsing** — typos viravam texto da tarefa; `export` não persistia entre chamadas; env antigo reusado vinha incompleto (D31, FT-01/CTX-01). Solução: zona de prefixo + `do-context.sh` único validador.
- **Contenção/limpeza** — worktrees órfãs, `git clean -fdXX` a destruir ignorados do usuário, undo a destruir trabalho alheio, merges silenciosamente perdidos: é a dor mais antiga (v3.2.0) e ainda a mais reaberta (v4.1.0).
- **Contenção vs. autonomia** — perguntar ou não: evoluiu de "nunca pergunta" para 6 exceções + `do-question`; a lição é que **certas falhas (chave de pesquisa) são de configuração do usuário e exigem humano**.
- **Portabilidade** — GNU-isms partiam as suítes no macOS bash 3.2 e mascaravam regressões reais (D31).

---

## 5. Como a modularização em sub-skills sob demanda se encaixa

**Encaixa-se bem — e já está decidida como trabalho futuro.** O `Fora de escopo` de `2026-09-20-limpeza-por-tarefa-pergunta-pesquisa-flags.md` regista literalmente: *"Fatiar o `SKILL.md` em arquivos de referência (templates, relatório, FASE 2.5, degradations carregados sob demanda) — TRABALHO FUTURO"*, com o diagnóstico E03 (~31% desnecessário no load) e as duas ressalvas: **risco alto** (referências cruzadas por passo; literais verificados por `test-surf-gate.sh` G8) e o pedido da altura era "conserto, não reescrita". É a única forma coerente de voltar ao orçamento D4 (< 500 linhas) sem contradição.

Mas o corte tem de respeitar: (a) **uma casa canônica por regra** — fatiar não é duplicar; cada regra vive num só lado e o núcleo referencia; (b) o bloco `<orchestrator>` (XML parseável, `SKILL.md:55`) e os **61 `<step order>`** são contrato mecanizado — ou se mantêm inteiros no núcleo, ou o carregamento do módulo é garantido por script; (c) os **templates de sub-agente** (`SKILL.md:1994+`: feature, tester, validator, explainer, evolution) são o candidato natural a sub-skill — só são necessários **no momento da delegação**; (d) coerência SKILL.md×frontmatter×README (invariante do plano) e `description` ≤ 1024 (D31); (e) FASE 2.5/Plannotator, degradations e relatório são os módulos "sob demanda" nomeados na própria decisão. O repo já tem a mecânica de casa partilhada (`.claude/skills/.../scripts` e `/prompts` são symlinks para a raiz), portanto sub-skills em `prompts/` ou `references/` resolvem sem mudar o contrato de instalação (`check-install.sh`).

---

## 6. Top 10 recomendações

1. **Executar o fatiamento já decidido (D31/E03)** como o próximo release (v4.2.0), com escopo exato dos módulos nomeados: templates de sub-agente, FASE 2.5, degradations, relatório — núcleo < 500 linhas como alvo (D4), teto duro G12 mantido.
2. **Começar pelos templates de sub-agente** (`SKILL.md:1994+`): maior bloco, zero perda de contexto no load (entregues só no handoff) e baixo risco de referência cruzada.
3. **Antes de cortar, congelar o contrato**: extrair os literais que `test-surf-gate.sh` G8/G12 verificam para um ficheiro de contrato único, e atualizar as suítes (309+307+139+228+81 asserções) para validar os módulos — sem isto, o fatiamento quebra testes silenciosamente.
4. **Manter o `<orchestrator>` como unidade atómica** (um ficheiro carregado integralmente pelo orquestrador) — o parse XML inteiro é invariante da v4.1.0.
5. **Não fatiar por "pesquisa" nem reintroduzir camadas de busca**: D23 é dura; qualquer módulo de pesquisa é um módulo de ponteiro para `surf-gate.sh` + protocolo PESQUISA-FALHOU.
6. **Preservar o rito AGUARDE e as 6 exceções** em qualquer reestruturação — são o contrato de UX com o dono (texto + disco + fim de turno; Brave-key pergunta incondicional).
7. **Continuar a tendência enforcement-no-script**: onde a prosa ainda manda (ex.: premissas falsificáveis do plano, P-20260923-001; critério de verde vs. baseline, P-20260924-001), codificar no `do-wt.sh`/`do-context.sh` em vez de acrescentar texto.
8. **Resolver as pendências de "Fora de escopo"** de menor custo junto do fatiamento: `gate <nome> --at-head`, purge/gc de runs órfãs no `do-context.sh`, classe exit 137 e `OK_PARTIAL_QUOTA` no `classify`.
9. **Registar a decisão do fatiamento em `docs/decisions/`** (série D32+, com data e supersedes explícitos) e atualizar no mesmo commit README+SKILL.md+frontmatter — invariantes do plano e da D5 (contradição na escrita).
10. **Fechar o ciclo de auto-evolução nas propostas pendentes**: `pending/proposals.md` tem 9 propostas sólidas (E2E seed-gap, handoff falsificável, baseline de gate); promover as de `confidence: high` via diff revisável (D1/D14) em vez de as deixar re-superficiarem para sempre.

---

### Notas de namespace (para citações futuras)
Existem **quatro séries "D"**: D1–D7 do `RESEARCH_PLAN.md`/`RESEARCH_ANSWER.md` (2026-08-03), D1–D4 do `PLANO-MELHORIAS.xml` (2026-08-14), D1–D11 de `2026-08-23-auto-evolucao.md`, e D12–D31 da série contínua v3.8→v4.1 (`docs/decisions/README.md` manda citar sempre o documento).
