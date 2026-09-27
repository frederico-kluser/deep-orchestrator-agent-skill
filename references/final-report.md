<!-- MÓDULO v6.0.0 · origem: SKILL.md <final-report-template> (split progressive disclosure)
     carga: FASE 4 passo 7 (relatório final) · conteúdo byte-a-byte com a origem (CONTRATO.md §5)
     1 HOP: não referenciar outros módulos -->

  <final-report-template>
    <![CDATA[
## [Tarefa concluída | Tarefa concluída PARCIALMENTE]
[Fonte: a linha RESUMO do `"$DO_WT" ledger` (FASE 4 passo 6). "Tarefa concluída"
SÓ com nunca-integradas=0 e parciais=0; com NEVER-MERGED ou MERGED-PARTIAL
(PURGE_RC=3), ou na opção [4] do protocolo: PARCIALMENTE.]
[Resumo em linguagem natural. Se PARCIALMENTE, ou se "Pesquisa" tem pausa,
opção [3] ou fato NÃO VERIFICADO, a PRIMEIRA frase diz isso.]

## Não integrado
[OBRIGATÓRIA. Fonte: `"$DO_WT" ledger` + o bloco `PURGE: NUNCA INTEGRADAS /
PARCIAIS` do purge, LITERAL. Uma linha por filha NEVER-MERGED, MERGED-PARTIAL
ou EMPTY; nada → "nenhum".]
| Worktree | Kind | Onda | Destino (NEVER-MERGED:<motivo> / MERGED-PARTIAL:<motivo> / EMPTY) | ARCHIVE_REF | Resgate |
|----------|------|------|--------------------------------------------------------------------|-------------|---------|
{{NOT_INTEGRATED_ROWS_OR_NENHUM}}
[Resgate = `git branch resgate/<nome> refs/do-archive/$RUN_ID/<nome>` (RUN_ID
literal; refs LOCAIS, não vão no push). EMPTY não tem resgate.]
- Planejadas e nunca despachadas (fonte: TASK_PLAN.md): [lista | nenhuma]

## O que cada sub-agente fez
| Onda | Worktree | Tarefa | Arquivos | Status (outcome do ledger) |
|------|----------|--------|----------|----------------------------|
{{ROWS}}

## Commits realizados (squash commits, um por sub-tarefa)
{{COMMITS}}

## Pesquisa
[OBRIGATÓRIA. Fonte: tabelas "Triagem de pesquisa — Onda N" e linhas
PAUSA-PESQUISA do TASK_PLAN.md. Nenhuma SEARCH_REQUIRED=sim e nenhuma chamada
busca → "Pesquisa: não exigida."]
- Portão (`"$DO_TAVILY_GATE"`): [TAVILY_GATE/TAVILY_CODE na FASE 0, no PORTÃO PÓS-PLANO e no passo 0 de cada onda]
- Pausas do protocolo PESQUISA-FALHOU: [N — por pausa: onda, sub-tarefas, motivo, opção do usuário ([1]|[2]|[3]|[4])] | nenhuma
- Decisão do usuário de seguir SEM pesquisa (opção [3]): [sim — a partir da onda N | não]
| Onda | Sub-tarefa | SEARCH_REQUIRED | SEARCH_STATUS | Comandos de busca / exit |
|------|------------|-----------------|---------------|----------------------|
{{SEARCH_ROWS}}
- Premissas e fatos NÃO VERIFICADOS (busca vazia | pesquisa falhou | seguiu sem pesquisa): [lista com a sub-tarefa | nenhum]

## Testes
[UM bloco, conforme o TEST_MODE — apague os outros.]
[full]
### Cobertura de Testes (Testing Subwaves)
| Testing Subwave | Worktree | Arquivos cobertos | Cobertura | Status |
|-----------------|----------|-------------------|-----------|--------|
{{TESTING_SUBWAVE_ROWS}}
### Arquivos sem cobertura (degradação)
{{UNCOVERED_FILES_OR_NONE}}
[none]
Testes: DESLIGADOS por no-test — testes novos: <N, verificado por `gwt diff --stat <pre-da-1ª-filha>..HEAD -- <globs de teste>`>; gate rodou a suíte existente: <GATE_TEST>
- Testes EXISTENTES ajustados por mudança intencional de contrato: [lista | nenhum]
- Arquivos sem cobertura: N/A (no-test)
[e2e]
### Testes e2e (only-e2e)
| Testing Subwave | Worktree | Jornadas cobertas / planejadas | Specs | Runner | Status |
|-----------------|----------|--------------------------------|-------|--------|--------|
{{E2E_SUBWAVE_ROWS}}
### Jornadas sem cobertura
[Jornadas que nunca fecharam, sem spec, ou com spec fixme/flaky — com o motivo. Ou "nenhuma".]

## Validação de Código (Validation Subwaves)
| Validation Subwave | Veredito do gate (build/lint/typecheck/testes, + e2e em only-e2e) | Achados adversariais | Fixes gerados | Status |
|--------------------|-------------------------------------------------------------------|----------------------|---------------|--------|
{{VALIDATION_SUBWAVE_ROWS}}

## Bugs encontrados
| Origem (teste/validação) | Descrição (arquivo:linha) | Fix aplicado (sub-tarefa) | Estado (CORRIGIDO / ABERTO — teste segue skip/xfail/fixme) |
|--------------------------|---------------------------|---------------------------|--------------------------------------------------------------|
{{BUG_ROWS}}

## Perguntas ao usuário
[SÓ com DO_QUESTION=1 — sem a flag, OMITA. A pergunta do protocolo vai em "Pesquisa".]
| Rodada (antes do plano / fim da onda N) | Pergunta | Resposta | Default aceito? |
|------------------------------------------|----------|----------|-----------------|
{{QUESTION_ROWS}}
- Dúvidas devolvidas por sub-agentes que NÃO viraram pergunta: [lista + o que foi inferido | nenhuma]

## Portão de aprovação do plano (FASE 2.5)
[Omita quando PLAN_APPROVAL=0.]
- Estado: APROVADO na revisão N / NÃO APROVADO ([recusado|fechado|timeout|orçamento]) · Rodadas: N de {{DO_PLAN_MAX_REVISIONS}} · Trail: [$PLAN_APPROVAL_DIR]
| Revisão | Decisão | O que o usuário pediu | O que mudou no plano |
|---------|---------|------------------------|----------------------|
{{PLAN_APPROVAL_ROWS}}
- Propostas do REPLAN fora do escopo aprovado: [nenhuma | lista com o veredito]

## Contenção
- Modo: [contido | normal] · Raiz-de-mundo: [$BASE_DIR] · Branch de integração: [$BASE_BRANCH]
- Projeto principal ([$MAIN_ROOT]): HEAD e working tree inalterados — [resultado do último `do-wt.sh verify`]
- Worktrees pré-existentes de terceiros: [N] — NÃO tocadas

## Limpeza
[Fonte: saída do passo 6 da FASE 4.]
- Cada filha fechada pelo script no gate verde dela (integrate → gate → finish); as não integradas por close.
- Purge final: [PURGE OK | PURGE INCOMPLETO — o que sobrou] · PURGE_RC=[0 | 3 — ver "Não integrado"] · [ASSERT-CLEAN OK — tudo fechado]
- RESUMO do ledger, LITERAL: integradas=N nunca-integradas=N vazias=N descartaveis=N parciais=N abertas=0 sem-destino=0
- Branches arquivados em refs/do-archive/$RUN_ID/ (refs LOCAIS). Única exceção viva: a worktree wt-root (DO_WT_ROOT=1), fora do owned.tsv.

## Dependências instaladas
[Por sub-agente: gerenciador, pacotes, versões, lockfile. Ou "Nenhuma".]

## Decisões tomadas autonomamente
[Premissas inferidas sem perguntar.]

## Convergência (válvula de escape)
["Convergência declarada pelo REVISOR DE PLANO." ou válvula (teto de ondas — só com DO_NO_STOP=0 | REPLANs estagnados) + propostas não executadas.]

## Bloqueios — causa e o que destrava
[As linhas de "Não integrado" com a causa e o que o usuário faz para destravar. Ou "nenhum".]

## HTML Explainer
EXPLAINER.html gerado em $BASE_DIR/EXPLAINER.html pelo fluxo `html-explainer-agent-skill` (brief didático + render `visual-explainer`). Degradação (fallback mínimo, R1-c): [nenhuma | registrar].

## Evolução pós-execução
- Propostas do agente de evolução: [N (X globais, Y projeto) | nenhuma | não rodou (no-evolve / degradação)]
- Pergunta: [respondida na mensagem final — códigos "1:b2" | sem candidatos | degradada | DO_EVOLUTION_SURVEY=0 (no-evolve)]
- Resposta do usuário: [pendente — turno seguinte (FASE 0 passo 0) | salvas/descartadas/pendentes com path]
- Configs salvas do projeto: [nenhuma | lista]
- Push: [feito — $BASE_BRANCH | sem remote | falhou (registrar)]
]]>
  </final-report-template>
