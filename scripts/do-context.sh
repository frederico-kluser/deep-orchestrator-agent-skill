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
#   2 = DO_MAX_PARALLEL inválido (não é inteiro positivo), ou SKILL_HOME não
#       resolvido (skill incompleta — do-wt.sh ficaria inalcançável)
#   3 = cwd não está dentro de um repositório git
#   4 = HEAD destacado (não há branch de integração)
#   5 = repositório sem commits
#   6 = índice sujo (há mudanças estagiadas que não são desta execução)
#   7 = path ou BASE_BRANCH com caractere que quebraria o arquivo de estado
#       (aspa simples, TAB ou newline)
#   8 = `git rev-parse` respondeu de forma inesperada (git muito antigo/exótico)
#   9 = colisão de namespace de branch (nome completo ou PREFIXO)
# =============================================================================

set -uo pipefail

# Vazamento verificado: GIT_DIR exportada VENCE `git -C <path>`. Se o processo
# pai tiver qualquer uma dessas variáveis no ambiente, todo comando git deste
# script operaria no repositório errado — inclusive os `git -C "$BASE_DIR"`.
# DO_STATE/DO_HOME/DO_WT também são EXPORTADOS pelo ENV_FILE de uma execução
# anterior: sem desfazê-los, o rollback do die() apagaria a run de OUTRA
# sessão (verificado em lab: run R1 sourceada + die 6 numa 2ª FASE 0 -> R1
# DELETADA). Zerar como as GIT_*.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES \
      DO_STATE DO_HOME DO_WT 2>/dev/null || true

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
die() {
  # Rollback da FASE 0 (F4-07.11): até o estado ser gravado por completo,
  # QUALQUER falha remove o run-* — um run sem env é invisível ao reuso (0.2)
  # e acumula lixo na máquina; um env parcialmente escrito seria reutilizado
  # corrupto por uma sessão seguinte. Guardas (F4-07, validador adversarial):
  # DO_STATE vazio (falhas ANTES do mkdir não criaram nada) E DO_STATE EXATO
  # desta invocação ($DO_HOME/run-$RUN_ID) — a guarda por prefixo deixava o
  # rollback apagar a run de OUTRA sessão quando DO_STATE/DO_HOME vinham
  # EXPORTADOS do ENV_FILE anterior (verificado em lab: run R1 sourceada +
  # die 6 numa 2ª FASE 0 -> R1 DELETADA). O unset no topo zera o vetor; a
  # igualdade ancla o alvo nesta invocação.
  if [ -n "${DO_STATE:-}" ] && [ "$DO_STATE" = "${DO_HOME:-}/run-${RUN_ID:-}" ]; then
    rm -rf "$DO_STATE" 2>/dev/null || true
  fi
  # CHILD_ROOT recém-criado (vazio) também é lixo acumulativo — rmdir só
  # remove diretório VAZIO (nunca toca em worktree com conteúdo).
  if [ -n "${CHILD_ROOT:-}" ]; then
    rmdir "$CHILD_ROOT" 2>/dev/null || true
  fi
  printf 'DO_ABORT %s: %s\n' "$1" "$2" >&2
  exit "$1"
}

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
# Escolha entre múltiplas pendentes: o glob run-*/env é varrido em ordem
# ALFABÉTICA e o RUN_ID é YYYYMMDD-HHMMSS-PID — ordem alfabética = ordem
# cronológica, então a pendente mais ANTIGA vence.
if [ "$NEW_RUN" = 0 ]; then
  for prev in "$BASE_DIR"/.deep-orchestrator/run-*/env; do
    [ -f "$prev" ] || continue
    pend=$(awk -F'\t' 'NR>1 && $9!="REMOVED" && $9!="BLOCKED" && $9!="ORPHANED" {c++} END{print c+0}' \
             "$(dirname "$prev")/owned.tsv" 2>/dev/null || echo 0)
    [ "$pend" -gt 0 ] || continue
    # Revalidação anti-stale (F4-07.12): o env reutilizado só é válido se a
    # raiz-de-mundo AINDA está no MESMO branch da FASE 0 original. Se o branch
    # mudou entre sessões (ou o HEAD foi destacado), os merges iriam para o
    # branch errado — avisa e segue para criar execução nova (--new-run
    # implícito) em vez de reutilizar o env obsoleto.
    _reuse_br=$(sed -n "s/^BASE_BRANCH='\([^']*\)'.*/\1/p" "$prev")
    _cur_br=$(git branch --show-current 2>/dev/null || true)
    if [ -z "$_cur_br" ] || [ "$_cur_br" != "$_reuse_br" ]; then
      say "DO_STALE: a execução em andamento pertence ao branch '$_reuse_br' e o HEAD atual"
      say "          está em '${_cur_br:-<destacado>}' — o env reutilizado seria obsoleto."
      say "          Criando execução NOVA (equivalente a --new-run)."
      say ""
      continue
    fi
    # Revalidação anti-stale do PORTÃO (FASE 2.5): o ENV_FILE é o ÚNICO
    # carregador da decisão do passo 0.5 — o shell do harness não persiste entre
    # chamadas. Reaproveitar um env cujo DO_PLAN_APPROVAL diverge do que ESTA
    # invocação resolveu inverte a decisão em silêncio, nos dois sentidos:
    # `plan=on` sobre um env antigo com '0' pularia a FASE 2.5 e executaria um
    # plano NÃO aprovado (a violação exata que a R10 existe para impedir); e um
    # env com '1' sob `plan=off` abriria um navegador que ninguém pediu. Um env
    # anterior à v3.4.0 nem tem a chave — também diverge, e também precisa de
    # execução nova, senão $PLAN_DOC viria vazio.
    _want_gate="${DO_PLAN_APPROVAL:-0}"
    case "$_want_gate" in 1|on|yes|true) _want_gate=1 ;; *) _want_gate=0 ;; esac
    if grep -q '^DO_PLAN_APPROVAL=' "$prev" 2>/dev/null; then
      _reuse_gate=$(sed -n "s/^DO_PLAN_APPROVAL='\([^']*\)'.*/\1/p" "$prev")
    else
      _reuse_gate="<ausente>"
    fi
    if [ "$_reuse_gate" != "$_want_gate" ]; then
      say "DO_STALE: a execução em andamento tem PLAN_APPROVAL='$_reuse_gate' e esta invocação"
      say "          resolveu '$_want_gate' — reaproveitar inverteria a decisão do portão em silêncio."
      say "          Criando execução NOVA (equivalente a --new-run)."
      say ""
      continue
    fi
    say "DO_REUSE: execução em andamento encontrada ($pend sub-tarefa(s) pendentes)."
    say "          Reaproveitando o estado dela (PLAN_APPROVAL=$_reuse_gate)."
    say "          Use --new-run para forçar uma nova."
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

# --- (0.3b) WT-ROOT: worktree NOMEADA como RAIZ-DE-MUNDO (flag wt=) -----------
# Quando o orquestrador recebe o prefixo `wt=<nome>` (DO_WT_ROOT=1), o trabalho
# NÃO acontece no checkout principal: acontece numa worktree irmã VERDADEIRA do
# projeto, em <pai>/<repo>.worktrees/<nome>, que passa a ser a RAIZ-DE-MUNDO.
#
# Como chega aqui, na prática:
#   • cwd JÁ é a worktree (invocação dentro dela): MODE=contido já vale e este
#     bloco NÃO roda — o fluxo EXISTENTE abaixo trata tudo (ondas, sub-agentes,
#     merges, gates, COMMIT-FINAL) com a fronteira = esta worktree.
#   • cwd é o checkout PRINCIPAL e DO_WT_ROOT=1: criamos/reusamos a worktree irmã,
#     deduplicamos o nome contra o que já existe, ENTRA `<repo>.worktrees/<nome>`
#     e RE-EXECUTAMOS este script com o cwd dentro dela. A re-execução cai no
#     mesmo MODE=contido de sempre — zero lógica duplicada. O sentinel evita loop.
#
# O wt-root é PERSISTENTE: ao contrário das filhas efêmeras de CHILD_ROOT (que
# morrem na onda), ele sobrevive entre execuções — o par pasta/branch se reusa.
if [ "$DO_WT_ROOT" = 1 ] && [ "$MODE" = normal ] && [ "${DO_WT_ROOT_ENTERED:-0}" != 1 ]; then
  _wt_name="${DO_WT_NAME:-}"
  # Nome vem do orquestrador (kebab-case, ≤40 chars). Pode conter espaço do prompt
  # original: normalizamos aqui para um slug seguro de nome de pasta.
  _wt_name=$(printf '%s' "$_wt_name" | tr '[:upper:]' '[:lower:]' \
             | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')
  case "$_wt_name" in
    ""|*/*|.)
      die 7 "DO_WT_ROOT=1 mas DO_WT_NAME resultou num nome inválido: '$_wt_name' — o orquestrador deve passar um nome que vire kebab-case" ;;
  esac
  [ "${#_wt_name}" -le 40 ] || _wt_name="${_wt_name:0:40}"
  # Pasta irmã: <pai>/<repo>.worktrees/ — exatamente o pedido "PROJECT_NAME.worktrees".
  # BASE_NAME ainda não foi resolvido aqui (é (0.6)) — deriva do basename de BASE_DIR.
  # Se JÁ existe (entre execuções), entra nela em vez de recriar (pedido explícito).
  _wt_base="${WT_ROOT_BASE:-$(cd "$BASE_DIR/.." && pwd -P)/$(basename "$BASE_DIR").worktrees}"
  # Dedupe o nome contra o que JÁ EXISTE dentro de <repo>.worktrees/: o pedido é
  # "a pasta irmã pode já existir; entre nela, e só crie um nome que não exista lá
  # dentro". Colisão com um diretório existente (de feature anterior) ganha -2, -3...
  # até um nome livre. A paleta é <nome>, <nome>-2, <nome>-3...
  if [ -e "$_wt_base/$_wt_name" ]; then
    say "DOCTYPE: '$(basename "$BASE_DIR").worktrees/$_wt_name' já existe — procurando nome livre."
    _n=2
    while [ -e "$_wt_base/$_wt_name-$_n" ] && [ "$_n" -lt 1000 ]; do _n=$((_n+1)); done
    [ "$_n" -lt 1000 ] || die 7 "não achei nome livre sob $_wt_base para $_wt_name"
    _wt_name="$_wt_name-$_n"
    say "DO_WT_ROOT: nome deduplicado -> $_wt_name"
  fi
  _wt_path="$_wt_base/$_wt_name"

  # Proteção de symlink: vetor de escrita fora da fronteira.
  for _p in "$_wt_base" "$_wt_path"; do
    [ -L "$_p" ] && die 7 "$_p é um symlink — recuso trabalhar através dele"
  done
  # <pai>/<repo>.worktrees/ é irmã oculta do projeto (como o CHILD_ROOT sibling);
  # só não pode cair DENTRO de outra working tree git — mesmo motivo do CHILD_ROOT.
  if git -C "$(dirname "$_wt_base")" rev-parse --show-toplevel >/dev/null 2>&1 \
     && [ "$(git -C "$(dirname "$_wt_base")" rev-parse --show-toplevel)" != "$(dirname "$_wt_base")" ]; then
    die 7 "o container irmão $_wt_base cairia dentro de outra working tree git"
  fi

  [ -e "$_wt_path" ] && die 7 "$_wt_path existe mas não é uma worktree git (sem .git arquivo) — recuso"
  # Branch determinístico e reusável: do/wt/<nome>. Se o ref já existe (worktree
  # anterior removida/feita prune mas branch preservado), REUSA-o via `add <path>
  # <branch>` (sem -b — nunca -B, que resetaria silenciosamente o branch da run
  # anterior); senão CRIAmos com -b a partir do HEAD.
  _wt_branch="do/wt/$_wt_name"
  git check-ref-format --branch "$_wt_branch" >/dev/null 2>&1 \
    || die 7 "branch inválido: $_wt_branch"
  mkdir -p "$_wt_base" || die 7 "não consegui criar $_wt_base"
  if git show-ref --verify --quiet "refs/heads/$_wt_branch"; then
    git worktree add -q "$_wt_path" "$_wt_branch" \
      || die 7 "worktree em '$_wt_path' do branch '$_wt_branch' falhou — provável: o branch está"
             "  registrado em OUTRA worktree ('git worktree list') ou a entrada anterior virou"
             "  prunable porque o diretório sumiu sem 'git worktree remove' — rode 'git worktree "
             "  prune' no repo principal ($BASE_DIR) e re-invoque"
    say "DO_WT_ROOT: worktree $_wt_path no branch existente $_wt_branch (reusado)"
  else
    git worktree add -q -b "$_wt_branch" "$_wt_path" HEAD \
      || die 7 "não consegui criar a worktree $_wt_path (branch $_wt_branch)"
    say "DO_WT_ROOT: worktree criada em $_wt_path (branch $_wt_branch)"
  fi

  # ENTRA na worktree e RE-RODA este script FASE 0 com o cwd dentro dela. A partir
  # daqui MODE=contido e toda a contenção EXISTENTE vale — nada duplicado.
  cd "$_wt_path" || die 7 "não consegui entrar em $_wt_path"
  DO_WT_ROOT_ENTERED=1
  export DO_WT_ROOT_ENTERED
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true
  exec "$0" "$@"
fi

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

# Aspas simples, TAB ou newline em QUALQUER valor interpolado quebrariam o
# arquivo de estado (que usa aspas simples) e o owned.tsv (que é separado por
# TAB). A validação (F4-07.3) cobre TODAS as variáveis interpoladas no ENV_FILE:
# os paths (BASE_DIR, PARENT_DIR, MAIN_ROOT, COMMON_DIR) e o branch de
# integração (BASE_BRANCH) — um branch "it's" corrompia o ENV_FILE e a FASE 0
# morria com exit 8 enganoso em vez de 7. Espaço e acento SÃO permitidos.
for _v in BASE_DIR PARENT_DIR BASE_BRANCH MAIN_ROOT COMMON_DIR; do
  _val=${!_v}
  case "$_val" in
    *\'*)     die 7 "$_v contém aspa simples: $_val" ;;
    *"$(printf '\t')"*) die 7 "$_v contém TAB: $_val" ;;
    *$'\n'*)  die 7 "$_v contém newline: $_val" ;;
  esac
done

git check-ref-format --branch "$BRANCH_NS/probe" >/dev/null 2>&1 \
  || die 9 "namespace de branch inválido: $BRANCH_NS"
# Colisão de PREFIXO do namespace (F4-07.4): validar só o namespace COMPLETO
# deixa passar um branch "do/wtA" quando o namespace é "do/wtA/<run>/..." — e o
# cmd_new falharia depois com erro genérico (refs/heads/do/wtA já é um ARQUIVO,
# não um diretório). Verifica CADA prefixo (do, do/<slug>, do/<slug>/<run>).
_ns="$BRANCH_NS"
while [ -n "$_ns" ]; do
  git show-ref --verify --quiet "refs/heads/$_ns" \
    && die 9 "colisão de namespace: já existe um branch com o prefixo do namespace: refs/heads/$_ns"
  case "$_ns" in */*) _ns=${_ns%/*} ;; *) _ns="" ;; esac
done

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
# scripts/ vive na raiz da casa da skill. readlink -f NÃO existe no macOS —
# fallback portável: dirname + pwd -P.
_self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)
SKILL_HOME=""
[ -n "$_self_dir" ] && SKILL_HOME=$(cd "$_self_dir/.." && pwd -P 2>/dev/null || true)
[ -d "$SKILL_HOME/scripts" ] || SKILL_HOME=""
# DO_WT é interpolado no ENV_FILE como $SKILL_HOME/scripts/do-wt.sh — vazio,
# a FASE 3 ficaria com um DO_WT quebrado e morreria com erro confuso. Falha
# cedo, com mensagem clara (exit 2).
[ -n "$SKILL_HOME" ] \
  || die 2 "não consegui resolver SKILL_HOME — scripts/ não está ao lado de do-context.sh (skill incompleta?)"
# SKILL_HOME é fonte INDEPENDENTE (localização do script) — fora do loop de
# validação acima; sem checá-la, uma skill em path com aspa corrompia o
# ENV_FILE e o source 'sucedia' silenciosamente com DO_STATE/DO_WT unset
# (verificado em lab: /tmp/do-probe-skill-o'brien).
case "$SKILL_HOME" in
  *\'*)     die 7 "SKILL_HOME contém aspa simples: $SKILL_HOME" ;;
  *"$(printf '\t')"*) die 7 "SKILL_HOME contém TAB: $SKILL_HOME" ;;
  *$'\n'*)  die 7 "SKILL_HOME contém newline: $SKILL_HOME" ;;
esac

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

# --- (0.9b) DO_MAX_PARALLEL: cap de paralelismo (F3-02) ----------------------
# O orquestrador parseia o prefixo `max-parallel=N` da invocação e exporta
# DO_MAX_PARALLEL antes da FASE 0; ausente → default 20 (CAP protetor — o ponto
# ótimo recomendado é 3-5). Validação: inteiro positivo. Só dígitos, então a
# interpolação no ENV_FILE (aspas simples) é segura.
case "${DO_MAX_PARALLEL:-}" in
  "") DO_MAX_PARALLEL=20 ;;   # ausente → default 20 (CAP protetor)
  *[!0-9]*)
    die 2 "DO_MAX_PARALLEL inválido: '${DO_MAX_PARALLEL}' — precisa ser um inteiro positivo (ex.: max-parallel=20)" ;;
esac
[ "$DO_MAX_PARALLEL" -gt 0 ] 2>/dev/null \
  || die 2 "DO_MAX_PARALLEL inválido: '$DO_MAX_PARALLEL' — precisa ser maior que zero"

# --- (0.9c) PORTÃO DE APROVAÇÃO: aprovação do plano no Plannotator (FASE 2.5) ----
# ATENÇÃO ao vocabulário: neste projeto "gate" significa o trio
# GATE_BUILD/GATE_TEST/GATE_LINT (FASE 1, passo 9). O que a FASE 2.5 faz é um
# PORTÃO DE APROVAÇÃO DO PLANO — nada a ver com build/test/lint. Os nomes aqui
# dizem APPROVAL de propósito, para que ninguém rode a suíte na hora do plano.
# O orquestrador parseia o prefixo `plan=on|off` da invocação (e os gatilhos de
# linguagem natural) e exporta DO_PLAN_APPROVAL antes da FASE 0. Ausente → 0, que
# preserva EXATAMENTE o comportamento autônomo histórico da skill: quem nunca
# pediu plano nunca vê um navegador abrir. O gate é ADITIVO, nunca default.
case "${DO_PLAN_APPROVAL:-}" in
  ""|0|off|no|false) DO_PLAN_APPROVAL=0 ;;
  1|on|yes|true)     DO_PLAN_APPROVAL=1 ;;
  *) die 2 "DO_PLAN_APPROVAL inválido: '${DO_PLAN_APPROVAL}' — use 0/1 (ou plan=off/plan=on na invocação)" ;;
esac
case "${DO_PLAN_MAX_REVISIONS:-}" in
  "") DO_PLAN_MAX_REVISIONS=5 ;;
  *[!0-9]*) die 2 "DO_PLAN_MAX_REVISIONS inválido: '${DO_PLAN_MAX_REVISIONS}' — inteiro positivo" ;;
esac
[ "$DO_PLAN_MAX_REVISIONS" -gt 0 ] 2>/dev/null \
  || die 2 "DO_PLAN_MAX_REVISIONS inválido: '$DO_PLAN_MAX_REVISIONS' — precisa ser maior que zero"
case "${DO_PLAN_TIMEOUT:-}" in
  "") DO_PLAN_TIMEOUT=3600 ;;
  *[!0-9]*) die 2 "DO_PLAN_TIMEOUT inválido: '${DO_PLAN_TIMEOUT}' — segundos, inteiro positivo" ;;
esac
[ "$DO_PLAN_TIMEOUT" -gt 0 ] 2>/dev/null \
  || die 2 "DO_PLAN_TIMEOUT inválido: '$DO_PLAN_TIMEOUT' — precisa ser maior que zero"

PLAN_APPROVAL_DIR="$DO_STATE/plan-approval"
PLAN_DOC="$PLAN_APPROVAL_DIR/PLANO.md"
# O diretório é criado AQUI, e SÓ com o portão ligado. A FASE 2.5 escreve o
# $PLAN_DOC com `cat >` no passo 3, e um redirecionamento não cria diretório:
# sem isto a PRIMEIRA rodada de toda execução com portão morria em ENOENT.
# Condicionado ao portão de propósito: com ele desligado, o $DO_STATE tem que
# ficar EXATAMENTE como sempre foi — quem não pediu plano não ganha nem um
# diretório vazio a mais (asserção DC4 de test-plan-approval.sh).
if [ "$DO_PLAN_APPROVAL" = 1 ]; then
  mkdir -p "$PLAN_APPROVAL_DIR" || die 7 "não consegui criar $PLAN_APPROVAL_DIR"
fi

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
DO_MAX_PARALLEL='$DO_MAX_PARALLEL'
DO_PLAN_APPROVAL='$DO_PLAN_APPROVAL'
DO_PLAN_MAX_REVISIONS='$DO_PLAN_MAX_REVISIONS'
DO_PLAN_TIMEOUT='$DO_PLAN_TIMEOUT'
PLAN_APPROVAL_DIR='$PLAN_APPROVAL_DIR'
PLAN_DOC='$PLAN_DOC'
DO_PLAN_APPROVAL_SH='$SKILL_HOME/scripts/plan-approval.sh'
export MODE BASE_DIR BASE_BRANCH BASE_NAME BASE_SLUG MAIN_ROOT MAIN_ROOT_DESC
export COMMON_DIR PARENT_DIR CHILD_ROOT PLACEMENT RUN_ID BRANCH_NS SKILL_HOME
export DO_HOME DO_STATE PLAN_FILE OWNED DO_WT DO_MAX_PARALLEL
export DO_PLAN_APPROVAL DO_PLAN_MAX_REVISIONS DO_PLAN_TIMEOUT PLAN_APPROVAL_DIR PLAN_DOC DO_PLAN_APPROVAL_SH

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
# grep -vxF (F4-07.13): -vF faria substring — "$BASE_DIR" "main" casaria com um
# path "main2"; -x exige linha IGUAL ao caminho inteiro.
gwt worktree list --porcelain -z 2>/dev/null | tr '\0' '\n' \
  | awk '/^worktree /{print substr($0,10)}' \
  | grep -vxF -e "$BASE_DIR" -e "$CHILD_ROOT" > "$DO_STATE/foreign-worktrees.txt" || true

# --- (0.11) Avisos não-bloqueantes ------------------------------------------
case "$MODE:$BASE_BRANCH" in
  contido:main|contido:master|contido:develop|contido:trunk)
    say "DO_WARN: MODE=contido, mas BASE_BRANCH=$BASE_BRANCH. Os squash-commits irão"
    say "         para ESTE branch (o HEAD desta worktree). Registre no relatório." ;;
esac

say "FASE 0 OK"
say "  MODE          = $MODE"
say "  BASE_DIR      = $BASE_DIR          (RAIZ-DE-MUNDO — fronteira de escrita)"
say "  BASE_BRANCH   = $BASE_BRANCH       (ÚNICO alvo de integração)"
say "  MAIN_ROOT     = $MAIN_ROOT_DESC    (ZONA PROIBIDA)"
say "  CHILD_ROOT    = $CHILD_ROOT ($PLACEMENT)"
say "  BRANCH_NS     = $BRANCH_NS"
say "  SKILL_HOME    = ${SKILL_HOME:-<não resolvido>}  (somente leitura)"
say "  DO_MAX_PARALLEL = $DO_MAX_PARALLEL  (cap de paralelismo por onda — F3-02)"
if [ "$DO_PLAN_APPROVAL" = 1 ]; then
  say "  PLAN_APPROVAL = ON   (FASE 2.5 — plano aprovado pelo usuário no Plannotator;"
  say "                  até $DO_PLAN_MAX_REVISIONS revisões, timeout ${DO_PLAN_TIMEOUT}s por rodada)"
else
  say "  PLAN_APPROVAL = OFF  (autonomia total — nenhuma interação com o usuário)"
fi
say "  worktrees de terceiros: $(wc -l < "$DO_STATE/foreign-worktrees.txt" 2>/dev/null || echo 0) (NÃO tocar)"
say ""
say "Sourceie em TODA chamada Bash posterior:"
printf '%s\n' "$ENV_FILE"
