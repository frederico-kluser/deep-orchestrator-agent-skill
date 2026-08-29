# Prompts do PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5)

Templates da fase em que o usuário aprova o plano no Plannotator antes de
qualquer worktree existir. Referência normativa: R10 e a FASE 2.5 do `SKILL.md`.

> **Não confunda com o "gate" do projeto.** `GATE_BUILD` / `GATE_TEST` /
> `GATE_LINT` (FASE 1, passo 9) são build, teste e lint de integração. O portão
> desta fase não roda suíte nenhuma — ele só pergunta ao usuário se o plano
> está certo.

---

## 1. O documento de aprovação (`$PLAN_DOC`)

O `TASK_PLAN.md` é o caderno de bordo da execução: SHAs, `owned.tsv`, baselines,
handoffs. Quem vai *decidir* não consegue ler aquilo. O `$PLAN_DOC` é o mesmo
plano visto por quem aprova.

### Regra que não se negocia: o TÍTULO é imutável

O Plannotator deriva do primeiro `#` o identificador com que reconhece que duas
sessões falam do MESMO plano. Trocá-lo entre revisões cria um plano novo e joga
o histórico fora — por isso o `plan-approval.sh round` **recusa** (exit 2) uma
rodada cujo título mudou, e por isso o próprio Plannotator instrui, no texto que
ele devolve na negação: *"Do NOT change the plan title"*.

O título descreve a **tarefa**, nunca a revisão:

| | |
|---|---|
| ✅ | `# Plano: migração do módulo de pagamentos para a nova API` |
| ❌ | `# Plano v2` · `# Plano (revisado)` · `# Plano — rodada 3` |

### Esqueleto

```markdown
# Plano: <a tarefa, em uma linha — IDÊNTICO em todas as revisões>

## O que mudou nesta revisão      <!-- só da revisão 2 em diante -->
- <item do feedback anterior> → <o que você fez a respeito>
- <item do feedback anterior> → <o que você fez a respeito>

## Objetivo
<1-2 frases: o que passa a ser verdade quando isso terminar.>

## Abordagem
<Como, em prosa curta. Sem jargão de orquestração — nada de owned.tsv,
BRANCH_NS, squash-merge, subwave. Quem aprova não opera a máquina.>

## Ondas
| Onda | Sub-tarefa | O que entrega | Arquivos que toca |
|------|-----------|----------------|-------------------|
| 1 | <nome> | <entrega observável> | `caminho/` |

## Fora do escopo
- <o que este plano deliberadamente NÃO faz>

## Riscos e premissas
- <premissa que você assumiu e que, se falsa, muda o plano>

## Como verificar que funcionou
- <comando ou observação concreta>
```

A seção **Fora do escopo** é a que mais economiza rodadas: quase todo feedback
`🚫 Out of scope` nasce de uma fronteira que o plano não declarou.

---

## 2. Ler o feedback

`plan-approval.sh feedback` devolve o markdown que o Plannotator monta. Formato
real (verificado no binário):

```markdown
## 1. (line 12) Feedback on: "trecho que o usuário selecionou"
> o comentário dele

## 2. (line 30) [🚫 Out of scope] Feedback on: "outro trecho"

## 3. (line 41) Remove this
```
o trecho que ele quer fora
```
> I don't want this in the document.

## 4. General feedback about the document
> um comentário que não está preso a nenhum trecho

---

## Label Summary
- **🚫 Out of scope**: 1
```

Pode vir também uma seção `## Reference Images` ou `**Attached images:**` com
**caminhos de arquivo** — leia essas imagens com `Read` antes de responder a
elas; ignorá-las é responder metade do feedback.

### Tabela de reação

| No feedback | O que significa | O que fazer |
|---|---|---|
| `[🚫 Out of scope]` | "isso não é parte da tarefa" | **REMOVER** a sub-tarefa do plano — não reduzir, tirar. E remover a worktree batizada para ela. |
| `[🔍 Verify this]` | "você assumiu isso" | Voltar ao código (`Read`/`Grep`) ou pesquisar (`surf-search-normal "<pergunta>" --insights "<a premissa>" --deliverable "fato + URL"`) e trocar a premissa por fato **antes** de reescrever. Se sair 78 (sem chave Brave válida), MANTENHA a premissa e marque-a **NÃO VERIFICADA**, dizendo por quê. |
| `[👍 Looks good]` | aprovação parcial | Não mexer nesse trecho. Mudá-lo mesmo assim custa uma rodada. |
| `Remove this` | bloco a apagar | Apagar o trecho citado. |
| `General feedback` | comentário global | Costuma ser sobre abordagem, não sobre um item — pode implicar redesenhar as ondas. |
| Comentário livre | o caso comum | Responder no plano, no lugar em que a linha citada estava. |

**Discordar é permitido; ignorar não.** Um item que você acha errado ainda
precisa aparecer no plano novo, com a razão explícita. Silêncio, para quem
aprova, lê-se como item ignorado — e vira mais uma rodada.

---

## 3. Prompt: REGERAR o plano a partir do feedback

Use quando `round` sai **10 (ANNOTATED)**. Este é o caminho principal da fase,
não uma exceção.

```
Você está na FASE 2.5 do deep-orchestrator-agent-skill, revisão {{N}} de {{MAX}}.

O usuário anotou o plano no Plannotator. O trabalho agora é REGERAR O PLANO —
NÃO é implementar nada. É PROIBIDO escrever código, criar worktree ou tratar
qualquer item do feedback como sub-tarefa de implementação. O feedback é uma
correção DO PLANO.

PLANO QUE FOI REVISADO (revisão {{N-1}}):
{{CONTEUDO_DE_rev-NNN.md}}

FEEDBACK DO USUÁRIO:
{{CONTEUDO_DE_rev-NNN.feedback.md}}

TAREFA ORIGINAL:
{{ARGUMENTS}}

Faça, nesta ordem:
1. Liste cada item do feedback e o que ele exige. Itens com caminho de imagem
   (Reference Images / Attached images): leia a imagem com Read antes.
2. Para cada [🔍 Verify this]: investigue de verdade (Read/Grep no repositório,
   ou `surf-search-normal "<pergunta>" --insights "<a premissa>" --deliverable "fato + URL"`)
   e substitua a premissa por fato. Exit 78 = sem chave Brave válida: mantenha
   a premissa marcada **NÃO VERIFICADA** e diga por quê — não troque de
   ferramenta.
3. Para cada [🚫 Out of scope] e cada "Remove this": REMOVA do plano. Se a
   sub-tarefa removida tinha worktree batizada, tire-a também.
4. Refaça a decomposição da FASE 2 com o feedback como restrição de PRIMEIRA
   classe: ondas, mapa de propriedade de arquivo, batismo (R6) e prompts todos
   derivam do plano NOVO.
5. Reescreva $PLAN_FILE (TASK_PLAN.md) e $PLAN_DOC, mantendo o TÍTULO
   IDÊNTICO e abrindo o corpo com "## O que mudou nesta revisão", que responde
   item a item ao feedback.

Se você discorda de um item, ele ainda entra no plano novo, com a razão
explícita. Não deixe nenhum item sem resposta visível.
```

---

## 4. Prompt: REVISOR DE PLANO subordinado ao plano aprovado

Delta a colar no prompt do REVISOR DE PLANO (FASE 3, passo 5) quando
`$DO_PLAN_APPROVAL=1`.

```
RESTRIÇÃO — ESTE PLANO FOI APROVADO PELO USUÁRIO:
{{CONTEUDO_DO_PLANO_APROVADO}}

FEEDBACK ACUMULADO NAS RODADAS DE APROVAÇÃO:
{{FEEDBACK_ACUMULADO}}

Classifique CADA proposta sua em exatamente uma categoria:

DENTRO — detalha, corrige ou reordena o que o plano aprovado já previa, sem
alargar o que será entregue. Descobrir detalhe durante a execução é o objetivo
do REPLAN; isso segue sem nova aprovação.

FORA — acrescenta entregável, toca subsistema que o plano não citava, ou
contraria um item que o usuário mandou remover. Estas voltam ao portão.

Responda com as duas listas separadas e, para cada item FORA, uma linha
dizendo por que ele não cabe no escopo aprovado.
```

---

## 5. Prompt: parada sem aprovação

Use nos exits **11 (fechado)**, **12 (timeout)** e **14 (orçamento)**. É saída
legítima por R3: na FASE 2.5 não existe worktree, branch nem commit — o
repositório está exatamente como estava.

```
O portão de aprovação terminou sem aprovação: {{MOTIVO}}.

Nada foi executado e nada mudou no repositório — na FASE 2.5 ainda não existe
worktree, branch nem commit.

Revisões até aqui:
| # | Decisão | O que você pediu | O que mudei |
|---|---------|------------------|-------------|
{{LINHAS}}

O que destrava:
- revisar o plano de novo (o trail está em $PLAN_APPROVAL_DIR);
- `DO_PLAN_MAX_REVISIONS=N` para subir o teto de rodadas;
- `plan=off` para executar sem o portão;
- reformular a tarefa.
```

Nunca ofereça "executo assim mesmo": ausência de resposta não é consentimento,
e quem pediu para aprovar o plano não autorizou a execução dele.
