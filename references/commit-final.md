<!-- MÓDULO v6.0.0 · origem: SKILL.md <phase 4 COMMIT-FINAL> (split progressive disclosure)
     carga: ao ENTRAR na FASE 4 (antes do passo 0) · conteúdo byte-a-byte com a origem (CONTRATO.md §5),
     salvo as correções D-H (modelo único mimo-v2.6-pro, sem tiering) -->

    <phase id="4" name="COMMIT-FINAL">
      <objective>Commitar tudo e entregar — com ZERO worktrees e branches de
        sub-agente desta execução, e com o que NÃO foi integrado DECLARADO no
        relatório (I-MERGE, R3)</objective>
      <steps>
        <step order="0"><strong>PROCESSAR ÚLTIMAS SUBWAVES (TESTES +
          VALIDAÇÃO)</strong> — gatilho = LEDGER:
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" checklist final; "$DO_WT" status</cmd>
          TODA linha kind=test/validation com status != REMOVED, de QUALQUER
          onda, é subwave a processar AGORA (as seções PENDENTE do TASK_PLAN.md
          são só metadado). Com $DO_TEST_MODE=none só existe validação.
          <substeps>
            <substep><strong>TESTING SUBWAVE:</strong> BARREIRA (enquanto
              espera, PODE adiantar o gate PARCIAL sem os testes e o ARQUIVO
              DE FATOS; o gate final e o EXPLAINER só depois do merge dos
              testes) → REVISÃO DE TESTES (mesmas perguntas e mesmo destino do
              passo 3.5 da FASE 3; BLOCK persistente → close --discard +
              "Arquivos sem cobertura"; veredito CONFIRMADO | REFUTADO de cada
              "Bug encontrado") → BUGS CONFIRMADOS ENTRAM NO FLUXO FIX-FINAL
              (não há onda seguinte; bug reportado NUNCA vira "débito
              documentado" sem tentativa de fix) → INTEGRAR como no passo 7 da
              FASE 3:
              <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" integrate test-ondaN-&lt;foco&gt; "test-ondaN-&lt;foco&gt;: adiciona testes para &lt;desc&gt;"</cmd>
              e em background <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" gate test-ondaN-&lt;foco&gt;</cmd>
              (em e2e: <code>E2E_PORT=&lt;p&gt; "$DO_WT" gate test-ondaN-e2e-&lt;jornada&gt;</code>).
              Gate VERMELHO persistente (2 fixes) →
              <cmd>"$DO_WT" undo test-ondaN-&lt;foco&gt;</cmd> +
              <cmd>"$DO_WT" close test-ondaN-&lt;foco&gt; --discard "gate vermelho persistente"</cmd>
              + arquivos sem cobertura no relatório. TASK_PLAN.md: "Testing
              Subwave Onda N — CONCLUÍDA" com "Bugs reportados: N |
              confirmados: X | fix-final: &lt;nomes&gt;".</substep>
            <substep><strong>VALIDATION SUBWAVE:</strong> BARREIRA dos 2
              agentes (validador na val-ondaN-gate; revisor do diff integrado)
              → AVALIE o veredito por etapa e os achados: TUDO VERDE → registre
              "Validation Subwave Onda N — CONCLUÍDA"; VERMELHO ou achado
              material → FLUXO FIX-FINAL → feche SEM merge:
              <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" close val-ondaN-gate</cmd>.</substep>
            <substep><strong>FLUXO FIX-FINAL</strong> (validação VERMELHA por
              código OU bug CONFIRMADO de handoff de teste): LOTE ÚNICO, só
              DEPOIS das duas barreiras — cada achado vira
              <cmd>"$DO_WT" new fix fix-final-&lt;foco&gt;</cmd> (bug de teste:
              prompt com o teste que o revela — "remova o marcador
              skip/xfail/fixme e faça-o passar corrigindo a PRODUÇÃO —
              PROIBIDO enfraquecer a asserção ou apagar o teste") → revisão
              (passo 6) → integrate + gate (passo 7) → RE-VALIDAÇÃO UMA vez
              (val-ondaN-gate-r2, mesmo protocolo, fechada com
              <cmd>"$DO_WT" close val-ondaN-gate-r2</cmd>). Máx 2 tentativas
              por achado; persistiu → <cmd>"$DO_WT" undo &lt;nome&gt;</cmd> +
              <cmd>"$DO_WT" close &lt;nome&gt; --discard "&lt;motivo&gt;"</cmd> e a
              degradação vai ao relatório ("Não integrado", "Bugs encontrados"
              como ABERTO, "Arquivos sem cobertura", "Validação"). ANTI-LOOP:
              fix-final NÃO dispara nova subwave — o débito vai a "Arquivos
              sem cobertura". Falha por AMBIENTE → reinstale deps e re-rode,
              nunca fix de produção (R9).</substep>
          </substeps>
          Sem test-/val- aberta → NO-OP. Ao sair, confira que nada integrado
          ficou por limpar nem sub-tarefa esquecida:
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" sweep</cmd> — rc != 0 → resolva
          cada linha pelo comando impresso (integre pelo passo 7 ou close
          --discard) ANTES do gate final: o que o purge fechar sozinho sai como
          NEVER-MERGED:purge no relatório.</step>
        <step order="1">O TASK_PLAN.md é descartável e NUNCA entra na história —
          vive sob $DO_STATE (excluído por pathspec no gstatus/stage-delta; sem
          <cmd>git rm</cmd>); a remoção é o passo 8. NUNCA use
          <code>$CLAUDE_PROJECT_DIR</code> (vazia fora de hooks →
          <cmd>rm /TASK_PLAN.md</cmd>).</step>
        <step order="2">Estado final: <cmd>. '&lt;ENV_FILE&gt;'; gstatus; gwt diff --stat</cmd></step>
        <step order="3">GATE FINAL — as MESMAS etapas gravadas na FASE 1 passo
          9, com cwd em $BASE_DIR (o <code>"$DO_WT" gate</code> é dos
          snapshots; aqui os mesmos arquivos de comando):
          <cmd>. '&lt;ENV_FILE&gt;'; ( cd "$BASE_DIR" &amp;&amp; for s in install build test lint; do f="$DO_STATE/gate/$s.cmd"; [ -s "$f" ] || continue; echo "=== [$s] $(cat "$f")"; HUSKY=0 CI=1 bash -c "$(cat "$f")" &lt; /dev/null || { echo "GATE FINAL VERMELHO: $s"; exit 4; }; done; echo "GATE FINAL VERDE" )</cmd>
          Com none o GATE_TEST roda igual, na suíte EXISTENTE. Em e2e o
          GATE_E2E final NÃO roda em $BASE_DIR (os artefatos do runner
          entrariam no stage-delta): numa worktree descartável, com a porta do
          contexto "gate final" da tabela E2E_PORT —
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" new validation val-final-e2e</cmd>,
          rode <code>CI=1 E2E_PORT=&lt;p&gt; bash -c "$(cat "$DO_STATE/gate/e2e.cmd")"</code>
          com cwd nela e feche com <cmd>"$DO_WT" close val-final-e2e</cmd>.
          "GATE FINAL VERMELHO" → NÃO commite: classifique pela degradation
          gate-red e corrija por fix-final-&lt;foco&gt; (FLUXO FIX-FINAL).</step>
        <step order="4"><strong>HTML EXPLAINER (antes do commit — entra
          nele):</strong> DELEGUE a um SUB-AGENTE explicador FRESCO pelo
          <code>&lt;explainer-agent-template&gt;</code>, seguindo a skill
          <code>html-explainer-agent-skill</code> (leitor declarado, portão de
          complexidade, brief didático, Buzzwords, Figuras com legenda
          afirmativa, andaime em <code>&lt;details&gt;</code>; render por
          <code>visual-explainer</code> / <code>plannotator-visual-explainer</code>
          com Mermaid no <code>diagram-shell</code>, página self-contained).
          <substeps>
            <substep><strong>ARQUIVO DE FATOS:</strong> grave antes, via Bash
              (R1(c)), <path>$DO_STATE/explainer/fatos.md</path>: resumo da
              tarefa; ondas × worktrees × arquivos; squashes; decisões
              autônomas; vereditos de validação; cobertura conforme
              $DO_TEST_MODE (none: "Testes: DESLIGADOS por no-test"; e2e:
              jornadas cobertas × sem cobertura); a saída de
              <cmd>"$DO_WT" ledger</cmd>; a triagem de pesquisa; a timeline.</substep>
            <substep><strong>DISPARE o explicador em BACKGROUND</strong> (fatos
              INLINE ou pelo path; pode ler $BASE_DIR; escreve SÓ em
              <path>$BASE_DIR/EXPLAINER.html</path> — raiz da RAIZ-DE-MUNDO,
              nunca path de --git-common-dir); modelo ÚNICO mimo-v2.6-pro (sem tiering, D-H); SEM timeout. A UI do Plannotator é opcional.</substep>
            <substep><strong>DISPARE JUNTO o AGENTE DE EVOLUÇÃO</strong> (SÓ
              com DO_EVOLUTION_SURVEY=1; <code>&lt;evolution-agent-template&gt;</code>):
              grave o contexto —
              <cmd>. '&lt;ENV_FILE&gt;'; mkdir -p "$DO_STATE/evolution"; cat &gt; "$DO_STATE/evolution/contexto.md" &lt;&lt;'CTX'</cmd>
              (paths: $PLAN_FILE com TODOS os handoffs — "o principal" —,
              $DO_STATE/explainer/fatos.md, $PLAN_APPROVAL_DIR se
              DO_PLAN_APPROVAL=1, $PROJECT_CONFIG, $PROJECT_LEARNINGS,
              $GLOBAL_TIPS, $PENDING_DIR, $GLOBAL_PENDING_DIR, variáveis do
              harness para os transcripts) — e dispare-o com o path colado;
              SEM limite de tempo; o passo 7.5.1 aguarda os dois. Com
              no-evolve: nem contexto nem agente.</substep>
            <substep><strong>CONFIRA</strong> o EXPLAINER.html (existe, não
              vazio, HTML completo). Explicador falhou → subagent-failure (máx
              3); esgotadas, grave via Bash (R1(c)) um EXPLAINER.html mínimo
              auto-contido com os fatos e registre a degradação no relatório.
              NUNCA recrie o gerador antigo.</substep>
          </substeps></step>
        <step order="5">Tudo verde → commite o que RESTA, e só o seu:
          <cmd>. '&lt;ENV_FILE&gt;' &amp;&amp; "$DO_WT" stage-delta &amp;&amp; gwt commit -m "&lt;mensagem descritiva&gt;"</cmd>
          (stage-delta estagia só os paths que apareceram DEPOIS da FASE 0; a
          sujeira pré-existente é do USUÁRIO; PROIBIDO <cmd>git add -A</cmd>).
          Sucesso = <cmd>gstatus</cmd> contém exatamente o
          <path>$DO_STATE/dirty-baseline.txt</path> — não "100% limpo".</step>
        <step order="5.5"><strong>PUSH (a pergunta de evolução vem DEPOIS do
          commit E do push):</strong>
          <cmd>. '&lt;ENV_FILE&gt;'; if gwt remote &gt;/dev/null 2&gt;&amp;1; then gwt push -u origin "$BASE_BRANCH" 2&gt;&amp;1 || echo "AVISO: push falhou — registre no relatório e siga (nunca bloqueia)"; else echo "AVISO: sem remote configurado — push pulado"; fi</cmd>
          NUNCA bloqueia nem aborta (sem remote/upstream/rede → registre e
          siga). Com wt-root (DO_WT_ROOT=1) sobe $BASE_BRANCH
          (<code>do/wt/&lt;nome&gt;</code>) — e o fim é APENAS isso (R8(j)):
          PROIBIDO mergear/fast-forward/rebasear/abrir PR do branch do wt de
          volta ao branch de ORIGEM ou pushar outro branch; integrar é decisão
          do usuário.</step>
        <step order="6"><strong>PURGE FINAL — ZERO WORKTREES SOBREVIVEM
          (R6/R8):</strong> TODAS as worktrees/branches de sub-agente DESTA
          execução morrem AQUI — inclusive test/validation, snapshots e
          BLOCKED/ORPHANED:
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" purge; echo "PURGE_RC=$?"; "$DO_WT" assert-clean; "$DO_WT" ledger; "$DO_WT" verify</cmd>
          (com <code>;</code>, nunca <code>&amp;&amp;</code>). O purge fecha
          cada linha: integradas por finish --gate-ok (o squash já está em
          $BASE_BRANCH e o gate FINAL já rodou — pode sair MERGED-PARTIAL), o
          resto por close --discard "purge"; arquiva ANTES de apagar.
          <substeps>
            <substep><code>PURGE_RC=0</code> → tudo fechado e integrado.</substep>
            <substep><code>PURGE_RC=1</code> → "PURGE INCOMPLETO": conserto de
              cada sobra impresso — resolva e repita o comando inteiro até 0
              ou 3. NÃO siga com rc 1.</substep>
            <substep><code>PURGE_RC=3</code> → limpou TUDO, mas houve
              NEVER-MERGED e/ou MERGED-PARTIAL: não é erro de limpeza nem se
              "conserta" repetindo; o bloco
              <code>PURGE: NUNCA INTEGRADAS / PARCIAIS (obrigatorio no relatorio final):</code>
              vai LITERAL para "Não integrado" e o título vira "Tarefa
              concluída PARCIALMENTE" (I-MERGE).</substep>
          </substeps>
          <code>assert-clean</code> sem --wave = prova do fim ("ASSERT-CLEAN OK
          — tudo fechado"). O <code>ledger</code> é a FONTE do relatório —
          guarde a saída AGORA (o passo 8 apaga o owned.tsv). Branches
          arquivados em refs/do-archive/$RUN_ID/ (refs LOCAIS, não vão no
          push; o relatório entrega ao usuário
          <cmd>git branch resgate/&lt;nome&gt; refs/do-archive/$RUN_ID/&lt;nome&gt;</cmd>).
          Única sobrevivente: a irmã do wt-root (fora do owned.tsv, R8(j)).
          Worktrees/branches fora do owned.tsv são de outras sessões
          ("pré-existentes, não tocados"); PROIBIDO <cmd>git worktree prune</cmd>
          e <cmd>worktree remove -f -f</cmd>.</step>
        <step order="7">RELATÓRIO FINAL (formato no
          <code>&lt;final-report-template&gt;</code>), mencionando o
          EXPLAINER.html. Fonte do destino de cada sub-tarefa = o
          <code>"$DO_WT" ledger</code> do passo 6, NUNCA a memória. Título:
          "Tarefa concluída" só com nunca-integradas=0 e parciais=0 no RESUMO;
          senão "Tarefa concluída PARCIALMENTE". "Não integrado" é
          OBRIGATÓRIA (NEVER-MERGED/MERGED-PARTIAL/EMPTY com nome, kind,
          motivo, ARCHIVE_REF + comando de resgate — ou "nenhum"). Também:
          "Pesquisa" (tabelas do 4.5), "Perguntas ao usuário" (com
          DO_QUESTION=1) e a linha de testes do modo (none: "Testes:
          DESLIGADOS por no-test — testes novos: &lt;contagem verificada por
          gwt diff --stat &lt;pre-da-1ª-filha&gt;..HEAD -- &lt;globs de teste&gt;&gt;;
          gate rodou a suíte existente: &lt;GATE_TEST&gt;"; e2e: tabela "Testes
          e2e (only-e2e)" + "Jornadas sem cobertura"). Com PLAN_APPROVAL=1,
          copie o trail AGORA (<cmd>. '&lt;ENV_FILE&gt;'; "$DO_PLAN_APPROVAL_SH" status</cmd>
          — vive sob $DO_STATE). Com evolução ligada, seção "Evolução
          pós-execução" (propostas: quantidade, escopos, keys) e a nota
          "pergunta ao final — responda com os códigos". NÃO limpe o $DO_STATE
          aqui.</step>
        <step order="7.5"><strong>EVOLUÇÃO PÓS-EXECUÇÃO (PERGUNTA EM TEXTO ao
          fim de TUDO — nunca um site):</strong> SÓ com DO_EVOLUTION_SURVEY=1;
          com no-evolve pule o passo INTEIRO.
          <substeps>
            <substep><strong>7.5.1 BARREIRA</strong> do agente de evolução
              (disparado no passo 4): ele analisou o histórico COMPLETO
              (handoffs do TASK_PLAN.md = fonte mínima; transcripts =
              best-effort), filtrou pelo evolution-guide.md e gravou
              <path>$DO_STATE/evolution/proposals.md</path> (candidatos PNNN
              com title, type, confidence, source, tags, scope
              project|global, observacao, acao e opcao_a/b/c — a c é SEMPRE
              "Não fazer nada"). Falhou 3× → "evolução degradada (sem
              pergunta)" no relatório e pule o resto — NUNCA bloqueia.</substep>
            <substep><strong>7.5.2 SEM CANDIDATOS:</strong>
              <cmd>. '&lt;ENV_FILE&gt;'; grep -q '^key: P' "$DO_STATE/evolution/proposals.md" 2&gt;/dev/null || echo SEM-PROPOSTAS</cmd>
              → registre "evolução: sem candidatos" e vá ao passo 8.</substep>
            <substep><strong>7.5.3 MONTE A PERGUNTA (via script):</strong>
              <cmd>. '&lt;ENV_FILE&gt;'; "$DO_SURVEY" ask</cmd> gera
              <path>$DO_STATE/evolution/pendente.md</path> (propostas numeradas
              com opções a/b/c e escopo "1 = local · 2 = global") e imprime o
              bloco. Cole-o na SUA mensagem final e AGUARDE (R2(e)): o
              $DO_STATE fica PRESERVADO (passo 8 pulado); a continuação é a
              FASE 0 passo 0.</substep>
            <substep><strong>7.5.4 RESPOSTA E APPLY (turno seguinte, FASE 0
              passo 0):</strong>
              <cmd>. '&lt;ENV_FILE&gt;'; "$DO_SURVEY" answer "&lt;mensagem do usuário&gt;" &amp;&amp; "$DO_SURVEY" apply</cmd>
              ("1:b2 2:c1"; "b2" para uma só; "nada"/"pular"/vazio = tudo
              pendente; "config: &lt;texto&gt;"); o apply salva as aprovadas
              (a/b → projeto ou global), descarta as "c", pendura as sem
              resposta em pending/ e grava configs em project-config.md;
              falha de escrita → AVISO. Sem resposta →
              <cmd>"$DO_SURVEY" dismiss</cmd>. Nada é promovido ao corpo da
              skill automaticamente (evolution-guide.md).</substep>
          </substeps></step>
        <step order="8"><strong>DESCARTE O ESTADO (PULADO com pergunta
          pendente):</strong> UM comando, NESTA ordem — clean-ignored-delta e
          assert-clean leem arquivos de $DO_STATE, logo ANTES do rm -rf:
          <cmd>. '&lt;ENV_FILE&gt;'; "$DO_WT" discard-state</cmd>
          clean-ignored-delta apaga SÓ os ignorados que NÃO existiam na FASE
          0 (deps que você instalou para o gate, R9 — gigabytes na worktree do
          usuário; o baseline protege node_modules/.venv/.env.local
          pré-existentes; NUNCA <cmd>git clean -fdX</cmd> às cegas). O
          assert-clean é a trava: owned.tsv com linha viva NUNCA é apagado
          (R8(d)). Apaga SÓ o run do ENV_FILE sourceado; outros run-* ficam.
          Um <cmd>rmdir "$DO_HOME"</cmd> sozinho falha em silêncio e deixa
          <code>?? .deep-orchestrator/</code> no git status do usuário.
          COM PERGUNTA PENDENTE (evolução, do-question, search-pause.md): pule
          — a limpeza roda no passo 0 da FASE 0 da próxima mensagem; NUNCA
          descarte estado com pausa viva, salvo na opção [4] do protocolo
          (purge → relatório parcial → este passo).</step>
      </steps>
    </phase>
