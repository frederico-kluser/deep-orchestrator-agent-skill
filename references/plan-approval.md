<!-- MÓDULO v6.0.0 · origem: SKILL.md <rule R10> + <phase 2.5> + casos plan-* + example ex2 (split progressive disclosure)
     carga: SÓ com plan=on · conteúdo byte-a-byte com a origem (CONTRATO.md §5)
     1 HOP: não referenciar outros módulos -->

<!-- TEMPLATE OFICIAL do $PLAN_DOC (fim do órfão): prompts/plan-approval-prompts.md -->

    <rule id="R10" severity="FATAL">
      <title>PORTÃO DE APROVAÇÃO DO PLANO: só executa plano que o usuário aprovou</title>
      <body>Quando o usuário PEDE UM PLANO, o plano deixa de ser um rascunho
        interno e vira o ENTREGÁVEL: ele precisa ser aprovado por ele, no
        Plannotator, ANTES de qualquer worktree existir.
        <strong>NÃO confunda com o "gate" do projeto</strong> — GATE_BUILD,
        GATE_TEST e GATE_LINT (FASE 1, passo 9) são build/teste/lint e NUNCA
        rodam na FASE 2.5. Este é o PORTÃO DE APROVAÇÃO, e ele não roda suíte
        nenhuma.
        <strong>Quando liga.</strong> $DO_PLAN_APPROVAL=1, resolvido UMA vez na
        FASE 0 (passos 1–2 — casa ÚNICA da precedência e dos gatilhos): token
        explícito <code>plan=on</code>/<code>plan=off</code> vence tudo; depois
        a variável de ambiente DO_PLAN_APPROVAL; depois os gatilhos de
        linguagem natural do $ARGUMENTS, em que pedido de autonomia VENCE
        pedido de plano. Só a decisão vinda dos gatilhos vira token repassado
        ao do-context.sh, que é quem valida. Na dúvida, DESLIGADO (default).
        <strong>Cada anotação gera um Plannotator NOVO.</strong> Feedback do
        usuário NÃO é tarefa de implementação e é PROIBIDO tratá-lo como
        código a escrever. Ele é uma correção do PLANO: você REGENERA o plano
        incorporando o feedback e abre uma sessão INTEIRAMENTE NOVA do
        Plannotator (processo novo, servidor novo, aba nova) com a revisão
        seguinte. A rodada anterior fica preservada no trail. Repete até
        APROVADO ou até o orçamento acabar.
        <strong>O TÍTULO do plano (primeiro <code>#</code>) é IMUTÁVEL</strong>
        entre as revisões — é a âncora com que o Plannotator reconhece o MESMO
        plano evoluindo. O que muda vai no corpo. O plan-approval.sh RECUSA a
        rodada se o título mudar.
        <strong>A decisão vem do exit code</strong> de
        <cmd>plan-approval.sh round</cmd> (0 aprovado · 10 anotado · 11
        fechado · 12 timeout · 13 falha da ferramenta · 14 orçamento), NUNCA da
        leitura do texto que o Plannotator imprime. Sem APROVADO, a FASE 3 não
        começa — e parar ali é legítimo por R3.
        <strong>Independe do agente que hospeda a skill.</strong> O portão é
        UMA chamada Bash; Claude Code, pi, jcode e opencode têm todos shell.
        NUNCA use hook de plan-mode, ExitPlanMode, AskUserQuestion ou plugin de
        um agente específico. O veto a AskUserQuestion vale para a skill
        INTEIRA: TODA pergunta ao usuário — protocolo PESQUISA-FALHOU, rodadas
        do-question (R2(f)) e PERGUNTA DE EVOLUÇÃO (R2(e)) — é TEXTO como
        última coisa da resposta, estado em $DO_STATE e fim de turno (AGUARDE,
        R2).</body>
    </rule>

    <phase id="2.5" name="APROVAR-O-PLANO">
      <objective>Quando o usuário PEDIU UM PLANO (R10), fazer com que ele
        aprove o plano no Plannotator ANTES de existir a primeira worktree —
        e, a cada anotação, REGERAR o plano num Plannotator NOVO. O portão é
        AQUI e SÓ aqui: nada foi construído, recusar não custa rollback; por
        isso é o ponto em que a interação é a entrega (R2(d)).</objective>
      <preamble>Toda chamada desta fase começa com
        <cmd>. '&lt;ENV_FILE&gt;'</cmd> — define $PLAN_APPROVAL_DIR, $PLAN_DOC,
        $DO_PLAN_APPROVAL_SH e os tetos. <strong>Nada aqui roda
        GATE_BUILD/GATE_TEST/GATE_LINT</strong> (gate de integração, FASE 1
        passo 9).</preamble>
      <steps>
        <step order="0"><strong>PORTÃO DESLIGADO? PULE A FASE INTEIRA.</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; [ "$DO_PLAN_APPROVAL" = 1 ] || echo SKIP</cmd>
          DO_PLAN_APPROVAL=0 → registre "PLAN_APPROVAL=0 — execução autônoma,
          sem portão" e vá DIRETO para a FASE 3: nenhum navegador, nenhuma
          pergunta.</step>
        <step order="1"><strong>JÁ APROVADO? NÃO REABRA.</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_PLAN_APPROVAL_SH" approved &amp;&amp; echo JA-APROVADO</cmd>
          (numa sessão seguinte, DO_REUSE, o $PLAN_DOC pode já estar aprovado).
          Exit 0 → registre a revisão aprovada e siga para a FASE 3 — reabrir
          queimaria uma revisão do orçamento.</step>
        <step order="2"><strong>PLANNOTATOR DISPONÍVEL (instalando se
          preciso):</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; "$SKILL_HOME/scripts/check-plannotator.sh" --install</cmd>
          Resolve o executável ($DO_PLANNOTATOR_BIN → PATH → ~/.local/bin),
          confere a versão e sonda com <code>annotate</code> sem argumento (só
          usage, sem navegador); ausente, instala com <code>--minimal</code>
          (só o binário em ~/.local/bin; não toca ~/.claude, ~/.codex,
          ~/.gemini, ~/.kiro nem ~/.config/opencode).
          <substeps>
            <substep>Exit 0 — disponível: passo 3.</substep>
            <substep>Exit 1 — instalável, mas a instalação falhou (rede,
              checksum): tente UMA vez mais; persistindo, trate como exit 2.</substep>
            <substep>Exit 2 — indisponível e não instalável: <strong>PARE</strong>
              (R2(d)): informe o caminho manual
              (<code>curl -fsSL https://plannotator.ai/install.sh | bash</code>),
              diga que <code>plan=off</code> executa sem o portão, e AGUARDE.
              NÃO execute o plano por conta própria.</substep>
          </substeps></step>
        <step order="3"><strong>ESCREVA O DOCUMENTO DE APROVAÇÃO em
          $PLAN_DOC</strong> (Bash echo/cat — R1(a); vive sob $DO_STATE). NÃO é
          o TASK_PLAN.md (caderno de bordo, ilegível para quem decide): é o
          plano do ponto de vista de QUEM APROVA.
          <substeps>
            <substep><strong>O TÍTULO (primeiro <code>#</code>) É IMUTÁVEL entre
              revisões</strong> e descreve a TAREFA, jamais a revisão (certo:
              <code># Plano: cache de sessão no serviço de auth</code>; errado:
              <code># Plano v2</code>). É a âncora do Plannotator; o
              plan-approval.sh RECUSA a rodada (exit 2) se mudar.</substep>
            <substep>Conteúdo: objetivo em 1-2 frases · abordagem · tabela onda
              → sub-tarefa → o que entrega → arquivos · o que NÃO está no
              escopo · riscos e premissas (NÃO VERIFICADA toda premissa externa
              sem pesquisa — busca vazia ou opção [3] do protocolo) · como se
              verifica que funcionou · a POLÍTICA DE TESTES conforme
              $DO_TEST_MODE (full = "testes escritos ao fim de cada onda"; none
              = "Testes: DESLIGADOS por no-test — nenhum teste novo; a suíte
              existente roda a cada integração"; e2e = "só testes end-to-end"
              + o mapa de jornadas) — quem aprova precisa VER que a flag pegou.
              Prosa curta, sem jargão interno (owned.tsv, BRANCH_NS, squash).</substep>
            <substep>Da revisão 2 em diante, abra o corpo com
              <code>## O que mudou nesta revisão</code>, item a item do
              feedback anterior.</substep>
          </substeps></step>
        <step order="4"><strong>UMA RODADA NO PLANNOTATOR:</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_PLAN_APPROVAL_SH" round "$PLAN_DOC"; echo "rc=$?"</cmd>
          O script fotografa o documento num arquivo imutável, abre uma sessão
          NOVA, BLOQUEIA até a decisão (ou timeout) e devolve a decisão no EXIT
          CODE. Avise que o navegador vai abrir e que
          <cmd>plannotator sessions --open 1</cmd> reabre a aba. As travas de
          rede (127.0.0.1; upload de paste desligado) são forçadas pelo script
          e é PROIBIDO afrouxá-las: o endpoint de aprovação NÃO tem
          autenticação. Ramifique SÓ pelo exit code:
          <substeps>
            <substep><strong>0 APROVADO</strong> → registre revisão, snapshot e
              feedback acumulado no TASK_PLAN.md; FASE 3.</substep>
            <substep><strong>10 ANOTADO</strong> → passo 5 (o caminho
              principal desta fase).</substep>
            <substep><strong>11 FECHADO</strong> e <strong>12 TIMEOUT</strong> →
              PARE: ausência de resposta NÃO é consentimento. Diga o que
              aconteceu, ofereça <code>plan=off</code> e AGUARDE (R2(d); saída
              legítima por R3).</substep>
            <substep><strong>13 FALHA DA FERRAMENTA</strong> → stderr em
              $PLAN_APPROVAL_DIR/rev-NNN.stderr; tente UMA vez mais;
              persistindo, trate como exit 2 do passo 2.</substep>
            <substep><strong>14 ORÇAMENTO ESGOTADO</strong> →
              $DO_PLAN_MAX_REVISIONS rodadas sem acordo: PARE e entregue o
              resumo das revisões (pedido × mudança). O usuário decide: subir
              o teto, <code>plan=off</code>, ou reformular a tarefa.</substep>
            <substep><strong>2 ERRO DE ENTRADA</strong> → quase sempre deriva de
              TÍTULO: restaure-o EXATAMENTE, mova o resto para o corpo e
              repita o passo 4 (não consome revisão).</substep>
          </substeps></step>
        <step order="5"><strong>ANOTADO → REGERE O PLANO (o coração da
          fase):</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_PLAN_APPROVAL_SH" feedback</cmd>
          <strong>PROIBIDO implementar o feedback como código</strong>, criar
          worktree por ele ou tratá-lo como sub-tarefa: é correção DO PLANO.
          <substeps>
            <substep>Leia o feedback inteiro: <code>## N. (line X) ...</code>
              com o trecho citado e o comentário após <code>&gt;</code>;
              rótulos <code>[👍 Looks good]</code>, <code>[🔍 Verify this]</code>,
              <code>[🚫 Out of scope]</code>; blocos <code>Remove this</code>;
              seções <code>Reference Images</code> / <code>Attached images</code>
              com CAMINHOS — leia as imagens com Read antes de responder.</substep>
            <substep>Trate CADA item. <code>🚫 Out of scope</code> = REMOVER a
              sub-tarefa (não reduzir). <code>Remove this</code> apaga o trecho
              citado. Item de que você discorda ainda aparece no plano novo,
              com a razão — silêncio lê-se como ignorado.
              <code>🔍 Verify this</code> = você assumiu algo: volte ao código
              (Read/Grep); se o código não responde, pesquise —
              <strong>EXCEÇÃO DECLARADA: o ÚNICO ponto em que o ORQUESTRADOR
              roda busca ele mesmo</strong> (fora a sonda <code>resume --probe</code>);
              aqui R=1, N inteiro:
              <cmd>. '&lt;ENV_FILE&gt;'; tavily.py "&lt;pergunta&gt;" --insights "&lt;a premissa&gt;" --sub-agents="${DO_TAVILY_SUB_AGENTS:-10}" &gt; "$DO_STATE/verify.out" 2&gt; "$DO_STATE/verify.err"; rc=$?; "$DO_TAVILY_GATE" classify "$rc" "$DO_STATE/verify.out" "$DO_STATE/verify.err"</cmd>
              Aja pela CLASSE (tabela da R7): <code>OK</code> → substitua a
              premissa por FATO com URL (lendo verify.out) ANTES de reescrever;
              <code>EMPTY</code> → premissa NÃO VERIFICADA, motivo "busca
              vazia", SEM pergunta; <code>BLOCKED_NOKEY</code> /
              <code>FAILED_QUOTA</code> / <code>FAILED_OTHER</code> (inclui
              binário ausente) → o usuário PEDIU a verificação, a pesquisa é
              EXIGIDA: protocolo PESQUISA-FALHOU (&lt;onda&gt; = 0; sub-tarefas
              = "[Verify this] &lt;premissa&gt;"), sem abrir outro Plannotator
              antes da resposta; NUNCA marque NÃO VERIFICADA por conta própria
              num 78/127/cota (só a opção [3] autoriza); com RESUME=OK refaça
              ESTA busca. <code>USAGE_2</code> → corrija o comando;
              <code>KILLED_143</code> → refaça com timeout maior.</substep>
            <substep>REFAÇA a decomposição da FASE 2 com o feedback como
              restrição de PRIMEIRA classe (ondas, mapa de propriedade,
              batismo, prompts). Sub-tarefa retirada → worktree batizada
              retirada. Preencha SEARCH_REQUIRED para cada sub-tarefa nova e,
              se nasceu alguma "sim", repita o PORTÃO PÓS-PLANO antes da
              próxima rodada.</substep>
            <substep>Reescreva $PLAN_FILE E $PLAN_DOC, TÍTULO idêntico, corpo
              aberto por <code>## O que mudou nesta revisão</code>.</substep>
            <substep>Volte ao passo 4: a rodada seguinte é um Plannotator
              INTEIRAMENTE NOVO, nunca um remendo na sessão anterior.</substep>
          </substeps></step>
        <step order="6"><strong>APROVADO — CONGELE O CONTRATO.</strong> O plano
          aprovado é RESTRIÇÃO, não sugestão:
          <substeps>
            <substep>Registre no TASK_PLAN.md a seção
              <code>Portão de aprovação — APROVADO na revisão N</code> com o
              caminho de cada snapshot e o feedback de cada rodada.</substep>
            <substep>Cole o feedback acumulado no bloco de contexto dos prompts
              de delegação (FASE 2 passo 7): intenção declarada do usuário
              tem prioridade sobre qualquer inferência sua.</substep>
            <substep>O REVISOR DE PLANO (FASE 3 passo 5) fica SUBORDINADO ao
              plano aprovado.</substep>
          </substeps></step>
      </steps>
      <output>Plano APROVADO na revisão N, trail completo em
        $PLAN_APPROVAL_DIR (snapshot imutável + feedback por rodada) e o
        feedback acumulado pronto para os prompts — ou uma parada limpa, sem
        nenhuma worktree criada, quando não houve aprovação</output>
    </phase>

    <case id="plannotator-unavailable">
      <when>PLAN_APPROVAL=1 e check-plannotator.sh sai 2 nas duas tentativas.</when>
      <action>PARE antes de qualquer worktree (R2(d)): informe o que falhou,
        o comando manual (curl -fsSL https://plannotator.ai/install.sh | bash)
        e que <code>plan=off</code> executa sem portão. AGUARDE; NUNCA execute
        o plano por conta própria.</action>
    </case>

    <case id="plan-not-approved">
      <when>Portão sem aprovação: fechado (11), timeout (12) ou orçamento (14).</when>
      <action>Encerre LIMPO (R3): nenhuma linha do projeto foi tocada.
        Entregue o relatório do portão (tabela de revisões) e o que destrava
        (subir DO_PLAN_MAX_REVISIONS, plan=off, reformular). NÃO adivinhe a
        aprovação nem execute "as partes pacíficas". Só com parada DEFINITIVA
        (usuário desistiu / relatório entregue), DEPOIS de copiar o trail,
        rode o DESCARTE O ESTADO (FASE 4 passo 8, o MESMO comando) — sem ele
        sobra <code>?? .deep-orchestrator/</code> com o plano e os comentários.
        NÃO faça teardown enquanto AGUARDA (11/12 são espera): destruiria o
        título travado, o trail e o documento.</action>
    </case>

    <case id="plan-title-drift">
      <when><cmd>plan-approval.sh round</cmd> sai 2: TÍTULO mudou.</when>
      <action>Erro SEU, não consome revisão: restaure o título EXATO
        (<cmd>plan-approval.sh title</cmd> imprime), mova o resto para
        <code>## O que mudou nesta revisão</code> e repita a rodada.</action>
    </case>

    <case id="plan-scope-expanded">
      <when>Portão ativo, REPLAN propõe FORA do escopo e o orçamento acabou.</when>
      <action>Siga com o escopo APROVADO; registre cada proposta como
        FORA-DO-ESCOPO-NÃO-APROVADA e leve ao relatório. Ondas integradas
        ficam; só o que estava por vir não acontece.</action>
    </case>

    <case id="plan-round-interrupted">
      <when>Rodada morreu no meio (Ctrl-C, suspensão, processo morto): há
        <code>rev-NNN.md</code> sem linha no <code>trail.tsv</code>.</when>
      <action>Rode a rodada de novo: o script resolve o número pelo MAIOR entre
        trail e disco — nada é sobrescrito. Antes, olhe
        <code>rev-NNN.stdout</code>: se a decisão do usuário está lá, não a
        peça de novo. Cada tentativa consome uma revisão.</action>
    </case>

    <example id="ex2" task="Fluxo com PORTÃO DE APROVAÇÃO DO PLANO (R10 / FASE 2.5)">
      <invocation>/deep-orchestrator-agent-skill faça um plano para migrar o módulo de
        pagamentos para a nova API e me deixe aprovar antes</invocation>
      <gate-resolution>FASE 0, passo 2: sem prefixo plan= na zona de prefixo;
        sem gatilho negativo; gatilhos positivos "faça um plano" e "me deixe
        aprovar antes" → token <code>plan=on</code> no
        <code>--flags</code> do passo 3 →
        <strong>DO_PLAN_APPROVAL=1</strong>. Registrado no TASK_PLAN.md com o
        motivo.</gate-resolution>
      <rounds>
        <round n="1" decision="annotated">
          $PLAN_DOC com o título <code># Plano: migração do módulo de pagamentos
          para a nova API</code> e 3 ondas. O usuário anota duas coisas:
          "[🚫 Out of scope] refatorar o logger" e "[🔍 Verify this] a API
          antiga ainda é chamada pelo job noturno?".
          Reação: a sub-tarefa do logger é REMOVIDA do plano (e a worktree
          onda2-logger, batizada para ela, deixa de existir no plano); a
          pergunta vira investigação real (Grep no repositório + <code>tavily.py</code> na
          documentação da API) e a resposta entra como fato, não como premissa.
          O plano é REGERADO com o MESMO título e uma seção
          <code>## O que mudou nesta revisão</code>.
        </round>
        <round n="2" decision="annotated">
          Plannotator NOVO — processo novo, servidor novo, aba nova. O usuário
          pede para dividir a onda 2 em duas, por risco. O plano é REGERADO de
          novo: ondas, mapa de propriedade de arquivo e batismo das worktrees
          todos refeitos a partir do plano novo.
        </round>
        <round n="3" decision="approved">
          Aprovado. O feedback das 3 rodadas é colado no bloco de contexto dos
          prompts de delegação e o REVISOR DE PLANO da FASE 3 passa a ser
          subordinado a este escopo. A FASE 3 começa — daqui em diante, zero
          interação, salvo REPLAN fora do escopo aprovado e o protocolo
          PESQUISA-FALHOU (que é incondicional).
        </round>
      </rounds>
      <trail>$PLAN_APPROVAL_DIR/ guarda rev-001.md, rev-002.md, rev-003.md
        (snapshots imutáveis, um por rodada), rev-001.feedback.md,
        rev-002.feedback.md e o trail.tsv com a decisão de cada rodada. Tudo
        vive sob $DO_STATE e some com ele no fim — por isso a tabela de
        revisões é copiada para o relatório final ANTES da limpeza.</trail>
      <counter-example>A MESMA tarefa invocada como
        <code>/deep-orchestrator-agent-skill migre o módulo de pagamentos para a nova API,
        não me pergunte nada</code> resolve DO_PLAN_APPROVAL=0 pelo gatilho
        negativo: nenhum navegador abre, a FASE 2.5 é pulada inteira e o
        comportamento é o autônomo de sempre. E
        <code>/deep-orchestrator-agent-skill plan=off faça um plano e execute</code>
        também dá 0 — o prefixo explícito vence o gatilho positivo.</counter-example>
    </example>
