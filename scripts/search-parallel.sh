#!/usr/bin/env bash
# =============================================================================
# search-parallel.sh — Buscas em PARALELO via search.sh (agregação + dedup)
# -----------------------------------------------------------------------------
# Decisão D3: pesquisas em paralelo SEM LIMITE de quantidade, gerenciadas pelo
# código — a skill chama UMA vez e espera. Nenhum provedor novo na cadeia:
# cada query vira uma chamada search.sh (que tem o fallback 3-tier interno).
#
# ENTRADA
#   --batch <arquivo>   Uma query por linha, OU
#   queries posicionais múltiplas
#
# EXECUÇÃO
#   Uma chamada search.sh por query EM PARALELO (background jobs + wait), sem
#   teto de quantidade. Cada job grava seu resultado em arquivo próprio sob um
#   dir temporário (mktemp -d).
#
# RATE LIMIT
#   A Brave nesta conta é ~1 req/s: cada job espera um jitter de 0..2s antes
#   de disparar (PARALLEL_JITTER_MAX) e, em HTTP 429 detectado no stderr do
#   search.sh, aplica backoff exponencial com jitter (1s, 2s, 4s + 0-1s) — em
#   cima do retry interno (1x) do brave-search.sh.
#
# CACHE POR RUN
#   Queries idênticas na mesma execução reutilizam o resultado (dedup por hash
#   da query ANTES de disparar — sha256sum/md5/md5sum).
#
# SAÍDA (--json)
#   {queries: [{query, provider, total_results, urls, cached}],
#    results: [{url, title, description, source, queries}]  (dedup por URL),
#    failures: [{query, exit_code, stderr}],
#    diagnostics: {total_queries, unique_queries, cached_queries,
#                  successful_queries, failed_queries, unique_results,
#                  duration_ms}}
#
# EXIT CODES
#   0 = pelo menos 1 query com resultado
#   1 = todas as queries falharam/vieram vazias (alinhado ao search.sh)
#   2 = erro de uso/configuração
#
# AMBIENTE
#   SEARCH_SH             Path do search.sh (default: <dir deste script>/search.sh)
#   PARALLEL_JITTER_MAX   Jitter máximo de disparo por job em segundos (default 2)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

SEARCH_SH="${SEARCH_SH:-$SCRIPT_DIR/search.sh}"
PARALLEL_JITTER_MAX="${PARALLEL_JITTER_MAX:-2}"

JSON_OUT=0
BATCH_FILE=""
SEARCH_ARGS=()
declare -a BATCH_QUERIES=()
WORK=""

# --- Ajuda --------------------------------------------------------------------
usage() {
  cat <<EOF
Uso: $SCRIPT_NAME [OPTS] <query1> [query2 ...]
     $SCRIPT_NAME [OPTS] --batch <arquivo>

Executa MÚLTIPLAS buscas EM PARALELO via search.sh e devolve um relatório
agregado e deduplicado (por URL). NUNCA chame search.sh em loop — use este
script para lotes.

ARGUMENTOS
  <query1> [query2 ...]   Queries a pesquisar (cada uma vira um job paralelo)
  --batch <arquivo>       Alternativa: uma query por linha (vazias são ignoradas)

OPÇÕES
  --task "<texto>"        Contexto da tarefa (repassado ao search.sh)
  --goal "<texto>"        Objetivo da busca (repassado ao search.sh)
  --insights "<texto>"    Premissas a verificar (repassado ao search.sh)
  --deliverable "<texto>" Formato esperado (repassado ao search.sh)
  --brief-file <arquivo>  JSON com {question, task, goal, insights, deliverable}
                          (repassado ao search.sh; query vem dos posicionais/batch)
  --count N               Resultados por busca (repassado; default do search.sh)
  --freshness <v>         pd | pw | pm | py (repassado)
  --country <cc>          Código de país (repassado)
  --search-lang <lang>    Idioma dos resultados (repassado)
  --offset N              Deslocamento de paginação (repassado)
  --result-filter <lista> web,news,videos,images (repassado)
  --max-evolutions N      Evoluções de query no Tier 2 (repassado)
  --dev-mode              Contexto de dev nas queries (repassado)
  --timeout N             Timeout por chamada em segundos (repassado)
  --json                  Saída AGREGADA em JSON puro (envelope único:
                          {queries, results, failures, diagnostics})
  -h, --help              Mostra esta ajuda

EXIT CODES
  0 = pelo menos 1 query com resultado
  1 = todas as queries falharam ou vieram vazias
  2 = erro de uso/configuração

AMBIENTE
  SEARCH_SH             Path do search.sh (default: scripts/search.sh)
  PARALLEL_JITTER_MAX   Jitter máximo de disparo por job (default 2; use 0
                        em testes para disparos imediatos)
EOF
}

# flag_val <flag> <args...> → valor (exit 2 se faltar)
flag_val() {
  local flag="$1"
  shift
  if [[ $# -lt 1 ]]; then
    echo "ERRO: a flag $flag requer um valor" >&2
    usage >&2
    exit 2
  fi
  echo "$1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --batch)     BATCH_FILE="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --batch=*)   BATCH_FILE="${1#*=}"; shift ;;
      --json)      JSON_OUT=1; shift ;;
      --task|--goal|--insights|--deliverable|--brief-file|--count|--freshness|--country|--search-lang|--offset|--result-filter|--max-evolutions|--timeout)
        SEARCH_ARGS+=( "$1" "$(flag_val "$1" "${@:2}")" )
        shift 2
        ;;
      --task=*|--goal=*|--insights=*|--deliverable=*|--brief-file=*|--count=*|--freshness=*|--country=*|--search-lang=*|--offset=*|--result-filter=*|--max-evolutions=*|--timeout=*)
        SEARCH_ARGS+=( "$1" )
        shift
        ;;
      --dev-mode) SEARCH_ARGS+=( --dev-mode ); shift ;;
      --)
        shift
        # Tudo após "--" é query posicional
        while [[ $# -gt 0 ]]; do
          BATCH_QUERIES+=( "$1" ); shift
        done
        break
        ;;
      -*)
        echo "ERRO: flag desconhecida: $1" >&2
        usage >&2
        exit 2
        ;;
      *) BATCH_QUERIES+=( "$1" ); shift ;;
    esac
  done
}

# --- Batch file ---------------------------------------------------------------
load_batch_file() {
  if [[ ! -f "$BATCH_FILE" ]]; then
    echo "ERRO: --batch não encontrado: $BATCH_FILE" >&2
    exit 2
  fi
  local q
  while IFS= read -r q || [[ -n "$q" ]]; do
    q="${q//$'\r'/}"   # remove CR de arquivos Windows
    [[ -z "$q" ]] && continue
    BATCH_QUERIES+=( "$q" )
  done < "$BATCH_FILE"
}

# --- Hash para cache intra-run -------------------------------------------------
# Qualquer hash serve (dedup dentro da MESMA execução); fallbacks portáveis.
qhash() {
  local q="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$q" | sha256sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then
    printf '%s' "$q" | md5
  elif command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$q" | md5sum | cut -d' ' -f1
  else
    printf '%s' "$q"
  fi
}

# --- Job: uma query -------------------------------------------------------------
# 1) jitter de disparo (0..PARALLEL_JITTER_MAX s) para não bater a API de uma vez
# 2) search.sh com --json (sempre, para o agregador parsear)
# 3) em HTTP 429 (detectado no stderr do search.sh), backoff 1s/2s/4s + jitter 0-1s
run_query() {
  local q="$1" h="$2"
  sleep "$(( RANDOM % (PARALLEL_JITTER_MAX + 1) ))"

  local out="$WORK/out-$h.json" err="$WORK/err-$h.txt"
  local attempt rc
  for (( attempt = 0; attempt < 4; attempt++ )); do
    # set +e: a falha do search.sh (rc=1) não pode abortar o job antes do retry
    set +e
    "$SEARCH_SH" --json "${SEARCH_ARGS[@]}" "$q" > "$out" 2> "$err"
    rc=$?
    set -e
    if (( rc == 0 )); then
      break
    fi
    if (( rc == 2 )); then
      break   # erro de uso/config — não retenta
    fi
    if ! grep -q "HTTP 429" "$err"; then
      break   # falha sem rate limit (ex.: cadeia toda vazia) — sem backoff
    fi
    if (( attempt == 3 )); then
      break
    fi
    local delay=$(( (1 << attempt) + (RANDOM % 2) ))   # 1s, 2s, 4s + jitter 0-1s
    echo "[$SCRIPT_NAME] '$q' rate limit (HTTP 429); nova tentativa em ${delay}s..." >&2
    sleep "$delay"
  done
  echo "$rc" > "$WORK/status-$h.txt"
}

# --- Agregação ----------------------------------------------------------------
# Lê queries.jsonl (uma entrada por query do lote) + os arquivos do job e
# monta o envelope único: {queries, results (dedup por URL), failures}.
aggregate() {
  local total_q=0 unique_q=0 cached_q=0 ok_q=0 fail_q=0
  local line q h cached st f total ok
  local out_ok="$WORK/queries-ok.jsonl"
  local envelopes="$WORK/envelopes.jsonl"
  : > "$out_ok"
  : > "$envelopes"
  : > "$WORK/failures.jsonl"

  while IFS= read -r line; do
    q="$(echo "$line" | jq -r '.query')"
    h="$(echo "$line" | jq -r '.hash')"
    cached="$(echo "$line" | jq -r '.cached')"
    total_q=$(( total_q + 1 ))
    if [[ "$cached" == "true" ]]; then
      cached_q=$(( cached_q + 1 ))
    else
      unique_q=$(( unique_q + 1 ))
    fi

    st="$(cat "$WORK/status-$h.txt" 2>/dev/null || echo 2)"
    f="$WORK/out-$h.json"
    total=0
    ok=0
    if [[ "$st" == "0" ]] && [[ -s "$f" ]]; then
      total="$(jq -r '.total_results // 0' "$f" 2>/dev/null || echo 0)"
      if (( total > 0 )); then
        ok=1
      fi
    fi

    if (( ok )); then
      ok_q=$(( ok_q + 1 ))
      jq -c -n \
        --arg q "$q" \
        --arg provider "$(jq -r '.diagnostics.provider // "unknown"' "$f" 2>/dev/null || echo unknown)" \
        --argjson total "$total" \
        --argjson urls "$(jq -c '[.results[].url]' "$f" 2>/dev/null || echo '[]')" \
        --argjson cached "$( [[ "$cached" == "true" ]] && echo true || echo false )" \
        '{query: $q, provider: $provider, total_results: $total, urls: $urls, cached: $cached}' \
        >> "$out_ok"
      cat "$f" >> "$envelopes"
    else
      fail_q=$(( fail_q + 1 ))
      jq -c -n \
        --arg q "$q" \
        --argjson ec "$st" \
        --arg err "$(tail -n 2 "$WORK/err-$h.txt" 2>/dev/null | tr '\n' ' ')" \
        '{query: $q, exit_code: $ec, stderr: $err}' \
        >> "$WORK/failures.jsonl"
    fi
  done < "$WORK/queries.jsonl"

  # diagnostics + envelope final
  local duration_ms end_ms start_ms
  end_ms="$(now_ms)"
  start_ms="${_par_start_ms:-$end_ms}"
  duration_ms=$(( end_ms - start_ms ))

  local queries_json results_json failures_json
  queries_json="$(jq -s '.' "$out_ok" 2>/dev/null || echo '[]')"
  results_json="$(jq -s '
    def queries_for($all; $u): [ $all[] | select((.results // []) | any(.url == $u)) | .query_original ] | unique;
    . as $all |
    ( [ $all[].results[] ] | unique_by(.url)
      | map({url: .url, title: .title, description: .description, source: .source, queries: queries_for($all; .url)}) )
  ' "$envelopes" 2>/dev/null || echo '[]')"
  failures_json="$(jq -s '.' "$WORK/failures.jsonl" 2>/dev/null || echo '[]')"
  local unique_results
  unique_results="$(echo "$results_json" | jq 'length' 2>/dev/null || echo 0)"

  local diag_json
  diag_json="$(jq -n \
    --argjson tq "$total_q" \
    --argjson uq "$unique_q" \
    --argjson cq "$cached_q" \
    --argjson ok "$ok_q" \
    --argjson fl "$fail_q" \
    --argjson ur "$unique_results" \
    --argjson d "$duration_ms" \
    '{total_queries: $tq, unique_queries: $uq, cached_queries: $cq, successful_queries: $ok, failed_queries: $fl, unique_results: $ur, duration_ms: $d}')"

  local final
  final="$(jq -n \
    --argjson queries "$queries_json" \
    --argjson results "$results_json" \
    --argjson failures "$failures_json" \
    --argjson diag "$diag_json" \
    '{queries: $queries, results: $results, failures: $failures, diagnostics: $diag}')"

  echo "$final" > "$WORK/final.json"

  # Exit code: 0 se ≥1 query com resultado; senão 1
  if (( ok_q > 0 )); then
    return 0
  fi
  return 1
}

# --- Saída humana -------------------------------------------------------------
human_output() {
  local final="$WORK/final.json"
  local line i j
  echo "# Search batch — $(jq -r '.diagnostics.total_queries' "$final") queries, $(jq -r '.diagnostics.unique_results' "$final") resultados únicos"
  echo
  i=1
  while IFS= read -r line; do
    echo "## $i. $(echo "$line" | jq -r '.query')$( [[ "$(echo "$line" | jq -r '.cached')" == "true" ]] && echo ' [cached]' ) — provider $(echo "$line" | jq -r '.provider') ($(echo "$line" | jq -r '.total_results') resultados)"
    echo "$line" | jq -r '.urls[] | "   " + .'
    echo
    i=$(( i + 1 ))
  done < <(jq -c '.queries[]' "$final")

  if [[ "$(jq '.failures | length' "$final")" != "0" ]]; then
    echo "## Falhas ($(jq '.failures | length' "$final"))"
    while IFS= read -r line; do
      echo "- \"$(echo "$line" | jq -r '.query')\" (exit $(echo "$line" | jq -r '.exit_code')): $(echo "$line" | jq -r '.stderr')"
    done < <(jq -c '.failures[]' "$final")
    echo
  fi

  echo "## Fontes únicas (dedup por URL)"
  j=1
  while IFS= read -r line; do
    echo "$j. $(echo "$line" | jq -r '.url') — $(echo "$line" | jq -r '.title')"
    j=$(( j + 1 ))
  done < <(jq -c '.results[]' "$final")
}

# --- Utilitários --------------------------------------------------------------
now_ms() {
  local t
  t="$(date +%s%3N 2>/dev/null)" || t=""
  if [[ "$t" =~ ^[0-9]{13}$ ]]; then
    echo "$t"
  else
    echo "$(( $(date +%s) * 1000 ))"
  fi
}

# --- Main ---------------------------------------------------------------------
main() {
  parse_args "$@"

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERRO: dependência ausente no PATH: jq (necessário para a agregação)" >&2
    exit 2
  fi

  if [[ ! -x "$SEARCH_SH" ]]; then
    echo "ERRO: search.sh não encontrado/executável: $SEARCH_SH (defina SEARCH_SH se necessário)" >&2
    exit 2
  fi

  if [[ -n "$BATCH_FILE" ]] && (( ${#BATCH_QUERIES[@]} > 0 )); then
    echo "ERRO: use --batch OU queries posicionais, não ambos." >&2
    exit 2
  fi
  if [[ -n "$BATCH_FILE" ]]; then
    load_batch_file
  fi
  if (( ${#BATCH_QUERIES[@]} == 0 )); then
    echo "ERRO: nenhuma query fornecida. Passe queries posicionais ou use --batch <arquivo>." >&2
    usage >&2
    exit 2
  fi

  WORK="$(mktemp -d)"
  trap 'rm -rf "${WORK:-}"' EXIT
  : > "$WORK/queries.jsonl"

  local _par_start_ms
  _par_start_ms="$(now_ms)"

  # --- Cache intra-run + disparo em paralelo (sem teto de quantidade) ---
  declare -A SEEN=()
  local q h
  for q in "${BATCH_QUERIES[@]}"; do
    h="$(qhash "$q")"
    if [[ -n "${SEEN[$h]:-}" ]]; then
      # Query idêntica já vista nesta execução: reutiliza o resultado do 1º job
      jq -c -n --arg q "$q" --arg h "$h" --argjson cached true \
        '{query: $q, hash: $h, cached: true}' >> "$WORK/queries.jsonl"
      continue
    fi
    SEEN[$h]=1
    jq -c -n --arg q "$q" --arg h "$h" --argjson cached false \
      '{query: $q, hash: $h, cached: false}' >> "$WORK/queries.jsonl"
    # cada job roda em subshell: grava seus próprios arquivos sob $WORK
    ( run_query "$q" "$h" ) &
  done

  # wait retorna status do último job — o resultado real está nos arquivos
  # de status por job; `|| true` protege o set -e
  wait || true

  # --- Agregação e saída ---
  local rc=0
  if aggregate; then
    rc=0
  else
    rc=1
  fi

  if (( JSON_OUT )); then
    cat "$WORK/final.json"
  else
    human_output
  fi

  exit "$rc"
}

main "$@"
