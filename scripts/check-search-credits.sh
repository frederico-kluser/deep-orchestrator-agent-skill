#!/usr/bin/env bash
# =============================================================================
# check-search-credits.sh — Verifica disponibilidade de TODAS as camadas de busca
# -----------------------------------------------------------------------------
# Substitui check-brave-credits.sh como verificador pré-onda do orquestrador.
# Verifica surf-skill (Tier 1), Brave API (Tier 2) e DuckDuckGo keyless (Tier 3).
#
# Uso:
#   check-search-credits.sh [--fail-fast] [--json]
#
# Camadas verificadas (em ordem de prioridade):
#   Tier 1 — surf-skill:    surf-search-normal + surf-free-skill (AI-powered multi-provider)
#   Tier 2 — Brave API:     Brave Search API com chave de assinatura (legacy)
#   Tier 3 — Keyless DDG:   DuckDuckGo Instant Answer API (fallback sem chave)
#
# Exit codes:
#   0 = Tier 1 ou Tier 2 disponível (pesquisa completa possível)
#   1 = Apenas Tier 3 disponível (pesquisa limitada mas funcional)
#   2 = NADA disponível (sem rede? erro crítico)
#
# Opções:
#   --fail-fast   Sai no primeiro tier funcional (não testa tiers inferiores)
#   --json        Output em JSON estruturado (texto de diagnóstico vai para stderr)
# =============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
API_URL="${BRAVE_API_URL:-https://api.search.brave.com/res/v1/web/search}"
DEFAULT_TIMEOUT=15
DDG_CHECK_URL="https://api.duckduckgo.com/?q=test&format=json"

# --- Estado global ---
JSON_OUT=0
FAIL_FAST=0
TIMEOUT="$DEFAULT_TIMEOUT"

# ---------------------------------------------------------------------------
# Ajuda
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Uso: $SCRIPT_NAME [OPTS]

Verificador pré-onda do deep-orchestrator. Testa TODAS as camadas de busca
disponíveis (surf-skill, Brave API, DuckDuckGo keyless) e reporta o status
consolidado para que o orquestrador decida se os sub-agentes podem pesquisar.

OPÇÕES
  --json         Saída em JSON parseável (em stdout; avisos em stderr)
  --fail-fast    Sai no primeiro tier funcional — não testa tiers inferiores
  --timeout N    Timeout das chamadas HTTP em segundos (default $DEFAULT_TIMEOUT)
  -h, --help     Mostra esta ajuda

AMBIENTE
  BRAVE_API_KEY  Chave da Brave Search API (opcional; se ausente, Tier 2 = NOT_CONFIGURED)
  BRAVE_API_URL  Override do endpoint da Brave API (uso interno/testes)

EXIT CODES
  0 pesquisa completa disponível (Tier 1 ou 2) · 1 apenas keyless (Tier 3) ·
  2 nada disponível ou dependências ausentes (curl/jq)
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

# ---------------------------------------------------------------------------
# Parsing de argumentos
# ---------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --json)      JSON_OUT=1; shift ;;
      --fail-fast) FAIL_FAST=1; shift ;;
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

  if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || (( TIMEOUT < 1 || TIMEOUT > 120 )); then
    echo "ERRO: --timeout deve ser um inteiro entre 1 e 120" >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------

# header_val <arquivo-headers> <nome> → valor do header (ou vazio; always exit 0)
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

# api_error_message <arquivo-body> → mensagem de erro da API (ou vazio)
api_error_message() {
  local f="$1"
  jq -r '.message // .error.message // .error // .type // empty' "$f" 2>/dev/null | head -n 1 || true
}

# Tempo em milissegundos (compatível macOS + Linux)
now_ms() {
  local t
  t="$(date +%s%3N 2>/dev/null)" || t=""
  if [[ "$t" =~ ^[0-9]{13}$ ]]; then
    echo "$t"
  else
    echo "$(( $(date +%s) * 1000 ))"
  fi
}

# ---------------------------------------------------------------------------
# Tier 1 — surf-skill (surf-search-normal + surf-free-skill)
# ---------------------------------------------------------------------------

# Retorna via variáveis globais:
#   T1_STATUS   = AVAILABLE | DEGRADED | NOT_FOUND
#   T1_DETAIL   = descrição textual
#   T1_VERSION  = versão do surf-search-normal (ou "unknown")
#   T1_HAS_SSN  = "true" | "false"
#   T1_HAS_SFS  = "true" | "false"
check_tier1_surf_skill() {
  T1_STATUS="NOT_FOUND"
  T1_DETAIL=""
  T1_VERSION=""
  T1_HAS_SSN="false"
  T1_HAS_SFS="false"

  local ssn_path
  ssn_path="$(command -v surf-search-normal 2>/dev/null || true)"

  if [[ -z "$ssn_path" ]]; then
    T1_STATUS="NOT_FOUND"
    T1_DETAIL="surf-search-normal not in PATH"
    return
  fi

  T1_HAS_SSN="true"

  # Tenta obter versão
  local ver
  ver="$(surf-search-normal --version 2>/dev/null || true)"
  if [[ -z "$ver" ]]; then
    T1_VERSION="unknown"
  else
    # Extrai só o número da versão (ex.: "surf-search-normal v5.4.0" → "5.4.0")
    T1_VERSION="$(echo "$ver" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || echo "unknown")"
  fi

  # Tier 1 SÓ é AVAILABLE com um provedor configurado: keys.json do surf
  # existente e NÃO-vazio (~/.config/surf/keys.json). Sem isso o binário
  # existe mas não tem com o que pesquisar — DEGRADED, não "ALL SYSTEMS GO".
  local keys_file="${HOME}/.config/surf/keys.json"
  if [[ ! -f "$keys_file" ]] || [[ ! -s "$keys_file" ]]; then
    T1_STATUS="DEGRADED"
    T1_DETAIL="surf-search-normal found but ${keys_file} missing or empty — no AI provider configured"
    return
  fi

  # Verifica surf-free-skill
  if command -v surf-free-skill >/dev/null 2>&1; then
    T1_HAS_SFS="true"
  fi

  T1_STATUS="AVAILABLE"

  # Monta detail
  local components=()
  components+=("surf-skill v${T1_VERSION}")
  if [[ "$T1_HAS_SFS" == "true" ]]; then
    components+=("surf-free-skill available")
  else
    components+=("surf-free-skill NOT found")
  fi

  T1_DETAIL="$(IFS='; '; echo "${components[*]}")"
}

# ---------------------------------------------------------------------------
# Tier 2 — Brave Search API (legacy)
# ---------------------------------------------------------------------------

# Variáveis globais:
#   T2_STATUS         = ACTIVE | NO_CREDITS | NOT_CONFIGURED | ERROR
#   T2_DETAIL         = descrição textual
#   T2_CREDITS        = número de créditos (ou "null")
#   T2_HTTP           = código HTTP (ou "null")
#   T2_BILLING        = billing-status (ou vazio)
#   T2_RATE_REMAINING = X-RateLimit-Remaining (ou vazio)
#   T2_RATE_RESET     = X-RateLimit-Reset (ou vazio)
check_tier2_brave_api() {
  T2_STATUS="NOT_CONFIGURED"
  T2_DETAIL=""
  T2_CREDITS="null"
  T2_HTTP="null"
  T2_BILLING=""
  T2_RATE_REMAINING=""
  T2_RATE_RESET=""

  # --- Chave não configurada ---
  if [[ -z "${BRAVE_API_KEY:-}" ]]; then
    T2_STATUS="NOT_CONFIGURED"
    T2_DETAIL="BRAVE_API_KEY not set"
    return
  fi

  # --- Ferramentas necessárias ---
  local missing_tools=()
  for bin in curl jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing_tools+=("$bin")
    fi
  done
  if (( ${#missing_tools[@]} > 0 )); then
    T2_STATUS="ERROR"
    T2_DETAIL="missing tools: ${missing_tools[*]}"
    return
  fi

  # --- Query mínima para checar headers ---
  local body headers curl_err http_code rc credits billing rate_remaining rate_reset
  body="$(mktemp)"
  headers="$(mktemp)"
  curl_err="$(mktemp)"
  # Guarda ${var:-} + auto-remoção: o trap RETURN dispara também no retorno de
  # funções chamadoras, quando as locals já saíram de escopo — sem a guarda
  # isso vira "unbound variable" e corrompe o exit code (bash 4.4/5.x).
  # shellcheck disable=SC2064
  trap 'rm -f "${body:-}" "${headers:-}" "${curl_err:-}"; trap - RETURN' RETURN

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

  T2_HTTP="$http_code"

  if [[ $rc -ne 0 ]]; then
    T2_STATUS="ERROR"
    T2_DETAIL="network failure (curl exit $rc): $(tr '\n' ' ' < "$curl_err" | sed 's/  */ /g')"
    return
  fi

  # Extrai headers de diagnóstico
  credits="$(credits_from_headers "$headers")"
  rate_remaining="$(header_val "$headers" "X-RateLimit-Remaining")"
  rate_reset="$(header_val "$headers" "X-RateLimit-Reset")"
  # billing-status: header NÃO existe na resposta real da Brave (verificado
  # 14/08/2026); mantido como opcional/defensivo — na prática sai vazio.
  billing="$(header_val "$headers" "billing-status")"

  if [[ -n "$credits" ]] && [[ "$credits" =~ ^[0-9]+$ ]]; then
    T2_CREDITS="$credits"
  fi
  T2_RATE_REMAINING="$rate_remaining"
  T2_RATE_RESET="$rate_reset"
  T2_BILLING="$billing"

  local status detail

  case "${http_code:-}" in
    200)
      if [[ -n "$credits" ]] && [[ "$credits" =~ ^[0-9]+$ ]]; then
        if (( credits == 0 )); then
          # Créditos zerados: verificar se é assinatura ativa via busca real
          if _brave_real_search_works; then
            status="ACTIVE"
            if [[ -n "$billing" ]]; then
              detail="subscription active (billing: $billing), credits header shows 0 but API functional"
            else
              detail="subscription active, credits header shows 0 but API functional"
            fi
          else
            status="NO_CREDITS"
            detail="0 credits, real search returned no results — free plan exhausted. Reload at https://api.search.brave.com/app/plans"
          fi
        else
          status="ACTIVE"
          detail="${credits} queries remaining"
        fi
      else
        # Sem header de créditos — tenta busca real
        if _brave_real_search_works; then
          status="ACTIVE"
          if [[ -n "$billing" ]]; then
            detail="subscription active (billing: $billing), no credits header but API functional"
          else
            detail="no credits header but API functional — assuming active"
          fi
        else
          status="ERROR"
          detail="API returned 200 but no credits header found and real search failed"
        fi
      fi
      ;;
    401)
      status="ERROR"
      detail="invalid API key (HTTP 401) — check BRAVE_API_KEY"
      ;;
    402|403)
      status="NO_CREDITS"
      detail="billing issue (HTTP ${http_code}): $(api_error_message "$body")"
      ;;
    429)
      status="ACTIVE"
      detail="rate limited (HTTP 429) but API active — reset: ${rate_reset:-unknown}"
      ;;
    *)
      status="ERROR"
      detail="unexpected HTTP ${http_code}: $(api_error_message "$body")"
      ;;
  esac

  T2_STATUS="$status"
  T2_DETAIL="$detail"
}

# _brave_real_search_works → 0 se a busca real retornou resultados, 1 caso contrário
# Faz uma busca com count=3 para verificar se a API realmente funciona.
_brave_real_search_works() {
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
    # Sem trap RETURN aqui: limpeza explícita em cada saída — um trap com
    # locals vazaria para o retorno da função chamadora (unbound variable)
    rm -f "$body" "$headers" "$curl_err"
    return 1
  fi

  result_count="$(jq -r '(.web.results // .results // empty | length) // 0' "$body" 2>/dev/null || echo 0)"

  # Atualiza billing-status com o da busca real (mais confiável; header
  # opcional — na prática a Brave não envia billing-status)
  local real_billing
  real_billing="$(header_val "$headers" "billing-status")"
  if [[ -n "$real_billing" ]]; then
    T2_BILLING="$real_billing"
  fi

  rm -f "$body" "$headers" "$curl_err"

  if [[ "$result_count" =~ ^[0-9]+$ ]] && (( result_count > 0 )); then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Tier 3 — DuckDuckGo Keyless (fallback sem chave)
# ---------------------------------------------------------------------------

# Variáveis globais:
#   T3_STATUS     = REACHABLE | UNREACHABLE
#   T3_DETAIL     = descrição textual
#   T3_HTTP       = código HTTP (ou "null")
#   T3_LATENCY_MS = latência em milissegundos (ou "null")
check_tier3_keyless_ddg() {
  T3_STATUS="UNREACHABLE"
  T3_DETAIL=""
  T3_HTTP="null"
  T3_LATENCY_MS="null"

  if ! command -v curl >/dev/null 2>&1; then
    T3_STATUS="UNREACHABLE"
    T3_DETAIL="curl not available"
    return
  fi

  local http_code rc curl_err start_ms end_ms latency
  curl_err="$(mktemp)"
  # Guarda ${var:-} + auto-remoção: o trap RETURN dispara também no retorno de
  # funções chamadoras, quando as locals já saíram de escopo (unbound variable)
  # shellcheck disable=SC2064
  trap 'rm -f "${curl_err:-}"; trap - RETURN' RETURN

  start_ms="$(now_ms)"
  set +e
  http_code="$(curl -sS --connect-timeout 5 --max-time 10 \
    -o /dev/null \
    -w '%{http_code}' \
    "$DDG_CHECK_URL" 2>"$curl_err")"
  rc=$?
  set -e
  end_ms="$(now_ms)"

  T3_HTTP="$http_code"
  latency=$(( end_ms - start_ms ))
  T3_LATENCY_MS="$latency"

  if [[ $rc -ne 0 ]]; then
    T3_STATUS="UNREACHABLE"
    local err_msg
    err_msg="$(tr '\n' ' ' < "$curl_err" 2>/dev/null | sed 's/  */ /g' || true)"
    T3_DETAIL="cannot reach DuckDuckGo API (curl exit $rc${err_msg:+: $err_msg})"
    return
  fi

  # 200/301/302/403: servidor está respondendo (403 acontece com alguns
  # endpoints DDG mas conectividade existe) — o regex inclui 403 explicitamente
  if [[ "$http_code" =~ ^([23][0-9][0-9]|403)$ ]]; then
    T3_STATUS="REACHABLE"
    T3_DETAIL="DuckDuckGo API reachable"
  else
    T3_STATUS="UNREACHABLE"
    T3_DETAIL="DuckDuckGo API returned HTTP ${http_code} (${latency}ms)"
  fi
}

# ---------------------------------------------------------------------------
# Cálculo do tier máximo e veredito
# ---------------------------------------------------------------------------

# compute_max_tier → imprime "1", "2", "3", ou "0" (nenhum)
compute_max_tier() {
  if [[ "$T1_STATUS" == "AVAILABLE" ]]; then
    echo "1"
  elif [[ "$T2_STATUS" == "ACTIVE" ]]; then
    echo "2"
  elif [[ "$T3_STATUS" == "REACHABLE" ]]; then
    echo "3"
  else
    echo "0"
  fi
}

# tier_label <tier-number> → nome descritivo do tier
tier_label() {
  case "$1" in
    1) echo "full AI-powered multi-provider search (surf-skill)" ;;
    2) echo "Brave Search API (legacy, subscription-based)" ;;
    3) echo "DuckDuckGo keyless (limited, no API key needed)" ;;
    *) echo "NONE — no search available" ;;
  esac
}

# verdict <max-tier> → mensagem de veredito
verdict_text() {
  case "$1" in
    1) echo "ALL SYSTEMS GO — sub-agentes podem pesquisar com capacidade máxima" ;;
    2) echo "OPERATIONAL — Brave API ativa como fallback principal" ;;
    3) echo "DEGRADED — apenas pesquisa keyless disponível (qualidade reduzida)" ;;
    *) echo "CRITICAL — nenhuma camada de busca disponível; verifique rede e configuração" ;;
  esac
}

# exit_code_for_tier <max-tier> → exit code
exit_code_for_tier() {
  case "$1" in
    1|2) echo "0" ;;
    3)   echo "1" ;;
    *)   echo "2" ;;
  esac
}

# ---------------------------------------------------------------------------
# Saída
# ---------------------------------------------------------------------------

# status_icon <status> → indicador visual (plain text)
status_icon() {
  case "$1" in
    AVAILABLE|ACTIVE|REACHABLE)  echo "OK" ;;
    NOT_FOUND|NOT_CONFIGURED)    echo "--" ;;
    NO_CREDITS)                  echo "XX" ;;
    DEGRADED)                    echo "!!" ;;
    ERROR|UNREACHABLE)           echo "!!" ;;
    SKIPPED)                     echo "~~" ;;
    *)                           echo "??" ;;
  esac
}

# Colunas para output humano alinhado
COL1_WIDTH=24   # "Tier N (label):"
COL2_WIDTH=16   # "ICON STATUS"

human_output() {
  local max_tier vtext

  # Cabeçalho
  echo "=== deep-orchestrator Search Status ==="

  # Tier 1
  printf "%-${COL1_WIDTH}s %-${COL2_WIDTH}s %s\n" \
    "Tier 1 (surf-skill):" \
    "$(status_icon "$T1_STATUS") $T1_STATUS" \
    "$T1_DETAIL"

  # Tier 2
  printf "%-${COL1_WIDTH}s %-${COL2_WIDTH}s %s\n" \
    "Tier 2 (Brave API):" \
    "$(status_icon "$T2_STATUS") $T2_STATUS" \
    "$T2_DETAIL"
  # Informações adicionais do Brave (se disponíveis)
  if [[ "$T2_CREDITS" != "null" ]] && [[ "$T2_CREDITS" =~ ^[0-9]+$ ]]; then
    printf "%-${COL1_WIDTH}s %-${COL2_WIDTH}s %s queries remaining\n" "" "" "$T2_CREDITS"
  fi
  if [[ -n "$T2_BILLING" ]]; then
    printf "%-${COL1_WIDTH}s %-${COL2_WIDTH}s billing: %s\n" "" "" "$T2_BILLING"
  fi
  if [[ -n "$T2_RATE_REMAINING" ]]; then
    local rr_info="${T2_RATE_REMAINING}"
    [[ -n "$T2_RATE_RESET" ]] && rr_info="${rr_info} (reset: ${T2_RATE_RESET}s)"
    printf "%-${COL1_WIDTH}s %-${COL2_WIDTH}s rate limit: %s\n" "" "" "$rr_info"
  fi

  # Tier 3
  local t3_latency_str=""
  if [[ "$T3_LATENCY_MS" != "null" ]] && [[ "$T3_LATENCY_MS" =~ ^[0-9]+$ ]]; then
    t3_latency_str=" (${T3_LATENCY_MS}ms)"
  fi
  printf "%-${COL1_WIDTH}s %-${COL2_WIDTH}s %s%s\n" \
    "Tier 3 (Keyless DDG):" \
    "$(status_icon "$T3_STATUS") $T3_STATUS" \
    "$T3_DETAIL" \
    "$t3_latency_str"

  echo "---"

  max_tier="$(compute_max_tier)"
  vtext="$(verdict_text "$max_tier")"
  echo "Max tier: ${max_tier} ($(tier_label "$max_tier"))"
  echo "Veredito: ${vtext}"
}

json_output() {
  local max_tier vtext exit_code

  max_tier="$(compute_max_tier)"
  vtext="$(verdict_text "$max_tier")"
  exit_code="$(exit_code_for_tier "$max_tier")"

  jq -n \
    --arg t1_status "$T1_STATUS" \
    --arg t1_detail "$T1_DETAIL" \
    --arg t1_version "$T1_VERSION" \
    --argjson t1_has_ssn "$( [[ "$T1_HAS_SSN" == "true" ]] && echo true || echo false )" \
    --argjson t1_has_sfs "$( [[ "$T1_HAS_SFS" == "true" ]] && echo true || echo false )" \
    --arg t2_status "$T2_STATUS" \
    --arg t2_detail "$T2_DETAIL" \
    --argjson t2_credits "$T2_CREDITS" \
    --argjson t2_http "$T2_HTTP" \
    --arg t2_billing "$T2_BILLING" \
    --arg t2_rate_remaining "$T2_RATE_REMAINING" \
    --arg t2_rate_reset "$T2_RATE_RESET" \
    --arg t3_status "$T3_STATUS" \
    --arg t3_detail "$T3_DETAIL" \
    --argjson t3_http "$T3_HTTP" \
    --argjson t3_latency_ms "$T3_LATENCY_MS" \
    --argjson max_tier "$max_tier" \
    --arg max_tier_label "$(tier_label "$max_tier")" \
    --arg verdict "$vtext" \
    --argjson ec "$exit_code" \
    '{
      tiers: {
        "1": {
          name: "surf-skill",
          status: $t1_status,
          detail: $t1_detail,
          surf_search_normal: $t1_has_ssn,
          surf_free_skill: $t1_has_sfs,
          version: $t1_version
        },
        "2": {
          name: "Brave API",
          status: $t2_status,
          detail: $t2_detail,
          credits_remaining: $t2_credits,
          http_status: $t2_http,
          billing_status: $t2_billing,
          rate_limit_remaining: $t2_rate_remaining,
          rate_limit_reset: $t2_rate_reset
        },
        "3": {
          name: "Keyless DDG",
          status: $t3_status,
          detail: $t3_detail,
          http_status: $t3_http,
          latency_ms: $t3_latency_ms
        }
      },
      max_tier: $max_tier,
      max_tier_label: $max_tier_label,
      verdict: $verdict,
      exit_code: $ec
    }'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"

  # Dependências verificadas UMA vez, no início (o script não tem como testar
  # tiers 2/3 sem curl, nem emitir --json sem jq) — exit 2 com mensagem clara
  local missing_tools=()
  for bin in curl jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing_tools+=("$bin")
    fi
  done
  if (( ${#missing_tools[@]} > 0 )); then
    echo "ERRO: dependências ausentes no PATH: ${missing_tools[*]} (necessárias: curl, jq)" >&2
    exit 2
  fi

  # --- Tier 1: surf-skill ---
  check_tier1_surf_skill

  if (( FAIL_FAST )) && [[ "$T1_STATUS" == "AVAILABLE" ]]; then
    # Pula tiers inferiores — marca como SKIPPED para output consistente
    T2_STATUS="SKIPPED"
    T2_DETAIL="skipped (--fail-fast: Tier 1 available)"
    T2_CREDITS="null"
    T2_HTTP="null"
    T2_BILLING=""
    T2_RATE_REMAINING=""
    T2_RATE_RESET=""
    T3_STATUS="SKIPPED"
    T3_DETAIL="skipped (--fail-fast: Tier 1 available)"
    T3_HTTP="null"
    T3_LATENCY_MS="null"
  else
    # --- Tier 2: Brave API ---
    check_tier2_brave_api

    if (( FAIL_FAST )) && [[ "$T2_STATUS" == "ACTIVE" ]]; then
      # Tier 2 funciona — pula Tier 3
      T3_STATUS="SKIPPED"
      T3_DETAIL="skipped (--fail-fast: Tier 2 available)"
      T3_HTTP="null"
      T3_LATENCY_MS="null"
    else
      # --- Tier 3: Keyless DDG ---
      check_tier3_keyless_ddg
    fi
  fi

  # --- Output ---
  if (( JSON_OUT )); then
    json_output
  else
    human_output
  fi

  # --- Exit code ---
  local max_tier ec
  max_tier="$(compute_max_tier)"
  ec="$(exit_code_for_tier "$max_tier")"
  exit "$ec"
}

main "$@"
