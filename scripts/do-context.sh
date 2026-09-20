#!/usr/bin/env bash
# =============================================================================
# do-context.sh — FASE 0 do deep-orchestrator-agent-skill: DELIMITA A RAIZ-DE-MUNDO
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
#   do-context.sh [--flags='<tokens>'] [--boundary='<token>'] [--new-run]
#                 [--force-nested] [--quiet]
#
# --flags='<tokens separados por espaço>' (v4.1.0) — UM argv só. O orquestrador
# repassa TODOS os tokens da zona de prefixo da invocação e NÃO julga: este
# script é o ÚNICO validador. Tabela (flag → variável):
#   plan=on|off → DO_PLAN_APPROVAL      max-parallel=N → DO_MAX_PARALLEL
#   surf-sub-agents=N (1..20, default 10) → DO_SURF_SUB_AGENTS
#   wt=<nome>   → DO_WT_ROOT=1 + DO_WT_NAME
#   no-stop     → DO_NO_STOP=1          no-evolve   → DO_EVOLUTION_SURVEY=0
#   no-test     → DO_TEST_MODE=none     only-e2e    → DO_TEST_MODE=e2e
#   do-question → DO_QUESTION=1
# Flag VENCE a variável de ambiente; token ausente → a variável de ambiente
# segue valendo como fallback (DO_X=1 do-context.sh) → senão o default.
# Token desconhecido, valor inválido ou no-test+only-e2e → exit 2.
# `--flags=''` (sem flags) é válido e é a forma canônica da FASE 0.
# `--flags=` aparece UMA vez (todos os tokens no mesmo argv); repetido → exit 2.
# Flag mal escrita NUNCA é consertada em silêncio: `--no-test`, `No-Test`,
# `no_test` e os apelidos (no-tests, e2e-only, mp=8, ask...) saem exit 2 com a
# forma certa na mensagem.
#
# --boundary='<token>' — UM argv só, opcional. É o PRIMEIRO token que ENCERROU a
# zona de prefixo (o 1º que não casou as regex da zona), repassado só quando
# casa `^-{0,2}[A-Za-z0-9][A-Za-z0-9_=-]*$` (sem aspas, `$` ou espaço) e não é o
# `--` literal. O script normaliza (tira `-` iniciais, minúsculas, `_`→`-`) e
# decide: flag/apelido mal escrito → exit 2 com a sugestão; senão IGNORA (é
# texto da tarefa). Vazio, `-` e `--` são ignorados; fora do formato → exit 2.
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
#   2 = flag desconhecida/inválida/mal escrita em --flags, --flags= repetido,
#       --boundary que é flag mal escrita (ou fora do formato), combinação
#       contraditória
#       (no-test + only-e2e), variável DO_* inválida (ex.: DO_MAX_PARALLEL não
#       é inteiro positivo), ou SKILL_HOME não resolvido (skill incompleta —
#       do-wt.sh ficaria inalcançável)
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
#
# As variáveis de FLAG também são exportadas pelo ENV_FILE, e aqui elas são
# ENTRADA (fallback de env): num shell que sourceou o ENV_FILE de outra execução
# (harness com shell persistente, ou `. '<ENV>'; ...; "$DO_CTX" --flags=''` numa
# chamada só), a FASE 0 seguinte herdava no-test/do-question/max-parallel e, vindo
# de um wt-root, ENTRAVA no wt sem ninguém digitar wt= (verificado em lab). A
# assinatura de ENV_FILE sourceado é o trio coerente DO_STATE = DO_HOME/run-RUN_ID
# — o fallback legítimo `DO_X=1 do-context.sh` não o define, nem o re-exec do wt=
# (a 1ª passada não sourceia nada e zera o trio aqui embaixo).
_env_leaked=""
if [ -n "${RUN_ID:-}" ] && [ -n "${DO_STATE:-}" ] \
   && [ "$DO_STATE" = "${DO_HOME:-}/run-$RUN_ID" ]; then
  for _v in DO_PLAN_APPROVAL DO_MAX_PARALLEL DO_SURF_SUB_AGENTS DO_WT_ROOT DO_WT_NAME \
            DO_NO_STOP DO_EVOLUTION_SURVEY DO_TEST_MODE DO_QUESTION; do
    [ -n "${!_v:-}" ] && _env_leaked="$_env_leaked $_v"
  done
  _env_leaked="run-$RUN_ID:$_env_leaked"
  unset DO_PLAN_APPROVAL DO_MAX_PARALLEL DO_SURF_SUB_AGENTS DO_WT_ROOT DO_WT_NAME \
        DO_NO_STOP DO_EVOLUTION_SURVEY DO_TEST_MODE DO_QUESTION 2>/dev/null || true
fi
# CHILD_ROOT/RUN_ID nunca são entrada (nascem em 0.6/0.7): herdados, o rmdir do
# die() alcançaria o CHILD_ROOT vazio de OUTRA run.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES \
      DO_STATE DO_HOME DO_WT CHILD_ROOT RUN_ID 2>/dev/null || true

# Caminho ABSOLUTO deste script, resolvido ANTES de qualquer `cd`: o re-exec do
# wt= (0.3b) roda com o cwd DENTRO da worktree nova — com "$0" relativo
# (`../s/do-context.sh`, `bash do-context.sh`) a worktree nascia e o exec morria
# com rc 126, sem DO_ABORT; num repo que TENHA o mesmo caminho relativo, rodava a
# cópia do script de DENTRO da worktree (outra versão). readlink -f NÃO existe no
# macOS — dirname + pwd -P. (0.8) deriva o SKILL_HOME deste mesmo valor.
_self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || _self_dir=""
_self="$_self_dir/$(basename "${BASH_SOURCE[0]}")"

QUIET=0
NEW_RUN=0
FORCE_NESTED="${DO_FORCE_NESTED:-0}"
# --flags='...' é UM argv (forma `--flags=`, nunca `--flags <valor>`): o laço é
# `for a in "$@"` SEM shift e o re-exec do wt= (0.3b) repassa "$@" intacto — a
# flag sobrevive à re-execução sem array auxiliar (bash 3.2 + set -u).
# --boundary='<token>' segue a MESMA regra de um argv só. Os dois aparecem no
# MÁXIMO uma vez: antes, no `--flags=` repetido o ÚLTIMO vencia e os tokens do
# primeiro sumiam sem exit 2 (`--flags='no-test' --flags='plan=off'` = full).
DO_FLAGS_RAW=""
DO_BOUNDARY_RAW=""
_flags_argc=0
_boundary_argc=0
for a in "$@"; do
  case "$a" in
    --quiet)        QUIET=1 ;;
    --new-run)      NEW_RUN=1 ;;
    --force-nested) FORCE_NESTED=1 ;;
    --flags=*)      DO_FLAGS_RAW="${a#--flags=}"; _flags_argc=$((_flags_argc+1)) ;;
    --boundary=*)   DO_BOUNDARY_RAW="${a#--boundary=}"; _boundary_argc=$((_boundary_argc+1)) ;;
    # O cabeçalho cresce: imprime até o 2º separador `# ====`, não até um nº de linha.
    -h|--help)      awk 'NR>1 { print } NR>2 && /^# ====/ { exit }' "$0"; exit 0 ;;
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
    # ...e o container dele (<repo>-worktrees / .<repo>-do), que o `mkdir -p` de
    # (0.9) pode ter acabado de criar: idem, só se ficou VAZIO.
    rmdir "$(dirname "$CHILD_ROOT")" 2>/dev/null || true
  fi
  printf 'DO_ABORT %s: %s\n' "$1" "$2" >&2
  exit "$1"
}

# --- (0.0) FLAGS: a tabela única (v4.1.0) ------------------------------------
# Por que ARGUMENTO e não `export` feito pelo orquestrador: o shell do harness
# não persiste entre chamadas Bash, e `VAR=1 DO_CTX=$(...)` (atribuição antes de
# atribuição) NÃO exporta — a flag evaporava e a FASE 0 imprimia o default sem
# ninguém conferir (verificado em lab). Aqui a flag viaja no MESMO argv do
# script, é validada por ELE (o orquestrador não julga token) e é re-exportada,
# de modo que o re-exec do wt= a enxerga por argv E por env.
# Precedência por variável: token em --flags > variável de ambiente > default.
# Vem ANTES do reuso (0.2), que já lê DO_PLAN_APPROVAL/DO_NO_STOP/... para o
# anti-stale. Nada foi criado até aqui: die 2 não deixa resíduo.
_flags_seen=" "
_flag_set() {  # _flag_set <VAR> <valor> <token>
  case "$_flags_seen" in
    *" $1=$2 "*) ;;                       # token repetido com o MESMO valor: inofensivo
    *" $1="*)
      [ "$1" = DO_TEST_MODE ] && die 2 "no-test e only-e2e são mutuamente exclusivos: no-test = NENHUM teste novo; only-e2e = SÓ testes e2e novos. Reinvoque com UM deles."
      die 2 "flags contraditórias: '$3' colide com outro token que já definiu $1. Reinvoque com UM deles." ;;
  esac
  _flags_seen="$_flags_seen$1=$2 "
  printf -v "$1" '%s' "$2"
  # shellcheck disable=SC2163
  export "$1"
}
_flag_hint() { die 2 "flag desconhecida em --flags: '$1' — quis dizer '$2'? (se era texto da tarefa, separe com um '--' literal antes dele)"; }
# _flag_norm <token>: forma de COMPARAÇÃO — tira os `-` iniciais, minúsculas e
# `_`→`-` (portável no bash 3.2: sem ${x,,}). Só para JULGAR o token: o valor
# normalizado nunca é aplicado (a regra é nunca consertar em silêncio).
_flag_norm() {
  local t="$1"
  while [ "${t#-}" != "$t" ]; do t="${t#-}"; done
  printf '%s' "$t" | LC_ALL=C tr 'A-Z_' 'a-z-'
}
# _flag_alias <token-normalizado>: a ÚNICA lista de apelidos (DETERMINÍSTICOS,
# sem fuzzy) — imprime a flag canônica, ou nada. Um typo nunca vira texto da
# tarefa em silêncio: inverteria o pedido do usuário sem ninguém notar.
# (`no_test`, `only_e2e`, `--no-test`, `No-Test` não precisam estar aqui: a
# normalização os leva à flag canônica.)
_flag_alias() {
  case "$1" in
    no-tests|notest|skip-tests) printf '%s' no-test ;;
    e2e-only|e2e)               printf '%s' only-e2e ;;
    mp=*)                       printf '%s' "max-parallel=${1#mp=}" ;;
    ask|question|do-questions)  printf '%s' do-question ;;
  esac
}
# _flag_suggest <token-cru>: a forma CERTA quando o token, normalizado, é uma flag
# da tabela ou um apelido; vazio = não parece flag. Serve ao laço do --flags
# (token que não casou a tabela) e ao --boundary.
_flag_suggest() {
  local n; n=$(_flag_norm "$1")
  case "$n" in
    plan=on|plan=off|no-stop|no-evolve|no-test|only-e2e|do-question) printf '%s' "$n" ;;
    plan=*)                                  printf '%s' 'plan=on|off' ;;
    max-parallel=?*|surf-sub-agents=?*|wt=?*) printf '%s' "$n" ;;
    *) _flag_alias "$n" ;;
  esac
}
# (CTX-04) os dois argv aparecem no máximo UMA vez. Nada foi criado: sem resíduo.
[ "$_flags_argc" -le 1 ] \
  || die 2 "--flags= repetido ($_flags_argc vezes) — é UM argv só, com TODOS os tokens separados por espaço (ex.: --flags='no-test plan=off'). Reinvoque com um único --flags=."
[ "$_boundary_argc" -le 1 ] \
  || die 2 "--boundary= repetido ($_boundary_argc vezes) — é UM argv só: o PRIMEIRO token que encerrou a zona de prefixo."
set -f   # sem glob: um token '*' não pode virar lista de arquivos
for _t in $DO_FLAGS_RAW; do
  case "$_t" in
    --)        break ;;   # fim da zona de prefixo: o que vem depois é texto da tarefa, não se julga
    plan=on)   _flag_set DO_PLAN_APPROVAL 1 "$_t" ;;
    plan=off)  _flag_set DO_PLAN_APPROVAL 0 "$_t" ;;
    plan=*)    die 2 "flag inválida: '$_t' — use plan=on ou plan=off" ;;
    max-parallel=*)
      case "${_t#max-parallel=}" in
        ""|*[!0-9]*) die 2 "flag inválida: '$_t' — max-parallel=N exige N inteiro positivo (ex.: max-parallel=50)" ;;
      esac
      [ "${_t#max-parallel=}" -gt 0 ] 2>/dev/null \
        || die 2 "flag inválida: '$_t' — max-parallel=N exige N maior que zero"
      _flag_set DO_MAX_PARALLEL "${_t#max-parallel=}" "$_t" ;;
    surf-sub-agents=*)
      case "${_t#surf-sub-agents=}" in
        ""|*[!0-9]*) die 2 "flag inválida: '$_t' — surf-sub-agents=N exige N inteiro de 1 a 20" ;;
      esac
      _flag_set DO_SURF_SUB_AGENTS "${_t#surf-sub-agents=}" "$_t" ;;
    # `wt=on` é resolvido pelo ORQUESTRADOR (só ele vê o texto da tarefa): chegar
    # cru aqui criaria uma worktree chamada "on" em silêncio.
    wt=|wt=on) die 2 "flag inválida: '$_t' — o orquestrador deve trocar wt=on por wt=<slug-kebab-case> ANTES de chamar a FASE 0" ;;
    wt=*)        _flag_set DO_WT_NAME "${_t#wt=}" "$_t"; DO_WT_ROOT=1; export DO_WT_ROOT ;;
    no-stop)     _flag_set DO_NO_STOP 1 "$_t" ;;
    no-evolve)   _flag_set DO_EVOLUTION_SURVEY 0 "$_t" ;;
    no-test)     _flag_set DO_TEST_MODE none "$_t" ;;
    only-e2e)    _flag_set DO_TEST_MODE e2e "$_t" ;;
    do-question) _flag_set DO_QUESTION 1 "$_t" ;;
    # Não casou a tabela: apelido ou flag mal escrita (`--no-test`, `No-Test`,
    # `no_test`, `e2e-only`...) sai com a FORMA CERTA na mensagem — nunca é
    # consertado em silêncio, nem vira texto da tarefa.
    *) _sug=$(_flag_suggest "$_t")
       [ -z "$_sug" ] || _flag_hint "$_t" "$_sug"
       die 2 "flag desconhecida em --flags: '$_t' — válidas: plan=on|off max-parallel=N surf-sub-agents=N wt=<nome> no-stop no-evolve no-test only-e2e do-question (se era texto da tarefa, separe com um '--' literal antes dele)" ;;
  esac
done
set +f

# (0.0a) --boundary: o token de FRONTEIRA (FT-01). A zona de prefixo é decidida
# por regex no SKILL.md e 8 dos 11 apelidos (e `--no-test`, `No-Test`) NÃO casam
# a regex: o orquestrador obediente nunca os repassava em --flags, e
# `e2e-only no-stop <tarefa>` virava TEST_MODE=full + NO_STOP=OFF sem erro — a
# inversão silenciosa que o exit 2 existe para impedir. Aqui o script julga
# TAMBÉM o 1º token que encerrou a zona; o orquestrador continua sem julgar.
# Custo aceito: tarefa cujo 1º token seja literalmente `ask`, `question` ou `e2e`
# sai exit 2 — falha barulhenta, com o escape `--` escrito na mensagem.
case "$DO_BOUNDARY_RAW" in
  ""|-|--) ;;   # ausente, ou só traços (separador/pontuação): texto da tarefa
  *)
    case "$DO_BOUNDARY_RAW" in
      *[[:space:]]*) _b_ok=1 ;;
      *) printf '%s' "$DO_BOUNDARY_RAW" | LC_ALL=C grep -Eq '^-{0,2}[A-Za-z0-9][A-Za-z0-9_=-]*$'; _b_ok=$? ;;
    esac
    [ "$_b_ok" = 0 ] \
      || die 2 "--boundary fora do formato: só repasse o token de fronteira quando ele casar ^-{0,2}[A-Za-z0-9][A-Za-z0-9_=-]*\$ (sem aspas, \$, espaço ou pontuação) — senão OMITA o --boundary (é texto da tarefa)."
    _sug=$(_flag_suggest "$DO_BOUNDARY_RAW")
    if [ -n "$_sug" ] && [ "$_sug" = "$DO_BOUNDARY_RAW" ]; then
      die 2 "o 1º token depois das flags ('$DO_BOUNDARY_RAW') É uma flag válida e ficou FORA de --flags — repasse-o dentro de --flags='...' (se era texto da tarefa, separe com um '--' literal antes dele)"
    elif [ -n "$_sug" ]; then
      die 2 "o 1º token depois das flags ('$DO_BOUNDARY_RAW') parece flag mal escrita — quis dizer '$_sug'? (se era texto da tarefa, separe com um '--' literal antes dele)"
    fi ;;   # senão: texto da tarefa — ignorado
esac

# (0.0b) Validação das variáveis NOVAS — vale para flag E para env (fallback).
# Cedo de propósito: o anti-stale (0.2) compara o valor JÁ normalizado.
# DO_TEST_MODE: full (default) | none (no-test: não CRIA testes; gate e suíte
# existente continuam) | e2e (only-e2e: Testing Subwaves só criam e2e).
case "${DO_TEST_MODE:-}" in
  ""|full) DO_TEST_MODE=full ;;
  none|e2e) ;;
  *) die 2 "DO_TEST_MODE inválido: '${DO_TEST_MODE}' — use full|none|e2e (ou no-test / only-e2e na invocação)" ;;
esac
# DO_QUESTION: 1 = o orquestrador PODE perguntar ao usuário (flag do-question).
# A pergunta da chave Brave (protocolo PESQUISA-FALHOU) NÃO depende disto.
case "${DO_QUESTION:-}" in
  ""|0|off|no|false) DO_QUESTION=0 ;;
  1|on|yes|true)     DO_QUESTION=1 ;;
  *) die 2 "DO_QUESTION inválido: '${DO_QUESTION}' — use 0/1 (ou do-question na invocação)" ;;
esac
# DO_SURF_SUB_AGENTS: teto de sub-agentes por chamada surf (--sub-agents=N).
# Antes era "valide você mesmo" no prompt e NUNCA chegava ao ENV_FILE: expandia
# vazio, `--sub-agents=` saía 2 no surf e a pesquisa morria sem virar exit 78.
case "${DO_SURF_SUB_AGENTS:-}" in
  "") DO_SURF_SUB_AGENTS=10 ;;
  *[!0-9]*) die 2 "DO_SURF_SUB_AGENTS inválido: '${DO_SURF_SUB_AGENTS}' — inteiro de 1 a 20 (ex.: surf-sub-agents=10)" ;;
esac
{ [ "$DO_SURF_SUB_AGENTS" -ge 1 ] && [ "$DO_SURF_SUB_AGENTS" -le 20 ]; } 2>/dev/null \
  || die 2 "DO_SURF_SUB_AGENTS fora da faixa: '$DO_SURF_SUB_AGENTS' — inteiro de 1 a 20"
DO_SURF_SUB_AGENTS=$((10#$DO_SURF_SUB_AGENTS))   # "07" -> 7 (sem octal)
# DO_WT_ROOT: só "1" liga o bloco (0.3b); lixo no env caía em MODE=normal calado.
case "${DO_WT_ROOT:-}" in
  ""|0|off|no|false) DO_WT_ROOT=0 ;;
  1|on|yes|true)     DO_WT_ROOT=1 ;;
  *) die 2 "DO_WT_ROOT inválido: '${DO_WT_ROOT}' — use 0/1 (ou wt=<nome> na invocação)" ;;
esac
export DO_TEST_MODE DO_QUESTION DO_SURF_SUB_AGENTS DO_WT_ROOT

# Aviso do vazamento barrado no topo — só quando havia o que barrar.
case "$_env_leaked" in
  *": "*)
    say "DO_WARN: este shell tinha o ENV_FILE de OUTRA execução sourceado (${_env_leaked%%:*}). As variáveis"
    say "         de flag herdadas dele foram IGNORADAS (${_env_leaked#*: }) — nesta FASE 0 só vale o --flags='...'."
    say "" ;;
esac

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
#
# wt= a partir do checkout PRINCIPAL: a raiz-de-mundo será a worktree (0.3b), não
# este checkout — avaliar o reuso aqui sequestraria `wt=<nome>` para uma run
# pendente do principal. A re-execução roda este bloco de novo, já DENTRO da
# worktree (é lá que vive o estado de uma run wt= interrompida). Após o
# `cd "$BASE_DIR"`, --git-dir == --git-common-dir só na árvore principal.
_defer_reuse=0
if [ "$DO_WT_ROOT" = 1 ] && [ "${DO_WT_ROOT_ENTERED:-0}" != 1 ] \
   && [ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then
  _defer_reuse=1
fi
_reuse_env=""     # env da execução reaproveitada (vazio = execução nova)
_stale_envs=""    # envs preteridos por DO_STALE (um por linha) — viram DO_ORPHAN_RUNS
_stale() { _stale_envs="$_stale_envs$prev
"; }
if [ "$NEW_RUN" = 0 ] && [ "$_defer_reuse" = 0 ]; then
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
      _stale; continue
    fi
    # Revalidação anti-stale do PORTÃO (FASE 2.5): o ENV_FILE é o ÚNICO
    # carregador da decisão do passo 2 da FASE 0 — o shell do harness não persiste entre
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
      _stale; continue
    fi
    # Revalidação anti-stale do NO_STOP: mesma classe de inversão silenciosa do
    # portão — reaproveitar um env cujo DO_NO_STOP diverge do que ESTA invocação
    # resolveu liga/desliga o teto de 10 ondas sem o usuário pedir, nos dois
    # sentidos. Um env anterior à introdução da flag nem tem a chave — também
    # diverge, e também precisa de execução nova.
    _want_nostop="${DO_NO_STOP:-0}"
    case "$_want_nostop" in 1|on|yes|true) _want_nostop=1 ;; *) _want_nostop=0 ;; esac
    if grep -q '^DO_NO_STOP=' "$prev" 2>/dev/null; then
      _reuse_nostop=$(sed -n "s/^DO_NO_STOP='\([^']*\)'.*/\1/p" "$prev")
    else
      _reuse_nostop="<ausente>"
    fi
    if [ "$_reuse_nostop" != "$_want_nostop" ]; then
      say "DO_STALE: a execução em andamento tem NO_STOP='$_reuse_nostop' e esta invocação"
      say "          resolveu '$_want_nostop' — reaproveitar inverteria a flag no-stop em silêncio."
      say "          Criando execução NOVA (equivalente a --new-run)."
      say ""
      _stale; continue
    fi
    # Revalidação anti-stale do QUESTIONÁRIO DE EVOLUÇÃO (v3.8.0): mesma classe
    # das anteriores — reaproveitar um env cujo DO_EVOLUTION_SURVEY diverge do
    # que ESTA invocação resolveu ligaria/desligaria a pergunta de evolução pós-execução
    # sem o usuário pedir, nos dois sentidos. Um env anterior à v3.8.0 nem tem a
    # chave — também diverge, e também precisa de execução nova.
    _want_survey="${DO_EVOLUTION_SURVEY:-1}"
    case "$_want_survey" in 1|on|yes|true) _want_survey=1 ;; *) _want_survey=0 ;; esac
    if grep -q '^DO_EVOLUTION_SURVEY=' "$prev" 2>/dev/null; then
      _reuse_survey=$(sed -n "s/^DO_EVOLUTION_SURVEY='\([^']*\)'.*/\1/p" "$prev")
    else
      _reuse_survey="<ausente>"
    fi
    if [ "$_reuse_survey" != "$_want_survey" ]; then
      say "DO_STALE: a execução em andamento tem EVOLUTION_SURVEY='$_reuse_survey' e esta invocação"
      say "          resolveu '$_want_survey' — reaproveitar inverteria a decisão da pergunta de evolução em silêncio."
      say "          Criando execução NOVA (equivalente a --new-run)."
      say ""
      _stale; continue
    fi
    # Revalidação anti-stale do TEST_MODE e do QUESTION (v4.1.0): mesma classe —
    # reaproveitar um env com outro DO_TEST_MODE faria `no-test` CRIAR testes (ou
    # `only-e2e` criar unitários) em silêncio, e a guarda do `do-wt.sh new` ficaria
    # inerte; com outro DO_QUESTION, o orquestrador perguntaria (ou calaria) sem o
    # usuário pedir. Diferente das chaves acima, a chave AUSENTE num env anterior
    # à v4.1.0 equivale ao DEFAULT (full / 0) — era o único comportamento que
    # existia —, então uma run antiga segue reaproveitável por quem não passou flag.
    _reuse_testmode=$(sed -n "s/^DO_TEST_MODE='\([^']*\)'.*/\1/p" "$prev")
    [ -n "$_reuse_testmode" ] || _reuse_testmode=full
    if [ "$_reuse_testmode" != "$DO_TEST_MODE" ]; then
      say "DO_STALE: a execução em andamento tem TEST_MODE='$_reuse_testmode' e esta invocação"
      say "          resolveu '$DO_TEST_MODE' — reaproveitar inverteria no-test/only-e2e em silêncio."
      say "          Criando execução NOVA (equivalente a --new-run)."
      say ""
      _stale; continue
    fi
    _reuse_question=$(sed -n "s/^DO_QUESTION='\([^']*\)'.*/\1/p" "$prev")
    [ -n "$_reuse_question" ] || _reuse_question=0
    if [ "$_reuse_question" != "$DO_QUESTION" ]; then
      say "DO_STALE: a execução em andamento tem QUESTION='$_reuse_question' e esta invocação"
      say "          resolveu '$DO_QUESTION' — reaproveitar inverteria a flag do-question em silêncio."
      say "          Criando execução NOVA (equivalente a --new-run)."
      say ""
      _stale; continue
    fi
    say "DO_REUSE: execução em andamento encontrada ($pend sub-tarefa(s) pendentes)."
    say "          Reaproveitando o estado dela (PLAN_APPROVAL=$_reuse_gate, NO_STOP=$_reuse_nostop,"
    say "          EVOLUTION_SURVEY=$_reuse_survey, TEST_MODE=$_reuse_testmode, QUESTION=$_reuse_question)."
    say "          Use --new-run para forçar uma nova."
    say ""
    _reuse_env="$prev"
    break
  done
fi

# --- (0.2b) DO_ORPHAN_RUNS: nunca abandonar uma run em silêncio ---------------
# Toda run anterior com linha VIVA (coluna 9 != REMOVED — BLOCKED/ORPHANED
# INCLUSIVE: a worktree delas segue travada no disco) que NÃO será reusada fica
# fora do owned.tsv novo, e a limpeza só aceita alvos do PRÓPRIO owned.tsv (R8d):
# sem aviso, worktree + branch + lock vazam para sempre (travada, nem o gc do
# git poda). Causas: DO_STALE, --new-run, run só com BLOCKED/ORPHANED, ou run
# preterida por outra mais antiga. Este script NÃO purga sozinho (pode ser a run
# de uma sessão concorrente viva — A8/A12): imprime, por run, o comando EXATO,
# e a FASE 0 do SKILL.md manda rodá-los antes de prosseguir. A contagem é por
# awk na coluna 9 (o ledger tem 11 colunas; status NÃO é a última — nunca `$`).
#
# wt= a partir do checkout PRINCIPAL (_defer_reuse=1): só o REUSO é adiado para a
# re-execução — o INVENTÁRIO roda AQUI, sobre o .deep-orchestrator do principal,
# que a re-execução (cwd dentro do wt) nunca mais enxerga. Sem isto, uma run
# interrompida do principal sumia de TODA invocação com wt= (nem DO_REUSE nem
# DO_ORPHAN_RUNS) e as filhas dela viravam "worktrees de terceiros" no wt
# (verificado em lab). O bloco é impresso imediatamente ANTES do re-exec (0.3b).
ORPHAN_BLOCK=""
ORPHAN_COUNT=0
for prev in "$BASE_DIR"/.deep-orchestrator/run-*/env; do
  [ -f "$prev" ] || continue
  [ "$prev" = "$_reuse_env" ] && continue
  _live=$(awk -F'\t' 'NR>1 && $9!="REMOVED" {c++} END{print c+0}' \
            "$(dirname "$prev")/owned.tsv" 2>/dev/null || echo 0)
  [ "$_live" -gt 0 ] || continue
  _pend=$(awk -F'\t' 'NR>1 && $9!="REMOVED" && $9!="BLOCKED" && $9!="ORPHANED" {c++} END{print c+0}' \
            "$(dirname "$prev")/owned.tsv" 2>/dev/null || echo 0)
  case "$_stale_envs" in
    *"$prev
"*) _why="DO_STALE" ;;
    *) if   [ "$_defer_reuse" = 1 ]; then _why="wt="
       elif [ "$NEW_RUN" = 1 ];  then _why="--new-run"
       elif [ "$_pend" = 0 ];    then _why="so-BLOCKED/ORPHANED"
       else                           _why="preterida-por-run-mais-antiga"; fi ;;
  esac
  _rid=$(basename "$(dirname "$prev")"); _rid=${_rid#run-}
  ORPHAN_COUNT=$((ORPHAN_COUNT+1))
  ORPHAN_BLOCK="$ORPHAN_BLOCK  run=$_rid vivas=$_live motivo=$_why
    ( . '$prev'; \"\$DO_WT\" purge )
"
done
say_orphans() {
  [ "$ORPHAN_COUNT" -gt 0 ] || return 0
  say "DO_ORPHAN_RUNS: $ORPHAN_COUNT execução(ões) anterior(es) com worktrees VIVAS que NÃO serão reusadas."
  say "  Rode CADA comando abaixo (uma chamada Bash por comando) ANTES de prosseguir — o"
  say "  owned.tsv delas é a ÚNICA alça de limpeza: NUNCA apague run-* com linhas vivas."
  say "  Branches vão para refs/do-archive/<run>/ (nada se perde). Se for a run de OUTRA"
  say "  sessão ainda viva nesta pasta, NÃO purgue: registre no relatório."
  if [ "$_defer_reuse" = 1 ]; then
    say "  motivo=wt=: a run é do checkout PRINCIPAL ($BASE_DIR), que o wt= deixa para trás."
  fi
  [ "$QUIET" = 1 ] || printf '%s' "$ORPHAN_BLOCK"
  say ""
}

# (0.2c) DO_REUSE de env ANTERIOR à v4.1.0: o anti-stale trata a chave ausente como
# default e REUSA — mas o arquivo seguia SEM as chaves novas, e todo
# `. '<ENV_FILE>'; "$DO_SURF_GATE"` saía "command not found" (rc 127, sem linha
# SURF_GATE=): o portão de pesquisa e a pergunta da chave Brave nunca disparavam;
# `--sub-agents=$DO_SURF_SUB_AGENTS` expandia vazio e, num wt-root, a R8j voltava
# a depender da memória do turno (verificado em lab). Completa SÓ as chaves que
# faltam, por anexação (nada do env antigo é reescrito). DO_WT_ROOT/NAME vêm do
# FATO gravado nele (mesma regra de 0.9f); DO_SURF_GATE aponta para ESTA skill.
_env_complete() {  # _env_complete <env>
  local _e="$1" _add="" _md _bb _r=0 _n=""
  _md=$(sed -n "s/^MODE='\([^']*\)'.*/\1/p" "$_e")
  _bb=$(sed -n "s/^BASE_BRANCH='\([^']*\)'.*/\1/p" "$_e")
  case "$_md:$_bb" in
    contido:do/wt/*/*) ;;
    contido:do/wt/?*)  _r=1; _n="${_bb#do/wt/}" ;;
  esac
  grep -q '^DO_TEST_MODE=' "$_e"       || _add="${_add}DO_TEST_MODE='$_reuse_testmode'
"
  grep -q '^DO_QUESTION=' "$_e"        || _add="${_add}DO_QUESTION='$_reuse_question'
"
  grep -q '^DO_SURF_SUB_AGENTS=' "$_e" || _add="${_add}DO_SURF_SUB_AGENTS='$DO_SURF_SUB_AGENTS'
"
  grep -q '^DO_WT_ROOT=' "$_e"         || _add="${_add}DO_WT_ROOT='$_r'
"
  grep -q '^DO_WT_NAME=' "$_e"         || _add="${_add}DO_WT_NAME='$_n'
"
  if ! grep -q '^DO_SURF_GATE=' "$_e"; then
    case "$_self_dir" in
      ""|*\'*|*"$(printf '\t')"*|*$'\n'*)
        say "DO_WARN: não consegui resolver um caminho seguro para surf-gate.sh — DO_SURF_GATE ficou de fora do env reaproveitado." ;;
      *) _add="${_add}DO_SURF_GATE='$_self_dir/surf-gate.sh'
" ;;
    esac
  fi
  [ -n "$_add" ] || return 0
  # (as chaves entre { }: o erro de um `>>` recusado é do SHELL, não do printf)
  if { printf '\n# (v4.1.0) chaves que faltavam neste env (gerado por versão anterior) — completadas pelo DO_REUSE\n%sexport DO_TEST_MODE DO_QUESTION DO_SURF_SUB_AGENTS DO_WT_ROOT DO_WT_NAME DO_SURF_GATE\n' \
         "$_add" >> "$_e"; } 2>/dev/null; then
    say "DO_REUSE: env anterior à v4.1.0 — completei as chaves que faltavam ($(printf '%s' "$_add" | sed -n "s/^\([A-Z_]*\)=.*/\1/p" | tr '\n' ' ' | sed 's/ $//'))."
    say ""
  else
    say "DO_WARN: não consegui completar $_e (sem permissão de escrita?) — DO_SURF_GATE e as chaves da v4.1.0 podem faltar ao sourcear."
  fi
}

if [ -n "$_reuse_env" ]; then
  _env_complete "$_reuse_env"
  say_orphans
  printf '%s\n' "$_reuse_env"
  exit 0
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
#   • cwd é o checkout PRINCIPAL e DO_WT_ROOT=1: criamos — ou REENTRAMOS, se
#     `<repo>.worktrees/<nome>` já é o wt-root deste repo no branch do/wt/<nome> —
#     a worktree irmã (o nome só é deduplicado contra o que existe e NÃO é isso),
#     ENTRA nela e RE-EXECUTAMOS este script com o cwd dentro dela, repassando
#     "$@" (as --flags sobrevivem). A re-execução cai no mesmo MODE=contido de
#     sempre — zero lógica duplicada. O sentinel evita loop.
#
# O wt-root é PERSISTENTE: ao contrário das filhas efêmeras de CHILD_ROOT (que
# morrem na onda), ele sobrevive entre execuções — o par pasta/branch se reusa.
if [ "$DO_WT_ROOT" = 1 ] && [ "$MODE" = normal ] && [ "${DO_WT_ROOT_ENTERED:-0}" != 1 ]; then
  # Tudo o que ABORTA a re-execução é validado AQUI, antes de criar worktree/branch:
  # a FASE 0 abortada dizia "nada foi criado" e deixava um wt + do/wt/<nome> que
  # nenhum owned.tsv conhece (nem purge nem assert-clean alcançam). Repo sem commits
  # saía 7 com o erro cru do git ("not a valid object name: 'HEAD'") em vez do 5
  # acionável, e ainda deixava <repo>.worktrees/ vazio para trás (verificado em lab).
  git rev-parse --verify --quiet HEAD >/dev/null \
    || die 5 "repositório sem commits.
  'git worktree add' não consegue derivar o wt-root (wt=) de um HEAD inexistente.
  Faça o commit inicial e reinvoque. Nada foi criado."
  [ -n "$_self_dir" ] && [ -f "$_self" ] \
    || die 2 "não consegui resolver o caminho absoluto deste script (${BASH_SOURCE[0]}) para a re-execução do wt= — invoque pelo caminho absoluto. Nada foi criado."
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
  # REENTRADA (v4.1.0): o wt-root é PERSISTENTE — se <repo>.worktrees/<nome> JÁ É
  # worktree DESTE repo no branch do/wt/<nome>, a 2ª invocação ENTRA nela. Antes,
  # QUALQUER path existente ganhava -2: `wt=feat` re-invocado nascia em feat-2 a
  # partir do HEAD de origem, SEM o trabalho da 1ª execução (que por R8j nunca é
  # mergeado de volta), e uma run interrompida dentro de `feat` nunca mais era
  # alcançada pelo DO_REUSE (verificado em lab). Prova de identidade, toda por
  # caminho CANÔNICO e avaliada DENTRO do candidato (um repo alheio responde
  # `.git` RELATIVO — resolvido no nosso cwd viraria falso positivo): não é
  # symlink, é o toplevel dele mesmo, mesmo git-common-dir, branch do/wt/<nome>.
  _wt_is_ours() {  # _wt_is_ours <path> <nome>
    [ -d "$1" ] && [ ! -L "$1" ] || return 1
    local _real _top _cdir
    _real=$(cd "$1" 2>/dev/null && pwd -P) || return 1
    _top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
    [ "$_top" = "$_real" ] || return 1
    _cdir=$(cd "$1" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
    [ "$_cdir" = "$(cd "$COMMON_DIR" && pwd -P)" ] || return 1
    [ "$(git -C "$1" branch --show-current 2>/dev/null)" = "do/wt/$2" ]
  }
  # Dedupe SÓ contra o que existe e NÃO é o nosso wt-root (diretório estranho,
  # outro repo, worktree deste repo em OUTRO branch): ganha -2, -3... até um nome
  # livre — ou até um <nome>-N que seja o NOSSO wt-root (nasceu de um dedupe
  # anterior), no qual também se reentra. Mesmo pedido => mesma worktree.
  _wt_reenter=0
  if [ -e "$_wt_base/$_wt_name" ] || [ -L "$_wt_base/$_wt_name" ]; then
    if _wt_is_ours "$_wt_base/$_wt_name" "$_wt_name"; then
      _wt_reenter=1
    else
      say "DO_WT_ROOT: '$(basename "$BASE_DIR").worktrees/$_wt_name' já existe e NÃO é o wt-root deste repo no branch do/wt/$_wt_name — procurando nome livre."
      _n=2
      while { [ -e "$_wt_base/$_wt_name-$_n" ] || [ -L "$_wt_base/$_wt_name-$_n" ]; } \
            && ! _wt_is_ours "$_wt_base/$_wt_name-$_n" "$_wt_name-$_n" \
            && [ "$_n" -lt 1000 ]; do _n=$((_n+1)); done
      [ "$_n" -lt 1000 ] || die 7 "não achei nome livre sob $_wt_base para $_wt_name"
      _wt_name="$_wt_name-$_n"
      say "DO_WT_ROOT: nome deduplicado -> $_wt_name"
      _wt_is_ours "$_wt_base/$_wt_name" "$_wt_name" && _wt_reenter=1
    fi
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

  [ "$_wt_reenter" = 0 ] && [ -e "$_wt_path" ] \
    && die 7 "$_wt_path existe mas não é uma worktree git (sem .git arquivo) — recuso"
  # Branch determinístico e reusável: do/wt/<nome>. Se o ref já existe (worktree
  # anterior removida/feita prune mas branch preservado), REUSA-o via `add <path>
  # <branch>` (sem -b — nunca -B, que resetaria silenciosamente o branch da run
  # anterior); senão CRIAmos com -b a partir do HEAD.
  _wt_branch="do/wt/$_wt_name"
  git check-ref-format --branch "$_wt_branch" >/dev/null 2>&1 \
    || die 7 "branch inválido: $_wt_branch"
  # Mesmas validações de (0.6)/(0.8), ANTECIPADAS: na re-execução BASE_DIR=$_wt_path,
  # PARENT_DIR=$_wt_base, MAIN_ROOT=este checkout, COMMON_DIR o mesmo, e SKILL_HOME
  # deriva de $_self_dir. Aspa simples/TAB/newline em qualquer um abortaria (exit 7)
  # só DEPOIS de a worktree e o branch existirem.
  for _v in _wt_path BASE_DIR COMMON_DIR _self_dir; do
    _val=${!_v}
    case "$_val" in
      *\'*)     die 7 "o wt-root não pode nascer: path com aspa simples ($_val). Nada foi criado." ;;
      *"$(printf '\t')"*) die 7 "o wt-root não pode nascer: path com TAB ($_val). Nada foi criado." ;;
      *$'\n'*)  die 7 "o wt-root não pode nascer: path com newline ($_val). Nada foi criado." ;;
    esac
  done
  # Idem para a colisão de PREFIXO do namespace (0.6, exit 9): dentro do wt o
  # namespace das filhas será do/<nome>/<run> (o slug do basename É o nome).
  if [ "$_wt_reenter" = 0 ]; then
    for _ns in do "do/$_wt_name"; do
      git show-ref --verify --quiet "refs/heads/$_ns" \
        && die 9 "colisão de namespace: já existe o branch refs/heads/$_ns, prefixo do namespace que o wt-root '$_wt_name' usaria (do/$_wt_name/<run>). Nada foi criado."
    done
  fi
  _wt_base_new=0; [ -d "$_wt_base" ] || _wt_base_new=1
  mkdir -p "$_wt_base" || die 7 "não consegui criar $_wt_base"
  # Falha ao criar a worktree: o container que ACABOU de nascer não fica para trás
  # (rmdir só remove diretório VAZIO — nunca toca em wt-root de outra execução).
  _wt_undo_base() { [ "$_wt_base_new" = 1 ] && rmdir "$_wt_base" 2>/dev/null; return 0; }
  if [ "$_wt_reenter" = 1 ]; then
    # Nunca merge/rebase automático do branch de origem aqui dentro: só entra.
    say "DO_WT_ROOT: REENTRANDO $_wt_path (branch $_wt_branch, HEAD $(git -C "$_wt_path" rev-parse --short HEAD 2>/dev/null || echo '?')) — wt-root persistente, nada recriado"
  elif git show-ref --verify --quiet "refs/heads/$_wt_branch"; then
    git worktree add -q "$_wt_path" "$_wt_branch" \
      || { _wt_undo_base; die 7 "worktree em '$_wt_path' do branch '$_wt_branch' falhou — provável: o branch está
  registrado em OUTRA worktree ('git worktree list') ou a entrada anterior virou
  prunable porque o diretório sumiu sem 'git worktree remove' — rode 'git worktree
  prune' no repo principal ($BASE_DIR) e re-invoque"; }
    say "DO_WT_ROOT: worktree $_wt_path no branch existente $_wt_branch (reusado)"
  else
    git worktree add -q -b "$_wt_branch" "$_wt_path" HEAD \
      || { _wt_undo_base; die 7 "não consegui criar a worktree $_wt_path (branch $_wt_branch)"; }
    say "DO_WT_ROOT: worktree criada em $_wt_path (branch $_wt_branch)"
  fi

  # ENTRA na worktree e RE-RODA este script FASE 0 com o cwd dentro dela. A partir
  # daqui MODE=contido e toda a contenção EXISTENTE vale — nada duplicado.
  cd "$_wt_path" || die 7 "não consegui entrar em $_wt_path"
  DO_WT_ROOT_ENTERED=1
  # O nome JÁ deduplicado viaja por env; o ENV_FILE o deriva do BASE_BRANCH (0.9).
  DO_WT_NAME="$_wt_name"
  export DO_WT_ROOT_ENTERED DO_WT_NAME
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true
  # As runs vivas do checkout PRINCIPAL são anunciadas AGORA (0.2b): a re-execução
  # só enxerga <wt>/.deep-orchestrator. A última linha da saída continua sendo o
  # ENV_FILE impresso por ela.
  say_orphans
  # Re-exec pelo caminho ABSOLUTO resolvido no topo (nunca "$0", que é relativo ao
  # cwd ANTIGO), no MESMO bash desta passada — funciona com `bash do-context.sh` e
  # com arquivo sem +x. `exec` que falha mata o shell não-interativo sem passar
  # pelo `||`: a existência de $_self já foi validada antes de criar a worktree.
  _bash="${BASH:-/bin/bash}"; [ -x "$_bash" ] || _bash=/bin/bash
  exec "$_bash" "$_self" "$@"
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
[ -n "$BASE_BRANCH" ] || die 4 "HEAD destacado — o deep-orchestrator-agent-skill exige um branch de integração.
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
# fallback portável: dirname + pwd -P. $_self_dir foi resolvido no TOPO, antes do
# `cd "$BASE_DIR"` de (0.1): aqui um caminho relativo já apontaria para outro lugar.
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

# --- (0.8b) PREFS DE EVOLUÇÃO (v3.8.0): memória consultiva gitignored -------
# O projeto REAL guarda as preferências em .deep-orchestrator-preferences/.
# Em MODE=contido, o projeto real é $MAIN_ROOT (prefs não podem morrer com a
# worktree da run nem poluir o branch dela — escrita no checkout principal é a
# exceção documentada na R8(a)); em MODE=normal é $BASE_DIR. A skill guarda as
# dicas globais na MESMA pasta, dentro de $SKILL_HOME. Nada é criado aqui
# (D9: diretórios só nascem na primeira escrita, por do-prefs.sh).
if [ -n "$MAIN_ROOT" ]; then
  PROJECT_PREFS_ROOT="$MAIN_ROOT"
else
  PROJECT_PREFS_ROOT="$BASE_DIR"
fi
PROJECT_PREFS_DIR="$PROJECT_PREFS_ROOT/.deep-orchestrator-preferences"
GLOBAL_PREFS_DIR="$SKILL_HOME/.deep-orchestrator-preferences"
PROJECT_CONFIG="$PROJECT_PREFS_DIR/project-config.md"
PROJECT_LEARNINGS="$PROJECT_PREFS_DIR/learnings.md"
PENDING_DIR="$PROJECT_PREFS_DIR/pending"
GLOBAL_TIPS="$GLOBAL_PREFS_DIR/global-tips.md"
GLOBAL_PENDING_DIR="$GLOBAL_PREFS_DIR/pending"
DO_PREFS="$SKILL_HOME/scripts/do-prefs.sh"
DO_SURVEY="$SKILL_HOME/scripts/evolution-survey.sh"
# Derivam de paths já validados; a checagem é defensiva (mesma classe do 0.8).
for _v in PROJECT_PREFS_DIR GLOBAL_PREFS_DIR; do
  _val=${!_v}
  case "$_val" in
    *\'*)     die 7 "$_v contém aspa simples: $_val" ;;
    *"$(printf '\t')"*) die 7 "$_v contém TAB: $_val" ;;
    *$'\n'*)  die 7 "$_v contém newline: $_val" ;;
  esac
done

# --- (0.9) Estado persistente ------------------------------------------------
# O shell NÃO persiste entre chamadas Bash do harness. Sem este arquivo, toda
# variável desaparece no comando seguinte.
DO_HOME="$BASE_DIR/.deep-orchestrator"
DO_STATE="$DO_HOME/run-$RUN_ID"
PLAN_FILE="$DO_STATE/TASK_PLAN.md"
OWNED="$DO_STATE/owned.tsv"
ENV_FILE="$DO_STATE/env"

mkdir -p "$DO_STATE" "$CHILD_ROOT" || die 7 "não consegui criar $DO_STATE / $CHILD_ROOT"

# Ledger de 11 colunas (v4.1.0): 10 parent · 11 outcome — NUNCA vazias (placeholder
# `-`). O status segue na coluna 9, que NÃO é mais a última: quem lê usa
# awk -F'\t' por coluna (nunca `$` ancorado nem `IFS=$'\t' read`, que colapsa as
# colunas 7/8 vazias). Linha antiga de 9 colunas = 10/11 ausentes = `-`.
printf 'run_id\tkind\tname\tbranch\tpath\tbase_sha\tpre_merge_sha\tpost_merge_sha\tstatus\tparent\toutcome\n' > "$OWNED"

# --- (0.9b) DO_MAX_PARALLEL: cap de paralelismo (F3-02) ----------------------
# Chega por --flags='max-parallel=N' (0.0) ou, como fallback, pela variável de
# ambiente DO_MAX_PARALLEL; ausente → default 50 (CAP protetor).
# Validação: inteiro positivo. Só dígitos, então a
# interpolação no ENV_FILE (aspas simples) é segura.
case "${DO_MAX_PARALLEL:-}" in
  "") DO_MAX_PARALLEL=50 ;;   # ausente → default 50 (CAP protetor)
  *[!0-9]*)
    die 2 "DO_MAX_PARALLEL inválido: '${DO_MAX_PARALLEL}' — precisa ser um inteiro positivo (ex.: max-parallel=50)" ;;
esac
[ "$DO_MAX_PARALLEL" -gt 0 ] 2>/dev/null \
  || die 2 "DO_MAX_PARALLEL inválido: '$DO_MAX_PARALLEL' — precisa ser maior que zero"

# --- (0.9c) PORTÃO DE APROVAÇÃO: aprovação do plano no Plannotator (FASE 2.5) ----
# ATENÇÃO ao vocabulário: neste projeto "gate" significa o trio
# GATE_BUILD/GATE_TEST/GATE_LINT (FASE 1, passo 9). O que a FASE 2.5 faz é um
# PORTÃO DE APROVAÇÃO DO PLANO — nada a ver com build/test/lint. Os nomes aqui
# dizem APPROVAL de propósito, para que ninguém rode a suíte na hora do plano.
# O orquestrador resolve o prefixo `plan=on|off` da invocação (e os gatilhos de
# linguagem natural) e o repassa em --flags (0.0); a variável de ambiente
# DO_PLAN_APPROVAL segue como fallback. Ausente → 0, que
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
# (0.9d) DO_NO_STOP: controla o teto de ondas por execução. Chega pelo token
# `no-stop` em --flags (0.0) ou, como fallback, pela variável de ambiente.
# Ausente → 0, que preserva o teto histórico de 10 ondas; =1 remove o teto
# (ondas ilimitadas), MANTENDO a válvula anti-loop de 2 REPLANs estagnados.
case "${DO_NO_STOP:-}" in
  ""|0|off|no|false) DO_NO_STOP=0 ;;
  1|on|yes|true)     DO_NO_STOP=1 ;;
  *) die 2 "DO_NO_STOP inválido: '${DO_NO_STOP}' — use 0/1 (ou no-stop na invocação)" ;;
esac
# (0.9e) DO_EVOLUTION_SURVEY (v3.9.0): a PERGUNTA DE EVOLUÇÃO pós-execução
# (FASE 4, passo 7.5). Ausente → 1 — a pergunta SEMPRE aparece, por decisão do
# usuário (inclusive com gatilhos de autonomia); =0 é o kill-switch manual, o
# mesmo que a flag `no-evolve` na invocação (token em --flags — 0.0). Com 0, o
# passo é pulado INTEIRO: o agente de
# evolução não é disparado (sem análise do histórico) e nada é aplicado.
case "${DO_EVOLUTION_SURVEY:-}" in
  ""|1|on|yes|true) DO_EVOLUTION_SURVEY=1 ;;
  0|off|no|false)   DO_EVOLUTION_SURVEY=0 ;;
  *) die 2 "DO_EVOLUTION_SURVEY inválido: '${DO_EVOLUTION_SURVEY}' — use 0/1 (ou no-evolve na invocação)" ;;
esac

# (0.9f) DO_WT_ROOT / DO_WT_NAME no ENV_FILE vêm do FATO, não da flag: estamos
# num wt-root quando a raiz-de-mundo é uma worktree vinculada no branch
# do/wt/<nome>. Cobre o nome DEDUPLICADO (-2, -3 — a flag traz o nome cru), a
# sessão iniciada de DENTRO do wt sem o prefixo, e faz a R8j (fim = commit + push
# no branch do wt, NUNCA merge de volta) deixar de depender da memória do turno.
# BASE_BRANCH já passou pela validação de aspa/TAB/newline (0.6).
_wt_asked="$DO_WT_ROOT"
# O nome PEDIDO (mesmo slug de 0.3b), guardado antes de o FATO sobrescrever
# DO_WT_NAME — só quando o pedido chegou com o cwd JÁ dentro de uma worktree (na
# re-execução de 0.3b o nome que viaja já é o deduplicado: não é divergência).
_wt_req=""
if [ "$_wt_asked" = 1 ] && [ "${DO_WT_ROOT_ENTERED:-0}" != 1 ]; then
  _wt_req=$(printf '%s' "${DO_WT_NAME:-}" | tr '[:upper:]' '[:lower:]' \
            | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')
  [ "${#_wt_req}" -le 40 ] || _wt_req="${_wt_req:0:40}"
fi
case "$MODE:$BASE_BRANCH" in
  contido:do/wt/*/*) DO_WT_ROOT=0; DO_WT_NAME="" ;;   # do/wt/<run>/<filha>: namespace de um repo chamado "wt"
  contido:do/wt/?*)  DO_WT_ROOT=1; DO_WT_NAME="${BASE_BRANCH#do/wt/}" ;;
  *)                 DO_WT_ROOT=0; DO_WT_NAME="" ;;
esac
if [ "$_wt_asked" = 1 ] && [ "$DO_WT_ROOT" = 0 ]; then
  say "DO_WARN: wt= pedido, mas o cwd JÁ é uma worktree vinculada (MODE=contido) no branch"
  say "         '$BASE_BRANCH' — nenhum wt-root foi criado; a raiz-de-mundo é ESTA worktree. WT_ROOT = OFF."
fi
# wt=<outro> pedido de DENTRO de um wt-root: o trabalho iria para o branch de OUTRA
# tarefa sem aviso, e o resumo (WT_ROOT = ON (<atual>)) divergiria do digitado sem
# saída documentada.
if [ "$_wt_asked" = 1 ] && [ "$DO_WT_ROOT" = 1 ] && [ -n "$_wt_req" ] && [ "$_wt_req" != "$DO_WT_NAME" ]; then
  say "DO_WARN: wt=$_wt_req pedido, mas o cwd JÁ é o wt-root '$DO_WT_NAME' (branch $BASE_BRANCH) — nenhuma"
  say "         worktree nova foi criada; a raiz-de-mundo é ESTA e o trabalho vai para $BASE_BRANCH."
  say "         Para outro wt-root, invoque a partir do checkout principal${MAIN_ROOT:+ ($MAIN_ROOT)}."
fi

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
# deep-orchestrator-agent-skill — estado da execução $RUN_ID. Sourceie em TODA chamada Bash.
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
DO_NO_STOP='$DO_NO_STOP'
DO_EVOLUTION_SURVEY='$DO_EVOLUTION_SURVEY'
DO_TEST_MODE='$DO_TEST_MODE'
DO_QUESTION='$DO_QUESTION'
DO_SURF_SUB_AGENTS='$DO_SURF_SUB_AGENTS'
DO_WT_ROOT='$DO_WT_ROOT'
DO_WT_NAME='$DO_WT_NAME'
DO_SURF_GATE='$SKILL_HOME/scripts/surf-gate.sh'
PLAN_APPROVAL_DIR='$PLAN_APPROVAL_DIR'
PLAN_DOC='$PLAN_DOC'
DO_PLAN_APPROVAL_SH='$SKILL_HOME/scripts/plan-approval.sh'
PROJECT_PREFS_ROOT='$PROJECT_PREFS_ROOT'
PROJECT_PREFS_DIR='$PROJECT_PREFS_DIR'
GLOBAL_PREFS_DIR='$GLOBAL_PREFS_DIR'
PROJECT_CONFIG='$PROJECT_CONFIG'
PROJECT_LEARNINGS='$PROJECT_LEARNINGS'
PENDING_DIR='$PENDING_DIR'
GLOBAL_TIPS='$GLOBAL_TIPS'
GLOBAL_PENDING_DIR='$GLOBAL_PENDING_DIR'
DO_PREFS='$DO_PREFS'
DO_SURVEY='$DO_SURVEY'
export MODE BASE_DIR BASE_BRANCH BASE_NAME BASE_SLUG MAIN_ROOT MAIN_ROOT_DESC
export COMMON_DIR PARENT_DIR CHILD_ROOT PLACEMENT RUN_ID BRANCH_NS SKILL_HOME
export DO_HOME DO_STATE PLAN_FILE OWNED DO_WT DO_MAX_PARALLEL
export DO_PLAN_APPROVAL DO_PLAN_MAX_REVISIONS DO_PLAN_TIMEOUT DO_NO_STOP PLAN_APPROVAL_DIR PLAN_DOC DO_PLAN_APPROVAL_SH
export DO_EVOLUTION_SURVEY
export DO_TEST_MODE DO_QUESTION DO_SURF_SUB_AGENTS DO_WT_ROOT DO_WT_NAME DO_SURF_GATE
export PROJECT_PREFS_ROOT PROJECT_PREFS_DIR GLOBAL_PREFS_DIR PROJECT_CONFIG
export PROJECT_LEARNINGS PENDING_DIR GLOBAL_TIPS GLOBAL_PENDING_DIR DO_PREFS DO_SURVEY

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
say "  SURF_SUB_AGENTS = $DO_SURF_SUB_AGENTS  (teto de --sub-agents por chamada surf — 1..20)"
if [ "$DO_WT_ROOT" = 1 ]; then
  say "  WT_ROOT = ON ($DO_WT_NAME)  (wt-root persistente — R8j: o fim é commit + push em $BASE_BRANCH, NUNCA merge de volta)"
else
  say "  WT_ROOT = OFF"
fi
if [ "$DO_PLAN_APPROVAL" = 1 ]; then
  say "  PLAN_APPROVAL = ON   (FASE 2.5 — plano aprovado pelo usuário no Plannotator;"
  say "                  até $DO_PLAN_MAX_REVISIONS revisões, timeout ${DO_PLAN_TIMEOUT}s por rodada)"
else
  # OFF desliga SÓ o portão do plano: o texto antigo ("nenhuma interação com o
  # usuário") contradizia, na mesma saída, QUESTION = 1, EVOLUTION = ON e a pergunta
  # incondicional do protocolo PESQUISA-FALHOU.
  say "  PLAN_APPROVAL = OFF (sem portão de plano; a pergunta de pesquisa (chave/cota Brave) e a de evolução continuam valendo)"
fi
if [ "$DO_NO_STOP" = 1 ]; then
  say "  NO_STOP       = ON   (teto de 10 ondas REMOVIDO — ondas ilimitadas; válvula anti-loop de REPLAN estagnado mantida)"
else
  say "  NO_STOP       = OFF  (teto histórico de 10 ondas por execução — FASE 3)"
fi
if [ "$DO_EVOLUTION_SURVEY" = 1 ]; then
  say "  EVOLUTION     = ON   (pergunta de evolução em texto ao fim de TUDO — FASE 4, passo 7.5; no-evolve desliga)"
else
  say "  EVOLUTION     = OFF  (no-evolve / DO_EVOLUTION_SURVEY=0 — pergunta e análise não rodam)"
fi
# TEST_MODE / QUESTION: literal `NOME = valor` (um espaço) — é o que o passo
# "confira o resumo" da FASE 0 e as suítes comparam com o que foi digitado.
case "$DO_TEST_MODE" in
  none) say "  TEST_MODE = none  (no-test — NENHUM teste novo; Testing Subwave DESLIGADA; gate e suíte EXISTENTE continuam rodando)" ;;
  e2e)  say "  TEST_MODE = e2e  (only-e2e — Testing Subwaves criam APENAS testes end-to-end, por jornada)" ;;
  *)    say "  TEST_MODE = full  (default — Testing + Validation Subwaves completas)" ;;
esac
if [ "$DO_QUESTION" = 1 ]; then
  say "  QUESTION = 1  (do-question — o orquestrador PODE perguntar em texto: rodada de dúvidas na FASE 1 e no máx. 1 por onda)"
else
  say "  QUESTION = 0  (autonomia — infere e documenta; a pergunta da chave Brave/pesquisa vale MESMO assim)"
fi
say "  PREFS projeto = ${PROJECT_PREFS_DIR:-<não resolvido>}  (memória consultiva, gitignored — do-prefs.sh)"
say "  PREFS global  = ${GLOBAL_PREFS_DIR:-<não resolvido>}  (dicas globais da skill, gitignored)"
say "  worktrees de terceiros: $(wc -l < "$DO_STATE/foreign-worktrees.txt" 2>/dev/null | tr -d ' ') (NÃO tocar)"
say ""
say_orphans
say "Sourceie em TODA chamada Bash posterior:"
printf '%s\n' "$ENV_FILE"
