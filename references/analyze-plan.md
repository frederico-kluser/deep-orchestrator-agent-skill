<!-- MÓDULO v5.0.0 · origem: SKILL.md <phase 1 ANALYZE> + <phase 2 PLAN> (split progressive disclosure)
     carga: após a FASE 0 · conteúdo byte-a-byte com a origem (CONTRATO.md §5),
     salvo as correções D-H (modelo único mimo-v2.6-pro, sem tiering) -->

    <phase id="1" name="ANALYZE">
      <objective>Entender a tarefa e o contexto do repositório</objective>
      <steps>
        <step order="1">Leia o prompt do usuário ($ARGUMENTS). A FASE 0 já
          rodou — sourceie o ENV_FILE antes de qualquer comando.</step>
        <step order="2">Use <tool>project_report</tool> para a estrutura do
          repo (fallback: Glob + Read nos arquivos-chave). Escopo = $BASE_DIR —
          NUNCA suba para $MAIN_ROOT.</step>
        <step order="3">Identifique subsistemas, arquivos-chave e dependências.</step>
        <step order="4"><strong>PROJECT-ROUTER:</strong> existe DENTRO da
          raiz-de-mundo, em <path>$BASE_DIR/.claude/skills/project-router/SKILL.md</path>
          ou <path>$BASE_DIR/.agents/skills/project-router/SKILL.md</path>?
          (NÃO procure em $MAIN_ROOT nem em ~/.claude.) EXISTE → leia-o
          COMPLETAMENTE e o SKILL.md de CADA skill que ele referenciar — é o
          mapa de conhecimento com que você instrui os sub-agentes; anote
          "project-router ENCONTRADO — X skills, Y convenções". NÃO EXISTE →
          anote "Project-router ausente — sub-agentes prosseguirão sem." e
          siga (não bloqueia).</step>
        <step order="5">Classifique: greenfield (código NOVO) ou brownfield
          (modifica existente)? Brownfield → identifique os golden masters e
          testes de caracterização que NÃO podem quebrar.</step>
        <step order="6">NÃO redescubra a fronteira: o branch de integração é
          <strong>$BASE_BRANCH</strong> (HEAD da raiz-de-mundo) — PROIBIDO
          resolver "branch principal" por convenção (main/master) ou
          <cmd>git remote show</cmd>; as filhas nascem em
          <strong>$CHILD_ROOT</strong>. Apenas confirme e registre no
          TASK_PLAN.md.</step>
        <step order="7">Registre no TASK_PLAN.md o veredito do portão da FASE 0
          passo 6 (binário, SURF_GATE/SURF_CODE, estado do surf-ai).
          <cmd>printenv BRAVE_API_KEY</cmd> NÃO é o teste: a chave vive no
          keystore do surf (que você NUNCA lê — R7). Ausência de chave NÃO é
          "modo degradado" a registrar: seguir sem a pesquisa exigida é a opção
          [3] do protocolo PESQUISA-FALHOU, e só o USUÁRIO a escolhe.</step>
        <step order="8">RECONFIRME o portão antes de fechar a análise — e SÓ
          REGISTRE o veredito: <cmd>. '&lt;ENV_FILE&gt;'; "$DO_SURF_GATE"</cmd>
          78/127 → NÃO pare aqui: sem sub-tarefas não há como julgar se a
          pesquisa é exigida; quem decide é o PORTÃO PÓS-PLANO (FASE 2 passo
          9), com a coluna SEARCH_REQUIRED na mão.</step>
        <step order="8.5"><strong>MEMÓRIA DA SKILL E PREFS DO PROJETO (evitar
          repetir erros):</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_PREFS" load</cmd> e
          <cmd>. '&lt;ENV_FILE&gt;'; "$SKILL_HOME/scripts/evolve-skill.sh" search "&lt;tema-central&gt;"</cmd>
          (prefs do PROJETO — project-config.md e learnings.md —, dicas
          GLOBAIS e PENDENTES dos dois escopos; o search varre esses arquivos +
          prompts/ + SKILL.md). Tudo é MEMÓRIA consultiva, nunca política
          executável: use para informar o plano (anti-padrões, gotchas,
          preferências), verificando contra o código. Registre no TASK_PLAN.md
          se há propostas pendentes (o agente de evolução as re-superficia).
          Script falhou → registre e prossiga (NUNCA bloqueia).</step>
        <step order="9"><strong>REGISTRE O GATE UMA ÚNICA VEZ:</strong> detecte
          os comandos do projeto-alvo (package.json scripts / Makefile /
          pyproject.toml / Cargo.toml / go.mod...) e grave o trio EXATO no
          TASK_PLAN.md (GATE_BUILD, GATE_TEST, GATE_LINT) E no SCRIPT — é ele
          quem roda o gate nos snapshots e limpa a filha no verde (FASE 3
          passo 7):
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" gate-set build "&lt;GATE_BUILD&gt;"; "$DO_WT" gate-set test "&lt;GATE_TEST&gt;"; "$DO_WT" gate-set lint "&lt;GATE_LINT&gt;"; "$DO_WT" gate-set install "&lt;instalação congelada&gt;"</cmd>
          <code>install</code> = comando CONGELADO da R9 (<code>npm ci</code>,
          <code>uv sync --frozen</code>...) quando o projeto precisa de deps
          para buildar/testar — o snapshot nasce sem node_modules/.venv. Etapa
          ausente → registre "sem &lt;etapa&gt;" e grave string vazia (remove
          a etapa) — NUNCA invente comando. O comando é gravado CRU e roda por
          <code>bash -c</code> com cwd NO SNAPSHOT, HUSKY=0 e CI=1: sem
          <code>cd</code> nem caminho absoluto. Sem etapa nenhuma o
          <code>gate</code> sai 5. TODA invocação de gate daqui em diante
          (passos 3.5 e 7, validação, gate final) é este trio, com o cwd do
          contexto (snapshot int-&lt;nome&gt;, val-ondaN-gate ou $BASE_DIR).</step>
        <step order="9.5"><strong>SÓ COM $DO_TEST_MODE=e2e (only-e2e) —
          DETECTE O RUNNER E2E:</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; [ "$DO_TEST_MODE" = e2e ] || echo SKIP</cmd>
          (SKIP → pule). Procure playwright.config.*, cypress.config.*, script
          <code>test:e2e</code>/<code>e2e</code>, diretórios tests/e2e, e2e/,
          cypress/, marker <code>e2e</code> do pytest, supertest/httpx contra o
          servidor de pé, bats para CLI. Registre <code>E2E_RUNNER</code>,
          <code>E2E_DIR</code> e <code>GATE_E2E</code> — o comando que roda SÓ
          a suíte e2e e lê a porta do ambiente (<code>$E2E_PORT</code>; quem
          roda passa <code>CI=1 E2E_PORT=&lt;p&gt;</code>, uma porta por
          contexto — FASE 3 passo 10) — e grave-o:
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" gate-set e2e "&lt;GATE_E2E&gt;"</cmd>
          Sem runner → registre "sem e2e" e NÃO invente: a FASE 2 (passo 4.5)
          cria <code>onda1-e2e-harness</code> e o <code>gate-set e2e</code>
          acontece quando ela integrar. Config com PORTA FIXA → registre
          "E2E_PORT fixa": a parametrização entra no COMMIT PREP da onda 1
          (porta TCP é SINGLETON, FASE 2 passo 6). GATE_E2E NÃO entra no trio:
          roda na worktree do agente e2e, no snapshot do merge de TESTE (o
          <code>gate</code> liga o e2e sozinho para kind=test), na validação e
          no gate final — nunca em snapshot de feature.</step>
        <step order="10"><strong>RODADA DE DÚVIDAS — SÓ COM $DO_QUESTION=1
          (do-question; R2(f)):</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; [ "$DO_QUESTION" = 1 ] || echo SKIP</cmd>
          SKIP → não pergunte NADA: infira, documente cada premissa no
          TASK_PLAN.md e siga (R2). Com a flag (que VENCE gatilho de autonomia
          no texto), esta é a ÚNICA rodada antes do plano:
          <substeps>
            <substep>1. Junte TODAS as dúvidas REAIS (mudam escopo, contrato ou
              decisão difícil de reverter); dúvida trivial continua inferida
              (pergunta tem custo). Nenhuma → registre "RODADA DE DÚVIDAS:
              nenhuma" e siga SEM perguntar.</substep>
            <substep>2. UM bloco numerado, cada dúvida com opções a/b/c e UM
              DEFAULT recomendado (o que você inferiria sem a flag):
              <question-format><![CDATA[
===== DÚVIDAS ANTES DO PLANO (do-question) =====
Responda "1:a 2:c" — ou "segue" para aceitar TODOS os defaults. Dúvida sem resposta fica com o default.
1. <a dúvida em uma frase — e o que muda conforme a resposta>
   a) <opção>   b) <opção>   c) <opção>
   DEFAULT: <letra> — <por quê>
2. ...
]]></question-format></substep>
            <substep>3. GRAVE o estado ANTES de perguntar, via Bash (R1(a)), em
              <path>$DO_STATE/question/pendente.md</path>
              (<cmd>. '&lt;ENV_FILE&gt;'; mkdir -p "$DO_STATE/question"</cmd>):
              "PONTO DE RETOMADA: FASE 1 passo 10 → FASE 2", a data e o bloco
              LITERAL.</substep>
            <substep>4. Cole o bloco como ÚLTIMA coisa da resposta e AGUARDE
              (R2; AskUserQuestion vetado — R10). A retomada é o passo 0 da
              FASE 0, que registra as respostas em "Perguntas ao usuário" do
              TASK_PLAN.md (vão ao relatório final).</substep>
          </substeps>
          A pergunta do protocolo PESQUISA-FALHOU NÃO passa por aqui. Sub-agentes
          NUNCA perguntam ao usuário: com a flag devolvem a seção
          <code>## Dúvidas para o usuário</code> no handoff e VOCÊ decide se
          ela entra na rodada de fim de onda (FASE 3).</step>
      </steps>
      <output>Compreensão completa do escopo, subsistemas afetados e o que NÃO
        pode quebrar</output>
    </phase>

    <phase id="2" name="PLAN">
      <objective>Criar o plano de decomposição em ondas</objective>
      <steps>
        <step order="1">Decomponha a tarefa em sub-tarefas ATÔMICAS.</step>
        <step order="2">Identifique o GRAFO de dependências: cada sub-tarefa
          declara explicitamente do que depende.</step>
        <step order="3">Organize em ONDAS topológicas: onda K depende só de
          ondas &lt; K; sub-tarefas da mesma onda são INDEPENDENTES e rodam em
          PARALELO. O número de ondas NÃO é fixo — o REVISOR DE PLANO recalcula
          após cada onda (FASE 3 passo 5).
          <substeps>
            <substep><strong>ORÇAMENTO DE PARALELISMO ($DO_MAX_PARALLEL,
              default 50):</strong> in-flight TOTAL — features da onda +
              worktrees de teste/validação das subwaves da onda anterior (com
              $DO_TEST_MODE=none não há worktrees de teste: conte só a
              validação) + revisores + REVISOR DE PLANO — ≤ DO_MAX_PARALLEL.
              Ondas maiores viram BATCHES sequenciais dentro da mesma onda,
              cada batch com a sua barreira (passo 4) e o mesmo passo 7.</substep>
            <substep><strong>SEARCH_REQUIRED=sim|nao — COLUNA OBRIGATÓRIA do
              plano, por sub-tarefa, com o motivo:</strong> é a ÚNICA definição
              de "exige pesquisa" — o portão (R7), o PORTÃO PÓS-PLANO (passo 9)
              e o protocolo PESQUISA-FALHOU decidem por ELA, nunca por juízo
              feito na hora. É <code>sim</code> quando a sub-tarefa depende de
              API, lib, serviço ou versão EXTERNA cujo contrato não está no
              repo; ou diz "mais recente", "atual", "docs", "pesquise",
              "compare" ou "escolha"; ou escolhe/adiciona dependência; ou é
              migração de versão. NA DÚVIDA, <code>sim</code> (fail-closed).
              Agentes de TESTE, VALIDAÇÃO e REVISORES são sempre
              <code>nao</code> (suas fontes são o contrato e o diff). PROIBIDO
              rebaixar para <code>nao</code> depois de um portão != 0 (R7).
              Todo REPLAN preenche a coluna para cada sub-tarefa nova.</substep>
            <substep><strong>ORÇAMENTO DE PESQUISA — os dois orçamentos SOMAM,
              nunca multiplicam:</strong> N = $DO_SURF_SUB_AGENTS (default 10,
              1..20; leia do ENV_FILE) e R = contagem de sub-tarefas DESTA onda
              com SEARCH_REQUIRED=sim. R=0 → NÃO calcule floor(N/R): ninguém
              pesquisa na onda. Sub-tarefa SEARCH_REQUIRED=nao recebe
              {{SURF_SUB_AGENTS}} = "0 — não pesquise" e fica FORA de R. Com
              R ≥ 1, cada pesquisadora recebe
              <code>--sub-agents=max(1, floor(N / R))</code>, colado LITERAL em
              {{SURF_SUB_AGENTS}} — a soma da onda fica ≤ N (multiplicar daria
              DO_MAX_PARALLEL × 10 buscas contra um plano Brave que serve 1
              por segundo). Ao planejar, limite <code>R ≤ N</code>. Registre N,
              R e o valor colado, por onda, no TASK_PLAN.md. O teto REAL é o
              plano Brave: se o surf avisar "--sub-agents X exceeds what your
              Brave plan can serve at once", BAIXE N — nunca aumente
              --sub-agents.</substep>
            <substep><strong>ESCALA DE FAN-OUT:</strong> ≤2 sub-tarefas
              independentes e pequenas → SEM fan-out extra (um sub-agente as
              absorve); crie sub-agente só quando o isolamento se justificar;
              registre a justificativa no TASK_PLAN.md.</substep>
          </substeps></step>
        <step order="4">Para cada onda, declare o MAPA DE PROPRIEDADE DE ARQUIVO
          (quais arquivos cada sub-agente modifica). Dois sub-agentes no MESMO
          arquivo → sequencie-os em ondas diferentes. <strong>Manifesto de
          dependências + lockfile são recurso SINGLETON:</strong> no máximo 1
          agente por onda adiciona dependências; os demais registram "deps
          pendentes: &lt;pacote@versão&gt;" no handoff e a adição acontece no
          COMMIT PREP da onda seguinte.</step>
        <step order="4.5"><strong>PLANEJE OS TESTES CONFORME $DO_TEST_MODE</strong>
          (<cmd>. '&lt;ENV_FILE&gt;'; echo "TEST_MODE=$DO_TEST_MODE"</cmd>,
          nunca da memória). Registre no plano "POLÍTICA DE TESTES: &lt;modo&gt;"
          e o texto de {{TEST_POLICY}}, que TODO agente que escreve código
          (feature, fix, fix-final, prep) recebe no prompt:
          <substeps>
            <substep><strong>full (default):</strong> Testing + Validation
              Subwaves ao fim de cada onda (FASE 3 passo 10). {{TEST_POLICY}} =
              "Se sua tarefa modifica comportamento existente, rode os testes
              ANTES e DEPOIS. Se adiciona comportamento novo, escreva testes."</substep>
            <substep><strong>none (no-test) — NÃO CRIA testes:</strong> nenhuma
              sub-tarefa cujo entregável seja teste; Testing Subwave DESLIGADA
              (o <code>new</code> recusa kind=test e nome <code>test-onda*</code>);
              o gate (com GATE_TEST na suíte EXISTENTE) e a VALIDATION
              CONTINUAM. {{TEST_POLICY}} = "NÃO crie arquivo nem caso de teste
              novo; rode a suíte existente ANTES e DEPOIS; PERMITIDO ajustar
              teste EXISTENTE quebrado por mudança INTENCIONAL de contrato
              (registre no handoff). Esta política VENCE
              ecc-prompts/ecc-skills/project-router." ÚNICA exceção: teste
              pedido EXPLICITAMENTE no TEXTO DA TAREFA é entregável de feature
              (sub-tarefa kind=feature comum, com {{TEST_POLICY}} PRÓPRIO que
              PERMITE esse entregável; registre em "Decisões tomadas
              autonomamente") — nunca infira a exceção de "robusto" ou "com
              qualidade". Registre "Estratégia de teste: DESLIGADA (no-test) —
              o gate roda a suíte existente".</substep>
            <substep><strong>e2e (only-e2e) — SÓ testes end-to-end, por
              JORNADA</strong> (definição de e2e, proibições, portas e
              artefatos: template do agente de teste, MODO e2e). Monte o
              <strong>MAPA DE JORNADAS</strong> a partir dos critérios de
              aceitação: <code>J1..Jn → onda em que a jornada FECHA → path do
              spec</code> (dono do spec = o agente e2e da Testing Subwave
              daquela onda; os paths entram em {{FORBIDDEN_FILES}} das
              features). Cobertura é de JORNADAS (≥1 caminho feliz + 1 erro
              observável por jornada), nunca % de linha. Todo REPLAN recalcula
              o mapa. Se a FASE 1 (passo 9.5) registrou "sem e2e", crie na
              onda 1 <code>onda1-e2e-harness</code>: kind=feature, dona
              SINGLETON de manifesto + lockfile (passo 4), entrega o runner
              como devDependency LOCAL (R9), o config lendo <code>$E2E_PORT</code>,
              os artefatos do runner no .gitignore e UM spec de fumaça — com
              {{TEST_POLICY}} PRÓPRIO que permite esse spec; ao integrá-la,
              <cmd>"$DO_WT" gate-set e2e "&lt;GATE_E2E&gt;"</cmd>. Runner
              impossível de instalar → degradation
              <code>e2e-runner-unavailable</code>. {{TEST_POLICY}} das demais
              features = "NÃO crie testes unit/integration; e2e é da subwave;
              rode a suíte existente ANTES e DEPOIS. Esta política VENCE
              ecc-prompts/ecc-skills/project-router."</substep>
          </substeps></step>
        <step order="5"><strong>BATISMO:</strong> para CADA sub-tarefa, defina
          AGORA o nome da worktree seguindo R6 (ex.: onda1-cache-service —
          descreve O QUE entrega, não quem executa). Derive o branch
          ($BRANCH_NS/&lt;nome&gt;) e o path ($CHILD_ROOT/&lt;nome&gt;) e
          registre a tripla no plano — o registro canônico em owned.tsv nasce
          no <cmd>do-wt.sh new</cmd>.</step>
        <step order="6">Onda com recursos SINGLETON (arquivo de solução, config
          raiz, porta TCP, banco compartilhado, manifesto + lockfile) → COMMIT
          PREP antes de criar as worktrees: stubs vazios, contratos congelados,
          faixas de ID disjuntas. Deps pendentes dos handoffs da onda anterior
          são adicionadas AQUI, nunca por mais de um agente.</step>
        <step order="7">Para CADA sub-tarefa, escreva o prompt de delegação
          pelo TEMPLATE DE PROMPT (WORKTREE_PATH e BRANCH_NAME preenchidos;
          {{HANDOFF}} fica PENDENTE até o disparo, FASE 3).
          <strong>PERGUNTAS FALSIFICÁVEIS ({{FALSIFIABLE_QUESTIONS}}):</strong>
          3-5 por sub-tarefa, a partir do contrato (passos 4-5); as MESMAS
          alimentam a revisão adversarial (FASE 3 passo 6) E os testes (passo
          10) — registre-as no plano. Com $DO_TEST_MODE=none alimentam SÓ a
          revisão: acrescente "algum teste existente foi enfraquecido ou
          removido sem mudança de contrato correspondente?". Preencha também
          {{TEST_POLICY}} (passo 4.5) e {{SURF_SUB_AGENTS}} (passo 3).</step>
        <step order="8">Publique o plano em <path>$PLAN_FILE</path> (Bash:
          echo/cat) com a tabela sub-tarefa → worktree → branch → arquivos →
          SEARCH_REQUIRED (sim|nao + motivo), "POLÍTICA DE TESTES" (em e2e,
          também o MAPA DE JORNADAS), N/R por onda e o bloco de contexto da
          FASE 0. NUNCA use <code>$CLAUDE_PROJECT_DIR</code> (vazia fora de
          hooks: <cmd>rm /TASK_PLAN.md</cmd>). O único path é $PLAN_FILE, sob
          .deep-orchestrator/ — protegido pela exclusão EXPLÍCITA por pathspec
          no gstatus/stage-delta, não por gitignore.</step>
        <step order="9"><strong>PORTÃO PÓS-PLANO — o ÚNICO ponto de decisão da
          parada por pesquisa antes da FASE 2.5/3</strong> (FASE 0 passo 6 e
          FASE 1 passo 8 só REGISTRARAM): agora as sub-tarefas existem e a
          coluna SEARCH_REQUIRED está publicada. Rerode
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_SURF_GATE"</cmd> e decida pela tabela
          da R7 com &lt;onda&gt; = 0:
          <substeps>
            <substep>SURF_GATE=0 → registre e siga.</substep>
            <substep>78|127 E TODAS as sub-tarefas de TODAS as ondas têm
              SEARCH_REQUIRED=nao → registre "pesquisa indisponível
              (SURF_GATE=&lt;n&gt; SURF_CODE=&lt;código&gt;); nenhuma sub-tarefa
              a exige" e siga sem busca — ÚNICO caso em que a decisão é SUA
              (e é PROIBIDO rebaixar a coluna depois de ver o portão).</substep>
            <substep>78|127 E QUALQUER sub-tarefa SEARCH_REQUIRED=sim → execute
              o protocolo PESQUISA-FALHOU AGORA (g1; nenhuma worktree existe:
              o passo A é no-op e [4] devolve o repositório como estava).
              INCONDICIONAL. Com SURF_CODE=BraveKeyCooling vale antes a regra
              &lt;cooling&gt; (rerode o portão ao fim deste passo, ao fim da
              FASE 2.5 e no passo 0 da onda 1, sem sleep; persistiu na 3ª →
              protocolo).</substep>
            <substep>RETOMADA (passo E do protocolo): [1]/[2] com RESUME=OK →
              FASE 2.5/3; [3] → marque NÃO VERIFICADA cada premissa externa do
              plano (e do $PLAN_DOC) e {{SURF_STATUS}} = "NÃO PESQUISE — usuário
              autorizou seguir sem busca" nos prompts; [4] → purge (nada a
              fechar) e relatório do que foi planejado.</substep>
          </substeps>
          Daqui em diante quem reroda o portão é o passo 0 de CADA onda.</step>
      </steps>
      <output>Plano com N sub-tarefas, M ondas, mapa de propriedade de arquivo,
        coluna SEARCH_REQUIRED, política de testes (em e2e, o MAPA DE
        JORNADAS), nomes de worktree, prompts prontos e o PORTÃO PÓS-PLANO
        decidido — plano inicial, recalculado após cada onda pelo REVISOR DE
        PLANO</output>
    </phase>
