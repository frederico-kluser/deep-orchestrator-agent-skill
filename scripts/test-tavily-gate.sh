#!/usr/bin/env bash
# =============================================================================
# test-tavily-gate.sh — Suíte do PORTÃO DE PESQUISA (tavily-gate.sh) v6.0.0
# -----------------------------------------------------------------------------
# SEM REDE, SEM créditos, SEM chave real: o tavily.py é MOCKADO numa skill-home
# de fixture ($CASE/tavily/scripts/tavily.py — Python real, comandos status/
# status --check/search). O que se testa é o CONTRATO que a skill declara:
# fail-closed, PREMISSA de trabalho (chave validada antes de iniciar), classify
# anti-eco, scrub de chaves e o protocolo PESQUISA-FALHOU.
#
#   T1  skill ausente → TAVILY_GATE=127 + TavilySkillMissing
#   T2  sem chaves → 78 + TavilyKeyMissing
#   T3  cota esgotada / todas banidas → 78 + TavilyQuotaExhausted/TavilyAllBanned
#   T4  ≥1 ACTIVE → 0; SEARCH_MODE=no-search sai mesmo com portão verde
#   T5  premise: ok / skill-missing / key-missing / key-invalid (status --check)
#   T6  classify: OK|EMPTY|FAILED_QUOTA|FAILED_OTHER|USAGE_2|KILLED_143|BLOCKED_NOKEY
#   T7  FAIL-CLOSED: tavily.py status morre → 78 + TavilyUnknown
#   T8  scrub: chave tvly- NUNCA impressa
#   T9  pause/resume/choose: estado em disco (search-pause.md, search-mode)
#   T10 bloco da pergunta byte-a-byte com CONTRATO.md e research-protocol.md
#   T11 dispatch/--help (lista os verbos; não vaza o marcador de fim)
#
# Uso: bash scripts/test-tavily-gate.sh   (exit 0 = tudo verde)
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
GATE_SH="$ROOT/scripts/tavily-gate.sh"
CONTRATO="$ROOT/CONTRATO.md"
PROTO="$ROOT/references/research-protocol.md"
PASS=0; FAIL=0
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()  { if [ "$2" = 0 ]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"
        else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; fi; }
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"
        else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s — esperado "%s", obtido "%s"\n' "$1" "$3" "$2"; fi; }

# --- fixture: uma skill-home com tavily.py MOCKADO (Python real) --------------
CASE="$(mktemp -d)"
trap 'rm -rf "$CASE"' EXIT
mkdir -p "$CASE/tavily/scripts" "$CASE/state"
cat > "$CASE/tavily/scripts/tavily.py" <<'PYEOF'
import os, sys
mode = os.environ.get('FAKE_TAVILY', 'ok')
args = sys.argv[1:]
if args[:1] == ['status']:
    if '--check' in args:
        sys.exit(0 if mode in ('ok', 'quota') else 1)
    if mode == 'errstatus':
        print('Erro: pool corrompido'); sys.exit(2)
    if mode == 'nokeys':
        print('Pool Tavily: 0 credencial(is)')
    elif mode == 'quota':
        print('  TAVILY_API_KEY_A  …aaaa  [QUOTA_EXHAUSTED]  restam 0/1000')
    elif mode == 'banned':
        print('  TAVILY_API_KEY_A  …aaaa  [BANNED]  FORA DE ROTAÇÃO por mais 3 h')
    else:
        print('Pool Tavily: 2 credencial(is)')
        print('  TAVILY_API_KEY_A  …aaaa  [ACTIVE]  restam 500/1000')
        print('  TAVILY_API_KEY_B  …bbbb  [ACTIVE]  restam 400/1000')
    sys.exit(0)
if args[:1] == ['search']:
    m = os.environ.get('FAKE_TAVILY_SEARCH', 'ok')
    if m == 'quota':
        print('Erro: HTTP 432 — cota esgotada em todas as chaves'); sys.exit(1)
    if m == 'empty':
        sys.exit(1)
    # ecoa a query com "429 quota" EM CRASES para provar o anti-eco do classify
    print('## [1/1] `429 quota billing required`')
    print('- `tavily 429 quota` — ok')
    sys.exit(0)
print('usage: tavily.py status|search'); sys.exit(2)
PYEOF

run() { # run <modo> <modo-search> <args...> → stdout
  FAKE_TAVILY="$1" FAKE_TAVILY_SEARCH="$2" TAVILY_HOME="$CASE/tavily" DO_STATE="$CASE/state" \
    RUN_ID=run-t bash "$GATE_SH" "${@:3}"
}

section "T1 — skill ausente (PREMISSA) → 127"
out="$(TAVILY_HOME="$CASE/nao-existe" DO_STATE="$CASE/state" bash "$GATE_SH" gate)"
chk "TAVILY_GATE=127" "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_GATE=//p')" "127"
ok "TAVILY_CODE=TavilySkillMissing" "$(printf '%s\n' "$out" | grep -q 'TAVILY_CODE=TavilySkillMissing'; echo $?)"
ok "mensagem aponta a PREMISSA + keys add" "$(printf '%s\n' "$out" | grep -q 'keys add' && printf '%s\n' "$out" | grep -q 'PREMISSA'; echo $?)"

section "T2 — sem chaves → 78 + TavilyKeyMissing"
out="$(run nokeys ok gate)"
chk "TAVILY_GATE=78" "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_GATE=//p')" "78"
ok "TAVILY_CODE=TavilyKeyMissing + pede chave ao usuário" \
   "$(printf '%s\n' "$out" | grep -q 'TAVILY_CODE=TavilyKeyMissing' && printf '%s\n' "$out" | grep -q 'Peça UMA chave\|PEÇA UMA CHAVE\|Peça uma chave'; echo $?)"

section "T3 — cota esgotada / todas banidas → 78"
out="$(run quota ok gate)"
chk "quota → 78 + TavilyQuotaExhausted" "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_GATE=//p')/$(printf '%s\n' "$out" | grep -c 'TAVILY_CODE=TavilyQuotaExhausted')" "78/1"
out="$(run banned ok gate)"
chk "banidas → 78 + TavilyAllBanned" "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_GATE=//p')/$(printf '%s\n' "$out" | grep -c 'TAVILY_CODE=TavilyAllBanned')" "78/1"

section "T4 — ≥1 ACTIVE → 0 (+ SEARCH_MODE)"
out="$(run ok ok gate)"
chk "portão verde" "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_GATE=//p')" "0"
chk "sem TAVILY_CODE quando verde" "$(printf '%s\n' "$out" | grep -c 'TAVILY_CODE=')" "0"
printf 'no-search\n' > "$CASE/state/search-mode"
out="$(run ok ok gate)"
ok "SEARCH_MODE=no-search sai MESMO com portão verde" "$(printf '%s\n' "$out" | grep -q 'SEARCH_MODE=no-search'; echo $?)"
rm -f "$CASE/state/search-mode"

section "T5 — premise (a premissa de trabalho)"
out="$(run ok ok premise)"
chk "chave válida → TAVILY_PREMISE=ok" "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_PREMISE=//p')" "ok"
out="$(TAVILY_HOME="$CASE/nao-existe" DO_STATE="$CASE/state" bash "$GATE_SH" premise)"
chk "skill ausente → TAVILY_PREMISE=skill-missing" "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_PREMISE=//p')" "skill-missing"
out="$(run nokeys ok premise)"
chk "sem chave → TAVILY_PREMISE=key-missing + PEDE CHAVE" \
    "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_PREMISE=//p')/$(printf '%s\n' "$out" | grep -q 'PEÇA UMA CHAVE\|Peça UMA chave' && echo sim)" "key-missing/sim"
out="$(run invalid ok premise)"
chk "status --check falha → TAVILY_PREMISE=key-invalid" "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_PREMISE=//p')" "key-invalid"

section "T6 — classify"
t="$CASE/c"
printf '%s\n' '- `x` — ok' > "$t.out"; : > "$t.err"
chk "exit 0 → OK" "$(run ok ok classify 0 "$t.out" "$t.err")" "OK"
chk "exit 2 → USAGE_2" "$(run ok ok classify 2 "$t.out" "$t.err")" "USAGE_2"
chk "exit 143 → KILLED_143" "$(run ok ok classify 143 "$t.out" "$t.err")" "KILLED_143"
chk "exit 78 → BLOCKED_NOKEY" "$(run ok ok classify 78 "$t.out" "$t.err")" "BLOCKED_NOKEY"
printf 'Erro: HTTP 432 — cota esgotada\n' > "$t.err"
chk "432/cota → FAILED_QUOTA" "$(run ok ok classify 1 "$t.out" "$t.err")" "FAILED_QUOTA"
printf 'Erro: timeout de rede\n' > "$t.err"
chk "timeout → FAILED_OTHER" "$(run ok ok classify 1 "$t.out" "$t.err")" "FAILED_OTHER"
# anti-eco: query ecoada com "429 quota" em crases NÃO vira FAILED_QUOTA
printf '## [1/1] `429 quota billing required`\n- `tavily 429 quota` — nada\n' > "$t.out"; : > "$t.err"
chk "eco da query com 429/quota em crases → EMPTY (não FAILED_QUOTA)" \
    "$(run ok ok classify 1 "$t.out" "$t.err")" "EMPTY"
printf '429 quota esgotada\n' > "$t.err"
chk "…mas o erro REAL no stderr continua FAILED_QUOTA" \
    "$(run ok ok classify 1 "$t.out" "$t.err")" "FAILED_QUOTA"

section "T7 — FAIL-CLOSED: status morre → 78"
out="$(run errstatus ok gate)"
chk "tavily.py status exit 2 → 78 + TavilyUnknown" \
    "$(printf '%s\n' "$out" | sed -n 's/^TAVILY_GATE=//p')/$(printf '%s\n' "$out" | grep -c 'TAVILY_CODE=TavilyUnknown')" "78/1"

section "T8 — scrub: chave tvly- nunca impressa"
out="$(run ok ok gate; run ok quota resume --probe 2>&1)"
ok "nenhuma ocorrência de tvly- com material" "$(! printf '%s\n' "$out" | grep -qE 'tvly-[A-Za-z0-9_-]{8,}'; echo $?)"

section "T9 — pause/resume/choose (estado em disco)"
out="$(run ok ok pause 3 "t1, t2" "cota")"
ok "PAUSE_FILE gravado" "$(printf '%s\n' "$out" | grep -q "PAUSE_FILE=$CASE/state/search-pause.md"; echo $?)"
ok "bloco da pergunta impresso" "$(printf '%s\n' "$out" | grep -q '===== PESQUISA-FALHOU'; echo $?)"
out="$(run ok ok resume)"
chk "resume com portão verde → RESUME=OK e pausa apagada" \
    "$(printf '%s\n' "$out" | sed -n 's/^RESUME=//p')/$([ -f "$CASE/state/search-pause.md" ] && echo fica || echo apaga)" "OK/apaga"
out="$(run nokeys ok resume)"
chk "resume bloqueado → RESUME=STILL_BLOCKED" "$(printf '%s\n' "$out" | sed -n 's/^RESUME=//p')" "STILL_BLOCKED"
out="$(run ok ok choose no-search)"
ok "choose no-search → SEARCH_MODE=no-search + MODE_FILE" \
   "$(printf '%s\n' "$out" | grep -q 'SEARCH_MODE=no-search' && printf '%s\n' "$out" | grep -q 'MODE_FILE='; echo $?)"
out="$(run ok ok choose search)"
ok "choose search → SEARCH_MODE=search (volta a pesquisar)" \
   "$(printf '%s\n' "$out" | grep -q 'SEARCH_MODE=search'; echo $?)"
out="$(DO_STATE= TAVILY_HOME="$CASE/tavily" bash "$GATE_SH" choose no-search 2>&1)"; rc=$?
chk "choose sem DO_STATE → exit 2" "$rc" "2"

section "T10 — bloco da pergunta byte-a-byte (3 donos)"
out="$(run nokeys ok pause 1 "x" "y")"
miss=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  grep -qF -- "$line" "$CONTRATO" || miss="$miss contrato:[${line:0:24}]"
  grep -qF -- "$line" "$PROTO"    || miss="$miss proto:[${line:0:24}]"
done <<EOF
$(printf '%s\n' "$out" | grep -E '^  \[[1-4]\] |^===== PESQUISA-FALHOU|^Rode os comandos no SEU terminal|^Outros: remover chave morta')
EOF
chk "título, [1]-[4] e adendos idênticos em tavily-gate.sh × CONTRATO.md × research-protocol.md" "$miss" ""

section "T11 — dispatch/--help"
help="$(bash "$GATE_SH" --help)"
ok "--help lista gate/premise/classify/pause/resume/choose" \
   "$(printf '%s\n' "$help" | grep -q 'tavily-gate.sh premise' && printf '%s\n' "$help" | grep -q 'classify <exit> <stdout-file> <stderr-file>' && printf '%s\n' "$help" | grep -q 'choose no-search|search'; echo $?)"
ok "--help não vaza o marcador de fim" "$(! printf '%s\n' "$help" | grep -q 'FIM-DO-CABECALHO'; echo $?)"
usage="$(bash "$GATE_SH" explode 2>&1 >/dev/null)"; rc=$?
chk "subcomando desconhecido → exit 2 com uso" "$rc" "2"
ok "check-install.sh registra scripts/tavily-gate.sh" \
   "$(grep -q '"\$ROOT/scripts/tavily-gate.sh" x' "$ROOT/scripts/check-install.sh"; echo $?)"
ok "sintaxe bash 3.2 limpa (sem GNU-isms proibidos)" \
   "$(! grep -qE 'declare -A|local -A|mapfile|readarray|sed -i' "$GATE_SH"; echo $?)"

printf '\n\033[1mRESULTADO: %d PASS, %d FAIL\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
