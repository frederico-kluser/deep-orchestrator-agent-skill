#!/usr/bin/env bash
# =============================================================================
# do-wt.sh — ciclo de vida das worktrees-filhas do deep-orchestrator-agent-skill
# -----------------------------------------------------------------------------
# Toda operação destrutiva do orquestrador passa por aqui, porque toda operação
# destrutiva do git é GLOBAL ao repositório: `git worktree list` enxerga a
# árvore principal e as worktrees de outras sessões; `git branch -D` alcança
# qualquer branch; `git worktree prune` desregistra worktrees de terceiros.
# A fonte de alvos NUNCA é uma varredura — é sempre o owned.tsv desta execução,
# confirmado pelo lock nativo do git como etiqueta de posse.
#
# Uso (sempre com o ENV_FILE da FASE 0 sourceado, ou via --env <arquivo>):
#
# --- FLUXO POR TAREFA (v4.1.0): a limpeza acontece no gate verde, pelo SCRIPT ---
#   do-wt.sh new <kind> <nome>            cria filha, trava e registra (11 colunas).
#                                        RECUSA (rc 6) kind feature|fix|prep da onda N
#                                        enquanto houver sobra de onda anterior (mesma
#                                        tabela do assert-clean --wave N); RECUSA
#                                        kind=test e nome test-onda* quando
#                                        DO_TEST_MODE=none; falha ao travar = desfaz e
#                                        falha (filha sem lock seria irremovível)
#   do-wt.sh integrate <nome> "<msg>"     = merge (mesmas guardas) + snapshot
#                                        kind=integration int-<nome> (-r2, -r3... se o
#                                        nome já existir; parent=<nome>) no SHA pós-merge
#                                        + filha=gate-pending. Imprime SNAPSHOT=<path>.
#                                        Merge falhou -> nada de snapshot, rc do merge
#   do-wt.sh gate-set <etapa> "<cmd>"     etapa = build|test|lint|e2e|install. Grava o
#                                        comando CRU em $DO_STATE/gate/<etapa>.cmd
#                                        ("" remove = "sem <etapa>")
#   do-wt.sh gate <nome> [--e2e]          roda no snapshot vivo de <nome> (cwd = snapshot,
#                                        HUSKY=0 CI=1): install -> build -> test -> lint
#                                        (-> e2e). Log/rc em $DO_STATE/gates/<nome>.log|.rc;
#                                        o veredito fica amarrado ao squash em que
#                                        rodou. VERDE => chama finish SOZINHO e imprime
#                                        "GATE VERDE — <nome> fechado". VERMELHO => NÃO
#                                        limpa nada, mostra a etapa + 40 linhas do log,
#                                        rc 4. Sem etapa configurada => rc 5. Feito para
#                                        rodar em background. Gate de kind=test com
#                                        DO_TEST_MODE=e2e e etapa e2e registrada roda o
#                                        e2e SOZINHO (--e2e segue aceito). Já rodando =>
#                                        rc 3 "AGUARDE" (log e .rc NÃO são tocados)
#   do-wt.sh finish <nome> [--gate-ok]    fecha filha INTEGRADA (MERGED|gate-pending):
#                                        salva restos (commit --no-verify) -> arquiva o
#                                        branch em refs/do-archive/$RUN_ID/<nome> ->
#                                        remove a worktree (--force, após arquivar) ->
#                                        apaga o branch -> fecha TODOS os snapshots com
#                                        parent=<nome> -> REMOVED/outcome=MERGED.
#                                        gate-pending exige gates/<nome>.rc == 0 OU
#                                        --gate-ok. Com cauda NÃO integrada (tip da
#                                        filha com conteúdo novo após o último squash)
#                                        e/ou gate VERMELHO o outcome vira
#                                        MERGED-PARTIAL:<motivo> (vai ao bloco do purge).
#                                        Idempotente. rc 3 = gate rodando;
#                                        rc 4 = gate vermelho (nada limpo)
#   do-wt.sh close <nome> [--discard "<motivo>"]
#                                        fecha quem NÃO será integrado. integration|
#                                        validation: sempre (outcome=DISPOSABLE). Demais:
#                                        MERGED/gate-pending => RECUSA ("use finish");
#                                        commits à frente de base_sha OU árvore suja =>
#                                        exige --discard (salva restos, arquiva, remove,
#                                        outcome=NEVER-MERGED:<motivo>); vazia e limpa =>
#                                        outcome=EMPTY. Sempre REMOVED ao fim. Idempotente
#   do-wt.sh assert-clean [--wave N]      PORTÃO inter-onda (rc 1 + tabela com o comando
#                                        de conserto): (a) feature|fix|prep|integration de
#                                        onda < N não-REMOVED; (b) test|validation de onda
#                                        < N-1 não-REMOVED; (c) realidade x ledger (dir em
#                                        $CHILD_ROOT sem linha; linha REMOVED com dir;
#                                        ref em $BRANCH_NS/ sem linha viva). Sem --wave:
#                                        exige TUDO fechado (fim da execução)
#   do-wt.sh ledger                       NOME KIND ONDA STATUS OUTCOME ARCHIVE_REF — fonte
#                                        da seção "Não integrado" do relatório final;
#                                        o RESUMO conta integradas/nunca-integradas/
#                                        vazias/descartaveis/parciais/abertas
#   do-wt.sh checklist                    CARTÃO DA ONDA (FASE 3, passos 0-10 do SKILL.md;
#                                        re-ancoragem pós-compactação)
#   do-wt.sh checklist final              CHECKLIST FINAL (FASE 4, passos 0-8, 1 linha cada)
#   do-wt.sh sweep                        fim de onda: fecha MERGED (via finish) e os
#                                        snapshots cujo parent já fechou; rc != 0 com
#                                        gate-pending, REVERTED ou feature|fix ACTIVE
#                                        (cada um com o comando de conserto).
#                                        test/validation ACTIVE só são listadas
#   do-wt.sh purge                        COMMIT-FINAL: garantia FINAL — NADA desta
#                                        execução sobrevive. Por linha não-REMOVED:
#                                        MERGED/gate-pending => finish --gate-ok; resto
#                                        => close --discard "purge" (branch SEMPRE
#                                        arquivado antes). "PURGE OK" só se ledger E
#                                        realidade fecharam. rc 1 = falha de remoção;
#                                        rc 3 = houve NEVER-MERGED ou MERGED-PARTIAL
#                                        (imprime o bloco "PURGE: NUNCA INTEGRADAS /
#                                        PARCIAIS" — obrigatório no relatório final).
#                                        Nunca toca no branch da raiz-de-mundo nem em
#                                        alvos fora do owned.tsv
#
# --- PRIMITIVOS / REPARO (continuam compatíveis) ---
#   do-wt.sh merge <nome> "<mensagem>"    squash-merge guardado na raiz-de-mundo.
#                                        MERGES SÃO SERIAIS; o owned.tsv é serializado por
#                                        lock (flock, ou mkdir sem flock — macOS).
#                                        CONFLITO é detectado ANTES de tocar a árvore
#                                        (git merge-tree, git >= 2.38): rc 1, raiz
#                                        intacta — resolva DENTRO da filha
#                                        (git -C <wt> merge "$BASE_BRANCH") e re-execute.
#                                        Commits internos usam --no-verify (hook do
#                                        repo-alvo não trava a orquestração; a qualidade
#                                        é do gate). Commit do squash falhou => índice
#                                        desfeito, re-merge possível. Squash SEM mudança
#                                        => NÃO vira MERGED: rc 4 ("VAZIO"). RE-integração
#                                        (fix após gate vermelho) que perderia deleção/
#                                        reversão do fix => RECUSA rc 1 com os paths:
#                                        merge do $BASE_BRANCH na filha ANTES do fix
#   do-wt.sh undo <nome>                 desfaz TODOS os squashes VIVOS da filha — o
#                                        original e o de cada fix re-integrado
#                                        (revert do mais novo ao mais antigo; reset
#                                        --hard só sob guarda) — funciona com HEAD
#                                        avançado: numa FALHA TARDIA de gate de
#                                        snapshot (F3-01), reverte EXATAMENTE os
#                                        squashes daquela filha e arquiva cada um em
#                                        refs/do-archive/$RUN_ID/undo-<nome>-<k>
#   do-wt.sh remove <nome> [--artifacts]  remove a filha (com guardas de posse). Diretório
#                                        sumiu com registro travado => desregistra SÓ
#                                        aquela entrada (nunca `worktree prune`)
#   do-wt.sh drop-branch <nome>           arquiva e apaga o branch (só se
#                                        MERGED/REMOVED). feature|fix|test|prep exigem
#                                        squash registrado (post_merge_sha) OU outcome
#                                        != "-": `mark MERGED` manual não apaga trabalho
#                                        não integrado. REVERTED: rode remove primeiro
#                                        (F4-07.8)
#   do-wt.sh verify                       prova de contenção (roda a cada onda)
#   do-wt.sh stage-delta                  estagia SÓ o que é nosso (COMMIT-FINAL)
#   do-wt.sh clean-ignored-delta          remove SÓ ignorados pós-FASE 0 (COMMIT-FINAL)
#   do-wt.sh wave-files <nome-da-1a-filha> arquivos tocados pela onda (aceita a 1ª
#                                        filha MERGED da onda; se a passada não foi
#                                        mergeada, resolve pela filha MERGED de menor
#                                        pre_merge_sha do mesmo prefixo ondaN-)
#   do-wt.sh status                       tabela do owned.tsv
#   do-wt.sh mark <nome> <STATUS>         ACTIVE|MERGED|REMOVED|BLOCKED|ORPHANED|
#                                        REVERTED|gate-pending
#
# kind: feature | test | validation | fix | prep | integration
# owned.tsv (11 colunas TSV): run_id kind name branch path base_sha pre_merge_sha
#   post_merge_sha status parent outcome — parent/outcome nunca vazios ("-").
#   outcome: - | MERGED | EMPTY | DISPOSABLE | MERGED-PARTIAL:<motivo> |
#            NEVER-MERGED:<motivo>
# =============================================================================
# (o --help imprime este cabeçalho até a régua acima — marcador de fim, não nº de linha)

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

if [ "${1:-}" = "--env" ]; then
  # shellcheck source=/dev/null
  . "$2" || { echo "do-wt.sh: não consegui sourcear $2" >&2; exit 2; }
  shift 2
fi

# --help e checklist são texto fixo: funcionam SEM o ENV_FILE (re-ancoragem após
# compactação de contexto não pode depender de estado). O --help imprime o
# cabeçalho INTEIRO até a régua de fim (marcador, não número de linha — o
# `sed -n 2,32p` antigo truncava sweep/purge/verify/mark).
cmd_checklist() { # [final] — texto fixo, funciona SEM o ENV_FILE
  if [ "${1:-}" = final ]; then
    # FASE 4 (B01): UMA linha por <step order> — 0 1 2 3 4 5 5.5 6 7 7.5 8.
    cat <<'FIM'
CHECKLIST FINAL — FASE 4, do fim das ondas até o descarte do estado (`. '<ENV_FILE>'` antes de cada comando)
 0. Últimas subwaves: teste/validação de QUALQUER onda com linha != REMOVED processa AGORA (gatilho = ledger, nunca a memória)
 1. TASK_PLAN.md é descartável: vive em $DO_STATE, NUNCA entra na história; a remoção é do passo 8
 2. Estado final: gstatus ; gwt diff --stat
 3. Gate FINAL completo (mesmas etapas da FASE 1; cwd $BASE_DIR; e2e acrescenta GATE_E2E) — VERMELHO => NÃO commite
 4. HTML EXPLAINER: DELEGA a um sub-agente fresco (html-explainer-agent-skill); fatos em $DO_STATE/explainer/fatos.md
 5. Commit: "$DO_WT" stage-delta && gwt commit -m "<mensagem>"   (PROIBIDO git add -A: sujeira do usuário fica de fora)
 5.5. Push: gwt push -u origin "$BASE_BRANCH" — nunca bloqueia; R8j: NUNCA mergear o branch do wt de volta
 6. Purge final: "$DO_WT" purge; echo PURGE_RC=$?; "$DO_WT" assert-clean; "$DO_WT" ledger; "$DO_WT" verify   (com ;, nunca &&)
 7. Relatório final — a FONTE de cada destino é o ledger do passo 6 (título PARCIALMENTE com NUNCA INTEGRADAS/PARCIAIS)
 7.5. Pergunta de evolução em TEXTO ao fim de tudo (pule o passo INTEIRO com no-evolve)
 8. Descarte do estado: "$DO_WT" clean-ignored-delta; if "$DO_WT" assert-clean; then rm -rf "$DO_STATE"; fi   (NESTA ordem)
FIM
    return 0
  fi
  # B01: a numeracao é EXATAMENTE a dos <step order> da FASE 3 do SKILL.md
  # (0, 1, 2, 3, 3.5, 4, 4.5, 5, 6, 7, 8, 9, 10) — re-ancorar pelo cartão não
  # pode trocar "passo 7" (os números do SKILL.md estão congelados nesta rodada).
  cat <<'CARTAO'
CARTÃO DA ONDA N — FASE 3 (troque N; `. '<ENV_FILE>'` antes de cada comando; siga o cartão e o ledger, nunca a memória)
 0. Re-ancoragem + portão surf:  "$DO_WT" checklist ; "$DO_WT" status ; "$DO_SURF_GATE"
      SURF_GATE != 0 com SEARCH_REQUIRED=sim => protocolo PESQUISA-FALHOU (a pesquisa é pré-condição, não dispensável)
 1. COMMIT PREP (se a onda tem singleton): stubs/contratos commitados em $BASE_BRANCH ANTES de criar as worktrees
 2. Portão inter-onda + criar:   "$DO_WT" assert-clean --wave N        rc != 0 => conserte pelo comando impresso
      em seguida: "$DO_WT" new feature ondaN-<nome>     rc 6 = sobra de onda anterior (mesma tabela do assert-clean)
 3. Disparar os sub-agentes da onda (teto DO_MAX_PARALLEL; dispatches escalonados)
 3.5. Subwaves da onda N-1 (gatilho = LEDGER: "$DO_WT" status):
      test-onda(N-1)-* => integrate + gate, como feature        val-onda(N-1)-* => "$DO_WT" close <nome>
 4. BARREIRA: esperar TODOS os sub-agentes (nunca prosseguir antes)
 4.5. Triagem de pesquisa: SEARCH_STATUS de CADA handoff — BLOCKED_78/FAILED_*/ausente => protocolo ANTES de integrar
 5. REPLAN: revisor de plano em BACKGROUND ao fim da triagem (recalcula a onda seguinte)
 6. Revisão adversarial por sub-tarefa concluída — o veredito é PRECONDIÇÃO do passo 7; fix NA MESMA worktree
 7. INTEGRAR UM A UM: "$DO_WT" integrate <nome> "<msg>" e logo "$DO_WT" gate <nome> (background)
      GATE VERDE = filha + snapshot fechados pelo SCRIPT. VERMELHO (rc 4) = nada limpo; NA MESMA worktree:
      git merge "$BASE_BRANCH" ANTES do fix -> fix -> integrate + gate. TETO de 2 fixes; persistiu =>
      "$DO_WT" undo <nome> (desfaz TODOS os squashes da filha) && close --discard "gate vermelho persistente"
      VAZIO (rc 4 do integrate) = a filha não trouxe mudança: re-delegue ou "$DO_WT" close <nome>
 8. Fim de onda: "$DO_WT" sweep && "$DO_WT" assert-clean --wave N+1 ; "$DO_WT" verify    rc != 0 NÃO é ignorável
 9. Handoff da onda no TASK_PLAN.md (aprendizados, fatos NÃO VERIFICADOS da triagem, destino de cada sub-tarefa)
10. Subwaves pós-onda: full = test-ondaN-* + val-ondaN-gate | none = só val-ondaN-gate
      | e2e = test-ondaN-e2e-<jornada> (gate <nome> --e2e; com DO_TEST_MODE=e2e o e2e liga sozinho) + val-ondaN-gate
FIM DA EXECUÇÃO: "$DO_WT" purge (rc 3 = NEVER-MERGED/MERGED-PARTIAL — cole o bloco no relatório)
      -> "$DO_WT" assert-clean -> "$DO_WT" ledger (fonte da seção "Não integrado")
CARTAO
  # Rodada de pergunta do do-question (DESIGN 2.3-ii): linha EXTRA, não é um
  # <step order> do SKILL.md — por isso nunca começa com um número de passo.
  if [ "${DO_QUESTION:-0}" = 1 ]; then
    echo "      Pergunta da onda (do-question): no máximo 1 rodada por onda, ao FIM (depois do passo 8), nunca com filha integrada"
  fi
}
case "${1:-}" in
  ""|-h|--help) sed -n '2,/^# ====*$/p' "$0"; exit 0 ;;
  checklist)    cmd_checklist "${2:-}"; exit 0 ;;
esac

: "${BASE_DIR:?do-wt.sh: sourceie o ENV_FILE da FASE 0 antes (ou use --env <arquivo>)}"
: "${OWNED:?ENV_FILE incompleto: OWNED}"
: "${CHILD_ROOT:?ENV_FILE incompleto: CHILD_ROOT}"
: "${BRANCH_NS:?ENV_FILE incompleto: BRANCH_NS}"
: "${RUN_ID:?ENV_FILE incompleto: RUN_ID}"
# F4-07.10: BASE_BRANCH vazio + HEAD destacado fazia o gassert passar
# indevidamente; DO_STATE é usado por sweep/verify/stage-delta/clean-ignored.
: "${BASE_BRANCH:?ENV_FILE incompleto: BASE_BRANCH}"
: "${DO_STATE:?ENV_FILE incompleto: DO_STATE}"

gwt()  { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$BASE_DIR" "$@"; }
gch()  { local p="$1"; shift; env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$p" "$@"; }
gstatus() { gwt status --porcelain "$@" -- ':(exclude,top).deep-orchestrator'; }
gassert() {
  local h; h=$(gwt symbolic-ref -q --short HEAD 2>/dev/null || true)
  [ "$h" = "$BASE_BRANCH" ] || { echo "RECUSADO: HEAD saiu de $BASE_BRANCH (agora: ${h:-destacado})" >&2; return 1; }
}
err() { printf '%s\n' "$*" >&2; }

LOCK_REASON="deep-orchestrator-agent-skill run=$RUN_ID"
# Lock de exclusão mútua sobre o owned.tsv (F4-07.1) — ver seção de registro.
LOCK_FILE="$OWNED.lock"
LOCK_DIR="$OWNED.lock.d"   # fallback sem flock(1) (macOS): mkdir é atômico em POSIX
LOCK_HELD=0

# --- registro (owned.tsv) ----------------------------------------------------
# colunas: 1 run_id  2 kind  3 name  4 branch  5 path  6 base_sha
#          7 pre_merge_sha  8 post_merge_sha  9 status  10 parent  11 outcome
# 10/11 NUNCA ficam vazias (placeholder "-"); 7/8 continuam podendo ser vazias
# — por isso a linha NUNCA é lida com `IFS=$'\t' read` (TAB é whitespace de IFS
# e colapsa campos vazios: o status cairia na coluna errada). Toda leitura é
# awk -F'\t' por coluna. Linha antiga de 9 colunas: 10/11 ausentes valem "-"
# na leitura e são completadas na 1ª reescrita (o cabeçalho de 9 também).
#
# Toda reescrita do arquivo passa por row_set() (ou pelo append do cmd_new) e é
# serializada por lock (F4-07.1): sem isso, dois do-wt.sh simultâneos fariam
# read-modify-write + mv em rajada e o ÚLTIMO venceria — lost update (um mark
# de uma onda paralela sumiria; pior: a linha recém-criada por um `new` sumiria
# e a worktree ficaria órfã). Merges são seriais por design, mas o `gate` roda
# em background e chama `finish` sozinho — a concorrência é REAL.
# O lock é num arquivo SEPARADO ($OWNED.lock): o OWNED é substituído por mv a
# cada escrita, e um flock sobre ele sofreria corrida de inode — o fd antigo
# travaria um inode ÓRFÃO enquanto outro processo trava o inode novo.

row_get() { awk -F'\t' -v n="$1" -v c="$2" \
  'NR>1 && $3==n { v=$c; if (c+0>=10 && v=="") v="-"; print v; exit }' "$OWNED"; }

lock_stale() { # dono morto (kill -9, timeout do harness) OU lock com mais de 30 s
  local pid m now
  pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then return 0; fi
  m=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || stat -f %m "$LOCK_DIR" 2>/dev/null || true)
  now=$(date +%s)
  case "$m" in ""|*[!0-9]*) return 1 ;; esac
  [ $((now - m)) -gt 30 ]
}

owned_lock() { # flock(1) do util-linux quando existe; senão mkdir (macOS não tem flock).
  # ATENÇÃO: NUNCA usar `exec 9>"$LOCK_FILE" 2>/dev/null` — exec sem comando
  # aplica as redireções ao shell PERMANENTEMENTE e mataria o stderr do script.
  # DO_WT_NO_FLOCK=1 força o fallback mesmo com flock no PATH (diagnóstico/teste).
  if [ "${DO_WT_NO_FLOCK:-0}" != 1 ] && command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE" \
      || { err "FALHA: não consegui abrir $LOCK_FILE"; return 1; }
    flock 9 2>/dev/null \
      || { err "FALHA: não consegui travar $LOCK_FILE (flock(1) indisponível?)"; return 1; }
    LOCK_HELD=flock
    return 0
  fi
  # AVISO no máximo 1x por processo — e, com a sentinela, 1x por execução: o
  # aviso repetido a cada escrita (9 linhas por merge) afogava os erros reais.
  if [ "${LOCK_WARNED:-0}" = 0 ]; then
    LOCK_WARNED=1
    if [ ! -e "$DO_STATE/.flock-aviso" ]; then
      : > "$DO_STATE/.flock-aviso" 2>/dev/null || true
      err "AVISO: flock(1) ausente — exclusão mútua do owned.tsv via mkdir ($LOCK_DIR)."
    fi
  fi
  local i=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if lock_stale; then
      # Quebra por RENAME (atômico: só um dos que esperam vence) e re-tenta o
      # mkdir — nunca assume a posse depois de um rm.
      mv "$LOCK_DIR" "$LOCK_DIR.velho.$$" 2>/dev/null && rm -rf "$LOCK_DIR.velho.$$"
      continue
    fi
    i=$((i+1))
    [ "$i" -lt 700 ] || { err "FALHA: não consegui travar o owned.tsv em ~35 s ($LOCK_DIR preso) — NADA foi escrito"; return 1; }
    sleep 0.05
  done
  echo "$$" > "$LOCK_DIR/pid" 2>/dev/null || true
  LOCK_HELD=mkdir
}
owned_unlock() {
  case "$LOCK_HELD" in
    flock)
      flock -u 9 2>/dev/null || true
      # fd 9 só é fechado aqui se owned_lock o abriu antes — nunca `2>/dev/null`
      # junto (o exec sem comando tornaria a redireção permanente).
      exec 9>&- || true ;;
    mkdir) rm -rf "$LOCK_DIR" ;;
  esac
  LOCK_HELD=0
}
trap 'owned_unlock' EXIT   # saída no meio da seção crítica não deixa o lock preso

row_set() { # <nome> <col> <valor> [<col2> <valor2> [<col3> <valor3>]] — reescrita atômica serializada
  local n="$1" c="$2" v="$3" c2="${4:-0}" v2="${5:-}" c3="${6:-0}" v3="${7:-}" tmp="$OWNED.tmp.$$"
  owned_lock || return 1
  awk -F'\t' -v OFS='\t' -v n="$n" -v c="$c" -v v="$v" -v c2="$c2" -v v2="$v2" -v c3="$c3" -v v3="$v3" '
      NR==1 && NF==9 { print $0, "parent", "outcome"; next }
      NR>1 && $3==n { for (i=NF+1; i<=11; i++) $i="-"
                      $c = v; if (c2+0 > 0) $c2 = v2; if (c3+0 > 0) $c3 = v3 }
      { print }' "$OWNED" > "$tmp" \
    && mv "$tmp" "$OWNED" \
    || { rm -f "$tmp" 2>/dev/null; owned_unlock; return 1; }
  owned_unlock
}

# --- onda e sobras (awk compartilhado) ---------------------------------------
# Onda de uma linha = N de ^(test-|val-)?onda([0-9]+)- no name; snapshot
# (kind=integration) herda a onda do parent (linha legada sem parent: int-<x>
# herda de <x>); nome sem onda (ex.: fix-final-*) vale -1 e não entra em (a)/(b).
AWK_LIB='
function wave_name(n,   s) {
  if (match(n, /^(test-|val-)?onda[0-9]+-/)) { s = substr(n, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); return s + 0 }
  return -1
}
function wave_row(n, k, par,   t) {
  if (k == "integration") {
    if (par != "" && par != "-") return wave_name(par)
    t = n; sub(/^int-/, "", t); return wave_name(t)
  }
  return wave_name(n)
}
function load_row() { K[$3] = $2; ST[$3] = $9; POST[$3] = $8; PAR[$3] = $10 }
function parent_of(n,   p) { p = PAR[n]; if (p == "" || p == "-") { p = n; sub(/^int-/, "", p) } return p }
function gstate(n,   i, m, a, b) { # estado do gate de n — pré-computado em shell (gate_states) e passado por ENVIRON
  if (!GS_INIT) {
    GS_INIT = 1; m = split(ENVIRON["DO_GATE_STATES"], a, "\n")
    for (i = 1; i <= m; i++) if (split(a[i], b, "\t") >= 2) GS[b[1]] = b[2]
  }
  return (n in GS) ? GS[n] : "none"
}
# hint(n) lê K/ST/POST/PAR: o chamador roda load_row() em TODAS as linhas antes.
# Snapshot com parent INTEGRADO vivo => dica do PARENT (fechar o snapshot com o
# gate em voo tira o cwd de baixo dele => VERMELHO falso). gate-pending lê o .rc:
# rodando => aguarde; vermelho => fix (NUNCA `finish --gate-ok` como conserto).
function hint(n,   k, st, post, p, g) {
  k = K[n]; st = ST[n]; post = POST[n]
  if (k == "integration" && st != "REMOVED") {
    p = parent_of(n)
    if (p != n && (p in ST) && (ST[p] == "gate-pending" || ST[p] == "MERGED") && POST[p] != "")
      return "é o snapshot do gate de " p " — NÃO feche com o gate em voo; resolva o PARENT: " hint(p)
  }
  if (k == "integration" || k == "validation") return "\"$DO_WT\" close " n
  if (st == "MERGED" && post != "") return "\"$DO_WT\" finish " n
  if (st == "gate-pending" && post != "") {
    g = gstate(n)
    if (g == "running" || g == "running?")
      return "AGUARDE — o gate de " n " está rodando em background (tail -f \"$DO_STATE/gates/" n ".log\"); NÃO rode outro"
    if (g == "green") return "\"$DO_WT\" finish " n
    if (g ~ /^covered:/)
      return "\"$DO_WT\" finish " n " --gate-ok     (vermelho próprio, mas o gate VERDE de " substr(g, 9) " já contém este squash)"
    if (g ~ /^red:/)
      return "gate VERMELHO (rc=" substr(g, 5) "): fix NA MESMA worktree (git merge \"$BASE_BRANCH\" ANTES do fix) -> \"$DO_WT\" integrate " n " \"<msg>\" -> \"$DO_WT\" gate " n "   |   desistir: \"$DO_WT\" undo " n " && \"$DO_WT\" close " n " --discard \"gate vermelho persistente\""
    return "\"$DO_WT\" gate " n
  }
  if (st == "REVERTED")
    return "re-integrar: \"$DO_WT\" integrate " n " \"<msg>\"   |   descartar: \"$DO_WT\" close " n " --discard \"<motivo>\""
  if (st == "REMOVED") return (post != "") ? "\"$DO_WT\" finish " n : "\"$DO_WT\" close " n "   (com trabalho: --discard \"<motivo>\")"
  return "integrar: \"$DO_WT\" integrate " n " \"<msg>\" && \"$DO_WT\" gate " n "   |   descartar: \"$DO_WT\" close " n " --discard \"<motivo>\""
}'

wave_of() { # <nome> -> N (vazio se o nome não tem onda)
  awk -v n="$1" "$AWK_LIB"' BEGIN { w = wave_name(n); if (w >= 0) print w }'
}

# --- estado do gate (.rc) ------------------------------------------------------
# $DO_STATE/gates/<nome>.rc: "running <pid> <post_sha>" enquanto roda; ao fim
# "<rc> <post_sha>" — o veredito vale SÓ para o squash em que rodou (col 8).
# Formato antigo ("running" / "<rc>", sem pid/sha) continua sendo lido.
covered_by() { # <post_sha> -> nome de um gate VERDE cujo SHA (ainda em $BASE_BRANCH) contém este squash
  local post="$1" f a b c
  for f in "$DO_STATE/gates"/*.rc; do
    [ -f "$f" ] || continue
    a=""; b=""; read -r a b c < "$f" || true
    [ "$a" = 0 ] && [ -n "$b" ] && [ "$b" != "$post" ] || continue
    gwt merge-base --is-ancestor "$post" "$b" 2>/dev/null \
      && gwt merge-base --is-ancestor "$b" HEAD 2>/dev/null || continue
    f="${f##*/}"; printf '%s\n' "${f%.rc}"; return 0
  done
  return 1
}
gate_state() { # <nome> -> none | running | running? | dead | stale | green | red:<rc> | covered:<gate-verde>
  local name="$1" f="$DO_STATE/gates/$1.rc" post a="" b="" c="" cov
  post=$(row_get "$name" 8)
  [ -s "$f" ] || { echo none; return 0; }
  read -r a b c < "$f" || true
  case "$a" in
    running)
      case "$b" in
        "")        echo "running?" ;;                                   # formato antigo: sem pid para conferir
        *[!0-9]*)  echo none ;;
        *)         if kill -0 "$b" 2>/dev/null; then echo running; else echo dead; fi ;;
      esac ;;
    ""|*[!0-9]*) echo none ;;
    *)
      if [ -n "$b" ] && [ "$b" != "$post" ]; then echo stale             # veredito de OUTRO squash
      elif [ "$a" = 0 ]; then echo green
      elif cov=$(covered_by "$post"); then echo "covered:$cov"
      else echo "red:$a"; fi ;;
  esac
}
gate_states() { # "nome<TAB>estado" de cada gate-pending — vai para o awk via ENVIRON (ver gstate)
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    printf '%s\t%s\n' "$n" "$(gate_state "$n")"
  done < <(awk -F'\t' 'NR>1 && $9=="gate-pending" && $8!="" {print $3}' "$OWNED")
}

ledger_leftovers() { # <N|""> -> sobras (a)+(b) do assert-clean; N vazio = TODA linha não-REMOVED
  # 2 passadas (NR==FNR carrega o ledger): o snapshot herda a ONDA e também a
  # REGRA DO KIND DO PARENT — o snapshot de test-onda(N-1)-* vale como test
  # (limiar N-1); senão o passo 3.5 travava `new fix ondaN-*` com rc 6.
  DO_GATE_STATES="$(gate_states)" awk -F'\t' -v N="$1" "$AWK_LIB"'
    NR==FNR { if (FNR>1) load_row(); next }
    FNR>1 && $9!="REMOVED" {
      w = wave_row($3, $2, $10); k = $2; bad = 0
      if (k == "integration") { p = parent_of($3); if ((p in K) && (K[p]=="test" || K[p]=="validation")) k = "test" }
      if (N == "") bad = 1
      else if (w >= 0) {
        if ((k=="feature" || k=="fix" || k=="prep" || k=="integration") && w < N+0) bad = 1
        if ((k=="test" || k=="validation") && w < N-1) bad = 1
      }
      if (bad) printf "  SOBRA  %-28s kind=%-11s onda=%-3s status=%s\n         conserto: %s\n", \
                      $3, $2, (w >= 0 ? w : "-"), $9, hint($3)
    }' "$OWNED" "$OWNED"
}

reality_leftovers() { # (c) REALIDADE x ledger — só o que é provadamente nosso:
  # $CHILD_ROOT e $BRANCH_NS contêm o RUN_ID. Nunca deriva ALVO de `git worktree
  # list` global (R8d): aqui só se RELATA; quem fecha é finish/close, por nome.
  local d r row
  if [ -d "$CHILD_ROOT" ]; then
    for d in "$CHILD_ROOT"/*; do
      [ -e "$d" ] || continue
      row=$(awk -F'\t' -v p="$d" "$AWK_LIB"' NR>1 { load_row() } NR>1 && $5==p { n=$3; st=$9; f=1 }
            END { if (!f) print "?"; else if (st=="REMOVED") print n "\t" hint(n) }' "$OWNED")
      case "$row" in
        "") : ;;
        "?") printf '  SOBRA  %s\n         diretório em CHILD_ROOT SEM linha no owned.tsv (posse não provada: sem comando automático — inspecione e registre no relatório)\n' "$d" ;;
        *)  printf '  SOBRA  %-28s linha REMOVED, mas o diretório ainda existe (%s)\n         conserto: %s\n' "${row%%$'\t'*}" "$d" "${row#*$'\t'}" ;;
      esac
    done
  fi
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    row=$(awk -F'\t' -v b="$r" "$AWK_LIB"' NR>1 { load_row() } NR>1 && $4==b { f=1; if ($9!="REMOVED") live=1; n=$3 }
          END { if (!f) print "?"; else if (!live) print n "\t" hint(n) }' "$OWNED")
    case "$row" in
      "") : ;;
      "?") printf '  SOBRA  refs/heads/%s\n         branch sob o namespace desta execução SEM linha no owned.tsv (sem comando automático — inspecione e registre no relatório)\n' "$r" ;;
      *)  printf '  SOBRA  %-28s linha REMOVED, mas o branch %s ainda existe\n         conserto: %s\n' "${row%%$'\t'*}" "$r" "${row#*$'\t'}" ;;
    esac
  done < <(gwt for-each-ref --format='%(refname:short)' "refs/heads/$BRANCH_NS/" 2>/dev/null)
}

# --- guardas de posse --------------------------------------------------------
# A guarda de lock lê o REGISTRO porcelain inteiro. Contagem de linhas (grep -A2)
# quebra: `locked` é a 4ª linha, e registros `detached`/`prunable` deslocam tudo.
owns_lock() { # <path>
  gwt worktree list --porcelain -z 2>/dev/null | tr '\0' '\n' \
    | awk -v p="$1" -v r="locked $LOCK_REASON" '
        $0 == "worktree " p { inrec = 1; next }
        /^worktree /        { inrec = 0 }
        inrec && index($0, r) == 1 { found = 1 }
        END { exit !found }'
}

guard_child() { # <path> — recusa qualquer coisa que não seja filha DESTA execução
  local p="$1"
  [ -n "$p" ] || { err "RECUSADO: path vazio"; return 1; }
  awk -F'\t' -v p="$p" 'NR>1 && $5==p {found=1} END{exit !found}' "$OWNED" \
    || { err "RECUSADO: $p não está no owned.tsv desta execução"; return 1; }
  case "$p/" in "$CHILD_ROOT"/*) : ;; *) err "RECUSADO: $p está fora de CHILD_ROOT"; return 1 ;; esac
  [ "$p" = "$BASE_DIR" ] && { err "RECUSADO: é a própria raiz-de-mundo"; return 1; }
  [ -n "${MAIN_ROOT:-}" ] && [ "$p" = "$MAIN_ROOT" ] && { err "RECUSADO: é o checkout principal"; return 1; }
  if [ -e "$p" ]; then
    [ -d "$p/.git" ] && { err "RECUSADO: $p/.git é diretório — é um repositório, não uma worktree"; return 1; }
    owns_lock "$p" || { err "RECUSADO: $p não tem o lock desta execução (run=$RUN_ID) — pode ser de outra sessão"; return 1; }
  fi
  return 0
}

# --- leitura NUL-safe de status ---------------------------------------------
# `git status --porcelain` sem -z aplica C-quoting a path com espaço ou acento
# e devolve `"relat\303\263rio.md"` — que o `git add` recusa como pathspec.
status_paths() { # stdin: saída de `status --porcelain -z`  → stdout: paths, NUL-terminados
  local entry orig
  while IFS= read -r -d '' entry; do
    case "${entry:0:2}" in
      R*|C*) IFS= read -r -d '' orig && printf '%s\0' "$orig" ;;
    esac
    printf '%s\0' "${entry:3}"
  done
}

# =============================================================================
# Se uma asserção pós-add falhar (ou o append no owned.tsv), a worktree
# recém-criada NUNCA foi registrada e ficaria ÓRFÃ — inalcançável pela limpeza,
# que só aceita alvos do próprio owned.tsv. Limpeza com guarda (F4-07.6): SÓ o
# que este cmd_new acabou de criar — branch exato sob $BRANCH_NS e path exato
# sob $CHILD_ROOT. --force porque a asserção que falhou pode ter deixado sujeira.
cleanup_orphan_new() { # <branch> <path>
  local br="$1" wt="$2"
  case "$br" in "$BRANCH_NS"/*) : ;; *) err "AVISO: limpeza recusada (branch fora do namespace): $br"; return 1 ;; esac
  case "$wt/" in "$CHILD_ROOT"/*) : ;; *) err "AVISO: limpeza recusada (path fora de CHILD_ROOT): $wt"; return 1 ;; esac
  gwt worktree unlock "$wt" >/dev/null 2>&1
  if gwt worktree remove --force "$wt" >/dev/null 2>&1; then
    err "  Limpeza: worktree recém-criada removida ($wt)"
  else
    err "  AVISO: não consegui remover a worktree recém-criada $wt — remova manualmente"
  fi
  if gwt branch -D "$br" >/dev/null 2>&1; then
    err "  Limpeza: branch recém-criado apagado ($br)"
  else
    err "  AVISO: não consegui apagar o branch recém-criado $br"
  fi
}

cmd_new() { # <kind> <nome>  [<start-point> <parent>] — os 2 últimos são INTERNOS
  # (integrate/gate criam o snapshot no SHA pós-merge); o dispatcher só repassa 2.
  local kind="${1:?kind}" name="${2:?nome}" start="${3:-$BASE_BRANCH}" parent="${4:--}"
  local br="$BRANCH_NS/$name" wt="$CHILD_ROOT/$name"

  # O kind agora decide destino (integration|validation = descartável no close):
  # um kind fora do conjunto documentado não pode passar.
  case "$kind" in feature|test|validation|fix|prep|integration) : ;;
    *) err "RECUSADO: kind inválido: '$kind' — use feature|test|validation|fix|prep|integration"; return 1 ;; esac
  case "$name" in */*|.*|""|*[[:space:]]*) err "RECUSADO: nome inválido: $name"; return 1 ;; esac
  # Reservados do arquivo: refs/do-archive/$RUN_ID/<nome>-HEAD (HEAD da filha fora
  # do branch) e undo-<nome>-<k> (squash desfeito) — um nome assim colidiria.
  case "$name" in *-HEAD|undo-*)
    err "RECUSADO: nome reservado: $name ('*-HEAD' e 'undo-*' são refs de arquivo desta execução) — use outro"; return 1 ;; esac
  [ -z "$(row_get "$name" 3)" ] || {
    err "RECUSADO: o nome $name já consta do owned.tsv desta execução (status=$(row_get "$name" 9)) — use outro (ex.: $name-r2)"
    return 1; }

  # (ii) no-test: NÃO cria testes — a recusa é do script, não da prosa.
  if [ "${DO_TEST_MODE:-full}" = none ]; then
    case "$kind:$name" in test:*|*:test-onda*)
      err "RECUSADO: TEST_MODE=none (no-test) — esta execução NÃO cria worktree de teste ($kind $name)."
      err "  (o gate e a validation subwave continuam: no-test = não CRIAR teste, != não rodar)"
      return 1 ;; esac
  fi

  # (i) PORTÃO INTER-ONDA: a onda N não abre com sobra de onda anterior — mesma
  # checagem (a)+(b) e mesma tabela de conserto do `assert-clean --wave N`.
  case "$kind" in feature|fix|prep)
    local wn lo
    wn=$(wave_of "$name")
    if [ -n "$wn" ]; then
      lo=$(ledger_leftovers "$wn")
      if [ -n "$lo" ]; then
        err "RECUSADO: onda $wn BLOQUEADA — há sobra de onda anterior. Feche cada linha pelo comando e repita:"
        printf '%s\n' "$lo" >&2
        return 6
      fi
    fi ;;
  esac

  gwt show-ref --verify --quiet "refs/heads/$br" && { err "RECUSADO: branch $br já existe"; return 1; }
  [ -e "$wt" ] && { err "RECUSADO: $wt já existe"; return 1; }
  gassert || return 1

  mkdir -p "$CHILD_ROOT" || return 1
  # Base = BASE_BRANCH, o branch DESTA raiz-de-mundo. NUNCA main/master, NUNCA origin/*.
  # (snapshot de integração: o SHA pós-merge da filha, que É um commit de BASE_BRANCH.)
  gwt worktree add -q -b "$br" "$wt" "$start" || { err "FALHA: git worktree add"; return 1; }
  # (iii) Sem o lock de posse a filha nasceria IRREMOVÍVEL (guard_child exige o
  # lock desta execução): falhar ao travar é falha do new, não AVISO (F11).
  gwt worktree lock --reason "$LOCK_REASON" "$wt" \
    || { err "FALHA: não consegui travar $wt com o lock de posse desta execução"; cleanup_orphan_new "$br" "$wt"; return 1; }

  # Isolamento já falhou em silêncio em produção — asseverar.
  [ -f "$wt/.git" ] || { err "FALHA: $wt/.git não é arquivo (não é worktree)"; cleanup_orphan_new "$br" "$wt"; return 1; }
  [ "$(gch "$wt" rev-parse --show-toplevel)" = "$wt" ] || { err "FALHA: toplevel divergente"; cleanup_orphan_new "$br" "$wt"; return 1; }
  [ "$(gch "$wt" symbolic-ref --short HEAD)" = "$br" ] || { err "FALHA: branch errado"; cleanup_orphan_new "$br" "$wt"; return 1; }

  owned_lock || { cleanup_orphan_new "$br" "$wt"; return 1; }
  # Linha nova SEMPRE com 11 colunas (7/8 vazias; parent/outcome = "-" se n/a).
  if ! printf '%s\t%s\t%s\t%s\t%s\t%s\t\t\t%s\t%s\t%s\n' \
      "$RUN_ID" "$kind" "$name" "$br" "$wt" "$(gch "$wt" rev-parse HEAD)" "ACTIVE" "$parent" "-" >> "$OWNED"; then
    owned_unlock
    cleanup_orphan_new "$br" "$wt"
    return 1
  fi
  owned_unlock

  printf 'OK  worktree=%s\n    branch=%s\n' "$wt" "$br"
}

# =============================================================================
# Commits INTERNOS (wip de restos, rescue do finish/close) usam --no-verify: o
# hook do repo-alvo (husky/lint-staged) não pode travar a orquestração — a
# qualidade é do gate. Nunca entram na história final (squash) e gpg sem TTY
# só atrapalharia. O commit do SQUASH também é --no-verify, mas mantém a
# assinatura/identidade do usuário.
wip_commit() { # <dir> <mensagem>
  gch "$1" -c commit.gpgsign=false commit -q --no-verify -m "$2"
}

# O diretório É uma worktree git com toplevel próprio? Sem isto, `git -C <dir>`
# num diretório sem .git subiria até o repositório de FORA (placement nested) e
# leria o HEAD errado.
is_child_wt() { # <path>
  [ -d "$1" ] && [ -f "$1/.git" ] && [ "$(gch "$1" rev-parse --show-toplevel 2>/dev/null)" = "$1" ]
}

# A filha TEM de estar no branch registrado. O sub-agente que faz `git checkout
# <sha>` / `git switch -c outro` (ou morre no meio de um rebase) commita FORA de
# refs/heads/<branch registrado>: o squash não veria esse trabalho e o
# arquivamento do branch guardaria um ref vazio. Imprime "<sha-do-HEAD> <branch
# atual|vazio se destacado>" quando o HEAD da filha != tip do branch registrado
# (HEAD destacado NO MESMO commit é inofensivo: não imprime nada).
child_head_off() { # <nome>
  local br wt tip="" wh cur
  br=$(row_get "$1" 4); wt=$(row_get "$1" 5)
  is_child_wt "$wt" || return 0
  wh=$(gch "$wt" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || true)
  [ -n "$wh" ] || return 0
  gwt show-ref --verify --quiet "refs/heads/$br" && tip=$(gwt rev-parse "refs/heads/$br")
  [ "$wh" != "$tip" ] || return 0
  cur=$(gch "$wt" symbolic-ref -q --short HEAD 2>/dev/null || true)
  [ "$cur" != "$br" ] || return 0
  printf '%s %s\n' "$wh" "$cur"
}

# close/finish/purge/remove: ANTES de destruir, o HEAD da filha que não é o tip
# do branch registrado também vai para o arquivo — refs/do-archive/$RUN_ID/<nome>-HEAD.
archive_child_head() { # <nome>
  local name="$1" off wh cur
  off=$(child_head_off "$name"); [ -n "$off" ] || return 0
  wh="${off%% *}"; cur="${off#* }"
  gwt update-ref "refs/do-archive/$RUN_ID/$name-HEAD" "$wh" \
    || { err "FALHA ao arquivar o HEAD da filha $name em refs/do-archive/$RUN_ID/$name-HEAD — nada foi removido"; return 1; }
  err "AVISO: o HEAD de $name NÃO era o branch registrado (HEAD=${cur:-destacado} @ $(printf '%s' "$wh" | cut -c1-7)) — arquivado TAMBÉM em refs/do-archive/$RUN_ID/$name-HEAD (relate)"
  case "$cur" in ""|"$BRANCH_NS"/*) : ;;
    *) err "  branch FORA do namespace criado na filha e NÃO apagado pelo script: $cur   (relate; se for lixo: git branch -D \"$cur\")" ;; esac
  return 0
}

rescue_commit() { # <nome> — restos não commitados da filha viram commit (no HEAD dela): --force nunca passa por cima de trabalho não salvo
  local name="$1" wt; wt=$(row_get "$1" 5)
  [ -d "$wt" ] || return 0
  [ -n "$(gch "$wt" status --porcelain -- ':(exclude,top).deep-orchestrator' 2>/dev/null)" ] || return 0
  gch "$wt" add -A -- ':(exclude,top).deep-orchestrator' \
    && { gch "$wt" diff --cached --quiet || wip_commit "$wt" "wip: restos de $name (fechamento)"; } \
    || { err "FALHA: não consegui salvar os restos de $name num commit — worktree PRESERVADA (nada é forçado sobre trabalho não salvo)"; return 1; }
}

squash_rollback() { # desfaz o índice de um squash cujo commit falhou
  # Tudo que está estagiado aqui é DO SQUASH: o guard de índice garantiu índice
  # == HEAD antes do merge, e o git recusa o squash se um path tocado estiver
  # sujo/untracked na raiz. Restaura os paths do HEAD e remove os que o squash
  # criou (não existem no HEAD). --no-renames: senão sobra "D <path-antigo>".
  local all added p
  all=$(gwt diff --cached --name-only --no-renames -z | tr '\0' '\n')
  added=$(gwt diff --cached --name-only --no-renames --diff-filter=A -z | tr '\0' '\n')
  gwt diff --cached --name-only --no-renames -z \
    | GIT_LITERAL_PATHSPECS=1 gwt restore --staged --worktree --source=HEAD \
        --pathspec-from-file=- --pathspec-file-nul 2>/dev/null
  # git antigo (< 2.25, sem --pathspec-from-file) ou restore parcial: reset mixed
  # + checkout dos que existem no HEAD, path a path.
  if ! gwt diff --cached --quiet; then
    gwt reset -q || return 1
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      printf '%s\n' "$added" | grep -qxF -- "$p" && continue
      GIT_LITERAL_PATHSPECS=1 gwt checkout -q HEAD -- "$p" || return 1
    done <<< "$all"
  fi
  # Os que o squash CRIOU não existem no HEAD: sobrariam como untracked e o git
  # recusaria o re-merge ("untracked working tree files would be overwritten").
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -e "$BASE_DIR/$p" ] && ! gwt ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
      rm -f -- "$BASE_DIR/$p"
    fi
  done <<< "$added"
  gwt diff --cached --quiet
}

# RE-integração (já há squash VIVO desta filha em $BASE_BRANCH) de um branch que
# NÃO contém esse squash: o merge-base continua sendo o base_sha antigo e o merge
# de 3 vias descarta EM SILÊNCIO toda deleção/reversão do fix ("theirs == base"
# => fica o "ours"). Verificado em lab: saía "sem delta novo", rc 0, e o gate
# nunca mais ficava verde. Imprime os paths que a filha tocou e que NÃO chegariam
# à árvore do merge idênticos aos da filha. Fix só aditivo não imprime nada;
# REVERTED não entra (o re-merge pós-undo é legítimo).
reint_lost() { # <nome> <branch> <tree-do-merge-em-memória>
  local name="$1" br="$2" tree="$3" prev bsha p
  prev=$(row_get "$name" 8); bsha=$(row_get "$name" 6)
  [ -n "$prev" ] && [ -n "$bsha" ] && [ -n "$tree" ] || return 0
  [ "$(row_get "$name" 9)" != REVERTED ] || return 0
  gwt merge-base --is-ancestor "$prev" HEAD 2>/dev/null || return 0   # squash saiu por reset (undo)
  gwt merge-base --is-ancestor "$prev" "$br" 2>/dev/null && return 0  # a filha já contém o squash
  { gwt -c core.quotePath=false diff --name-only "$bsha" "$br"
    gwt -c core.quotePath=false diff --name-only "$prev^" "$prev"; } 2>/dev/null | sort -u \
  | while IFS= read -r p; do
      [ -n "$p" ] || continue
      [ "$(gwt rev-parse -q --verify "$tree:$p" 2>/dev/null)" = "$(gwt rev-parse -q --verify "$br:$p" 2>/dev/null)" ] \
        || printf '%s\n' "$p"
    done
  return 0
}

cmd_merge() { # <nome> <mensagem>
  local name="${1:?nome}" msg="${2:?mensagem}"
  local br wt
  br=$(row_get "$name" 4); wt=$(row_get "$name" 5)
  [ -n "$br" ] || { err "RECUSADO: $name não está no owned.tsv"; return 1; }
  gassert || return 1
  gwt show-ref --verify --quiet "refs/heads/$br" \
    || { err "RECUSADO: o branch $br já não existe (status=$(row_get "$name" 9)) — nada a mergear"; return 1; }

  # Resíduo de squash INTERROMPIDO (processo morto entre o merge e o rollback,
  # ou versão antiga deste script, que deixava o conflito no índice): entradas
  # não-mergeadas SEM operação do usuário em andamento (squash nunca grava
  # MERGE_HEAD). O índice era == HEAD quando o squash começou (guard abaixo),
  # então `reset --merge` devolve a raiz EXATAMENTE ao pré-merge e preserva a
  # sujeira não estagiada do usuário (verificado em lab; o `reset` mixed +
  # checkout por arquivo de antes deixava a meia-feature no working tree e o
  # re-merge nunca convergia). Se algum path já não tem marcador, alguém
  # resolveu NA RAIZ — não destruímos: recusa e manda decidir à mão.
  local unmerged p resolved_in_root=0
  unmerged=$(gwt diff --name-only --diff-filter=U 2>/dev/null)
  if [ -n "$unmerged" ] \
     && ! [ -f "$(gwt rev-parse --git-path MERGE_HEAD 2>/dev/null)" ] \
     && ! [ -f "$(gwt rev-parse --git-path CHERRY_PICK_HEAD 2>/dev/null)" ] \
     && ! [ -f "$(gwt rev-parse --git-path REBASE_HEAD 2>/dev/null)" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      grep -q '^<<<<<<< ' "$BASE_DIR/$p" 2>/dev/null || resolved_in_root=1
    done <<< "$unmerged"
    if [ "$resolved_in_root" = 1 ]; then
      err "RECUSADO: há um squash interrompido na raiz-de-mundo com resolução manual (path sem marcador)."
      err "  Decida à mão: leve a resolução para DENTRO da filha ($wt) e descarte o resíduo da raiz."
      return 1
    fi
    err "AVISO: resíduo de squash interrompido na raiz-de-mundo — desfazendo (reset --merge) antes do merge."
    gwt reset -q --merge || { err "FALHA: não consegui desfazer o resíduo do squash"; return 1; }
  fi

  # `git commit` após um squash-merge comita o ÍNDICE INTEIRO. Se o usuário
  # deixou algo estagiado na raiz-de-mundo, entraria no commit da sub-tarefa.
  gwt diff --cached --quiet || {
    err "RECUSADO: a raiz-de-mundo tem mudanças ESTAGIADAS que não são desta execução."
    err "  O squash-commit as engoliria. Resolva antes:"
    gwt diff --cached --name-only | sed 's/^/    /' >&2
    return 1
  }

  # Trabalho não commitado na filha seria PERDIDO na limpeza.
  if [ -d "$wt" ] && [ -n "$(gch "$wt" status --porcelain)" ]; then
    gch "$wt" add -A -- ':(exclude,top).deep-orchestrator' \
      && { gch "$wt" diff --cached --quiet || wip_commit "$wt" "wip: restos de $name"; } \
      || { err "FALHA: não consegui commitar restos em $wt"; return 1; }
  fi

  # (0) A filha saiu do branch registrado (HEAD destacado / `git switch -c`): o
  # squash de $br NÃO veria o trabalho e sairia "VAZIO" (rc 4) mandando fechar a
  # filha. Depois do wip-commit acima, para os restos já estarem salvos no SHA.
  local off; off=$(child_head_off "$name")
  if [ -n "$off" ]; then
    local offsha="${off%% *}" offbr="${off#* }"
    err "RECUSADO: a filha $name saiu do branch registrado (HEAD=${offbr:-destacado} @ $(printf '%s' "$offsha" | cut -c1-7); registrado: $br) — o squash NÃO veria esse trabalho. NADA foi tocado na raiz-de-mundo."
    err "  1) git -C \"$wt\" switch \"$br\" && git -C \"$wt\" merge $offsha      (rebase/merge em andamento na filha? termine ou aborte antes)"
    err "  2) Re-execute este comando."
    case "$offbr" in ""|"$BRANCH_NS"/*) : ;;
      *) err "  O branch '$offbr' foi criado na filha FORA do namespace desta execução: o script NÃO o apaga — depois do passo 1: git -C \"$wt\" branch -D \"$offbr\" (e relate)." ;; esac
    return 1
  fi

  # (1) CONFLITO detectado ANTES de tocar a árvore (git >= 2.38): merge-tree
  # --write-tree faz o merge em memória. rc 0 = limpo; rc 1 COM saída (OID da
  # árvore + paths em conflito) = conflito. Qualquer outra coisa (git antigo:
  # rc 129) cai no fluxo antigo abaixo, que desfaz o squash falho.
  # DO_WT_MERGE_TREE=0 força o fluxo antigo (diagnóstico/teste).
  local mt mtrc
  if [ "${DO_WT_MERGE_TREE:-1}" = 1 ]; then
    mt=$(gwt merge-tree --write-tree --name-only --no-messages HEAD "$br" 2>/dev/null); mtrc=$?
    if [ "$mtrc" = 1 ] && [ -n "$mt" ]; then
      err "CONFLITO: o squash de $br conflita com $BASE_BRANCH — NADA foi tocado na raiz-de-mundo. Paths:"
      printf '%s\n' "$mt" | tail -n +2 | sed 's/^/    /' >&2
      err "  1) Resolva DENTRO da filha:  git -C \"$wt\" merge \"$BASE_BRANCH\"   (resolva e commite LÁ)."
      err "  2) Re-execute este comando. Não há nada a desfazer na raiz (nem reset, nem merge --abort)."
      return 1
    fi
    # (1b) merge limpo, mas é RE-integração de filha que não contém o squash
    # anterior: confere em memória se o fix chega inteiro (ver reint_lost).
    local lost=""
    [ "$mtrc" = 0 ] && lost=$(reint_lost "$name" "$br" "$(printf '%s\n' "$mt" | head -n 1)")
    if [ -n "$lost" ]; then
      local tip; tip=$(gwt rev-parse --short "$br")
      err "RECUSADO: a re-integração de $br PERDERIA parte do fix — NADA foi tocado na raiz-de-mundo."
      err "  O squash anterior ($(row_get "$name" 8 | cut -c1-7)) já está em $BASE_BRANCH e a filha NÃO o contém: o merge de 3 vias"
      err "  descarta EM SILÊNCIO deleção/reversão do fix (ou há mudança concorrente). Paths em que o merge != filha:"
      printf '%s\n' "$lost" | sed 's/^/    /' >&2
      err "  1) git -C \"$wt\" merge \"$BASE_BRANCH\"     (traz o squash para DENTRO da filha — e pode trazer de volta o que o fix apagou)"
      err "  2) Reaplique o fix nesses paths e commite LÁ  (o fix está em $tip:  git -C \"$wt\" diff HEAD $tip -- <path>)"
      err "  3) Re-execute este comando.   Regra: após gate VERMELHO, faça o merge de $BASE_BRANCH na filha ANTES de começar o fix."
      return 1
    fi
  fi

  local pre; pre=$(gwt rev-parse HEAD)

  if ! gwt merge --squash "$br"; then
    local upaths; upaths=$(gwt diff --name-only --diff-filter=U 2>/dev/null)
    if [ -n "$upaths" ]; then
      # Squash-merge não grava MERGE_HEAD (`merge --abort` não serve): o rollback
      # é `reset --merge`, seguro porque o índice era == HEAD antes do squash.
      gwt reset -q --merge || err "FALHA: o rollback (reset --merge) não completou — confira com gstatus"
      err "CONFLITO no squash-merge de $br (rollback FEITO — raiz-de-mundo restaurada). Paths:"
      printf '%s\n' "$upaths" | sed 's/^/    /' >&2
      err "  1) Resolva DENTRO da filha:  git -C \"$wt\" merge \"$BASE_BRANCH\"   (resolva e commite LÁ)."
      err "  2) Re-execute este comando."
    else
      err "RECUSADO pelo git: o squash de $br nem começou (erro acima). NÃO é conflito de merge:"
      err "  há mudança local/untracked na raiz-de-mundo sobreposta aos arquivos da filha. Nada foi alterado."
    fi
    return 1
  fi

  # (4) Squash SEM mudança NÃO vira MERGED: o sub-agente não produziu nada NESTA
  # worktree (escreveu fora dela? morreu?). Marcar MERGED aqui escondia a falha.
  if gwt diff --cached --quiet; then
    if [ -n "$(row_get "$name" 8)" ]; then
      # O tip integrado ANDA mesmo sem delta (ex.: a filha só fez o merge do
      # $BASE_BRANCH): senão o finish acusaria "cauda não integrada" no fluxo normal.
      record_integrated_tip "$name" "$br" || return 1
      echo "OK  re-merge de $br sem delta novo — o squash anterior ($(row_get "$name" 8 | cut -c1-7)) segue valendo"
      return 0
    fi
    err "VAZIO: $br nao trouxe mudanca — re-delegue ou \`close $name\`"
    return 4
  fi

  # (2)+(3) --no-verify; se o commit falhar MESMO assim (prepare-commit-msg, gpg,
  # identidade), o índice do squash é desfeito — senão o re-merge seria recusado
  # pelo guard de índice com uma mensagem que culpava o usuário.
  if ! gwt commit -q --no-verify -m "$msg"; then
    err "FALHA: o git recusou o commit do squash de $br (saída acima — hook prepare-commit-msg? gpg? identidade?)."
    if squash_rollback; then
      err "  Rollback OK: a raiz-de-mundo voltou ao pré-merge; filha e branch intactos (status inalterado)."
      err "  Corrija a causa e re-execute — o re-merge é seguro."
    else
      err "  ROLLBACK INCOMPLETO: o índice de $BASE_DIR ainda contém o squash de $br (é DESTA execução, não do usuário)."
      err "  NÃO use reset --hard. Confira com gstatus e reporte."
    fi
    return 1
  fi

  # RE-integração (fix após gate vermelho, na MESMA linha) NÃO sobrescreve o pre
  # do 1º squash: col 7 = pre do PRIMEIRO squash vivo (undo e wave-files partem
  # dele); col 8 = ÚLTIMO post (gate/reint_lost/finish usam o último). A lista
  # completa vive em $DO_STATE/squashes/<nome> (1 SHA por linha, do mais antigo ao
  # mais novo) e é TRUNCADA quando não há squash vivo (1º merge ou re-merge
  # pós-undo) — só anexar faria o próximo undo reverter SHAs já desfeitos.
  local newsha prev sq="$DO_STATE/squashes/$name"
  newsha=$(gwt rev-parse HEAD); prev=$(row_get "$name" 8)
  mkdir -p "$DO_STATE/squashes" || return 1
  if [ -n "$prev" ] && [ "$(row_get "$name" 9)" != REVERTED ] \
     && gwt merge-base --is-ancestor "$prev" "$pre" 2>/dev/null; then
    [ -s "$sq" ] || printf '%s\n' "$prev" > "$sq" || return 1     # linha legada: semeia com o 1º post
    printf '%s\n' "$newsha" >> "$sq" || return 1
    row_set "$name" 8 "$newsha" 9 MERGED || return 1
  else
    printf '%s\n' "$newsha" > "$sq" || return 1
    row_set "$name" 7 "$pre" 8 "$newsha" 9 MERGED || return 1
  fi
  record_integrated_tip "$name" "$br" || return 1
  printf 'OK  squash de %s -> %s (%s)\n' "$br" "$BASE_BRANCH" "$(gwt rev-parse --short HEAD)"
}

# Tip da filha que JÁ ESTÁ no squash (o wip-commit dos restos veio antes). O
# finish compara com o tip na hora de fechar: conteúdo novo depois disto = cauda
# NÃO integrada (MERGED-PARTIAL), nunca "MERGED" em silêncio.
record_integrated_tip() { # <nome> <branch>
  mkdir -p "$DO_STATE/gates" && gwt rev-parse "refs/heads/$2" > "$DO_STATE/gates/$1.tip"
}

# =============================================================================
cmd_undo() { # <nome> — desfaz TODOS os squashes vivos de UMA filha (o original e o de cada fix re-integrado)
  local name="${1:?nome}" pre post sq list live="" asc="" s k n=0
  pre=$(row_get "$name" 7); post=$(row_get "$name" 8); sq="$DO_STATE/squashes/$name"
  gassert || return 1
  [ -n "$post" ] || { err "RECUSADO: $name não tem squash-commit registrado"; return 1; }
  [ "$(row_get "$name" 9)" != REVERTED ] \
    || { err "RECUSADO: $name já está REVERTED — os squashes dela já foram desfeitos (re-integrar: do-wt.sh integrate $name \"<msg>\")"; return 1; }

  # Lista do mais NOVO ao mais ANTIGO (sem `tac` no macOS). Linha sem o arquivo
  # (squash único de versão anterior) = só o post registrado.
  if [ -s "$sq" ]; then
    list=$(awk 'NF {a[++n]=$1} END {for (i=n; i>=1; i--) print a[i]}' "$sq")
  else
    list="$post"
  fi
  [ "$(printf '%s\n' "$list" | sed -n 1p)" = "$post" ] || {
    err "RECUSADO: $sq diverge do ledger (último da lista != post_merge_sha $post) — nada foi desfeito."
    err "  Confira a lista; para desfazer SÓ o squash registrado, apague o arquivo e repita."
    return 1; }
  for s in $list; do
    gwt merge-base --is-ancestor "$s" HEAD 2>/dev/null && { live="$live $s"; asc="$s $asc"; n=$((n+1)); }
  done
  [ -n "$live" ] || { err "RECUSADO: nenhum squash de $name está na história de $BASE_BRANCH"; return 1; }

  # Rede de segurança: CADA squash desfeito fica em refs/do-archive/$RUN_ID/
  # undo-<nome>-<k> (k = 1, 2, ... na ordem de integração; continua a contagem
  # se a filha já teve undo antes — nunca sobrescreve um arquivo anterior).
  k=$(gwt for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID/" 2>/dev/null \
      | awk -v p="refs/do-archive/$RUN_ID/undo-$name-" 'index($0, p) == 1 && substr($0, length(p) + 1) ~ /^[0-9]+$/ {c++} END {print c+0}')
  local first=$((k+1))
  for s in $asc; do
    k=$((k+1))
    gwt update-ref "refs/do-archive/$RUN_ID/undo-$name-$k" "$s" \
      || { err "FALHA ao arquivar o squash $s de $name — nada foi desfeito"; return 1; }
  done
  local refs="refs/do-archive/$RUN_ID/undo-$name-$first"
  [ "$k" = "$first" ] || refs="$refs..$k"

  # reset --hard só é permitido quando: pre..HEAD é EXATAMENTE a lista de
  # squashes desta filha (nenhum commit de outra filha no intervalo), o pré-merge
  # é ancestral, e o working tree não tem NENHUMA modificação tracked — nem do
  # usuário (o baseline da FASE 0 pode conter " M root.txt" dele), nem da
  # execução. Linhas "??" (untracked) são aceitas: reset --hard não as toca. A
  # comparação contra o baseline é FALSA como guarda: o baseline pode já ter
  # tracked sujo e o reset --hard apagaria essa edição silenciosamente.
  # ATENÇÃO (verificado em lab): NUNCA use `gstatus | grep -qv` com -q aqui —
  # o grep sai no 1º match, fecha o pipe, o gstatus morre com SIGPIPE e, com
  # pipefail, a condição vira falsa -> reset --hard COM modificações tracked.
  # Capturar a saída INTEIRA primeiro (falha real do git aborta aqui) e só
  # então filtrar: grep sem -q consome tudo, SIGPIPE é impossível. O `|| true`
  # no filtro é obrigatório: sem linhas não-"??" o grep -v sai 1 (esperado).
  local st mods
  st=$(gstatus) || { err "FALHA: não consegui ler o status da raiz-de-mundo"; return 1; }
  mods=$(printf '%s\n' "$st" | grep -v '^??' || true)
  if [ -z "$mods" ] && [ -n "$pre" ] && gwt merge-base --is-ancestor "$pre" HEAD 2>/dev/null \
     && [ "$(gwt rev-list "$pre..HEAD" | sort)" = "$(printf '%s\n' $live | sort)" ]; then
    gwt reset --hard "$pre" || return 1
    rm -f "$sq"
    row_set "$name" 9 REVERTED
    echo "OK  reset para $pre ($n squash(es) de $name desfeito(s); arquivado(s) em $refs)"
    return 0
  fi

  # Caminho PADRÃO: revert, do mais novo ao mais antigo. Não toca no working
  # tree do usuário, é seguro com $BASE_BRANCH já pushado e funciona com HEAD
  # avançado — FALHA TARDIA (F3-01): o gate do snapshot de $name só ficou
  # vermelho DEPOIS de merges seguintes; os reverts desfazem EXATAMENTE os
  # squashes desta filha e o squash das outras fica. Falhou no meio => a
  # sequência é abortada: $BASE_BRANCH volta ao ponto de partida (nunca meio revert).
  if [ -n "$mods" ]; then
    err "Há modificações tracked no working tree — reset --hard PROIBIDO."
    err "Usando revert (preserva o working tree e o histórico)."
  else
    err "HEAD avançou desde o squash de $name (há commit de outra filha no intervalo) — revert é o único caminho seguro."
  fi
  # shellcheck disable=SC2086  # $live é uma lista de SHAs: o word-splitting é o que se quer
  gwt revert --no-edit $live || {
    gwt revert --abort >/dev/null 2>&1
    err "FALHA no revert de $name — sequência abortada: $BASE_BRANCH voltou ao ponto de partida. Resolva manualmente (squashes: $live)"
    return 1; }
  rm -f "$sq"
  row_set "$name" 9 REVERTED
  echo "OK  revert de $n squash(es) de $name:$live (arquivado(s) em $refs)"
}

# =============================================================================
is_registered() { # <path> — consta do `worktree list` (mesmo com o diretório ausente)?
  gwt worktree list --porcelain -z 2>/dev/null | tr '\0' '\n' \
    | awk -v p="$1" '$0 == "worktree " p { f = 1 } END { exit !f }'
}

# Diretório SUMIU (rm -rf do sub-agente, teardown aninhado) mas o registro
# TRAVADO ficou: entrada locked é imune a prune/gc e bloqueia o `branch -D` para
# sempre ("checked out at ..."). Remoção DIRECIONADA só daquela entrada, com a
# posse provada pelo lock — nunca `worktree prune` (desregistraria terceiros).
unregister_missing() { # <nome> <path>
  local name="$1" wt="$2" errout common d
  if ! is_registered "$wt"; then echo "OK  $name já não existia"; return 0; fi
  owns_lock "$wt" \
    || { err "RECUSADO: o registro de $wt existe, mas o lock não é desta execução (run=$RUN_ID)"; return 1; }
  gwt worktree unlock "$wt" >/dev/null 2>&1
  if errout=$(gwt worktree remove --force "$wt" 2>&1); then
    echo "OK  $name: o diretório já não existia — registro travado desregistrado"; return 0
  fi
  # O git recusou (verificado em lab que o 2.39 aceita; versões antigas exigem o
  # diretório): remove APENAS o admin dir cujo `gitdir` aponta para o NOSSO path.
  common=$(cd "$BASE_DIR" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || common=""
  if [ -n "$common" ]; then
    for d in "$common"/worktrees/*; do
      [ -f "$d/gitdir" ] || continue
      if [ "$(cat "$d/gitdir" 2>/dev/null)" = "$wt/.git" ]; then
        rm -rf -- "$d" && { echo "OK  $name: o diretório já não existia — registro órfão removido ($d)"; return 0; }
      fi
    done
  fi
  gwt worktree lock --reason "$LOCK_REASON" "$wt" >/dev/null 2>&1
  err "FALHA: não consegui desregistrar $wt (diretório ausente):"
  printf '%s\n' "$errout" | sed 's/^/    /' >&2
  return 1
}

# REMOVED pelos primitivos (remove/sweep) também registra o DESTINO: sem isso o
# ledger apagava o próprio histórico (uma REVERTED removida ficava idêntica a
# uma integrada). Só preenche quando o outcome ainda é "-".
mark_removed() { # <nome>
  local n="$1" st oc k
  st=$(row_get "$n" 9); oc=$(row_get "$n" 11); k=$(row_get "$n" 2)
  if [ "$oc" = "-" ]; then
    case "$k" in
      integration|validation) oc=DISPOSABLE ;;
      *) case "$st" in
           MERGED|gate-pending) [ -n "$(row_get "$n" 8)" ] && oc=MERGED ;;
           REVERTED) oc="NEVER-MERGED:revertida por undo" ;;
         esac ;;
    esac
  fi
  row_set "$n" 9 REMOVED 11 "$oc"
}

cmd_remove() { # <nome> [--artifacts]
  local name="${1:?nome}" opt="${2:-}" wt errout
  wt=$(row_get "$name" 5)
  # Nome inexistente: antes caía no guard_child "" ("RECUSADO: path vazio"), que
  # o LLM lia como "já removida" e seguia com o snapshot vivo.
  [ -n "$wt" ] || { err "RECUSADO: $name não está no owned.tsv desta execução — confira o nome com \`do-wt.sh status\`"; return 1; }
  guard_child "$wt" || return 1
  if [ ! -e "$wt" ]; then
    unregister_missing "$name" "$wt" || return 1
    mark_removed "$name"; return 0
  fi

  if [ "$opt" = "--artifacts" ]; then
    # Daemons seguram file handles e fazem o remove recusar.
    ( cd "$wt" && command -v gradle >/dev/null 2>&1 && gradle --stop >/dev/null 2>&1 ) || true
    # `clean -fdX` apaga SOMENTE o que o .gitignore já declara descartável.
    # Uma lista fixa de nomes apagaria bin/, dist/ e build/ RASTREADOS, que
    # existem em muitos repositórios (bin/rails, bin/setup, dist/ versionado).
    gch "$wt" clean -fdXq 2>/dev/null || true
  fi

  archive_child_head "$name" || return 1   # HEAD fora do branch registrado: o reflog morre com o admin dir
  gwt worktree unlock "$wt" >/dev/null 2>&1
  if errout=$(gwt worktree remove "$wt" 2>&1); then
    mark_removed "$name"; echo "OK  worktree removida: $wt"; return 0
  fi
  # Submódulo: o git recusa por design, e --force resolve. A posse já foi
  # provada por guard_child + owns_lock, então --force não amplia o alvo.
  if printf '%s' "$errout" | grep -qi 'submodule'; then
    if gwt worktree remove --force "$wt" 2>/dev/null; then
      mark_removed "$name"; echo "OK  worktree removida (--force, submódulo): $wt"; return 0
    fi
  fi
  # Recusa por sujeira: re-travar para não perder a etiqueta de posse.
  gwt worktree lock --reason "$LOCK_REASON" "$wt" >/dev/null 2>&1
  err "RECUSADO pelo git ao remover $wt:"
  printf '%s\n' "$errout" | sed 's/^/    /' >&2
  local dirt; dirt=$(gch "$wt" status --porcelain 2>/dev/null)
  if [ -n "$dirt" ]; then
    # --artifacts NÃO resolve sujeira: `clean -fdX` só apaga IGNORADOS, que nunca
    # bloqueiam o `worktree remove`. Quem fecha árvore suja é finish/close, que
    # salvam os restos num commit e ARQUIVAM o branch antes de forçar.
    err "  Conteúdo não commitado:"; printf '%s\n' "$dirt" | sed 's/^/    /' >&2
    err "  Filha integrada?     do-wt.sh finish $name"
    err "  Snapshot/validation? do-wt.sh close $name"
    err "  Não vai integrar?    do-wt.sh close $name --discard \"<motivo>\"   (salva os restos e arquiva o branch)"
  else
    err "  Árvore limpa — daemon de build segurando arquivos?  do-wt.sh remove $name --artifacts"
  fi
  return 1
}

# =============================================================================
cmd_drop_branch() { # <nome>
  local name="${1:?nome}" br st kind
  br=$(row_get "$name" 4); st=$(row_get "$name" 9); kind=$(row_get "$name" 2)
  [ -n "$br" ] || { err "RECUSADO: $name não está no owned.tsv"; return 1; }
  case "$br" in "$BRANCH_NS"/*) : ;; *) err "RECUSADO: $br está fora do namespace desta execução"; return 1 ;; esac
  [ "$br" = "$BASE_BRANCH" ] && { err "RECUSADO: é o branch da raiz-de-mundo"; return 1; }
  case "$st" in
    MERGED|REMOVED) : ;;
    *)
      err "RECUSADO: $name está com status=$st — só apago branch de sub-tarefa integrada."
      err "  (BLOCKED/ORPHANED/ACTIVE preservam o trabalho do sub-agente para inspeção.)"
      # F4-07.8: REVERTED (undo aplicado) tem a filha ainda no disco — o fluxo
      # undo -> remove -> drop-branch fecha o ciclo do revert.
      err "  REVERTED: rode 'do-wt.sh remove $name' primeiro e repita."
      return 1 ;;
  esac
  gwt show-ref --verify --quiet "refs/heads/$br" || { echo "OK  $br já não existe"; return 0; }

  # I-MERGE: o status é livre (`mark <nome> MERGED` manual), então ele sozinho
  # não autoriza apagar. A PROVA de integração é o squash registrado (col 8);
  # sem ele, só um destino já decidido no ledger (outcome != "-") libera.
  case "$kind" in feature|fix|test|prep)
    if [ -z "$(row_get "$name" 8)" ] && [ "$(row_get "$name" 11)" = "-" ]; then
      err "RECUSADO: $name nunca foi integrada (sem squash registrado) — apagar o branch perderia o trabalho."
      err "  Integrar:   do-wt.sh integrate $name \"<msg>\""
      err "  Descartar:  do-wt.sh close $name --discard \"<motivo>\"   (arquiva e registra NEVER-MERGED; vazia = EMPTY)"
      return 1
    fi ;;
  esac

  # Arquivar antes de apagar: custo zero e recuperável mesmo após gc.
  gwt update-ref "refs/do-archive/$RUN_ID/$name" "$(gwt rev-parse "refs/heads/$br")"
  # `-d` sempre recusa após squash-merge (não há ancestralidade). O que autoriza
  # o `-D` é o squash registrado — gravado só depois de um squash-commit bem-sucedido.
  gwt branch -D "$br" >/dev/null || { err "FALHA ao apagar $br"; return 1; }
  echo "OK  branch $br apagado (arquivado em refs/do-archive/$RUN_ID/$name)"
}

# =============================================================================
cmd_sweep() { # fim de onda — fecha o que JÁ FOI INTEGRADO. Nunca destrói trabalho.
  local rc=0 n p
  # Integradas (MERGED com squash registrado): `finish` — salva restos, arquiva,
  # remove, apaga o branch, fecha os snapshots do parent e grava outcome=MERGED.
  # Profundidade decrescente: remover a pai com filha viva deixa registro órfão.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$(awk -F'\t' -v p="$p" 'NR>1 && $5==p {print $3; exit}' "$OWNED")
    cmd_finish "$n" >/dev/null || rc=1
  done < <(awk -F'\t' 'NR>1 && $9=="MERGED" && $8!="" {print $5}' "$OWNED" \
           | awk '{print gsub(/\//,"/"), $0}' | sort -rn | cut -d' ' -f2-)

  # Linhas já REMOVED pelo `remove` manual cujo branch ainda existe.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    gwt show-ref --verify --quiet "refs/heads/$(row_get "$n" 4)" || continue
    cmd_drop_branch "$n" >/dev/null || rc=1
  done < <(awk -F'\t' 'NR>1 && $9=="REMOVED" {print $3}' "$OWNED")

  # Snapshots (kind=integration) cujo parent JÁ FECHOU: descartáveis por
  # construção (nascem do SHA pós-merge e ninguém commita neles) — sem isto cada
  # tarefa integrada deixava uma worktree com deps instaladas até o purge.
  # Parent vivo (gate-pending/REVERTED/...) não é tocado: o gate pode estar rodando.
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    p=$(row_get "$n" 10); [ "$p" = "-" ] && p="${n#int-}"
    case "$(row_get "$p" 9)" in
      REMOVED) close_unintegrated "$n" "" >/dev/null || rc=1 ;;
      "") echo "SWEEP: snapshot $n sem parent no owned.tsv — feche com: \"\$DO_WT\" close $n"; rc=1 ;;
    esac
  done < <(awk -F'\t' 'NR>1 && $2=="integration" && $9!="REMOVED" {print $3}' "$OWNED")

  # O que sobrou. ACTIVE de test/validation é subwave em voo (legítimo por UMA
  # onda — o assert-clean barra a onda N+1 depois disso): só listado. ACTIVE de
  # feature|fix é trabalho NÃO INTEGRADO: a onda não fecha (rc != 0). Idem
  # gate-pending (F3-01), REVERTED e MERGED sem squash (mark manual).
  local left
  left=$(awk -F'\t' 'NR>1 && $9!="REMOVED" {c++} END{print c+0}' "$OWNED")
  if [ "$left" = 0 ]; then
    echo "SWEEP OK — nada desta execução ficou pendente"
  else
    local bad
    bad=$(DO_GATE_STATES="$(gate_states)" awk -F'\t' "$AWK_LIB"'
      NR>1 { load_row() }
      NR>1 && $9!="REMOVED" {
        k=$2; st=$9; why=""
        if (st=="gate-pending") {
          g = gstate($3)
          if (g == "running" || g == "running?") why="gate-pending — gate RODANDO em background"
          else if (g ~ /^red:/)     why="gate-pending — gate VERMELHO (rc=" substr(g, 5) ")"
          else if (g ~ /^covered:/) why="gate-pending — gate próprio VERMELHO, coberto pelo verde de " substr(g, 9)
          else if (g == "green")    why="gate-pending — gate VERDE, fechamento pendente"
          else if (g == "dead")     why="gate-pending — o gate MORREU sem veredito (pid morto)"
          else if (g == "stale")    why="gate-pending — o veredito gravado é de OUTRO squash"
          else                      why="gate-pending (o gate do snapshot ainda não rodou)"
        }
        else if (st=="REVERTED") why="REVERTED (undo aplicado — decida o destino)"
        else if (st=="MERGED") why="MERGED sem squash registrado (mark manual?)"
        else if (st=="ACTIVE" && (k=="feature" || k=="fix")) why="ACTIVE — NÃO INTEGRADA"
        if (why != "") printf "  %-28s kind=%-11s %s\n         conserto: %s\n", $3, k, why, hint($3)
      }' "$OWNED")
    if [ -n "$bad" ]; then
      echo "SWEEP: a onda NÃO fecha — resolva cada linha pelo comando e rode o sweep de novo:"
      printf '%s\n' "$bad"
      rc=1
    fi
    awk -F'\t' '
      NR>1 && $9=="ACTIVE" && ($2=="test" || $2=="validation" || $2=="prep") {
        if (!h++) print "SWEEP: subwave/prep ainda ACTIVE (em voo — só listadas):"
        printf "  %-28s kind=%s\n", $3, $2 }' "$OWNED"
    awk -F'\t' '
      NR>1 && $9=="ACTIVE" && $2=="integration" {
        if (!h++) print "SWEEP: snapshot(s) com parent ainda aberto (fecham junto com ele):"
        printf "  %-28s parent=%s\n", $3, $10 }' "$OWNED"
    awk -F'\t' '
      NR>1 && ($9=="BLOCKED" || $9=="ORPHANED") {
        if (!h++) print "SWEEP: BLOCKED/ORPHANED preservadas para diagnóstico (feche com close --discard \"<motivo>\"; o purge fecha no fim):"
        printf "  %-28s kind=%-11s %s\n", $3, $2, $9 }' "$OWNED"
  fi
  local foreign; foreign=$(wc -l < "$DO_STATE/foreign-worktrees.txt" 2>/dev/null || echo 0)
  foreign=$((foreign + 0))   # wc -l do BSD devolve com espaços à esquerda
  [ "$foreign" -gt 0 ] && echo "  (worktrees pré-existentes de terceiros: $foreign — não tocadas)"
  return $rc
}

# =============================================================================
cmd_verify() { # prova de contenção — rodar ao fim de CADA onda e no COMMIT-FINAL
  local fail=0
  [ "$(gwt symbolic-ref -q --short HEAD 2>/dev/null)" = "$BASE_BRANCH" ] \
    || { echo "VIOLAÇÃO: HEAD da raiz-de-mundo não está em $BASE_BRANCH"; fail=1; }

  # Config local é COMPARTILHADO entre a raiz-de-mundo, as filhas e o principal.
  # Só as chaves que atravessam a fronteira são violação; o resto é ruído.
  # Chaves perigosas (F4-07.9): hooks (execução remota), core.worktree
  # (redireciona o checkout), remote URL (desvia o push), alias (execução
  # arbitrária), include/includeIf + excludesFile/attributesFile (podem
  # ESCONDER vazamento do status), filter (rewrite de conteúdo) e sshCommand
  # (execução arbitrária no lugar do ssh).
  local cfgdiff
  cfgdiff=$(gwt config --list --local 2>/dev/null | diff "$DO_STATE/config-baseline.txt" - | grep '^[<>]' || true)
  if [ -n "$cfgdiff" ]; then
    if printf '%s' "$cfgdiff" | grep -qE 'core\.hookspath|core\.worktree|core\.excludesfile|core\.attributesfile|core\.sshcommand|remote\..*\.url|alias\.|include\.path|includeif\..*\.path|filter\.'; then
      echo "VIOLAÇÃO: config compartilhado do repositório mudou em chave que atravessa a fronteira:"
      printf '%s\n' "$cfgdiff" | sed 's/^/  /'; fail=1
    else
      echo "ALERTA: config local mudou (não atravessa a fronteira — registre no relatório):"
      printf '%s\n' "$cfgdiff" | sed 's/^/  /'
    fi
  fi

  if [ -n "${MAIN_ROOT:-}" ] && [ -s "$DO_STATE/main-head.txt" ]; then
    # O usuário pode estar trabalhando no principal em paralelo — mudança lá NÃO
    # é, por si só, prova de que fomos nós. O que condena é AUTORIA: algum ref
    # desta execução alcançável a partir do HEAD do principal.
    local mh; mh=$(git -C "$MAIN_ROOT" rev-parse HEAD)
    if [ "$mh" != "$(cat "$DO_STATE/main-head.txt")" ]; then
      local ours=0
      while IFS= read -r r; do
        [ -n "$r" ] || continue
        git -C "$MAIN_ROOT" merge-base --is-ancestor "$r" "$mh" 2>/dev/null && ours=1
      done < <(gwt for-each-ref --format='%(objectname)' "refs/heads/$BRANCH_NS" "refs/do-archive/$RUN_ID" 2>/dev/null)
      if [ "$ours" = 1 ]; then
        echo "VIOLAÇÃO: o HEAD do checkout principal contém commits DESTA execução"; fail=1
      else
        echo "ALERTA: o HEAD do checkout principal mudou, mas não por commits desta execução"
        echo "        (provavelmente você ou outra sessão trabalhando lá). Registre no relatório."
      fi
    fi
    local ms; ms=$(git -C "$MAIN_ROOT" status --porcelain --ignored=traditional 2>/dev/null)
    if [ "$ms" != "$(cat "$DO_STATE/main-status.txt" 2>/dev/null)" ]; then
      echo "ALERTA: a working tree do projeto principal mudou desde a FASE 0:"
      diff "$DO_STATE/main-status.txt" <(printf '%s\n' "$ms") | grep '^[<>]' | sed 's/^/  /'
      echo "        Confira se alguma entrada é sua (node_modules/, build/) — se for, é VIOLAÇÃO."
    fi
  fi

  while IFS= read -r p; do
    [ -n "$p" ] && [ -e "$p" ] || continue
    case "$p/" in "$CHILD_ROOT"/*) : ;; *) echo "VIOLAÇÃO: worktree registrada fora de CHILD_ROOT: $p"; fail=1 ;; esac
  done < <(awk -F'\t' 'NR>1 {print $5}' "$OWNED")

  [ "$fail" = 0 ] && echo "CONTENÇÃO OK" || echo "CONTENÇÃO QUEBRADA — registre no TASK_PLAN e no relatório final"
  return $fail
}

# =============================================================================
cmd_stage_delta() { # COMMIT-FINAL: estagia SÓ o que esta execução produziu
  gassert || return 1
  local basepaths="$DO_STATE/baseline-paths.txt"
  status_paths < "$DO_STATE/dirty-baseline.nul" | tr '\0' '\n' | sort -u > "$basepaths"

  # -uall nos DOIS lados (baseline da FASE 0 e leitura aqui) é OBRIGATÓRIO:
  # sem ele, um diretório untracked colapsa numa única linha "?? docs/" e a
  # comparação EXATA excluiria o diretório INTEIRO — inclusive arquivos novos
  # que a execução criou dentro dele. O diff de paths tem que ser por arquivo,
  # não por diretório.
  local -a add=()
  while IFS= read -r -d '' path; do
    # Comparação EXATA de path. Substring classificaria "relatorio.md" como
    # preexistente só porque o usuário tinha um "relatorio.md.bak" sujo.
    grep -qxF -- "$path" "$basepaths" && continue
    case "$path" in .deep-orchestrator/*|.deep-orchestrator) continue ;; esac
    add+=("$path")
  done < <(gstatus -z --untracked-files=all | status_paths)

  if [ "${#add[@]}" = 0 ]; then echo "Nada novo a estagiar."; return 0; fi
  gwt add -- "${add[@]}" || return 1
  printf 'Estagiados %s path(s):\n' "${#add[@]}"; printf '  %s\n' "${add[@]}"
  local kept; kept=$(wc -l < "$basepaths")
  [ "$kept" -gt 0 ] && printf 'Preservados fora do commit (sujeira preexistente do usuário): %s\n' "$kept"
  return 0
}

# =============================================================================
cmd_clean_ignored_delta() { # COMMIT-FINAL: limpa SÓ os ignorados que esta
  # execução criou (dependências do gate). Nunca os ignorados pré-existentes:
  # o baseline de ignorados da FASE 0 protege node_modules/.venv/.env.local
  # que o usuário já tinha antes — `git clean -fdX` às cegas apagaria tudo.
  [ -f "$DO_STATE/ignored-baseline.nul" ] \
    || { err "RECUSADO: sem ignored-baseline.nul — clean-ignored-delta exige a FASE 0 (baseline de ignorados)"; return 1; }
  gassert || return 1
  local basepaths="$DO_STATE/ignored-baseline-paths.txt"
  status_paths < "$DO_STATE/ignored-baseline.nul" | tr '\0' '\n' | sort -u > "$basepaths"

  # Mesmo modo da gravação do baseline (--ignored, colapso de diretório
  # padrão): um diretório inteiramente ignorado vira UMA linha "!! dir/". Assim
  # um node_modules/ pré-existente é um único path no baseline e nunca vira
  # delta, mesmo que o gate tenha instalado mais coisas dentro dele.
  local -a delta=()
  while IFS= read -r -d '' path; do
    # Comparação EXATA de path (mesmo padrão do stage-delta): substring
    # classificaria um ignorado novo como preexistente.
    grep -qxF -- "$path" "$basepaths" && continue
    case "$path" in .deep-orchestrator/*|.deep-orchestrator) continue ;; esac
    delta+=("$path")
  done < <(gstatus --ignored -z | status_paths)

  if [ "${#delta[@]}" = 0 ]; then echo "Nada novo a limpar (todos os ignorados já existiam na FASE 0)."; return 0; fi
  local path
  for path in "${delta[@]}"; do
    # clean -fdX por pathspec EXPLÍCITO: -X só toca ignorados, e o path veio
    # do próprio --ignored -z (cru, sem quoting). GIT_LITERAL_PATHSPECS impede
    # que um path com metacaractere glob (ex.: "a[1].tmp") vire padrão e
    # remova OUTRO arquivo (verificado em lab: o glob removia "a1.tmp" junto).
    if GIT_LITERAL_PATHSPECS=1 gwt clean -fdXq -- "$path"; then
      echo "Removido ignorado novo: $path"
    else
      err "AVISO: não consegui remover ignorado novo: $path"
    fi
  done
  return 0
}

# =============================================================================
cmd_wave_files() { # <nome-da-primeira-filha-da-onda> — escopo da testing subwave
  local first="${1:?nome da primeira filha da onda}" pre
  pre=$(row_get "$first" 7)
  # Robustez (F2-09): se a filha passada NÃO foi mergeada (BLOCKED/ORPHANED, ou
  # ainda ACTIVE), ela não tem pre_merge_sha e o escopo da testing/validation
  # subwave seria incomputável justamente nos cenários já degradados. O owned.tsv
  # não tem coluna de onda, mas os nomes batizados na FASE 2/PLAN seguem a
  # convenção ondaN-* (ex.: onda1-cache, test-onda1-cache, val-onda1-gate): o
  # prefixo identifica a onda. Resolve então automaticamente para a filha MERGED
  # do MESMO prefixo com o MENOR pre_merge_sha — a mais antiga integrada, o
  # início da onda. Filha já mergeada (com pre_merge_sha) continua indo direto.
  # O filtro do prefixo usa substring ($3 ~ p) e NÃO ancora no início: o hífen
  # desambigua (onda10-x não contém "onda1-") e assim test-ondaN-*/val-ondaN-*
  # também casam (verificado em lab: ^-ancorado deixava escopo incomputável
  # quando a única filha MERGED da onda era de subwave).
  if [ -z "$pre" ]; then
    local prefix
    prefix=$(printf '%s\n' "$first" | sed -n 's/.*\(onda[0-9][0-9]*-\).*/\1/p')
    if [ -n "$prefix" ]; then
      # INTEGRADA = squash registrado (col 7/8) e não revertido: com o fechamento
      # por tarefa a filha passa por gate-pending e vira REMOVED no gate verde —
      # filtrar só status=MERGED deixaria o escopo incomputável.
      pre=$(awk -F'\t' -v p="$prefix" \
            'NR>1 && $9!="REVERTED" && $3 ~ p && $7!="" && $8!="" {print $7}' "$OWNED" \
            | sort | head -n 1)
    fi
    [ -n "$pre" ] || {
      err "RECUSADO: $first não tem pre_merge_sha (ainda não foi mergeada?) e não há filha"
      err "  MERGED do mesmo prefixo de onda (${prefix:-nenhum — nome fora do padrão ondaN-*}) no owned.tsv."
      err "  O escopo da testing/validation subwave exige ao menos uma filha integrada desta onda."
      return 1
    }
    err "AVISO: $first não foi mergeada — escopo resolvido pela filha MERGED de menor pre_merge_sha do prefixo $prefix"
  fi
  # Determinístico e imune ao COMMIT PREP — ao contrário de HEAD~N, que conta
  # commits às cegas e engole o prep da própria onda.
  gwt diff --name-only "$pre..HEAD"
}

cmd_status() {
  printf '%-28s %-11s %-12s %s\n' NOME KIND STATUS BRANCH
  awk -F'\t' 'NR>1 {printf "%-28s %-11s %-12s %s\n", $3, $2, $9, $4}' "$OWNED"
}

cmd_mark() { # <nome> <STATUS> — validação (F4-07.7): nome existe e status ∈
  # máquina de estados, case exato (um typo não pode corromper a máquina).
  local name="${1:?nome}" st="${2:?status}"
  case "$st" in
    ACTIVE|MERGED|REMOVED|REVERTED|BLOCKED|ORPHANED|gate-pending) : ;;
    *) err "RECUSADO: status inválido: '$st' — use ACTIVE|MERGED|REMOVED|REVERTED|BLOCKED|ORPHANED|gate-pending (case exato)"
       return 1 ;;
  esac
  [ -n "$(row_get "$name" 9)" ] || { err "RECUSADO: $name não está no owned.tsv"; return 1; }
  row_set "$name" 9 "$st" || return 1
  echo "OK  $name -> $st"
}

# =============================================================================
# FECHAMENTO POR TAREFA (v4.1.0) — integrate / gate / finish / close
# A limpeza deixou de ser um ritual de 5 comandos + flips de status que o LLM
# precisava lembrar a cada notificação de gate: o `gate` chama o `finish`
# sozinho no instante do verde, e quem não vai ser integrado sai por `close`,
# com o destino gravado no ledger (outcome) — nunca em silêncio.

# Núcleo comum: salva restos -> ARQUIVA o branch -> remove a worktree (--force,
# só DEPOIS do arquivamento: nada se perde) -> apaga o branch. Re-executável
# após falha parcial (cada etapa confere a existência antes de agir).
close_core() { # <nome> <rescue 0|1>
  local name="$1" rescue="$2" br wt errout
  br=$(row_get "$name" 4); wt=$(row_get "$name" 5)
  case "$br" in "$BRANCH_NS"/*) : ;; *) err "RECUSADO: $br está fora do namespace desta execução"; return 1 ;; esac
  [ "$br" = "$BASE_BRANCH" ] && { err "RECUSADO: é o branch da raiz-de-mundo"; return 1; }
  guard_child "$wt" || return 1

  # Rescue-commit: o --force abaixo NUNCA passa por cima de trabalho não salvo.
  if [ "$rescue" = 1 ]; then rescue_commit "$name" || return 1; fi

  if gwt show-ref --verify --quiet "refs/heads/$br"; then
    gwt update-ref "refs/do-archive/$RUN_ID/$name" "$(gwt rev-parse "refs/heads/$br")" \
      || { err "FALHA ao arquivar $br em refs/do-archive/$RUN_ID/$name — nada foi removido"; return 1; }
  fi
  # O rescue-commit vai para o HEAD DA WORKTREE: com HEAD destacado / `switch -c`
  # o branch registrado não o contém — arquiva TAMBÉM o HEAD (<nome>-HEAD), DEPOIS
  # do rescue (para o wip entrar) e ANTES de remover.
  archive_child_head "$name" || return 1

  if [ -e "$wt" ]; then
    gwt worktree unlock "$wt" >/dev/null 2>&1
    # UM --force só (o lock já saiu; `-f -f` continua proibido): a posse foi
    # provada por guard_child + owns_lock, então --force não amplia o alvo.
    if ! errout=$(gwt worktree remove --force "$wt" 2>&1); then
      gwt worktree lock --reason "$LOCK_REASON" "$wt" >/dev/null 2>&1
      err "FALHA ao remover $wt (branch já arquivado em refs/do-archive/$RUN_ID/$name):"
      printf '%s\n' "$errout" | sed 's/^/    /' >&2
      err "  Processo/daemon segurando arquivos? Pare-o (do-wt.sh remove $name --artifacts roda gradle --stop) e repita."
      return 1
    fi
  else
    unregister_missing "$name" "$wt" >/dev/null || return 1
  fi

  if gwt show-ref --verify --quiet "refs/heads/$br"; then
    gwt branch -D "$br" >/dev/null || { err "FALHA ao apagar $br"; return 1; }
  fi
  return 0
}

child_snapshots() { # <nome> -> nomes dos snapshots do parent (linha legada: int-<nome>)
  awk -F'\t' -v n="$1" 'NR>1 && $2=="integration" && ($10==n || (($10=="" || $10=="-") && $3=="int-" n)) {print $3}' "$OWNED"
}

# Núcleo do close (também usado por sweep e purge): classifica e fecha quem NÃO
# será integrado. <motivo> vazio = sem --discard.
close_unintegrated() { # <nome> <motivo|"">
  local name="$1" reason="$2" kind st post oc br wt base ahead=0 dirty=0 outcome
  kind=$(row_get "$name" 2); st=$(row_get "$name" 9); post=$(row_get "$name" 8); oc=$(row_get "$name" 11)
  br=$(row_get "$name" 4); wt=$(row_get "$name" 5); base=$(row_get "$name" 6)
  [ -n "$st" ] || { err "RECUSADO: $name não está no owned.tsv desta execução — confira o nome com \`do-wt.sh status\`"; return 1; }

  if [ "$st" = REMOVED ] && ! [ -e "$wt" ] && ! gwt show-ref --verify --quiet "refs/heads/$br"; then
    echo "OK  $name já fechado (outcome=$oc)"; return 0          # idempotente
  fi

  case "$kind" in
    integration|validation)
      # Descartáveis por construção: snapshot nasce do SHA pós-merge e ninguém
      # commita nele; a validation é somente-leitura e NUNCA é mergeada.
      close_core "$name" 0 || return 1
      outcome=DISPOSABLE ;;
    *)
      case "$st" in MERGED|gate-pending)
        # A PROVA de integração é o squash registrado; MERGED por `mark` manual
        # (col 8 vazia) NÃO é integração e segue a classificação abaixo.
        if [ -n "$post" ]; then
          err "RECUSADO: $name está $st (INTEGRADA) — use finish:  do-wt.sh finish $name"
          return 1
        fi ;;
      esac
      if [ "$st" = REMOVED ] && [ "$oc" != "-" ]; then
        outcome="$oc"                     # destino já decidido: só termina a limpeza
      else
        # Conta o branch registrado E o HEAD da worktree (HEAD destacado / `switch
        # -c`): commits em base..HEAD-da-worktree NUNCA viram EMPTY.
        local tips="" wh2=""
        gwt show-ref --verify --quiet "refs/heads/$br" && tips="refs/heads/$br"
        if is_child_wt "$wt"; then
          wh2=$(gch "$wt" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || true)
          [ -n "$wh2" ] && tips="$tips $wh2"
        fi
        # shellcheck disable=SC2086  # $tips é lista de revs (branch não tem espaço)
        [ -n "$tips" ] && ahead=$(gwt rev-list --count $tips --not "$base" 2>/dev/null || echo 0)
        if [ -d "$wt" ] && [ -n "$(gch "$wt" status --porcelain -- ':(exclude,top).deep-orchestrator' 2>/dev/null)" ]; then
          dirty=1
        fi
        if [ "$ahead" -gt 0 ] || [ "$dirty" = 1 ]; then
          if [ -z "$reason" ]; then
            err "RECUSADO: $name tem trabalho NÃO INTEGRADO ($ahead commit(s) à frente de base_sha; árvore suja: $([ "$dirty" = 1 ] && echo sim || echo não))."
            err "  Integrar:   do-wt.sh integrate $name \"<msg>\""
            err "  Descartar:  do-wt.sh close $name --discard \"<motivo>\"   (salva os restos, ARQUIVA o branch em"
            err "              refs/do-archive/$RUN_ID/$name e registra NEVER-MERGED:<motivo> — vai ao relatório final)"
            return 1
          fi
          outcome="NEVER-MERGED:$reason"
        else
          outcome=EMPTY
        fi
      fi
      close_core "$name" 1 || return 1 ;;
  esac
  row_set "$name" 9 REMOVED 11 "$outcome" || return 1
  local hd=""
  gwt show-ref --verify --quiet "refs/do-archive/$RUN_ID/$name-HEAD" && hd=" (+ HEAD da filha em refs/do-archive/$RUN_ID/$name-HEAD)"
  case "$outcome" in
    NEVER-MERGED:*) echo "OK  $name fechado SEM integrar (outcome=$outcome) — arquivado em refs/do-archive/$RUN_ID/$name$hd" ;;
    *)              echo "OK  $name fechado (outcome=$outcome)$hd" ;;
  esac
}

cmd_close() { # <nome> [--discard "<motivo>"]
  local name="${1:?nome}" reason=""
  case "${2:-}" in
    "") : ;;
    --discard)
      # O motivo vira campo do TSV (e argumento -v do awk): sem TAB/newline/barra invertida.
      reason=$(printf '%s' "${3:-}" | tr '\t\n\\' '  /' | sed 's/^ *//; s/ *$//')
      [ -n "$reason" ] || { err "uso: do-wt.sh close <nome> --discard \"<motivo>\" — o motivo é obrigatório (vai ao relatório final)"; return 2; } ;;
    *) err "uso: do-wt.sh close <nome> [--discard \"<motivo>\"]"; return 2 ;;
  esac
  close_unintegrated "$name" "$reason"
}

# CAUDA NÃO INTEGRADA: o tip da filha (ou o HEAD da worktree, se saiu do branch)
# tem CONTEÚDO novo depois do último squash? Compara ÁRVORES, não só SHA: o merge
# do $BASE_BRANCH dentro da filha (sem fix) move o tip sem trazer nada novo.
# Imprime o nº de commits pós-squash (0 = sem cauda). Sem gates/<nome>.tip
# (execução anterior a este registro) não há como saber: 0.
unintegrated_tail() { # <nome>
  local name="$1" br wt tip_int c cands="" n=0 m mt mrc ht
  br=$(row_get "$name" 4); wt=$(row_get "$name" 5)
  tip_int=$(cat "$DO_STATE/gates/$name.tip" 2>/dev/null || true)
  [ -n "$tip_int" ] || { echo 0; return 0; }
  gwt show-ref --verify --quiet "refs/heads/$br" && cands=$(gwt rev-parse "refs/heads/$br")
  if is_child_wt "$wt"; then
    c=$(gch "$wt" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || true)
    [ -n "$c" ] && cands="$cands $c"
  fi
  ht=$(gwt rev-parse 'HEAD^{tree}')
  for c in $cands; do
    [ "$c" != "$tip_int" ] || continue
    if [ "${DO_WT_MERGE_TREE:-1}" = 1 ]; then
      mt=$(gwt merge-tree --write-tree --no-messages HEAD "$c" 2>/dev/null); mrc=$?
    else
      mrc=129
    fi
    case "$mrc" in
      0) [ "$(printf '%s\n' "$mt" | sed -n 1p)" = "$ht" ] && continue ;;   # merge == $BASE_BRANCH: nada novo
      1) : ;;                                                              # conflita = há conteúdo novo
      *) [ "$(gwt rev-parse "$c^{tree}" 2>/dev/null)" = "$(gwt rev-parse "$tip_int^{tree}" 2>/dev/null)" ] && continue ;;  # git < 2.38
    esac
    m=$(gwt rev-list --count "$tip_int..$c" 2>/dev/null || echo 0)
    [ "$m" -gt 0 ] 2>/dev/null || m=1
    [ "$m" -gt "$n" ] && n=$m
  done
  echo "$n"
}

cmd_finish() { # <nome> [--gate-ok] — fecha uma filha INTEGRADA
  local name="${1:?nome}" gate_ok=0 st post oc g red="" snap
  [ "${2:-}" = "--gate-ok" ] && gate_ok=1
  st=$(row_get "$name" 9); post=$(row_get "$name" 8); oc=$(row_get "$name" 11)
  [ -n "$st" ] || { err "RECUSADO: $name não está no owned.tsv desta execução — confira o nome com \`do-wt.sh status\`"; return 1; }
  case "$st" in
    REMOVED)
      # Idempotente. Só refaz a limpeza se a linha É de integrada (outcome
      # MERGED, ou "-" com squash registrado: removida pelos primitivos). Com
      # outro destino já gravado (EMPTY/DISPOSABLE/NEVER-MERGED/MERGED-PARTIAL) não
      # há o que fazer; "-" SEM squash (remove manual de quem nunca integrou) cai
      # na recusa abaixo.
      if [ "$oc" != MERGED ] && [ "$oc" != "-" ]; then
        echo "OK  $name já fechado (outcome=$oc)"; return 0
      fi ;;
    MERGED|gate-pending)
      # O veredito vem do .rc AMARRADO ao squash atual (gate_state): rc 0 de um
      # squash anterior não fecha o squash novo. MERGED (primitivo `merge`, sem
      # gate do script) segue fechando sem veredito — mas um VERMELHO gravado barra.
      g=$(gate_state "$name")
      case "$g" in
        green) : ;;
        running)
          err "AGUARDE: o gate de $name está RODANDO (pid vivo) — nada foi limpo; fechar agora tiraria o snapshot de baixo dele."
          err "  Acompanhe: tail -f \"$DO_STATE/gates/$name.log\"   (o verde fecha a filha sozinho)"
          return 3 ;;
        red:*|covered:*)
          if [ "$gate_ok" = 1 ]; then
            case "$g" in red:*) red="${g#red:}" ;; esac    # covered: um verde posterior contém este squash — atestado pelo SCRIPT
          else
            err "RECUSADO: gate VERMELHO de $name (rc=${g#*:}) — NADA foi limpo. Log: $DO_STATE/gates/$name.log"
            case "$g" in covered:*)
              err "  Mas o gate VERDE de '${g#covered:}' rodou num SHA que JÁ CONTÉM este squash (vítima de outro squash): do-wt.sh finish $name --gate-ok"
              return 4 ;; esac
            err "  Conserte NA MESMA worktree (ANTES do fix: git -C \"$(row_get "$name" 5)\" merge \"$BASE_BRANCH\" — senão deleção/reversão do fix se perde),"
            err "  re-integre (do-wt.sh integrate $name \"<msg>\") e rode o gate de novo;"
            err "  ou desista: do-wt.sh undo $name (desfaz TODOS os squashes da filha) && do-wt.sh close $name --discard \"<motivo>\""
            return 4
          fi ;;
        *) # none | running? | dead | stale
          if [ "$st" = gate-pending ] && [ "$gate_ok" = 0 ]; then
            case "$g" in
              "running?") err "AGUARDE: o gate de $name ainda não reportou (running) — nada foi limpo." ;;
              dead)       err "AGUARDE: o gate de $name MORREU sem veredito (pid morto — timeout do harness?) — nada foi limpo." ;;
              stale)      err "AGUARDE: o veredito gravado é de OUTRO squash de $name (houve re-integração) — nada foi limpo." ;;
              *)          err "AGUARDE: o gate de $name ainda não reportou (nunca rodou) — nada foi limpo." ;;
            esac
            err "  Rode:  do-wt.sh gate $name      (ou, se VOCÊ rodou o gate por fora e atesta o verde:  do-wt.sh finish $name --gate-ok)"
            return 3
          fi ;;
      esac ;;
    *)
      err "RECUSADO: $name está $st — finish fecha só filha INTEGRADA (MERGED|gate-pending)."
      err "  Integrar:  do-wt.sh integrate $name \"<msg>\"      Não vai integrar:  do-wt.sh close $name [--discard \"<motivo>\"]"
      return 1 ;;
  esac
  [ -n "$post" ] || {
    err "RECUSADO: $name não tem squash registrado (post_merge_sha vazio — MERGED por \`mark\` manual?)."
    err "  Integrar:  do-wt.sh integrate $name \"<msg>\"      Não vai integrar:  do-wt.sh close $name [--discard \"<motivo>\"]"
    return 1; }

  # I-MERGE: fechar como "MERGED" uma filha com fix NUNCA integrado (só no
  # arquivo) ou com gate VERMELHO era mentira por omissão. O squash ESTÁ em
  # $BASE_BRANCH, então o destino é MERGED-PARTIAL:<motivo> — vai ao bloco
  # obrigatório do purge (rc 3) e a `parciais=` do ledger. O motivo é gravado
  # ANTES de destruir: um finish re-executado após falha parcial (branch já
  # apagado) não consegue mais recalcular a cauda.
  local why="" tail_n pf="$DO_STATE/partial/$name"
  rescue_commit "$name" || return 1                 # antes de medir: os restos contam como cauda
  tail_n=$(unintegrated_tail "$name")
  [ "${tail_n:-0}" -gt 0 ] 2>/dev/null && why="cauda nao integrada (+$tail_n)"
  [ -n "$red" ] && why="${why:+$why + }gate vermelho (rc=$red)"
  if [ -n "$why" ]; then
    mkdir -p "$DO_STATE/partial" && printf '%s\n' "$why" > "$pf" || return 1
  elif [ -s "$pf" ]; then
    why=$(sed -n 1p "$pf")
  fi
  if [ -n "$why" ]; then
    err "AVISO: $name fecha como MERGED-PARTIAL — o squash ($(printf '%s' "$post" | cut -c1-7)) está em $BASE_BRANCH, mas: $why."
    err "  O que NÃO foi integrado fica SÓ em refs/do-archive/$RUN_ID/$name (ref local, não vai no push) — relate em \"Não integrado\"."
  fi

  close_core "$name" 1 || return 1
  # Snapshots do parent: descartáveis (force). Falhou algum => a filha NÃO vira
  # REMOVED ainda (re-executar o finish termina o serviço).
  local rc=0
  while IFS= read -r snap; do
    [ -n "$snap" ] || continue
    [ "$(row_get "$snap" 9)" = REMOVED ] && ! [ -e "$(row_get "$snap" 5)" ] && continue
    close_unintegrated "$snap" "" >/dev/null || rc=1
  done < <(child_snapshots "$name")
  [ "$rc" = 0 ] || { err "FALHA: snapshot(s) de $name não fecharam (acima) — repita: do-wt.sh finish $name${2:+ $2}"; return 1; }
  local outcome=MERGED
  [ -n "$why" ] && outcome="MERGED-PARTIAL:$why"
  row_set "$name" 9 REMOVED 11 "$outcome" || return 1
  echo "OK  $name fechado (outcome=$outcome) — branch arquivado em refs/do-archive/$RUN_ID/$name"
}

live_snapshot() { # <nome> -> "nome<TAB>path" do ÚLTIMO snapshot vivo do parent
  awk -F'\t' -v n="$1" 'NR>1 && $2=="integration" && $9!="REMOVED" && ($10==n || (($10=="" || $10=="-") && $3=="int-" n)) {r=$3 "\t" $5}
       END { if (r != "") print r }' "$OWNED"
}

new_snapshot() { # <nome> <sha> -> cria int-<nome> (-r2, -r3... se o nome já existir) e imprime o path
  local name="$1" sha="$2" s="int-$1" k=2
  while [ -n "$(row_get "$s" 3)" ]; do s="int-$name-r$k"; k=$((k+1)); done
  cmd_new integration "$s" "$sha" "$name" >/dev/null || return 1
  row_get "$s" 5
}

cmd_integrate() { # <nome> "<msg>" = merge + snapshot no SHA pós-merge + gate-pending
  local name="${1:?nome}" msg="${2:?mensagem}" rc post snap
  cmd_merge "$name" "$msg"; rc=$?
  [ "$rc" = 0 ] || return "$rc"          # merge falhou -> nada de snapshot, rc do merge
  post=$(row_get "$name" 8)
  # gate-pending ANTES do snapshot: fecha a janela em que um sweep apagaria a
  # filha (o backup para o fix) antes do verde. Um veredito de gate anterior
  # (re-integração após vermelho) não vale para este squash.
  rm -f "$DO_STATE/gates/$name.rc" 2>/dev/null
  row_set "$name" 9 gate-pending || return 1
  snap=$(new_snapshot "$name" "$post") || {
    err "FALHA: o squash de $name entrou, mas o snapshot não nasceu (acima). A filha está gate-pending;"
    err "  \`do-wt.sh gate $name\` recria o snapshot a partir do SHA pós-merge."
    return 1; }
  echo "SNAPSHOT=$snap"
}

cmd_gate_set() { # <build|test|lint|e2e|install> "<comando>"   ("" = sem <etapa>)
  [ "$#" -ge 2 ] || { err "uso: do-wt.sh gate-set <build|test|lint|e2e|install> \"<comando>\"   (\"\" = sem a etapa)"; return 2; }
  local stage="$1" cmd="$2"
  case "$stage" in build|test|lint|e2e|install) : ;;
    *) err "RECUSADO: etapa inválida: '$stage' — use build|test|lint|e2e|install"; return 2 ;; esac
  mkdir -p "$DO_STATE/gate" || return 1
  if [ -z "$cmd" ]; then
    rm -f "$DO_STATE/gate/$stage.cmd"; echo "OK  gate-set $stage: sem $stage"; return 0
  fi
  # Comando CRU, uma string só: roda depois com bash -c "$(cat arquivo)" — sem
  # env sourceado, sem problema de quoting.
  printf '%s\n' "$cmd" > "$DO_STATE/gate/$stage.cmd" || return 1
  echo "OK  gate-set $stage: $cmd"
}

cmd_gate() { # <nome> [--e2e] — feito para rodar em background; limpa no verde SEM o LLM
  local name="${1:?nome}" e2e=0 st post row snap stages="" s f rc log rcf
  [ "${2:-}" = "--e2e" ] && e2e=1
  # FT-03 (only-e2e): o e2e é da subwave de teste — kind=test com DO_TEST_MODE=e2e
  # e etapa e2e registrada roda o e2e SOZINHO (o --e2e segue aceito). Sem isto, um
  # `gate test-*` esquecido da flag dava VERDE sem rodar o spec e2e e fechava a
  # filha — o vermelho só apareceria depois, sem worktree para consertar.
  if [ "$e2e" = 0 ] && [ "${DO_TEST_MODE:-full}" = e2e ] \
     && [ "$(row_get "$name" 2)" = test ] && [ -s "$DO_STATE/gate/e2e.cmd" ]; then
    e2e=1
  fi
  st=$(row_get "$name" 9); post=$(row_get "$name" 8)
  [ -n "$st" ] || { err "RECUSADO: $name não está no owned.tsv desta execução — confira o nome com \`do-wt.sh status\`"; return 5; }
  if [ "$st" = REMOVED ] && [ "$(row_get "$name" 11)" = MERGED ]; then
    echo "GATE: $name já está fechado (outcome=MERGED) — nada a fazer"; return 0
  fi
  case "$st" in gate-pending|MERGED) : ;; *)
    err "RECUSADO: $name está $st — o gate roda no snapshot de uma filha INTEGRADA. Rode antes: do-wt.sh integrate $name \"<msg>\""
    return 5 ;; esac
  [ -n "$post" ] || { err "RECUSADO: $name não tem squash registrado — rode: do-wt.sh integrate $name \"<msg>\""; return 5; }

  for s in install build test lint; do
    [ -s "$DO_STATE/gate/$s.cmd" ] && stages="$stages $s"
  done
  if [ "$e2e" = 1 ]; then
    [ -s "$DO_STATE/gate/e2e.cmd" ] \
      || { err "RECUSADO: --e2e pedido, mas não há etapa e2e — registre: do-wt.sh gate-set e2e \"<comando>\""; return 5; }
    stages="$stages e2e"
  fi
  [ -n "$stages" ] || {
    err "RECUSADO: nenhuma etapa de gate configurada — registre na FASE 1:"
    err "  do-wt.sh gate-set build \"<cmd>\" ; do-wt.sh gate-set test \"<cmd>\" ; do-wt.sh gate-set lint \"<cmd>\"   (install/e2e opcionais)"
    return 5; }

  row=$(live_snapshot "$name"); snap="${row#*$'\t'}"
  if [ -z "$row" ] || [ ! -d "$snap" ]; then
    snap=$(new_snapshot "$name" "$post") || { err "FALHA: não consegui (re)criar o snapshot de $name"; return 1; }
  fi
  # WT-F6: a transição para gate-pending fica FORA do if. Num gate sobre filha
  # MERGED com snapshot LEGADO (fluxo v4.0: `merge` + `new integration`), ela
  # dentro do if era pulada — o vermelho era IGNORADO e o sweep fechava a filha
  # como MERGED (I-MERGE violada).
  [ "$st" = gate-pending ] || row_set "$name" 9 gate-pending || return 1

  mkdir -p "$DO_STATE/gates" || return 1
  log="$DO_STATE/gates/$name.log"; rcf="$DO_STATE/gates/$name.rc"
  # WT-F5 — reentrância: 2º gate com o 1º vivo sai rc 3 SEM tocar log/rc (o 2º
  # truncaria o log e colidiria com o install/build/porta do 1º — VERMELHO falso
  # por ambiente). Formato antigo ("running" sem pid, rc cru) é sobrescrito.
  local r0="" r1="" r2=""
  if [ -s "$rcf" ]; then
    # 3 variáveis: com 2, o pid viraria "pid sha" (read dá o RESTO da linha ao
    # último nome) e o kill -0 nunca validaria — a guarda nunca disparava.
    read -r r0 r1 r2 < "$rcf" || true
    if [ "$r0" = running ] && [ -n "$r1" ] && kill -0 "$r1" 2>/dev/null; then
      err "AGUARDE: o gate de $name já está rodando (pid $r1) — nada a fazer (log e .rc NÃO foram tocados)."
      err "  Acompanhe: tail -f \"$log\""
      return 3
    fi
  fi
  # O veredito fica AMARRADO ao squash: .rc = "running <pid> <post_sha>" no
  # início e "<rc> <post_sha>" no fim — um 0 gravado por um gate ANTIGO não
  # fecha o squash ATUAL (gate_state dá stale, e o finish recusa).
  printf 'running %s %s\n' "$$" "$post" > "$rcf"; : > "$log"
  for s in $stages; do
    f="$DO_STATE/gate/$s.cmd"
    printf '=== [%s] %s\n' "$s" "$(cat "$f")" >> "$log"
    ( cd "$snap" && HUSKY=0 CI=1 bash -c "$(cat "$f")" ) >> "$log" 2>&1 < /dev/null
    rc=$?
    printf '=== [%s] rc=%s\n' "$s" "$rc" >> "$log"
    if [ "$rc" != 0 ]; then
      printf '%s %s\n' "$rc" "$post" > "$rcf"
      echo "GATE VERMELHO — $name: a etapa '$s' falhou (rc=$rc). NADA foi limpo (filha e snapshot preservados)."
      echo "  snapshot: $snap"
      echo "  log:      $log"
      echo "  fix:      NA MESMA worktree — ANTES do fix: git -C \"$(row_get "$name" 5)\" merge \"$BASE_BRANCH\"; depois integrate + gate de novo"
      echo "--- últimas 40 linhas do log ---"
      tail -n 40 "$log"
      return 4
    fi
  done
  printf '0 %s\n' "$post" > "$rcf"
  cmd_finish "$name" >/dev/null || {
    err "GATE VERDE de $name, mas o fechamento falhou (acima) — repita: do-wt.sh finish $name"
    return 1; }
  echo "GATE VERDE — $name fechado"
}

cmd_assert_clean() { # [--wave N] — PORTÃO inter-onda (sem --wave: fim da execução)
  local N="" lo re
  case "${1:-}" in
    "") : ;;
    --wave) N="${2:-}"
      case "$N" in ""|*[!0-9]*) err "uso: do-wt.sh assert-clean [--wave N]"; return 2 ;; esac ;;
    *) err "uso: do-wt.sh assert-clean [--wave N]"; return 2 ;;
  esac
  lo=$(ledger_leftovers "$N"); re=$(reality_leftovers)
  if [ -z "$lo" ] && [ -z "$re" ]; then
    if [ -n "$N" ]; then echo "ASSERT-CLEAN OK — a onda $N pode abrir"; else echo "ASSERT-CLEAN OK — tudo fechado"; fi
    return 0
  fi
  if [ -n "$N" ]; then echo "ASSERT-CLEAN FALHOU — a onda $N NÃO abre. Feche cada sobra pelo comando e repita:"
  else echo "ASSERT-CLEAN FALHOU — ainda há sobra desta execução. Feche cada uma pelo comando e repita:"; fi
  [ -n "$lo" ] && printf '%s\n' "$lo"
  [ -n "$re" ] && printf '%s\n' "$re"
  return 1
}

cmd_ledger() { # tabela legível — fonte da seção "Não integrado" do relatório final
  local refs
  refs=$(gwt for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID/" 2>/dev/null)
  printf '%-28s %-11s %-4s %-12s %-34s %s\n' NOME KIND ONDA STATUS OUTCOME ARCHIVE_REF
  DO_LEDGER_REFS="$refs" awk -F'\t' -v pfx="refs/do-archive/$RUN_ID/" "$AWK_LIB"'
    BEGIN { n = split(ENVIRON["DO_LEDGER_REFS"], a, "\n"); for (i = 1; i <= n; i++) has[a[i]] = 1 }
    NR>1 {
      oc = ($11 == "" ? "-" : $11); w = wave_row($3, $2, $10); ref = pfx $3
      printf "%-28s %-11s %-4s %-12s %-34s %s\n", $3, $2, (w >= 0 ? w : "-"), $9, oc, ((ref in has) ? ref : "-")
      if ($9 != "REMOVED") open++
      else if (oc == "MERGED") merged++
      else if (oc ~ /^NEVER-MERGED/) never++
      else if (oc ~ /^MERGED-PARTIAL/) partial++
      else if (oc == "EMPTY") empty++
      else if (oc == "DISPOSABLE") disp++
      else other++
    }
    END { printf "RESUMO: integradas=%d nunca-integradas=%d vazias=%d descartaveis=%d parciais=%d abertas=%d sem-destino=%d\n", \
                 merged, never, empty, disp, partial, open, other }' "$OWNED"
}

cmd_purge() { # COMMIT-FINAL: garantia final — NADA desta execução sobrevive.
  # Diferente do sweep (que só fecha o integrado e PRESERVA ACTIVE/BLOCKED/
  # ORPHANED para diagnóstico durante a onda), o purge fecha TODAS as linhas:
  # MERGED/gate-pending com squash registrado => finish --gate-ok (o squash já
  # está em BASE_BRANCH; o finish pode declarar MERGED-PARTIAL — cauda não
  # integrada e/ou gate VERMELHO, e o arquivamento SEMPRE precede a destruição,
  # inclusive o HEAD da filha que saiu do branch); o resto => close --discard
  # "purge" (salva restos, ARQUIVA o branch, remove com --force). Nada é
  # perdido. Alvos vêm EXCLUSIVAMENTE do owned.tsv (nunca de git worktree list /
  # branch --list — R8d), lidos por awk (NUNCA `IFS=$'\t' read`: colapsa as
  # colunas 7/8 vazias). O stderr de cada fechamento NÃO é engolido: a falha
  # aparece com o motivo.
  local rc=0 name st
  while IFS= read -r name <&3; do
    [ -n "$name" ] || continue
    st=$(row_get "$name" 9)
    [ "$st" = REMOVED ] && continue      # fechada no caminho (snapshot do parent)
    case "$st" in
      MERGED|gate-pending)
        if [ -n "$(row_get "$name" 8)" ]; then
          cmd_finish "$name" --gate-ok | sed 's/^/PURGE: /' || rc=1
          continue
        fi ;;
    esac
    close_unintegrated "$name" "purge" | sed 's/^/PURGE: /' || rc=1
  done 3< <(awk -F'\t' 'NR>1 && $9!="REMOVED" {print $3}' "$OWNED")

  # Linhas REMOVED pelos primitivos cujo branch/diretório ainda existe.
  while IFS= read -r name <&3; do
    [ -n "$name" ] || continue
    if [ -e "$(row_get "$name" 5)" ] || gwt show-ref --verify --quiet "refs/heads/$(row_get "$name" 4)"; then
      if [ -n "$(row_get "$name" 8)" ] && { [ "$(row_get "$name" 11)" = MERGED ] || [ "$(row_get "$name" 11)" = "-" ]; }; then
        cmd_finish "$name" --gate-ok | sed 's/^/PURGE: /' || rc=1
      else
        close_unintegrated "$name" "purge" | sed 's/^/PURGE: /' || rc=1
      fi
    fi
  done 3< <(awk -F'\t' 'NR>1 && $9=="REMOVED" {print $3}' "$OWNED")

  # "PURGE OK" só se o LEDGER e a REALIDADE fecharam (diretório ausente com
  # registro travado + branch vivo já rendeu "PURGE OK" falso).
  local left re
  left=$(awk -F'\t' 'NR>1 && $9!="REMOVED" {c++} END{print c+0}' "$OWNED")
  re=$(reality_leftovers)
  if [ "$left" != 0 ]; then
    echo "PURGE: $left linha(s) do owned.tsv não fechada(s) — o motivo está acima; resolva e rode o purge de novo:"
    ledger_leftovers ""
    rc=1
  fi
  if [ -n "$re" ]; then
    echo "PURGE: a REALIDADE não fechou com o ledger (são sobras DESTA execução — o namespace contém o RUN_ID):"
    printf '%s\n' "$re"
    rc=1
  fi
  [ "$rc" = 0 ] && echo "PURGE OK — nenhuma worktree/branch de sub-agente desta execução sobrou"
  [ "$rc" = 0 ] || echo "PURGE INCOMPLETO — rc=1"

  # I-MERGE: trabalho NUNCA integrado (NEVER-MERGED) e a INTEGRAÇÃO PARCIAL
  # (MERGED-PARTIAL: o squash está em $BASE_BRANCH, mas sobrou cauda não
  # integrada e/ou o gate fechou VERMELHO) NUNCA somem em silêncio — um bloco
  # só, obrigatório no relatório final, e rc 3 quando qualquer um dos dois
  # existiu nesta execução.
  local block
  block=$(awk -F'\t' -v pfx="refs/do-archive/$RUN_ID/" \
    'NR>1 && ($11 ~ /^NEVER-MERGED/ || $11 ~ /^MERGED-PARTIAL/) {printf "  %-28s kind=%-11s %s  ref=%s%s\n", $3, $2, $11, pfx, $3}' "$OWNED")
  if [ -n "$block" ]; then
    echo "PURGE: NUNCA INTEGRADAS / PARCIAIS (obrigatorio no relatorio final):"
    printf '%s\n' "$block"
    echo "  (recuperar: git branch resgate/<nome> <ref> — refs locais, NÃO vão no push)"
    [ "$rc" = 0 ] && rc=3
  fi
  return $rc
}

# =============================================================================
case "${1:-}" in
  new)          shift; cmd_new "${1:-}" "${2:-}" ;;
  integrate)    shift; cmd_integrate "$@" ;;
  gate-set)     shift; cmd_gate_set "$@" ;;
  gate)         shift; cmd_gate "$@" ;;
  finish)       shift; cmd_finish "$@" ;;
  close)        shift; cmd_close "$@" ;;
  assert-clean) shift; cmd_assert_clean "$@" ;;
  ledger)       shift; cmd_ledger "$@" ;;
  merge)        shift; cmd_merge "$@" ;;
  undo)         shift; cmd_undo "$@" ;;
  remove)       shift; cmd_remove "$@" ;;
  drop-branch)  shift; cmd_drop_branch "$@" ;;
  sweep)        shift; cmd_sweep "$@" ;;
  purge)        shift; cmd_purge "$@" ;;
  verify)       shift; cmd_verify "$@" ;;
  stage-delta)  shift; cmd_stage_delta "$@" ;;
  clean-ignored-delta) shift; cmd_clean_ignored_delta "$@" ;;
  wave-files)   shift; cmd_wave_files "$@" ;;
  status)       shift; cmd_status "$@" ;;
  mark)         shift; cmd_mark "$@" ;;
  *)            err "do-wt.sh: subcomando desconhecido: $1 (veja do-wt.sh --help)"; exit 2 ;;
esac
