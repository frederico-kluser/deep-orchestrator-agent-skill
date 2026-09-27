<!-- MÓDULO v4.2.0 · origem: SKILL.md <examples> (ex1; ex2 em references/plan-approval.md) (split progressive disclosure)
     carga: opcional (few-shot) · conteúdo byte-a-byte com a origem (CONTRATO.md §5)
     1 HOP: não referenciar outros módulos -->

  <examples>
    <example id="ex1" task="Adicionar endpoint de busca com cache a uma API REST">
      <plan>
        <wave id="1" name="Fundação">
          <agent id="1.1" worktree="onda1-cache-service" branch="$BRANCH_NS/onda1-cache-service" files="src/cache/">
            Pesquisar (<code>surf-search-normal "melhores bibliotecas de cache para a linguagem do projeto" --sub-agents=10</code>) as 3 melhores libraries
            de cache para a linguagem do projeto. Escolher uma. Instalar a dependência
            DENTRO da worktree (cwd na filha, modo congelado, HUSKY=0 — R9). Criar
            src/cache/CacheService com interface genérica.
          </agent>
          <agent id="1.2" worktree="onda1-schema-busca" branch="$BRANCH_NS/onda1-schema-busca" files="src/search/">
            Mapear o schema de busca existente: que campos, que filtros,
            que ordenação. Documentar no handoff.
          </agent>
        </wave>
        <wave id="2" name="Implementação" depends-on="1">
          <agent id="2.1" worktree="onda2-endpoint-busca" branch="$BRANCH_NS/onda2-endpoint-busca" files="src/search/SearchController.java" depends-on="1.1,1.2">
            Implementar o endpoint de busca com cache. Usar a interface do 1.1.
            Seguir o schema mapeado pelo 1.2. Escrever testes de integração
            (só no modo full: com no-test ou only-e2e essa frase sai —
            {{TEST_POLICY}}).
          </agent>
        </wave>
      </plan>
      <lifecycle>Fim da Onda 1: a história de $BASE_BRANCH (o branch da
        raiz-de-mundo — dentro de uma worktree vinculada, o branch DELA) ganhou
        exatamente 2 commits ("onda1-cache-service: ..." e
        "onda1-schema-busca: ..."); as worktrees onda1-* e os branches
        $BRANCH_NS/onda1-* NÃO existem mais — cada uma foi fechada pelo script
        no gate verde DELA (integrate → gate → finish), e o
        <code>assert-clean --wave 2</code> do passo 8 provou que nada sobrou;
        worktrees pré-existentes de terceiros continuam intactas.
        As subwaves da Onda 1 são disparadas em background ao fim dela (passo
        10): Testing Subwave 1 (test-onda1-cache-coverage e
        test-onda1-schema-tests) e Validation Subwave 1 (val-onda1-gate). Elas
        rodam ENQUANTO a Onda 2 executa — os features da Onda 2 já foram
        disparados (passo 3) e as subwaves são processadas no passo 3.5 da
        Onda 2, em paralelo com a barreira do passo 4.</lifecycle>
      <testing-subwaves>
        <tsw for-wave="1" worktrees="test-onda1-cache-coverage, test-onda1-schema-tests"
             runs-during="Onda 2" delivered-at="Onda 2, passo 3.5 (slot ocioso, após disparo dos features)"/>
        <tsw for-wave="2" worktrees="test-onda2-endpoint-tests"
             runs-during="COMMIT-FINAL setup" delivered-at="COMMIT-FINAL (passo 0 — processa as duas subwaves pendentes)"/>
      </testing-subwaves>
    </example>
      <!-- example ex2 (portão de aprovação) → references/plan-approval.md -->
  </examples>
