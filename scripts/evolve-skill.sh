#!/usr/bin/env bash
# =============================================================================
# evolve-skill.sh — evolução do CORPO da skill (v3.8.0)
# -----------------------------------------------------------------------------
# A MEMÓRIA da skill mudou de casa na v3.8.0: aprendizados e preferências
# vivem em `.deep-orchestrator-preferences/` (projeto e skill), GITIGNORED,
# geridos por scripts/do-prefs.sh com o questionário scripts/evolution-survey.sh
# (FASE 4, passo 6.5). Este script NÃO persiste mais aprendizados — ele
# evolui o CORPO da skill (SKILL.md, prompts/, docs/), sempre com diff
# revisável e nunca merge sozinho.
#
# Uso:
#   evolve-skill.sh search <termo>
#       grep -i pelo termo na memória consultiva (global-tips.md + prefs do
#       projeto quando resolvíveis) + prompts/*.md + SKILL.md. Entradas de
#       bloco saem como 'id | data | type | confidence | source | título'
#       (dedup por id). Exit 0 com resultados, 1 sem.
#   evolve-skill.sh diff [--stat]
#       git diff HEAD -- <paths do corpo> — mudanças pendentes da evolução;
#       '--stat' resume.
#   evolve-skill.sh apply [--direct] [--branch <nome>] [--message <msg>]
#       Commita as mudanças do corpo. Default: branch evolve/YYYY-MM-DD a
#       partir do branch atual (NUNCA commit direto — D8/Habituation: o diff
#       fica para revisão humana); --direct: commit no branch atual;
#       --branch <nome>: usa o nome dado. Mensagem: conventional commit
#       'evolve(body): <resumo>' (ou --message). Imprime o diff --stat do
#       commit. NUNCA faz push.
#   evolve-skill.sh status
#       SKILL_REPO, branch atual, versão da skill (frontmatter do SKILL.md),
#       estado das prefs (via do-prefs.sh status, quando resolvível),
#       branches evolve/* abertas.
#   evolve-skill.sh --help
#
# Exit codes:
#   0 = sucesso
#   1 = search sem resultados
#   2 = erro de uso/ambiente: opção desconhecida, skill instalada por CÓPIA
#       sem git, lock ocupado
#   3 = identidade: o SKILL.md da casa não tem 'name: deep-orchestrator-agent-skill'
#   4 = escrita detectada fora da allowlist (working tree, staged ou commit)
#
# GARANTIAS DE SEGURANÇA (implementadas como código, não como comentário):
#   • a casa da skill é resolvida pela localização DESTE script, com pwd -P
#     colapsando a cadeia de symlinks — o cwd de invocação é irrelevante;
#   • sem repositório git válido → exit 2 (skill instalada por CÓPIA: rode
#     scripts/sync-global-skill.sh para converter para symlink);
#   • guarda de identidade: só opera se o SKILL.md contém exatamente
#     'name: deep-orchestrator-agent-skill';
#   • ALLOWLIST do CORPO (relativos a SKILL_REPO): SKILL.md (raiz E
#     .claude/skills/deep-orchestrator-agent-skill/SKILL.md), prompts/,
#     docs/decisions/, README.md, scripts/README.md, check-install.sh,
#     CHANGELOG.md — o git status --porcelain é fotografado no início e
#     conferido após cada mutação; qualquer path novo fora da allowlist →
#     exit 4 (scripts/*.sh e a memória em prefs ficam FORA do apply);
#   • NENHUM commit engole staged alheio: antes de commitar o índice é
#     conferido (git diff --cached --name-only) e QUALQUER path staged fora da
#     allowlist → exit 4 SEM tocar no índice;
#   • flock exclusivo (em <gitdir>/evolve-skill.lock) durante o apply —
#     execuções paralelas não colidem;
#   • nunca usa $PWD do chamador para resolver nada da skill; nunca push;
#     nunca mexe na versão da skill (metadata.version é de outra sub-tarefa).
# =============================================================================

set -uo pipefail

# O orquestrador pode exportar GIT_DIR/GIT_WORK_TREE etc. para o próprio fluxo;
# `git -C` não sobrevive a isso (GIT_DIR tem precedência). Zeramos o ambiente
# git herdado para que TODOS os git aqui sejam explícitos via -C.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

SKILL_NAME="deep-orchestrator-agent-skill"

err()  { printf 'evolve-skill.sh: %s\n' "$*" >&2; }
say()  { printf '%s\n' "$*"; }
warn() { printf 'evolve-skill.sh: %s\n' "$*" >&2; }
die()  { err "$*"; exit 2; }

# ---------------------------------------------------------------------------
# Resolução da casa da skill — NUNCA pelo cwd do chamador
# ---------------------------------------------------------------------------
_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)"
if [ -z "$_self" ]; then
  err "não consegui resolver o próprio diretório"
  exit 2
fi
SKILL_HOME="$(cd "$_self/.." && pwd -P 2>/dev/null || true)"
if [ -z "$SKILL_HOME" ] || [ ! -d "$SKILL_HOME/scripts" ]; then
  err "SKILL_HOME inválido ($SKILL_HOME)"
  exit 2
fi

# Repositório git que contém a casa da skill. Sem git → a skill está instalada
# por CÓPIA num lugar sem repositório: não há onde commitar a evolução do corpo.
SKILL_REPO="$(git -C "$SKILL_HOME" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$SKILL_REPO" ]; then
  err "skill instalada por CÓPIA sem git — rode scripts/sync-global-skill.sh para converter para symlink"
  exit 2
fi

# Guarda de identidade: o SKILL.md da raiz é symlink; o grep lê o arquivo real.
if ! grep -qx "name: $SKILL_NAME" "$SKILL_HOME/SKILL.md" 2>/dev/null; then
  err "não é a casa desta skill: $SKILL_HOME/SKILL.md não tem 'name: $SKILL_NAME'"
  exit 3
fi

# ---------------------------------------------------------------------------
# Parsers/validadores compartilhados do formato de bloco (fonte única)
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "$_self/lib/evolve-common.sh"

# ALLOWLIST do CORPO (relativos a SKILL_REPO). A memória (LEARNINGS.md) saiu na
# v3.8.0 — vive em .deep-orchestrator-preferences/ (gitignored, do-prefs.sh).
# scripts/*.sh NÃO estão na allowlist: edição de script não é edição de corpo
# via este comando (é trabalho de sub-tarefa normal da orquestração).
ALLOWED_PATHS=(SKILL.md .claude/skills/deep-orchestrator-agent-skill/SKILL.md prompts/ docs/decisions/ README.md scripts/README.md check-install.sh CHANGELOG.md)

# Memória consultiva para o search: dicas globais (sempre) + prefs do projeto
# (via env PROJECT_PREFS_DIR do ENV_FILE, ou --project <dir>).
GLOBAL_PREFS_DIR="$SKILL_HOME/.deep-orchestrator-preferences"
PROJECT_PREFS_DIR="${PROJECT_PREFS_DIR:-}"

# Fotografia do git status --porcelain no início: a conferência da allowlist
# tolera o que JÁ estava sujo antes deste script rodar (outras sub-tarefas do
# orquestrador podem estar mexendo em SKILL.md/README.md ao mesmo tempo) e
# dispara exit 4 apenas para paths NOVOS fora da allowlist.
PORCELAIN_BEFORE="$(git -C "$SKILL_REPO" status --porcelain 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  # Imprime o cabeçalho INTEIRO (da linha 2 até o fechamento '# ==='), sem
  # depender do número de linhas — o doc cresceu com os defaults novos (F8/F6).
  awk 'NR==1{next} /^# =+$/ && NR>2 {exit} {print}' "$0" | sed 's/^# \{0,1\}//'
}

is_allowed_path() { # <path> → 0 se dentro da allowlist
  local p="$1" a
  for a in "${ALLOWED_PATHS[@]}"; do
    case "$a" in
      */) case "$p" in "$a"*) return 0 ;; esac ;;
      *)  [ "$p" = "$a" ] && return 0 ;;
    esac
  done
  return 1
}

detect_outside_write() { # 0 se apareceu path novo fora da allowlist (não fomos nós → tolerado)
  local line st p out staged sp
  out="$(git -C "$SKILL_REPO" status --porcelain 2>/dev/null || true)"
  if [ -n "$out" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      st="${line:0:2}"
      p="${line:3}"
      if ! is_allowed_path "$p"; then
        if printf '%s\n' "$PORCELAIN_BEFORE" | grep -Fqx -- "$line"; then
          continue   # já estava assim antes de este script rodar — não fomos nós
        fi
        err "ESCRITA FORA DA ALLOWLIST detectada: $p ($st)"
        err "allowlist: ${ALLOWED_PATHS[*]}"
        return 0
      fi
    done <<< "$out"
  fi
  staged="$(git -C "$SKILL_REPO" diff --cached --name-only 2>/dev/null || true)"
  while IFS= read -r sp; do
    [ -n "$sp" ] || continue
    if ! is_allowed_path "$sp"; then
      if printf '%s\n' "$PORCELAIN_BEFORE" | grep -Fq -- "$sp"; then
        continue
      fi
      err "ESCRITA FORA DA ALLOWLIST detectada (staged): $sp"
      err "allowlist: ${ALLOWED_PATHS[*]}"
      return 0
    fi
  done <<< "$staged"
  return 1
}

guard_allowlist() {
  detect_outside_write && exit 4
  return 0
}

# Guarda pré-commit: NENHUM path fora da allowlist pode estar no índice.
# O staged do usuário/outra sub-tarefa é preservado — nunca fazemos reset —
# mas o nosso commit NUNCA o engole: abortamos (exit 4) antes de qualquer
# mutação, listando o path.
guard_staged_allowlist() {
  local staged sp bad=0
  staged="$(git -C "$SKILL_REPO" diff --cached --name-only 2>/dev/null || true)"
  while IFS= read -r sp; do
    [ -n "$sp" ] || continue
    if ! is_allowed_path "$sp"; then
      err "PATH STAGED FORA DA ALLOWLIST: $sp — abortando SEM commitar (índice preservado)"
      bad=1
    fi
  done <<< "$staged"
  if [ "$bad" = 1 ]; then
    err "allowlist: ${ALLOWED_PATHS[*]}"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# search — memória consultiva (prefs) + corpo
# ---------------------------------------------------------------------------
# Blocos (global-tips.md, learnings.md do projeto) saem no formato
# 'id | data | type | confidence | source | título'; prompts/ e SKILL.md saem
# como 'arquivo: linha'. Dedup por id nos blocos.
cmd_search() {
  local term="$1" found=0
  local tmp n i f
  local M_ID M_DATE M_TYPE M_CONF M_SRC M_STATUS M_TAGS M_TITLE
  local seen="" id bfile
  local -a blockfiles=("$GLOBAL_PREFS_DIR/global-tips.md")
  if [ -n "$PROJECT_PREFS_DIR" ]; then
    blockfiles+=("$PROJECT_PREFS_DIR/learnings.md")
    blockfiles+=("$PROJECT_PREFS_DIR/pending/proposals.md")
  fi
  [ -n "$PROJECT_PREFS_DIR" ] || blockfiles+=("$GLOBAL_PREFS_DIR/pending/proposals.md")
  for bfile in "${blockfiles[@]}"; do
    [ -f "$bfile" ] || continue
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/evolve-search.XXXXXX")" || continue
    split_entries "$bfile" "$tmp"
    n=$(cat "$tmp/COUNT")
    for ((i = 1; i <= n; i++)); do
      f=$(printf '%s/%03d.entry' "$tmp" "$i")
      entry_valid_id "$f" || continue
      if grep -qi "$term" "$f"; then
        IFS='|' read -r M_ID M_DATE M_TYPE M_CONF M_SRC M_STATUS M_TAGS M_TITLE <<< "$(entry_meta "$f")"
        id="$M_ID"
        if ! printf '%s\n' "$seen" | grep -Fqx -- "$id"; then
          seen="${seen}${id}"$'\n'
          printf '%s | %s | %s | %s | %s | %s\n' "$id" "$M_DATE" "$M_TYPE" "$M_CONF" "$M_SRC" "$M_TITLE"
          found=1
        fi
      fi
    done
    rm -rf "$tmp"
  done
  # configs do projeto (linhas '- ...') e corpo: contexto bruto com arquivo:linha.
  local sf
  if [ -n "$PROJECT_PREFS_DIR" ] && [ -f "$PROJECT_PREFS_DIR/project-config.md" ]; then
    sf="$PROJECT_PREFS_DIR/project-config.md"
    while IFS= read -r line; do
      printf '%s: %s\n' "project-config.md" "$line"
      found=1
    done < <(grep -in "$term" "$sf")
  fi
  for sf in "$SKILL_HOME"/prompts/*.md "$SKILL_HOME/SKILL.md"; do
    [ -f "$sf" ] || continue
    while IFS= read -r line; do
      printf '%s: %s\n' "$(basename "$sf")" "$line"
      found=1
    done < <(grep -in "$term" "$sf")
  done
  [ "$found" = 1 ] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------

cmd_diff() {
  local stat=0
  if [ $# -gt 1 ]; then
    die "diff: aceita no máximo --stat"
  fi
  [ "${1:-}" = "--stat" ] && stat=1
  [ $# -eq 0 ] || [ "$1" = "--stat" ] || die "diff: opção desconhecida: $1"

  local -a paths=() a
  for a in "${ALLOWED_PATHS[@]}"; do
    case "$a" in
      */) [ -d "$SKILL_REPO/$a" ] && paths+=("$a") ;;
      *)  [ -e "$SKILL_REPO/$a" ] && paths+=("$a") ;;
    esac
  done
  if [ "$stat" = 1 ]; then
    git -C "$SKILL_REPO" diff HEAD --stat -- "${paths[@]}"
  else
    git -C "$SKILL_REPO" diff HEAD -- "${paths[@]}"
  fi
  local untracked
  untracked=$(git -C "$SKILL_REPO" ls-files --others --exclude-standard -- "${paths[@]}" 2>/dev/null || true)
  if [ -n "$untracked" ]; then
    if [ "$stat" = 1 ]; then
      printf '%s\n' "$untracked" | sed 's/^/novo (não rastreado): /'
    else
      printf '\n## Não rastreados (serão incluídos pelo apply):\n'
      printf '%s\n' "$untracked" | sed 's/^/  /'
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# apply — corpo, sempre com diff revisável (nunca merge sozinho)
# ---------------------------------------------------------------------------

GIT_DIR_ABS=""
acquire_lock() { # flock EXCLUSIVO não-bloqueante em <gitdir>/evolve-skill.lock
  if ! command -v flock >/dev/null 2>&1; then
    warn "flock não disponível (util-linux) — prosseguindo sem exclusão mútua"
    return 0
  fi
  if [ -z "$GIT_DIR_ABS" ]; then
    GIT_DIR_ABS="$(git -C "$SKILL_REPO" rev-parse --absolute-git-dir 2>/dev/null || printf '%s/.git' "$SKILL_REPO")"
  fi
  LOCK_FILE="$GIT_DIR_ABS/evolve-skill.lock"
  if ! exec 9>>"$LOCK_FILE"; then
    err "não consegui abrir o lock $LOCK_FILE"
    return 1
  fi
  if ! flock -n 9; then
    err "outra execução (apply) está em andamento — lock $LOCK_FILE ocupado"
    return 1
  fi
  return 0
}

release_lock() {
  flock -u 9 2>/dev/null || true
  exec 9>&- || true
}

changed_allowlist_paths() { # paths da allowlist com mudança real (working tree vs HEAD, incl. não rastreados)
  local -a paths=() a
  for a in "${ALLOWED_PATHS[@]}"; do
    case "$a" in
      */) [ -d "$SKILL_REPO/$a" ] && paths+=("$a") ;;
      *)  [ -e "$SKILL_REPO/$a" ] && paths+=("$a") ;;
    esac
  done
  {
    git -C "$SKILL_REPO" diff --name-only HEAD -- "${paths[@]}" 2>/dev/null || true
    git -C "$SKILL_REPO" ls-files --others --exclude-standard -- "${paths[@]}" 2>/dev/null || true
  } | sort -u
}

stage_allowlist_changed() { # estágia APENAS paths da allowlist com mudança real no working tree
  local changed c
  local -a stage=()
  changed="$(changed_allowlist_paths)"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ -e "$SKILL_REPO/$c" ] || git -C "$SKILL_REPO" ls-files --error-unmatch -- "$c" >/dev/null 2>&1; then
      stage+=("$c")
    fi
  done <<< "$changed"
  if [ "${#stage[@]}" -gt 0 ]; then
    git -C "$SKILL_REPO" add -A -- "${stage[@]}" || die "falha no git add"
  fi
}

commit_and_report() { # <mensagem> — commit do que está staged + diff --stat
  local msg="$1"
  msg="${msg:0:72}"
  if git -C "$SKILL_REPO" diff --cached --quiet; then
    say "nada a commitar (sem mudanças nos paths da allowlist)"
    return 0
  fi
  git -C "$SKILL_REPO" commit --quiet -m "$msg" || die "falha no commit"
  say "commitado — $msg"
  git -C "$SKILL_REPO" show --stat --format='%h %s' HEAD
  return 0
}

switch_to_branch() { # <nome> — cria (se faltar) e entra no branch; nunca push
  local bname="$1"
  if git -C "$SKILL_REPO" rev-parse --verify --quiet "refs/heads/$bname" >/dev/null 2>&1; then
    git -C "$SKILL_REPO" checkout --quiet "$bname" || die "não consegui trocar para $bname"
  else
    git -C "$SKILL_REPO" checkout --quiet -b "$bname" || die "não consegui criar $bname"
  fi
  say "branch: $bname"
}

cmd_apply() {
  local direct=0 branch="" message="" a
  while [ $# -gt 0 ]; do
    case "$1" in
      --direct)    direct=1; shift ;;
      --branch)    [ $# -ge 2 ] || die "apply: --branch exige um nome"; branch="$2"; shift 2 ;;
      --branch=*)  branch="${1#--branch=}"; shift ;;
      --message)   [ $# -ge 2 ] || die "apply: --message exige um texto"; message="$2"; shift 2 ;;
      --message=*) message="${1#--message=}"; shift ;;
      *) die "apply: opção desconhecida: $1" ;;
    esac
  done
  [ "$direct" = 1 ] && [ -n "$branch" ] && die "apply: --direct e --branch são mutuamente exclusivos"

  say "apply: validando antes de commitar..."
  acquire_lock || exit 2
  guard_staged_allowlist || exit 4
  guard_allowlist

  if [ "$direct" = 1 ]; then
    say "apply: commit direto no branch atual"
  elif [ -n "$branch" ]; then
    switch_to_branch "$branch"
  else
    # v3.8.0: o "default inteligente" (memória → commit direto) MORREU junto com
    # o LEARNINGS.md — TODO o apply de corpo vai para branch próprio, com diff
    # para revisão humana (D8/Habituation). NUNCA merge sozinho.
    switch_to_branch "evolve/$(date +%F)"
  fi

  stage_allowlist_changed

  local msg resumo
  if [ -n "$message" ]; then
    msg="$message"
  else
    resumo=$(git -C "$SKILL_REPO" diff --cached HEAD --stat | tail -1 | sed 's/^ *//')
    msg="evolve(body): atualização do corpo da skill"
    [ -n "$resumo" ] && msg="evolve(body): $resumo"
  fi

  guard_staged_allowlist || exit 4
  commit_and_report "$msg"
  guard_allowlist
  return 0
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

cmd_status() {
  local branch version
  branch=$(git -C "$SKILL_REPO" symbolic-ref --short HEAD 2>/dev/null || printf '(detached)')
  version=$(sed -n 's/^  version: *"\([^"]*\)".*/\1/p' "$SKILL_HOME/SKILL.md" | head -1)
  [ -n "$version" ] || version='?'
  say "SKILL_REPO  : $SKILL_REPO"
  say "SKILL_HOME  : $SKILL_HOME"
  say "branch      : $branch"
  say "versão      : $version"
  say "memória     : .deep-orchestrator-preferences/ (gitignored — do-prefs.sh)"
  if [ -x "$SKILL_HOME/scripts/do-prefs.sh" ]; then
    "$SKILL_HOME/scripts/do-prefs.sh" status 2>/dev/null || say "prefs       : (do-prefs.sh status indisponível)"
  fi
  local eb
  eb=$(git -C "$SKILL_REPO" for-each-ref --format='%(refname:short)' 'refs/heads/evolve/*' | sort)
  if [ -n "$eb" ]; then
    say "evolve/*    :"
    printf '%s\n' "$eb" | sed 's/^/  /'
  else
    say "evolve/*    : (nenhuma)"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
  '')          usage >&2; exit 2 ;;
  -h|--help|help) usage; exit 0 ;;
  add|consolidate)
    err "subcomando '$1' REMOVIDO na v3.8.0 — a memória mudou de casa:"
    err "  aprendizados e preferências vivem em .deep-orchestrator-preferences/ (gitignored),"
    err "  geridos por scripts/do-prefs.sh (add-project/add-global/pending-add) com o"
    err "  questionário scripts/evolution-survey.sh (FASE 4, passo 6.5). O LEARNINGS.md"
    err "  foi removido do repo — nada de memória é commitado."
    exit 2 ;;
  search)      shift; [ $# -ge 1 ] || die "search: aceita um termo (e --project <dir> opcional)"
               _term=""; while [ $# -gt 0 ]; do
                 case "$1" in
                   --project) [ $# -ge 2 ] || die "search: --project exige um diretório"; PROJECT_PREFS_DIR="$(cd "$2" && pwd -P 2>/dev/null)/.deep-orchestrator-preferences"; shift 2 ;;
                   --project=*) PROJECT_PREFS_DIR="$(cd "${1#--project=}" && pwd -P 2>/dev/null)/.deep-orchestrator-preferences"; shift ;;
                   *) [ -z "$_term" ] && { _term="$1"; shift; } || die "search: aceita exatamente um termo" ;;
                 esac
               done
               [ -n "$_term" ] || die "search: aceita exatamente um termo"
               cmd_search "$_term" ;;
  diff)        shift; cmd_diff "$@" ;;
  apply)       shift; cmd_apply "$@" ;;
  status)      shift; cmd_status "$@" ;;
  *)           die "subcomando desconhecido: ${1:-}" ;;
esac
