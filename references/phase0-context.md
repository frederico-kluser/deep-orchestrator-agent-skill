<!-- MÓDULO v5.0.0 · origem: SKILL.md <phase 0 DELIMITAR-O-MUNDO> (split progressive disclosure)
     carga: SEMPRE, primeiro passo · conteúdo byte-a-byte com a origem (CONTRATO.md §5),
     salvo as correções D-H (modelo único mimo-v2.6-pro, sem tiering) -->

    <phase id="0" name="DELIMITAR-O-MUNDO">
      <objective>Descobrir a fronteira ANTES de qualquer leitura, plano ou
        comando git — SEMPRE o primeiro passo. Dentro de uma worktree vinculada
        o repositório principal continua acessível (mesmo .git, mesmos refs):
        sem esta fase "branch principal" vira main/master e o trabalho
        aterrissa no projeto principal.</objective>
      <steps>
        <step order="0"><strong>ESTADOS PENDENTES (continuação do turno
          anterior):</strong> toda pergunta desta skill vive no DISCO (AGUARDE,
          R2): <code>search-pause.md</code> (protocolo PESQUISA-FALHOU),
          <code>question/pendente.md</code> (do-question) e
          <code>evolution/pendente.md</code> (evolução). $BASE_DIR ainda não
          existe: procure no checkout atual e na pasta irmã do wt-root:
          <cmd>bash -c 'T=$(git rev-parse --show-toplevel 2&gt;/dev/null || pwd); for r in "$T"/.deep-orchestrator/run-* "$T".worktrees/*/.deep-orchestrator/run-*; do for f in search-pause.md question/pendente.md evolution/pendente.md; do [ -f "$r/$f" ] &amp;&amp; echo "PENDENTE=$r/$f ENV=$r/env"; done; done; echo FIM-PENDENTES'</cmd>
          Nenhuma linha <code>PENDENTE=</code> → passo 1. Havendo,
          <code>ENV=</code> é o ENV_FILE DAQUELE run — comece com
          <cmd>. '&lt;ENV&gt;'</cmd> toda chamada Bash. Ordem:
          <substeps>
            <substep>1. <code>search-pause.md</code> → RETOMADA do protocolo:
              execute o passo E dele com a mensagem atual (não é resposta →
              reimprima UMA vez a pergunta gravada e AGUARDE). NÃO rode os
              passos 1–6 de novo: re-ancore com
              <cmd>. '&lt;ENV&gt;'; "$DO_WT" checklist; "$DO_WT" status</cmd> e
              retome do ponto "PAUSA-PESQUISA" do TASK_PLAN.md.</substep>
            <substep>2. <code>question/pendente.md</code> → a mensagem responde
              a rodada do-question (R2(f)): "1:a 2:c" por número; "segue" =
              TODOS os defaults; sem resposta = default. Registre em
              "Perguntas ao usuário" do TASK_PLAN.md, apague o pendente
              (<cmd>. '&lt;ENV&gt;'; rm -f "$DO_STATE/question/pendente.md"</cmd>)
              e retome do PONTO DE RETOMADA gravado (sem repetir 1–6). Não
              responde → reimprima UMA vez e AGUARDE. Mandou abandonar →
              <cmd>. '&lt;ENV&gt;'; "$DO_WT" purge</cmd> (relate; rc 3 = filha
              NUNCA INTEGRADA) e DESCARTE O ESTADO (FASE 4 passo 8) antes da
              tarefa nova.</substep>
            <substep>3. <code>evolution/pendente.md</code> → (a) a mensagem
              RESPONDE ("1:b2", "nada", "pular", "config: ...") →
              <cmd>. '&lt;ENV&gt;'; "$DO_SURVEY" answer "&lt;mensagem&gt;" &amp;&amp; "$DO_SURVEY" apply</cmd>,
              reporte o resultado, rode o DESCARTE O ESTADO daquele run e
              ENCERRE o turno (não há tarefa nova); (b) NÃO responde →
              <cmd>. '&lt;ENV&gt;'; "$DO_SURVEY" dismiss</cmd> (tudo para
              pending/), DESCARTE O ESTADO e prossiga pelo passo 1; (c) NUNCA
              repita a pergunta de evolução.</substep>
          </substeps>
          <strong>NUNCA <code>rm -rf</code> um <code>run-*</code> com linha
          VIVA no owned.tsv</strong> (coluna 9 != REMOVED): é a ÚNICA alça de
          limpeza daquelas worktrees (R8(d)). Run vivo sai pelo purge DELE:
          <cmd>( . '&lt;env daquele run&gt;'; "$DO_WT" purge )</cmd> — o passo
          5 lista os que existirem (DO_ORPHAN_RUNS); o DESCARTE O ESTADO apaga
          SÓ o run que sourceou, depois do purge dele.</step>
        <step order="1"><strong>PARSE DE PREFIXOS — ZONA DE PREFIXO + TABELA
          ÚNICA DE FLAGS:</strong> a ZONA são os tokens INICIAIS de $ARGUMENTS
          que casam <code>^[a-z][a-z0-9-]*=\S+$</code> (chave=valor) ou
          <code>^(no|only|do)-[a-z0-9-]+$</code> (booleana), até o PRIMEIRO
          token que não case ou um <code>--</code> literal (escape para tarefa
          que começa com "no-reply ..."; o <code>--</code> é descartado). O
          resto é o TEXTO DA TAREFA.
          <substeps>
            <substep>(i) Repasse TODOS os tokens da zona, na ordem, em
              <code>--flags='...'</code> (passo 3) SEM julgá-los: o
              do-context.sh é o ÚNICO validador — typo sai exit 2 com
              sugestão, em vez de virar texto e inverter o pedido.</substep>
            <substep>(ii) FRONTEIRA: o PRIMEIRO token que encerrou a zona (se
              não for <code>--</code>) vai em <code>--boundary='&lt;token&gt;'</code>
              sempre que casar <code>^-{0,2}[A-Za-z0-9][A-Za-z0-9_=-]*$</code>
              (sem aspas, $ ou espaço — sem risco de injeção): o SCRIPT decide
              se é flag mal escrita (<code>e2e-only</code>,
              <code>--no-test</code>, <code>notest</code> → exit 2 com a forma
              certa) ou texto da tarefa (ignorado). Você NÃO julga.</substep>
            <substep>(iii) Token igual no MEIO da frase é texto ("adicione uma
              flag no-test ao CLI" NÃO liga no-test). NUNCA infira flag por
              linguagem natural ("módulo sem testes", "pode me perguntar"); a
              ÚNICA decisão por linguagem natural é o portão do plano (passo 2).</substep>
            <substep>(iv) <code>wt=on</code> é o ÚNICO token que você
              reescreve: <code>wt=&lt;slug&gt;</code> (kebab-case das primeiras
              palavras significativas da tarefa) — o script recusa
              <code>wt=on</code> cru (exit 2).</substep>
            <substep>(v) NÃO existe "exportar antes da FASE 0": o shell não
              persiste entre chamadas; a flag só existe no argv do comando do
              passo 3. Env DO_* que o USUÁRIO definiu vale como fallback (flag
              vence env) — você não a repassa.</substep>
          </substeps>
          TABELA — token → variável no ENV_FILE → default → efeito:
          <substeps>
            <substep><code>plan=on|off</code> → DO_PLAN_APPROVAL=1|0 →
              decidido no passo 2 → FASE 2.5 (R10).</substep>
            <substep><code>max-parallel=N</code> → DO_MAX_PARALLEL → 50 → teto
              de in-flight por onda (FASE 2 passo 3). Inteiro positivo.
              <code>no-subagent-limit</code> → DO_MAX_PARALLEL=0 = SEM teto
              (contradiz max-parallel=N → exit 2).</substep>
            <substep>LIMITES (todos configuráveis por flag — v5.0.0):
              <code>plan-revisions=N</code> → DO_PLAN_MAX_REVISIONS (5);
              <code>plan-timeout=S</code> → DO_PLAN_TIMEOUT (3600 s);
              <code>retries=N</code> → DO_DELEGATE_RETRIES (3; 0 = sem
              re-delegação); <code>fix-retries=N</code> → DO_FIX_RETRIES (2;
              0 = sem retry de fix).</substep>
            <substep><code>surf-sub-agents=N</code> → DO_SURF_SUB_AGENTS → 10
              (1..20) → teto GLOBAL de buscas simultâneas, DIVIDIDO entre as
              sub-tarefas que pesquisam (FASE 2 passo 3) — nunca multiplicado
              por DO_MAX_PARALLEL.</substep>
            <substep><code>wt=&lt;nome&gt;</code> → DO_WT_ROOT=1 + DO_WT_NAME →
              ausente = checkout atual → o script cria ou REENTRA a worktree
              irmã <code>&lt;pai&gt;/&lt;repo&gt;.worktrees/&lt;nome&gt;</code>
              (branch <code>do/wt/&lt;nome&gt;</code>, PERSISTENTE; deduplica
              -2, -3 só se o path existe e NÃO é essa worktree) e re-executa a
              FASE 0 lá dentro: TODO o trabalho acontece nela (MODE=contido) e
              o checkout principal fica INTOCADO. Fim (R8j): commit + push no
              branch do wt, NUNCA merge de volta; as filhas morrem no purge, o
              wt-root fica.</substep>
            <substep><code>no-stop</code> → DO_NO_STOP=1 → 0 → remove o teto
              de 10 ondas (mantém a válvula de 2 REPLANs estagnados).</substep>
            <substep><code>no-evolve</code> → DO_EVOLUTION_SURVEY=0 → 1 (a
              pergunta SEMPRE aparece, mesmo com gatilhos de autonomia) → pula
              INTEIRO o passo 7.5 da FASE 4 (agente de evolução não roda, nada
              é perguntado nem aplicado).</substep>
            <substep><code>no-test</code> → DO_TEST_MODE=none → full → NÃO CRIA
              testes: nenhuma sub-tarefa de teste, Testing Subwave desligada,
              <code>do-wt.sh new</code> recusa worktree de teste. O gate (com
              GATE_TEST na suíte EXISTENTE) e a VALIDATION continuam: não
              criar ≠ não rodar.</substep>
            <substep><code>only-e2e</code> → DO_TEST_MODE=e2e → full → Testing
              Subwaves criam APENAS testes end-to-end, por JORNADA (FASE 1
              passo 9.5; FASE 2 passo 4.5). Com <code>no-test</code> junto:
              exit 2.</substep>
            <substep><code>do-question</code> → DO_QUESTION=1 → 0 (infere e
              documenta) → você PODE perguntar (R2(f)): rodada da FASE 1 passo
              10 e no máximo UMA por onda. A pergunta do protocolo
              PESQUISA-FALHOU independe desta flag.</substep>
          </substeps></step>
        <step order="2"><strong>PORTÃO DE APROVAÇÃO DO PLANO (R10) — decida
          UMA vez</strong>; o resultado vira TOKEN <code>plan=on|off</code> no
          passo 3, nunca variável. Precedência:
          <substeps>
            <substep>1. <code>plan=on|off</code> na zona de prefixo: vence tudo
              (já está nos tokens; não acrescente outro).</substep>
            <substep>2. Env DO_PLAN_APPROVAL do usuário (confira SÓ sem token:
              <cmd>printenv DO_PLAN_APPROVAL</cmd>; vazio = não definida):
              respeite-a e NÃO emita token — no script a flag venceria a env.</substep>
            <substep>3. Gatilho NEGATIVO no texto ("não me pergunte nada",
              "autônomo", "toca o barco", "sem interrupção", "não pare para
              nada") → <code>plan=off</code>; vence os positivos mesmo com a
              palavra "plano".</substep>
            <substep>4. Gatilho POSITIVO ("faça/monte/quero um plano",
              "planeje", "quero aprovar", "aprovar antes", "revisar o plano",
              "me mostra o plano", "plannotator") → <code>plan=on</code>.</substep>
            <substep>5. Nada disso → <code>plan=off</code>: DEFAULT DESLIGADO
              (navegador que ninguém pediu é pior que nenhum).</substep>
          </substeps>
          Gatilho de autonomia desliga SÓ o portão do plano — não o protocolo
          PESQUISA-FALHOU (R2(a)/(b)) nem a flag <code>do-question</code>
          explícita (R2(f)). Registre a decisão E o motivo no TASK_PLAN.md
          assim que ele existir.</step>
        <step order="3"><strong>LOCALIZE A CASA DA SKILL E RODE A FASE 0 — em
          UM comando Bash</strong>, terminando em
          <code>"$DO_CTX" --flags='&lt;TOKENS&gt;'</code> (os scripts vivem
          FORA do projeto, $SKILL_HOME só existe depois do ENV_FILE e o shell
          não persiste entre chamadas):
          <cmd>DO_CTX=$(for d in "${CLAUDE_SKILL_DIR:-}" "${CLAUDE_SKILL_DIR:-}/../../.." "$HOME/.agents/skills/deep-orchestrator-agent-skill" "${DSH_HOME:-$HOME/.dsh}/skills/deep-orchestrator-agent-skill" "$HOME/.claude/skills/deep-orchestrator-agent-skill" "$PWD/.claude/skills/deep-orchestrator-agent-skill" "$HOME/.claude/skills/deep-orchestrator-agent-skill/../../.."; do [ -x "$d/scripts/do-context.sh" ] &amp;&amp; { echo "$d/scripts/do-context.sh"; break; }; done); [ -n "$DO_CTX" ] || { echo "PARE: do-context.sh nao encontrado"; exit 1; }; "$DO_CTX" --flags='&lt;TOKENS&gt;' --boundary='&lt;FRONTEIRA&gt;'</cmd>
          <code>&lt;TOKENS&gt;</code> = tokens da zona (wt=on já trocado) + o
          <code>plan=on|off</code> do passo 2, separados por espaço, num ÚNICO
          argv entre aspas simples; <code>&lt;FRONTEIRA&gt;</code> = o token
          do substep (ii) — ex.:
          <code>"$DO_CTX" --flags='max-parallel=8 no-test plan=off' --boundary='e2e-only'</code>.
          Sem flag: <code>--flags=''</code>; sem fronteira: omita
          <code>--boundary=</code>. Sempre a forma <code>--flags=</code> /
          <code>--boundary=</code> (um argv), nunca <code>--flags &lt;valor&gt;</code>.
          <strong>PROIBIDO passar flag por variável</strong>
          (<code>DO_NO_STOP=1 DO_CTX=$(...)</code> vira variável local: o
          script cai no default sem erro; <code>export</code> de chamada
          anterior evapora) — flag perdida INVERTE o pedido em silêncio.
          Candidatos: pasta exposta pelo harness, <code>~/.agents/skills</code>,
          <code>~/.dsh/skills</code>, o symlink
          <code>~/.claude/skills/deep-orchestrator-agent-skill</code> (raiz ou
          pasta interna) e <code>&lt;projeto&gt;/.claude/skills/</code>. Nada
          encontrado → PARE e informe (sem os scripts não há contenção).
          <strong>SAIU != 0 = ABORTOU:</strong> 2 = flag desconhecida, inválida
          ou contraditória (<code>no-test</code>+<code>only-e2e</code>,
          <code>--flags=</code> repetido), DO_* inválida ou SKILL_HOME não
          resolvido · 3 = não é repositório · 4 = HEAD destacado (exige
          <cmd>git switch -c &lt;branch&gt;</cmd>) · 5 = repo sem commits ·
          6 = índice sujo · 7 = path com caractere proibido · 8 = git
          inesperado · 9 = colisão de namespace. Repasse a mensagem
          LITERALMENTE e PARE (R2(c)). No exit 2 nada foi criado e a mensagem
          já traz a sugestão e o escape <code>--</code>: NUNCA "conserte" o
          token nem rode sem ele.</step>
        <step order="4"><strong>ANOTE O ENV_FILE</strong> (ÚLTIMA linha da
          saída) e comece com <cmd>. '&lt;ENV_FILE&gt;'</cmd> TODA chamada Bash
          da execução: sem o source, variáveis e helpers (gwt, gch, gstatus,
          gassert, $DO_WT) somem — "command not found" = faltou o source;
          NUNCA reexecute a FASE 0 para "recuperar". Recuperar o caminho:
          <cmd>ls -d "$PWD"/.deep-orchestrator/run-*/env | tail -1</cmd> (com
          wt=, troque "$PWD" pelo path da irmã, linha <code>DO_WT_ROOT:</code>
          do veredito).</step>
        <step order="5"><strong>LEIA O VEREDITO E CONFIRA O RESUMO.</strong>
          <substeps>
            <substep><code>MODE=contido</code> → dentro de worktree vinculada:
              BASE_DIR é a RAIZ-DE-MUNDO, BASE_BRANCH o único alvo, MAIN_ROOT
              ZONA PROIBIDA (R8). <code>MODE=normal</code> → árvore principal:
              BASE_BRANCH é o branch atual (nunca assuma main/master); R8 vale
              igual, MAIN_ROOT vazio.</substep>
            <substep><strong>CONFERÊNCIA OBRIGATÓRIA:</strong> as linhas
              <code>TEST_MODE</code>, <code>QUESTION</code>, NO_STOP,
              EVOLUTION, PLAN_APPROVAL, DO_MAX_PARALLEL, SURF_SUB_AGENTS e
              WT_ROOT do resumo batem com o que o USUÁRIO DIGITOU? Divergiu →
              o comando foi montado errado: rode o MESMO comando do passo 3
              corrigido, SEM <code>--new-run</code>, e apague o
              <code>run-*</code> vazio da tentativa (owned.tsv só com
              cabeçalho). Daqui em diante todo ponto lê $DO_TEST_MODE /
              $DO_QUESTION do ENV_FILE, nunca a memória.</substep>
            <substep><strong><code>DO_REUSE</code> na saída</strong> →
              ENV_FILE de execução EM ANDAMENTO (o script completa as chaves
              que faltem num env antigo; as flags dela estão na própria linha).
              Rode <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" checklist; "$DO_WT" status; head -20 "$PLAN_FILE"</cmd>
              e compare a tarefa. MESMA tarefa → RETOME pelo ledger: ACTIVE →
              re-dispare NA MESMA worktree; gate-pending/MERGED →
              <cmd>"$DO_WT" gate &lt;nome&gt;</cmd>; test-/val- ACTIVE → FASE 3
              passo 3.5. Tarefa DIFERENTE → purge DELA
              (<cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" purge</cmd>; rc 3 = filha
              NUNCA INTEGRADA: relate), DESCARTE O ESTADO dela e repita o passo
              3. <code>--new-run</code> SÓ quando a tarefa é diferente E há
              indício de OUTRA sessão viva (abaixo) — aí não purgue; nunca para
              "fugir" do DO_REUSE (a antiga ficaria órfã).</substep>
            <substep><strong><code>DO_ORPHAN_RUNS:</code> na saída</strong> →
              execução anterior com worktrees VIVAS que não será reusada; o
              bloco traz o comando EXATO por run
              (<code>( . '&lt;env antigo&gt;'; "$DO_WT" purge )</code>). Rode
              CADA um, uma chamada Bash por comando, ANTES de prosseguir, e
              anote o resultado no TASK_PLAN.md (rc 3 → o branch está em
              refs/do-archive/&lt;run&gt;/ e vai ao relatório final). ÚNICA
              exceção: indício de OUTRA sessão viva (owned.tsv ou TASK_PLAN.md
              daquele run modificado há menos de 15 minutos) → não purgue;
              registre.</substep>
          </substeps></step>
        <step order="5.5">Registre no TASK_PLAN.md o bloco de contexto: MODE,
          BASE_DIR, BASE_BRANCH, MAIN_ROOT, CHILD_ROOT, PLACEMENT, BRANCH_NS,
          SKILL_HOME, ENV_FILE, as FLAGS EFETIVAS do resumo e a contagem de
          worktrees de terceiros (NUNCA tocadas). Com wt=: a irmã
          <code>&lt;repo&gt;.worktrees/&lt;nome&gt;</code> é a RAIZ-DE-MUNDO e
          MAIN_ROOT é ZONA PROIBIDA.</step>
        <step order="6"><strong>DEPENDÊNCIA OBRIGATÓRIA — SURF-AGENT-SKILL v9+
          (R7) — AQUI só REGISTRA:</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_SURF_GATE"</cmd>
          e, só para os blocos de diagnóstico (o exit do doctor NÃO é
          interpretado; o veredito é a linha <code>SURF_GATE=</code>):
          <cmd>. '&lt;ENV_FILE&gt;'; command -v surf-search-normal || echo "SURF_AUSENTE"; surf doctor || true</cmd>
          Registre no TASK_PLAN.md: binário, SURF_GATE, SURF_CODE, a mensagem
          do portão VERBATIM e os blocos "## Brave key gate" e "## surf-ai".
          SURF_GATE=0 → pesquisa disponível. 78/127 → REGISTRE e PROSSIGA: sem
          plano não há como saber se alguma sub-tarefa exige pesquisa — a
          decisão é do PORTÃO PÓS-PLANO (FASE 2 passo 9), o ÚNICO ponto de
          decisão antes da FASE 3, e depois do passo 0 de CADA onda (inclusive
          sub-tarefa nascida de REPLAN). "## surf-ai" sem chave OpenRouter →
          buscas reais sem síntese: registre "pesquisa sem síntese" e siga (não
          é R7). PROIBIDO instalar a surf você mesmo (R9): quem instala é o
          USUÁRIO, pela pergunta do protocolo.</step>
      </steps>
      <output>Estados pendentes resolvidos; ENV_FILE com as flags VALIDADAS
        pelo script e conferidas no resumo; execuções órfãs purgadas;
        fronteira conhecida; portão da surf registrado; baselines de contenção
        (sujeira do usuário, config local, HEAD e status do checkout principal)
        capturados para a prova ao fim de cada onda.</output>
    </phase>
