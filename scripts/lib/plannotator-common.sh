# =============================================================================
# plannotator-common.sh — helpers COMPARTILHADOS de interação com o Plannotator
# -----------------------------------------------------------------------------
# Fonte única para o contrato de máquina do Plannotator (`annotate --gate
# --json`), usada por:
#   • scripts/plan-approval.sh     — portão de aprovação do plano (FASE 2.5)
#   • scripts/evolution-survey.sh  — questionário de evolução (FASE 4, 6.5)
#
# Esta lib é SOURCEADA e só DEFINE funções/estado — nunca executa nada por
# conta própria. Compatível com bash 3.2 (macOS). Os consumidores precisam
# definir `err` (stderr) e `note` ANTES de sourcear.
#
# Contrato do Plannotator (verificado no binário 0.19.17):
#   {"decision":"approved"}
#   {"decision":"dismissed"}
#   {"decision":"annotated","feedback":"<markdown>"}
# O campo feedback traz \n e " escapados — extrair com sed é errado, então
# exigimos jq OU python3 (pick_json_tool).
# =============================================================================

# ---------------------------------------------------------------------------
# Resolução do binário — MESMA ordem do check-plannotator.sh
# ---------------------------------------------------------------------------
resolve_bin() {
  local cand
  if [ -n "${DO_PLANNOTATOR_BIN:-}" ] && [ -x "$DO_PLANNOTATOR_BIN" ]; then
    printf '%s\n' "$DO_PLANNOTATOR_BIN"; return 0
  fi
  if cand="$(command -v plannotator 2>/dev/null)" && [ -n "$cand" ]; then
    printf '%s\n' "$cand"; return 0
  fi
  for cand in "$HOME/.local/bin/plannotator" "$HOME/.local/bin/plannotator.exe"; do
    [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
  done
  # Git-Bash / MSYS: o install.ps1 põe o .exe em %LOCALAPPDATA% e o install.cmd
  # em %USERPROFILE%\.local\bin — nenhum dos dois cai no $HOME do POSIX.
  if [ -n "${LOCALAPPDATA:-}" ] && [ -x "$LOCALAPPDATA/plannotator/plannotator.exe" ]; then
    printf '%s\n' "$LOCALAPPDATA/plannotator/plannotator.exe"; return 0
  fi
  if [ -n "${USERPROFILE:-}" ] && [ -x "$USERPROFILE/.local/bin/plannotator.exe" ]; then
    printf '%s\n' "$USERPROFILE/.local/bin/plannotator.exe"; return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Detecção de harness → PLANNOTATOR_ORIGIN
# ---------------------------------------------------------------------------
# Prioridade pedida: Claude Code > pi coding agent > jcode > opencode.
# O valor só é aceito pelo Plannotator se for uma chave conhecida dele
# (claude-code, opencode, copilot-cli, pi, codex, gemini-cli); um valor
# desconhecido é IGNORADO por ele e a autodetecção assume. jcode não tem chave
# própria — detectamos o harness (para o relatório) e NÃO forçamos origin.
# Isso é cosmético (um selo na UI): jamais deixe a detecção bloquear nada.
# ancestor_is <comm> <níveis> → 0 se algum ancestral até <níveis> acima tem esse
# nome de comando. `ps -o comm=` é POSIX; falhas viram "não é" (nunca erro).
ancestor_is() {
  local want="$1" levels="${2:-3}" pid="${PPID:-0}" comm
  while [ "$levels" -gt 0 ]; do
    levels=$((levels - 1))
    [ "$pid" -gt 1 ] 2>/dev/null || return 1
    comm="$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ "$comm" = "$want" ] && return 0
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$pid" ] || return 1
  done
  return 1
}

detect_harness() {
  if [ -n "${DO_PLAN_ORIGIN:-}" ]; then printf '%s\n' "$DO_PLAN_ORIGIN"; return; fi
  # 1. Claude Code
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ] \
     || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    printf 'claude-code\n'; return
  fi
  # 2. pi coding agent (não é autodetectado pelo Plannotator — daí o override)
  if [ -n "${PI_CODING_AGENT:-}" ] || [ -n "${PI_SESSION_ID:-}" ] \
     || [ -n "${PI_CODING_AGENT_DIR:-}" ]; then
    printf 'pi\n'; return
  fi
  # 3. jcode — NÃO exporta variável nenhuma (as JCODE_* são LIDAS, nunca
  # setadas), então a única evidência é a árvore de processos + a casa dele.
  if [ -n "${JCODE_SESSION_ID:-}" ] || [ -n "${JCODE_HOME:-}" ] \
     || { [ -f "$HOME/.jcode/config.toml" ] && ancestor_is jcode 3; }; then
    printf 'jcode\n'; return
  fi
  # 4. opencode
  if [ -n "${OPENCODE:-}" ] || [ -n "${OPENCODE_PID:-}" ]; then
    printf 'opencode\n'; return
  fi
  # Outros que o Plannotator conhece — respeitamos o que ele já detectaria.
  [ -n "${CODEX_THREAD_ID:-}" ] && { printf 'codex\n'; return; }
  [ -n "${COPILOT_CLI:-}" ]     && { printf 'copilot-cli\n'; return; }
  [ -n "${GEMINI_CLI:-}" ]      && { printf 'gemini-cli\n'; return; }
  printf 'unknown\n'
}

# origin_for_plannotator <harness> → valor aceito pelo Plannotator (ou vazio)
origin_for_plannotator() {
  case "$1" in
    claude-code|opencode|copilot-cli|pi|codex|gemini-cli) printf '%s\n' "$1" ;;
    *) printf '' ;;   # jcode/unknown: deixe o Plannotator decidir
  esac
}

# ---------------------------------------------------------------------------
# Utilitários de arquivo/hash/data
# ---------------------------------------------------------------------------

# first_h1 <arquivo> → texto do primeiro `# título` (mesma regra do Plannotator:
# /^#\s+(.+)$/m — qualquer linha, não só a primeira), com espaços das pontas
# aparados. Vazio quando não há H1.
first_h1() {
  sed -n 's/^#[[:space:]]\{1,\}\(.*[^[:space:]]\)[[:space:]]*$/\1/p' "$1" | head -n 1
}

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else printf 'nosha\n'
  fi
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

rev_pad() { printf '%03d\n' "$1"; }

# ---------------------------------------------------------------------------
# Parse do envelope --json (jq OU python3; nunca sed)
# ---------------------------------------------------------------------------
JSON_TOOL=""
pick_json_tool() {
  if command -v jq >/dev/null 2>&1; then JSON_TOOL=jq; return 0; fi
  if command -v python3 >/dev/null 2>&1; then JSON_TOOL=python3; return 0; fi
  err "preciso de jq OU python3 no PATH para ler o envelope --json"
  err "  do Plannotator (o campo feedback carrega \\n e \" escapados)."
  return 1
}

# json_field <arquivo-json> <campo> → valor (string vazia se ausente)
json_field() {
  local f="$1" k="$2"
  case "$JSON_TOOL" in
    jq)      jq -r --arg k "$k" '.[$k] // ""' < "$f" 2>/dev/null ;;
    python3) python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
v = d.get(sys.argv[2], "")
sys.stdout.write(v if isinstance(v, str) else json.dumps(v))' "$f" "$k" 2>/dev/null ;;
  esac
}

# last_json_line <arquivo> → última linha não vazia que começa com '{'.
# O stdout do Plannotator é UMA linha, mas um aviso de runtime poderia
# precedê-la; ancorar na última linha JSON é o parse honesto.
last_json_line() {
  awk '/^[[:space:]]*\{/ { line = $0 } END { if (line != "") print line }' "$1"
}
