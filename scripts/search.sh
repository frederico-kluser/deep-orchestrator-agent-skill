#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# search.sh — Unified search wrapper for deep-orchestrator
# -----------------------------------------------------------------------------
# Smart wrapper com cadeia de fallback automática:
#   Tier 1: surf-skill (multi-provider AI-powered) — BEST
#   Tier 2: Brave Search API (direct, via search_brave_api sourced) — GOOD
#   Tier 3: DuckDuckGo Instant Answer API (keyless) — conectividade garantida,
#           cobertura limitada a instant answers (não é busca full-text)
#
# Interface CLI idêntica ao brave-search.sh para backward compatibility.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# --- Source brave-search.sh para obter search_brave_api() e helpers -----------
# Sourceado CEDO (antes das nossas definições) para que search.sh possa
# sobrescrever funções com mesmo nome (ex.: human_report, main).
# Salva e restaura opções de shell para isolar set -euo pipefail.
_search_saved_opts="$(set +o)"
# shellcheck disable=SC1090
if [[ -f "$SCRIPT_DIR/brave-search.sh" ]]; then
  source "$SCRIPT_DIR/brave-search.sh" 2>/dev/null || true
fi
eval "$_search_saved_opts" 2>/dev/null || true

# --- Configuração -------------------------------------------------------------
DEFAULT_COUNT=10
DEFAULT_TIMEOUT=30
DEFAULT_MAX_EVOLUTIONS=2
DEFAULT_SEARCH_LANG="en"

# Valores de flags (populados durante o parsing)
QUERY=""
TASK=""
GOAL=""
INSIGHTS=""
DELIVERABLE=""
BRIEF_FILE=""
COUNT="$DEFAULT_COUNT"
FRESHNESS=""
COUNTRY=""
SEARCH_LANG="$DEFAULT_SEARCH_LANG"
OFFSET=0
RESULT_FILTER=""
MAX_EVOLUTIONS="$DEFAULT_MAX_EVOLUTIONS"
DEV_MODE=0
TIMEOUT="$DEFAULT_TIMEOUT"
JSON_OUT=0

# --- Ajuda --------------------------------------------------------------------
usage() {
  cat <<EOF
Uso: $SCRIPT_NAME [OPTS] "<query>"

Smart search wrapper do deep-orchestrator (fallback automático).

ARGUMENTOS
  "<query>"                 A pergunta/tópico a pesquisar (obrigatório,
                            a menos que --brief-file seja usado)

OPÇÕES
  --task "<texto>"          Contexto da tarefa em andamento
  --goal "<texto>"          Objetivo específico desta busca
  --insights "<texto>"      Premissas a verificar
  --deliverable "<texto>"   Formato esperado da resposta
  --brief-file <arquivo>    JSON com {question, task, goal, insights, deliverable};
                            flags individuais sobrescrevem o arquivo
  --count N                 Resultados por busca (default $DEFAULT_COUNT, máx 20)
  --freshness <v>           pd | pw | pm | py ou AAAA-MM-DDtoAAAA-MM-DD
  --country <cc>            Código de país de 2 letras
  --search-lang <lang>      Idioma dos resultados (default: $DEFAULT_SEARCH_LANG)
  --offset N                Deslocamento de paginação (default 0, máx 9)
  --result-filter <lista>   web,news,videos,images
  --max-evolutions N        Evoluções de query (default $DEFAULT_MAX_EVOLUTIONS, máx 5)
  --dev-mode                Adiciona contexto de dev às queries (afeta só o Tier 2/Brave)
  --timeout N               Timeout por chamada em segundos (default $DEFAULT_TIMEOUT)
  --json                    Saída em JSON puro com envelope UNIFICADO: a saída
                            do Tier 1 (surf, envelope {answer, sources}) é
                            normalizada para o mesmo formato dos Tiers 2/3
                            ({query_original, answer?, query_evolution?, task,
                            goal, insights, deliverable, results, total_results,
                            credits_remaining?, diagnostics}); avisos vão para stderr
  -h, --help                Mostra esta ajuda

PROVIDERS (fallback automático)
  1. surf-search-normal     Se disponível no PATH (Tier 1 — melhor qualidade)
  2. Brave Search API       Se BRAVE_API_KEY estiver definida (Tier 2)
  3. DuckDuckGo             Sempre disponível, sem chave (Tier 3 — fallback final)

EXIT CODES
  0 sucesso (resultados encontrados)
  1 sem resultados em TODA a cadeia de fallback, ou erro de busca
  2 erro de configuração/uso (dependências ausentes, flag inválida, query ausente)
EOF
}

# --- Dependências --------------------------------------------------------------
# Verificadas UMA vez, no início (antes de qualquer uso de jq/curl/python3,
# inclusive no --brief-file). Exit 2 coerente com a mensagem clara.
check_deps() {
  local missing=()
  for bin in curl jq python3; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing+=("$bin")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "ERRO: dependências ausentes no PATH: ${missing[*]} (necessárias: curl, jq, python3)" >&2
    exit 2
  fi
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
      --task)          TASK="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --goal)          GOAL="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --insights)      INSIGHTS="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --deliverable)   DELIVERABLE="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --brief-file)    BRIEF_FILE="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --count)         COUNT="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --freshness)     FRESHNESS="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --country)       COUNTRY="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --search-lang)   SEARCH_LANG="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --offset)        OFFSET="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --result-filter) RESULT_FILTER="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --max-evolutions) MAX_EVOLUTIONS="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --timeout)       TIMEOUT="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --task=*)          TASK="${1#*=}"; shift ;;
      --goal=*)          GOAL="${1#*=}"; shift ;;
      --insights=*)      INSIGHTS="${1#*=}"; shift ;;
      --deliverable=*)   DELIVERABLE="${1#*=}"; shift ;;
      --brief-file=*)    BRIEF_FILE="${1#*=}"; shift ;;
      --count=*)         COUNT="${1#*=}"; shift ;;
      --freshness=*)     FRESHNESS="${1#*=}"; shift ;;
      --country=*)       COUNTRY="${1#*=}"; shift ;;
      --search-lang=*)   SEARCH_LANG="${1#*=}"; shift ;;
      --offset=*)        OFFSET="${1#*=}"; shift ;;
      --result-filter=*) RESULT_FILTER="${1#*=}"; shift ;;
      --max-evolutions=*) MAX_EVOLUTIONS="${1#*=}"; shift ;;
      --timeout=*)       TIMEOUT="${1#*=}"; shift ;;
      --json)      JSON_OUT=1; shift ;;
      --dev-mode)  DEV_MODE=1; shift ;;
      --)
        shift
        # Tudo após "--" é posicional (permite query começando com "-")
        local pos
        for pos in "$@"; do
          if [[ -n "$QUERY" ]]; then
            echo "ERRO: apenas UMA query é permitida (recebidas múltiplas)." >&2
            usage >&2
            exit 2
          fi
          QUERY="$pos"
        done
        break
        ;;
      -*)
        echo "ERRO: flag desconhecida: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        if [[ -n "$QUERY" ]]; then
          echo "ERRO: apenas UMA query é permitida (recebidas múltiplas: '$QUERY' e '$1')." >&2
          usage >&2
          exit 2
        fi
        QUERY="$1"; shift ;;
    esac
  done
}

# Carrega campos faltantes do --brief-file (flags individuais têm prioridade)
load_brief_file() {
  [[ -n "$BRIEF_FILE" ]] || return 0
  if [[ ! -f "$BRIEF_FILE" ]]; then
    echo "ERRO: --brief-file não encontrado: $BRIEF_FILE" >&2
    exit 2
  fi
  if ! jq -e . "$BRIEF_FILE" >/dev/null 2>&1; then
    echo "ERRO: --brief-file não é JSON válido: $BRIEF_FILE" >&2
    exit 2
  fi
  [[ -z "$QUERY" ]]       && QUERY="$(jq -r '.question // empty' "$BRIEF_FILE")"
  [[ -z "$TASK" ]]        && TASK="$(jq -r '.task // empty' "$BRIEF_FILE")"
  [[ -z "$GOAL" ]]        && GOAL="$(jq -r '.goal // empty' "$BRIEF_FILE")"
  [[ -z "$INSIGHTS" ]]    && INSIGHTS="$(jq -r '.insights // empty' "$BRIEF_FILE")"
  [[ -z "$DELIVERABLE" ]] && DELIVERABLE="$(jq -r '.deliverable // empty' "$BRIEF_FILE")"
}

validate() {
  if [[ -z "$QUERY" ]]; then
    echo "ERRO: query não fornecida. Passe \"<query>\" ou use --brief-file." >&2
    usage >&2
    exit 2
  fi
  if [[ ! "$COUNT" =~ ^[0-9]+$ ]] || (( COUNT < 1 || COUNT > 20 )); then
    echo "ERRO: --count deve ser um inteiro entre 1 e 20 (recebido: '$COUNT')" >&2
    exit 2
  fi
  if [[ ! "$MAX_EVOLUTIONS" =~ ^[0-9]+$ ]] || (( MAX_EVOLUTIONS > 5 )); then
    echo "ERRO: --max-evolutions deve ser um inteiro entre 0 e 5" >&2
    exit 2
  fi
  if [[ -n "$FRESHNESS" ]] \
     && [[ ! "$FRESHNESS" =~ ^(pd|pw|pm|py|[0-9]{4}-[0-9]{2}-[0-9]{2}to[0-9]{4}-[0-9]{2}-[0-9]{2})$ ]]; then
    echo "ERRO: --freshness inválido ('$FRESHNESS'). Use pd|pw|pm|py ou AAAA-MM-DDtoAAAA-MM-DD." >&2
    exit 2
  fi
  if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || (( TIMEOUT < 1 || TIMEOUT > 120 )); then
    echo "ERRO: --timeout deve ser um inteiro entre 1 e 120" >&2
    exit 2
  fi
  if [[ ! "$OFFSET" =~ ^[0-9]+$ ]] || (( OFFSET > 9 )); then
    echo "ERRO: --offset deve ser um inteiro entre 0 e 9" >&2
    exit 2
  fi
}

# --- Utilitários ---------------------------------------------------------------
now_ms() {
  local t
  t="$(date +%s%3N 2>/dev/null)" || t=""
  if [[ "$t" =~ ^[0-9]{13}$ ]]; then
    echo "$t"
  else
    echo "$(( $(date +%s) * 1000 ))"
  fi
}

# urlencode: pure-bash (portable macOS/Linux)
urlencode() {
  local string="$1"
  local strlen=${#string}
  local encoded=""
  local pos c o
  for (( pos=0 ; pos<strlen ; pos++ )); do
    c=${string:$pos:1}
    case "$c" in
      [-_.~a-zA-Z0-9] ) o="${c}" ;;
      * )               printf -v o '%%%02x' "'$c"
    esac
    encoded+="${o}"
  done
  echo "${encoded}"
}

# --- Saída --------------------------------------------------------------------
human_report() {
  local results_json="$1"
  local duration_ms="$2"
  local provider="$3"
  local i=1

  echo "# Search: $QUERY"
  echo
  echo "**Task:** ${TASK:-—}"
  echo "**Goal:** ${GOAL:-—}"
  echo "**Insights:** ${INSIGHTS:-—}"
  echo "**Deliverable:** ${DELIVERABLE:-—}"
  echo

  while IFS= read -r r; do
    local title url published desc
    title="$(echo "$r" | jq -r '.title')"
    url="$(echo "$r" | jq -r '.url')"
    published="$(echo "$r" | jq -r '.published // empty')"
    desc="$(echo "$r" | jq -r '.description')"
    echo "## [$i] $title"
    echo "$url"
    [[ -n "$published" ]] && echo "*published: $published*"
    echo
    echo "${desc:0:600}"
    echo
    i=$(( i + 1 ))
  done < <(echo "$results_json" | jq -c '.[]')

  if [[ "$i" == "1" ]]; then
    echo "_Nenhum resultado encontrado._"
    echo
  fi

  echo "---"
  echo
  echo "_provider: ${provider} · ${duration_ms}ms_"
  echo
  echo "## Sources"
  echo "$results_json" | jq -r '.[].url'
}

# Envelope JSON UNIFICADO do search.sh — os 3 tiers emitem o MESMO formato
# (o Tier 1 é normalizado para ele). Campos opcionais só aparecem quando
# presentes: answer (Tier 1), query_evolution (Tier 2, --max-evolutions),
# credits_remaining (Tier 2, header X-RateLimit-Remaining).
# Uso: json_report <results-json> <duration-ms> <provider> [answer] [evolution-json] [credits]
json_report() {
  local results_json="$1"
  local duration_ms="$2"
  local provider="$3"
  local answer="${4:-}"
  local evolution_json="${5:-[]}"
  local credits="${6:-null}"
  local total_results
  total_results="$(echo "$results_json" | jq 'length')"

  local diagnostics
  diagnostics="$(jq -n \
    --arg provider "$provider" \
    --argjson total "$total_results" \
    --argjson duration "$duration_ms" \
    '{provider: $provider, total_results: $total, duration_ms: $duration}')"

  # NOTA: valor `empty` dentro de objeto zera o objeto INTEIRO no jq 1.7 —
  # campos opcionais viram null e são removidos com with_entries(select(.value != null))
  jq -n \
    --arg qo "$QUERY" \
    --arg ans "$answer" \
    --arg task "$TASK" \
    --arg goal "$GOAL" \
    --arg insights "$INSIGHTS" \
    --arg deliverable "$DELIVERABLE" \
    --argjson results "$results_json" \
    --argjson total "$total_results" \
    --argjson diagnostics "$diagnostics" \
    --argjson qe "$evolution_json" \
    --argjson cr "$credits" \
    '{query_original: $qo, answer: $ans, query_evolution: $qe, task: $task, goal: $goal, insights: $insights, deliverable: $deliverable, results: $results, total_results: $total, credits_remaining: $cr, diagnostics: $diagnostics}
     | .answer = (if $ans != "" then $ans else null end)
     | .query_evolution = (if ($qe | length) > 0 then $qe else null end)
     | .credits_remaining = (if $cr != null then $cr else null end)
     | with_entries(select(.value != null))'
}

# --- Tier 1: surf-skill -------------------------------------------------------
# Retorna 0 e imprime resultados em stdout se bem-sucedido.
# Retorna não-zero se falhar (mensagens de erro em stderr).
try_surf_skill() {
  local surf_bin="surf-search-normal"
  if ! command -v "$surf_bin" &>/dev/null; then
    echo "[search.sh] Tier 1 (surf-skill) não encontrado no PATH, pulando Tier 1." >&2
    return 1
  fi

  local args=()
  [[ -n "$TASK" ]]        && args+=( --task "$TASK" )
  [[ -n "$GOAL" ]]        && args+=( --goal "$GOAL" )
  [[ -n "$INSIGHTS" ]]    && args+=( --insights "$INSIGHTS" )
  [[ -n "$DELIVERABLE" ]] && args+=( --deliverable "$DELIVERABLE" )

  # Map --count to --max-queries (COUNT é validado em 1..20, então o
  # último ramo cobre 11..20 — sem caso inalcançável)
  local maxq
  if (( COUNT <= 5 )); then
    maxq=3
  elif (( COUNT <= 10 )); then
    maxq=6
  else
    maxq=12
  fi
  args+=( --max-queries "$maxq" )

  (( JSON_OUT )) && args+=( --json )
  # NOTA: --dev-mode afeta apenas o Tier 2 (brave-search.sh:524-525);
  # o binário surf-search-normal NÃO possui essa flag — não a passamos aqui.

  # Timeout: surf-search-normal consome --budget-ms em MILISSEGUNDOS
  # (fonte: src/lib/dispatch.mjs do surf); TIMEOUT do search.sh é em segundos.
  args+=( --budget-ms "$(( TIMEOUT * 1000 ))" )

  # CAPTURA a saída (não flui direto): se o surf imprimir parcial e falhar,
  # o parcial é descartado — os tiers seguintes não concatenam lixo no stdout
  # (que quebraria o --json). Só emite se rc=0.
  local surf_out_file surf_rc
  surf_out_file="$(mktemp)"
  set +e
  "$surf_bin" "${args[@]}" "$QUERY" > "$surf_out_file"
  surf_rc=$?
  set -e

  if [[ $surf_rc -ne 0 ]]; then
    echo "[search.sh] Tier 1 (surf-skill) retornou exit code $surf_rc" >&2
    rm -f "$surf_out_file"
    return 1
  fi

  if (( JSON_OUT )); then
    # NORMALIZAÇÃO: o Tier 1 fala {answer, sources}; reembrulha no envelope
    # unificado do search.sh (answer + results extraídos de sources).
    local raw
    raw="$(cat "$surf_out_file")"
    rm -f "$surf_out_file"
    if echo "$raw" | jq -e . >/dev/null 2>&1; then
      local results answer duration_ms end_ms start_ms
      results="$(echo "$raw" | jq -c '[.sources // [] | .[] | select(.url != null and .url != "") | {title: (.title // ""), url: .url, description: (.description // ""), published: (.published // .date // .page_age // ""), source: "surf"}]')"
      answer="$(echo "$raw" | jq -r '.answer // empty' 2>/dev/null || true)"
      end_ms="$(now_ms)"
      start_ms="${_search_start_ms:-$end_ms}"
      duration_ms=$(( end_ms - start_ms ))
      json_report "$results" "$duration_ms" "surf-skill" "$answer"
    else
      echo "AVISO: saída do Tier 1 não é JSON válido (com --json); repassando cru." >&2
      echo "$raw"
    fi
  else
    cat "$surf_out_file"
    rm -f "$surf_out_file"
  fi

  return 0
}

# --- Tier 2: Brave API (sourced from brave-search.sh) --------------------------
# Retorna 0 e imprime resultados em stdout se bem-sucedido.
# Retorna não-zero se falhar.
# Implementa o loop de evolução do --max-evolutions reutilizando
# classify_feedback/evolve_query (sourceadas de brave-search.sh).
try_brave_direct() {
  # Verifica pré-requisitos básicos (curl/jq/python3 já foram checados em
  # check_deps, no início do script)
  if [[ -z "${BRAVE_API_KEY:-}" ]]; then
    echo "[search.sh] Tier 2 indisponível: BRAVE_API_KEY não definida." >&2
    return 1
  fi

  # Verifica se a função foi carregada (via source no topo do script)
  if ! declare -f search_brave_api &>/dev/null; then
    echo "[search.sh] Tier 2 indisponível: search_brave_api() não foi definida após source." >&2
    return 1
  fi

  # Prepara ambiente para search_brave_api
  local search_out_file all_tmp
  search_out_file="$(mktemp)"
  all_tmp="$(mktemp)"
  export SEARCH_OUT_FILE="$search_out_file"
  export API_URL="${BRAVE_API_URL:-https://api.search.brave.com/res/v1/web/search}"

  # Loop de evolução: 1ª busca usa a query original; cada iteração classifica
  # o feedback (empty/few/lowq/good) e evolui a query até --max-evolutions.
  local -a queries_done=( "$QUERY" )
  local -a query_evolutions=()
  local i q fb next results api_rc
  for (( i = 0; i <= MAX_EVOLUTIONS; i++ )); do
    q="${queries_done[$i]}"
    set +e
    search_brave_api "$q"
    api_rc=$?
    set -e
    if [[ $api_rc -ne 0 ]]; then
      echo "[search.sh] Tier 2 (Brave) falhou na evolução $i com código $api_rc." >&2
      rm -f "$all_tmp" "$search_out_file"
      return 1
    fi
    results="$(cat "$search_out_file")"
    echo "$results" >> "$all_tmp"

    if [[ $i -lt $MAX_EVOLUTIONS ]]; then
      sleep "${QUERY_INTERVAL:-1.1}"
      fb="$(classify_feedback "$results")"
      next="$(evolve_query "$q" "$(( i + 1 ))" "$fb")"

      # Evita repetir uma query já usada (loop de evolução)
      local dup=0 tries=0 used
      while (( tries < 3 )); do
        dup=0
        for used in "${queries_done[@]}"; do
          if [[ "$next" == "$used" ]]; then dup=1; break; fi
        done
        (( dup == 0 )) && break
        next="${next} overview"
        tries=$(( tries + 1 ))
      done
      if (( dup == 1 )); then
        echo "AVISO: evolução não produziu query nova; parando após $(( i + 1 )) busca(s)." >&2
        break
      fi
      queries_done+=( "$next" )
      query_evolutions+=( "$next" )
    fi
  done

  # Consolida todos os resultados e deduplica por URL (primeira ocorrência vence)
  local merged unique
  merged="$(jq -s 'add' "$all_tmp")"
  unique="$(echo "$merged" | jq 'unique_by(.url)')"
  rm -f "$all_tmp" "$search_out_file"

  if [[ -z "$unique" ]] || [[ "$unique" == "[]" ]]; then
    echo "[search.sh] Tier 2 (Brave) retornou 0 resultados." >&2
    return 1
  fi

  # Emite resultado
  local duration_ms end_ms start_ms qe_json cr_json
  end_ms="$(now_ms)"
  start_ms="${_search_start_ms:-$end_ms}"
  duration_ms=$(( end_ms - start_ms ))

  qe_json="[]"
  if (( ${#query_evolutions[@]} > 0 )); then
    qe_json="$(printf '%s\n' "${query_evolutions[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')"
  fi
  cr_json="null"
  if [[ "${LAST_CREDITS:-}" =~ ^[0-9]+$ ]]; then cr_json="$LAST_CREDITS"; fi

  if (( JSON_OUT )); then
    json_report "$unique" "$duration_ms" "brave" "" "$qe_json" "$cr_json"
  else
    human_report "$unique" "$duration_ms" "brave"
  fi

  return 0
}

# --- Tier 3: DuckDuckGo keyless -------------------------------------------------
# Sempre tentado por último. Usa a DuckDuckGo Instant Answer API.
# A API retorna Abstract, RelatedTopics, e Results (instante answers + tópicos).
# Nem toda query tem resultados — é um fallback best-effort sem chave.
try_ddg_keyless() {
  echo "[search.sh] Tier 3 (DuckDuckGo keyless) — fallback final." >&2

  local encoded_q
  encoded_q="$(urlencode "$QUERY")"

  local ddg_out ddg_rc
  set +e
  ddg_out="$(curl -s --max-time "$TIMEOUT" \
    "https://api.duckduckgo.com/?q=${encoded_q}&format=json&no_html=1&skip_disambig=1" \
    2>/dev/null)"
  ddg_rc=$?
  set -e

  if [[ $ddg_rc -ne 0 ]]; then
    echo "ERRO: falha ao chamar DuckDuckGo API (curl exit $ddg_rc)." >&2
    return 1
  fi
  if [[ -z "$ddg_out" ]]; then
    echo "[search.sh] DuckDuckGo API retornou resposta vazia." >&2
    ddg_out='{}'
  fi

  # Constrói array de resultados normalizados a partir da resposta DDG
  # A API retorna: Abstract, AbstractText, AbstractURL, Heading,
  #                RelatedTopics[], Results[]
  local results
  if command -v jq &>/dev/null; then
    results="$(echo "$ddg_out" | jq -c '
      # Abstract como primeiro resultado (se existir)
      (if (.Abstract // "") != "" then
        [{
          title: (.Heading // .Abstract),
          url: (.AbstractURL // ""),
          description: (.AbstractText // .Abstract),
          published: "",
          source: "ddg"
        }]
      else [] end) as $abstract |
      # RelatedTopics
      ([.RelatedTopics // [] | .[] | select(.Text and .Text != "") | {
        title: (.Text | split(" - ")[0]),
        url: (.FirstURL // ""),
        description: .Text,
        published: "",
        source: "ddg"
      }]) as $topics |
      # Results (instant answers, disambiguation)
      ([.Results // [] | .[] | select(.Text and .Text != "") | {
        title: (.Text | split(" - ")[0]),
        url: (.FirstURL // ""),
        description: .Text,
        published: "",
        source: "ddg"
      }]) as $results |
      ($abstract + $topics + $results)
      | unique_by(.url)
      | .[0:'"${COUNT}"']' 2>/dev/null)"
  else
    # Fallback sem jq: parse via python3
    results="$(echo "$ddg_out" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    out = []
    # Abstract
    if d.get('Abstract') and str(d['Abstract']).strip():
        title = d.get('Heading') or d['Abstract']
        url = d.get('AbstractURL') or ''
        desc = d.get('AbstractText') or d['Abstract']
        out.append({'title': str(title)[:200], 'url': str(url), 'description': str(desc)[:600], 'published': '', 'source': 'ddg'})
    # RelatedTopics
    for t in d.get('RelatedTopics') or []:
        if isinstance(t, dict) and t.get('Text'):
            title = t['Text'].split(' - ')[0] if ' - ' in t['Text'] else t['Text']
            out.append({'title': str(title)[:200], 'url': str(t.get('FirstURL', '')), 'description': str(t['Text'])[:600], 'published': '', 'source': 'ddg'})
    # Results
    for t in d.get('Results') or []:
        if isinstance(t, dict) and t.get('Text'):
            title = t['Text'].split(' - ')[0] if ' - ' in t['Text'] else t['Text']
            out.append({'title': str(title)[:200], 'url': str(t.get('FirstURL', '')), 'description': str(t['Text'])[:600], 'published': '', 'source': 'ddg'})
    # Dedup by URL
    seen = set()
    dedup = []
    for r in out:
        if r['url'] not in seen:
            seen.add(r['url'])
            dedup.append(r)
    # Limit by COUNT
    print(json.dumps(dedup[:${COUNT}]))
except Exception as e:
    print('[]', file=sys.stderr)
    print('[]')
" 2>/dev/null)"
  fi

  local duration_ms end_ms start_ms
  end_ms="$(now_ms)"
  start_ms="${_search_start_ms:-$end_ms}"
  duration_ms=$(( end_ms - start_ms ))

  if [[ -z "$results" ]] || [[ "$results" == "[]" ]]; then
    echo "[search.sh] DuckDuckGo não retornou instant answers para esta query (esperado para queries genéricas — é Instant Answer, não full-text)." >&2
    # Toda a cadeia vazia: ainda emite o relatório (vazio) mas sai 1 —
    # o orquestrador precisa distinguir "sem matches" de "tudo falhou".
    if (( JSON_OUT )); then
      json_report "[]" "$duration_ms" "ddg"
    else
      human_report "[]" "$duration_ms" "ddg"
    fi
    return 1
  fi

  if (( JSON_OUT )); then
    json_report "$results" "$duration_ms" "ddg"
  else
    human_report "$results" "$duration_ms" "ddg"
  fi

  return 0
}

# --- Main ----------------------------------------------------------------------
main() {
  parse_args "$@"
  check_deps
  load_brief_file
  validate

  local _search_start_ms
  _search_start_ms="$(now_ms)"
  export _search_start_ms

  # --- Tier 1: surf-skill (a própria função decide se o binário existe) ---
  if try_surf_skill; then
    return 0
  fi
  echo "[search.sh] Tier 1 (surf-skill) falhou, caindo para Tier 2..." >&2

  # --- Tier 2: Brave API ---
  if [[ -n "${BRAVE_API_KEY:-}" ]]; then
    if try_brave_direct; then
      return 0
    fi
    echo "[search.sh] Tier 2 (Brave) falhou, caindo para Tier 3..." >&2
  else
    echo "[search.sh] BRAVE_API_KEY não definida, pulando Tier 2." >&2
  fi

  # --- Tier 3: DuckDuckGo (fallback final; conectividade garantida, cobertura
  # limitada a instant answers — pode retornar vazio → exit 1) ---
  try_ddg_keyless
}

main "$@"
