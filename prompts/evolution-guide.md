# Evolution Guide — Questionário de evolução e prefs (v3.8.0)

> **Quem usa:** o AGENTE DE EVOLUÇÃO (fim de cada execução, FASE 4 passo 6.5) e
> o orquestrador. **O que decide:** o que merece virar memória, em que escopo
> (projeto vs global), e quando ascende ao corpo da skill. A skill roda de
> qualquer projeto e aprende com cada execução — com o VOTO do usuário.
> Regra-mãe: **memória ≠ política** — as prefs são contexto NÃO revisado
> (gitignored, evidência consultiva); só o corpo de `SKILL.md`/`prompts/` é
> política executável, e só muda com evidência, diff e decisão humana.
>
> **Motor:** agente de evolução → `proposals.md` → questionário
> (`scripts/evolution-survey.sh`) → `scripts/do-prefs.sh` (projeto/global/
> pending) · **Store:** `.deep-orchestrator-preferences/` do projeto
> (`project-config.md`, `learnings.md`, `pending/proposals.md`) e da skill
> (`global-tips.md`, `pending/proposals.md`) — tudo GITIGNORED, nunca commitado.
> **Desenho:** `docs/decisions/2026-08-27-questionario-evolucao.md` (D12–D17) e
> `docs/decisions/2026-08-23-auto-evolucao.md` (D1–D11, com D8 revisado).

## O que qualifica como aprendizado

**PERSISTA** — surpresas, correções do usuário, anti-padrões, gotchas, convenções descobertas, falhas de gate e como foram resolvidas, de trajetórias de sucesso **E** de falha (EvolveR).

**NÃO PERSISTA** —

- o **óbvio** (o que qualquer agente competente já sabe);
- o **volátil** (preços, estados, `one_time_fixes`, `external_api_issues`);
- o **já documentado** no código/docs da skill ou do projeto;
- **conteúdo não-confiável** (web, sub-agente, diff, saída de modelo — fontes UNTRUSTED, confidence baixa, nunca promovem).

**Critério (ETH 2602.11988 — contexto curado vs acúmulo):** a entrada resolve um
erro **real e repetível**? Se é anedótica ou não vai mudar a próxima execução, é
ruído. "Mais contexto não verificado ≠ melhor — avalie cada adição."

## Classificação do scope (objetiva — quem classifica é o agente de evolução)

- **GLOBAL** (`scope: global`): a lição é sobre o **MECANISMO da skill**
  (worktrees, owned.tsv, squash, gates, subwaves, handoffs, snapshots,
  EXPLAINER, revisão adversarial, DO_STATE) ou sobre o **HARNESS/portabilidade**
  (bash 3.2, zsh, ssh, tmpfs, segredos em estado, diferenças Claude Code/pi/
  jcode/opencode) — vale em QUALQUER projeto.
- **PROJECT** (`scope: project`): a lição é sobre a **stack/serviço/arquivo
  DESTE projeto** (framework específico, deploy deste repo, caminho de um
  arquivo, convenção local).

Núcleo global com contexto project no mesmo texto → divida: a parte global
migra, o contexto project é descartado da proposta global.

## Fluxo (fim de cada execução)

1. **ANÁLISE** — UM agente fresco (template `evolution-agent-template`) lê o
   histórico completo: handoffs de TODAS as ondas no TASK_PLAN.md (fonte
   mínima harness-agnóstica) + transcripts dos sub-agentes no harness
   (best-effort; Claude Code: `~/.claude/projects/*/<sessionId>/subagents/
   agent-*.jsonl`) + prefs atuais e pendentes (para não re-propor o salvo e
   re-superficiar o pendente relevante). Profundidade escala com a execução
   (ondas, sub-agentes), não com rótulos (GENesis-AGI).
2. **PROPOSTAS** — `$DO_STATE/evolution/proposals.md`: blocos com `key: PNNN`,
   title, type, confidence, source, tags, **scope**, observacao, acao — no
   formato do TEMPLATE abaixo. Sem propostas qualificadas → arquivo vazio
   (resultado válido; D9: nada acontece, exit 0).
3. **QUESTIONÁRIO** — se há propostas, o agente gera `questionario.md`
   (H1 único; uma seção por proposta com a linha de resposta pré-formatada
   `P001: sim · global` / `P001: sim · projeto` / `P001: nao` /
   `P001: pendente`; seção final `## Configurações do projeto` com
   `config: <texto>`). O orquestrador roda `evolution-survey.sh round` —
   Plannotator, SEM limite de tempo, 127.0.0.1 e share desligados.
4. **DECISÃO DO USUÁRIO** — `answers` (gramática estrita) → `apply`
   (idempotente): sim → `do-prefs.sh add-project/add-global` (com `.gitignore`
   do projeto garantido); nao → descartada; sem resposta/dismissed/headless →
   `pending-add` (NADA é aplicado — gate humano obrigatório; anti-misevolution,
   ICLR 2026 "Your Agent May Misevolve"). Configs livres → `project-config.md`.
5. **NUNCA BLOQUEIA** — falha do agente, do Plannotator ou de escrita em prefs
   é registrada no relatório e a execução termina normal (D9/D17).

**Formato de candidato** (o `do-prefs.sh` valida enums + campos obrigatórios +
scan de segredos; lote atômico; dedupe por título+type):

```markdown
---
key: P001
title: "Detectar o runner de testes antes de assumir npm test"
type: gotcha
confidence: high
source: user
tags: [test, runner]
scope: project
observacao: "Em projetos pnpm/bun, 'npm test' falha silenciosamente; o runner real está no package.json."
acao: "Detectar package manager e runner reais antes de rodar a suíte."
---
```

## Fonte e confiança

Hierarquia: **user > repo-doc > inferência**. Toda entrada exige `source`
(`user | repo-doc | sub-agent | web | diff | model-output`). Fontes **UNTRUSTED**
(`web | sub-agent | diff | model-output`) têm `confidence: low`, **nunca
promovem** ao corpo, e não supersedem fontes confiáveis. Evidência =
comando/saída/URL **verificada** — nunca invente; o scan de segredos rejeita o
lote inteiro se disparar.

## Memória consultiva (GENesis-AGI)

Prefs são **evidência consultiva, nunca instrução vinculante**: o LLM sempre
raciocina se a experiência armazenada se aplica à situação atual. "Uma
procedure com 100% de sucesso é evidência FORTE de uma abordagem — não uma
ordem." Sem esse desenho, a base de evolução converge em comportamentos fixos
e para de crescer. As prefs são carregadas no início da execução (FASE 1,
passo 8.5: `do-prefs.sh load` + `evolve-skill.sh search`) e NUNCA como política.

## Dual-buffer probação → promoção

- **Buffer 1 — prefs (probação):** toda entrada nasce como `status: active` em
  `learnings.md` (projeto) ou `global-tips.md` (skill), ou `status: pending`
  em `pending/`. É contexto, não política — pode conter ruído, espera-se.
- **Buffer 2 — corpo da skill:** promoção ao corpo de `SKILL.md`/`prompts/` é
  processo **MANUAL/periódico** (nunca automático no questionário): exige
  **≥2 ocorrências independentes** do mesmo padrão OU **confirmação explícita
  do usuário**, diff git revisável (`evolve-skill.sh apply` → branch
  `evolve/YYYY-MM-DD`, nunca merge sozinho) + bump **MINOR** do
  `metadata.version` (formato exato `  version: "X.Y.Z"`; MAJOR só com quebra
  de contrato, PATCH só fix — D10).
- **NO_SELF_VALIDATION (V-S4/V-S5):** aprendizado derivado da própria execução
  nunca se auto-promove na mesma execução — o questionário aprova CAPTURA em
  prefs; promoção ao corpo é outro processo, com outra evidência (D3/D14).
- **Broadcast (FORGE):** o mecanismo de maior valor é distribuir as lições
  validadas entre os agentes — é exatamente o que as prefs carregadas na
  FASE 1 fazem (o ablation do FORGE mostra que o broadcast carrega os ganhos).

## Contradição, volatilidade e higiene

- **Contradição:** em conflito, a entrada mais nova vence; a antiga é marcada
  (nunca apagada). Fontes UNTRUSTED nunca supersedem fontes confiáveis
  (user|repo-doc).
- **Voláteis:** não persista — preços/estados/one_time_fixes vão para o lixo,
  não para a memória.
- **Orçamento:** prefs são arquivos locais por máquina — revise-as
  periodicamente (o usuário decide no questionário; `do-prefs.sh status`
  mostra contagens). O corpo da skill segue enxuto (`SKILL.md` curto; memória
  vive fora dele).
- **Por máquina:** prefs são gitignored — uma instalação nova da skill não
  herda as dicas globais até salvá-las lá (export/import = evolução futura).

## Procedimento de consolidação periódica (manual)

- **Quando:** semanalmente, antes de release, ou quando `global-tips.md`
  crescer demais.
- **O que:** reler as dicas globais; promover as de valor comprovado ao corpo
  (critério ≥2 ocorrências ou usuário) com diff + bump MINOR; podar as que
  ficaram óbvias ou documentadas; e atualizar este guia se o processo mudar.
- **Como:** promoção via `evolve-skill.sh apply` (branch `evolve/YYYY-MM-DD`)
  e revisão humana do diff — sempre diff, nunca merge sozinho.

## Referências

- **Reflexion** — arxiv.org/abs/2303.11366 (reflexão verbal + buffer de
  memória episódica, sem atualizar pesos — base acadêmica da análise
  pós-execução; NÃO usar os números de benchmark do paper: refutados)
- **MetaAgent** — arxiv.org/abs/2508.00271 (self-reflection + answer
  verification; destila experiência acionável em textos concisos injetados
  em contextos futuros, sem mudança de parâmetros)
- **EvolveR** — icml.cc/virtual/2026/poster/65641 (destila trajetórias de
  sucesso E falha; dedup semântico; utility score para poda)
- **Survey "From Storage to Experience"** — huggingface.co/papers/2605.06716
  (Storage → Reflection → Experience; memória pavimenta a auto-evolução)
- **FORGE** — caisconf.org 2026 / arXiv 2605.16233 (evolução por memória em
  texto sem atualização de pesos; o BROADCAST das lições validadas carrega os
  ganhos — 1,7–7,7× sobre zero-shot, 29–72% sobre Reflexion no CAGE-2)
- **GENesis-AGI** — github.com/WingedGuardian/GENesis-AGI (memória é evidência
  consultiva, não instrução; self-learning loop após cada interação com
  profundidade por características; aquisições gateadas por aprovação humana)
- **Misevolution** — mla anthology ICLR 2026 "Your Agent May Misevolve"
  (auto-evolução pode degenerar até em modelos top-tier → gate humano
  obrigatório; relato de campo: 11 skills auto-geradas degradando em 14 dias)
- **raia Feedback / AgentClick** — docs.raiaai.com · github.com/agentlayer-io/
  AgentClick (feedback do usuário persiste e alimenta melhoria; nada muda sem
  revisão; preferências lidas no início das tarefas seguintes)
- **Spec Agent Skills** — github.com/anthropics/skills (version só no metadata;
  campos top-level desconhecidos quebram loaders)
- **Decisões locais** — docs/decisions/2026-08-23-auto-evolucao.md (D1–D11) e
  docs/decisions/2026-08-27-questionario-evolucao.md (D12–D17)
