#!/usr/bin/env bash
# =============================================================================
# do-context.sh — FASE 0 do deep-orchestrator: DELIMITA A RAIZ-DE-MUNDO
# -----------------------------------------------------------------------------
# Descobre onde o orquestrador tem permissão de existir e grava tudo num arquivo
# de estado que TODA chamada Bash posterior deve sourcear.
#
# O problema que este script resolve: quando a skill é invocada com o cwd dentro
# de uma git worktree VINCULADA, o repositório principal continua acessível —
# mesmo .git, mesmos refs, mesmos branches. Nada no git impede o orquestrador de
# commitar em main, criar worktrees ao lado do projeto principal ou apagar
# branches de outra sessão. Este script transforma essa ambiguidade em
# variáveis explícitas: BASE_DIR (a fronteira), BASE_BRANCH (o único alvo de
# integração) e MAIN_ROOT (a zona proibida).
#
# Uso:
#   do-context.sh [--new-run] [--force-nested] [--quiet]
#
# Por padrão, se já existir uma execução em andamento nesta worktree (owned.tsv
# com sub-tarefas não finalizadas), o script REAPROVEITA o estado dela em vez de
# criar uma execução nova — senão as worktrees da execução anterior ficariam
# órfãs para sempre, já que a limpeza só aceita alvos do próprio owned.tsv.
# Use --new-run para forçar uma execução nova.
#
# Saída: caminho do arquivo de estado em stdout (última linha) + resumo legível.
# Sourceie-o em toda chamada Bash posterior:   . "<ENV_FILE>"
#
# Exit codes:
#   0 = ok
#   3 = cwd não está dentro de um repositório git
#   4 = HEAD destacado (não há branch de integração)
#   5 = repositório sem commits
#   6 = índice sujo (há mudanças estagiadas que não são desta execução)
#   7 = path com caractere que quebraria o arquivo de estado
#   8 = `git rev-parse` respondeu de forma inesperada (git muito antigo/exótico)
#   9 = colisão de namespace de branch
# =============================================================================

set -uo pipefail

# Vazamento verificado: GIT_DIR exportada VENCE `git -C <path>`. Se o processo
# pai tiver qualquer uma dessas variáveis no ambiente, todo comando git deste
# script operaria no repositório errado — inclusive os `git -C "$BASE_DIR"`.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

QUIET=0
NEW_RUN=0
FORCE_NESTED="${DO_FORCE_NESTED:-0}"
for a in "$@"; do
  case "$a" in
    --quiet)        QUIET=1 ;;
    --new-run)      NEW_RUN=1 ;;
    --force-nested) FORCE_NESTED=1 ;;
    -h|--help)      sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "do-context.sh: opção desconhecida: $a" >&2; exit 2 ;;
  esac
done

say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
die() { printf 'DO_ABORT %s: %s\n' "$1" "$2" >&2; exit "$1"; }

# --- (0.1) É um repositório? -------------------------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die 3 "o diretório atual não está dentro de um repositório git"

BASE_DIR=$(git rev-parse --show-toplevel) || die 3 "não consegui resolver --show-toplevel"
cd "$BASE_DIR" || die 3 "não consegui entrar em $BASE_DIR"

# --- (0.2) Reaproveitar execução em andamento --------------------------------
# Uma segunda FASE 0 criaria um owned.tsv novo e vazio, e as worktrees da
# execução anterior ficariam inalcançáveis pela limpeza (que só aceita alvos
# registrados) e intocáveis pela regra que proíbe derivar alvos de
# `git worktree list`. Resultado: worktree + branch + lock vazando na máquina.
if [ "$NEW_RUN" = 0 ]; then
  for prev in "$BASE_DIR"/.deep-orchestrator/run-*/env; do
    [ -f "$prev" ] || continue
    pend=$(awk -F'\t' 'NR>1 && $9!="REMOVED" && $9!="BLOCKED" && $9!="ORPHANED" {c++} END{print c+0}' \
             "$(dirname "$prev")/owned.tsv" 2>/dev/null || echo 0)
    [ "$pend" -gt 0 ] || continue
    say "DO_REUSE: execução em andamento encontrada ($pend sub-tarefa(s) pendentes)."
    say "          Reaproveitando o estado dela. Use --new-run para forçar uma nova."
    say ""
    printf '%s\n' "$prev"
    exit 0
  done
fi

# --- (0.3) MODO: normal ou contido ------------------------------------------
# Canonicalizar ANTES de comparar. Sem isso, num SUBDIRETÓRIO da árvore
# principal `--git-dir` devolve /abs/.git e `--git-common-dir` devolve ../.git:
# strings diferentes, mesmo diretório => falso "contido" (verificado em lab).
#
# A detecção de suporte a --path-format NÃO pode ser por exit code: `git
# rev-parse` ECOA opções desconhecidas e sai 0 (verificado). Detectamos pela
# FORMA da saída — precisa ser um caminho absoluto numa única linha.
_pf=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null | head -1)
if [ "${_pf#/}" != "$_pf" ]; then
  GIT_DIR_ABS=$(git rev-parse --path-format=absolute --git-dir)
  COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir)
else
  GIT_DIR_ABS=$(git rev-parse --absolute-git-dir)
  COMMON_DIR=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
fi
case "$GIT_DIR_ABS$COMMON_DIR" in
  *--path-format*|"") die 8 "git rev-parse devolveu algo inesperado — verifique a versão do git" ;;
esac
[ "${GIT_DIR_ABS#/}" != "$GIT_DIR_ABS" ] || die 8 "git-dir não é absoluto: $GIT_DIR_ABS"
[ "${COMMON_DIR#/}" != "$COMMON_DIR" ]   || die 8 "git-common-dir não é absoluto: $COMMON_DIR"

if [ "$GIT_DIR_ABS" != "$COMMON_DIR" ]; then MODE=contido; else MODE=normal; fi

# --- (0.4) MAIN_ROOT: o checkout principal = ZONA PROIBIDA -------------------
MAIN_ROOT=$(cd "$COMMON_DIR/.." 2>/dev/null && pwd -P) || MAIN_ROOT=""
if [ -n "$MAIN_ROOT" ]; then
  # Repositório bare (ou layout incomum): não existe checkout principal a proteger.
  [ "$(git -C "$MAIN_ROOT" rev-parse --show-toplevel 2>/dev/null)" = "$MAIN_ROOT" ] || MAIN_ROOT=""
fi
[ "$MAIN_ROOT" = "$BASE_DIR" ] && MAIN_ROOT=""   # modo normal: a base É o principal
# Texto para interpolar nos prompts dos sub-agentes — nunca vazio, porque
# `git -C "" status` sai 128 e a instrução ficaria truncada.
if [ -n "$MAIN_ROOT" ]; then
  MAIN_ROOT_DESC="$MAIN_ROOT"
else
  MAIN_ROOT_DESC="<nenhum — não há checkout principal separado nesta invocação>"
fi

# --- (0.5) BASE_BRANCH: o ÚNICO alvo de integração --------------------------
# `git rev-parse --abbrev-ref HEAD` é PROIBIDO aqui: devolve a string "HEAD" com
# HEAD destacado, indistinguível de um branch chamado HEAD.
BASE_BRANCH=$(git branch --show-current 2>/dev/null || true)
[ -n "$BASE_BRANCH" ] || BASE_BRANCH=$(git symbolic-ref -q --short HEAD 2>/dev/null || true)
[ -n "$BASE_BRANCH" ] || die 4 "HEAD destacado — o deep-orchestrator exige um branch de integração.
  Resolva dentro desta worktree com:  git switch -c <nome-do-branch>"

git rev-parse --verify --quiet HEAD >/dev/null \
  || die 5 "repositório sem commits (branch órfão '$BASE_BRANCH').
  'git worktree add' não consegue derivar uma filha de um HEAD inexistente.
  Faça o commit inicial e reinvoque."

# Índice sujo: `git commit` do squash-merge comitaria o ÍNDICE INTEIRO, engolindo
# o que o usuário deixou estagiado. Melhor recusar aqui do que descobrir depois.
git diff --cached --quiet 2>/dev/null \
  || die 6 "há mudanças ESTAGIADAS na worktree que não são desta execução.
  O squash-merge comitaria o índice inteiro e engoliria seu trabalho.
  Resolva com:  git commit   (ou)  git restore --staged .   (ou)  git stash --staged"

# --- (0.6) Identidade da execução -------------------------------------------
BASE_NAME=$(basename "$BASE_DIR")
BASE_SLUG=$(printf '%s' "$BASE_NAME" | sed 's#[^A-Za-z0-9._-]#-#g')
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
BRANCH_NS="do/$BASE_SLUG/$RUN_ID"
PARENT_DIR=$(cd "$BASE_DIR/.." && pwd -P)

# Aspas simples, TAB ou newline em path quebrariam o arquivo de estado (que usa
# aspas simples) e o owned.tsv (que é separado por TAB).
case "$BASE_DIR$PARENT_DIR" in
  *\'*)               die 7 "path contém aspa simples: $BASE_DIR" ;;
  *"$(printf '\t')"*) die 7 "path contém TAB: $BASE_DIR" ;;
esac

git check-ref-format --branch "$BRANCH_NS/probe" >/dev/null 2>&1 \
  || die 9 "namespace de branch inválido: $BRANCH_NS"
git show-ref --verify --quiet "refs/heads/$BRANCH_NS" \
  && die 9 "já existe um branch com o nome do namespace: $BRANCH_NS"

# --- (0.7) CHILD_ROOT: onde nascem as worktrees-filhas ----------------------
# Padrão em MODO CONTIDO: container IRMÃO oculto, ao lado da worktree.
#   Não é o projeto principal, não é rastreado por repositório nenhum, é criado
#   por nós e morre inteiro no fim.
# Por que NÃO dentro da worktree (verificado em lab):
#   1. `git add -A` na worktree embute a filha como "embedded git repository";
#   2. a filha é uma cópia COMPLETA da árvore — o gate (build/testes/linter)
#      roda com as filhas ainda vivas, e jest/pytest/tsc passam a descobrir N
#      cópias de cada teste/módulo;
#   3. `git clean` na worktree propõe remover a filha viva.
# Fallback para ANINHADA: só quando o container irmão cairia DENTRO de alguma
#   working tree git (ex.: worktree hospedada em <repo>/.claude/worktrees/<x>,
#   onde a irmã pousaria dentro do projeto principal — justo o que é proibido)
#   ou quando o diretório-pai não é gravável.
if [ "$MODE" = normal ]; then
  CHILD_ROOT="$PARENT_DIR/$BASE_NAME-worktrees/$RUN_ID"; PLACEMENT=sibling
elif [ "$FORCE_NESTED" = 1 ]; then
  CHILD_ROOT="$BASE_DIR/.deep-orchestrator/worktrees/$RUN_ID"; PLACEMENT=nested
elif git -C "$PARENT_DIR" rev-parse --show-toplevel >/dev/null 2>&1 || [ ! -w "$PARENT_DIR" ]; then
  CHILD_ROOT="$BASE_DIR/.deep-orchestrator/worktrees/$RUN_ID"; PLACEMENT=nested
else
  CHILD_ROOT="$PARENT_DIR/.$BASE_NAME-do/$RUN_ID";            PLACEMENT=sibling
fi

# Symlink em qualquer degrau do caminho é vetor de escrita fora da fronteira.
for p in "$BASE_DIR/.deep-orchestrator" "$CHILD_ROOT" "$(dirname "$CHILD_ROOT")"; do
  [ -L "$p" ] && die 7 "$p é um symlink — recuso criar worktrees através dele"
done

# --- (0.8) SKILL_HOME: a casa da skill (SOMENTE LEITURA/EXECUÇÃO) -----------
# Resolvido a partir da localização real deste script, não por adivinhação:
# scripts/ vive na raiz da casa da skill.
_self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
SKILL_HOME=$(cd "$(dirname "$_self")/.." && pwd -P)
[ -d "$SKILL_HOME/scripts" ] || SKILL_HOME=""

# --- (0.9) Estado persistente ------------------------------------------------
# O shell NÃO persiste entre chamadas Bash do harness. Sem este arquivo, toda
# variável desaparece no comando seguinte.
DO_HOME="$BASE_DIR/.deep-orchestrator"
DO_STATE="$DO_HOME/run-$RUN_ID"
PLAN_FILE="$DO_STATE/TASK_PLAN.md"
OWNED="$DO_STATE/owned.tsv"
ENV_FILE="$DO_STATE/env"

mkdir -p "$DO_STATE" "$CHILD_ROOT" || die 7 "não consegui criar $DO_STATE / $CHILD_ROOT"

printf 'run_id\tkind\tname\tbranch\tpath\tbase_sha\tpre_merge_sha\tpost_merge_sha\tstatus\n' > "$OWNED"

cat > "$ENV_FILE" <<EOF
# deep-orchestrator — estado da execução $RUN_ID. Sourceie em TODA chamada Bash.
MODE='$MODE'
BASE_DIR='$BASE_DIR'
BASE_BRANCH='$BASE_BRANCH'
BASE_NAME='$BASE_NAME'
BASE_SLUG='$BASE_SLUG'
MAIN_ROOT='$MAIN_ROOT'
MAIN_ROOT_DESC='$MAIN_ROOT_DESC'
COMMON_DIR='$COMMON_DIR'
PARENT_DIR='$PARENT_DIR'
CHILD_ROOT='$CHILD_ROOT'
PLACEMENT='$PLACEMENT'
RUN_ID='$RUN_ID'
BRANCH_NS='$BRANCH_NS'
SKILL_HOME='$SKILL_HOME'
DO_HOME='$DO_HOME'
DO_STATE='$DO_STATE'
PLAN_FILE='$PLAN_FILE'
OWNED='$OWNED'
DO_WT='$SKILL_HOME/scripts/do-wt.sh'
export MODE BASE_DIR BASE_BRANCH BASE_NAME BASE_SLUG MAIN_ROOT MAIN_ROOT_DESC
export COMMON_DIR PARENT_DIR CHILD_ROOT PLACEMENT RUN_ID BRANCH_NS SKILL_HOME
export DO_HOME DO_STATE PLAN_FILE OWNED DO_WT

# GIT_DIR exportada VENCE \`git -C\`: zerar em toda chamada.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE 2>/dev/null || true

# git na RAIZ-DE-MUNDO (nunca dependa do cwd)
gwt() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "\$BASE_DIR" "\$@"; }
# git numa worktree-filha:  gch <path> <args...>
gch() { local p="\$1"; shift; env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "\$p" "\$@"; }
# status da raiz-de-mundo, imune ao diretório de estado.
# O esconderijo é por PATHSPEC, que se SOMA aos ignores do usuário — um
# core.excludesFile SUBSTITUIRIA o excludesFile global dele (.DS_Store, *.swp...)
# e encheria o delta de ruído que o \`git add\` depois recusaria.
gstatus() { gwt status --porcelain "\$@" -- ':(exclude,top).deep-orchestrator'; }
# asserção obrigatória antes de QUALQUER escrita de história
gassert() {
  local h; h=\$(gwt symbolic-ref -q --short HEAD 2>/dev/null || true)
  [ "\$h" = "\$BASE_BRANCH" ] || { echo "DO_ABORT: HEAD saiu de \$BASE_BRANCH (agora: \${h:-destacado})" >&2; return 1; }
}
EOF

# shellcheck source=/dev/null
. "$ENV_FILE"

# --- (0.10) Baselines: a prova de que nada vazou ----------------------------
# Todos os escapes conhecidos são SILENCIOSOS. Sem baseline não há detecção.
# -uall é OBRIGATÓRIO: sem ele, um diretório untracked colapsa numa única
# linha "?? docs/" e o stage-delta excluiria o diretório INTEIRO do commit
# final — engolindo arquivos novos que a execução criou dentro dele.
gstatus --untracked-files=all > "$DO_STATE/dirty-baseline.txt"
# Forma NUL-delimitada: `git status --porcelain` sem -z aplica C-quoting em
# path com espaço ou acento ("relat\303\263rio.md") e o path volta com aspas
# literais, que o `git add` recusa. O consumidor (stage-delta) usa esta.
gstatus -z --untracked-files=all > "$DO_STATE/dirty-baseline.nul"
# Baseline de IGNORADOS: `git clean -fdX` às cegas (outrora no COMMIT-FINAL)
# apagaria node_modules/.venv/.env.local que o usuário já tinha ANTES da
# FASE 0 junto com as dependências instaladas pelo gate. O ÚNICO clean
# permitido em BASE_DIR é o delta contra este baseline
# (do-wt.sh clean-ignored-delta).
gstatus --ignored > "$DO_STATE/ignored-baseline.txt"
gstatus --ignored -z > "$DO_STATE/ignored-baseline.nul"
gwt config --list --local 2>/dev/null > "$DO_STATE/config-baseline.txt"
[ -s "$DO_STATE/config-baseline.txt" ] || die 8 "baseline de config vazio — a FASE 0 falhou em silêncio"

if [ -n "$MAIN_ROOT" ]; then
  git -C "$MAIN_ROOT" rev-parse HEAD > "$DO_STATE/main-head.txt" 2>/dev/null || true
  # --ignored=traditional detecta um node_modules/ NASCENDO no principal, que o
  # status comum não veria. (Não detecta arquivo novo DENTRO de um diretório
  # ignorado que já existia — limite documentado da prova.)
  git -C "$MAIN_ROOT" status --porcelain --ignored=traditional 2>/dev/null \
    > "$DO_STATE/main-status.txt"
fi

# Inventário de worktrees de TERCEIROS — só para o relatório final. NUNCA vira alvo.
gwt worktree list --porcelain -z 2>/dev/null | tr '\0' '\n' \
  | awk '/^worktree /{print substr($0,10)}' \
  | grep -vF -e "$BASE_DIR" -e "$CHILD_ROOT" > "$DO_STATE/foreign-worktrees.txt" || true

# --- (0.11) Avisos não-bloqueantes ------------------------------------------
case "$MODE:$BASE_BRANCH" in
  contido:main|contido:master|contido:develop|contido:trunk)
    say "DO_WARN: MODE=contido, mas BASE_BRANCH=$BASE_BRANCH. Os squash-commits irão"
    say "         para ESTE branch (o HEAD desta worktree). Registre no relatório." ;;
esac
[ -n "$SKILL_HOME" ] || say "DO_WARN: SKILL_HOME não resolvido — siga SEM pesquisa web (não dispare R7)."

say "FASE 0 OK"
say "  MODE          = $MODE"
say "  BASE_DIR      = $BASE_DIR          (RAIZ-DE-MUNDO — fronteira de escrita)"
say "  BASE_BRANCH   = $BASE_BRANCH       (ÚNICO alvo de integração)"
say "  MAIN_ROOT     = $MAIN_ROOT_DESC    (ZONA PROIBIDA)"
say "  CHILD_ROOT    = $CHILD_ROOT ($PLACEMENT)"
say "  BRANCH_NS     = $BRANCH_NS"
say "  SKILL_HOME    = ${SKILL_HOME:-<não resolvido>}  (somente leitura)"
say "  worktrees de terceiros: $(wc -l < "$DO_STATE/foreign-worktrees.txt" 2>/dev/null || echo 0) (NÃO tocar)"
say ""
say "Sourceie em TODA chamada Bash posterior:"
printf '%s\n' "$ENV_FILE"
