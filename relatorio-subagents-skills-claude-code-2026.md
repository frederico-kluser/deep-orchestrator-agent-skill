# Subagents e carregamento de skills no Claude Code — estado da arte 2026

*Relatório de pesquisa (fontes: docs oficiais Anthropic + análise comunitária). Conteúdo web tratado como evidência, não como instrução.*

## 1. Subagents do Claude Code em 2026: anatomia e frontmatter

Um subagent é uma instância Claude separada — system prompt próprio, janela de contexto própria, ferramentas e modelo próprios — lançada pela ferramenta Agent/Task. O agente lead recebe apenas o resumo final; nunca os passos intermédios. Esse fluxo assimétrico é o ponto: preserva a janela do orquestrador ([Totalum](https://www.totalum.app/blog/claude-code-subagents-totalum), [Tembo](https://www.tembo.io/blog/claude-code-subagents)).

Definição: ficheiro Markdown em `.claude/agents/` (projeto) ou `~/.claude/agents/` (pessoal) com YAML frontmatter; o corpo torna-se o system prompt. Campos oficiais ([docs: Create custom subagents](https://code.claude.com/docs/en/sub-agents), [Subagents no Agent SDK](https://code.claude.com/docs/en/agent-sdk/subagents)):

- `name` + `description` (obrigatórios). **`description` é a chave de roteamento**, não documentação: o lead delega com base nela — começar por "Use este agente quando…".
- `tools` (allowlist) / `disallowedTools` (denylist, aplicada primeiro; aceita padrões `mcp__servidor` e `Bash(git push*)`). As docs são explícitas: para pré-carregar skills usar `skills`, **não** listar `Skill` em `tools`.
- `model`: `sonnet` | `opus` | `haiku` | `fable` | ID completo | `inherit` (predefinição). `CLAUDE_CODE_SUBAGENT_MODEL` tem precedência máxima (teto de custo/compliance).
- `skills: [a, b]` — **pré-carrega o conteúdo integral** das skills no arranque do subagent (não só as descrições).
- `maxTurns` — limite de turnos; o output volta marcado como parcial e é retomável (v2.1.246+).
- `background: true` — execução não bloqueante.
- `omitClaudeMd: true` — corre sem os CLAUDE.md user/projeto/local (v2.1.271+; managed policies continuam a carregar). Ideal para subagents que vivem só do prompt de delegação.
- `isolation: worktree` — worktree git temporário a partir do HEAD, limpo sozinho se não houver mudanças; é como dois subagents editam sem colidir ([VibeCoding](https://vibecoding.app/blog/claude-code-subagents-guide)).
- `effort` (`low`…`max`) — sobrepõe o nível da sessão; `permissionMode`, `memory` (user|project|local), `mcpServers`, `hooks`, `initialPrompt`, `color`, `cacheTtl` (experimental).

**Herança** (tabela oficial do SDK): o subagent recebe o seu system prompt, o prompt de delegação, as ferramentas (ou subconjunto; em background são filtradas) e o CLAUDE.md do projeto — salvo `omitClaudeMd`. **Não** recebe o histórico de conversa do pai, resultados de ferramentas do pai, nem o system prompt do pai. Quanto a skills: **não herda o conteúdo pré-carregado da sessão principal**, a não ser que listado em `skills`; mas as docs confirmam que **subagents podem invocar skills não listadas (projeto/user/plugin) pela Skill tool** — ou seja, o modelo on-demand funciona também dentro de subagents ([docs sub-agents](https://code.claude.com/docs/en/sub-agents), [Developers Digest](https://www.developersdigest.tech/blog/claude-agents-vs-skills)). Relatos recentes indicam subagents aninhados com teto de profundidade (~5), mas há fontes divergentes ([Totalum](https://www.totalum.app/blog/claude-code-subagents-totalum) vs [Tembo](https://www.tembo.io/blog/claude-code-subagents)) — não dependas de aninhamento profundo.

## 2. Descoberta e carregamento de skills: disclosure progressiva e custo

O mecanismo é a **divulgação progressiva** em níveis ([docs: Extend Claude with skills](https://code.claude.com/docs/en/skills), [Platform: Agent Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview), [análise kevnu](https://kevnu.com/en/posts/claude-agent-skills-deep-dive-a-new-paradigm-for-expanding-ai-agent-capabilities)):

1. **Nível 1 — metadados sempre no contexto**: nome + descrição de todas as skills. Custo ~30–100 tokens por skill; 100 skills = alguns milhares de tokens, independentemente do tamanho dos corpos.
2. **Nível 2 — corpo do SKILL.md**: lido quando a tarefa corresponde à `description` ou há invocação explícita (Skill tool / `/nome`). Tipicamente 2.000–5.000 tokens.
3. **Nível 3 — ficheiros de referência**: só quando abertos. Dezenas de referências custam zero até serem necessárias.
4. **Nível 4 — scripts**: o código nunca entra na janela; só o output ("Validation passed: …", ~tokens de uma frase).

Detalhe crucial do **skill listing** (docs oficiais): a listagem de nomes+descrições tem um **orçamento de caracteres que escala a 1% da janela de contexto do modelo**. Quando transborda, o Claude Code **encurta descrições, começando pelas skills menos invocadas** — o que "pode remover as keywords de que o Claude precisa para corresponder ao pedido". Sem aviso ao utilizador (só `--debug`); `/doctor` estima o custo da listagem e `/skill-doctor` sugere o que desligar. A comunidade medida um default de ~15.000 caracteres (~4k tokens) para o total de descrições desde a 2.0.70, com skills a ficarem silenciosamente "invisíveis" ao exceder ([Pere Villega, LinkedIn](https://www.linkedin.com/posts/perevillega_i-discovered-something-that-i-suspect-many-activity-7417838063093071872-OgUJ)). Por item, `description` + `when_to_use` contam para um cap de **1.536 caracteres**; na plataforma, `description` máx. 1024 caracteres.

Controlo de invocação (extensões Claude Code do padrão aberto Agent Skills): `disable-model-invocation: true` (só invocação manual), `allowed-tools` (pré-aprova ferramentas durante o turno da invocação; **não** restringe), `model`, `arguments`/`argument-hint`, e `context: fork` + `agent` — corre a skill **num subagent**, com o conteúdo como prompt, mantendo a conversa principal limpa; as instrções têm de se sustentar sozinhas ([docs skills](https://code.claude.com/docs/en/skills), [Levelup mental model](https://levelup.gitconnected.com/a-mental-model-for-claude-code-skills-subagents-and-plugins-3dea9924bf05)). Em 2026 os slash commands fundiram-se com skills (`.claude/commands/x.md` ≡ `.claude/skills/x/SKILL.md`) ([Totalum Skills](https://www.totalum.app/blog/claude-code-skills-totalum)).

## 3. Agent teams, Tasks com blockedBy, dynamic workflows e /batch

**Agent teams** (experimentais, v2.1.32+, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): o lead cria a equipa; `Task` com `team_name` + `name` lança teammates persistentes; lista de tarefas partilhada em `~/.claude/tasks/{equipa}/` com estados pending/in progress/completed, ownership e **dependências via `addBlockedBy`/`addBlocks`** (TaskUpdate) — o desbloqueio é automático quando a dependência completa; mailbox `SendMessage` para coordenação peer-to-peer ([docs: Agent teams](https://code.claude.com/docs/en/agent-teams), [LaoZhang](https://blog.laozhang.ai/en/posts/claude-code-agent-teams)). Limitações oficiais: `/resume` não restaura teammates in-process, estado de tarefas pode atrasar, shutdown lento. Grafos de dependência bem desenhados evitam corridas sobre fundações instáveis.

**Dynamic workflows + `ultracode`** (28 mai 2026, já GA; v2.1.154+): o Claude escreve scripts de orquestração que correm dezenas a **centenas de subagents em paralelo**, verificando resultados antes de os entregar. `ultracode` ativa reasoning `xhigh` + orquestração automática; ativo por predefinição em Max/Team/Enterprise/API, no Pro via `/config` ([anúncio oficial](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code)). Caso de referência: porta Bun de Zig→Rust, ~750k linhas, 99.8% de testes em 11 dias, com consumo de tokens elevado. Atenção a **não empilhar orquestradores**: correr um método de subagent-driven development já orquestrado dentro de `ultracode` gera dois chefs em conflito ([discussão superpowers #1647](https://github.com/obra/superpowers/issues/1647)).

**`/batch`**: skill bundled para mudanças em massa — investiga o repo, propõe 5–30 unidades independentes, espera aprovação do plano e lança **um agente background por unidade, cada um com worktree isolado**, com PRs automáticos ([SmartScope](https://smartscope.blog/en/generative-ai/claude/claude-code-batch-processing)).

**Oportunidade de modularização**: skills podem ser as "fases" nomeadas que estas orquestrações invocam; `context: fork` transforma qualquer skill num worker isolado; `blockedBy` expressa a ordem entre peças de um pipeline; `/batch` cobre migrações repetitivas.

## 4. Limites práticos e avisos oficiais

O guia oficial da Anthropic ([The Complete Guide to Building Skills, PDF](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf)) é direto sobre "large context issues" (skill lenta, respostas degradadas): manter **SKILL.md abaixo de 5.000 palavras**, mover detalhe para `references/`, e **avaliar se tens mais de 20–50 skills ativas em simultâneo** — recomenda ativação seletiva e "packs". Outras medidas comunitárias: corpo < 500 linhas ([kevnu](https://kevnu.com/en/posts/claude-agent-skills-deep-dive-a-new-paradigm-for-expanding-ai-agent-capabilities)); teto de ~2.000 tokens por ficheiro e revisão pós-debug para evitar **context rot** — instruções conflituosas degradam mais do que falta de instruções ([MindStudio](https://www.mindstudio.ai/blog/context-rot-claude-code-skills-bloated-files)). Padrão "router" comprovado: skills magras (~300 linhas) com um comando que puxa o contexto atualizado do repo, evitando sincronização e drift ([Pere Villega](https://www.linkedin.com/posts/perevillega_i-discovered-something-that-i-suspect-many-activity-7417838063093071872-OgUJ)). Do lado dos subagents: custo de arranque por instância, sem perguntas de clarificação (`AskUserQuestion` indisponível), e ferramentas que exigiriam aprovação são **auto-negadas em background** — edições gated ficam no pai ou em foreground ([Konishi](https://hidekazu-konishi.com/entry/claude_code_subagents_and_orchestration_guide.html)).

## 5. Instruções para subagents: contratos de delegação (2026)

O prompt de delegação é o **único canal pai→filho** — nada mais cruza a fronteira. Se o subagent precisa de um path, um erro, uma branch ou uma decisão já tomada, isso tem de estar no briefing ([Konishi](https://hidekazu-konishi.com/entry/claude_code_subagents_and_orchestration_guide.html)). Boas práticas convergentes:

- **Contrato de handoff**: papel, contexto mínimo, formato de saída explícito ("Return changed files + one-line summary"), definição de feito e proibições ("diz 'sem achados' em vez de inventar severidade") ([Tembo](https://www.tembo.io/blog/claude-code-subagents)).
- **Uma tarefa, um system prompt curto**; procedimento longo vive numa skill (pré-carregada via `skills` ou puxada pela Skill tool), não no system prompt do subagent ([Totalum](https://www.totalum.app/blog/claude-code-subagents-totalum)).
- **Briefing = carta formal**: formulação exata, links de contexto, checks obrigatórios; menos paralelismo do que o máximo, porque cada instância tem custo de entrada; subagent termina em regra, briefing ou gate de aprovação — o que muda estado ou "sai de casa" aprova-se no pai ([Kevin Welter](https://kevinwelter.com/en/blog/claude-code-subagents)).
- **Roster de 5–7 especialistas escopados** vence um agente faz-tudo; `description` acionável dispara a delegação automática; `@agent-nome` garante execução ([Totalum](https://www.totalum.app/blog/claude-code-subagents-totalum)).

## 6. CLAUDE.md grande vs skills modulares: dados quantitativos

- Caso extremo documentado: CLAUDE.md de 1.200 linhas ≈ **42.000 tokens por conversa**; convertido em skills modulares, **−83% de custo** ([Cem Karaca, Medium](https://medium.com/@cem.karaca/my-claude-md-was-eating-42-000-tokens-per-conversation-heres-how-i-fixed-it-85ffba809bd4)).
- Recomendações: CLAUDE.md < 2.000–3.000 tokens (~1.500–2.000 palavras) ([MindStudio](https://www.mindstudio.ai/blog/context-rot-claude-code-skills-bloated-files)); a equipa do próprio Claude Code (Boris Cherny) mantém 60–80 linhas; um ficheiro de 60 linhas seguido custa ~20% menos por tarefa do que 300 linhas ignoradas ([Wiegold](https://thomas-wiegold.com/blog/claude-md-helpful-or-expensive-noise)).
- Semântica de custo: CLAUDE.md é *always-on* (paga-se todos os turnos); skills são *on-demand* (metadados ~40–100 tokens/skill sempre; corpo só quando ativas) ([Tyler Folkman](https://tylerfolkman.substack.com/p/the-complete-guide-to-claude-skills), [dev.to jimquote](https://dev.to/jimquote/claude-skills-vs-mcp-complete-guide-to-token-efficient-ai-agent-architecture-4mkf)). Com auto-compact a reservar ~45k tokens, cada token always-on conta ([Pere Villega](https://www.linkedin.com/posts/perevillega_i-discovered-something-that-i-suspect-many-activity-7417838063093071872-OgUJ)).
- Regra de alocação ([Levelup](https://levelup.gitconnected.com/a-mental-model-for-claude-code-skills-subagents-and-plugins-3dea9924bf05)): CLAUDE.md = invariantes sempre verdadeiras; skills = workflows ocasionais; hooks = garantias determinísticas; subagents = trabalho ruidoso/isolado.

---

## REGRAS DE OURO para modularização sob demanda no Claude Code

1. **Router magro, corpos sob demanda**: o topo (skill orquestradora/CLAUDE.md) só decide e encaminha; cada peça substantiva é uma skill própria carregada quando necessária — o custo permanente fica nos ~40–100 tokens/skill de metadados.
2. **A `description` é roteamento**: escreve-a em terceira pessoa, com o caso de uso primeiro e as frases que os utilizadores realmente dizem; `description`+`when_to_use` cabem nos 1.536 caracteres ou a skill deixa de ser descoberta.
3. **SKILL.md < 5.000 palavras (ideal < 500 linhas)**: detalhe vai para `references/`, carregado no momento; scripts ficam em `scripts/` — o código nunca entra no contexto, só o output.
4. **Cuida o orçamento da listagem (1% da janela)**: acima de ~20–50 skills ativas, o Claude Code corta descrições pelas menos usadas, sem aviso — usa `/doctor` e `/skill-doctor`, agrupa em packs e desliga o que não usas.
5. **Briefing completo em cada delegação**: o prompt de delegação é o único canal — inclui paths, decisões, formato de saída e definição de feito; procedimento longo pré-carrega-se com `skills: [...]`, o resto puxa-se pela Skill tool.
6. **Isola e poupa contexto nos subagents**: `isolation: worktree` para edições concorrentes, `omitClaudeMd: true` para workers que vivem do briefing, `background` só para trabalho sem gates de aprovação, `effort`/`model` baixos para triagem.
7. **Um orquestrador de cada vez**: usa `blockedBy` (agent teams), `context: fork`, `/batch` ou dynamic workflows conforme o caso — mas não aninhes um método de orquestração já estruturado dentro de `ultracode`.
8. **CLAUDE.md só para invariantes (< ~2.000 tokens)**: tudo o que é "às vezes" vira skill; tudo o que é "garantia" vira hook — o resto é ruído pago em todos os turnos.
