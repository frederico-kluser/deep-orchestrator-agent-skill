# Decisão — Evolução como PERGUNTA EM TEXTO no terminal (v3.9.0)

**Data:** 2026-08-28 · **Versão alvo:** v3.8.0 → v3.9.0 (metadata.version) · **Status:** aprovada
**Artefatos relacionados:** `SKILL.md` (frontmatter, R2e, R3, R6-h2, FASE 0 0/0.1b/0.4, FASE 1 8.5, FASE 4 4/5.5/7/7.5/8, template evolution-agent, final-report-template, final-note), `scripts/evolution-survey.sh` (reescrito: ask/answer/apply/dismiss), `scripts/lib/evolve-common.sh` (sha_of/now_iso + opcao_a/b/c no parse_fields), `scripts/do-context.sh` (no-evolve + max-parallel), `prompts/evolution-guide.md`, `scripts/test-evolve.sh` (S1–S10 reescritos), `README.md`.

---

## Contexto

A v3.8.0 levou a evolução para o Plannotator: um sub-agente analisava o
histórico completo e subia um questionário próprio num site, onde o usuário
anotava cada proposta (`P001: sim · global`). Na prática, isso se provou um
atrito desnecessário no momento errado: o usuário já passou por TUDO na
execução (ondas, gates, merge, relatório) e, ao fim, é convidado a sair do
terminal e responder num navegador — quando a pergunta poderia simplesmente
estar no terminal, respondida com um código. O pedido (2026-08-28):
**a evolução não vem mais como um site; vem como uma pergunta depois de tudo,
até do commit e push** — no formato:

```
1 - Toda vez que criamos uma worktree precisamos instalar as dependências.
    como resolver definitivamente?
    a: symlinks
    b: merge para principal e teste
    c: não fazer nada
    (1 = fix local · 2 = fix global — qual config você quer? ex.: 1:b2)
```

O usuário responde **se quiser** (já passou por tudo; pular é legítimo), e uma
flag `no-evolve` na invocação pula a pergunta **e** o pós-processamento —
porque sem a flag os sub-agentes entregam todo o histórico mais o principal
(handoffs + transcripts + TASK_PLAN.md) para essa análise.

## Restrição de mecanismo (medida em 2026-08-28)

O Bash tool do harness NÃO tem stdin interativo (`read` retorna EOF na hora —
verificado na sessão). Logo, "pergunta no terminal" NÃO pode ser um `read`
bloqueante; e a skill proíbe AskUserQuestion (inexistente nos harnesses onde
ela roda: Claude Code, DSH, pi, jcode, opencode). A única mecânica
harness-agnóstica e terminal-first: **o orquestrador imprime a pergunta na
mensagem final e encerra o turno; o usuário responde com códigos na próxima
mensagem; a continuação (FASE 0 passo 0.4) processa a resposta**. O estado
pendente vive no DISCO (`$DO_STATE/evolution/pendente.md`), não na memória do
turno — sobrevive a compactação de contexto e a sessões novas.

## Decisões

### D18 — PERGUNTA EM TEXTO, NUNCA MAIS UM SITE

- **Decisão:** a evolução pós-execução deixa de abrir o Plannotator. O agente
  de evolução (único, fresco, modelo forte — inalterado) escreve
  `proposals.md` com as propostas **no formato de pergunta**: além dos campos
  de candidato (key/type/confidence/source/scope/observacao/acao), cada bloco
  ganha `opcao_a`, `opcao_b` (soluções CONCRETAS) e `opcao_c` (SEMPRE "Não
  fazer nada (descartar)"). `evolution-survey.sh ask` monta a pergunta
  numerada em `pendente.md` e a imprime; o orquestrador a cola na mensagem
  final e encerra o turno. SEM limite de tempo: o usuário responde quando
  quiser. Nada de `questionario.md`/HTML — o site morre junto.
- **Evidência:** o formato de pergunta do pedido; o atrito navegador-no-fim
  da execução relatado pelo usuário; a restrição de stdin medida na sessão.
- **Fonte:** usuário (2026-08-28); medição direta do harness.

### D19 — GRAMÁTICA `N:XY` (opção + escopo) E A OPÇÃO VIRA A AÇÃO

- **Decisão:** resposta com códigos — `N:XY` (N = número da proposta, X =
  opção a|b|c, Y = escopo 1|2); `b2` abreviado quando há UMA proposta; `nada`/
  `pular`/vazio = nada salvo; `config: <texto>` (no início OU no meio da
  linha) = preferência livre do projeto. A opção **a|b** salva a proposta com
  a AÇÃO da opção escolhida (o `acao` do bloco é SUBSTITUÍDO — o usuário
  decidiu a solução definitiva, não só "salvar ou não"); **c** = descarta;
  dígito 1 = fix local (projeto), 2 = fix global (skill). Resposta ilegível →
  exit 2 com a gramática na mensagem. `dismiss` = sem resposta (tudo pendente,
  nada aplicado — gate humano inalterado).
- **Evidência:** o exemplo do pedido ("ex.: b2"); o modelo de escopo da
  v3.8.0 (project/global) preservado como dígito.
- **Fonte:** usuário; evolução da D12–D17.

### D20 — `no-evolve` PULA A PERGUNTA E O PÓS-PROCESSAMENTO

- **Decisão:** token booleano `no-evolve` na invocação (qualquer posição, como
  `no-stop`) → `DO_EVOLUTION_SURVEY=0` (o kill-switch manual da v3.8.0 vira
  flag de invocação). Sem a flag (default), a pergunta SEMPRE aparece ao fim,
  mesmo com gatilhos de autonomia. Com `no-evolve`, o passo 7.5 é pulado
  INTEIRO: o agente de evolução nem é disparado no passo 4 (a análise do
  histórico completo — handoffs + transcripts + TASK_PLAN.md — é o custo que
  a flag evita), nada é perguntado, nada é aplicado.
- **Evidência:** "pode evitar a pergunta com o no-evolve flag evitando a
  pergunta e o pos processamento de tudo que foi feito nela (porque sem a
  flag os subagents entregam todo o historico mais o principal para essa
  analise)".
- **Fonte:** usuário.

### D21 — POSIÇÃO: DEPOIS DE TUDO (COMMIT + PUSH + RELATÓRIO) + CONTINUAÇÃO NA FASE 0

- **Decisão:** o passo de evolução sai do meio (6.5) e vira o **7.5**, o
  ÚLTIMO passo — depois do commit (5), do novo passo **5.5 PUSH** (guarded:
  `git push -u origin $BASE_BRANCH` quando há remote; falha/sem remote →
  AVISO no relatório, nunca bloqueia) e do relatório (7). A limpeza do
  $DO_STATE vira o passo 8, PULADO quando a pergunta fica pendente. A
  continuação é um contrato de entrada: a FASE 0 ganha o passo **0.4
  RESOLVA EVOLUÇÃO PENDENTE** — se há `run-*/evolution/pendente.md` no disco,
  a mensagem do usuário é resposta → `answer` + `apply` + limpeza + fim de
  turno; não é resposta → `dismiss` (tudo pendente) + limpeza + prossegue com
  a tarefa nova. A pergunta nunca é refeita.
- **Evidência:** "vem como uma pergunta depois de tudo ate do commit e push";
  robustez: estado no disco, não na memória do turno.
- **Fonte:** usuário; engenharia de continuação do harness.

### D22 — PREFIXO `mp=N` → `max-parallel=N`

- **Decisão:** o prefixo de invocação do cap de concorrência (F3-02,
  DO_MAX_PARALLEL) passa a ser `max-parallel=N`, em toda a doc (SKILL.md,
  README, do-context.sh). Nome explícito, zero ambiguidade com `tmp=`. Sem
  alias de compatibilidade: a skill é nova o suficiente para a troca limpa.
- **Evidência:** pedido explícito ("quero mudar o mp por max-parallel").
- **Fonte:** usuário.

## Fora de escopo

- O PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5) continua no Plannotator — só a
  EVOLUÇÃO saiu do site.
- `DO_SURVEY_TIMEOUT` foi removido (não existe mais espera bloqueante por
  rodada; a resposta é assíncrona por construção).
- A promoção ao corpo da skill continua MANUAL/periódica (evolution-guide.md,
  diff revisável + bump MINOR) — NO_SELF_VALIDATION inalterado.
