# Decisão — Questionário de evolução + prefs de projeto (v3.8.0)

**Data:** 2026-08-27 · **Versão alvo:** v3.7.0 → v3.8.0 (metadata.version) · **Status:** aprovada
**Artefatos relacionados:** `scripts/do-prefs.sh`, `scripts/evolution-survey.sh`,
`scripts/lib/evolve-common.sh`, `scripts/lib/plannotator-common.sh`,
`prompts/evolution-guide.md` (reescrito), `SKILL.md` (R2e, R8a/h2, FASE 1 8.5,
FASE 4 6.5, template evolution-agent), `.gitignore` (raiz).
**Pesquisa de base:** deep-research 2026-08-27 (104 agentes, 22 fontes
buscadas, 103 claims, 25 verificados adversarialmente — 24 confirmados,
1 refutado: os números de benchmark do Reflexion).

---

## Contexto

A v3.7.0 evoluía às cegas: ao fim de cada execução o orquestrador coletava
aprendizados e o `evolve-skill.sh` os **commitava no repo da skill**
(`LEARNINGS.md` — 59 entradas, muitas de projetos específicos: Unity, DSH,
Azure, Electron). Memória de UM projeto contaminava o sistema inteiro e todos
os outros projetos. O pedido: análise do histórico completo por um agente, um
questionário em que o usuário decide salvar/não salvar e o escopo
(projeto/global), prefs por projeto em `.deep-orchestrator-preferences/`
carregadas no início de cada execução, dicas globais na mesma pasta dentro da
skill, tudo gitignored, e higiene do que já existia.

## Decisões

### D12 — AGENTE DE EVOLUÇÃO FRESCO

- **Decisão:** UM sub-agente de contexto zero (template
  `evolution-agent-template`) analisa o histórico COMPLETO ao fim de cada
  execução: handoffs de todas as ondas no TASK_PLAN.md (fonte MÍNIMA
  harness-agnóstica) + transcripts de sub-agentes do harness (best-effort —
  Claude Code: `~/.claude/projects/*/<sessionId>/subagents/agent-*.jsonl`,
  append-only, retenção ~30 dias) + prefs atuais e pendentes. O agente NÃO
  decide nada: propõe (`proposals.md`) e monta o questionário.
- **Evidência:** Reflexion/MetaAgent/EvolveR/survey ACL 2026 (reflexão
  pós-execução é o estágio "Reflection" da evolução de memória); subagentes
  nascem com contexto isolado e precisam ser explicitamente instruídos a ler
  os arquivos (docs oficiais do Claude Code, sub-agents); GENesis-AGI
  (profundidade escala por características da execução, não rótulos).

### D13 — QUESTIONÁRIO SEMPRE, PÁGINA PRÓPRIA, SEM LIMITE DE TEMPO

- **Decisão:** o questionário aparece ao fim de TODA execução com ≥1 proposta
  — inclusive quando o usuário pediu "não me pergunte nada" (exceção R2-e: a
  interação é a entrega pedida). Kill-switch manual `DO_EVOLUTION_SURVEY=0` e
  freio opcional `DO_SURVEY_TIMEOUT` (default 0 = SEM limite de tempo).
  Página PRÓPRIA (não dentro do EXPLAINER.html), render via
  plannotator-visual-explainer, focada só nas perguntas; o `round` roda sobre
  o `.md` (contrato garantido do Plannotator), o `.html` é cópia de leitura.
- **Evidência:** decisão do usuário (2026-08-27, respostas ao questionário de
  design); precedente local do PORTÃO DE APROVAÇÃO (R2-d/R10) como padrão de
  interação entregue pelo Plannotator.

### D14 — GATE HUMANO OBRIGATÓRIO (nada aplicado sem resposta)

- **Decisão:** sem resposta (dismissed, timeout com freio ligado, headless,
  aprovado sem anotações) → TODAS as propostas vão para `pending/` e NADA é
  aplicado. O usuário responde por proposta: `sim` (+ escopo projeto/global),
  `nao`, `pendente`. Gramática estrita no feedback
  (`P001: sim · global` etc.), parseada por jq OU python3.
- **Evidência:** GENesis-AGI (propose-and-wait; "no exception, no override");
  raia (feedback não muda comportamento sem revisão); AgentClick (proposta →
  UI → inspeção humana → execução); ICLR 2026 "Your Agent May Misevolve" +
  relato de campo (11 skills auto-geradas degradando em 14 dias) +
  self-gaming de critérios em horas.

### D15 — PREFS GITIGNORED (memória nunca commitada)

- **Decisão:** aprendizados e preferências vivem em
  `.deep-orchestrator-preferences/` — projeto (`project-config.md`,
  `learnings.md`, `pending/proposals.md`) e skill (`global-tips.md`,
  `pending/proposals.md`) — TODOS gitignored. O `LEARNINGS.md` foi REMOVIDO do
  repo (59 entradas reclassificadas: ~30 globais migraram para `global-tips.md`,
  ~29 project-only deletadas — git history preserva). `evolve-skill.sh` perdeu
  add/consolidate e não commita mais memória. Prefs são memória CONSULTIVA
  (evidência, nunca instrução vinculante) e POR MÁQUINA (export/import =
  evolução futura).
- **Evidência:** GENesis-AGI (memória como evidência, não evangelho);
  misevolution (memória acumulada pode degradar); pedido do usuário ("a
  evolução nunca atrapalha o sistema todo e outros projetos").

### D16 — ESCRITA SÓ POR SCRIPT (e .gitignore automático)

- **Decisão:** prefs são escritas EXCLUSIVAMENTE por `do-prefs.sh`
  (add-project/add-global/pending-add/ensure-gitignore) e
  `evolution-survey.sh` (round/answers/apply) — validação de lote atômico,
  enums, scope obrigatório, scan de segredos, dedupe por título+type, ids
  `P-YYYYMMDD-NNN` atribuídos pelo script, flock por diretório de prefs.
  `.gitignore` do projeto (e do repo da skill) ganha a linha
  `.deep-orchestrator-preferences/` por APPEND idempotente (nunca reescreve o
  arquivo) — precedente: o Claude Code acrescenta `settings.local.json` ao
  excludes global do git quando o repo não o ignora. Exceção R8-a documentada:
  em MODE=contido, prefs do projeto vão para o checkout principal
  (PROJECT_PREFS_ROOT = MAIN_ROOT) — prefs não podem morrer com a worktree.
- **Evidência:** D1/D2 da v3.7.0 (captura determinística por script, não por
  instrução; anti-poisoning como código); docs oficiais do Claude Code
  (claude-directory).

### D17 — NUNCA BLOQUEIA (D9 estendido)

- **Decisão:** sem propostas → sem questionário (exit 0). Falha do agente de
  evolução (3 tentativas, subagent-failure), do Plannotator (TOOLFAIL → retry
  → pending) ou de escrita em prefs → AVISO no relatório e a execução termina
  normal. `apply` é idempotente por marcação (sha do answers.json).
  Pendentes são re-superficiados no questionário da execução seguinte.
- **Evidência:** D9 da v3.7.0; LEARN-20260827-001/003 (backgrounds longos são
  mortos pelo harness — o questionário usa o mesmo padrão do explicador).

---

## Revisões

- **D8 (2026-08-23) revisada:** o "default inteligente" do apply (só memória →
  commit direto) MORREU junto com o LEARNINGS.md — TODO apply de corpo vai
  para branch `evolve/YYYY-MM-DD` + diff, nunca merge sozinho.

## Referências

- Reflexion: arxiv.org/abs/2303.11366 · MetaAgent: arxiv.org/abs/2508.00271 ·
  EvolveR: icml.cc/virtual/2026/poster/65641 · Survey: huggingface.co/papers/2605.06716
- FORGE: caisconf.org/program/2026 (ACM CAIS '26) · arXiv 2605.16233
- GENesis-AGI: github.com/WingedGuardian/GENesis-AGI (docs/architecture)
- Misevolution: mla anthology ICLR 2026 (shao2026iclr-your)
- raia Feedback: docs.raiaai.com/products/skills/feedback · AgentClick:
  github.com/agentlayer-io/AgentClick
- Claude Code: code.claude.com/docs/en/sub-agents (transcripts de subagente,
  memória por agente user/project/local) · code.claude.com/docs/en/claude-directory
  (precedência projeto-sobre-global; auto-gitignore de settings.local.json)

## Anexo — classificação da migração (LEARNINGS.md → prefs, 2026-08-27)

58 entradas (ids LEARN-*). **30 GLOBAIS** migraram para
`$SKILL_HOME/.deep-orchestrator-preferences/global-tips.md` (ids preservados,
`scope: global` acrescentado; LEARN-20260826-009 teve o contexto DAF dividido
fora — ficou só o núcleo global). **28 PROJECT** foram descartadas do repo
(git history preserva).

**GLOBAIS (migradas):** 20260823-001/-002 · 20260824-005/-006/-008/-011 ·
20260825-001/-002/-008 · 20260826-002/-003/-005/-006/-007/-008/-009/-010/
-012/-013/-014/-015/-020/-021/-022/-023/-024 · 20260827-001/-002/-003/-006
(mecanismo da skill: owned.tsv, squash, gates, subwaves, snapshots, EXPLAINER,
revisão adversarial, DO_STATE; harness/portabilidade: bash 3.2, zsh, ssh,
tmpfs, segredos, Claude Code/DSH).

**PROJECT (descartadas):** 20260823-003 (gate deste repo) · 20260824-001/-002/
-003/-004/-007/-009/-010 (DSH, systemd, Unity) · 20260825-003/-004/-005/-006/
-007/-009/-010/-011/-012/-013/-014 (electron/study-method, tsconfig deste
repo, Unity) · 20260826-001/-004/-011/-016/-017/-018/-019 (electron,
node:test+sqlite, DAF, daf-chat/az) · 20260827-004/-005 (deploy daf-chat,
security-guard.sh).
