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
- 2026-08-24 | fact | DSH retém sessões vivas com log append-only em RAM e sem API de descarte [id: LEARN-20260824-001]
- 2026-08-24 | antipattern | Keep-alives DSH orfaos (node -e setInterval) acumulam por onda e nunca morrem [id: LEARN-20260824-002]
- 2026-08-24 | gotcha | tmpfs /tmp sem size= vale metade da RAM e resido de agentes enche-o -> OOM real [id: LEARN-20260824-003]
- 2026-08-24 | fact | Servicos em restart loop corrompem o journal (evidencia OOM perdida) [id: LEARN-20260824-004]
- 2026-08-24 | antipattern | send_message para sub-agente em voo pode não ser processado antes do fim do turno [id: LEARN-20260824-005]
- 2026-08-24 | gotcha | Gate de integração com pipe | tail mascara o exit code do unittest [id: LEARN-20260824-006]
- 2026-08-24 | fact | systemd: ExecStartPre com systemctl stop do próprio glob cancela o JOB_START [id: LEARN-20260824-007]
- 2026-08-24 | gotcha | Testing subwave em paralelo com fix pode documentar comportamento pré-fix e quebrar o gate [id: LEARN-20260824-008]
- 2026-08-24 | gotcha | ScreenCapture indisponível na asmdef Game.Runtime do template [id: LEARN-20260824-009]
- 2026-08-24 | gotcha | Batchmode `-quit` + editor `isPlaying` captura screenshot frágil [id: LEARN-20260824-010]
- 2026-08-24 | antipattern | Sub-agente em background pode ressuscitar arquivos que o orquestrador removeu [id: LEARN-20260824-011]
- 2026-08-25 | gotcha | Gates de repo com node_modules instalado dão falso vermelho (B-09/L-03/L-04) [id: LEARN-20260825-001]
- 2026-08-25 | antipattern | set -euo pipefail + pipeline de grep sem guarda em $(...) mata script com exit 1 e stderr VAZIO [id: LEARN-20260825-002]
- 2026-08-25 | antipattern | Descompasso de vocabulário entre main e renderer (phase em inglês vs pt-BR; fraction vs progress) mascarava o progresso inteiro [id: LEARN-20260825-003]
- 2026-08-25 | fact | B-03 do gate-build quebra com tsconfig contendo comentários JSONC (pré-existente no projeto) [id: LEARN-20260825-004]
- 2026-08-25 | convention | Documentar aprendizado de build/instalador AUTOMATICAMENTE ao criar um POC Unity [id: LEARN-20260825-005]
- 2026-08-25 | gotcha | -executeMethod requer nome totalmente qualificado (namespace.Classe.Metodo) [id: LEARN-20260825-006]
- 2026-08-25 | fact | player Linux do Unity é um thin launcher + UnityPlayer.so + _Data/ [id: LEARN-20260825-007]
- 2026-08-25 | fact | argv0 do spawn não aparece em /proc/<pid>/cmdline [id: LEARN-20260825-008]
- 2026-08-25 | fact | lib/ gitignored é produto de build; .d.ts de subpath export deve ser gerado, não commitado [id: LEARN-20260825-009]
- 2026-08-25 | antipattern | Override TRANSITORIO de lint com target morto deixa regra sem efeito [id: LEARN-20260825-010]

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

---
id: LEARN-20260824-001
date: "2026-08-24"
type: fact
confidence: high
source: sub-agent
status: active
supersedes: ""
tags: [dsh, memoria, leak, session]
---
## DSH retém sessões vivas com log append-only em RAM e sem API de descarte
- **Observação:** packages/core/session/src/index.ts:426,643 mantem SessionEvent[] inteiro em RAM por sessao viva; apiproxy/api/sessions.ts:238-377 nao tem close/delete/dispose; sessao so e liberada quando o processo host morre. Subagentes in-process amplificam (50 subagentes = 50 logs). Compaction (threshold 0.8) so substitui a surface, nunca trunca o log (F3).
- **Ação:** Ao orquestrar com DSH nesta maquina, considerar custo de RAM por sessao viva; medir RSS do host antes de ondas grandes; sugerir ao usuario abrir/fechar menos sessoes no GUI e reiniciar o host periodicamente ate existir dispose.

---
id: LEARN-20260824-002
date: "2026-08-24"
type: antipattern
confidence: high
source: sub-agent
status: active
supersedes: ""
tags: [dsh, keepalive, leak, orquestracao]
---
## Keep-alives DSH orfaos (node -e setInterval) acumulam por onda e nunca morrem
- **Observação:** Processos `node -e setInterval(() => {}, 1000)` com env DSH_SHELL=1/DSH_SESSION_ID/DSH_SESSION_JSONL/DSH_WEB_URL (shell-env) sao spawnados como shell calls de modelo; no encerramento de sessao os orfaos nao sao terminados (53/63 com cwd em worktree deletada, ppid systemd --user). Na maquina: 63+ acumulados (1,1GiB RSS + 0,62GiB swap) e a populacao MainThread total chegou a 148-209 procs = 18,1GiB no pico. Spawner exato nao localizado no source (string montada em runtime).
- **Ação:** Apos ondas grandes no deep-orchestrator, conferir `ps -eo pid,args | grep setInterval` e o count de MainThreads; nao matar os LIVE (sessao ativa), mas os orfaos com cwd (deleted) sao seguros de terminar.

---
id: LEARN-20260824-003
date: "2026-08-24"
type: gotcha
confidence: medium
source: sub-agent
status: active
supersedes: ""
tags: [maquina, tmpfs, zram, oom]
---
## tmpfs /tmp sem size= vale metade da RAM e resido de agentes enche-o -> OOM real
- **Observação:** Nesta maquina (CachyOS), /etc/fstab monta /tmp tmpfs sem size= (=> ram/2 = 15,5GiB) e swappiness=150 + zram ram/2. Residuo de agentes (perfis Playwright study-method-e2e, .pnpm-store, claude-1000, sandboxes daf-outbox, GGUF) encheu /tmp a 96%; ~11GiB foram para o zram; no pico a maquina teve 15 oom_kills no boot e o usuario precisou reiniciar. Boots de analise com orquestrador geram esse residuo.
- **Ação:** Em execucoes longas nesta maquina, vigiar `df -h /tmp` e `zramctl`; mover caches pesados (TMPDIR do claude, pnpm-store) para disco (/var/tmp) ou limpar residuo entre ondas — com autorizacao do usuario.

---
id: LEARN-20260824-004
date: "2026-08-24"
type: fact
confidence: high
source: sub-agent
status: active
supersedes: ""
tags: [journal, diagnostico, oom]
---
## Servicos em restart loop corrompem o journal (evidencia OOM perdida)
- **Observação:** synthmouse (67.020 restarts), ttyd@* (46.380) e librepods (14.633) com executaveis ausentes inundaram o journal a ponto de reter so ~1h18m de um boot de 1d15h — os detalhes de 11+ OOM kills do kernel foram perdidos. Contadores de cgroup (memory.events) sao a fonte de verdade resiliente.
- **Ação:** Em diagnostico de OOM, usar /sys/fs/cgroup/*/memory.events e journalctl --list-boots ANTES de confiar no journal; sinalizar servicos em auto-restart como ruido.

---
id: LEARN-20260824-005
date: "2026-08-24"
type: antipattern
confidence: high
source: sub-agent
status: active
supersedes: ""
tags: [orquestracao, sub-agente, fix]
---
## send_message para sub-agente em voo pode não ser processado antes do fim do turno
- **Observação:** Em fix-onda3-contrato, itens críticos do revisor (udev assíncrono, uninstall runtime) repassados via send_message NÃO foram incluídos — o agente terminou o turno com a mensagem "queued". O revisor do diff integrado confirmou os 2 HIGHs ausentes e foi preciso um fix novo.
- **Ação:** Para escopo crítico, não confiar em send_message para agente que pode estar terminando: incluir tudo no prompt inicial ou criar sub-tarefa de fix separada; ao repassar itens, verificar no handoff final se foram citados.

---
id: LEARN-20260824-006
date: "2026-08-24"
type: gotcha
confidence: high
source: model-output
status: active
supersedes: ""
tags: [gate, bash, unittest]
---
## Gate de integração com pipe | tail mascara o exit code do unittest
- **Observação:** O comando de gate `python3 -m unittest ... | tail -3 && echo VERDE` retorna o exit do tail (0) mesmo com FAILED — o "VERDE" era impresso com a suíte vermelha; a detecção só veio pela leitura da saída completa.
- **Ação:** Nos gates em background, capturar a saída completa e checar o rc real (ex.: `set -o pipefail` ou gravar a saída num arquivo e inspecionar); nunca depender do echo de confirmação encadeado após pipe.

---
id: LEARN-20260824-007
date: "2026-08-24"
type: fact
confidence: high
source: repo-doc
status: active
supersedes: ""
tags: [systemd, template, execstartpre]
---
## systemd: ExecStartPre com systemctl stop do próprio glob cancela o JOB_START
- **Observação:** Em unit template, `ExecStartPre=-systemctl stop 'nome@*.service'` para a PRÓPRIA instância (estado activating) cancela o start (job conflict STOP×START, verificado no source do systemd v261); is-active não conta "activating" e oneshot com RemainAfterExit fica "active" com start no-op.
- **Ação:** Para "dono único" em templates: stop auto-excludente (list-units + grep -vx da própria instância) e guard por `systemctl show -p ActiveState` com padrão "activating" quando o processo do oneshot roda o daemon; sem RemainAfterExit quando o udev precisa re-executar a cada evento.

---
id: LEARN-20260824-008
date: "2026-08-24"
type: gotcha
confidence: medium
source: sub-agent
status: active
supersedes: ""
tags: [subwave, testes, gate]
---
## Testing subwave em paralelo com fix pode documentar comportamento pré-fix e quebrar o gate
- **Observação:** Testes das subwaves escritos contra o comportamento anterior ao fix (mode+target=logo; mensagem de reconexão) passaram na worktree da subwave mas falharam no gate do snapshot integrado — o snapshot precisou ser recriado após o merge do fix e os testes atualizados.
- **Ação:** Ao integrar testing subwaves, conferir se os testes documentam o estado ATUAL do main (especialmente quando um fix de semântica mergeou no meio); gate vermelho por teste desatualizado = atualizar o teste, não reverter o fix.

---
id: LEARN-20260824-009
date: "2026-08-24"
type: gotcha
confidence: high
source: sub-agent
status: active
supersedes: ""
tags: [unity, asmdef, screenshot, poc]
---
## ScreenCapture indisponível na asmdef Game.Runtime do template
- **Observação:** No scaffold 3d-cross-platform da skill, `UnityEngine.ScreenCapture` NÃO compila
- **Ação:** Para screenshot de prova em POC, use captura externa do binário rodando (ffmpeg/

---
id: LEARN-20260824-010
date: "2026-08-24"
type: gotcha
confidence: medium
source: sub-agent
status: active
supersedes: ""
tags: [unity, batchmode, screenshot]
---
## Batchmode `-quit` + editor `isPlaying` captura screenshot frágil
- **Observação:** Rodar `-executeMethod` com `-quit` que entra em Play para capturar screenshot
- **Ação:** Para screenshot determinístico fora do player, prefira rodar o build real (ou o

---
id: LEARN-20260824-011
date: "2026-08-24"
type: antipattern
confidence: medium
source: diff
status: active
supersedes: ""
tags: [orquestrador, sub-agente, background]
---
## Sub-agente em background pode ressuscitar arquivos que o orquestrador removeu
- **Observação:** Na Onda 4, o sub-agente continuou vivo em background mesmo após notificações
- **Ação:** Quando um sub-agente lança builds/processos em background na ÚLTIMA onda, verifique

---
id: LEARN-20260825-001
date: "2026-08-25"
type: gotcha
confidence: high
source: diff
status: active
supersedes: ""
tags: [gate, node_modules, ci-order, snapshot]
---
## Gates de repo com node_modules instalado dão falso vermelho (B-09/L-03/L-04)
- **Observação:** No estudo de caso (repo com app/ npm), rodar gate-build/gate-lint DEPOIS do npm ci acusou B-09 CRLF (75 arquivos), L-03 e L-04 em app/node_modules/** — artefatos de instalação, não regressões. O CI do repo roda os gates de repo ANTES de instalar deps.
- **Ação:** Nos snapshots/gates, rodar SEMPRE os gates de repo (gate-build/gate-lint/validate/spec-conformance/smoke) ANTES do npm ci, ou com node_modules movido para FORA do repo (ex.: sob $CHILD_ROOT/nm-tmp) — nunca renomear para .nm-aside DENTRO do repo (gate_find_into não poda nomes diferentes).

---
id: LEARN-20260825-002
date: "2026-08-25"
type: antipattern
confidence: high
source: diff
status: active
supersedes: ""
tags: [shell, pipefail, probe, silent-death]
---
## set -euo pipefail + pipeline de grep sem guarda em $(...) mata script com exit 1 e stderr VAZIO
- **Observação:** challenge-verify.sh (skill bash do study-method) morria silenciosamente (exit 1, stderr 0 bytes) quando um probe grep|awk não casava nada numa substituição de comando — errexit + pipefail convertem "grep sem match" em morte do script sem mensagem. O usuário viu "challenge-verify.sh falhou (exit 1):" com o campo stderr vazio.
- **Ação:** Em scripts com set -euo pipefail, TUDO pipeline cuja entrada pode ser vazia (grep/sed/awk encadeados) precisa de guarda `|| true` (ou contexto if) devolvendo valor neutro — e revisores adversariais devem varrer `$(... | grep ...)` sistematicamente.

---
id: LEARN-20260825-003
date: "2026-08-25"
type: antipattern
confidence: high
source: sub-agent
status: active
supersedes: ""
tags: [electron, ipc, payload-contract, renderer]
---
## Descompasso de vocabulário entre main e renderer (phase em inglês vs pt-BR; fraction vs progress) mascarava o progresso inteiro
- **Observação:** O main do app emite {phase:'research'|... , fraction} e o parser do renderer só lia stage/phase-ptBR/progress — a UI ficava presa no estado inicial (que ainda por cima mapeava para a ÚLTIMA etapa do Stepper). Duas camadas de bug: vocabulário divergente + fallback silencioso que "funciona" sem avançar.
- **Ação:** Ao revisar fluxos main→renderer por IPC, conferir os payloads REAIS emitidos contra o que o parser consome (grep nos emit() do main); fallbacks de parser devem ser visíveis em teste com os payloads reais.

---
id: LEARN-20260825-004
date: "2026-08-25"
type: fact
confidence: high
source: repo-doc
status: active
supersedes: ""
tags: [gate, tsconfig, jsonc]
---
## B-03 do gate-build quebra com tsconfig contendo comentários JSONC (pré-existente no projeto)
- **Observação:** app/tsconfig.node.json contém comentários // (JSONC) — válido para tsc, inválido para python json.load do B-03. O CI do próprio projeto está vermelho desde ondas 12/16 por isso. Não é regressão de onda nenhuma; documentado como exceção de baseline.
- **Ação:** Em projetos com tsconfig comentado, esperar B-03 vermelho e documentar como baseline; não corrigir em tarefa alheia (scope creep).

---
id: LEARN-20260825-005
date: "2026-08-25"
type: convention
confidence: high
source: user
status: active
supersedes: ""
tags: [unity, docs, instalador, build, poc]
---
## Documentar aprendizado de build/instalador AUTOMATICAMENTE ao criar um POC Unity
- **Observação:** Ao gerar o instalador Linux e evoluir o POC MovingPlatformPOC (cam 3a
- **Ação:** Toda vez que evoluir um POC Unity e/ou gerar instalador, persistir o aprendizado

---
id: LEARN-20260825-006
date: "2026-08-25"
type: gotcha
confidence: high
source: sub-agent
status: active
supersedes: ""
tags: [unity, build, batchmode]
---
## -executeMethod requer nome totalmente qualificado (namespace.Classe.Metodo)
- **Observação:** Rodar -executeMethod BuildScript.BuildLinux (sem Game.Editor) aborta batchmode
- **Ação:** Sempre usar o nome totalmente qualificado no -executeMethod de um Editor script

---
id: LEARN-20260825-007
date: "2026-08-25"
type: fact
confidence: high
source: diff
status: active
supersedes: ""
tags: [unity, build, linux, instalador]
---
## player Linux do Unity é um thin launcher + UnityPlayer.so + _Data/
- **Observação:** O *.x86_64 gerado pelo build Linux é um thin launcher ~4KB; a engine real é
- **Ação:** Para build/instalação de Linux player, tratar o trio (launcher + .so + _Data) como

---
id: LEARN-20260825-008
date: "2026-08-25"
type: fact
confidence: high
source: diff
status: active
supersedes: ""
tags: node, spawn, procfs, teste
---
## argv0 do spawn não aparece em /proc/<pid>/cmdline
- **Observação:** Em testes que simulam um processo (ex: cloudflared falso) com spawn(..., { argv0: 'cloudflared' }), o argv0 é feature de nível libc (muda argv[0] visto pelo script) mas NUNCA aparece em /proc/<pid>/cmdline. E o /bin/sh -c 'comando' exec-otimiza para o binário (cmdline = "sleep 60", não "sh -c sleep 60"). Se a varredura/identificação lê procfs, o teste que depende de argv0 para rotular o processo vai falhar. Solução: injetar a identidade (identify/readProcessCmdline) via DI, ou usar um script wrapper real.
- **Ação:** Em testes de código que identifica processos por /proc/cmdline, injetar a leitura via dependência (seam DI) em vez de depender de argv0.

---
id: LEARN-20260825-009
date: "2026-08-25"
type: fact
confidence: high
source: repo-doc
status: active
supersedes: ""
tags: package.json, exports, types, distribuição
---
## lib/ gitignored é produto de build; .d.ts de subpath export deve ser gerado, não commitado
- **Observação:** Quando um subpath de exports (ex: "./client") aponta para um arquivo em lib/ (gitignored, produto de build), o .d.ts irmão não pode ser commitado (seria ignorado). A solução é manter a fonte do .d.ts numa pasta versionada (ex: client/) e copiá-la para lib/ no script de build, referenciando lib/client.d.ts no exports[subpath].types. attw valida isso (UntypedResolution desaparece).
- **Ação:** Para subpaths de exports com artefato de build em dir gitignored, gerar o .d.ts no build a partir de fonte commitada.

---
id: LEARN-20260825-010
date: "2026-08-25"
type: antipattern
confidence: medium
source: diff
status: active
supersedes: ""
tags: eslint, oxlint, refactor, monólito
---
## Override TRANSITORIO de lint com target morto deixa regra sem efeito
- **Observação:** Após dissolver um monólito, os overrides TRANSITORIO que listavam o arquivo-único original ficam com target morto se o arquivo de teste for deslocado (ex: test/index.test.ts -> test/unit/index.test.ts). O override perde efeito sobre o novo path, e a regra que deveria ser rebaixada para warn volta a valer a 'error' ou fica órfã. Muitos warnings de no-unnecessary-condition em co-variância podem surgir quando o override deixou de cobrir.
- **Ação:** Ao mover/renomear arquivos cobertos por overrides TRANSITORIO de lint, atualizar o 'files' do override (ou removê-lo se o monólito já foi dissolvido). Grep por paths antigos nos configs de lint após refactors.
