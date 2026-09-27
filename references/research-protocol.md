<!-- MÓDULO v5.0.0 · origem: SKILL.md <rule R7> + <protocol PESQUISA-FALHOU> + casos surf do <degradation>
     carga: SÓ quando SEARCH_REQUIRED=sim ou portão surf SURF_GATE != 0 · byte-a-byte com a origem (CONTRATO.md §5)
     CANÓNICO da pesquisa: uma só casa para a tabela SURF_GATE e a pergunta [1]-[4] -->

    <rule id="R7" severity="FATAL">
      <title>Pesquisa é EXCLUSIVAMENTE surf-agent-skill v9+ — dependência dura, verificada ANTES de qualquer onda</title>
      <body>Sem sistema de busca próprio: todo acesso à web passa pelos binários GLOBAIS da surf-agent-skill v9+
        (npm i -g surf-agent-skill): <strong>surf</strong> · <strong>surf-search-normal</strong> (UMA onda, cabe no
        timeout do Bash) · <strong>surf-search-unlimit</strong> ·
        <strong>surf-research-skill search|search-parallel</strong> (trechos crus) · <strong>surf-plan-skill</strong>.
        Quem pesquisa são os SUB-AGENTES (--sub-agents=N, 1..20); VOCÊ só roda busca em DOIS pontos: o [Verify this] da
        FASE 2.5 (passo 5) e a sonda <code>resume --probe</code> do protocolo.
        Backend: <strong>Brave Search e NADA MAIS</strong> — sem provedor de reserva nem tier sem chave; NÃO existe modo
        degradado AUTOMÁTICO: sem chave válida não há pesquisa, e seguir sem a pesquisa exigida só com escolha explícita
        do USUÁRIO (opção [3] do protocolo).
        PORTÃO (FASE 0 passo 6, PORTÃO PÓS-PLANO da FASE 2 e passo 0 de CADA onda — a chave pode queimar no meio):
        <cmd>. '&lt;ENV_FILE&gt;'; "$DO_SURF_GATE"</cmd>
        FAIL-CLOSED e grátis: imprime SURF_GATE=&lt;0|78|127&gt; e, quando != 0,
        <code>SURF_CODE=&lt;BraveKey...|BraveKeyUnknown|NotInstalled&gt;</code> + a mensagem do portão VERBATIM (traz o
        "Fix:", NUNCA uma chave). SEMPRE sai 0: veredito = a linha SURF_GATE=, nunca o exit code. Linha SURF_GATE=
        AUSENTE na saída (ou "command not found") = trate como 78 e conserte o caminho (o ENV_FILE grava
        DO_SURF_GATE="$SKILL_HOME/scripts/surf-gate.sh").
        Ação por SURF_GATE — tabela ÚNICA; as fases apontam para cá:
        • 0 — pronto. Prossiga.
        • 78 — não há chave Brave válida (ausente, queimada, em cooldown, inválida, inalcançável ou não provada). É
          CONFIGURAÇÃO: retentar não conserta. Sub-tarefa PENDENTE SEARCH_REQUIRED=sim (coluna OBRIGATÓRIA do plano,
          FASE 2; na dúvida "sim") → NÃO dispare pesquisador e execute o protocolo PESQUISA-FALHOU (g1 — com
          SURF_CODE=BraveKeyCooling vale ANTES a regra &lt;cooling&gt; dele). TODAS as pendentes com SEARCH_REQUIRED=nao
          no plano publicado: seguir sem busca é decisão SUA — registre no TASK_PLAN.md e prossiga. É PROIBIDO rebaixar
          SEARCH_REQUIRED para "nao" depois de um portão != 0 para fugir da pausa.
        • 127 — surf não instalada: mesmo tratamento (R2(a)); NUNCA instale você mesmo (`npm -g` é vedado por R9).
        Linha extra <code>SURF_MODE=no-search</code> (o usuário escolheu [3]; sai mesmo com SURF_GATE=0) → NÃO PESQUISE
        em todos os prompts até o fim (protocolo, passo E).
        TODA chamada de busca (sua ou de sub-agente) redireciona stdout e stderr para arquivo e é CLASSIFICADA — o exit 1
        não separa "0 fontes" de cota/429/402 (que NÃO viram 78):
        <cmd>"$DO_SURF_GATE" classify &lt;exit&gt; &lt;stdout-file&gt; &lt;stderr-file&gt;</cmd>
        imprime UM de OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78 | KILLED_143 | USAGE_2 (detalhe no template
        do sub-agente). EMPTY = busca FUNCIONOU e não achou: NÃO VERIFICADO (motivo "busca vazia"), sem pergunta — salvo
        g3. FAILED_QUOTA/FAILED_OTHER/BLOCKED_78 = ambiente do usuário: protocolo (g2). USAGE_2 (comando mal montado,
        verbo removido) e KILLED_143 (timeout do Bash: refaça com surf-search-normal ou peça timeout maior) = corrija o
        comando; NUNCA viram pergunta.
        VERBOS REMOVIDOS NA v8 (saem 2 se chamados): extract · crawl · map · research · research-start · research-poll ·
        usage. A Brave devolve título, URL e trecho — NUNCA o corpo da página.
        PROIBIÇÕES ABSOLUTAS:
        • NUNCA envolva uma chamada surf em sleep, jitter, backoff ou retry próprio: o surf já ritma pelo limite real do
          plano Brave. (Rerodar o PORTÃO, grátis, não é retry de BUSCA.)
        • NUNCA monte o portão à mão (<code>surf doctor</code> + exit code é fail-open e joga fora a mensagem do
          portão): o portão é SEMPRE <code>"$DO_SURF_GATE"</code>, NÃO existe veredito 1; surf doctor fica SÓ na FASE 0
          passo 6, para REGISTRAR Keys/surf-ai (o exit dele NÃO é interpretado).
        • NUNCA use WebSearch/WebFetch do harness (nem outro buscador) para DESCOBRIR fontes: fonte que não veio pelo surf
          não pode ser citada. Ler com Read/WebFetch uma URL que o SURF JÁ DEVOLVEU (ou o usuário forneceu) é permitido e
          é a única forma de ler uma página — anote no handoff.
        • NUNCA rode `surf-research-skill keys list --json` nem leia ~/.config/surf/keys.json: o diagnóstico é
          <code>"$DO_SURF_GATE"</code>, que mascara as chaves. NUNCA peça a chave colada no chat (iria para o
          transcript): quem roda o comando de chave é ELE, no terminal dele.</body>
    </rule>

    <protocol id="PESQUISA-FALHOU">
      <title>PESQUISA-FALHOU — a pesquisa exigida não funciona: PERGUNTE ao usuário, nunca siga calado</title>
      <scope>Bloco ÚNICO — pergunta e comandos vivem AQUI. Comandos rodam após <code>. '&lt;ENV_FILE&gt;';</code> na MESMA
        chamada Bash.
        <strong>INCONDICIONAL:</strong> vale com ou sem do-question e VENCE "não me pergunte nada", "autônomo", "toca o
        barco", "sem interrupção", no-stop e plan=off. Chave, cota e instalação são CONFIGURAÇÃO DO AMBIENTE do usuário,
        não ambiguidade da tarefa: você NUNCA decide sozinho que a pesquisa exigida é dispensável.</scope>
      <triggers>
        <trigger id="g1">O portão devolveu SURF_GATE != 0 (R7) E há sub-tarefa pendente SEARCH_REQUIRED=sim no plano ou
          na onda.</trigger>
        <trigger id="g2">Handoff PRESENTE com SEARCH_STATUS em {BLOCKED_78, FAILED_QUOTA, FAILED_OTHER} — NÃO é
          subagent-failure: não consome as 3 tentativas e a filha NÃO vira BLOCKED. Handoff AUSENTE/SEM a seção
          <code>## SEARCH_STATUS</code> numa SEARCH_REQUIRED=sim (UNKNOWN): PRIMEIRO 1 re-disparo NA MESMA worktree
          exigindo a seção (conta como tentativa de subagent-failure); voltou de novo sem ela →
          <cmd>"$DO_SURF_GATE" resume --probe</cmd>; pause SÓ com <code>RESUME=STILL_BLOCKED</code>.</trigger>
        <trigger id="g3">≥ 2 handoffs EMPTY na MESMA onda: rode <cmd>"$DO_SURF_GATE" resume --probe</cmd> (busca real
          barata, 1 crédito — a sonda grátis não enxerga cota). <code>RESUME=OK</code> → os vazios são reais: siga, sem
          pergunta. <code>RESUME=STILL_BLOCKED</code> → execute o protocolo.</trigger>
        <cooling>Vale SÓ para o gatilho g1: SURF_CODE=BraveKeyCooling (cooldown de 60 s) NÃO vira pergunta de cara — siga o
          trabalho que NÃO pesquisa e rerode o portão até 3x (sem sleep). Voltou 0 → prossiga. Persistiu na 3ª →
          protocolo. Em g2/g3 o BraveKeyCooling no passo B é CONSEQUÊNCIA da busca que falhou e NÃO adia a pergunta; com
          FAILED_*/BLOCKED_78 pendente, "voltou 0" NÃO basta: exija <code>resume --probe</code> (OK → re-delegue;
          STILL_BLOCKED → protocolo).</cooling>
      </triggers>
      <steps>
        <step id="A"><strong>CONGELE a pesquisa, FECHE o resto.</strong> Não dispare novos pesquisadores; espere a
          barreira dos em voo; conclua revisão → integrate → gate → finish de TODA sub-tarefa NÃO bloqueada (I-CLEAN,
          R6). As BLOQUEADAS ficam ACTIVE no owned.tsv — não são revisadas nem mergeadas.</step>
        <step id="B"><strong>DIAGNÓSTICO grátis e VISÍVEL:</strong> <cmd>"$DO_SURF_GATE"</cmd> — guarde
          SURF_GATE/SURF_CODE e a mensagem VERBATIM. NUNCA <code>keys list --json</code>.</step>
        <step id="C"><strong>GRAVE o estado:</strong>
          <cmd>"$DO_SURF_GATE" pause &lt;onda&gt; "&lt;sub-tarefas bloqueadas&gt;" "&lt;motivo&gt;"</cmd>
          — grava $DO_STATE/search-pause.md e IMPRIME o bloco da pergunta para colar. Registre uma linha
          "PAUSA-PESQUISA" no TASK_PLAN.md. (Antes da FASE 3, &lt;onda&gt; = 0.)</step>
        <step id="D"><strong>PERGUNTE em TEXTO e AGUARDE (R2).</strong> Cole o bloco imprimido pelo <code>pause</code>
          como ÚLTIMA coisa da resposta, SEM reescrever, e ENCERRE O TURNO (AskUserQuestion vetado: R10). Conteúdo FIXO
          (se o <code>pause</code> falhar, monte-o à mão com ESTE texto):
          <question-text><![CDATA[
===== PESQUISA-FALHOU — a pesquisa exigida não pôde ser feita; a decisão é SUA =====
Onda: <onda>
Sub-tarefas bloqueadas: <lista>
Motivo: <motivo>
Portão: SURF_GATE=<n> SURF_CODE=<código>
----- MENSAGEM DO PORTÃO (VERBATIM) -----
<mensagem do portão>
-----------------------------------------
Responda com o NÚMERO da opção:
  [1] Adicionei/troquei a chave Brave — tente de novo  (`surf-research-skill keys add --provider brave <CHAVE>` | terminal separado: `surf add`)
  [2] Ajustei o plano/cota ou esperei o cooldown — tente de novo  (`surf-research-skill keys reset --provider brave` limpa burn/cooldown em cache)
  [3] Seguir SEM pesquisa — premissas ficam marcadas NÃO VERIFICADAS no plano, handoffs e relatório
  [4] Abortar — fecho o que está aberto (purge) e entrego relatório parcial
Rode os comandos no SEU terminal e NÃO cole a chave no chat (iria para o transcript). `surf` e `surf add` exigem TTY.
Outros: remover chave morta `surf remove brave <i>` · revalidar `surf validate brave` · painel de cota https://api-dashboard.search.brave.com
]]></question-text>
          Com SURF_GATE=127 acrescente antes das opções: "A surf-agent-skill não está instalada: rode <code>npm i -g
          surf-agent-skill</code> no SEU terminal e responda [1]" (R9: quem instala é o usuário).</step>
        <step id="E"><strong>RETOMADA</strong> — na mensagem seguinte; o passo 0 da FASE 0 (ESTADOS PENDENTES) acha o
          search-pause.md e sourceia o ENV_FILE DAQUELE run:
          <substeps>
            <substep>[1] ou [2] → <cmd>"$DO_SURF_GATE" resume --probe</cmd>. <code>RESUME=OK</code> → <cmd>"$DO_SURF_GATE" choose
              search</cmd>, re-delegue SÓ as bloqueadas, NA MESMA worktree, com o handoff anterior colado; retome do ponto
              registrado. <code>RESUME=STILL_BLOCKED</code> → repita a pergunta (passos B–D), SEM limite de rodadas: quem
              decide sair por [3]/[4] é o usuário, nunca você.</substep>
            <substep>[3] → <cmd>"$DO_SURF_GATE" choose no-search</cmd> (grava $DO_STATE/search-mode e apaga o
              search-pause.md; daí o portão imprime TAMBÉM <code>SURF_MODE=no-search</code>, mesmo com SURF_GATE=0).
              Registre no TASK_PLAN.md "DECISÃO DO USUÁRIO: seguir sem pesquisa" e re-delegue as bloqueadas NA MESMA
              worktree. Com SURF_MODE=no-search, até o fim da execução: {{SURF_STATUS}} = "NÃO PESQUISE — usuário
              autorizou seguir sem busca" em TODOS os prompts; NÃO pause de novo por g1–g3; handoff FAILED_*/BLOCKED_78 →
              re-delegue na mesma worktree com NÃO PESQUISE, NUNCA integre o parcial. Toda premissa externa sai NÃO
              VERIFICADA no plano, nos handoffs e na seção "Pesquisa" do relatório final.</substep>
            <substep>[4] → <cmd>"$DO_WT" purge</cmd> (rc 3 esperado aqui) e entregue o relatório PARCIAL, com a seção
              "Não integrado" preenchida pelo <cmd>"$DO_WT" ledger</cmd>. NADA das bloqueadas é mergeado; só DEPOIS do
              relatório rode o DESCARTE O ESTADO (FASE 4, passo 8).</substep>
            <substep>Não é resposta ao protocolo → reimprima a pergunta UMA vez e AGUARDE; NUNCA inicie tarefa nova por
              cima de run pausado nem apague o $DO_STATE com search-pause.md vivo.</substep>
          </substeps></step>
      </steps>
    </protocol>

    <case id="surf-ausente">
      <symptom>Portão devolveu SURF_GATE=127 (SURF_CODE=NotInstalled)</symptom>
      <action>NUNCA instale por conta própria (R9). Sub-tarefa pendente
        SEARCH_REQUIRED=sim → protocolo PESQUISA-FALHOU (R2(a), g1): a
        pergunta já leva "npm i -g surf-agent-skill" e a retomada é
        <cmd>"$DO_SURF_GATE" resume --probe</cmd> — não improvise texto nem
        comando. TODAS as pendentes =nao → registre e prossiga sem busca (R7:
        proibido rebaixar a coluna).</action>
    </case>

    <case id="brave-key-invalida">
      <symptom>SURF_GATE=78 no portão, OU handoff com SEARCH_STATUS
        BLOCKED_78/FAILED_QUOTA/FAILED_OTHER (FASE 3 passo 4.5)</symptom>
      <action>CONFIGURAÇÃO DO AMBIENTE do usuário: sem provedor de reserva,
        re-disparar só repete o erro. 78 cobre chave ausente, queimada,
        inválida, não provada, em COOLDOWN e REDE (BraveKeyUnverified: o
        usuário NÃO deve mexer na chave) — quem diz é SURF_CODE + a mensagem
        VERBATIM com o "Fix:" próprio: NUNCA resuma nem troque por comando
        fixo. Cota/429/billing NÃO saem 78 (exit 1): só o
        <code>classify</code> separa FAILED_QUOTA de EMPTY. Pendente
        SEARCH_REQUIRED=sim → protocolo PESQUISA-FALHOU (R2(b), g1/g2; com
        BraveKeyCooling vale antes a regra &lt;cooling&gt;, só em g1); retomada
        por <cmd>"$DO_SURF_GATE" resume --probe</cmd> (a sonda grátis não
        enxerga cota). TODAS =nao → registre e prossiga; essa decisão NUNCA é
        sua com pesquisa exigida.</action>
    </case>
