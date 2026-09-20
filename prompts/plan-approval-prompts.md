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
- <premissa externa que ficou sem pesquisa: marque **NÃO VERIFICADA** e o
  motivo — "busca vazia" ou "usuário autorizou seguir sem busca">

## Política de testes        <!-- conforme $DO_TEST_MODE (FASE 2, passo 4.5) -->
<full: "testes escritos ao fim de cada onda" · none: "Testes: DESLIGADOS por
no-test — nenhum teste novo; a suíte existente roda a cada integração" · e2e:
"só testes end-to-end" + o mapa jornada → onda em que fecha → o que ela prova.
Quem aprova precisa VER que a flag pegou.>

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
| `[🔍 Verify this]` | "você assumiu isso" | Voltar ao código (`Read`/`Grep`) ou pesquisar — com o comando da seção 2.1, que CLASSIFICA o resultado — e trocar a premissa por fato **antes** de reescrever. `EMPTY` (a busca funcionou e veio vazia): premissa **NÃO VERIFICADA**, motivo "busca vazia", sem pergunta. `BLOCKED_78` (exit 78), `FAILED_QUOTA`, `FAILED_OTHER` ou binário ausente (127): execute o protocolo PESQUISA-FALHOU — NUNCA marque NÃO VERIFICADA por conta própria. |
| `[👍 Looks good]` | aprovação parcial | Não mexer nesse trecho. Mudá-lo mesmo assim custa uma rodada. |
| `Remove this` | bloco a apagar | Apagar o trecho citado. |
| `General feedback` | comentário global | Costuma ser sobre abordagem, não sobre um item — pode implicar redesenhar as ondas. |
| Comentário livre | o caso comum | Responder no plano, no lugar em que a linha citada estava. |

**Discordar é permitido; ignorar não.** Um item que você acha errado ainda
precisa aparecer no plano novo, com a razão explícita. Silêncio, para quem
aprova, lê-se como item ignorado — e vira mais uma rodada.

### 2.1 A busca do `[🔍 Verify this]` (mesma regra da FASE 2.5, passo 5)

É o ÚNICO ponto do fluxo em que o ORQUESTRADOR roda uma busca surf ele mesmo
(fora a sonda `resume --probe` do protocolo PESQUISA-FALHOU). Aqui ele está
sozinho, R=1, então fica com o teto inteiro de `--sub-agents`. O exit code cru
engana — cota esgotada, 429 e billing saem **1**, igual a "não achei" —, por
isso a saída vai para arquivo e é CLASSIFICADA na mesma chamada Bash:

```bash
. '<ENV_FILE>'; surf-search-normal "<pergunta>" --insights "<a premissa>" --deliverable "fato + URL" --sub-agents="${DO_SURF_SUB_AGENTS:-10}" > "$DO_STATE/verify.out" 2> "$DO_STATE/verify.err"; rc=$?; "$DO_SURF_GATE" classify "$rc" "$DO_STATE/verify.out" "$DO_STATE/verify.err"
```

| Classe impressa | O que fazer |
|---|---|
| `OK` | Ler `$DO_STATE/verify.out` e trocar a premissa por FATO com URL. |
| `EMPTY` (exit 1: a busca FUNCIONOU e veio vazia) | Manter a premissa marcada **NÃO VERIFICADA**, motivo "busca vazia". SEM pergunta. |
| `BLOCKED_78` (exit 78) · `FAILED_QUOTA` · `FAILED_OTHER` (inclui o exit 127 do binário ausente) | O usuário PEDIU a verificação, logo a pesquisa é EXIGIDA: executar o protocolo **PESQUISA-FALHOU** (`SKILL.md`, logo após a R7; onda = 0; sub-tarefas bloqueadas = `"[Verify this] <premissa>"`) e NÃO abrir outro Plannotator antes da resposta. |
| `USAGE_2` | O comando montado está errado: corrigir e rodar de novo. |
| `KILLED_143` | Estourou o timeout do Bash: refazer com timeout maior. |

**NUNCA marque NÃO VERIFICADA por conta própria num 78/127/cota.** Chave, cota
e instalação são ambiente do USUÁRIO: só a opção [3] da pergunta do protocolo
autoriza seguir sem a busca — e aí o motivo registrado é "usuário autorizou
seguir sem busca". Na retomada com `RESUME=OK`, refaça ESTA busca e continue
a regeneração do plano. Nunca troque de ferramenta.

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
2. Para cada [🔍 Verify this]: investigue de verdade (Read/Grep no repositório;
   se o código não responde, a busca CLASSIFICADA da FASE 2.5, passo 5:
   `. '<ENV_FILE>'; surf-search-normal "<pergunta>" --insights "<a premissa>" --deliverable "fato + URL" --sub-agents="${DO_SURF_SUB_AGENTS:-10}" > "$DO_STATE/verify.out" 2> "$DO_STATE/verify.err"; rc=$?; "$DO_SURF_GATE" classify "$rc" "$DO_STATE/verify.out" "$DO_STATE/verify.err"`)
   e substitua a premissa por fato. Aja pela CLASSE impressa: OK = fato com
   URL. EMPTY (a busca funcionou e veio vazia) = mantenha a premissa marcada
   **NÃO VERIFICADA**, motivo "busca vazia" — sem pergunta. BLOCKED_78 (exit
   78), FAILED_QUOTA ou FAILED_OTHER (inclui o 127 do binário ausente) = a
   verificação foi PEDIDA pelo usuário, logo a pesquisa é EXIGIDA: execute o
   protocolo PESQUISA-FALHOU e NÃO abra outro Plannotator antes da resposta.
   NUNCA marque NÃO VERIFICADA por conta própria num 78/127/cota — só a opção
   [3] do usuário autoriza. Não troque de ferramenta.
3. Para cada [🚫 Out of scope] e cada "Remove this": REMOVA do plano. Se a
   sub-tarefa removida tinha worktree batizada, tire-a também.
4. Refaça a decomposição da FASE 2 com o feedback como restrição de PRIMEIRA
   classe: ondas, mapa de propriedade de arquivo, batismo (R6) e prompts todos
   derivam do plano NOVO. Preencha SEARCH_REQUIRED=sim|não para cada
   sub-tarefa nova; se nasceu alguma com "sim", repita o PORTÃO PÓS-PLANO
   (FASE 2, passo 9) antes da próxima rodada. A decomposição nova segue a
   POLÍTICA DE TESTES de $DO_TEST_MODE (FASE 2, passo 4.5): em `none` não
   nasce sub-tarefa cujo entregável seja teste; em `e2e` recalcule o MAPA DE
   JORNADAS.
5. Reescreva $PLAN_FILE (TASK_PLAN.md) e $PLAN_DOC, mantendo o TÍTULO
   IDÊNTICO e abrindo o corpo com "## O que mudou nesta revisão", que responde
   item a item ao feedback.

Se você discorda de um item, ele ainda entra no plano novo, com a razão
explícita. Não deixe nenhum item sem resposta visível.
```

---

## 4. Prompt: REVISOR DE PLANO subordinado ao plano aprovado

Delta a colar no prompt do REVISOR DE PLANO (FASE 3, passo 5) quando
`$DO_PLAN_APPROVAL=1`. `{{TEST_MODE}}` = o valor de `$DO_TEST_MODE` lido do
ENV_FILE (`full` | `none` | `e2e`) — o revisor RECEBE o modo de teste para não
propor o que a flag desligou (o bloco MODO DE TESTE vale também sem portão:
a FASE 3, passo 5, manda colar a mesma proibição quando o modo é `none`).

```
RESTRIÇÃO — ESTE PLANO FOI APROVADO PELO USUÁRIO:
{{CONTEUDO_DO_PLANO_APROVADO}}

FEEDBACK ACUMULADO NAS RODADAS DE APROVAÇÃO:
{{FEEDBACK_ACUMULADO}}

MODO DE TESTE DESTA EXECUÇÃO: {{TEST_MODE}}
- none (no-test): é PROIBIDO propor sub-tarefa cujo entregável seja teste. A
  Testing Subwave está DESLIGADA de propósito; ausência de testes novos NÃO é
  lacuna do plano. (O gate continua rodando a suíte EXISTENTE.)
- e2e (only-e2e): NÃO proponha sub-tarefa de teste unit/integration. Os testes
  e2e nascem na Testing Subwave, por JORNADA; se a sua proposta muda a onda em
  que uma jornada FECHA, diga qual jornada e para qual onda.
- full: nada muda.
Em QUALQUER modo você NUNCA propõe subwaves (testing/validation): o
orquestrador as gera sozinho.

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
