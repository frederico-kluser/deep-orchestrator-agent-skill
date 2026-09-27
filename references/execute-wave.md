<!-- MÓDULO v6.0.0 · origem: SKILL.md <phase 3 EXECUTE-ONDA> (split progressive disclosure)
     carga: ao ENTRAR na FASE 3 (antes do passo 0) · conteúdo byte-a-byte com a origem (CONTRATO.md §5),
     salvo as correções D-H (modelo único mimo-v2.6-pro, sem tiering) -->

    <phase id="3" name="EXECUTE-ONDA">
      <objective>Executar UMA onda de cada vez, com barreira, integrando e
        LIMPANDO cada sub-tarefa no instante do gate verde DELA (I-CLEAN, R6 —
        quem limpa é o script: integrate → gate → finish), e só abrir a onda
        seguinte com o PORTÃO INTER-ONDA verde: zero worktrees/branches kind
        feature|fix|prep|integration remanescentes; test-*/val-* em voo
        sobrevivem UMA onda (o assert-clean barra a segunda); as de terceiros
        ficam intactas. Toda sub-tarefa sai da onda INTEGRADA ou FECHADA com
        motivo (I-MERGE, R3) — nunca esquecida.</objective>
      <preamble>NENHUM comando desta fase ou da seguinte vale sem
        <cmd>. '&lt;ENV_FILE&gt;'</cmd> na frente ("command not found" = faltou
        o source; NUNCA reexecute a FASE 0). Perdeu o fio (compactação,
        retomada)? <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" checklist; "$DO_WT" status</cmd>
        — o estado está no DISCO, nunca na memória.</preamble>
      <repeat>Para cada onda (1, 2, 3...), enquanto houver sub-tarefas
        pendentes — o REVISOR DE PLANO recalcula após CADA onda; ondas são
        ILIMITADAS. Válvulas: (i) MÁXIMO 10 ONDAS só com DO_NO_STOP=0
        (default; <code>no-stop</code> remove o teto); (ii) 2 REPLANs
        consecutivos sem sub-tarefa nova ACEITA → convergência forçada, SEMPRE.
        Termina quando o REVISOR DE PLANO declara CONVERGÊNCIA ou uma válvula
        a força.</repeat>
      <steps>
        <step order="0"><strong>RE-ANCORAGEM + PORTÃO DA PESQUISA (R7) — antes de
          criar qualquer worktree da onda:</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" checklist; "$DO_WT" status</cmd>
          (o CARTÃO DA ONDA e o ledger: siga-os, nunca a memória) e
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_TAVILY_GATE"</cmd>
          O veredito é a linha <code>TAVILY_GATE=&lt;0|78|127&gt;</code> (+
          <code>SEARCH_MODE=no-search</code> quando o usuário escolheu [3]):
          <substeps>
            <substep><code>SEARCH_MODE=no-search</code> (confira ANTES dos
              demais) → NÃO pause por g1–g3 nesta execução: {{SEARCH_STATUS}} =
              "NÃO PESQUISE — usuário autorizou seguir sem busca" em TODOS os
              prompts (passo 3) e prossiga.</substep>
            <substep><code>TAVILY_GATE=0</code> → prossiga.</substep>
            <substep><code>78|127</code> E há sub-tarefa PENDENTE (desta onda
              ou futuras) com SEARCH_REQUIRED=sim → NÃO crie worktree nem
              dispare pesquisadora: protocolo PESQUISA-FALHOU (g1; &lt;onda&gt;
              = N). O passo A do protocolo AQUI é concluir ANTES o passo 3.5
              (subwaves da onda N-1 em voo) — nunca pause com filha integrada
              por limpar. Com <code>TAVILY_CODE=TavilyAllBanned</code> vale a
              regra &lt;cooling&gt;: crie e dispare SÓ as SEARCH_REQUIRED=nao,
              processe o 3.5 e rerode o portão (até 3x, sem sleep) antes de
              criar as pesquisadoras; persistiu → protocolo.</substep>
            <substep><code>78|127</code> E TODAS as pendentes têm
              SEARCH_REQUIRED=nao → registre "pesquisa indisponível; nenhuma
              sub-tarefa pendente a exige" e prossiga (PROIBIDO rebaixar a
              coluna depois de ver o portão — R7).</substep>
          </substeps>
          Repete-se por onda porque a chave pode queimar ou entrar em cooldown
          no meio da execução, e o REPLAN pode introduzir pesquisa; é também
          onde {{TAVILY_SUB_AGENTS}} é recalculado para o R desta onda.</step>
        <step order="1"><strong>COMMIT PREP (se necessário):</strong> onda com
          recursos compartilhados (singletons) → commit preparatório com
          stubs/contratos ANTES das worktrees, escrito via Bash em $BASE_DIR e
          commitado em $BASE_BRANCH. Deps pendentes dos handoffs da onda
          anterior ("deps pendentes: &lt;pacote@versão&gt;") entram TODAS neste
          único commit (manifesto + lockfile, uma vez por onda):
          <cmd>. '&lt;ENV_FILE&gt;' &amp;&amp; gassert &amp;&amp; gwt add -- &lt;paths-dos-stubs&gt; &amp;&amp; gwt commit -m "PREP-onda-N: &lt;descrição&gt;"</cmd>
          Estagie por path explícito — NUNCA <cmd>git add -A</cmd>.</step>
        <step order="2"><strong>PORTÃO INTER-ONDA + CRIAR WORKTREES:</strong>
          antes da primeira worktree da onda N:
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" assert-clean --wave &lt;N&gt;</cmd>
          Só prossiga com "ASSERT-CLEAN OK — a onda &lt;N&gt; pode abrir"; rc
          != 0 → rode o comando de conserto que o script imprime para cada
          sobra e repita. Pular não adianta: o <code>new</code> faz a MESMA
          checagem e RECUSA (rc 6) feature|fix|prep da onda N com sobra — e é
          PROIBIDO contornar com <cmd>git worktree add</cmd> (R8(c)). Na onda
          1 passa direto. Então, para CADA sub-tarefa batizada na FASE 2, a
          partir de $BASE_DIR (nunca <cmd>cd</cmd> para o principal; sem
          fetch/pull/rebase de branch alheio):
          <cmd>. '&lt;ENV_FILE&gt;' &amp;&amp; "$DO_WT" new feature &lt;nome&gt;</cmd>
          (filha em $CHILD_ROOT/&lt;nome&gt; a partir de $BASE_BRANCH, branch
          $BRANCH_NS/&lt;nome&gt;, lock de posse, registro no owned.tsv).
          Confirme com <cmd>"$DO_WT" status</cmd> antes de disparar.</step>
        <step order="3"><strong>DISPARAR:</strong> para CADA sub-tarefa, chame
          <tool>Agent</tool> com dispatches ESCALONADOS (alguns segundos entre
          eles — mitiga 429; a barreira do passo 4 continua esperando TODOS):
          <field name="prompt">o TEMPLATE DE PROMPT com TODOS os placeholders
            preenchidos com valores LITERAIS: {{WORKTREE_PATH}}, {{BRANCH_NAME}},
            {{BASE_DIR}}, {{BASE_BRANCH}}, {{SKILL_HOME}}; {{TAVILY_SUB_AGENTS}}
            (o inteiro max(1, floor(N/R)) desta onda, nunca expressão;
            SEARCH_REQUIRED=nao — e TODAS quando R=0 — recebem "0 — não
            pesquise"); {{SEARCH_STATUS}} — UM de: "pesquisa disponível" ·
            "pesquisa disponível sem síntese — sem chave OpenRouter" · "NÃO
            PESQUISE — usuário autorizou seguir sem busca" (OBRIGATÓRIO em
            todos os prompts com SEARCH_MODE=no-search: o sub-agente não chama
            binária busca e devolve cada premissa externa NÃO VERIFICADA) ·
            "NÃO PESQUISE — pesquisa indisponível e esta sub-tarefa não a
            exige" (portão != 0 e SEARCH_REQUIRED=nao); {{TEST_POLICY}} (texto
            FIXO do modo em vigor, FASE 2 passo 4.5 — em TODO agente que
            escreve código; leia $DO_TEST_MODE do ENV_FILE); {{DO_QUESTION}}
            ($DO_QUESTION: com 1 o sub-agente devolve a seção
            <code>## Dúvidas para o usuário</code> no handoff — ele NUNCA
            pergunta ao usuário; com 0 a seção não existe); {{MAIN_ROOT}} =
            <code>$MAIN_ROOT_DESC</code> (em MODE=normal vira "&lt;nenhum — não
            há checkout principal separado&gt;" e a verificação do principal
            vira <cmd>git -C {{BASE_DIR}} status --porcelain</cmd> comparado ao
            início); {{HANDOFF}} = a seção "Handoff Onda N-1" do TASK_PLAN.md
            colada INLINE (o sub-agente não lê o TASK_PLAN.md); onda 1:
            "Nenhum — primeira onda".</field>
          <field name="description">Resumo de 3-5 palavras</field>
          <field name="subagent_type">general-purpose</field>
          <field name="run_in_background" if="mais de 1 sub-agente na onda">true</field>
          (revisores e REVISOR DE PLANO sempre em background). MODELO
          ÚNICO (D-H): TODOS os sub-agentes correm no MESMO modelo do
          orquestrador (mimo-v2.6-pro, model: inherit) — PROIBIDO tiering por
          modelo ou downgrade (flash/leve). NÃO use isolation: "worktree" — a worktree JÁ EXISTE e tem o
          SEU nome.</step>
        <step order="3.5"><strong>PROCESSAR SUBWAVES PENDENTES (TESTES +
          VALIDAÇÃO da onda N-1)</strong> — em paralelo com o passo 4, e
          CONCLUÍDO antes do passo 8 (o assert-clean --wave N+1 acusa toda
          test-/val- da onda N-1 como sobra):
          <substeps>
            <substep><strong>GATILHO = LEDGER:</strong>
              <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" status</cmd> — TODA linha
              kind=test/validation com status != REMOVED é subwave a
              processar AGORA (onda mais antiga esquecida → PRIMEIRO). As
              seções "… Subwave Onda N-1 — PENDENTE" do TASK_PLAN.md são só
              metadado (linha sem seção → processe e registre a divergência).
              Nenhuma linha aberta → NO-OP. Com $DO_TEST_MODE=none só a
              VALIDAÇÃO existe.</substep>
            <substep><strong>BARREIRA:</strong> aguarde os sub-agentes das
              subwaves abertas (mesmo mecanismo do passo 4). Ainda rodam
              quando a barreira do passo 4 fechar → siga 4.5–7 e VOLTE aqui
              ANTES do passo 8: "não bloqueia o disparo" ≠ "fica para depois".</substep>
            <substep><strong>REVISÃO DE TESTES:</strong> por agente de teste,
              um revisor adversarial FRESCO com o diff + o handoff da onda
              original (+ {{BASE_DIR}} somente leitura; mesmo protocolo do
              passo 6). Avalia: cobrem os comportamentos? PASSAM de fato
              (evidência)? falsos positivos? gaps? teste FALHANDO commitado
              (bug revelado vai como skip/xfail/fixme NOMEANDO o bug —
              vermelho commitado envenena todo squash seguinte)? o diff toca
              algo além de testes/fixtures? cada "Bug encontrado" é REAL
              (CONFIRMADO | REFUTADO, arquivo:linha)? em e2e: specs são e2e de
              verdade e cobrem caminho feliz + 1 erro da jornada?
              <strong>DESTINO:</strong> APPROVE → integre; WARNING → integre
              com a ressalva registrada; BLOCK → re-dispare o agente de TESTE
              NA MESMA worktree (nunca fix de produção ali), máx 2, re-revise
              com revisor FRESCO; persistente → NÃO integre:
              <cmd>"$DO_WT" close test-onda(N-1)-&lt;foco&gt; --discard "testes reprovados na revisão: &lt;motivo&gt;"</cmd>
              + "Arquivos sem cobertura" (I-MERGE).</substep>
            <substep><strong>INTEGRAR OS TESTES (como feature):</strong> por
              agente aprovado, com o nome COMPLETO da linha do ledger:
              <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" integrate test-onda(N-1)-&lt;foco&gt; "test-onda(N-1)-&lt;foco&gt;: adiciona testes para &lt;desc&gt;"</cmd>
              e em background <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" gate test-onda(N-1)-&lt;foco&gt;</cmd>
              (em e2e, com a porta do contexto — tabela E2E_PORT do passo 10:
              <code>E2E_PORT=&lt;p&gt; "$DO_WT" gate test-onda(N-1)-e2e-&lt;jornada&gt;</code>;
              o gate liga o e2e sozinho para kind=test). Conflito, VAZIO e
              VERMELHO: mesmos ramos do passo 7.</substep>
            <substep><strong>VALIDAÇÃO — veredito + fechamento SEM merge:</strong>
              avalie o veredito por etapa e os achados do revisor do diff
              integrado; a val-onda(N-1)-gate NUNCA é mergeada — feche-a assim
              que o veredito chegar:
              <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" close val-onda(N-1)-gate</cmd>
              (validation fecha sempre, sem --discard; DISPOSABLE). Falha por
              AMBIENTE → reinstale deps congeladas e re-rode (nunca fix de
              produção — R9). Falhas de código → fix abaixo.</substep>
            <substep><strong>TASK_PLAN.md:</strong> marque "… Subwave Onda N-1
              — CONCLUÍDA" SÓ quando o <cmd>"$DO_WT" status</cmd> mostrar
              REMOVED em todas as test-/val- daquela onda. Gate vermelho
              persistente (2 fixes) num test-*: <cmd>"$DO_WT" undo test-onda(N-1)-&lt;foco&gt;</cmd>
              (desfaz TODOS os squashes dela; NUNCA <cmd>git reset --hard HEAD~1</cmd>
              — HEAD~1 pode ser o PREP ou outro squash), depois
              <cmd>"$DO_WT" close test-onda(N-1)-&lt;foco&gt; --discard "gate vermelho persistente"</cmd>
              e registre os arquivos não cobertos.</substep>
            <substep><strong>BUGS DOS HANDOFFS VIRAM FIX:</strong> bug
              CONFIRMADO pelo revisor de testes, ou reportado pela validação →
              sub-tarefa de fix com PRIORIDADE na onda em curso:
              <cmd>"$DO_WT" new fix ondaN-fix-&lt;foco&gt;</cmd>, integrada pelo
              passo 7. O prompt leva o bug (arquivo:linha) e o teste que o
              revela: "remova o marcador skip/xfail/fixme e faça-o passar
              corrigindo a PRODUÇÃO — PROIBIDO enfraquecer a asserção ou
              apagar o teste" (o fix vira dono desse arquivo de teste; integre
              o test-* ANTES). Máx 2 tentativas por achado; o que sobrar vai a
              "Bugs encontrados" como ABERTO — nunca rebaixado a "sem
              cobertura".</substep>
          </substeps>
          Subwaves nunca bloqueiam o DISPARO da onda atual nem da seguinte,
          MAS a onda N não FECHA com subwave da N-1 aberta (passo 8). Validação
          reprovada não bloqueia a onda em curso; seus fixes têm prioridade, e
          o COMMIT-FINAL não fecha com validação VERMELHA sem degradação
          documentada.</step>
        <step order="4"><strong>BARREIRA:</strong> aguarde TODOS os sub-agentes
          desta onda (notificações do harness ou o mecanismo de espera
          equivalente — ex.: TaskOutput com wait: true). NUNCA prossiga antes.</step>
        <step order="4.5"><strong>TRIAGEM DE PESQUISA — entre a barreira e o
          REPLAN, ANTES de revisar ou integrar:</strong> todo handoff abre com
          <code>## SEARCH_STATUS</code> e a linha
          <code>SEARCH_STATUS: NOT_NEEDED | OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_NOKEY</code>
          (+ comandos de busca/exit codes, erro VERBATIM, fatos NÃO VERIFICADOS).
          Falha de pesquisa NÃO é premissa a inferir:
          <substeps>
            <substep>EXTRAIA a linha de CADA handoff. Seção ausente numa
              SEARCH_REQUIRED=sim = UNKNOWN; numa =nao = NOT_NEEDED.</substep>
            <substep>REGISTRE a tabela "Triagem de pesquisa — Onda N"
              (sub-tarefa → SEARCH_REQUIRED → SEARCH_STATUS → comandos → erro
              → fatos NÃO VERIFICADOS) — fonte da seção "Pesquisa" do
              relatório.</substep>
            <substep><code>OK</code> | <code>NOT_NEEDED</code> → fluxo normal.
              <code>EMPTY</code> → fato NÃO VERIFICADO ("busca vazia"), fluxo
              normal, SEM pergunta; ≥ 2 EMPTY na onda → g3:
              <cmd>. '&lt;ENV_FILE&gt;'; "$DO_TAVILY_GATE" resume --probe</cmd>
              (RESUME=OK → vazios reais, siga; STILL_BLOCKED → protocolo).</substep>
            <substep><code>BLOCKED_NOKEY</code> | <code>FAILED_*</code> → g2: a
              sub-tarefa fica ACTIVE (fora dos passos 6–7; não é
              subagent-failure nem vira BLOCKED). UNKNOWN → 1 re-disparo NA
              MESMA worktree exigindo a seção; voltou sem ela →
              <code>resume --probe</code>; pause SÓ com STILL_BLOCKED. Execute
              o protocolo ANTES de integrar qualquer bloqueada: o passo A dele
              aqui é levar as NÃO bloqueadas pelos passos 5–7 até "GATE VERDE"
              e concluir o 3.5; só então B–D. O passo 8 roda DEPOIS da
              retomada (E) — até lá o sweep acusa a bloqueada como "ACTIVE —
              NÃO INTEGRADA", estado correto de onda pausada.</substep>
            <substep>Sob <code>SEARCH_MODE=no-search</code>: NÃO pause; handoff
              FAILED_*/BLOCKED_NOKEY → re-delegue NA MESMA worktree com "NÃO
              PESQUISE", NUNCA integre o parcial; cada fato sai NÃO VERIFICADO
              no handoff e no relatório.</substep>
          </substeps></step>
        <step order="5"><strong>RECÁLCULO DINÂMICO (REPLAN):</strong> ao fim da
          triagem, dispare em BACKGROUND um REVISOR DE PLANO (contexto fresco,
          sem worktree) com os handoffs desta onda + o $PLAN_FILE atual (ambos
          INLINE) + o prompt original. Roda concorrente com os passos 6–7; o
          resultado é consumido antes do passo 10/repeat. Responde em UM modo:
          <substeps>
            <substep><strong>NOVAS SUB-TAREFAS</strong> (com dependências e
              arquivos; remoções; ajustes de prioridade/sequência/mapa de
              propriedade) → VOCÊ atualiza o TASK_PLAN.md; elas passam pelos
              passos 4–7 da FASE 2 (propriedade, batismo, prompts) antes de
              virar onda. Para CADA nova: SEARCH_REQUIRED=sim|nao (critério da
              FASE 2 passo 3) e o R da onda recalculado; em e2e, recalcule o
              MAPA DE JORNADAS. Sub-tarefa BLOQUEADA POR PESQUISA entra como
              "pendente — aguardando o usuário", nunca concluída.</substep>
            <substep><strong>CONVERGÊNCIA</strong> → não há mais sub-tarefas;
              o repeat termina ao fim desta onda (com a nota "Subwaves
              pendentes desta onda serão processadas no COMMIT-FINAL").</substep>
          </substeps>
          Em ambos, PROSSIGA ao passo 6. Proposta do REPLAN é "condicionada ao
          gate verde da onda": fixes MATERIAIS da revisão → re-dispare o REPLAN
          (1 sub-agente) ou passe um delta. SUBWAVES SÃO EXCLUÍDAS DO REPLAN
          (ele nunca propõe testing/validation; achados de subwave entram no
          passo 3.5 como kind=fix). Cole SEMPRE o TEST_MODE no prompt do
          revisor: none → "PROIBIDO propor sub-tarefa cujo entregável seja
          teste"; e2e → "PROIBIDO propor teste unit/integration" — proposta
          assim é descartada e NÃO conta como ACEITA na válvula (ii).
          <strong>SUBORDINADO AO PLANO APROVADO (R10):</strong> com
          $DO_PLAN_APPROVAL=1, cole o plano aprovado + feedback acumulado e
          peça a classificação: DENTRO do escopo (detalha/corrige/reordena) →
          prossiga; FORA (novo entregável, subsistema não citado, item
          removido pelo usuário) → atualize o $PLAN_DOC (TÍTULO idêntico,
          "## O que mudou nesta revisão") e rode
          <cmd>"$DO_PLAN_APPROVAL_SH" round "$PLAN_DOC"</cmd> (exit codes como
          na FASE 2.5 passo 4; consome revisão do orçamento; exit 14 → registre
          <code>FORA-DO-ESCOPO-NÃO-APROVADA</code>, siga com o escopo aprovado
          e leve ao relatório). Com $DO_PLAN_APPROVAL=0 o REPLAN é soberano.</step>
        <step order="6"><strong>REVISÃO ADVERSARIAL — o VEREDITO é PRECONDIÇÃO
          do passo 7:</strong> por sub-agente concluído (bloqueadas por
          pesquisa ficam de fora), um revisor FRESCO com o diff
          (<cmd>. '&lt;ENV_FILE&gt;' &amp;&amp; gwt diff "$BASE_BRANCH"..."$BRANCH_NS/&lt;nome&gt;"</cmd>
          — base SEMPRE o branch da raiz-de-mundo), o prompt original,
          {{FALSIFIABLE_QUESTIONS}} e {{BASE_DIR}} (somente leitura), pelo
          TEMPLATE DE REVISÃO ADVERSARIAL com TODOS os placeholders (inclusive
          {{TEST_MODE}}: none → "ausência de testes novos NÃO é achado; teste
          existente enfraquecido/removido sem mudança de contrato É"; e2e →
          "ausência de unit/integration novos NÃO é achado"). Todos em
          background; aguarde a barreira de revisão. Só achado com evidência
          arquivo:linha reproduzível gera fix — zero fixes por finding não
          verificado; fixes em worktrees distintas rodam em paralelo.
          <strong>DESTINO (APPROVE | WARNING | BLOCK)</strong> — registrado no
          TASK_PLAN.md antes de qualquer integrate: APPROVE/WARNING → passo 7
          (WARNING com ressalva); BLOCK → fix NA MESMA worktree, pré-merge, e
          re-revisão por revisor FRESCO; TETO 2 ciclos; reprovada depois →
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" close &lt;nome&gt; --discard "reprovada na revisão adversarial: &lt;motivo&gt;"</cmd>
          (NEVER-MERGED → "Não integrado", I-MERGE) e entregue o achado ao
          REPLAN. Esta revisão é individual e pré-merge; a do diff INTEGRADO é
          a validation subwave (passo 10).</step>
        <step order="7"><strong>INTEGRAR UM A UM: INTEGRATE → GATE EM
          BACKGROUND → O SCRIPT LIMPA NO VERDE (I-CLEAN, R6):</strong> para
          cada sub-tarefa com veredito APPROVE/WARNING, na ordem do plano
          (infra/gateway primeiro, quem muda o gate por último). O squash é
          SERIAL e atômico; o gate roda em PARALELO no snapshot efêmero
          int-&lt;nome&gt; que o script cria no SHA pós-merge — NUNCA em
          $BASE_DIR (builds duplicados entre snapshot, validação e gate final
          são esperados). DOIS comandos e UM nome por sub-tarefa:
          <substeps>
            <substep><strong>INTEGRATE:</strong>
              <cmd>. '&lt;ENV_FILE&gt;' &amp;&amp; "$DO_WT" integrate &lt;nome&gt; "&lt;nome&gt;: &lt;o que a sub-tarefa entrega&gt;"</cmd>
              O script: assevera HEAD em $BASE_BRANCH; commita restos da
              filha; RECUSA filha fora do branch registrado (rc 1: siga o
              conserto impresso — switch + merge do SHA); detecta CONFLITO em
              memória ANTES de tocar a árvore (rc 1: nada a desfazer na raiz —
              degradation merge-conflict, resolva DENTRO da filha com
              <cmd>git -C &lt;wt-da-filha&gt; merge "&lt;BASE_BRANCH-literal&gt;"</cmd>
              e re-execute o MESMO integrate); squash + commit --no-verify;
              registra os SHAs; filha = gate-pending; cria o snapshot e imprime
              <code>SNAPSHOT=&lt;path&gt;</code>. VAZIO (rc 4: a filha não
              trouxe mudança) NÃO é integração (I-MERGE): confira vazamento
              com <cmd>. '&lt;ENV_FILE&gt;'; gstatus</cmd> e re-delegue NA
              MESMA worktree (subagent-failure, máx 3) ou
              <cmd>"$DO_WT" close &lt;nome&gt;</cmd> (EMPTY, vai ao relatório).
              Outro rc 1 (estagiado alheio na raiz; commit recusado por
              gpg/hook, com rollback FEITO) → siga a instrução impressa e
              re-execute. PROIBIDO merge à mão fora de $BASE_DIR e
              <cmd>git reset --hard</cmd>.</substep>
            <substep><strong>GATE (logo em seguida, em BACKGROUND, sem
              agente):</strong> <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" gate &lt;nome&gt;</cmd>
              com run_in_background=true (sem background no harness:
              foreground, em sequência, com timeout de Bash ≥ a duração do
              gate; se o harness matar, o .rc fica "running" com pid morto →
              rode o gate de novo). Roda no snapshot (HUSKY=0, CI=1) as etapas
              do gate-set: install → build → test → lint; log/rc em
              $DO_STATE/gates/&lt;nome&gt;.{log,rc}. NÃO rode o gate à mão nem
              invente comando. rc 5 = uso (sem etapa gravada / filha não
              integrada); rc 3 = já está rodando (AGUARDE; nunca dispare
              outro). Snapshot de feature NUNCA roda GATE_E2E.</substep>
            <substep><strong>SEGUIR SEM ESPERAR:</strong> os integrate seguem
              em sequência, cada um com seu gate em background; só o passo 8
              aguarda todos.</substep>
            <substep><strong>VERDE:</strong> o próprio gate chama finish e
              imprime <code>GATE VERDE — &lt;nome&gt; fechado</code> (restos
              salvos, branch arquivado em refs/do-archive/$RUN_ID/&lt;nome&gt;,
              worktree e snapshots removidos, outcome MERGED) — você NÃO roda
              nada. "GATE VERDE … mas o fechamento falhou" → repita
              <cmd>"$DO_WT" finish &lt;nome&gt;</cmd> (idempotente).
              <cmd>"$DO_WT" finish &lt;nome&gt; --gate-ok</cmd> SÓ quando VOCÊ
              rodou o gate por fora e atesta o verde, ou para VÍTIMA coberta
              (o script imprime "covered") — NUNCA para destravar vermelho.</substep>
            <substep><strong>VERMELHO (rc 4) — NADA foi limpo:</strong> filha,
              branch e snapshot ficam intactos (gate-pending). Siga a
              degradation <code>gate-red</code> (casa única: ambiente × código,
              fix NA MESMA worktree com <code>git merge</code> do $BASE_BRANCH
              ANTES do fix, re-integrate → snapshot -r2 → gate, teto 2,
              undo + close --discard, VÍTIMAS e FALHA TARDIA).</substep>
            <substep><strong>REPARO, não caminho:</strong> merge, new
              integration, mark, remove e drop-branch continuam como
              primitivos; o ritual manual (merge + snapshot + mark + remove +
              drop-branch) está ABOLIDO — use um primitivo SÓ quando a mensagem
              do script mandar. <code>mark MERGED</code> não integra nada:
              finish e drop-branch exigem o squash REGISTRADO.</substep>
          </substeps></step>
        <step order="8"><strong>FIM DE ONDA — PORTÃO INTER-ONDA:</strong>
          pré-condições: todos os gates do passo 7 reportaram e o passo 3.5
          está CONCLUÍDO. Então:
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" sweep &amp;&amp; "$DO_WT" assert-clean --wave &lt;N+1&gt;; "$DO_WT" verify</cmd>
          (<code>&amp;&amp;</code>: o portão só vale se o sweep fechou;
          <code>;</code> antes do verify: a contenção roda SEMPRE). O rc do
          composto é o do verify — LEIA a saída: a onda só está FECHADA com
          "ASSERT-CLEAN OK — a onda &lt;N+1&gt; pode abrir" E verify sem
          VIOLAÇÃO. rc != 0 de sweep/assert-clean NÃO é ignorável: rode o
          conserto impresso de cada sobra e repita. PROIBIDO ir ao 9/10 ou
          abrir a N+1 com sobra (o new recusa, rc 6). Vale na ÚLTIMA onda.
          <substeps>
            <substep><code>sweep</code> = rede de segurança do passo 7: fecha
              (finish) o que ficou MERGED e os snapshots de parent fechado;
              sai != 0 com gate-pending (aguarde o gate, ou "$DO_WT" gate
              &lt;nome&gt; se nunca rodou; vermelho → gate-red), REVERTED
              (re-integre ou close --discard) e feature|fix ACTIVE — "NÃO
              INTEGRADA": integre pelo passo 7 ou
              <cmd>"$DO_WT" close &lt;nome&gt; --discard "&lt;motivo&gt;"</cmd>;
              NUNCA a deixe para o purge em silêncio (I-MERGE). test/validation
              ACTIVE são só listadas (subwave DESTA onda, legítima por UMA).</substep>
            <substep><code>assert-clean --wave &lt;N+1&gt;</code> = o portão:
              lista (a) feature|fix|prep|integration de onda ≤ N não REMOVED
              — inclusive BLOCKED/ORPHANED: feche com
              <code>close &lt;nome&gt; --discard "&lt;motivo&gt;"</code> (R6(a));
              (b) test-/val- de onda ≤ N-1 (o 3.5 ficou aberto — volte lá);
              (c) realidade x ledger do que é provadamente nosso.</substep>
            <substep><code>verify</code> = prova de contenção: HEAD em
              $BASE_BRANCH, config local inalterada, e (com $MAIN_ROOT) HEAD e
              status do principal idênticos ao baseline. VIOLAÇÃO → TASK_PLAN.md
              e relatório.</substep>
            <substep>Entradas de <cmd>git worktree list</cmd>/<cmd>git branch --list</cmd>
              fora do owned.tsv NÃO SÃO SUAS (R8(d)); PROIBIDO
              <cmd>git worktree prune</cmd>. Diretório de filha NOSSA sumiu →
              feche a linha pelo nome (finish/close, conforme o assert-clean
              imprimir): o script desregistra SÓ aquela entrada.</substep>
            <substep><strong>RODADA DE DÚVIDAS DE FIM DE ONDA — SÓ COM
              $DO_QUESTION=1 (R2(f)):</strong>
              <cmd>. '&lt;ENV_FILE&gt;'; [ "$DO_QUESTION" = 1 ] || echo SKIP</cmd>
              SKIP → não pergunte (infira e documente). Com a flag: no máximo
              UMA rodada por onda, SÓ DEPOIS de o comando acima sair LIMPO
              (nunca com filha integrada por limpar ou gate em voo). Fontes:
              as seções <code>## Dúvidas para o usuário</code> dos handoffs e
              as suas; só decisão difícil de reverter ou que MUDA O ESCOPO
              vira pergunta. Nenhuma → registre "RODADA DE DÚVIDAS (onda N):
              nenhuma". Havendo: MESMO formato da FASE 1 passo 10, estado
              gravado ANTES em <path>$DO_STATE/question/pendente.md</path>
              ("PONTO DE RETOMADA: fim da onda N → onda N+1 (retome no passo
              9 da onda N)"), bloco como ÚLTIMA coisa da resposta e AGUARDE
              (R2). A pergunta do protocolo não passa por aqui.</substep>
          </substeps></step>
        <step order="9"><strong>HANDOFF:</strong> após o portão, registre em
          <path>$PLAN_FILE</path> a seção "Handoff Onda N": aprendizados de
          cada sub-agente, fatos NÃO VERIFICADOS da triagem (4.5) e o DESTINO
          de cada sub-tarefa (integrada | fechada com motivo), conferido no
          <cmd>"$DO_WT" ledger</cmd>. No disparo da onda seguinte VOCÊ cola
          este conteúdo em {{HANDOFF}} — sub-agentes nunca leem o TASK_PLAN.md.</step>
        <step order="10"><strong>CRIAR SUBWAVES PÓS-ONDA (VALIDAÇÃO + TESTES,
          ASSÍNCRONAS):</strong> ao fim da onda N, DUAS sub-ondas em
          BACKGROUND (run_in_background=true), processadas na próxima onda
          (passo 3.5) ou no COMMIT-FINAL. O BLOCO B depende de
          <cmd>. '&lt;ENV_FILE&gt;'; echo "TEST_MODE=$DO_TEST_MODE"</cmd>:
          full → A + B(full); none → SÓ A; e2e → A + B(e2e). O BLOCO A roda
          nos três modos. MAPA ANTI-COLISÃO: os arquivos de teste da subwave
          da onda N entram em {{FORBIDDEN_FILES}} dos agentes da onda N+1 (em
          e2e, os paths de spec do MAPA DE JORNADAS).
          <substeps>
            <substep><strong>BLOCO A — VALIDATION SUBWAVE:</strong>
              <cmd>. '&lt;ENV_FILE&gt;' &amp;&amp; "$DO_WT" new validation val-ondaN-gate</cmd>
              (o gate assíncrono NUNCA roda em $BASE_DIR: colidiria com os
              merges da onda seguinte). Dispare (1) o AGENTE VALIDADOR
              (somente-leitura) na val-ondaN-gate pelo TEMPLATE DE AGENTE DE
              VALIDAÇÃO com TODOS os placeholders ({{GATE_*}}, {{TEST_MODE}},
              {{E2E_PORT}}): build + lint + typecheck + suíte existente no
              estado integrado, instalando deps congeladas NA PRÓPRIA worktree
              (R9); em e2e roda TAMBÉM o GATE_E2E com a porta do contexto
              DELE; e (2) o REVISOR ADVERSARIAL DO DIFF INTEGRADO (sem
              worktree, contexto zero) com
              <cmd>. '&lt;ENV_FILE&gt;'; pre=$(awk -F'\t' -v n='&lt;nome-da-1a-filha-da-onda&gt;' '$3==n {print $7}' "$OWNED"); gwt diff "$pre..HEAD"</cmd>
              (pre = pre_merge_sha da 1ª filha integrada da onda) + prompt
              original + handoffs — missão: REFUTAR A INTEGRAÇÃO (contratos
              combinam? B usou a interface de A? dead code cruzado? golden
              masters?). Registre "Validation Subwave Onda N — PENDENTE"
              (worktree, agentes, escopo).</substep>
            <substep><strong>BLOCO B — TESTING SUBWAVE (full; e2e com as
              TROCAS abaixo):</strong>
              <substeps>
                <substep><strong>none:</strong> BLOCO B PULADO INTEIRO — NÃO
                  crie worktree nem agente de teste (o new recusa
                  kind=test/test-onda*; não contorne com outro kind). Registre
                  "Onda N: Testing Subwave DESLIGADA (no-test)" e NUNCA crie a
                  seção PENDENTE (o 3.5 e o COMMIT-FINAL ficam NO-OP para
                  testes). Teste pedido explicitamente no texto já é
                  sub-tarefa kind=feature do plano.</substep>
                <substep><strong>ESCOPO:</strong> TODOS os arquivos de produção
                  modificados na onda — handoffs +
                  <cmd>. '&lt;ENV_FILE&gt;' &amp;&amp; "$DO_WT" wave-files &lt;nome-da-1a-filha-da-onda&gt;</cmd>
                  (difere do SHA pré-merge registrado; nunca HEAD~N). Agrupe
                  por módulo; inclua stubs reais do COMMIT PREP; exclua docs,
                  templates HTML e config declarativa ("isentos de teste").
                  Onda só de docs/configs → NO-OP: registre "Onda N: nada a
                  testar" e pule o B (a validação roda sempre que houve
                  código).</substep>
                <substep><strong>AGENTES:</strong> subconjuntos disjuntos de
                  arquivos (mapa de propriedade de teste), máx 3 worktrees por
                  onda (contam no teto DO_MAX_PARALLEL — reduza antes de
                  estourá-lo), nomes <code>test-ondaN-&lt;foco&gt;</code>:
                  <cmd>. '&lt;ENV_FILE&gt;' &amp;&amp; "$DO_WT" new test test-ondaN-&lt;foco&gt;</cmd>
                  Dispare cada um em background pelo TEMPLATE DE AGENTE DE
                  TESTE com TODOS os placeholders ({{TEST_MODE}} e, em e2e,
                  {{E2E_*}}), {{ORIGINAL_TASK_DESCRIPTION}} e
                  {{ACCEPTANCE_CRITERIA}} do plano (fonte primária — NÃO o
                  diff) e {{FALSIFIABLE_QUESTIONS}} (FASE 2 passo 7).
                  Registre "Testing Subwave Onda N — PENDENTE" (worktrees,
                  agentes, escopo) — metadado; o gatilho do 3.5 é o ledger.</substep>
                <substep><strong>TROCAS do modo e2e:</strong> ESCOPO =
                  jornadas que FECHARAM nesta onda (MAPA DE JORNADAS do plano),
                  não arquivos; nenhuma fecha, ou runner ainda "sem e2e"
                  (onda1-e2e-harness não integrou) → NO-OP: "Onda N: nenhuma
                  jornada fecha — e2e adiado"; runner impossível →
                  degradation <code>e2e-runner-unavailable</code>. WORKTREES
                  <code>test-ondaN-e2e-&lt;jornada&gt;</code> (máx 3; agrupe
                  jornadas afins). PORTA POR CONTEXTO (porta TCP é SINGLETON):
                  tabela <code>E2E_PORT</code> no TASK_PLAN.md com UMA porta
                  por contexto que roda o GATE_E2E (cada test-ondaN-e2e-*, o
                  snapshot de cada merge de teste, a val-ondaN-gate e o gate
                  final), faixa alta (41000+), checada livre:
                  <cmd>lsof -nP -iTCP:&lt;p&gt; -sTCP:LISTEN || echo LIVRE</cmd>;
                  quem roda passa <code>CI=1 E2E_PORT=&lt;p&gt;</code> (CI=1
                  impede reusar servidor de OUTRA worktree); config com
                  "E2E_PORT fixa" ainda não parametrizado → SERIALIZE (1
                  contexto e2e por vez). AGENTE: template no MODO e2e com a
                  jornada, o path do spec e a porta DELE (as regras do modo —
                  só e2e, sem mock interno, cobertura por jornada, servidor só
                  pelo runner, artefatos fora do commit, rodar 2x, porta livre
                  ao terminar — vivem no template; o revisor de testes as
                  cobra). GATE_E2E roda na worktree do agente, no snapshot do
                  merge de teste (3.5), na validação e no gate final — nunca
                  em snapshot de feature. REGISTRE jornada → worktree → spec →
                  E2E_PORT; jornada que nunca fechar vai a "Jornadas sem
                  cobertura" no relatório.</substep>
              </substeps></substep>
          </substeps></step>
      </steps>
      <output>Onda concluída: squash commits em $BASE_BRANCH, gates verdes,
        cada filha fechada pelo script no gate verde dela (ou por close
        --discard com motivo), "ASSERT-CLEAN OK — a onda N+1 pode abrir",
        contenção provada, triagem registrada, handoff publicado, subwaves do
        modo de teste em vigor disparadas</output>
    </phase>
