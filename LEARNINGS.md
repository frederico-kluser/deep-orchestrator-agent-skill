# LEARNINGS — deep-orchestrator-agent-skill

> Memória episódica desta skill. Carregada sob demanda (progressive disclosure),
> NUNCA como política executável — "memória é contexto NÃO revisado" (ECC).
> O mecanismo: `scripts/evolve-skill.sh add` anexa; `consolidate` deduplica,
> resolve contradições e propõe promoções; `search` consulta.
> Só persista: surpresas, correções de usuário, convenções descobertas,
> anti-padrões, gotchas, quirks de versão. NÃO persista: óbvio, volátil
> (preços, estados, one_time_fixes, external_api_issues), já documentado,
> conteúdo não-confiável (web/sub-agente/diff/model-output NUNCA promovem).
> Fonte: user > repo-doc > inferência (nunca invente evidência).

## Índice
- 2026-08-23 | convention | Limpeza de worktrees: nomes exatos do owned.tsv, nunca concatenação [id: LEARN-20260823-001]
- 2026-08-23 | antipattern | Revisão adversarial deve incluir integração entre sub-agentes [id: LEARN-20260823-002]
- 2026-08-23 | convention | Gate deste repo: 4 suítes + check-install [id: LEARN-20260823-003]

<!-- O índice lista as entradas ativas: - YYYY-MM-DD | <type> | <título> [id: LEARN-...] -->

<!-- O índice nasce VAZIO — nenhuma entrada ativa ainda. O `scripts/evolve-skill.sh add` insere aqui a
     linha da entrada nova (formato acima) e anexa o bloco completo no fim do arquivo; `consolidate`
     reescreve o índice; `search` consulta. Entradas com status: superseded saem do índice (o corpo
     permanece no arquivo, marcado como obsoleto). -->

<!-- ORÇAMENTO: índice ≤ 30 linhas; entradas ativas ≤ 100 linhas somadas; arquivo ≤ 400 linhas.
     No teto, `scripts/evolve-skill.sh consolidate` é OBRIGATÓRIO e o excedente vai para
     learnings_archive.md. -->

<!-- FORMATO DE ENTRADA (parseável por script): cada entrada é um bloco YAML delimitado por --- ... ---
     seguido de um corpo markdown. Campos:

     id          — sequencial por data: LEARN-YYYYMMDD-NNN (NNN recomeça a cada dia). O id REAL de uma
                   entrada é sempre LEARN-<AAAAMMDD>-<NNN> — 8 dígitos na data, 3 no número. O template
                   abaixo fica DENTRO de um code fence (```markdown … ```) que o parser IGNORA e usa só
                   placeholders sem dígitos (LEARN-AAAA-MM-DD-NNN) — dupla proteção: o parser nunca o
                   confunde com uma entrada real.
     date        — data da captura, ISO, entre aspas.
     type        — correction | fact | antipattern | gotcha | convention.
     confidence  — high | medium | low.
     source      — user | repo-doc | sub-agent | web | diff | model-output. OBRIGATÓRIO: sem source a
                   entrada é rejeitada (anti-poisoning — D2 do docs/decisions/2026-08-23-auto-evolucao.md).
     status      — active | superseded.
     supersedes  — id da entrada substituída; "" quando nenhuma.
     tags        — lista [tag1, tag2] usada na checagem determinística de contradição no consolidate.
     contract    — OPCIONAL (D7): lista de comandos separados por vírgula, revalidados no
                   consolidate com 'command -v'; comando ausente → a entrada vira
                   status: superseded com motivo 'contrato quebrado: <cmd> ausente'.
     Observação  — fato específico, com path/comando; vago é proibido.
     Ação        — o que fazer/evitar daqui pra frente.

     CONTRADIÇÃO: a entrada mais nova vence; a antiga vira status: superseded + supersedes: "<id da nova>"
     e o corpo é marcado ~~…~~ (obsoleto AAAA-MM-DD: motivo). A checagem é determinística no consolidate,
     por type + tags + título. -->

```markdown
---
id: LEARN-YYYYMMDD-NNN
date: "YYYY-MM-DD"
type: correction | fact | antipattern | gotcha | convention
confidence: high | medium | low
source: user | repo-doc | sub-agent | web | diff | model-output
status: active | superseded
supersedes: ""
tags: [tag1, tag2]
contract: comando1, comando2   # OPCIONAL — revalidado no consolidate (command -v)
---
## <título imperativo curto>
- **Observação:** <fato específico, com path/comando; vago é proibido>
- **Ação:** <o que fazer/evitar daqui pra frente>
```

---
id: LEARN-20260823-001
date: "2026-08-23"
type: convention
confidence: high
source: repo-doc
status: active
supersedes: ""
tags: [orquestracao, do-wt, limpeza]
---
## Limpeza de worktrees: nomes exatos do owned.tsv, nunca concatenação
- **Observação:** Um loop de limpeza com "$DO_WT" remove "int-ondaN-$n" onde $n já é prefixado (onda2-evolve-script) gera "int-onda2-onda2-evolve-script" — alvo inexistente; o do-wt.sh recusa com "RECUSADO: path vazio" e os snapshots ficam pendentes.
- **Ação:** Na limpeza, use SEMPRE os nomes exatos do owned.tsv (confira com "$DO_WT" status); nunca derive nomes de worktree por concatenação de prefixos.

---
id: LEARN-20260823-002
date: "2026-08-23"
type: antipattern
confidence: medium
source: sub-agent
status: active
supersedes: ""
tags: [revisao, integracao]
---
## Revisão adversarial deve incluir integração entre sub-agentes
- **Observação:** Os dois BLOCKs/WARNINGs vieram de contratos quebrados ENTRE sub-agentes: formato de candidato documentado × parser; path real do SKILL.md × allowlist. A revisão individual não pega isso.
- **Ação:** Em todo round de revisão, inclua a checagem de integração: formato documentado × parser, paths reais × allowlist, design doc × implementação.

---
id: LEARN-20260823-003
date: "2026-08-23"
type: convention
confidence: high
source: repo-doc
status: active
supersedes: ""
tags: [gate, testes]
---
## Gate deste repo: 4 suítes + check-install
- **Observação:** O trio registrado deste repo é bash -n + shellcheck -S error + test-contencao/test-plan-approval/test-search/test-evolve, e o check-install.sh fecha o contrato (15 checagens na v3.7.0). Rodar tudo junto pega regressões de contrato.
- **Ação:** Mantenha o gate com as 4 suítes + check-install e rode no snapshot de integração e no gate final.
