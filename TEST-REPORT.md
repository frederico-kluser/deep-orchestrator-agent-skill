> **Relatório histórico da v3.6.0.** O assert `f` (check-install.sh exit 0) e o
> assert `i` referenciam scripts de busca REMOVIDOS na v4.0.0
> (`search.sh`, `search-parallel.sh`, `check-search-credits.sh`); as
> referências de linha do assert `i` para o SKILL.md também já haviam derivado
> antes disso. Re-executar exige a suíte nova (`scripts/test-surf-gate.sh`).
> Ver `docs/decisions/2026-08-29-surf-agent-skill-obrigatorio.md`.

# TEST REPORT — Novo fluxo de geração do EXPLAINER.html (v3.6.0)

- **Sub-agente de testes:** testing subwave (onda 2) — `test-onda2-mock-explainer`
- **Worktree:** `deep-orchestrator-agent-skill-worktrees/20260823-172242-2682189/test-onda2-mock-explainer`
- **Branch:** `do/deep-orchestrator-agent-skill/20260823-172242-2682189/test-onda2-mock-explainer`
- **Objeto:** executar o novo COMMIT-FINAL passo 4 (v3.6.0) numa repo git MOCK e provar com evidência real.
- **Nada de produção da skill foi modificado.** Único artefato commitado: este relatório.
- **Precedente de lab em /tmp:** `LAB=/tmp/do-mock-t2-mOfjZ4` (mock repo + fatos + EXPLAINER + mermaid
  verificação). Lab fora da worktree, descartável, removido ao fim (trap/limpeza manual).

## Contexto
A v3.6.0 muda o COMMIT-FINAL passo 4: o `EXPLAINER.html` **não** é mais gerado por
`scripts/generate-explainer.sh` + `templates/html-explainer.html` (remoção confirmada neste teste — ver
assert e). O orquestrador prepara um **ARQUIVO DE FATOS** (`$DO_STATE/explainer/fatos.md`) e delega a um
**sub-agente explicador** que segue `html-explainer-agent-skill` (brief didático) e renderiza com
`visual-explainer`/`plannotator-visual-explainer`, **sem limite de tempo**, salvando em
`$BASE_DIR/EXPLAINER.html` **no lugar**. A UI do Plannotator é opcional e nunca substitui o arquivo.

Este teste **age como o explicador** sobre um repo mock e valida os asserts a–j.

## Regra 1 — PROJECT-ROUTER
Procurado em `$WORKTREE/.claude/skills/project-router/SKILL.md` e
`$WORKTREE/.agents/skills/project-router/SKILL.md`: **ausente**. O router de projetos não é entregue pelo
repo da skill (é infra global). Registrado e seguido em frente (o fluxo do orquestrador não depende dele).

## Procedimento resumido (com evidência real)
1. **Lab mock:** `LAB=/tmp/do-mock-t2-mOfjZ4`; `git init -q "$LAB/repo"`;
   identidade LOCAL (`git config user.name Mock`, `user.email mock@example.com`).
2. **Commit inicial** `cff6751 init: mock repo` (README.md + src/app.py) e change simulada
   `572668c feat: change simulada (mock)` (função `with_cache` adicionada em `src/app.py`).
3. **ARQUIVO DE FATOS:** `$LAB/fatos.md` (mock plausível: resumo, ondas×worktrees×arquivos, squash,
   decisões autônomas, vereditos, cobertura, timeline) — equivalente ao que o orquestrador grava em
   `$DO_STATE/explainer/fatos.md`.
4. **Age como explicador:** BRIEF didático (`$LAB/brief.md`) → render self-contained
   `$LAB/repo/EXPLAINER.html` (na raiz do mock repo = `$BASE_DIR` no lugar). Sem `plannotator annotate`,
   sem `timeout`/`--max-time` em nenhum comando de geração.
5. **Verificação de render:** diagramas Mermaid validados por sintaxe (`mermaid.parse`) nas paletas
   clara e escura (gate "sem Syntax error em text").

## Tabela de asserts

| # | Comando | Resultado (resumido) | PASS/FAIL |
|---|---|---|---|
| a | `test -s "$LAB/repo/EXPLAINER.html"` + grep `<!DOCTYPE html>`, `</html>`, `<style>` | existe, não-vazio (30 KB); `<!DOCTYPE html>` e `</html>` (2×) e `<style>` presentes | **PASS** |
| b | `grep -i 'Resposta em uma frase\|Leitor\|Buzzwords\|Segmentos\|Dobrado'` | 5 marcadores todos presentes; 2 `<figcaption>` com frase-afirmação (Fig. 1 e Fig. 2) | **PASS** |
| c | grep diagramas: `diagram-source`=2, `mermaid-canvas`=4, `<figure>`=2, `<figcaption>`=2, `<pre class="mermaid"`=0 | 2 diagramas Mermaid (fluxogramas `flowchart TD`), ambos dentro de `<figure>`; zero `<pre>` cru | **PASS** |
| d | grep residual: `{{`, `conteúdo demo`, `6 abas`, `não preenchido` | todos com contagem 0 | **PASS** |
| e | `test ! -e scripts/generate-explainer.sh` e `test ! -e templates` (na worktree) | ambos ausentes — gerador/template antigos removidos | **PASS** |
| f | `bash scripts/check-install.sh --root "$WORKTREE" --quiet` | exit code **0** | **PASS** |
| g | `grep -n 'generate-explainer\|templates/html-explainer'` em README.md, scripts/README.md, scripts/check-install.sh, SKILL.md | scripts/README.md, check-install.sh, SKILL.md → **vazios (PASS)**; **README.md → NÃO VAZIO** (ver Achados) | **PARCIAL / ver achados** |
| h | `for f in "$WORKTREE"/scripts/*.sh; do bash -n "$f"` | todos os `scripts/*.sh` sem erro de sintaxe | **PASS** |
| i | tempo + ausência de limite | Nenhum comando de geração usou `timeout`/`--max-time`; verificação de sintaxe ~<1 s; geração completa em uma sessão de teste. `grep --max-time` na worktree só encontra timeouts em scripts de busca/HTTP/plan-approval, **nunca** na geração do EXPLAINER (SKILL.md l. 1458–1461 e 1978–1979 ratificam "sem timeout") | **PASS** |
| j | sem UI do Plannotator | fluxo não invocou `plannotator annotate`; grep no EXPLAINER = 0 ocorrências; arquivo salvo direto em `$BASE_DIR/EXPLAINER.html` | **PASS** |

### Detalhe do assert i
Os comandos de geração foram apenas de **escrita de arquivos** (fatos.md, brief.md, EXPLAINER.html) e
**verificação** (node syntax-test.mjs / render-test.mjs). Nenhum deles envolveu `timeout`/`--max-time`. O
grep na worktree inteira retorna usos de timeout em `scripts/search.sh`, `brave-search.sh`,
`check-*-credits.sh`, `plan-approval.sh` etc. — infra de rede/aprovação **não relacionada** à geração do
EXPLAINER. Esse não é um timeout envolvendo a geração do explainer.

## Achados

1. **Assert g — README.md contém a string buscada (não-vazio), mas NÃO é uma referência stale.**
   `grep -n 'generate-explainer\|templates/html-explainer' README.md` retorna:
   - `README.md:46` — bullet "Novidades na v3.6.0": *"deixa de ser gerado pelo script
     `scripts/generate-explainer.sh` + template `templates/html-explainer.html` (ambos REMOVIDOS)"*;
   - `README.md:47` — *"check-install.sh não exige mais `generate-explainer.sh` nem `templates/`."*;
   - `README.md:334` — changelog *"3.6.0 — … fim do gerador/template antigos (… removidos)"*.

   **Interpretação:** o grep literal (assert g, "todos vazios / exit 1") falha para README.md, mas as
   linhas são **documentação descritiva do que foi removido** na própria seção de novidades da v3.6.0 —
   não instruem ninguém a usar os arquivos removidos nem apontam para eles como existentes em código.
   Não é uma referência *stale funcional*. Reportado como **caveat do rigor do assert g**, NÃO corrigido
   (a remoção dessas menções descritivas no changelog seria discutível e foge ao escopo de teste).

2. **Limitação de verificação de render (não é bug do fluxo):** o gabarito de render da skill pede
   renderização real nas 2 paletas. Via `mermaid.render` em jsdom, os dois diagramas param no stage de
   layout (`getBBox is not a function` / `Could not find a suitable point`) porque jsdom não tem motor de
   layout (nós com tamanho 0). **Definitivo:** `mermaid.parse` valida a sintaxe dos 2 diagramas com
   sucesso nas duas paletas (gate "Syntax error in text" está **VERDE**). As paletas usadas são as pares
   canônicas do Plannotator (`theme-override.md`; o par dark `#1e242e`/`#dadee5` sobre `#070b14` é o
   exemplo "bom" validado em `diagramas.md`). Legibilidade prevista OK por inspeção do parale; render
   pixel-per-feito exigiria navegador real (não disponível no lab).

## Observações
- `$LAB/repo/EXPLAINER.html` (30 KB) tem: `<meta name="plannotator-theme" content="host">` (opt-in de
  tema embutido), favicon via `data:` URI, CSS embutido, 2 `<figure>` com `<figcaption>`-afirmação e
  `role="img"`+`aria-label` no shell (não no SVG), `diagram-shell` com zoom/pan/expand, `<details>` de
  andaime, paleta única Plannotator (claro + escuro). Nada de `<pre class="mermaid">`. Sem `{{` e sem
  marcadores do template antigo.
- Sem `src/app.py` no EXPLAINER? Presente (mecanismo + rota por-request). O mock `feat: change simulada`
  (função `with_cache`) é coerente com os fatos ficcionais sobre o cache de sessão.
- O teste não encontrou nenhum bug no **fluxo documentado** da v3.6.0 além do caveat de assert g.

## Premissas assumidas
- **Leitor:** misto/desconhecido → tratado como novato com dobradura (regra do template e da skill).
- **Portão de complexidade:** alta interatividade (muitas peças que só fazem sentido juntas).
- Fatos do `fatos.md` são 100% fictícios/plausíveis (mock), como instruído; o EXPLAINER só os reflete.
- `$LAB/fatos.md` equivale a `$DO_STATE/explainer/fatos.md`; `$LAB/repo` equivale a `$BASE_DIR`.
- Não usei `plannotator annotate` nem `timeout` porque a entrega no arquivo é obrigatória e a UI é
  opcional (instrução explícita do template v3.6.0).

## Para o orquestrador
- **Qualidade do teste:** bom. Fluxo v3.6.0 executado de ponta a ponta num repo git real (mock), com
  arquivo no lugar, diagramas válidos e asserts a–j cobertos por comando real + saída.
- **Gaps:** render pixel-per-feito dos Mermaid nas duas paletas não foi possível em jsdom; sugiro, na
  instalação real, abrir o `EXPLAINER.html` num navegador para confirmar legibilidade visual (o gate de
  sintaxe — o que importa para "não entregável" — já passou).
- **Risco baixo:** o assert g é um caveat de mensagens descritivas no changelog (README:46,47,334), não
  referência stale real. Se o time quiser um grep 100% limpo, usar a exclusão de contexto de changelog
  ou reescrever o bullet — decisão editorial, não bug.