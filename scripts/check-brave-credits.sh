#!/usr/bin/env bash
# =============================================================================
# check-brave-credits.sh — Verifica saldo de créditos da Brave Search API
# -----------------------------------------------------------------------------
# Faz uma query mínima (q=test, count=1) e lê os créditos dos headers de
# resposta. NA RESPOSTA REAL da Brave (verificado ao vivo 14/08/2026) o
# header X-Credit-Remaining NÃO existe — só X-RateLimit-{Limit,Remaining,
# Reset}, com o par "por segundo, por mês": usamos o 2º valor de
# X-RateLimit-Remaining (quota mensal restante). billing-status também não
# existe na prática — tratado como opcional. (O parsing de X-Credit-Remaining
# é mantido apenas como fallback defensivo para proxies/endpoints antigos.)
#
# QUANDO OS CRÉDITOS APARECEM COMO 0, uma segunda verificação é feita:
# uma busca real (count=3) para confirmar se a API está realmente bloqueada
# ou se é um plano de assinatura (onde créditos não são a métrica relevante).
# Se a busca real retornar resultados → CREDITS_OK (assinatura ativa).
#
# Cache: o resultado da verificação real é cacheado por 10 minutos em
# $TMPDIR/brave-check-cache.json. Use --no-cache para pular o cache.
#
# Uso:
#   check-brave-credits.sh [OPTS]
#
# Status: CREDITS_OK | CREDITS_LOW (<100) | NO_CREDITS (0 + busca real vazia) |
#         SUBSCRIPTION_ACTIVE (créditos zerados mas API funcional — assinatura) |
#         CREDITS_UNKNOWN | RATE_LIMITED | CONFIG_ERROR
#
# Exit codes:
#   0 = tem créditos ou assinatura ativa (CREDITS_OK/CREDITS_LOW/SUBSCRIPTION_ACTIVE/
#       CREDITS_UNKNOWN/RATE_LIMITED)
#   1 = sem créditos E busca real falhou (NO_CREDITS) ou, com --fail-fast,
#       status CREDITS_LOW/CREDITS_UNKNOWN
#   2 = erro de configuração (BRAVE_API_KEY ausente/inválida, rede, tools)
# =============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
API_URL="${BRAVE_API_URL:-https://api.search.brave.com/res/v1/web/search}"
DEFAULT_TIMEOUT=15
LOW_THRESHOLD=100
CACHE_TTL=600  # 10 minutos
CACHE_FILE="${TMPDIR:-/tmp}/brave-check-cache.json"

JSON_OUT=0
FAIL_FAST=0
NO_CACHE=0
TIMEOUT="$DEFAULT_TIMEOUT"

usage() {
  cat <<EOF
Uso: $SCRIPT_NAME [OPTS]

Verifica o saldo de créditos da Brave Search API com uma query mínima
(q=test, count=1). Sem argumentos posicionais.

Quando os créditos aparecem como 0, uma segunda verificação é feita com uma
busca real (count=3) para distinguir entre "plano gratuito esgotado" e
"plano de assinatura" (onde o header de créditos não é a métrica relevante).
Se a busca real retornar resultados → SUBSCRIPTION_ACTIVE (exit 0).

OPÇÕES
  --json         Saída em JSON parseável (sem texto em stdout)
  --fail-fast    Exit 1 para status de créditos não-confirmados
                 (CREDITS_LOW/CREDITS_UNKNOWN/NO_CREDITS); CREDITS_OK,
                 SUBSCRIPTION_ACTIVE e RATE_LIMITED seguem exit 0
  --no-cache     Ignora cache e força verificação real (se necessária)
  --timeout N    Timeout da chamada em segundos (default $DEFAULT_TIMEOUT)
  -h, --help     Mostra esta ajuda

AMBIENTE
  BRAVE_API_KEY   Chave da Brave Search API (obrigatória)
  BRAVE_API_URL   Override do endpoint (uso interno/testes)

STATUS
  CREDITS_OK           Créditos >= $LOW_THRESHOLD
  CREDITS_LOW          Créditos > 0 e < $LOW_THRESHOLD
  SUBSCRIPTION_ACTIVE  Créditos zerados mas busca real funciona (assinatura)
  NO_CREDITS           Créditos zerados E busca real vazia (plano gratuito esgotado)
  CREDITS_UNKNOWN      Sem header de créditos na resposta
  RATE_LIMITED         HTTP 429 (rate limit atingido; não confirma créditos)
  CONFIG_ERROR         Chave ausente/inválida, rede ou ferramentas

EXIT CODES
  0 tem créditos/assinatura · 1 sem créditos (ou --fail-fast) · 2 erro de configuração
EOF
}

# flag_val <flag> <args...> → valor (exit 2 se faltar — sem "unbound variable")
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
      --json)      JSON_OUT=1; shift ;;
      --fail-fast) FAIL_FAST=1; shift ;;
      --no-cache)  NO_CACHE=1; shift ;;
      --timeout)   TIMEOUT="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --timeout=*) TIMEOUT="${1#*=}"; shift ;;
      -*)
        echo "ERRO: flag desconhecida: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        echo "ERRO: argumento posicional não esperado: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
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
# Na resposta REAL da Brave (verificado 14/08/2026) X-Credit-Remaining NÃO
# existe — só X-RateLimit-{Limit,Remaining,Reset} (par "por segundo, por mês").
# Usamos o 2º valor de X-RateLimit-Remaining (quota mensal); o ramo
# X-Credit-Remaining é mantido como fallback defensivo.
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

# --- Cache ----------------------------------------------------------------------

cache_read() {
  if (( NO_CACHE )); then return 1; fi
  if [[ ! -f "$CACHE_FILE" ]]; then return 1; fi
  local age now
  if [[ "$(uname -s)" == "Darwin" ]]; then
    age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)))
  else
    age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
  fi
  if (( age > CACHE_TTL )); then
    rm -f "$CACHE_FILE"
    return 1
  fi
  return 0
}

cache_write() {
  local status="$1" detail="$2" credits="${3:-null}" http="${4:-null}"
  local rate_remaining="${5:-}" rate_reset="${6:-}" billing="${7:-}"
  jq -n \
    --arg status "$status" \
    --arg detail "$detail" \
    --argjson credits "$credits" \
    --argjson http "$http" \
    --arg rate_limit_remaining "$rate_remaining" \
    --arg rate_limit_reset "$rate_reset" \
    --arg billing_status "$billing" \
    --argjson cached_at "$(date +%s)" \
    '{status: $status, detail: $detail, credits_remaining: $credits, http_status: $http, rate_limit_remaining: $rate_remaining, rate_limit_reset: $rate_reset, billing_status: $billing_status, cached_at: $cached_at}' \
    > "$CACHE_FILE" 2>/dev/null || true
}

# --- Verificação real de funcionamento ------------------------------------------
# Faz uma busca real (q=test, count=3) para saber se a API realmente funciona.
# Isso distingue "créditos zerados em assinatura" (API funciona) de
# "créditos zerados no plano gratuito" (API bloqueada).
# Retorna 0 se a busca retornou resultados, 1 se não retornou.

real_search_works() {
  local body headers curl_err http_code rc result_count
  body="$(mktemp)"
  headers="$(mktemp)"
  curl_err="$(mktemp)"

  set +e
  http_code="$(curl -sS --max-time "$TIMEOUT" -G "$API_URL" \
    -H "Accept: application/json" \
    -H "Accept-Encoding: gzip" \
    -H "X-Subscription-Token: ${BRAVE_API_KEY}" \
    --compressed \
    --data-urlencode "q=test connectivity check" \
    --data-urlencode "count=3" \
    -D "$headers" \
    -o "$body" \
    -w '%{http_code}' 2>"$curl_err")"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]] || [[ "$http_code" != "200" ]]; then
    rm -f "$body" "$headers" "$curl_err"
    return 1
  fi

  # Conta resultados no JSON de resposta
  result_count="$(jq -r '(.web.results // .results // .data // empty | length) // 0' "$body" 2>/dev/null || echo 0)"

  # Guarda headers da busca real para enriquecer o diagnóstico
  local real_billing
  real_billing="$(header_val "$headers" "billing-status")"

  rm -f "$body" "$headers" "$curl_err"

  if [[ "$result_count" =~ ^[0-9]+$ ]] && (( result_count > 0 )); then
    # Propaga billing-status da busca real para o caller
    if [[ -n "$real_billing" ]]; then
      echo "$real_billing" > "${TMPDIR:-/tmp}/brave-real-billing.txt" 2>/dev/null || true
    fi
    return 0
  fi
  return 1
}

# --- Main -----------------------------------------------------------------------

main() {
  parse_args "$@"

  if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || (( TIMEOUT < 1 || TIMEOUT > 120 )); then
    echo "CONFIG_ERROR: --timeout deve ser um inteiro entre 1 e 120 (recebido: '$TIMEOUT')" >&2
    exit 2
  fi
  for bin in curl jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "CONFIG_ERROR: '$bin' não encontrado no PATH (necessário para $SCRIPT_NAME)." >&2
      exit 2
    fi
  done
  if [[ -z "${BRAVE_API_KEY:-}" ]]; then
    echo "CONFIG_ERROR: BRAVE_API_KEY não está definida. Exporte a chave da Brave Search API." >&2
    exit 2
  fi

  # --- Cache hit (sem --no-cache) ---
  if cache_read; then
    if (( JSON_OUT )); then
      cat "$CACHE_FILE"
    else
      local c_status c_detail
      c_status="$(jq -r '.status' "$CACHE_FILE")"
      c_detail="$(jq -r '.detail' "$CACHE_FILE")"
      echo "$c_status — $c_detail"
      local c_rr
      c_rr="$(jq -r '.rate_limit_remaining // empty' "$CACHE_FILE" 2>/dev/null || true)"
      [[ -n "$c_rr" ]] && echo "Rate limit restante: $c_rr"
      local c_bs
      c_bs="$(jq -r '.billing_status // empty' "$CACHE_FILE" 2>/dev/null || true)"
      [[ -n "$c_bs" ]] && echo "Billing status: $c_bs"
    fi
    local c_exit
    c_exit="$(jq -r '.status' "$CACHE_FILE")"
    case "$c_exit" in
      NO_CREDITS) exit 1 ;;
      CONFIG_ERROR) exit 2 ;;
      CREDITS_LOW|CREDITS_UNKNOWN)
        # Mesma lógica do fluxo sem cache: com --fail-fast, créditos
        # não-confirmados saem 1 (cache-hit não pode ignorar o --fail-fast)
        if (( FAIL_FAST )); then
          exit 1
        fi
        exit 0
        ;;
      *) exit 0 ;;
    esac
  fi

  # --- Query mínima para checar headers ---
  local body headers curl_err http_code rc
  body="$(mktemp)"
  headers="$(mktemp)"
  curl_err="$(mktemp)"
  trap 'rm -f "$body" "$headers" "$curl_err" "${TMPDIR:-/tmp}/brave-real-billing.txt"' EXIT

  set +e
  http_code="$(curl -sS --max-time "$TIMEOUT" -G "$API_URL" \
    -H "Accept: application/json" \
    -H "Accept-Encoding: gzip" \
    -H "X-Subscription-Token: ${BRAVE_API_KEY}" \
    --compressed \
    --data-urlencode "q=test" \
    --data-urlencode "count=1" \
    -D "$headers" \
    -o "$body" \
    -w '%{http_code}' 2>"$curl_err")"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "CONFIG_ERROR: falha de rede ao chamar a Brave API (curl exit $rc): $(cat "$curl_err")" >&2
    exit 2
  fi

  local credits rate_remaining rate_reset billing
  credits="$(credits_from_headers "$headers")"
  rate_remaining="$(header_val "$headers" "X-RateLimit-Remaining")"
  rate_reset="$(header_val "$headers" "X-RateLimit-Reset")"
  billing="$(header_val "$headers" "billing-status")"

  local status detail

  case "${http_code:-}" in
    200)
      if [[ -n "$credits" ]] && [[ "$credits" =~ ^[0-9]+$ ]]; then
        if (( credits == 0 )); then
          # --- Créditos zerados: verificar se é assinatura ativa ---
          #    Limpa cache anterior de billing da busca real
          rm -f "${TMPDIR:-/tmp}/brave-real-billing.txt"

          if real_search_works; then
            status="SUBSCRIPTION_ACTIVE"
            # Pega billing-status da busca real, se disponível
            local real_bill
            real_bill="$(cat "${TMPDIR:-/tmp}/brave-real-billing.txt" 2>/dev/null || true)"
            if [[ -n "$real_bill" ]]; then
              billing="$real_bill"
              detail="créditos zerados mas API funcional — assinatura ativa (billing: $real_bill)"
            else
              detail="créditos zerados mas API funcional — assinatura ativa"
            fi
          else
            status="NO_CREDITS"
            detail="créditos zerados e busca real sem resultados — plano gratuito esgotado. Recarregue em https://api.search.brave.com/app/plans"
          fi
        elif (( credits < LOW_THRESHOLD )); then
          status="CREDITS_LOW"
          detail="${credits} créditos restantes (< ${LOW_THRESHOLD})"
        else
          status="CREDITS_OK"
          detail="${credits} créditos restantes"
        fi
      else
        # Sem header de créditos — tenta busca real para ver se funciona
        rm -f "${TMPDIR:-/tmp}/brave-real-billing.txt"
        if real_search_works; then
          status="CREDITS_OK"
          local real_bill2
          real_bill2="$(cat "${TMPDIR:-/tmp}/brave-real-billing.txt" 2>/dev/null || true)"
          if [[ -n "$real_bill2" ]]; then
            billing="$real_bill2"
            detail="sem header de créditos, mas API funcional — assinatura ativa (billing: $real_bill2)"
          else
            detail="sem header de créditos, mas API funcional — assumindo OK"
          fi
        else
          status="CREDITS_UNKNOWN"
          detail="API respondeu 200 mas nenhum header de créditos encontrado e busca real falhou"
        fi
      fi
      ;;
    401)
      status="CONFIG_ERROR"
      detail="chave inválida (HTTP 401) — confira BRAVE_API_KEY"
      ;;
    402|403)
      status="NO_CREDITS"
      detail="problema de faturamento (HTTP ${http_code}): $(api_error_message "$body")"
      ;;
    429)
      status="RATE_LIMITED"
      detail="rate limit atingido (HTTP 429); reset: ${rate_reset:-desconhecido}"
      ;;
    *)
      status="CREDITS_UNKNOWN"
      detail="resposta inesperada (HTTP ${http_code}): $(api_error_message "$body")"
      ;;
  esac

  # --- Cache do resultado ---
  cache_write "$status" "$detail" "${credits:-null}" "${http_code:-null}" \
    "$rate_remaining" "$rate_reset" "$billing"

  # --- Exit code ---
  local exit_code=0
  case "$status" in
    NO_CREDITS)   exit_code=1 ;;
    CONFIG_ERROR) exit_code=2 ;;
    CREDITS_OK|SUBSCRIPTION_ACTIVE|RATE_LIMITED) exit_code=0 ;;
    *)
      # CREDITS_LOW/CREDITS_UNKNOWN: falham apenas com --fail-fast
      if (( FAIL_FAST )); then exit_code=1; fi
      ;;
  esac

  # --- Output ---
  if (( JSON_OUT )); then
    jq -n \
      --arg status "$status" \
      --arg detail "$detail" \
      --argjson credits "${credits:-null}" \
      --argjson http "${http_code:-null}" \
      --arg rate_limit_limit "$(header_val "$headers" "X-RateLimit-Limit")" \
      --arg rate_limit_remaining "$rate_remaining" \
      --arg rate_limit_reset "$rate_reset" \
      --arg billing_status "$billing" \
      '{status: $status, detail: $detail, credits_remaining: $credits, http_status: $http, rate_limit_limit: $rate_limit_limit, rate_limit_remaining: $rate_limit_remaining, rate_limit_reset: $rate_limit_reset, billing_status: $billing_status}'
  else
    echo "$status — $detail"
    if [[ -n "$rate_remaining" ]]; then
      echo "Rate limit restante: $rate_remaining (reset: ${rate_reset:-?}s)"
    fi
    [[ -n "$billing" ]] && echo "Billing status: $billing"
  fi

  exit "$exit_code"
}

main "$@"
