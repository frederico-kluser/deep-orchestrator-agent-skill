#!/usr/bin/env bash
# =============================================================================
# check-plannotator.sh — Verifica (e opcionalmente instala) o Plannotator
# -----------------------------------------------------------------------------
# Verificador pré-fase do orquestrador, análogo ao check-search-credits.sh: diz
# se a FASE 2.5 (PORTÃO DE APROVAÇÃO DO PLANO) pode rodar. NÃO abre navegador, NÃO inicia servidor
# e NÃO escreve nada fora de $HOME/.local/bin (só quando --install é pedido).
#
# Uso:
#   check-plannotator.sh [--install] [--json] [--quiet] [--min-version X.Y.Z]
#
# O que é verificado, em ordem:
#   1. BINÁRIO   — resolve o executável (DO_PLANNOTATOR_BIN → PATH → ~/.local/bin)
#   2. VERSÃO    — `plannotator --version` responde e é >= --min-version
#   3. CAPACIDADE— `plannotator annotate` (sem argumentos) imprime o usage e sai
#                  1 SEM efeito colateral; o usage precisa listar --gate e --json,
#                  que são o contrato de máquina da FASE 2.5. Esta é a sonda:
#                  nenhuma execução real de sessão é disparada aqui.
#
# Exit codes:
#   0 = DISPONÍVEL   — binário resolvido, versão OK e --gate/--json presentes
#   1 = INSTALÁVEL   — ausente/incapaz, MAS curl e rede estão de pé (com
#                      --install o script tenta instalar e reverifica; sem
#                      --install ele apenas reporta)
#   2 = INDISPONÍVEL — ausente/incapaz e NÃO instalável (sem curl, sem rede,
#                      prefixo não gravável, ou a instalação falhou)
#
# Instalação (apenas com --install):
#   curl -fsSL https://plannotator.ai/install.sh | bash -s -- --minimal --non-interactive
#   --minimal é DELIBERADO: instala SÓ o binário em ~/.local/bin e não escreve
#   uma linha em ~/.claude, ~/.codex, ~/.config/opencode, ~/.gemini ou ~/.kiro.
#   A skill não tem mandato para reescrever a configuração dos agentes do
#   usuário — a FASE 2.5 só precisa do binário. NUNCA sudo, NUNCA npm -g.
#   Uma instalação COMPLETA escreveria em ~/.claude/{skills,commands,plugins},
#   ~/.agents/skills, $CODEX_HOME, ~/.gemini, ~/.kiro e ~/.config/opencode.
#
# Ambiente:
#   DO_PLANNOTATOR_BIN        Caminho explícito do executável (vence tudo)
#   DO_PLANNOTATOR_INSTALL    0 proíbe a instalação automática mesmo com --install
#   DO_PLANNOTATOR_INSTALL_URL  Override da URL do instalador (testes)
#   DO_PLANNOTATOR_INSTALL_ARGS Args extras para o instalador (ex.: --version v0.27.4)
# =============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# Versão mínima: 0.19.1 é o release em que `annotate --gate` E `--json` passam a
# existir juntos. A checagem REAL de capacidade é a sonda do usage (passo 3),
# imune a esquemas de versionamento — a comparação de versão só produz um
# diagnóstico melhor quando o binário é antigo demais.
DEFAULT_MIN_VERSION="0.19.1"
INSTALL_URL_DEFAULT="https://plannotator.ai/install.sh"
INSTALL_DIR="$HOME/.local/bin"
NET_PROBE_TIMEOUT=10

JSON_OUT=0
QUIET=0
DO_INSTALL=0
MIN_VERSION="$DEFAULT_MIN_VERSION"

# Estado reportado
BIN_PATH=""
BIN_VERSION=""
BIN_STATUS="MISSING"       # AVAILABLE | OUTDATED | INCAPABLE | MISSING
BIN_DETAIL=""
INSTALLABLE="unknown"      # yes | no | unknown
INSTALL_ATTEMPTED=0
INSTALL_RESULT="not-attempted"   # not-attempted | ok | failed | forbidden

usage() {
  cat <<EOF
Uso: $SCRIPT_NAME [OPTS]

Verificador pré-fase do deep-orchestrator. Resolve o executável do Plannotator,
confere a versão e SONDA a capacidade (annotate --gate --json) sem abrir
navegador nem iniciar servidor. Com --install, instala o binário quando ausente.

OPÇÕES
  --install            Instala o Plannotator quando AUSENTE (modo --minimal: só
                       o binário em $INSTALL_DIR, nenhuma configuração de agente
                       é tocada). Uma instalação EXISTENTE nunca é sobrescrita —
                       velha/incapaz é reportada, não atualizada às escondidas.
  --json               Saída em JSON parseável (stdout; diagnóstico em stderr)
  --quiet              Silencia a saída humana (o exit code é a resposta)
  --min-version X.Y.Z  Versão mínima aceita (default $DEFAULT_MIN_VERSION)
  -h, --help           Mostra esta ajuda

AMBIENTE
  DO_PLANNOTATOR_BIN          Caminho explícito do executável (vence PATH)
  DO_PLANNOTATOR_INSTALL      0 proíbe instalação automática mesmo com --install
  DO_PLANNOTATOR_INSTALL_URL  Override da URL do instalador (default $INSTALL_URL_DEFAULT)
  DO_PLANNOTATOR_INSTALL_ARGS Args extras repassados ao instalador

EXIT CODES
  0 disponível · 1 ausente mas instalável · 2 ausente e não instalável
EOF
}

# say(): progresso humano. Com --json ele vai para STDERR, porque o stdout é
# contrato de máquina — uma linha "Instalando..." no meio do JSON quebraria
# qualquer parser (e quebrou, em lab).
say() {
  (( QUIET )) && return 0
  if (( JSON_OUT )); then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi
}
warn() { printf '%s\n' "$*" >&2; }

# flag_val <flag> <args...> → valor (exit 2 se faltar — sem "unbound variable")
flag_val() {
  local flag="$1"
  shift
  if [[ $# -lt 1 ]]; then
    warn "ERRO: a flag $flag requer um valor"
    usage >&2
    exit 2
  fi
  printf '%s\n' "$1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)       usage; exit 0 ;;
      --install)       DO_INSTALL=1; shift ;;
      --json)          JSON_OUT=1; shift ;;
      --quiet)         QUIET=1; shift ;;
      --min-version)   MIN_VERSION="$(flag_val "$1" "${@:2}")"; shift 2 ;;
      --min-version=*) MIN_VERSION="${1#*=}"; shift ;;
      -*)
        warn "ERRO: flag desconhecida: $1"
        usage >&2
        exit 2
        ;;
      *)
        warn "ERRO: argumento posicional não esperado: $1"
        usage >&2
        exit 2
        ;;
    esac
  done

  if [[ ! "$MIN_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    warn "ERRO: --min-version deve ser numérica (ex.: 0.19.1), recebido: '$MIN_VERSION'"
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Resolução do binário
# ---------------------------------------------------------------------------
# Ordem: override explícito → PATH → ~/.local/bin (onde o instalador oficial
# põe o binário e que MUITAS vezes não está no PATH de um shell não-interativo,
# que é exactamente o shell em que o agente roda).
resolve_bin() {
  local cand
  if [[ -n "${DO_PLANNOTATOR_BIN:-}" ]]; then
    if [[ -x "$DO_PLANNOTATOR_BIN" ]]; then
      printf '%s\n' "$DO_PLANNOTATOR_BIN"
      return 0
    fi
    warn "AVISO: DO_PLANNOTATOR_BIN='$DO_PLANNOTATOR_BIN' não é executável — ignorado"
  fi
  if cand="$(command -v plannotator 2>/dev/null)" && [[ -n "$cand" ]]; then
    printf '%s\n' "$cand"
    return 0
  fi
  for cand in "$INSTALL_DIR/plannotator" "$INSTALL_DIR/plannotator.exe"; do
    if [[ -x "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  # Git-Bash / MSYS: install.ps1 instala em %LOCALAPPDATA%, install.cmd em
  # %USERPROFILE%\.local\bin — nenhum dos dois é o $HOME do POSIX.
  if [[ -n "${LOCALAPPDATA:-}" && -x "$LOCALAPPDATA/plannotator/plannotator.exe" ]]; then
    printf '%s\n' "$LOCALAPPDATA/plannotator/plannotator.exe"; return 0
  fi
  if [[ -n "${USERPROFILE:-}" && -x "$USERPROFILE/.local/bin/plannotator.exe" ]]; then
    printf '%s\n' "$USERPROFILE/.local/bin/plannotator.exe"; return 0
  fi
  return 1
}

# version_ge <a> <b> → 0 se a >= b. sort -V trata largura de minor/patch
# corretamente (0.9.0 < 0.10.0), o que a comparação lexicográfica erra.
version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}

# ---------------------------------------------------------------------------
# Sondas (nenhuma abre navegador nem servidor)
# ---------------------------------------------------------------------------

# probe_version <bin> → imprime a versão numérica (ou vazio)
# `plannotator --version` responde "plannotator X.Y.Z"; extraímos o 1º token
# que pareça uma versão, tolerando prefixo v e sufixos de pré-release.
probe_version() {
  local bin="$1" out
  out="$("$bin" --version 2>/dev/null </dev/null || true)"
  printf '%s\n' "$out" \
    | tr ' \t' '\n\n' \
    | sed -n 's/^v\{0,1\}\([0-9]\{1,\}\(\.[0-9]\{1,\}\)\{1,\}\).*$/\1/p' \
    | head -n 1
}

# probe_capability <bin> → 0 se o usage de `annotate` lista --gate E --json.
# `plannotator annotate` SEM argumento imprime o usage em stderr e sai 1 —
# nenhum servidor sobe, nenhum navegador abre. É a sonda mais barata e mais
# honesta que existe: ela lê o contrato do próprio binário instalado.
probe_capability() {
  local bin="$1" out
  out="$("$bin" annotate 2>&1 </dev/null || true)"
  [[ "$out" == *"--gate"* && "$out" == *"--json"* ]]
}

# ---------------------------------------------------------------------------
# Instalabilidade
# ---------------------------------------------------------------------------
# "Instalável" = curl existe, o prefixo é gravável e a URL do instalador
# responde. Não baixamos nada aqui: só provamos que baixar é possível.
check_installable() {
  if [[ "${DO_PLANNOTATOR_INSTALL:-1}" == "0" ]]; then
    INSTALLABLE="no"
    BIN_DETAIL="${BIN_DETAIL:+$BIN_DETAIL; }instalação automática proibida (DO_PLANNOTATOR_INSTALL=0)"
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    INSTALLABLE="no"
    BIN_DETAIL="${BIN_DETAIL:+$BIN_DETAIL; }curl ausente no PATH"
    return 1
  fi
  # O instalador oficial NÃO tem guarda de EUID: rodando como root ele instala
  # em /root/.local/bin — invisível para o usuário real, que continuaria sem
  # plannotator e sem entender por quê. Recusamos em vez de instalar no vazio.
  if [[ "$(id -u 2>/dev/null || echo 1000)" == "0" ]]; then
    INSTALLABLE="no"
    BIN_DETAIL="${BIN_DETAIL:+$BIN_DETAIL; }recuso instalar como root (iria para /root/.local/bin)"
    return 1
  fi
  if ! mkdir -p "$INSTALL_DIR" 2>/dev/null || [[ ! -w "$INSTALL_DIR" ]]; then
    INSTALLABLE="no"
    BIN_DETAIL="${BIN_DETAIL:+$BIN_DETAIL; }$INSTALL_DIR não é gravável"
    return 1
  fi
  local url="${DO_PLANNOTATOR_INSTALL_URL:-$INSTALL_URL_DEFAULT}"
  if ! curl -fsSIL --max-time "$NET_PROBE_TIMEOUT" -o /dev/null "$url" 2>/dev/null; then
    # HEAD pode ser negado por CDN; tenta um GET com range mínimo antes de desistir.
    if ! curl -fsSL --max-time "$NET_PROBE_TIMEOUT" -r 0-0 -o /dev/null "$url" 2>/dev/null; then
      INSTALLABLE="no"
      BIN_DETAIL="${BIN_DETAIL:+$BIN_DETAIL; }instalador inacessível ($url)"
      return 1
    fi
  fi
  INSTALLABLE="yes"
  return 0
}

# ---------------------------------------------------------------------------
# Instalação
# ---------------------------------------------------------------------------
do_install() {
  local url="${DO_PLANNOTATOR_INSTALL_URL:-$INSTALL_URL_DEFAULT}"
  local extra_args=()
  # DO_PLANNOTATOR_INSTALL_ARGS é word-split de propósito: é uma lista de flags.
  if [[ -n "${DO_PLANNOTATOR_INSTALL_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_args=(${DO_PLANNOTATOR_INSTALL_ARGS})
  fi
  INSTALL_ATTEMPTED=1
  say "Instalando o Plannotator (modo --minimal: só o binário em $INSTALL_DIR)..."
  say "  fonte: $url"
  # O binário é um single-file Bun de ~150 MB e é baixado num mktemp ANTES do mv.
  # Um /tmp em tmpfs pequeno quebra a instalação mesmo com espaço sobrando no
  # $HOME — avisamos com o número na mão em vez de deixar o curl morrer no meio.
  local tmpdir free_kb
  tmpdir="${TMPDIR:-/tmp}"
  free_kb="$(df -Pk "$tmpdir" 2>/dev/null | awk 'NR==2 { print $4 }')"
  if [[ -n "$free_kb" ]] && (( free_kb < 300000 )); then
    warn "AVISO: $tmpdir tem ~$(( free_kb / 1024 )) MB livres; o download precisa de ~150 MB."
    warn "       Se falhar, aponte TMPDIR para um volume com espaço e repita."
  fi
  # PLANNOTATOR_MINIMAL=1 é redundante com --minimal e serve de cinto de
  # segurança caso a versão do instalador ainda não conheça a flag.
  if PLANNOTATOR_MINIMAL=1 curl -fsSL --max-time 120 "$url" \
       | bash -s -- --minimal --non-interactive "${extra_args[@]+"${extra_args[@]}"}" >&2; then
    INSTALL_RESULT="ok"
    return 0
  fi
  INSTALL_RESULT="failed"
  warn "ERRO: a instalação do Plannotator falhou"
  return 1
}

# ---------------------------------------------------------------------------
# Avaliação
# ---------------------------------------------------------------------------
# Preenche BIN_* e devolve 0 quando o binário está plenamente utilizável.
evaluate() {
  BIN_PATH=""
  BIN_VERSION=""
  BIN_DETAIL=""
  if ! BIN_PATH="$(resolve_bin)"; then
    BIN_STATUS="MISSING"
    BIN_DETAIL="executável não encontrado (PATH, \$DO_PLANNOTATOR_BIN, $INSTALL_DIR)"
    return 1
  fi
  BIN_VERSION="$(probe_version "$BIN_PATH")"
  if [[ -z "$BIN_VERSION" ]]; then
    BIN_STATUS="INCAPABLE"
    BIN_DETAIL="'$BIN_PATH --version' não respondeu uma versão reconhecível"
    return 1
  fi
  if ! version_ge "$BIN_VERSION" "$MIN_VERSION"; then
    BIN_STATUS="OUTDATED"
    BIN_DETAIL="versão $BIN_VERSION < mínima $MIN_VERSION"
    return 1
  fi
  if ! probe_capability "$BIN_PATH"; then
    BIN_STATUS="INCAPABLE"
    BIN_DETAIL="'annotate' não anuncia --gate/--json — o contrato do PLAN-GATE não existe neste binário"
    return 1
  fi
  BIN_STATUS="AVAILABLE"
  BIN_DETAIL="ok"
  return 0
}

# ---------------------------------------------------------------------------
# Saída
# ---------------------------------------------------------------------------
json_escape() {
  # Escapa para string JSON sem depender de jq (esta fase pode rodar sem jq).
  # O TAB entra por variável, NUNCA como `\t` dentro do script do sed: `\t` é
  # extensão do GNU sed. No sed do BSD/macOS — plataforma que este repositório
  # suporta explicitamente — `\t` no lado esquerdo casa a LETRA `t`, e a saída
  # viraria "no<TAB>-a<TAB><TAB>emp<TAB>ed" em vez de "not-attempted": JSON
  # válido e conteúdo errado, que é o pior tipo de bug.
  local tab; tab=$(printf '\t')
  local cr;  cr=$(printf '\r')
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$tab/\\\\t/g" -e "s/$cr/\\\\r/g" \
    | awk 'BEGIN{ORS=""} {if (NR>1) print "\\n"; print}'
}

json_output() {
  printf '{\n'
  printf '  "status": "%s",\n'       "$(json_escape "$BIN_STATUS")"
  printf '  "bin": "%s",\n'          "$(json_escape "$BIN_PATH")"
  printf '  "version": "%s",\n'      "$(json_escape "$BIN_VERSION")"
  printf '  "min_version": "%s",\n'  "$(json_escape "$MIN_VERSION")"
  printf '  "detail": "%s",\n'       "$(json_escape "$BIN_DETAIL")"
  printf '  "installable": "%s",\n'  "$(json_escape "$INSTALLABLE")"
  printf '  "install_attempted": %s,\n' "$INSTALL_ATTEMPTED"
  printf '  "install_result": "%s",\n' "$(json_escape "$INSTALL_RESULT")"
  printf '  "install_dir": "%s"\n'   "$(json_escape "$INSTALL_DIR")"
  printf '}\n'
}

human_output() {
  say "Plannotator: $BIN_STATUS"
  say "  bin           = ${BIN_PATH:-<não encontrado>}"
  say "  version       = ${BIN_VERSION:-<desconhecida>}  (mínima $MIN_VERSION)"
  say "  detalhe       = $BIN_DETAIL"
  say "  instalável    = $INSTALLABLE"
  if (( INSTALL_ATTEMPTED )); then
    say "  instalação    = $INSTALL_RESULT"
  fi
  if [[ "$BIN_STATUS" != "AVAILABLE" ]]; then
    say ""
    say "  Instalação manual (uma vez, pelo usuário):"
    say "    curl -fsSL $INSTALL_URL_DEFAULT | bash"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"

  if evaluate; then
    INSTALLABLE="n/a"
  else
    # Instalação automática SÓ quando o binário está AUSENTE. Se ele existe mas
    # está velho/incapaz, quem manda é o usuário: o instalador oficial não sabe
    # atualizar (sempre rebaixa ~150 MB e sobrescreve), e um --minimal por cima
    # de uma instalação COMPLETA deixaria as integrações de agente numa versão
    # e o binário em outra. Reportamos e paramos.
    if (( DO_INSTALL )) && [[ "$BIN_STATUS" != "MISSING" ]]; then
      warn "AVISO: Plannotator presente mas $BIN_STATUS ($BIN_DETAIL)."
      warn "       NÃO vou sobrescrever uma instalação existente. Atualize você:"
      warn "         curl -fsSL $INSTALL_URL_DEFAULT | bash"
      INSTALLABLE="no"
      INSTALL_RESULT="forbidden"
    elif (( DO_INSTALL )); then
      if check_installable && do_install; then
        # Reavalia com o PATH atualizado: o instalador põe o binário em
        # ~/.local/bin, que pode não estar no PATH deste shell — resolve_bin
        # já cobre esse caminho explicitamente.
        if evaluate; then
          INSTALLABLE="n/a"
        fi
      elif [[ "$INSTALL_RESULT" == "failed" ]]; then
        INSTALLABLE="no"
      fi
    else
      check_installable || true
    fi
  fi

  if (( JSON_OUT )); then
    json_output
  else
    human_output
  fi

  if [[ "$BIN_STATUS" == "AVAILABLE" ]]; then
    exit 0
  fi
  if [[ "$INSTALLABLE" == "yes" ]]; then
    exit 1
  fi
  exit 2
}

main "$@"
