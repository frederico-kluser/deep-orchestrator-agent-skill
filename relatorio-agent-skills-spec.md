# Relatório: Especificação oficial e boas práticas de "Agent Skills"

> Pesquisa realizada com a skill Tavily (8 queries, depth advanced). Conteúdo web tratado como evidência não-confiável; todas as afirmações estão citadas pelas respetivas URLs.

## 1. Spec oficial de uma Agent Skill (frontmatter e variações entre harnesses)

Uma Agent Skill é um **diretório com um `SKILL.md` obrigatório**, seguido de ficheiros opcionais. A especificação aberta vive em [agentskills.io/specification](https://agentskills.io/specification) e define o frontmatter YAML assim:

| Campo | Obrigatório | Restrições |
| --- | --- | --- |
| `name` | Sim | Máx. 64 caracteres; só minúsculas, números e hífens; não começa/termina com hífen; sem `--`; deve igualar o nome da pasta |
| `description` | Sim | Máx. 1024 caracteres; descreve **o que a skill faz e quando usar** |
| `license` | Não | Nome da licença ou referência a ficheiro incluído |
| `compatibility` | Não | Máx. 500 caracteres; requisitos de ambiente (produto alvo, pacotes de sistema, rede) |
| `metadata` | Não | Mapa livre de pares chave-valor (`author`, `version`, etc.) |
| `allowed-tools` | Não | String separada por espaços de ferramentas pré-aprovadas (ex.: `Bash(git:) Bash(jq:) Read`) — **experimental**, suporte varia entre agentes |

O corpo é Markdown sem restrições de formato; a spec recomenda passos, exemplos de entrada/saída e casos-limite ([agentskills.io](https://agentskills.io/specification)). O campo `when_to_use` **não faz parte da spec aberta** — é uma extensão do Claude Code, onde é "contexto adicional para quando invocar a skill", anexado à `description` no skill listing e contando para o limite combinado de **1.536 caracteres** ([documentação Claude Code](https://code.claude.com/docs/en/skills); [primeline.cc](https://primeline.cc/blog/claude-code-skills-not-triggering)).

**O que muda entre harnesses:** o Claude Code aceita todos os campos da tabela mais extras seus (`context: fork`, `hooks`, `disable-model-invocation`, `user-invocable`, `argument-hint`, `when_to_use`). Já uploads ao claude.ai, a Skills API e o `package_skill.py` de `anthropics/skills` aceitam apenas `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools` — qualquer outro campo é **erro duro**, não ignorado ([code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills)). A Skills API é ainda mais estrita: `name` sem palavras reservadas (`anthropic`, `claude`). Fora do ecossistema Claude, o formato é um standard suportado por 27+ agentes (Codex, Copilot, Cursor, Gemini CLI, etc.), "escrever uma vez, usar em todo o lado" ([denser.ai](https://denser.ai/blog/agent-skills-guide); [strapi.io](https://strapi.io/blog/what-are-agent-skills-and-how-to-use-them)).

## 2. Limites/recomendações de tamanho e progressive disclosure

A recomendação oficial, em [agentskills.io/specification](https://agentskills.io/specification), é explícita: *"the agent will load this entire file once it's decided to activate a skill. Consider splitting longer SKILL.md content into referenced files"* — com instruções **< 5.000 tokens** recomendados. O modelo de três níveis ([platform.claude.com](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)):

1. **Metadata (~100 tokens/skill)** — sempre carregada (startup);
2. **Instruções (< 5k tokens)** — corpo do `SKILL.md`, carregado ao ativar;
3. **Recursos** — `references/`, `scripts/`, `assets/`: custo zero até serem acedidos.

A comunidade converte isto em prática: corpo **< 500 linhas** ("working-level guidance, não cobertura enciclopédica"), um único nível de disclosure (`SKILL.md` → references, nunca reference→reference), scripts para computação (o código nunca entra no contexto) e índice (TOC) em ficheiros de referência > 100 linhas ([dotzlaw.com](https://dotzlaw.com/insights/claude-skills); [lucek.ai](https://lucek.ai/blogs/agent-skills.html); [Medium/Nimrita Koul](https://medium.com/@nimritakoul01/anthropics-agent-skills-0ef767d72b0f)).

A própria Anthropic diz: *"When the SKILL.md file becomes unwieldy, split its content into separate files and reference them. If certain contexts are mutually exclusive or rarely used together, keeping the paths separate will reduce the token usage"* ([anthropic.com/engineering](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)). Medições reais sobre as 17 skills oficiais da Anthropic: corpos entre ~275 e ~8.000 tokens (mediana ~2.000) e discovery de ~80 tokens por skill (mediana; todas as 17 ≈ 1.700 tokens no total) ([newsletter.swirlai.com](https://www.newsletter.swirlai.com/p/agent-skills-progressive-disclosure)). O conteúdo de nível 3 é "efetivamente ilimitado" porque nada carrega até ser lido ([atlan.com](https://atlan.com/know/ai-agent/ai-agent-skills/skill-md-file-explained)).

## 3. Carregamento sob demanda e custo de contexto

Quando uma skill dispara, o Claude **lê o `SKILL.md` do sistema de ficheiros via bash**; se as instruções referenciarem outros ficheiros (ex.: `forms.md`), lê-os também via bash; quando mencionam scripts, **executa-os e só o output entra no contexto** — o código-fonte nunca entra ([platform.claude.com](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)).

Métricas de custo: Level 1 ~100 tokens/skill sempre presentes; Level 2 < 5k tokens por ativação; Level 3 zero até leitura. Exemplo quantificado: 8 skills × 300 linhas + 1.000 linhas de references ≈ **70.000 tokens** se carregadas todas à cabeça; com progressive disclosure, ~500 tokens no arranque e tipicamente ~2.000 em uso ([dotzlaw.com](https://dotzlaw.com/insights/claude-skills)). A Anthropic enquadra a janela de contexto como "um bem público" — tudo o que se acrescenta degrada o resto ([strapi.io](https://strapi.io/blog/what-are-agent-skills-and-how-to-use-them)). Em sistemas multi-passo há ainda a "re-explanation tax": o prompt completo é reenviado a cada passo ([mindstudio.ai](https://www.mindstudio.ai/blog/prompt-bloat-vs-skill-systems-ai-agents)).

Detalhe do Claude Code: skills de projeto carregam de `.claude/skills/` no diretório de arranque e nos pais até à raiz do repo; skills em **subdiretórios abaixo** do arranque só carregam quando o Claude lê/edita ficheiros nesse subdiretório (`/add-dir` força). O texto combinado `description`+`when_to_use` trunca a 1.536 caracteres e, havendo muitas skills, as descrições encurtam-se para caber num orçamento — as menos invocadas são descartadas primeiro; `/doctor` mostra overflow ([code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills); [hidekazu-konishi.com](https://hidekazu-konishi.com/entry/claude_code_skills_complete_guide.html)).

## 4. Skills que invocam/carregam outras skills

A spec **não define um mecanismo formal de sub-skills**; a composição faz-se por referência textual: o `SKILL.md` aponta para `references/x.md` ou para o caminho de outra skill e o agente lê-a via bash. Como resume a comunidade: *"Tell the agent where the skill is and it will read it... A skill is just context and it gets injected"* ([r/ClaudeAI](https://www.reddit.com/r/ClaudeAI/comments/1qbc30u/claude_code_skills_subagents_feel_misaligned_what)). Padrões documentados ([Medium](https://medium.com/@nimritakoul01/anthropics-agent-skills-0ef767d72b0f)):

- **Guia de alto nível com references** — instruções principais no `SKILL.md`, detalhe em ficheiros ligados;
- **Organização por domínio** — ficheiro por domínio para não carregar contexto irrelevante;
- **Detalhes condicionais** — "apenas se X, lê `references/y.md`";
- **Router/orquestrador** — uma skill de tarefa despacha para skills de conhecimento via Skill tool ou `/skill-name` (o Claude Code permite invocação mútua; `disable-model-invocation`/`user-invocable` controlam quem pode invocar — [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills)).

Cuidado com subagentes: skills listadas no frontmatter de um subagente carregam **todas upfront** (milhares de tokens), perdendo o benefício do discovery dinâmico — a ligação é estática, definida em tempo de autoria ([r/ClaudeAI](https://www.reddit.com/r/ClaudeAI/comments/1qbc30u/claude_code_skills_subagents_feel_misaligned_what)). No Cursor, diretórios aninhados servem apenas para agrupar categorias — a identidade vem da pasta que contém o `SKILL.md` ([cursor.com/docs/skills](https://cursor.com/docs/skills)).

## 5. Boas práticas de organização

- **`scripts/`** — código executável autocontido, com mensagens de erro úteis e edge cases tratados (Python/Bash/JS) ([agentskills.io](https://agentskills.io/specification));
- **`references/`** — documentação adicional carregada sob demanda; convenções `REFERENCE.md`, `FORMS.md`, ficheiros por domínio; manter cada ficheiro focado;
- **`assets/`** — templates, imagens, tabelas de consulta, schemas.

**Nomes:** forma em gerúndio (`processing-pdfs`, `analyzing-spreadsheets`), kebab-case igual à pasta; evitar nomes vagos (`helper`, `utils`) e palavras reservadas. **Descrições:** fórmula `[o que faz] + [quando usar] + [capacidades-chave]`, terceira pessoa, com as frases literais que os utilizadores dizem; o `skill-creator` da Anthropic recomenda descrições "levemente insistentes", porque o Claude tende a **sub-ativar** skills; e cláusulas de exclusão ("Do NOT use for X") para não roubar trabalho de skills vizinhas ([platform.claude.com best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [generativeprogrammer.com](https://generativeprogrammer.com/p/skill-authoring-patterns-from-anthropics); [kdnuggets.com](https://www.kdnuggets.com/anthropics-complete-guide-to-claude-skills-building)).

**Versionamento:** a spec **não prescreve semver** nem sistema de updates; `metadata.version` é a convenção e são os registos/instaladores que dão significado ao valor ([atlan.com](https://atlan.com/know/ai-agent/ai-agent-skills/agent-skills-registry)). Estudo empírico (arXiv): conformidade ≥99% nos campos obrigatórios, mas os opcionais (`license`, `compatibility`, `metadata`, `allowed-tools`) aparecem em só 3–16% das skills; `references/` é o subdiretório mais comum (31% em registos centrais vs 17% pessoais) ([arxiv.org](https://arxiv.org/html/2607.00911v1)).

## 6. Erros comuns em skills grandes e como corrigir

**Description vaga** é a falha nº1 — a causa mais comum de uma skill nunca disparar; mais de 99% dos `SKILL.md` reais têm pelo menos um "skill smell", quase sempre na `description` ([atlan.com](https://atlan.com/know/ai-agent/ai-agent-skills/skill-md-file-explained); [levelup.gitconnected.com](https://levelup.gitconnected.com/a-mental-model-for-claude-code-skills-subagents-and-plugins-3dea9924bf05)).

**"Rule soup"/prompt bloat:** skills grandes acumulam patches sobre patches ("lembrar de não..."), regras contraditórias e exceções de exceções. Sintomas: comportamento inconsistente em entradas parecidas, falhas em edge cases apesar de instruções claras, medo de editar o prompt, degradação em sessões longas ([mindstudio.ai](https://www.mindstudio.ai/blog/prompt-bloat-vs-skill-systems-ai-agents)). A investigação confirma a "Curse of Instructions" (quanto mais regras, pior o cumprimento de cada uma) e o "instruction complexity cliff" (5 regras seguem-se fiavelmente, 15 não), agravado por conflitos aparentes e pelo decay posicional que enterra instruções no meio do prompt ([tianpan.co](https://tianpan.co/blog/2026/04/17/instruction-complexity-cliff-llm-compliance); [deepchecks.com](https://deepchecks.com/question/why-llm-responses-degrade-in-complex-user-scenarios)).

**Correções recomendadas:** guidelines condicionais em vez de prompt gigante (carregar só o relevante); separar contextos mutuamente exclusivos em caminhos distintos; terminologia única ("API endpoint" não misturado com "URL"/"path"); **defaults em vez de menus**; prescritivo onde é frágil, flexível onde varia; manter os *gotchas* no `SKILL.md` (onde são lidos antes do erro) e transformar cada correção humana em gotcha; iterar com evals (`Run → Validate → Fix → Repeat`) ([agentskills.io best-practices](https://agentskills.io/skill-creation/best-practices); [platform.claude.com](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [lucek.ai](https://lucek.ai/blogs/agent-skills.html)). Anti-padrões adicionais: paths estilo Windows (`scripts\helper.py`), demasiadas opções equivalentes. E atenção ao extremo oposto: micro-skills demasiado fragmentadas prejudicam a recuperação — a comunidade recomenda consolidar em "macro-skills" ([github.com discussions](https://github.com/orgs/community/discussions/182117)).

---

## IMPLICAÇÕES para partir uma skill de 220KB em sub-skills sob demanda

220KB ≈ **~55k tokens**, cerca de **11× o orçamento recomendado** para um corpo de `SKILL.md` (< 5k tokens) — e, sendo carregado numa peça só, estaria condenado ao "rule soup". Recomendações acionáveis:

1. **`SKILL.md`-mãe como router fino (< 500 linhas / 5k tokens):** só metadados, árvore de decisão "que sub-skill para que tarefa", gotchas transversais e ponteiros explícitos (`Se X → lê sub-skills/x/SKILL.md`). Nada de conteúdo enciclopédico.
2. **Partir por caminhos mutuamente exclusivos** (regra da Anthropic): uma sub-skill por workflow/fase que raramente coexiste — exatamente o padrão `task-*` (orquestrador) → `knowledge-*` (domínio). Cada sub-skill fica autocontida e só carrega quando o router a indica.
3. **`references/` com um só nível e ficheiros focados:** cada ficheiro < 500 linhas, com TOC se > 100 linhas; proibido reference→reference. Se a hierarquia for mais profunda, reorganizar em sub-skills.
4. **Toda a lógica determinística para `scripts/`:** validação, cálculo, parsing e transformações em código executável — o script nunca entra no contexto, só o output; liberta tokens e elimina contradições de prosa.
5. **Gatilhos cirúrgicos em cada sub-skill:** fórmula `[o que faz] + [quando usar] + frases literais do utilizador] + cláusula de exclusão`; ≤ 1024 chars pela spec (≤ 1.536 combinado com `when_to_use` no Claude Code); começar pelo caso de uso-chave porque o listing trunca.
6. **Erradicar o "rule soup" na decomposição:** uma terminologia por conceito, apagar patches contraditórios ("remember not to..."), fundir regras redundantes, escolher um default em vez de menus, e concentrar os gotchas numa secção curta do corpo.
7. **Versionar e validar:** `metadata.version` + changelog por sub-skill; verificar conformidade da spec (`name` = nome da pasta, kebab-case, sem palavras reservadas) antes de distribuir, pois a Skills API rejeita com erro duro.
8. **Medir e evitar sobre-fragmentação:** estimar tokens por nível (metadata ≈ 100/skill, corpo < 5k, references sob procura) e testar com evals; manter "macro-skills" temáticas em vez de dezenas de micro-skills que o roteador não sabe recuperar.
