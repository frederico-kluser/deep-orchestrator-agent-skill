# Search Prompts — Otimizados para Desenvolvimento de Software

> Contrato de prompts de busca do deep-orchestrator para tarefas de
> desenvolvimento de software. Define COMO as buscas são formuladas,
> refinadas (question evolution) e avaliadas. A interface PRIMÁRIA de
> execução é `{{SKILL_HOME}}/scripts/search.sh` (fallback automático em
> 3 tiers: surf-skill → Brave Search API → DuckDuckGo keyless); o
> `brave-search.sh` é a implementação do Tier 2 (API Brave, parsing,
> flags CLI). Este documento é a camada de estratégia; o search.sh é a
> camada de execução.

## Filosofia de Busca para Dev

Diferente de busca genérica, busca para desenvolvimento precisa de:

- **Termos técnicos precisos** (nomes de API, flags, métodos) — a query certa
  para um dev é o nome exato do símbolo, não a descrição conceitual
- **Contexto de versão** (v2, v3, deprecated, 2025, 2026) — sem pin de versão,
  o resultado de busca de um framework é uma mistura inútil de eras
- **Foco em fontes primárias** (documentação oficial, GitHub, RFCs) — para dev,
  a fonte primária é a fonte da verdade; blog explica a fonte, não a substitui
- **Verificação cruzada** (stackoverflow + docs + source code) — um trecho de
  código de um fórum não é verdade até bater com a documentação oficial e,
  idealmente, com o source code da versão instalada
- **Consciência de frescor** (tecnologia de 2022 pode já estar obsoleta) — em
  software, obsoleto se mede em anos, às vezes meses (ecossistemas JS e de LLMs)

Princípio extra, herdado do sistema de busca 3-tier do deep-orchestrator
(`search.sh --insights`): **estado o que julgo saber e busco o que o
FALSIFICARIA.** Uma busca que só confirma o que o agente já acredita não é
pesquisa; é viés. Toda rodada de evolução deve incluir pelo menos uma query de
falsificação quando existirem crenças prévias.

---

## 1. Categorias de Busca para Dev

Oito categorias cobrem a esmagadora maioria das buscas de desenvolvimento.
Cada uma tem um template de prompt base e regras de formulação. Placeholders
estão em `{{MAIUSCULAS}}`.

### 1.1 API / Library Lookup

Buscar documentação de API/biblioteca específica.

```text
"{{API_NAME}}" {{VERSAO}} documentation {{LINGUAGEM}}
"{{API_NAME}}" {{VERSAO}} reference {{FUNCAO_OU_CLASSE}}
"{{API_NAME}}" {{VERSAO}} example {{CASO_DE_USO}}
site:{{DOMINIO_DOCS_OFICIAL}} "{{API_NAME}}" {{SIMBOLO}}
```

Regras:
- **Sempre pinar versão** (`"react" 19`, `"axios" 1.x`) — sem isso o resultado
  mistura breaking changes irreconciliáveis.
- Preferir `site:` da documentação oficial; usar aspas no nome da API para
  evitar homônimos (ex.: `"express"` vs `expressjs` vs `express-writer`).
- Se a API tem nome comum (ex.: `fetch`, `cache`), adicionar a linguagem E o
  ecossistema: `"fetch" API JavaScript browser vs Node`.

### 1.2 Error / Exception Debug

Buscar solução de erro específico.

```text
"{{MENSAGEM_DE_ERRO}}" {{LINGUAGEM}} {{VERSAO_RUNTIME}}
"{{NOME_OU_CODIGO_DO_ERRO}}" {{FRAMEWORK}} stack trace
"{{MENSAGEM_DE_ERRO}}" site:stackoverflow.com
"{{MENSAGEM_DE_ERRO}}" site:github.com {{REPO}} issue
```

Regras:
- **Copiar a mensagem de erro EXATA entre aspas** — erros truncados ou
  parafraseados retornam ruído. Incluir código do erro (`EACCES`, `TS2304`,
  `ERR_INVALID_ARG_TYPE`) quando existir.
- Incluir ambiente: sistema operacional, versão do runtime, flag de compilação.
- GitHub issues > StackOverflow para bugs de biblioteca: issues têm o fix
  real, SO tem workaround.
- Após achar a solução, VALIDAR se o fix se aplica à mesma versão
  (um fix para `next 13` pode não valer para `next 15`).

### 1.3 Architecture Decision

Pesquisar trade-offs de decisão arquitetural.

```text
{{DECISAO}} trade-offs {{TECNOLOGIA_A}} vs {{TECNOLOGIA_B}}
"{{DECISAO}}" ADR architecture decision record {{ANO}}
{{DECISAO}} case study produção {{EMPRESA_OU_CASO}}
{{DECISAO}} quando NÃO usar limitações
```

Regras:
- Arquitetura não se resolve com "melhor biblioteca" — buscar **trade-offs**,
  **limitações** e **contraindicações**, não rankings.
- Preferir ADRs e case studies de produção (verdade empírica) sobre
  opiniões de blog.
- Incluir a query de falsificação: `{{TECNOLOGIA_X}} problems issues
  "we chose" regretted`.

### 1.4 Version Migration

Buscar breaking changes e guias de migração.

```text
{{BIBLIOTECA}} {{VERSAO_ANTIGA}} para {{VERSAO_NOVA}} migration guide
"{{BIBLIOTECA}}" breaking changes {{VERSAO_NOVA}} release notes
{{BIBLIOTECA}} {{RECURSO_DEPRECATED}} deprecated replacement
{{BIBLIOTECA}} changelog {{VERSAO}} upgrade
```

Regras:
- **Nunca migrar sem ler release notes + changelog oficiais** — são a fonte
  primária de breaking changes.
- Buscar `deprecated` da versão nova, não só o guia de migração (muitos
  deprecations não estão no guia).
- Cross-check com issues: `{{BIBLIOTECA}} {{VERSAO_NOVA}} migration
  site:github.com` revela o que quebrou na prática.

### 1.5 Security Vulnerability

Buscar CVEs e security advisories.

```text
{{BIBLIOTECA}} CVE {{ANO}} vulnerability
"{{BIBLIOTECA}}" security advisory {{VERSAO}} fixed
{{BIBLIOTECA}} CVE-{{ANO}}-{{ID}} versões afetadas patch
site:github.com {{REPO}} security-advisories
site:osv.dev "{{BIBLIOTECA}}"
```

Regras:
- **Sempre incluir a versão afetada** — "vulnerability" genérica sem versão
  não permite triagem.
- Fontes primárias: GitHub Security Advisories, OSV.dev, NVD/CVE.org, bulletins
  oficiais do ecossistema (ex.: https://rustsec.org para Rust).
- Cross-check: advisory oficial + issue de fix + PR do patch — o advisory
  sozinho não diz se a sua versão é atingida.

### 1.6 Performance Optimization

Buscar técnicas de otimização.

```text
{{BIBLIOTECA}} performance benchmark {{VERSAO}}
{{FRAMEWORK}} performance optimization {{PADRAO_OU_GARGALO}}
"{{OPERACAO_A}}" vs "{{OPERACAO_B}}" benchmark {{LINGUAGEM}}
{{FRAMEWORK}} profiling {{GARGALO}} {{CONTEXTO}}
```

Regras:
- Performance sem benchmark não é fato — preferir resultados com números e
  metodologia (hardware, versões, dataset).
- Benchmarks independentes > benchmarks do próprio autor da biblioteca.
- Otimização depende do gargalo real: incluir o contexto
  (`on AWS Lambda`, `in Docker`, `100k requests/min`).

### 1.7 Library Comparison

Comparar bibliotecas/frameworks.

```text
{{LIB_A}} vs {{LIB_B}} {{ANO}} comparison
"{{LIB_A}}" vs "{{LIB_B}}" benchmark {{METRICA}}
"{{LIB_A}}" alternatives {{ECOSSISTEMA}} {{ANO}}
"{{LIB_A}}" issues problems produção
```

Regras:
- Adicionar o ano — comparação de 2023 de bibliotecas JS está desatualizada.
- Comparar por métricas concretas: bundle size, performance, licença,
  manutenção (último release), tamanho da comunidade.
- A query mais valiosa é a de falsificação: `{{LIB_A}} problems` /
  `"we moved away from {{LIB_A}}"` — o que o marketing não mostra.

### 1.8 Code Example Search

Encontrar exemplos de código funcional.

```text
"{{BIBLIOTECA}}" {{VERSAO}} example {{RECURSO}}
{{BIBLIOTECA}} {{RECURSO}} minimal example {{LINGUAGEM}}
{{BIBLIOTECA}} {{RECURSO}} site:github.com examples
"{{BIBLIOTECA}}" code snippet {{CASO_DE_USO}}
```

Regras:
- Preferir exemplos com código executável sobre descrições textuais
  (ver métrica Density, seção 2.4).
- Preferir exemplos oficiais (docs, repo da própria lib, examples/ oficial)
  sobre snippets avulsos.
- Sempre conferir a versão do exemplo — exemplos antigos são a principal
  fonte de código errado.

---

## 2. Sistema de Evolução de Perguntas

### 2.1 Princípios

A evolução de perguntas (question evolution) é o processo de refinar
iterativamente uma query de busca baseado nos resultados obtidos.
É a implementação, para busca web, do loop agêntico clássico
**retrieve → analyze → refine**: a saída de uma busca informa a próxima
(multi-hop retrieval).

```
Query Inicial → Análise de Resultados → Identificação de Lacunas → Query Refinada
     ↑                                                                      |
     └──────────────────────────────────────────────────────────────────────┘
                              (loop até convergência)
```

Princípios:

1. **A evidência governa a evolução.** A próxima query é determinada pelas
   lacunas dos resultados atuais (o que KAIR chama de "What is Known vs What
   is Required"), não por intuição.
2. **Uma query resolve um objetivo.** Objetivos multi-condição devem ser
   decompostos em subqueries (um critério por busca) e depois sintetizados —
   buscar "biblioteca de cache + queue + logging para Node" de uma vez só
   falha; buscar cada critério separado funciona.
3. **Convergência é alcançada, não presumida.** O loop só para por critério
   explícito (seção 2.3) ou esgotamento do orçamento de evoluções
   (`--max-evolutions` no search.sh).
4. **Não redescobrir.** Ângulos já explorados ficam registrados (seção 5 —
   Handoff) para que as evoluções vão mais fundo em vez de re-buscar o mesmo
   fato; caminhos sem resultado viram "explorado, sem achado", nunca
   re-buscados às cegas.
5. **A evolução trabalha sobre resumo, não sobre a pilha crua de resultados.**
   O que alimenta o próximo round é a síntese do que já foi encontrado e do
   que falta — sem isso, o contexto apodrece e as evoluções degeneram em
   ruído (context rot).
6. **Falsificação a cada round.** Se o agente formou uma crença a partir dos
   resultados, a próxima evolução deve incluir a query que poderia derrubá-la.

### 2.2 Estratégias de Evolução

Quatro estratégias primárias + uma avançada. O nome da estratégia escolhida
fica registrado no handoff junto da query evoluída (seção 5).

#### Strategy A: Narrowing (Estreitamento)

**Quando:** resultados muito amplos/genéricos (precisão baixa — resumo de
tópico, não a resposta).

Operações de reescrita:
- Adicionar versão específica ("React 19", "Python 3.12")
- Adicionar contexto ("in Docker container", "on AWS Lambda")
- Adicionar restrição ("open source only", "TypeScript not JavaScript")
- Adicionar site target (`site:stackoverflow.com`, `site:docs.example.com`)
- Entre aspas o termo técnico exato para eliminar homônimos

Exemplo: `react hooks` → `"react" 19 "useActionState" form action example`

#### Strategy B: Broadening (Ampliação)

**Quando:** resultados muito específicos/escassos (recall baixo — quase nada
relevante voltou).

Operações de reescrita:
- Remover termos muito específicos (versão, sub-recurso)
- Usar sinônimos e conceitos relacionados ("memoization" → "caching
  computed values", "lazy loading" → "code splitting")
- Subir um nível de categoria ("Vue 3 Composition API" → "Vue 3 state
  management")
- Remover restrições que cortam demais o resultado
- Remover palavras comuns demais que diluem o resultado

Exemplo: `"useSyncExternalStore" react 19.1 bug` → `react "useSyncExternalStore"`

#### Strategy C: Lateral Expansion (Expansão Lateral)

**Quando:** resultados acertam o tópico mas falta profundidade (diversidade
baixa — tudo vem do mesmo domínio, ou só existe um ângulo coberto).

Operações de reescrita:
- Buscar por conceitos adjacentes ("request deduplication" em vez de
  só "react-query")
- Explorar implementações alternativas ("alternatives to X", "how does Y
  solve this")
- Buscar críticas/contraindicações ao que foi encontrado ("X problems",
  "X limitations", "when not to use X")
- Buscar o mesmo problema em ecossistemas vizinhos (o padrão do Go pode
  ter nome diferente no Rust)
- Buscar discussões de comunidade (HN, lobste.rs, Reddit) para ângulos
  que blogs não cobrem

Exemplo: `react-query cache invalidation` → `react-query vs SWR invalidation
stale data` + `react-query invalidation limitations`

#### Strategy D: Validation (Validação)

**Quando:** resultados parecem bons mas precisam verificação (fonte única,
blog sem autoridade, sem contradição testada).

Operações de reescrita:
- Buscar por "X issues", "X problems", "X deprecated", "X abandoned"
- Buscar por benchmarks independentes
- Buscar por CVEs ou security advisories
- Cross-check entre fontes: docs oficiais vs stackoverflow vs source code
  (o mesmo fato nas três = alta confiança)
- Buscar a data de última atualização/último release ("X last release",
  "X is maintained")

Exemplo: `libsqlite3-sys cross compile` → `libsqlite3-sys issues cross
compile` + `libsqlite3-sys security advisory`

#### Strategy E: Decomposition (Decomposição Multi-Hop)

**Quando:** a pergunta tem múltiplas restrições/etapas que a busca única não
resolve (a query "cabe" no buscador, mas o objetivo exige encadear fatos de
domínios diferentes).

Operações:
- Quebrar em subqueries, um critério por query
- Buscar os critérios em paralelo
- Usar o resultado de uma subquery como termo da próxima (encadeamento)
- Sintetizar os sub-resultados antes de declarar a resposta

Exemplo: `melhor vector DB para RAG com pgvector vs Qdrant em produção` →
subqueries: (a) `pgvector vs Qdrant benchmark 2026`, (b) `pgvector
limitations production`, (c) `Qdrant production case study`, e só então o
agente decide.

### 2.3 Algoritmo de Evolução

Pseudo-código de referência:

```
function evolve_query(original_query, previous_results, round_number):
    if round_number == 0:
        return original_query
    
    quality = assess_result_quality(previous_results)
    
    # Precedência: quando too_narrow e too_broad disparam juntos (poucos
    # resultados E baixa precisão), too_narrow vence — em resultados
    # escassos, broadening gera mais resultados para avaliar; narrowing
    # agravaria a escassez.
    if quality == "too_narrow":
        return apply_broadening(original_query, previous_results)
    elif quality == "too_broad":
        return apply_narrowing(original_query, previous_results)
    elif quality == "stale":
        # Freshness: mais de 80% dos resultados com mais de 2 anos →
        # validar versão/deprecação antes de confiar no achado.
        return apply_validation(original_query, previous_results)
    elif quality == "shallow":
        return apply_lateral_expansion(original_query, previous_results)
    elif quality == "needs_validation":
        return apply_validation(original_query, previous_results)
    elif quality == "multi_hop":
        return apply_decomposition(original_query, previous_results)
    else:
        return None  # converged
```

**Mapeamento qualidade → estratégia** (heurística operacional):

| Diagnóstico | Condição típica | Estratégia |
|---|---|---|
| `too_broad` | Precision < 0.3 (menos de 3 em 10 resultados relevantes) | A: Narrowing |
| `too_narrow` | Menos de 3 resultados, ou zero resultados relevantes | B: Broadening |
| `stale` | Freshness baixa: mais de 80% dos resultados com mais de 2 anos | D: Validation (buscar versão/deprecação) |
| `shallow` | Precision boa mas Diversity < 2 domínios, ou tudo da mesma fonte | C: Lateral |
| `needs_validation` | Achado importante veio de fonte única não-primária | D: Validation |
| `multi_hop` | Objetivo tem N≥2 restrições/etapas insatisfeitas | E: Decomposition |
| `converged` | Nenhum critério acima dispara | fim do loop |

**Precedência de diagnósticos:** quando `too_narrow` e `too_broad` disparam
juntos (poucos resultados E baixa precisão — ex.: 2 resultados com
precision 0), `too_narrow` tem precedência sobre `too_broad`:
`assess_result_quality` retorna `too_narrow` e a estratégia aplicada é
Broadening, NÃO Narrowing. Justificativa: resultados escassos se beneficiam
mais de broadening (mais resultados para avaliar) do que de narrowing
(menos resultados ainda).

**Critérios de convergência** (qualquer um encerra o loop):

1. **Sem lacunas:** todas as restrições do objetivo foram respondidas com
   confiança ≥ Média (avaliadas na seção 2.4).
2. **Rendimentos decrescentes:** 2 evoluções consecutivas não produziram
   ângulo novo (query evoluída devolveu URLs já vistos).
3. **Orçamento esgotado:** número de evoluções atingiu `--max-evolutions`
   do search.sh. Convergência forçada: relatar qualidade parcial.
4. **Saturação:** novas buscas retornam apenas duplicatas deduplicáveis.

### 2.4 Métricas de Qualidade de Resultado

Como avaliar se uma busca foi boa (usadas pelo `assess_result_quality`):

- **Precision:** resultados diretamente relevantes / total de resultados.
  Alvo: ≥ 0.5. Abaixo de 0.3 → `too_broad`.
- **Diversity:** quantos domínios diferentes (github.com, docs.X.org,
  stackoverflow.com, medium.com). Alvo: ≥ 3 domínios. Abaixo de 2 → `shallow`.
- **Freshness:** proporção de resultados do último ano. Alvo: ≥ 0.5 para
  bibliotecas ativas. Tecnologias instáveis (frameworks JS, LLMs) exigem
  ≥ 0.7. Resultados antigos só são aceitáveis se a fonte é primária e o
  conteúdo é atemporal (RFC, spec).
- **Authority:** proporção de fontes primárias (oficial docs, GitHub oficial)
  vs terciárias (blogs, agregadores). Alvo: ≥ 0.5 para dev. Para segurança
  (seção 1.5), o alvo sobe para ≥ 0.8.
- **Density:** resultados com código executável vs apenas descrições
  textuais. Alvo: ≥ 0.3 para buscas de exemplo/depuração. Densidade baixa →
  priorizar `site:github.com`, `stackoverflow.com`, docs com playground.

Regra de bolso: os três diagnósticos de qualidade mais comuns em busca de dev
são `too_broad` (versão/contexto ausentes), `shallow` (só blog de marketing
sobre a lib) e `needs_validation` (tutorial único sem fonte primária).

### 2.5 Prompts de Evolução (para o LLM)

#### System Prompt para Evolvedor de Queries

```text
Você é um Query Evolver especializado em desenvolvimento de software.
Recebe uma query original, um resumo dos resultados da rodada anterior e o
número da rodada. Sua tarefa: decidir se a pesquisa convergiu ou produzir
a próxima query evoluída.

REGRAS:
1. Diagnostique a qualidade dos resultados com as métricas: Precision,
   Diversity, Freshness, Authority, Density (definidas no documento
   search-prompts.md, seção 2.4).
2. Escolha UMA estratégia de evolução e siga-a estritamente:
   - Narrowing (resultados amplos/genéricos)
   - Broadening (resultados escassos)
   - Lateral Expansion (falta profundidade/diversidade)
   - Validation (achado importante sem verificação)
   - Decomposition (objetivo multi-etapa)
3. A query evoluída deve ser uma string pronta para envio ao buscador —
   com aspas, site:, versões e operadores. NÃO é uma frase de conversa.
4. Preserve a intenção semântica da query original. A evolução muda a
   forma e o escopo, nunca a pergunta que se tenta responder.
5. NÃO introduza vazamento de resposta: a query não pode embutir a resposta
   que você já espera dos resultados.
6. Se a sua crença inicial foi formada por uma fonte única, gere a query de
   FALSIFICAÇÃO dessa crença (busca por contradições, issues, benchmarks
   independentes).
7. Declare convergência SOMENTE quando: não restam lacunas para o objetivo,
   ou duas evoluções seguidas não trouxeram ângulo novo, ou o orçamento de
   evoluções acabou.
8. Ângulos já explorados não podem ser re-propostos. Consulte o resumo de
   rodadas anteriores antes de propor qualquer query.
9. Responda APENAS com JSON válido. Sem texto fora do JSON.

Você está autorizado a piorar temporariamente uma métrica para melhorar
outra (ex.: sacrificar Diversity para ganhar Precision) — mas deve dizer
por quê no rationale.
```

#### Template: Query Evolver

```text
Receba:
{
  "original_query": "{{ORIGINAL_QUERY}}",
  "round_number": "{{ROUND_NUMBER}}",
  "max_evolutions": "{{MAX_EVOLUTIONS}}",
  "goal": "{{OBJETIVO_DA_PESQUISA}}",
  "domain": "{{DOMINIO}}",
  "previous_results_summary": {
    "rounds": [
      {
        "round": "{{N}}",
        "query": "{{QUERY_USADA}}",
        "results_count": "{{N}}",
        "precision": "{{0.0-1.0}}",
        "diversity_domains": ["github.com", "docs.example.com"],
        "freshness": "{{0.0-1.0}}",
        "authority_primary_ratio": "{{0.0-1.0}}",
        "density_code_ratio": "{{0.0-1.0}}",
        "best_findings": ["{{ACHADO_1}}", "{{ACHADO_2}}"],
        "gaps": ["{{LACUNA_1}}", "{{LACUNA_2}}"],
        "explored_paths": ["{{ANGULO_EXPLORADO_1}}"]
      }
    ]
  }
}

Retorne EXATAMENTE:
{
  "evolved_query": "{{QUERY_EVOLUIDA_OU_NULL_SE_CONVERGIU}}",
  "strategy_used": "narrowing|broadening|lateral_expansion|validation|decomposition|null",
  "rationale": "{{JUSTIFICATIVA_CONCISA_1-3_FRASES}}",
  "converged": false,
  "convergence_reason": null
}
```

Notas de uso (substitua os placeholders pelos valores reais antes de
enviar): campos numéricos (`round_number`, `max_evolutions`, `round`,
`results_count`, `precision`, `freshness`, `authority_primary_ratio`,
`density_code_ratio`) preenchidos SEM aspas; `domain` aceita `frontend |
backend | devops | data | ml_ai | mobile | security`; `explored_paths`
nunca re-propõe ângulos já explorados (regra 8 do system prompt). Se
convergiu, retorne `"converged": true`, `"evolved_query": null` e
`"convergence_reason"` com `"sem lacunas" | "rendimentos decrescentes" |
"orçamento esgotado"`.

---

## 3. Prompts de Busca por Domínio

Termos, fontes e armadilhas específicos por área. O domínio é escolhido
pelo sub-agente ao formular as queries — o search.sh NÃO tem a flag
`--domain` (ver seção 4). O domínio tempera o plano de queries e a
avaliação de qualidade (ex.: Freshness pesa mais em ML/AI que em security).

### 3.1 Frontend (React, Vue, Svelte, etc.)

- **Termos de busca:** nomes exatos de hooks/componentes/diretivas
  (`useEffect`, `v-model`, `onMount`), nomes de frameworks + versão
  (`"react" 19`, `"vue" 3.5`, `"svelte" 5`), ferramentas de build
  (`vite`, `webpack`, `esbuild`), CSS (`tailwind` + versão, `css modules`).
- **Fontes recomendadas:** react.dev, vuejs.org, svelte.dev, developer.mozilla.org
  (MDN), caniuse.com (suporte de browser), React/Vue/Svelte GitHub
  (issues + RFCs), tailwindcss.com.
- **Armadilhas comuns:**
  - Frameworks sem versão: um resultado de 2021 sobre hooks é desinformação.
  - `hooks` como termo genérico (React hooks vs git hooks vs lifecycle hooks).
  - Poluição por marketing de biblioteca (tutorial de blog sem base em docs).
  - `caniuse` para APIs novas: checar browser + versão do bundler.

### 3.2 Backend (Node.js, Python, Go, Rust, etc.)

- **Termos de busca:** nome da linguagem + versão (`"python" 3.12`,
  `"go" 1.23`, `"rust" edition 2024`), frameworks web (`express`, `fastify`,
  `fastapi`, `actix-web`), runtime (`node` LTS versão, `deno`), padrões
  (`middleware`, `connection pooling`, `graceful shutdown`).
- **Fontes recomendadas:** docs oficiais de cada linguagem (docs.python.org,
  nodejs.org/docs, go.dev/doc, doc.rust-lang.org), npmjs.com e PyPI (versões
  e deprecation notices), pkg.go.dev, crates.io, GitHub (issues + source).
- **Armadilhas comuns:**
  - Nome do pacote ≠ nome do import (`pydantic` vs `from pydantic` —
    variantes `pydantic v2` quebram o v1).
  - Runtime vs biblioteca: erro de `node` vs erro de pacote.
  - Python 2/3 e `async`/`await` eras misturadas em resultados antigos.
  - Go: `go get` vs `go install` e módulos vs GOPATH (pré-2018).

### 3.3 DevOps (Docker, K8s, CI/CD, Terraform, etc.)

- **Termos de busca:** versões de Kubernetes (`k8s 1.31`), objetos K8s
  (`deployment`, `statefulset`, `ingress`), tools (`docker compose v2`,
  `terraform` + provider + versão, `helm`), CI (`github actions` +
  `runs-on`, `gitlab ci`), infras (`nginx`, `caddy`, `opentelemetry`).
- **Fontes recomendadas:** kubernetes.io/docs, docs.docker.com,
  developer.hashicorp.com/terraform, docs.github.com/actions, helm.sh,
  opencontainers.org (OCI), CNCF (cncf.io) para tendências.
- **Armadilhas comuns:**
  - Kubernetes muda rápido: guia para 1.20 é desinformação em 1.31.
  - Cloud vendors divergem do vanilla K8s (EKS/GKE/AKS têm diferenças reais).
  - YAML que "parece certo": validar contra schema oficial.
  - `docker-compose` (v1, deprecated) vs `docker compose` (plugin v2).

### 3.4 Data (SQL, NoSQL, ETL, Analytics, etc.)

- **Termos de busca:** engine + versão (`"postgresql" 16`, `"mysql" 8.4`,
  `"sqlite" 3.45`), features (`window functions`, `CTE`, `jsonb`, `vector`),
  NoSQL (`mongodb` + versão, `redis`, `dynamodb`), pipeline (`dbt`,
  `airflow`, `kafka`, `clickhouse`).
- **Fontes recomendadas:** docs oficiais de cada engine (postgresql.org/docs,
  dev.mysql.com, mongodb.com/docs, clickhouse.com/docs), dbt docs,
  kafka.apache.org, jepsen.io (análises de consistência), EXPLAIN/plans.
- **Armadilhas comuns:**
  - SQL não é portável: `LIMIT` vs `TOP`, `ILIKE`, funções de window —
    sempre citar o engine.
  - `NoSQL` é guarda-chuva: resultados de Redis nada dizem sobre MongoDB.
  - Benchmarks de banco sem hardware/metodologia não valem nada.
  - Sintaxe nova (ex.: `JSON` type do Postgres) vs strings JSON.

### 3.5 ML/AI (LLMs, embeddings, vector DBs, RAG, etc.)

- **Termos de busca:** modelos + data (`"claude" 4`, `"gpt-4o"`, `"llama" 3.3`),
  técnicas (`RAG`, `embeddings`, `fine-tuning`, `function calling`, `MCP`),
  vector DBs (`pgvector`, `qdrant`, `milvus`, `weaviate`), frameworks
  (`langchain`, `llamaindex`, `pytorch`, `transformers`).
- **Fontes recomendadas:** docs dos provedores (docs.anthropic.com,
  platform.openai.com, ai.google.dev), Hugging Face (model cards),
  arXiv (paper original), docs de vector DBs, pytorch.org.
- **Armadilhas comuns:**
  - Área mais sujeita a hype: "RAG" e "agents" estão poluídos por marketing —
    exigir fontes primárias e datas (semana!).
  - Modelos e preços mudam em meses: verificar na fonte oficial a data.
  - Termo `vector database` mistura pgvector (extensão) com engines dedicados.
  - Benchmarks de LLM sem detalhe de prompting/hardware são inúteis.

### 3.6 Mobile (React Native, Flutter, Swift, Kotlin, etc.)

- **Termos de busca:** framework + versão (`"react-native" 0.76`,
  `"flutter" 3.27`), plataforma específica (`iOS` vs `Android`), APIs de
  plataforma (`push notifications`, `in-app billing`), build (`xcode`,
  `gradle` + versão, `fastlane`).
- **Fontes recomendadas:** reactnative.dev, flutter.dev, developer.apple.com
  (documentation), developer.android.com, docs de CI mobile, App Store /
  Play Store review guidelines.
- **Armadilhas comuns:**
  - Docs de iOS e Android têm versões diferentes da mesma feature.
  - Exemplos de emulador não funcionam em device (permissões, push).
  - Regras de review das lojas mudam: buscar no site oficial do ano corrente.
  - `flutter` vs `flutter web` vs `flutter desktop` têm comportamentos
    divergentes.

### 3.7 Security (OWASP, Auth, Encryption, etc.)

- **Termos de busca:** padrões + versão (`"owasp" top 10 2021`,
  `"oauth" 2.1`, `"oidc"`, `"passkeys"`), primitivas cripto (`"argon2"`,
  `"chacha20-poly1305"`), libs (`bcrypt`, `jwt`, `openssl`), headers
  (`csp`, `hsts`, `csrf token`).
- **Fontes recomendadas:** owasp.org (cheat sheets!), NIST SP 800-63/800-175,
  RFCs (IETF), CVE.org e OSV.dev, GitHub Security Advisories, bulletins
  de linguagem (rustsec.org, PyPA, npm advisory), portswigger research.
- **Armadilhas comuns:**
  - Tutorial de segurança de 2020 pode recomendar prática já quebrada
    (ex.: `SHA-1` para senhas, JWT sem `aud`/`exp`).
  - `encryption` é ambíguo: at-rest vs in-transit — sempre especificar.
  - `auth` vs `authorization` misturados nos resultados.
  - Hash vs encryption vs encoding: termos trocados em blogs ruins —
    exigir fonte primária (NIST, OWASP, RFC).

---

## 4. Integração com search.sh

> **Nota de precedência:** a interface PRIMÁRIA é `search.sh`
> ({{SKILL_HOME}}/scripts/search.sh) — a fonte da verdade para flags e
> comportamento; `brave-search.sh` é a implementação do Tier 2 (API Brave,
> parsing, flags CLI) e só deve ser chamado diretamente em testes isolados
> do tier. Este documento é a camada de estratégia (COMO formular e
> avaliar buscas); o search.sh é a camada de execução (fallback 3-tier:
> surf-skill → Brave → DDG keyless). Se houver divergência entre este
> documento e o search.sh, o script vence — este documento deve ser
> atualizado na onda de skill-update.

O script **não** implementa os templates, estratégias e diagnósticos deste
documento internamente. A relação real é a seguinte:

- **`--dev-mode`** NÃO ativa os templates da seção 1. Ele apenas adiciona
  keywords de desenvolvimento ("documentation example", "API reference",
  "best practice 2025 2026", "github", "tutorial") aos sufixos usados na
  evolução de queries quando os resultados são bons (feedback "good").
- **A evolução de perguntas do script (loop de `--max-evolutions`) é um
  algoritmo heurístico simples**, não o Query Evolver (2.5) nem as
  estratégias da seção 2 — não há LLM no loop. A cada rodada o script
  classifica os resultados (`empty` / `few` / `lowq` / `good`) e reescreve
  a query mecanicamente:
  - `empty` (zero resultados) → corta a query nas 3 primeiras palavras.
    ATENÇÃO (fallback 3-tier): resultado vazio NÃO é prova de inexistência —
    o tier que respondeu pode ter degradado (ex.: apenas Tier 3 DDG, que é
    Instant Answer, não full-text). Registre o tier efetivo no handoff e,
    se um tier melhor estava indisponível, não declare "nada encontrado"
    como fato;
  - `few` (menos da metade do `--count`) → remove a última palavra;
  - `lowq` (maioria sem descrição) → adiciona "best practice";
  - `good` → adiciona um sufixo rotativo ("guide", "tutorial", "example",
    "overview"; com `--dev-mode`, os sufixos de dev listados acima).
  O Query Evolver (2.5) e as estratégias da seção 2 continuam valendo como
  referência para sub-agentes que evoluem queries MANUALMENTE (fora do
  loop do script) e para avaliar os resultados que o script retorna — não
  como descrição do loop interno do script.
- **Os domínios (seção 3) NÃO são ativados por flag** — o script não tem a
  flag `--domain` (o conjunto real de flags está na seção de Ajuda do
  script: `--task`, `--goal`, `--insights`, `--deliverable`, `--brief-file`,
  `--count`, `--freshness`, `--country`, `--search-lang`, `--offset`,
  `--result-filter`, `--max-evolutions`, `--dev-mode`, `--timeout`,
  `--json`). A seção 3 é referência para o sub-agente formular as queries
  do domínio manualmente (termos, fontes e armadilhas) antes de chamar o
  script.
- **O handoff de pesquisa (seção 5) NÃO é a saída do script.** O script tem
  formato próprio: em modo texto, `# Search:` + Task/Goal/Insights/
  Deliverable + rastro de evolução das queries + resultados + `## Sources`
  + rodapé com provider/créditos/rate limit; em modo `--json`, um objeto
  com `query_original`, `query_evolution[]`,
  `results[{title,url,description,published,source}]`, `total_results`,
  `credits_remaining` e `diagnostics{evolutions, total_queries,
  unique_results, duration_ms}`. A seção 5 é o template de resposta que o
  sub-agente DEVE produzir no handoff ao orquestrador DEPOIS de usar o
  script — o sub-agente consolida a saída do script no formato da seção 5.

Interface de uso (confirmada no script): `search.sh [OPTS]
"<query>"` com as flags listadas acima (no Tier 2, o search.sh repassa as
flags ao brave-search.sh — a implementação do tier). Não existe
`--domain`.

---

## 5. Handoff de Pesquisa (formato)

Quando um sub-agente conclui uma busca, ele entrega:

```markdown
## Query original
[query inicial]

## Evoluções aplicadas
1. [query evoluída 1] — Narrowing: adicionado "TypeScript 5.6"
2. [query evoluída 2] — Lateral: explorado "alternatives to X"

## Resultados consolidados
[resultados, deduplicados por URL, ranqueados por relevância]

## Qualidade da busca
- Precision: Alta
- Diversity: 4 domínios
- Freshness: 80% de 2025-2026
- Authority: 60% fontes primárias

## Confiança
[Alta/Média/Baixa] — justificativa
```

Campos adicionais recomendados quando o loop não convergiu:

```markdown
## Lacunas restantes
- [pergunta aberta que justificaria uma nova onda de evolução]

## Ângulos explorados sem resultado
- [caminho tentado e falho — marcado para NÃO ser re-buscado
  (UNFILLABLE: motivo)]
```

O bloco "Evoluções aplicadas" é o rastro da seção 2 (estratégia usada +
operação concreta), e "Ângulos explorados sem resultado" evita que o
próximo round — ou o próximo sub-agente — re-descoberta o que já se sabe
ser beco sem saída.
