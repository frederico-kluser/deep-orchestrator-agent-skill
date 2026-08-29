#!/usr/bin/env bash
# =============================================================================
# test-surf-gate.sh — Suíte do PORTÃO DA SURF (R7) e do orçamento --sub-agents
# -----------------------------------------------------------------------------
# Substitui test-search.sh, que testava o sistema de busca próprio removido na
# v4.0.0 (decisão D23).
#
# SEM REDE, SEM QUOTA, SEM CHAVE: todo binário surf é mockado num PATH
# temporário. O que se testa aqui é o CONTRATO que o SKILL.md declara —
# os códigos de saída que o orquestrador interpreta e a aritmética do
# orçamento de simultaneidade —, não o surf em si (esse tem a suíte dele).
#
# Uso: bash scripts/test-surf-gate.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$ROOT/.claude/skills/deep-orchestrator-agent-skill/SKILL.md"

PASS=0; FAIL=0
chk() { # chk <nome> <obtido> <esperado>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s — esperado "%s", obtido "%s"\n' "$1" "$3" "$2"; fi
}
ok() { # ok <nome> <cond-exit>
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; fi
}
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

CASE=""
newcase() { CASE="$(mktemp -d)"; mkdir -p "$CASE/bin"; }
cleanup() { [ -n "$CASE" ] && rm -rf "$CASE"; }
trap cleanup EXIT

# Cria um binário fake que apenas sai com o código dado.
mkbin() { # mkbin <nome> <exit-code> [stdout]
  printf '#!/usr/bin/env bash\n%s\nexit %s\n' "${3:-:}" "$2" > "$CASE/bin/$1"
  chmod +x "$CASE/bin/$1"
}

# O PORTÃO, copiado LITERALMENTE do que a R7 manda o orquestrador rodar.
# Se este texto e o SKILL.md divergirem, o teste perde o sentido — por isso
# G8 confere que o comando ainda está lá.
gate() {
  if command -v surf-search-normal >/dev/null 2>&1; then
    surf doctor >/dev/null 2>&1; echo "SURF_GATE=$?"
  else
    echo "SURF_GATE=127"
  fi
}

section "G1 — surf ausente: o portão reporta 127, não 0"
newcase
out="$(PATH="$CASE/bin" gate)"
chk "sem surf-search-normal no PATH → SURF_GATE=127" "$out" "SURF_GATE=127"

section "G2 — chave Brave inválida: 78, distinto de 1 e de 2"
newcase
mkbin surf-search-normal 0
mkbin surf 78
out="$(PATH="$CASE/bin:$PATH" gate)"
chk "surf doctor sai 78 → SURF_GATE=78" "$out" "SURF_GATE=78"
ok "78 não é 1 (operação falhou) nem 2 (erro de uso)" \
   "$([ "$out" != "SURF_GATE=1" ] && [ "$out" != "SURF_GATE=2" ]; echo $?)"

section "G3 — exit 1 do doctor é 'prossiga', não bloqueio"
newcase
mkbin surf-search-normal 0
mkbin surf 1
out="$(PATH="$CASE/bin:$PATH" gate)"
chk "skills do surf não symlinkadas → SURF_GATE=1" "$out" "SURF_GATE=1"
ok "R7 trata 1 como prossiga (documentado no SKILL.md)" \
   "$(grep -q 'Isso NÃO afeta os binários que' "$SKILL_MD"; echo $?)"

section "G4 — portão verde"
newcase
mkbin surf-search-normal 0
mkbin surf 0
chk "tudo pronto → SURF_GATE=0" "$(PATH="$CASE/bin:$PATH" gate)" "SURF_GATE=0"

section "G5 — aritmética do orçamento: os dois tetos SOMAM, nunca multiplicam"
# --sub-agents por sub-agente = max(1, floor(N/R)); a soma da onda nunca > N.
budget() { n=$1; r=$2; v=$(( n / r )); [ "$v" -lt 1 ] && v=1; echo "$v"; }
for pair in "10 1 10" "10 2 5" "10 3 3" "10 4 2" "10 10 1" "10 12 1" "20 3 6"; do
  set -- $pair; n=$1; r=$2; want=$3
  chk "N=$n R=$r → --sub-agents=$want" "$(budget "$n" "$r")" "$want"
done
for pair in "10 1" "10 2" "10 3" "10 4" "10 10" "20 3"; do
  set -- $pair; n=$1; r=$2; v=$(budget "$n" "$r"); total=$(( r * v ))
  ok "N=$n R=$r → soma da onda ${total} ≤ N" "$([ "$total" -le "$n" ]; echo $?)"
done
# R > N é o caso patológico que o SKILL.md manda evitar ao planejar.
v=$(budget 10 12); total=$(( 12 * v ))
ok "N=10 R=12 estoura (${total} > 10) — por isso o SKILL.md exige R ≤ N" \
   "$([ "$total" -gt 10 ]; echo $?)"
ok "o SKILL.md declara a restrição R ≤ N" \
   "$(grep -q 'limite <code>R ≤ N</code>' "$SKILL_MD"; echo $?)"

section "G6 — --sub-agents fora de 1..20 sai 2 (a skill valida ANTES de colar)"
newcase
# Reproduz o FlagError de src/lib/flags.mjs: valor fora da faixa → exit 2.
cat > "$CASE/bin/surf-search-normal" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    --sub-agents=*) v="${a#*=}"
      if ! [ "$v" -eq "$v" ] 2>/dev/null || [ "$v" -lt 1 ] || [ "$v" -gt 20 ]; then
        echo "❌ Error: --sub-agents must be between 1 and 20 (got $v)" >&2; exit 2
      fi ;;
  esac
done
exit 0
FAKE
chmod +x "$CASE/bin/surf-search-normal"
PATH="$CASE/bin:$PATH" surf-search-normal "q" --sub-agents=10 >/dev/null 2>&1
chk "--sub-agents=10 aceito" "$?" "0"
PATH="$CASE/bin:$PATH" surf-search-normal "q" --sub-agents=0 >/dev/null 2>&1
chk "--sub-agents=0 → exit 2" "$?" "2"
PATH="$CASE/bin:$PATH" surf-search-normal "q" --sub-agents=50 >/dev/null 2>&1
chk "--sub-agents=50 → exit 2" "$?" "2"

section "G7 — regressão de arquitetura: nada do sistema removido é INVOCÁVEL"
# Prosa que DECLARA a remoção é legítima (o D23 e os READMEs precisam nomear o
# que morreu). O que não pode existir é uma INVOCAÇÃO: um caminho de script, um
# {{SKILL_HOME}}/scripts/<busca>, ou um endpoint de provedor.
for pat in 'scripts/search\.sh' 'scripts/search-parallel\.sh' \
           'scripts/brave-search\.sh' 'scripts/check-search-credits' \
           'scripts/check-brave-credits' 'scripts/test-search\.sh' \
           'SKILL_HOME}}/scripts/search' 'SEARCH_TIER' \
           'api\.search\.brave\.com' 'api\.duckduckgo\.com' \
           'surf-free-skill'; do
  hits="$(grep -rIn -- "$pat" "$ROOT/scripts" "$ROOT/prompts" "$SKILL_MD" 2>/dev/null \
          | grep -v 'test-surf-gate\.sh' | wc -l | tr -d ' ')"
  chk "nada invoca '$pat'" "$hits" "0"
done
ok "os seis scripts de busca não existem mais" \
   "$([ ! -e "$ROOT/scripts/search.sh" ] && [ ! -e "$ROOT/scripts/brave-search.sh" ] \
      && [ ! -e "$ROOT/scripts/search-parallel.sh" ] && [ ! -e "$ROOT/scripts/check-search-credits.sh" ] \
      && [ ! -e "$ROOT/scripts/check-brave-credits.sh" ] && [ ! -e "$ROOT/scripts/test-search.sh" ]; echo $?)"
ok "check-install.sh não exige mais os scripts removidos" \
   "$(! grep -qE 'scripts/(search|search-parallel|check-search-credits)\.sh' "$ROOT/scripts/check-install.sh"; echo $?)"
# A prosa de remoção DEVE existir — apagar a história é tão ruim quanto mantê-la viva.
ok "o D23 registra o que foi removido" \
   "$(test -f "$ROOT/docs/decisions/2026-08-29-surf-agent-skill-obrigatorio.md"; echo $?)"

section "G8 — o SKILL.md ainda declara o contrato que esta suíte testa"
ok "R7 manda rodar 'surf doctor' no portão" \
   "$(grep -q 'surf doctor &gt;/dev/null 2&gt;&amp;1; echo "SURF_GATE=\$?"' "$SKILL_MD"; echo $?)"
ok "R7 documenta o exit 78 como configuração" \
   "$(grep -q '78 — não há chave Brave válida' "$SKILL_MD"; echo $?)"
ok "R7 proíbe jitter/backoff em volta do surf" \
   "$(grep -q 'NUNCA envolva uma chamada surf em sleep, jitter, backoff' "$SKILL_MD"; echo $?)"
ok "R7 proíbe WebSearch/WebFetch para DESCOBRIR fontes" \
   "$(grep -q 'para DESCOBRIR fontes' "$SKILL_MD"; echo $?)"
ok "R7 proíbe 'keys list --json' (imprimia as chaves em texto puro)" \
   "$(grep -q 'keys list --json' "$SKILL_MD"; echo $?)"
ok "o template de sub-agente usa {{SURF_SUB_AGENTS}}" \
   "$(grep -q -- '--sub-agents={{SURF_SUB_AGENTS}}' "$SKILL_MD"; echo $?)"
ok "FASE 0 tem o passo 6 (dependência obrigatória)" \
   "$(grep -q 'DEPENDÊNCIA OBRIGATÓRIA — SURF-AGENT-SKILL v8' "$SKILL_MD"; echo $?)"
ok "existem os dois casos de degradação novos" \
   "$(grep -q 'case id="surf-ausente"' "$SKILL_MD" && grep -q 'case id="brave-key-invalida"' "$SKILL_MD"; echo $?)"

printf '\n\033[1mRESULTADO:\033[0m %d passaram, %d falharam\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "surf-gate-ok"
