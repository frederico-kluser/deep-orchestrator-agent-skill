<!-- MÓDULO v5.0.0 · origem: SKILL.md <degradation> (13 casos restantes) (split progressive disclosure)
     carga: lookup SÓ em falha · conteúdo byte-a-byte com a origem (CONTRATO.md §5)
     1 HOP: não referenciar outros módulos -->

## ÍNDICE POR SINTOMA
- `subagent-failure`
- `gate-red`
- `merge-conflict`
- `cleanup-failure`
- `test-subwave-failure`
- `validation-subwave-failure`
- `test-coverage-insufficient`
- `e2e-runner-unavailable`

  <degradation>
    <case id="subagent-failure">
      <symptom>Sub-agente retornou erro, timeout ou resultado vazio —
        inclusive o VAZIO (rc 4) do <code>integrate</code></symptom>
      <action>NÃO é este caso: handoff com SEARCH_STATUS BLOCKED_78/FAILED_*
        (ou sem a seção numa SEARCH_REQUIRED=sim) — isso é o protocolo
        PESQUISA-FALHOU (FASE 3 passo 4.5): não consome tentativa e a filha
        NÃO vira BLOCKED.
        Analise o erro, ajuste o prompt, re-dispare NA MESMA worktree (o
        estado parcial é contexto útil). Máximo 3 tentativas. Worktree
        inutilizável → NUNCA apague o branch à mão (o sintoma comum é daemon
        ou node_modules segurando handles, e o branch guarda o trabalho):
        <cmd>"$DO_WT" close &lt;nome&gt; --discard "worktree inutilizável: &lt;motivo&gt;"</cmd>
        (salva restos, ARQUIVA em refs/do-archive/$RUN_ID/&lt;nome&gt;, remove);
        se o close falhar por file handle, <cmd>"$DO_WT" remove &lt;nome&gt; --artifacts</cmd>
        (gradle --stop + clean -fdX) e repita o close; a tentativa -r2 nasce
        de $BASE_BRANCH com linha própria (ex.: onda1-cache-service-r2).
        Na 3ª falha: <cmd>"$DO_WT" mark &lt;nome&gt; BLOCKED</cmd>, registre
        BLOQUEIO e prossiga com as outras — a onda NÃO para. BLOCKED vive SÓ
        dentro da própria onda (R6(a)): ANTES do passo 8,
        <cmd>"$DO_WT" close &lt;nome&gt; --discard "bloqueada: &lt;motivo&gt;"</cmd>
        (o assert-clean a acusa) — vai NOMINALMENTE a "Não integrado"
        (NEVER-MERGED, I-MERGE).</action>
    </case>
    <case id="gate-red">
      <symptom>Gate VERMELHO (rc 4 do <code>gate</code>, "GATE FINAL
        VERMELHO", ou refutação da revisão adversarial)</symptom>
      <action><strong>CLASSIFICAÇÃO 4-VIAS antes de agir:</strong> (1) bug →
        fix (abaixo); (2) spec gap → REPLAN (FASE 3 passo 5); (3) ruído =
        AMBIENTE (install, deps ausentes) → reinstale deps congeladas /
        conserte o comando e rode <cmd>"$DO_WT" gate &lt;nome&gt;</cmd> de novo
        (R9; nunca fix de produção); (4) ambiguidade de contrato → atualize o
        contrato no TASK_PLAN.md. NUNCA retente às cegas.
        O VERMELHO NÃO limpa nada: filha, branch e snapshot ficam intactos e a
        filha segue <code>gate-pending</code>. <strong>FIX (via 1):</strong>
        sub-agente de FIX NA MESMA worktree, com o prompt: "O gate quebrou
        após merge. Erro: &lt;ERRO&gt;. PRIMEIRO rode
        <cmd>git merge &lt;BASE_BRANCH-literal&gt;</cmd> DENTRO desta worktree
        (EXCEÇÃO à regra anti-merge; &lt;BASE_BRANCH-literal&gt; é o branch da
        raiz-de-mundo como VALOR LITERAL — nunca main/master, nunca
        origin/*). SÓ DEPOIS corrija APENAS o necessário e commite. NÃO
        refatore. Vermelho vindo de TESTE: classifique bug de produção x erro
        do teste — PROIBIDO apagar, pular ou enfraquecer teste para
        esverdear." O merge vem ANTES do fix porque o squash da filha já está
        em $BASE_BRANCH: sem ele o re-integrate conflita ou PERDERIA
        deleções/reversões do fix — o script confere e RECUSA (rc 1, lista
        de paths: faça o merge, REAPLIQUE o fix nesses paths, commite e
        repita). Depois <cmd>"$DO_WT" integrate &lt;nome&gt; "&lt;msg&gt;"</cmd>
        (snapshot -r2 no SHA novo; veredito antigo descartado) e
        <cmd>"$DO_WT" gate &lt;nome&gt;</cmd>. TETO: 2 fixes; persistiu →
        <cmd>"$DO_WT" undo &lt;nome&gt;</cmd> (desfaz TODOS os squashes vivos da
        filha, arquivando cada um em refs/do-archive/$RUN_ID/undo-&lt;nome&gt;-&lt;k&gt;;
        prefere revert; reset --hard só quando pre..HEAD é exatamente a
        lista de squashes e o working tree não tem modificação tracked — NUNCA
        <cmd>git reset --hard</cmd> à mão) +
        <cmd>"$DO_WT" close &lt;nome&gt; --discard "gate vermelho persistente: &lt;etapa&gt;"</cmd>
        (NEVER-MERGED). <code>finish --gate-ok</code> NUNCA destrava
        vermelho; fechar sem conserto sai MERGED-PARTIAL no purge e vai a "Não
        integrado".
        <strong>VÍTIMAS:</strong> o snapshot de todo merge POSTERIOR ao
        squash culpado fica vermelho pela MESMA falha e não volta a verde
        sozinho. Depois do conserto, o GATE VERDE de qualquer integrate
        posterior (o -r2 corrigido ou a próxima filha) nasce de um SHA que já
        contém o squash das vítimas — o script imprime "covered": feche cada
        uma com <cmd>"$DO_WT" finish &lt;vítima&gt; --gate-ok</cmd>. Sem integrate
        posterior (undo sem re-integrar): <cmd>"$DO_WT" new integration int-ondaN-pos-undo</cmd>,
        rode nele o laço do gate final (FASE 4 passo 3, trocando "$BASE_DIR"
        pelo path impresso), <cmd>"$DO_WT" close int-ondaN-pos-undo</cmd> e, se
        verde, o finish --gate-ok das vítimas. É o ÚNICO uso legítimo de
        --gate-ok aqui.
        <strong>FALHA TARDIA:</strong> o VERMELHO pode chegar DEPOIS de merges
        seguintes (HEAD avançado). Antes do undo, confirme que o teste que
        falha não veio de um squash test-* anterior
        (<cmd>gwt log --oneline -- &lt;arquivo-do-teste&gt;</cmd>). O undo
        cobre HEAD avançado (revert exato dos squashes daquela filha; os demais
        ficam). Gates posteriores já verdes só são re-rodados se o revert tocar
        os arquivos deles (<cmd>gwt show --name-only --format= &lt;SHA-do-revert&gt;</cmd>;
        na dúvida, re-rode — caso das vítimas). Filha REVERTED nunca atravessa
        o passo 8: re-integre (fix na mesma worktree, merge do BASE antes) ou
        close --discard. Worktree NOVA de fix (<cmd>"$DO_WT" new fix ondaN-fix-&lt;foco&gt;</cmd>)
        é SÓ para bug achado DEPOIS que a filha fechou (subwaves, FIX-FINAL).</action>
    </case>
    <case id="merge-conflict">
      <symptom><code>"$DO_WT" integrate</code> saiu rc 1 com "CONFLITO"</symptom>
      <action>Não deveria acontecer com o mapa de propriedade respeitado. O
        script detectou em memória e RECUSOU sem sujar $BASE_DIR (git antigo:
        rollback FEITO): NADA a desfazer na raiz — NUNCA
        <cmd>git merge --abort</cmd>, <cmd>git reset --hard</cmd> ou
        <cmd>git -C</cmd> fora de $BASE_DIR; confira com
        <cmd>. '&lt;ENV_FILE&gt;'; gstatus</cmd>. Resolva NA worktree-filha: um
        sub-agente de RESOLUÇÃO com o diff dos dois lados e a autorização
        "EXCEÇÃO à regra anti-merge: rode
        <cmd>git merge &lt;BASE_BRANCH-literal&gt;</cmd> DENTRO desta worktree
        (VALOR LITERAL; nunca main/master, nunca origin/*), resolva TODOS os
        conflitos preservando a intenção dos DOIS lados, sem refatorar, e
        commite no seu branch; não toque no repositório principal nem na
        worktree-pai." Depois re-execute o MESMO integrate (aplica limpo:
        $BASE_BRANCH virou ancestral) e o <code>gate</code>.</action>
    </case>
    <case id="cleanup-failure">
      <symptom>"GATE VERDE … mas o fechamento falhou", finish/close com "FALHA
        ao remover", ou sweep/assert-clean listando sobra</symptom>
      <action>Toda remoção passa por finish/close, que só aceitam alvos do
        owned.tsv DESTA execução, sob $CHILD_ROOT e com o lock dela; recusa
        por path desconhecido = worktree de OUTRA sessão: registre
        "pré-existente, não tocada" e siga. Sujeira NÃO trava: finish e close
        --discard salvam os restos e ARQUIVAM antes de forçar. "FALHA ao
        remover" com branch já arquivado = daemon/handle: pare-o
        (<cmd>"$DO_WT" remove &lt;nome&gt; --artifacts</cmd>) e REPITA o mesmo
        finish/close (idempotentes). Restos que parecem trabalho real numa
        filha gate-pending: sub-agente nela roda
        <cmd>git merge &lt;BASE_BRANCH-literal&gt;</cmd> e SÓ DEPOIS commita;
        então integrate (squash incremental, -r2) + gate. NUNCA
        <cmd>git worktree remove -f -f</cmd> nem <cmd>git worktree prune</cmd>
        (desregistra terceiros); registro órfão é inofensivo — anote.</action>
    </case>
    <!-- caso surf-ausente → references/research-protocol.md -->
    <!-- caso brave-key-invalida → references/research-protocol.md -->
    <case id="test-subwave-failure">
      <symptom>Agente de teste falhou (erro, timeout, vazio)</symptom>
      <when>$DO_TEST_MODE=full ou e2e (none: N/A).</when>
      <action>Como subagent-failure (máx 3, mesma worktree). Na 3ª:
        <cmd>"$DO_WT" close test-ondaN-&lt;foco&gt; --discard "agente de teste falhou 3x: &lt;motivo&gt;"</cmd>
        (NEVER-MERGED) e prossiga com os outros. Não bloqueia o disparo da
        próxima onda, mas a linha fecha antes do passo 8 dela. Reporte em "Não
        integrado" + "Arquivos sem cobertura" (e2e: "Jornadas sem cobertura").
        Subwave parcial é melhor que nenhuma.</action>
    </case>
    <case id="validation-subwave-failure">
      <symptom>Validador falhou (erro, timeout, vazio) ou gate VERMELHO por
        código no estado integrado</symptom>
      <action>Como subagent-failure: re-dispare NA MESMA val-ondaN-gate (máx
        3; deps já instaladas). Na 3ª: registre BLOQUEIO,
        <cmd>"$DO_WT" close val-ondaN-gate</cmd> e documente — o COMMIT-FINAL
        não fecha com validação VERMELHA sem degradação documentada.
        AMBIENTE → reinstale deps congeladas e re-rode (nunca fix de
        produção). CÓDIGO → fix-final (FASE 4 passo 0), máx 2 por achado.</action>
    </case>
    <case id="test-coverage-insufficient">
      <symptom>Cobertura abaixo de 80% nos arquivos alvo</symptom>
      <when>SÓ full. e2e: cobertura é de JORNADAS (% N/A) — jornada sem
        caminho feliz + 1 erro vai a "Jornadas sem cobertura", nunca agente
        extra por porcentagem. none: N/A.</when>
      <action>≥ 60%: aceite com ressalva no handoff. &lt; 60%: UM agente
        adicional focado nos gaps (mesma worktree); ainda &lt; 60% → BLOQUEIO
        PARCIAL documentado. O gate não bloqueia por cobertura — registra.</action>
    </case>
    <case id="e2e-runner-unavailable">
      <when>$DO_TEST_MODE=e2e e não há como ter runner: "sem e2e" na FASE 1 E
        a onda1-e2e-harness não o instalou dentro de R9 (sem rede; exige
        -g/sudo/--with-deps; sem browser), ou o GATE_E2E não sobe um spec de
        fumaça por AMBIENTE.</when>
      <action>NUNCA instale global/sudo e NUNCA troque e2e por
        unit/integration. (1) Black-box com o runner que JÁ existe, se ele
        exercita o sistema pela porta do usuário (HTTP, CLI via processo, API
        pública): specs nele, mesmas regras do modo e2e, e
        <cmd>"$DO_WT" gate-set e2e "&lt;comando&gt;"</cmd>. (2) Nem isso →
        <cmd>"$DO_WT" gate-set e2e ""</cmd>, registre "Onda N: e2e
        INDISPONÍVEL — &lt;motivo&gt;", NÃO crie test-ondaN-e2e-* e leve TODAS
        as jornadas a "Jornadas sem cobertura" com o comando que o usuário
        roda para instalar; harness não integrou →
        <cmd>"$DO_WT" close onda1-e2e-harness --discard "runner e2e indisponível: &lt;motivo&gt;"</cmd>.
        O resto segue: falta de runner NÃO pausa e NÃO é PESQUISA-FALHOU.</action>
    </case>
    <!-- caso plannotator-unavailable → references/plan-approval.md -->
    <!-- caso plan-not-approved → references/plan-approval.md -->
    <!-- caso plan-title-drift → references/plan-approval.md -->
    <!-- caso plan-scope-expanded → references/plan-approval.md -->
    <!-- caso plan-round-interrupted → references/plan-approval.md -->
  </degradation>
