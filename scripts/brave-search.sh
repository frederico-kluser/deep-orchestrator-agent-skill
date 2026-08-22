#!/usr/bin/env bash
# =============================================================================
# brave-search.sh — Wrapper da Brave Search API para o deep-orchestrator-agent-skill
# -----------------------------------------------------------------------------
# Substitui o surf-search-normal usando diretamente a API do Brave Search,
# permitindo que os sub-agentes do orquestrador pesquisem sem o CLI surf-ai.
#
# Uso:
#   brave-search.sh [OPTS] "<query>"
#   brave-search.sh --brief-file /tmp/brief.json
#
# Interface similar ao surf-search-normal (--task, --goal, --insights,
# --deliverable, --brief-file) para facilitar a migração dos sub-agentes.
#
# Evolução de perguntas: a primeira busca usa a query original; os resultados
# são analisados (vazios / poucos / baixa qualidade / bons) e a query é
# reformulada heuristicamente até --max-evolutions; tudo é consolidado com
# deduplicação por URL (primeira ocorrência vence).
# =============================================================================

set -euo pipefail

# --- Configuração -------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
API_URL="${BRAVE_API_URL:-https://api.search.brave.com/res/v1/web/search}"
QUERY_INTERVAL="${BRAVE_QUERY_INTERVAL:-1.1}"   # 1 query/segundo (conservador)
DEFAULT_TIMEOUT=30
DEFAULT_COUNT=10
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

# Últimos valores de crédito/rate-limit vistos em cada chamada à API
LAST_CREDITS=""
LAST_RATE_REMAINING=""
LAST_RATE_RESET=""
LAST_BILLING=""
LAST_HTTP=""

# Arquivos temporários globais (limpos no EXIT — o trap é instalado apenas
# quando executado como script principal; quando sourceado (ex.: pelo
# search.sh), NÃO instala, para não vazar para o processo do chamador)
ALL_TMP=""
SEARCH_OUT_FILE=""

# --- Ajuda --------------------------------------------------------------------
usage() {
  cat <<EOF
Uso: $SCRIPT_NAME [OPTS] "<query>"

Wrapper da Brave Search API (substitui o surf-search-normal).

ARGUMENTOS
  "<query>"                 A pergunta/tópico a pesquisar (obrigatório,
                            a menos que --brief-file seja usado)

OPÇÕES
  --task "<texto>"          Contexto da tarefa em andamento
  --goal "<texto>"          Objetivo específico desta busca
  --insights "<texto>"      Premissas a verificar (hunches que devem ser validados)
  --deliverable "<texto>"   Formato esperado da resposta
  --brief-file <arquivo>    JSON com {question, task, goal, insights, deliverable};
                            flags individuais sobrescrevem o arquivo
  --count N                 Resultados por busca (default $DEFAULT_COUNT, máx 20)
  --freshness <v>           pd | pw | pm | py (dia/semana/mês/ano) ou vazio
  --country <cc>            Código de país de 2 letras (default: vazio = todos)
  --search-lang <lang>      Idioma dos resultados (default: $DEFAULT_SEARCH_LANG)
  --offset N                Deslocamento de paginação (default 0, máx 9)
  --result-filter <lista>   web,news,videos,images (default: default da API)
  --max-evolutions N        Quantas evoluções de query (default $DEFAULT_MAX_EVOLUTIONS, máx 5)
  --dev-mode                Adiciona contexto de desenvolvimento de software às queries
  --timeout N               Timeout por chamada em segundos (default $DEFAULT_TIMEOUT)
  --json                    Saída em JSON puro (avisos vão para stderr)
  -h, --help                Mostra esta ajuda

AMBIENTE
  BRAVE_API_KEY             Chave da Brave Search API (obrigatória; header
                            X-Subscription-Token). Se ausente: erro + exit 2.
  BRAVE_API_URL             Override do endpoint (uso interno/testes)
  BRAVE_QUERY_INTERVAL      Segundos de espera entre chamadas (default 1.1)

SAÍDA (--json)
  {query_original, query_evolution[], results[{title,url,description,published,source}],
   total_results, credits_remaining,
   diagnostics{evolutions, total_queries, unique_results, duration_ms}}

EXIT CODES
  0 sucesso · 1 erro de busca/API · 2 erro de configuração/uso
EOF
}

# --- Dependências --------------------------------------------------------------
# Verificadas UMA vez, no início (antes de qualquer uso de jq/curl,
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
  if [[ -z "${BRAVE_API_KEY:-}" ]]; then
    echo "ERRO: BRAVE_API_KEY não está definida." >&2
    echo "      Exporte a chave da Brave Search API (https://api-dashboard.search.brave.com) antes de rodar $SCRIPT_NAME." >&2
    echo "      Ex.: export BRAVE_API_KEY=BSA_xxxx" >&2
    exit 2
  fi
  # Dependências (curl/jq/python3) já foram verificadas em check_deps, no início.
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

# header_val <arquivo-headers> <nome> → valor do header (ou vazio; sempre exit 0)
header_val() {
  local f="$1" name="$2"
  grep -i "^${name}:" "$f" 2>/dev/null \
    | head -n 1 \
    | cut -d: -f2- \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\r$//' \
    || true
}

# credits_from_headers <arquivo-headers> → créditos restantes (ou vazio)
# Na resposta REAL da Brave (verificado ao vivo 14/08/2026) o header
# X-Credit-Remaining NÃO existe — só X-RateLimit-{Limit,Remaining,Reset},
# com o par "por segundo, por mês". O 2º valor de X-RateLimit-Remaining é a
# quota mensal restante (ex.: "1, 950" → 950). O ramo X-Credit-Remaining é
# mantido apenas como fallback defensivo.
credits_from_headers() {
  local f="$1" v m
  v="$(header_val "$f" "X-Credit-Remaining")"
  if [[ -n "$v" ]] && [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "$v"
    return
  fi
  v="$(header_val "$f" "X-RateLimit-Remaining")"
  if [[ -n "$v" ]]; then
    m="$(echo "$v" | awk -F, '{ if (NF >= 2) { gsub(/[^0-9]/, "", $2); print $2 } else { gsub(/[^0-9]/, "", $1); print $1 } }')"
    if [[ -n "$m" ]] && [[ "$m" =~ ^[0-9]+$ ]]; then
      echo "$m"
      return
    fi
  fi
  echo ""
}

api_error_message() { # <arquivo-body> → mensagem de erro da API (ou vazio)
  local f="$1"
  jq -r '.message // .error.message // .error // .type // empty' "$f" 2>/dev/null | head -n 1 || true
}

# --- Chamada à API -------------------------------------------------------------
# search_brave "<query>" → imprime array JSON de resultados normalizados.
# Também atualiza LAST_* com créditos/rate-limit vistos nos headers.
# Hard-fail: exit 1 (rede/API/429 sem retry) ou exit 2 (401 = chave inválida).
search_brave() {
  local query="$1"
  local retried="${2:-0}"
  local body headers curl_err http_code rc err_msg results
  body="$(mktemp)"
  headers="$(mktemp)"
  curl_err="$(mktemp)"

  local args=( -sS --max-time "$TIMEOUT" -G "$API_URL"
    -H "Accept: application/json"
    -H "Accept-Encoding: gzip"
    -H "X-Subscription-Token: ${BRAVE_API_KEY}"
    --compressed
    --data-urlencode "q=$query"
    --data-urlencode "count=$COUNT"
    --data-urlencode "offset=$OFFSET"
    -D "$headers"
    -o "$body"
    -w '%{http_code}' )
  [[ -n "$COUNTRY" ]]       && args+=( --data-urlencode "country=$COUNTRY" )
  [[ -n "$SEARCH_LANG" ]]   && args+=( --data-urlencode "search_lang=$SEARCH_LANG" )
  [[ -n "$FRESHNESS" ]]     && args+=( --data-urlencode "freshness=$FRESHNESS" )
  [[ -n "$RESULT_FILTER" ]] && args+=( --data-urlencode "result_filter=$RESULT_FILTER" )

  set +e
  http_code="$(curl "${args[@]}" 2>"$curl_err")"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "ERRO: falha de rede ao chamar a Brave API (curl exit $rc): $(cat "$curl_err")" >&2
    rm -f "$body" "$headers" "$curl_err"
    exit 1
  fi

  LAST_HTTP="${http_code:-}"
  LAST_CREDITS="$(credits_from_headers "$headers")"
  LAST_RATE_REMAINING="$(header_val "$headers" "X-RateLimit-Remaining")"
  LAST_RATE_RESET="$(header_val "$headers" "X-RateLimit-Reset")"
  # billing-status: header NÃO existe na resposta real da Brave (verificado
  # 14/08/2026); mantido como opcional/defensivo — na prática sai vazio.
  LAST_BILLING="$(header_val "$headers" "billing-status")"

  case "${http_code:-}" in
    200) ;;
    401)
      echo "ERRO: chave inválida (HTTP 401). Confira BRAVE_API_KEY." >&2
      rm -f "$body" "$headers" "$curl_err"
      exit 2
      ;;
    402|403)
      err_msg="$(api_error_message "$body")"
      echo "ERRO: problema de faturamento/créditos na Brave API (HTTP $http_code): ${err_msg:-sem mensagem no corpo}" >&2
      rm -f "$body" "$headers" "$curl_err"
      exit 1
      ;;
    429)
      # Tenta recuperar de rate limit: espera o reset (até 10s) e repete no máx 1x
      local wait_s="${LAST_RATE_RESET%%,*}"
      wait_s="${wait_s//[^0-9]/}"
      if (( retried < 1 )) && [[ -n "$wait_s" ]] && (( wait_s > 0 )) && (( wait_s <= 10 )); then
        echo "AVISO: rate limit atingido (HTTP 429); aguardando ${wait_s}s e tentando de novo..." >&2
        sleep "$wait_s"
        rm -f "$body" "$headers" "$curl_err"
        search_brave "$query" 1
        return 0
      fi
      if (( retried >= 1 )); then
        echo "ERRO: rate limit da Brave API (HTTP 429) persistiu após 1 tentativa de retry." >&2
      else
        echo "ERRO: rate limit da Brave API (HTTP 429) e reset indisponível/inválido." >&2
      fi
      rm -f "$body" "$headers" "$curl_err"
      exit 1
      ;;
    *)
      err_msg="$(api_error_message "$body")"
      echo "ERRO: resposta inesperada da Brave API (HTTP $http_code): ${err_msg:-corpo não-JSON}" >&2
      rm -f "$body" "$headers" "$curl_err"
      exit 1
      ;;
  esac

  # Corpo → array de resultados normalizados
  if [[ -s "$body" ]]; then
    if ! jq -e . "$body" >/dev/null 2>&1; then
      echo "AVISO: HTTP 200 mas o corpo da resposta não é JSON válido (proxy/CDN/challenge?). Retornando 0 resultados (degradação)." >&2
      results="[]"
    else
      results="$(jq -c '[.web.results // [] | .[] | select(.url != null and .url != "") | {title: (.title // ""), url: .url, description: (.description // ""), published: (.page_age // .age // ""), source: "brave"}]' "$body")"
    fi
  else
    results="[]"
  fi
  rm -f "$body" "$headers" "$curl_err"
  echo "$results" > "$SEARCH_OUT_FILE"
}

# search_brave_api(): versão source-able de search_brave().
# Idêntica em lógica, mas retorna códigos de status em vez de chamar exit.
# Retorna: 0 = sucesso (resultados em $SEARCH_OUT_FILE), 1 = erro, 2 = erro de auth.
# Usada por search.sh (Tier 2 do smart wrapper) via source.
search_brave_api() {
  local query="$1"
  local retried="${2:-0}"
  local body headers curl_err http_code rc err_msg results
  body="$(mktemp)"
  headers="$(mktemp)"
  curl_err="$(mktemp)"

  local args=( -sS --max-time "$TIMEOUT" -G "$API_URL"
    -H "Accept: application/json"
    -H "Accept-Encoding: gzip"
    -H "X-Subscription-Token: ${BRAVE_API_KEY}"
    --compressed
    --data-urlencode "q=$query"
    --data-urlencode "count=$COUNT"
    --data-urlencode "offset=$OFFSET"
    -D "$headers"
    -o "$body"
    -w '%{http_code}' )
  [[ -n "$COUNTRY" ]]       && args+=( --data-urlencode "country=$COUNTRY" )
  [[ -n "$SEARCH_LANG" ]]   && args+=( --data-urlencode "search_lang=$SEARCH_LANG" )
  [[ -n "$FRESHNESS" ]]     && args+=( --data-urlencode "freshness=$FRESHNESS" )
  [[ -n "$RESULT_FILTER" ]] && args+=( --data-urlencode "result_filter=$RESULT_FILTER" )

  set +e
  http_code="$(curl "${args[@]}" 2>"$curl_err")"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "ERRO: falha de rede ao chamar a Brave API (curl exit $rc): $(cat "$curl_err")" >&2
    rm -f "$body" "$headers" "$curl_err"
    return 1
  fi

  LAST_HTTP="${http_code:-}"
  LAST_CREDITS="$(credits_from_headers "$headers")"
  LAST_RATE_REMAINING="$(header_val "$headers" "X-RateLimit-Remaining")"
  LAST_RATE_RESET="$(header_val "$headers" "X-RateLimit-Reset")"
  # billing-status: header NÃO existe na resposta real da Brave (verificado
  # 14/08/2026); mantido como opcional/defensivo — na prática sai vazio.
  LAST_BILLING="$(header_val "$headers" "billing-status")"

  case "${http_code:-}" in
    200) ;;
    401)
      echo "ERRO: chave inválida (HTTP 401). Confira BRAVE_API_KEY." >&2
      rm -f "$body" "$headers" "$curl_err"
      return 2
      ;;
    402|403)
      err_msg="$(api_error_message "$body")"
      echo "ERRO: problema de faturamento/créditos na Brave API (HTTP $http_code): ${err_msg:-sem mensagem no corpo}" >&2
      rm -f "$body" "$headers" "$curl_err"
      return 1
      ;;
    429)
      local wait_s="${LAST_RATE_RESET%%,*}"
      wait_s="${wait_s//[^0-9]/}"
      if (( retried < 1 )) && [[ -n "$wait_s" ]] && (( wait_s > 0 )) && (( wait_s <= 10 )); then
        echo "AVISO: rate limit atingido (HTTP 429); aguardando ${wait_s}s e tentando de novo..." >&2
        sleep "$wait_s"
        rm -f "$body" "$headers" "$curl_err"
        search_brave_api "$query" 1
        return $?
      fi
      if (( retried >= 1 )); then
        echo "ERRO: rate limit da Brave API (HTTP 429) persistiu após 1 tentativa de retry." >&2
      else
        echo "ERRO: rate limit da Brave API (HTTP 429) e reset indisponível/inválido." >&2
      fi
      rm -f "$body" "$headers" "$curl_err"
      return 1
      ;;
    *)
      err_msg="$(api_error_message "$body")"
      echo "ERRO: resposta inesperada da Brave API (HTTP $http_code): ${err_msg:-corpo não-JSON}" >&2
      rm -f "$body" "$headers" "$curl_err"
      return 1
      ;;
  esac

  # Corpo → array de resultados normalizados
  if [[ -s "$body" ]]; then
    if ! jq -e . "$body" >/dev/null 2>&1; then
      echo "AVISO: HTTP 200 mas o corpo da resposta não é JSON válido (proxy/CDN/challenge?). Retornando 0 resultados (degradação)." >&2
      results="[]"
    else
      results="$(jq -c '[.web.results // [] | .[] | select(.url != null and .url != "") | {title: (.title // ""), url: .url, description: (.description // ""), published: (.page_age // .age // ""), source: "brave"}]' "$body")"
    fi
  else
    results="[]"
  fi
  rm -f "$body" "$headers" "$curl_err"
  echo "$results" > "$SEARCH_OUT_FILE"
  return 0
}

# --- Heurísticas de evolução ---------------------------------------------------
# classify_feedback <results-json> → "empty" | "few" | "lowq" | "good"
classify_feedback() {
  local arr="$1" total lowq half
  total="$(echo "$arr" | jq 'length')"
  if [[ "$total" == "0" ]]; then
    echo "empty"
    return
  fi
  # half com mínimo de 1: com --count 1, um único resultado NÃO é classificado
  # como "lowq" (half=0 faria lowq > 0 sempre que a descrição viesse vazia)
  half=$(( COUNT / 2 ))
  (( half < 1 )) && half=1
  if (( total < half )); then
    echo "few"
    return
  fi
  lowq="$(echo "$arr" | jq '[.[] | select((.description | length) == 0 or (.title == .url))] | length')"
  if (( lowq > half )); then
    echo "lowq"
    return
  fi
  echo "good"
}

# evolve_query "<query>" <iteração 1-based> <feedback> → nova query
evolve_query() {
  local q="$1" iter="$2" fb="$3"
  local words=() n
  q="${q//\"/}"
  q="${q//\'/}"
  # read -ra divide por IFS sem glob expansion: query com "*" não vira
  # arquivos do cwd (words=( $q ) expandiria globs)
  IFS=' ' read -r -a words <<< "$q"
  n="${#words[@]}"

  case "$fb" in
    empty)
      # Query restritiva demais: simplifica (corta palavras finais)
      if (( n > 3 )); then
        echo "${words[@]:0:3}"
      else
        echo "$q overview"
      fi
      ;;
    few)
      # Poucos resultados: alarga (remove a última palavra)
      if (( n > 1 )); then
        echo "${words[@]:0:$(( n - 1 ))}"
      else
        echo "$q overview"
      fi
      ;;
    lowq)
      # Muitos resultados genéricos: pede fontes de maior qualidade
      echo "$q best practice"
      ;;
    good)
      # Bons resultados: evolui para um ângulo diferente
      local terms=()
      if (( DEV_MODE )); then
        terms=( "documentation example" "API reference" "best practice 2025 2026" "github" "tutorial" )
      else
        terms=( "guide" "tutorial" "example" "overview" )
      fi
      local idx=$(( (iter - 1) % ${#terms[@]} ))
      echo "$q ${terms[$idx]}"
      ;;
  esac
}

# --- Saída humana --------------------------------------------------------------
human_report() {
  local unique="$1"
  local duration_ms="$2"
  local total_queries="$3"
  local credits_log=("${@:4}")
  local i=1 trail=""

  echo "# Search: $QUERY"
  echo
  echo "**Task:** ${TASK:-—}"
  echo "**Goal:** ${GOAL:-—}"
  echo "**Insights:** ${INSIGHTS:-—}"
  echo "**Deliverable:** ${DELIVERABLE:-—}"
  echo
  if (( ${#query_evolutions[@]} > 0 )); then
    trail="\"$QUERY\""
    local q
    for q in "${query_evolutions[@]}"; do trail="${trail} → \"$q\""; done
    echo "**Evolução das queries:** ${trail}"
    echo
  fi

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
  done < <(echo "$unique" | jq -c '.[]')

  if [[ "$i" == "1" ]]; then
    echo "_Nenhum resultado encontrado após $total_queries busca(s)._"
    echo
  fi

  # Sumário: evolução, créditos por busca, rate limit, billing
  local credits_note="" j=0 c
  for c in "${credits_log[@]}"; do
    j=$(( j + 1 ))
    if [[ -n "$c" ]] && [[ "$c" != "?" ]]; then
      credits_note="${credits_note}busca $j: ${c} créditos · "
    fi
  done
  [[ -n "$credits_note" ]] && credits_note="${credits_note% · }"

  echo "---"
  echo
  echo "_provider: brave · ${duration_ms}ms${credits_note:+ · ${credits_note}}${LAST_CREDITS:+ · créditos finais: ${LAST_CREDITS}}_"
  [[ -n "$LAST_RATE_REMAINING" ]] && echo "_rate limit restante: ${LAST_RATE_REMAINING}${LAST_RATE_RESET:+ · reset: ${LAST_RATE_RESET}s}_"
  [[ -n "$LAST_BILLING" ]] && echo "_billing-status: ${LAST_BILLING}_"
  echo
  echo "## Sources"
  echo "$unique" | jq -r '.[].url'
}

# --- Fluxo principal -----------------------------------------------------------
main() {
  parse_args "$@"
  check_deps
  load_brief_file
  validate

  local start_ms end_ms duration_ms
  start_ms="$(now_ms)"

  ALL_TMP="$(mktemp)"                       # acumula arrays de resultados
  local queries_done=( "$QUERY" )
  local query_evolutions=()
  local credits_log=()
  local i fb next results q

  SEARCH_OUT_FILE="$(mktemp)"
  for (( i = 0; i <= MAX_EVOLUTIONS; i++ )); do
    q="${queries_done[$i]}"
    search_brave "$q"
    results="$(cat "$SEARCH_OUT_FILE")"
    echo "$results" >> "$ALL_TMP"
    credits_log+=( "${LAST_CREDITS:-?}" )

    if [[ $i -lt $MAX_EVOLUTIONS ]]; then
      sleep "$QUERY_INTERVAL"
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
        local fallback="overview"
        (( DEV_MODE )) && fallback="github overview"
        next="${next} ${fallback}"
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

  end_ms="$(now_ms)"
  duration_ms=$(( end_ms - start_ms ))

  # Consolida todos os resultados e deduplica por URL (primeira ocorrência vence)
  local merged unique unique_count total_queries evolutions
  merged="$(jq -s 'add' "$ALL_TMP")"
  unique="$(echo "$merged" | jq 'unique_by(.url)')"
  unique_count="$(echo "$unique" | jq 'length')"
  total_queries="${#queries_done[@]}"
  evolutions="${#query_evolutions[@]}"

  local qe_json="[]"
  if (( evolutions > 0 )); then
    qe_json="$(printf '%s\n' "${query_evolutions[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')"
  fi

  local diagnostics final_json
  diagnostics="$(jq -n --argjson e "$evolutions" --argjson tq "$total_queries" --argjson u "$unique_count" --argjson d "$duration_ms" '{evolutions: $e, total_queries: $tq, unique_results: $u, duration_ms: $d}')"
  final_json="$(jq -n \
    --arg qo "$QUERY" \
    --argjson qe "$qe_json" \
    --argjson res "$unique" \
    --argjson tr "$unique_count" \
    --argjson cr "${LAST_CREDITS:-null}" \
    --argjson diag "$diagnostics" \
    '{query_original: $qo, query_evolution: $qe, results: $res, total_results: $tr, credits_remaining: $cr, diagnostics: $diag}')"

  if (( JSON_OUT )); then
    echo "$final_json"
  else
    human_report "$unique" "$duration_ms" "$total_queries" "${credits_log[@]}"
  fi

  rm -f "$ALL_TMP" "$SEARCH_OUT_FILE"
  ALL_TMP=""
  SEARCH_OUT_FILE=""
}

# Quando sourceado (ex.: por search.sh), não executar main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap '[[ -n "$ALL_TMP" ]] && rm -rf "$ALL_TMP" "$SEARCH_OUT_FILE"' EXIT
  main "$@"
fi
