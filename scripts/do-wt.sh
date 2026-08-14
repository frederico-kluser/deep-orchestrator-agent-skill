#!/usr/bin/env bash
# =============================================================================
# do-wt.sh — ciclo de vida das worktrees-filhas do deep-orchestrator
# -----------------------------------------------------------------------------
# Toda operação destrutiva do orquestrador passa por aqui, porque toda operação
# destrutiva do git é GLOBAL ao repositório: `git worktree list` enxerga a
# árvore principal e as worktrees de outras sessões; `git branch -D` alcança
# qualquer branch; `git worktree prune` desregistra worktrees de terceiros.
# A fonte de alvos NUNCA é uma varredura — é sempre o owned.tsv desta execução,
# confirmado pelo lock nativo do git como etiqueta de posse.
#
# Uso (sempre com o ENV_FILE da FASE 0 sourceado, ou via --env <arquivo>):
#   do-wt.sh new <kind> <nome>            cria filha, trava e registra
#   do-wt.sh merge <nome> "<mensagem>"    squash-merge guardado na raiz-de-mundo
#   do-wt.sh undo <nome>                  desfaz o squash (revert; reset só sob guarda)
#   do-wt.sh remove <nome> [--artifacts]  remove a filha (com guardas de posse)
#   do-wt.sh drop-branch <nome>           arquiva e apaga o branch (só se MERGED)
#   do-wt.sh sweep                        fim de onda: fecha o que já foi integrado
#   do-wt.sh verify                       prova de contenção (roda a cada onda)
#   do-wt.sh stage-delta                  estagia SÓ o que é nosso (COMMIT-FINAL)
#   do-wt.sh clean-ignored-delta          remove SÓ ignorados pós-FASE 0 (COMMIT-FINAL)
#   do-wt.sh wave-files <nome-da-1a-filha> arquivos tocados pela onda (aceita a 1ª
#                                        filha MERGED da onda; se a passada não foi
#                                        mergeada, resolve pela filha MERGED de menor
#                                        pre_merge_sha do mesmo prefixo ondaN-)
#   do-wt.sh status                       tabela do owned.tsv
#   do-wt.sh mark <nome> <STATUS>         ACTIVE|MERGED|REMOVED|BLOCKED|ORPHANED
#
# kind: feature | test | validation | fix | prep
# =============================================================================

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

if [ "${1:-}" = "--env" ]; then
  # shellcheck source=/dev/null
  . "$2" || { echo "do-wt.sh: não consegui sourcear $2" >&2; exit 2; }
  shift 2
fi

: "${BASE_DIR:?do-wt.sh: sourceie o ENV_FILE da FASE 0 antes (ou use --env <arquivo>)}"
: "${OWNED:?ENV_FILE incompleto: OWNED}"
: "${CHILD_ROOT:?ENV_FILE incompleto: CHILD_ROOT}"
: "${BRANCH_NS:?ENV_FILE incompleto: BRANCH_NS}"
: "${RUN_ID:?ENV_FILE incompleto: RUN_ID}"

gwt()  { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$BASE_DIR" "$@"; }
gch()  { local p="$1"; shift; env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$p" "$@"; }
gstatus() { gwt status --porcelain "$@" -- ':(exclude,top).deep-orchestrator'; }
gassert() {
  local h; h=$(gwt symbolic-ref -q --short HEAD 2>/dev/null || true)
  [ "$h" = "$BASE_BRANCH" ] || { echo "RECUSADO: HEAD saiu de $BASE_BRANCH (agora: ${h:-destacado})" >&2; return 1; }
}
err() { printf '%s\n' "$*" >&2; }

LOCK_REASON="deep-orchestrator run=$RUN_ID"

# --- registro (owned.tsv) ----------------------------------------------------
# colunas: 1 run_id  2 kind  3 name  4 branch  5 path  6 base_sha
#          7 pre_merge_sha  8 post_merge_sha  9 status

row_get() { awk -F'\t' -v n="$1" -v c="$2" 'NR>1 && $3==n {print $c; exit}' "$OWNED"; }

row_set() { # <nome> <coluna> <valor>  — reescrita atômica
  local n="$1" c="$2" v="$3" tmp="$OWNED.tmp.$$"
  awk -F'\t' -v OFS='\t' -v n="$n" -v c="$c" -v v="$v" \
      'NR>1 && $3==n { $c = v } { print }' "$OWNED" > "$tmp" && mv "$tmp" "$OWNED"
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
cmd_new() { # <kind> <nome>
  local kind="${1:?kind}" name="${2:?nome}"
  local br="$BRANCH_NS/$name" wt="$CHILD_ROOT/$name"

  case "$name" in */*|.*|"") err "RECUSADO: nome inválido: $name"; return 1 ;; esac
  gwt show-ref --verify --quiet "refs/heads/$br" && { err "RECUSADO: branch $br já existe"; return 1; }
  [ -e "$wt" ] && { err "RECUSADO: $wt já existe"; return 1; }
  gassert || return 1

  mkdir -p "$CHILD_ROOT" || return 1
  # Base = BASE_BRANCH, o branch DESTA raiz-de-mundo. NUNCA main/master, NUNCA origin/*.
  gwt worktree add -q -b "$br" "$wt" "$BASE_BRANCH" || { err "FALHA: git worktree add"; return 1; }
  gwt worktree lock --reason "$LOCK_REASON" "$wt" || err "AVISO: não consegui travar $wt"

  # Isolamento já falhou em silêncio em produção — asseverar.
  [ -f "$wt/.git" ] || { err "FALHA: $wt/.git não é arquivo (não é worktree)"; return 1; }
  [ "$(gch "$wt" rev-parse --show-toplevel)" = "$wt" ] || { err "FALHA: toplevel divergente"; return 1; }
  [ "$(gch "$wt" symbolic-ref --short HEAD)" = "$br" ] || { err "FALHA: branch errado"; return 1; }

  printf '%s\t%s\t%s\t%s\t%s\t%s\t\t\t%s\n' \
    "$RUN_ID" "$kind" "$name" "$br" "$wt" "$(gwt rev-parse HEAD)" "ACTIVE" >> "$OWNED"

  printf 'OK  worktree=%s\n    branch=%s\n' "$wt" "$br"
}

# =============================================================================
cmd_merge() { # <nome> <mensagem>
  local name="${1:?nome}" msg="${2:?mensagem}"
  local br wt
  br=$(row_get "$name" 4); wt=$(row_get "$name" 5)
  [ -n "$br" ] || { err "RECUSADO: $name não está no owned.tsv"; return 1; }
  gassert || return 1

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
      && gch "$wt" commit -q -m "wip: restos de $name" \
      || { err "FALHA: não consegui commitar restos em $wt"; return 1; }
  fi

  row_set "$name" 7 "$(gwt rev-parse HEAD)"

  gwt merge --squash "$br" || {
    err "CONFLITO no squash-merge de $br."
    err "  Desfaça com:  git -C \"$BASE_DIR\" reset --merge"
    err "  (NÃO use 'git merge --abort': squash-merge não grava MERGE_HEAD.)"
    err "  Resolva DENTRO da filha $wt e re-execute este comando."
    return 1
  }
  gwt diff --cached --quiet && { err "AVISO: $br não trouxe mudança alguma — nada a commitar"; row_set "$name" 9 MERGED; return 0; }
  gwt commit -q -m "$msg" || { err "FALHA: commit do squash"; return 1; }

  row_set "$name" 8 "$(gwt rev-parse HEAD)"
  row_set "$name" 9 MERGED
  printf 'OK  squash de %s -> %s (%s)\n' "$br" "$BASE_BRANCH" "$(gwt rev-parse --short HEAD)"
}

# =============================================================================
cmd_undo() { # <nome> — desfaz o squash-commit de UMA filha
  local name="${1:?nome}" pre post cur
  pre=$(row_get "$name" 7); post=$(row_get "$name" 8); cur=$(gwt rev-parse HEAD)
  gassert || return 1
  [ -n "$post" ] || { err "RECUSADO: $name não tem squash-commit registrado"; return 1; }

  # Caminho PADRÃO: revert. Não toca no working tree do usuário e é seguro mesmo
  # que $BASE_BRANCH já tenha sido pushado.
  if [ "$cur" != "$post" ]; then
    err "HEAD avançou desde o squash de $name — revert é o único caminho seguro."
    gwt revert --no-edit "$post" || { err "FALHA no revert — resolva manualmente"; return 1; }
    row_set "$name" 9 REVERTED; echo "OK  revert de $post"; return 0
  fi

  # reset --hard só é permitido quando: HEAD é exatamente o squash desta filha,
  # o pré-merge é ancestral, há exatamente 1 commit de distância, e o working
  # tree não tem NENHUMA modificação tracked — nem do usuário (o baseline da
  # FASE 0 pode conter " M root.txt" dele), nem da execução. Linhas "??"
  # (untracked) são aceitas: reset --hard não as toca. A comparação contra o
  # baseline é FALSA como guarda: o baseline pode já ter tracked sujo e o
  # reset --hard apagaria essa edição silenciosamente.
  # ATENÇÃO (verificado em lab): NUNCA use `gstatus | grep -qv` com -q aqui —
  # o grep sai no 1º match, fecha o pipe, o gstatus morre com SIGPIPE e, com
  # pipefail, a condição vira falsa -> reset --hard COM modificações tracked.
  # Capturar a saída INTEIRA primeiro (falha real do git aborta aqui) e só
  # então filtrar: grep sem -q consome tudo, SIGPIPE é impossível. O `|| true`
  # no filtro é obrigatório: sem linhas não-"??" o grep -v sai 1 (esperado).
  local st mods
  st=$(gstatus) || { err "FALHA: não consegui ler o status da raiz-de-mundo"; return 1; }
  mods=$(printf '%s\n' "$st" | grep -v '^??' || true)
  if [ -n "$mods" ]; then
    err "Há modificações tracked no working tree — reset --hard PROIBIDO."
    err "Usando revert (preserva o working tree e o histórico)."
    gwt revert --no-edit "$post" || return 1
    row_set "$name" 9 REVERTED; echo "OK  revert de $post"; return 0
  fi
  gwt merge-base --is-ancestor "$pre" HEAD 2>/dev/null || { err "RECUSADO: $pre não é ancestral de HEAD"; return 1; }
  [ "$(gwt rev-list --count "$pre..HEAD")" = "1" ] || { err "RECUSADO: há mais de 1 commit desde o pré-merge"; return 1; }

  gwt update-ref "refs/do-archive/$RUN_ID/undo-$name" "$post"   # rede de segurança
  gwt reset --hard "$pre" || return 1
  row_set "$name" 9 REVERTED
  echo "OK  reset para $pre (commit desfeito arquivado em refs/do-archive/$RUN_ID/undo-$name)"
}

# =============================================================================
cmd_remove() { # <nome> [--artifacts]
  local name="${1:?nome}" opt="${2:-}" wt errout
  wt=$(row_get "$name" 5)
  guard_child "$wt" || return 1
  [ -e "$wt" ] || { row_set "$name" 9 REMOVED; echo "OK  $name já não existia"; return 0; }

  if [ "$opt" = "--artifacts" ]; then
    # Daemons seguram file handles e fazem o remove recusar.
    ( cd "$wt" && command -v gradle >/dev/null 2>&1 && gradle --stop >/dev/null 2>&1 ) || true
    # `clean -fdX` apaga SOMENTE o que o .gitignore já declara descartável.
    # Uma lista fixa de nomes apagaria bin/, dist/ e build/ RASTREADOS, que
    # existem em muitos repositórios (bin/rails, bin/setup, dist/ versionado).
    gch "$wt" clean -fdXq 2>/dev/null || true
  fi

  gwt worktree unlock "$wt" >/dev/null 2>&1
  if errout=$(gwt worktree remove "$wt" 2>&1); then
    row_set "$name" 9 REMOVED; echo "OK  worktree removida: $wt"; return 0
  fi
  # Submódulo: o git recusa por design, e --force resolve. A posse já foi
  # provada por guard_child + owns_lock, então --force não amplia o alvo.
  if printf '%s' "$errout" | grep -qi 'submodule'; then
    if gwt worktree remove --force "$wt" 2>/dev/null; then
      row_set "$name" 9 REMOVED; echo "OK  worktree removida (--force, submódulo): $wt"; return 0
    fi
  fi
  # Recusa por sujeira: re-travar para não perder a etiqueta de posse.
  gwt worktree lock --reason "$LOCK_REASON" "$wt" >/dev/null 2>&1
  err "RECUSADO pelo git ao remover $wt:"
  printf '%s\n' "$errout" | sed 's/^/    /' >&2
  err "  Conteúdo não commitado:"; gch "$wt" status --porcelain | sed 's/^/    /' >&2
  err "  Se for só artefato de build:  do-wt.sh remove $name --artifacts"
  err "  Se for trabalho real: commite na filha e refaça o merge antes de remover."
  return 1
}

# =============================================================================
cmd_drop_branch() { # <nome>
  local name="${1:?nome}" br st
  br=$(row_get "$name" 4); st=$(row_get "$name" 9)
  [ -n "$br" ] || { err "RECUSADO: $name não está no owned.tsv"; return 1; }
  case "$br" in "$BRANCH_NS"/*) : ;; *) err "RECUSADO: $br está fora do namespace desta execução"; return 1 ;; esac
  [ "$br" = "$BASE_BRANCH" ] && { err "RECUSADO: é o branch da raiz-de-mundo"; return 1; }
  case "$st" in
    MERGED|REMOVED) : ;;
    *) err "RECUSADO: $name está com status=$st — só apago branch de sub-tarefa integrada."
       err "  (BLOCKED/ORPHANED/ACTIVE preservam o trabalho do sub-agente para inspeção.)"; return 1 ;;
  esac
  gwt show-ref --verify --quiet "refs/heads/$br" || { echo "OK  $br já não existe"; return 0; }

  # Arquivar antes de apagar: custo zero e recuperável mesmo após gc.
  gwt update-ref "refs/do-archive/$RUN_ID/$name" "$(gwt rev-parse "$br")"
  # `-d` sempre recusa após squash-merge (não há ancestralidade). O que autoriza
  # o `-D` é o status=MERGED — gravado só depois de um squash-commit bem-sucedido.
  gwt branch -D "$br" >/dev/null || { err "FALHA ao apagar $br"; return 1; }
  echo "OK  branch $br apagado (arquivado em refs/do-archive/$RUN_ID/$name)"
}

# =============================================================================
cmd_sweep() { # fim de onda — fecha o que JÁ FOI INTEGRADO. Nunca destrói trabalho.
  local rc=0
  # Profundidade decrescente: remover a pai com filha viva deixa registro órfão.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    local n; n=$(awk -F'\t' -v p="$p" 'NR>1 && $5==p {print $3; exit}' "$OWNED")
    cmd_remove "$n" >/dev/null 2>&1 || cmd_remove "$n" --artifacts || rc=1
  done < <(awk -F'\t' 'NR>1 && $9=="MERGED" {print $5}' "$OWNED" \
           | awk '{print gsub(/\//,"/"), $0}' | sort -rn | cut -d' ' -f2-)

  while IFS= read -r n; do
    [ -n "$n" ] && cmd_drop_branch "$n" >/dev/null || rc=1
  done < <(awk -F'\t' 'NR>1 && ($9=="MERGED" || $9=="REMOVED") {print $3}' "$OWNED")

  # ACTIVE não é limpo: ou o merge ainda não aconteceu, ou é uma testing subwave
  # rodando em background. Ambos guardam trabalho — apenas relatamos.
  local pend
  pend=$(awk -F'\t' 'NR>1 && $9=="ACTIVE" {c++} END{print c+0}' "$OWNED")
  if [ "$pend" = 0 ]; then
    echo "SWEEP OK — nada desta execução ficou pendente"
  else
    echo "SWEEP: $pend sub-tarefa(s) ainda ACTIVE (não integradas ou testing subwave em voo):"
    awk -F'\t' 'NR>1 && $9=="ACTIVE" {printf "  %-28s kind=%s\n",$3,$2}' "$OWNED"
  fi
  local foreign; foreign=$(wc -l < "$DO_STATE/foreign-worktrees.txt" 2>/dev/null || echo 0)
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
  local cfgdiff
  cfgdiff=$(gwt config --list --local 2>/dev/null | diff "$DO_STATE/config-baseline.txt" - | grep '^[<>]' || true)
  if [ -n "$cfgdiff" ]; then
    if printf '%s' "$cfgdiff" | grep -qE 'core\.hookspath|core\.worktree|remote\..*\.url|alias\.'; then
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
      pre=$(awk -F'\t' -v p="$prefix" \
            'NR>1 && $9=="MERGED" && $3 ~ p && $7!="" {print $7}' "$OWNED" \
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
  printf '%-24s %-8s %-10s %s\n' NOME KIND STATUS BRANCH
  awk -F'\t' 'NR>1 {printf "%-24s %-8s %-10s %s\n", $3, $2, $9, $4}' "$OWNED"
}

cmd_mark() { row_set "${1:?nome}" 9 "${2:?status}"; echo "OK  $1 -> $2"; }

# =============================================================================
case "${1:-}" in
  new)          shift; cmd_new "$@" ;;
  merge)        shift; cmd_merge "$@" ;;
  undo)         shift; cmd_undo "$@" ;;
  remove)       shift; cmd_remove "$@" ;;
  drop-branch)  shift; cmd_drop_branch "$@" ;;
  sweep)        shift; cmd_sweep "$@" ;;
  verify)       shift; cmd_verify "$@" ;;
  stage-delta)  shift; cmd_stage_delta "$@" ;;
  clean-ignored-delta) shift; cmd_clean_ignored_delta "$@" ;;
  wave-files)   shift; cmd_wave_files "$@" ;;
  status)       shift; cmd_status "$@" ;;
  mark)         shift; cmd_mark "$@" ;;
  ""|-h|--help) sed -n '2,32p' "$0" ;;
  *)            err "do-wt.sh: subcomando desconhecido: $1"; exit 2 ;;
esac
