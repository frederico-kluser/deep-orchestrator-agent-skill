#!/usr/bin/env bash
# Testes de aceitação do search.sh — F1-03 (argv do Tier 1)
#
# FASE 4 (futuro, NÃO implementada nesta rodada — exige mocks extras):
#   T2: argv/fallback do Tier 2 (Brave) — mockar SEARCH_OUT_FILE + API_URL
#       (curl fake apontando para um servidor local ou arquivo), e validar a
#       evolução de query com DEV_MODE (brave-search.sh:524-525).
#   T3: fallback DuckDuckGo — mockar curl no PATH para retornar JSON DDG
#       local; validar normalização e limite de COUNT.
#   C1: cascata — fake do Tier 1 com exit != 0 + Tier 2 sem chave → Tier 3.
#   C2: validações de CLI (--timeout fora de 1..120, --count > 20, ...).
# Novos casos entram aqui sem reestruturar o arquivo.
set -uo pipefail
SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SEARCH="$SKILL/scripts/search.sh"
LAB="${TMPDIR:-/tmp}/search-accept-$$"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (esperado='$3' obtido='$2')"; fi; }

rm -rf "$LAB"; mkdir -p "$LAB/bin"; cd "$LAB"
trap 'rm -rf "$LAB"' EXIT   # nunca deixar labs /tmp/search-accept-* órfãos

# --- fixture: fake do Tier 1 --------------------------------------------------
# Grava o argv recebido em $SURF_ARGV_FILE e sai 0 — NUNCA toca rede.
# Search.sh só usa o Tier 1 se achar `surf-search-normal` no PATH; o fake é
# o primeiro do PATH, então o binário real nunca é invocado. Sem BRAVE_API_KEY
# o Tier 2 é pulado e o Tier 3 só rodaria se o Tier 1 falhasse (não falha).
cat > "$LAB/bin/surf-search-normal" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SURF_ARGV_FILE:?}"
exit 0
EOF
chmod +x "$LAB/bin/surf-search-normal"

echo "=== T1: argv do Tier 1 usa --budget-ms (ms) e NÃO --timeout/--dev-mode ==="
unset BRAVE_API_KEY
export SURF_ARGV_FILE="$LAB/argv.txt"
PATH="$LAB/bin:$PATH" "$SEARCH" --timeout 30 --dev-mode "test query" >/dev/null 2>&1
rc=$?
chk "T1 search.sh exit 0 (fake do Tier 1 respondeu)" "$rc" "0"
chk "T1 argv foi gravado pelo fake" "$(test -f "$SURF_ARGV_FILE" && echo sim || echo nao)" "sim"
argv=$(cat "$SURF_ARGV_FILE" | tr '\n' ' ')
case " $argv " in
  *" --budget-ms 30000 "*) ok "T1 argv contém --budget-ms 30000" ;;
  *) bad "T1 argv NÃO contém --budget-ms 30000: [$argv]" ;;
esac
case " $argv " in
  *" --timeout "*) bad "T1 argv contém --timeout (unidade errada): [$argv]" ;;
  *) ok "T1 argv não contém --timeout" ;;
esac
case " $argv " in
  *" --dev-mode "*) bad "T1 argv contém --dev-mode (flag inexistente no surf): [$argv]" ;;
  *) ok "T1 argv não contém --dev-mode (mesmo com --dev-mode no CLI)" ;;
esac

echo; printf 'RESULTADO: %s PASS, %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1
