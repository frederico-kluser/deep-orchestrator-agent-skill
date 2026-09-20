#!/usr/bin/env bash
# =============================================================================
# test-surf-gate.sh — Suíte do PORTÃO DA SURF (R7) e do orçamento --sub-agents
# -----------------------------------------------------------------------------
# Substitui test-search.sh, que testava o sistema de busca próprio removido na
# v4.0.0 (decisão D23).
#
# SEM REDE, SEM QUOTA, SEM CHAVE: todo binário surf é mockado num PATH
# temporário ($CASE/bin + SAFE_PATH — o surf REAL nunca é alcançado, nem pela
# sonda de 1 crédito do `resume --probe`). O que se testa aqui é o CONTRATO
# que o SKILL.md declara — o portão FAIL-CLOSED de scripts/surf-gate.sh
# (gate/classify/pause/resume, v4.1.0), os códigos que o orquestrador
# interpreta e a aritmética do orçamento de simultaneidade —, não o surf em
# si (esse tem a suíte dele).
#
#   G1  surf ausente → SURF_GATE=127 / SURF_CODE=NotInstalled
#   G2  chave inválida → 78 + SURF_CODE=BraveKey* + mensagem VERBATIM
#   G3  FAIL-CLOSED: exit 1/2/143 do binário do portão vira 78 (nunca "prossiga")
#   G4  portão verde; surf-gate.last; chave NUNCA impressa
#   G5  aritmética do orçamento · G6 --sub-agents fora da faixa · G7 regressão
#   G8  literais do SKILL.md
#   G9  classify — cada classe; eco da query (crases, lista SEM crases, --json,
#       pergunta multi-linha, aspas do progresso) NÃO vira FAILED_QUOTA; LC_ALL=C
#   G10 pause/resume com DO_STATE temporário (busca SEMPRE mockada); resume sem
#       pausa prévia não grava nada · G10b choose no-search|search / SURF_MODE
#   G11 instalação (check-install.sh) e higiene bash 3.2 do surf-gate.sh
#   G12 integração v4.1.0: o MESMO contrato em SKILL.md, scripts e prompts
#       (pergunta fixa, SEARCH_STATUS, subcomandos citados x dispatch, flags do
#       argument-hint x do-context.sh x README, description <= 1024, XML inteiro,
#       orçamento de tamanho do SKILL.md, passos do checklist ⊆ <step order>)
#   G13 hermeticidade: DO_STATE/RUN_ID/DO_* herdados não mudam NENHUM resultado
#       e a suíte não escreve NADA no $DO_STATE de um run vivo
#
# Uso: bash scripts/test-surf-gate.sh
# =============================================================================

set -uo pipefail

# HERMÉTICA (SG-2): o ENV_FILE da FASE 0 EXPORTA DO_STATE/RUN_ID/DO_*; quando
# esta suíte roda como GATE_TEST de um run vivo ("$DO_WT" gate herda o
# ambiente) ela NÃO pode ler nem escrever o estado dele. Tudo que a suíte usa
# é passado explicitamente por caso. (G13 prova.)
for _v in ${!DO_@} RUN_ID OWNED PLAN_FILE PLAN_DOC PLAN_APPROVAL_DIR BASE_DIR BASE_BRANCH \
          CHILD_ROOT BRANCH_NS COMMON_DIR SKILL_HOME; do
  unset "$_v"
done
unset _v

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$ROOT/.claude/skills/deep-orchestrator-agent-skill/SKILL.md"
GATE_SH="$ROOT/scripts/surf-gate.sh"
# PATH mínimo dos casos: coreutils do sistema e MAIS NADA. Os binários surf
# reais vivem fora daqui (~/.local/bin, prefixo do npm -g) — nenhum caso os vê.
SAFE_PATH="/usr/bin:/bin"

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
cleanup() { [ -n "$CASE" ] && rm -rf "$CASE"; CASE=""; }
newcase() { cleanup; CASE="$(mktemp -d)"; mkdir -p "$CASE/bin"; }   # o caso anterior é APAGADO
trap cleanup EXIT

# Cria um binário fake que apenas sai com o código dado.
mkbin() { # mkbin <nome> <exit-code> [stdout]
  printf '#!/usr/bin/env bash\n%s\nexit %s\n' "${3:-:}" "$2" > "$CASE/bin/$1"
  chmod +x "$CASE/bin/$1"
}

# Mock configurável do surf-research-skill. `gate` e `search` leem o veredito de
# arquivos do caso (gate.rc/gate.msg, search.rc/search.out/search.err); toda
# chamada de `search` fica registrada em search.calls, e `keys` (PROIBIDO para
# o portão) em forbidden.calls.
mksurf() { # mksurf <gate-rc> [<mensagem do portão no stderr>]
  printf '%s' "$1" > "$CASE/gate.rc"
  printf '%s' "${2:-}" > "$CASE/gate.msg"
  cat > "$CASE/bin/surf-research-skill" <<FAKE
#!/bin/bash
case "\${1:-}" in
  gate)   [ -s "$CASE/gate.msg" ] && cat "$CASE/gate.msg" >&2
          [ "\$(cat "$CASE/gate.rc")" = 0 ] && echo "✓ Brave gate OK — key #0 is usable (mock)."
          exit "\$(cat "$CASE/gate.rc")" ;;
  search) printf '%s\n' "\$*" >> "$CASE/search.calls"
          [ -f "$CASE/search.out" ] && cat "$CASE/search.out"
          [ -f "$CASE/search.err" ] && cat "$CASE/search.err" >&2
          exit "\$(cat "$CASE/search.rc" 2>/dev/null || echo 0)" ;;
  keys)   printf 'keys %s\n' "\$*" >> "$CASE/forbidden.calls"; exit 0 ;;
esac
exit 0
FAKE
  chmod +x "$CASE/bin/surf-research-skill"
}
calls() { # calls <arquivo> → número de linhas (0 se ausente), sem padding do wc BSD
  if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi
}

# O PORTÃO é scripts/surf-gate.sh — o MESMO arquivo que o SKILL.md manda rodar
# via "$DO_SURF_GATE" (G8 confere). Roda sempre com o PATH do caso.
gate() { PATH="$CASE/bin:$SAFE_PATH" "$GATE_SH" "$@"; }
field() { # field <saída> <CHAVE> → valor da 1ª linha CHAVE=valor
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n 1
}

# Mensagens REAIS do portão (surf-agent-skill 8.0.1, src/lib/preflight.mjs).
MSG_COOLING='❌ Error [BraveKeyCooling]: every Brave Search key is rate-limited right now.
   Detail: every usable key is cooling down after a rate limit until 2026-09-20T12:00:00.000Z
Fix: wait for the cooldown to expire, or add another Brave Search key —
     each key carries its own per-second rate budget.'

section "G0 — isolamento: o surf REAL está fora do PATH dos casos"
ok "SAFE_PATH não enxerga surf-research-skill nem surf-search-normal" \
   "$(! PATH="$SAFE_PATH" command -v surf-research-skill >/dev/null 2>&1 \
      && ! PATH="$SAFE_PATH" command -v surf-search-normal >/dev/null 2>&1; echo $?)"

section "G1 — surf ausente: o portão reporta 127, não 0"
newcase
out="$(gate)"; rc=$?
chk "sem binários no PATH → SURF_GATE=127" "$(field "$out" SURF_GATE)" "127"
chk "127 → SURF_CODE=NotInstalled" "$(field "$out" SURF_CODE)" "NotInstalled"
chk "127 traz o comando de instalação" "$(printf '%s' "$out" | grep -c 'npm i -g surf-agent-skill')" "1"
chk "o script SEMPRE sai 0 (o veredito é a linha SURF_GATE=)" "$rc" "0"
newcase
mksurf 0
chk "só surf-research-skill, sem surf-search-normal → SURF_GATE=127" "$(field "$(gate)" SURF_GATE)" "127"

section "G2 — chave Brave inválida: 78 + SURF_CODE + mensagem VERBATIM"
newcase
mkbin surf-search-normal 0
mksurf 78 "$MSG_COOLING"
out="$(gate gate)"; rc=$?
chk "portão do surf sai 78 → SURF_GATE=78" "$(field "$out" SURF_GATE)" "78"
chk "SURF_CODE extraído da mensagem" "$(field "$out" SURF_CODE)" "BraveKeyCooling"
chk "mensagem do portão VERBATIM (linha do erro)" \
    "$(printf '%s\n' "$out" | grep -cF '❌ Error [BraveKeyCooling]: every Brave Search key is rate-limited right now.')" "1"
chk "mensagem VERBATIM preserva o 'Fix:' do veredito" "$(printf '%s\n' "$out" | grep -c '^Fix: wait for the cooldown')" "1"
chk "78 também sai com exit 0" "$rc" "0"
for code in BraveKeyMissing BraveKeyBurned BraveKeyCooling BraveKeyInvalid BraveKeyUnverified BraveKeyUnproven; do
  mksurf 78 "❌ Error [$code]: mock."
  chk "SURF_CODE=$code" "$(field "$(gate)" SURF_CODE)" "$code"
done
chk "o portão NUNCA chama 'keys' (keys list --json é proibido)" "$(calls "$CASE/forbidden.calls")" "0"
chk "o portão NUNCA gasta busca" "$(calls "$CASE/search.calls")" "0"

section "G3 — FAIL-CLOSED: qualquer exit != 0 do binário do portão vira 78"
newcase
mkbin surf-search-normal 0
for brc in 1 2 143; do
  mksurf "$brc"
  out="$(gate)"
  chk "binário do portão sai $brc → SURF_GATE=78 (nunca 'prossiga')" "$(field "$out" SURF_GATE)" "78"
done
chk "sem código BraveKey na mensagem → SURF_CODE=BraveKeyUnknown" "$(field "$out" SURF_CODE)" "BraveKeyUnknown"
mksurf 1 "❌ Error: Unknown command: gate."
out="$(gate)"
chk "rc 1 com mensagem estranha → 78 + BraveKeyUnknown" "$(field "$out" SURF_GATE)/$(field "$out" SURF_CODE)" "78/BraveKeyUnknown"
chk "a mensagem estranha é repassada (diagnóstico não se perde)" "$(printf '%s\n' "$out" | grep -c 'Unknown command: gate')" "1"

section "G4 — portão verde, surf-gate.last e chave NUNCA impressa"
newcase
mkbin surf-search-normal 0
mksurf 0
out="$(gate)"
chk "tudo pronto → saída é EXATAMENTE 'SURF_GATE=0'" "$out" "SURF_GATE=0"
mkdir -p "$CASE/state"
mksurf 78 "❌ Error [BraveKeyInvalid]: the configured Brave Search key was rejected by the API.
   Detail: token BSAabcdefghijklmnopqrstuvwxyz0123 rejected (403)"
out="$(DO_STATE="$CASE/state" gate)"
chk "DO_STATE existe → grava surf-gate.last" "$([ -f "$CASE/state/surf-gate.last" ] && echo 1 || echo 0)" "1"
chk "surf-gate.last guarda veredito + código" \
    "$(grep -c -e '^SURF_GATE=78$' -e '^SURF_CODE=BraveKeyInvalid$' "$CASE/state/surf-gate.last")" "2"
chk "chave citada pelo provedor é MASCARADA no stdout" "$(printf '%s' "$out" | grep -c 'BSAabcdefghijklmnop')" "0"
chk "chave citada pelo provedor é MASCARADA no arquivo" "$(grep -c 'BSAabcdefghijklmnop' "$CASE/state/surf-gate.last")" "0"
chk "o resto da linha continua verbatim" "$(printf '%s' "$out" | grep -c 'rejected (403)')" "1"
mksurf 0
DO_STATE="$CASE/state" gate >/dev/null
chk "portão verde sobrescreve o surf-gate.last velho (sem veredito stale)" "$(cat "$CASE/state/surf-gate.last")" "SURF_GATE=0"
out="$(DO_STATE="$CASE/nao-existe" gate)"; rc=$?
chk "DO_STATE inexistente: não cria nada e não falha" "$rc/$([ -e "$CASE/nao-existe" ] && echo 1 || echo 0)" "0/0"

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
chk "o surf-search-normal do caso é o MOCK (o PATH real fica de fora)" \
    "$(PATH="$CASE/bin:$SAFE_PATH" command -v surf-search-normal)" "$CASE/bin/surf-search-normal"
PATH="$CASE/bin:$SAFE_PATH" surf-search-normal "q" --sub-agents=10 >/dev/null 2>&1
chk "--sub-agents=10 aceito" "$?" "0"
PATH="$CASE/bin:$SAFE_PATH" surf-search-normal "q" --sub-agents=0 >/dev/null 2>&1
chk "--sub-agents=0 → exit 2" "$?" "2"
PATH="$CASE/bin:$SAFE_PATH" surf-search-normal "q" --sub-agents=50 >/dev/null 2>&1
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
ok "o portão do SKILL.md é o script (\"\$DO_SURF_GATE\" = scripts/surf-gate.sh)" \
   "$(grep -q 'DO_SURF_GATE' "$SKILL_MD"; echo $?)"
ok "o portão fail-open antigo ('surf doctor >/dev/null; echo SURF_GATE=\$?') saiu" \
   "$(! grep -q 'surf doctor &gt;/dev/null 2&gt;&amp;1; echo "SURF_GATE=' "$SKILL_MD"; echo $?)"
ok "existe o protocolo PESQUISA-FALHOU (pergunta incondicional da chave Brave)" \
   "$(grep -q 'PESQUISA-FALHOU' "$SKILL_MD"; echo $?)"
ok "o handoff do sub-agente declara SEARCH_STATUS" \
   "$(grep -q 'SEARCH_STATUS' "$SKILL_MD"; echo $?)"
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
# Rodada final (DESIGN-2, SG-1): a escolha [3] é ESTADO do script, e o SKILL.md
# tem de mandar gravá-la e obedecê-la. (As duas grafias: o XML pode escapar as
# aspas. grep direto no ARQUIVO — `sed | grep -q` sob pipefail dá 141/SIGPIPE.)
ok "[DESIGN-2] SKILL.md obedece a linha 'SURF_MODE=no-search' do portão" \
   "$(grep -qF 'SURF_MODE=no-search' "$SKILL_MD"; echo $?)"
ok "[DESIGN-2] SKILL.md grava a escolha [3] com '\"\$DO_SURF_GATE\" choose'" \
   "$(grep -qF -e '"$DO_SURF_GATE" choose' -e '&quot;$DO_SURF_GATE&quot; choose' "$SKILL_MD"; echo $?)"

section "G9 — classify: cota/429/402 sai exit 1 no surf, quem distingue é o texto"
newcase
cls() { # cls <exit> → classe, lendo $CASE/o e $CASE/e
  PATH="$SAFE_PATH" "$GATE_SH" classify "$1" "$CASE/o" "$CASE/e"
}
fx() { printf '%s\n' "$1" > "$CASE/o"; printf '%s\n' "${2:-}" > "$CASE/e"; }

fx "ok" ""
chk "exit 0 → OK" "$(cls 0)" "OK"
fx "" "[surf 10:00:00] ! brave key #0 monthly quota exhausted — skipped, not retried"
chk "exit 0 com aviso de cota no stderr continua OK (houve fontes)" "$(cls 0)" "OK"
fx "" "❌ Error [BraveKeyBurned]: every Brave Search key on this machine is burned."
chk "exit 78 → BLOCKED_78" "$(cls 78)" "BLOCKED_78"
fx "" ""
chk "exit 143 → KILLED_143" "$(cls 143)" "KILLED_143"
fx "" "❌ Error: --sub-agents must be between 1 and 20 (got 50)"
chk "exit 2 → USAGE_2" "$(cls 2)" "USAGE_2"

# Textos REAIS: src/lib/ai/orchestrator.mjs (relatório sem fontes) e
# src/lib/dispatch.mjs (AllKeysExhausted: '<prov>#<i>: 429').
fx "> ❌ **No sources retrieved.** Every search failed (2 of 2), so there is nothing to synthesize.

# how do teams cap LLM spend
- \`llm spend cap\` — AllKeysExhausted: 'search' failed on every brave key: brave#0: 429; brave#1: 429." ""
chk "exit 1 + 'brave#N: 429' → FAILED_QUOTA" "$(cls 1)" "FAILED_QUOTA"
fx "" "❌ Error [AllKeysExhausted]: 'search' failed on every brave key: brave#0: 429."
chk "exit 1 + Error [AllKeysExhausted] ... 429 (stderr) → FAILED_QUOTA" "$(cls 1)" "FAILED_QUOTA"
fx "" "[surf 10:00:00] ! brave key #1 monthly quota exhausted — skipped, not retried"
chk "exit 1 + 'monthly quota exhausted' → FAILED_QUOTA" "$(cls 1)" "FAILED_QUOTA"
fx "" "brave 429 SUBSCRIPTION_QUOTA_EXCEEDED"
chk "exit 1 + SUBSCRIPTION_QUOTA_EXCEEDED → FAILED_QUOTA" "$(cls 1)" "FAILED_QUOTA"
fx "" "code: QUOTA_EXCEEDED"
chk "exit 1 + QUOTA_EXCEEDED → FAILED_QUOTA" "$(cls 1)" "FAILED_QUOTA"
fx "" "Brave reports billing required / out of credit — the key is sidelined, not burned"
chk "exit 1 + 'billing required' (402) → FAILED_QUOTA" "$(cls 1)" "FAILED_QUOTA"

fx "" "❌ Error [AllKeysExhausted]: 'search' failed on every brave key: brave#0: network."
chk "exit 1 + AllKeysExhausted SEM 429 (rede) → FAILED_OTHER" "$(cls 1)" "FAILED_OTHER"
fx "" "❌ Error [NoProviderAvailable]: no usable brave key."
chk "exit 1 + NoProviderAvailable → FAILED_OTHER" "$(cls 1)" "FAILED_OTHER"
fx "" "❌ Error [LikelyAgentTimeout]: the harness budget is about to expire."
chk "exit 1 + LikelyAgentTimeout → FAILED_OTHER" "$(cls 1)" "FAILED_OTHER"
fx "> ❌ **No sources retrieved.** Every search failed (1 of 1), so there is nothing to synthesize.
- \`q\` — AllKeysExhausted: 'search' failed on every brave key: brave#0: 5xx." ""
chk "exit 1 + 'Every search failed' por 5xx → FAILED_OTHER" "$(cls 1)" "FAILED_OTHER"

fx "> ❌ **No sources retrieved.** 2 search(es) ran — 0 failed and the rest came back empty — so there is nothing to synthesize.

# why does brave return 429 when the monthly quota is over
- \`brave api 429 quota exceeded\` — returned 0 results
- \`http 429 too many requests quota\` — returned 0 results" ""
chk "QUERY contendo '429' e 'quota' NÃO vira FAILED_QUOTA → EMPTY" "$(cls 1)" "EMPTY"
# O progresso do batch ecoa a query entre ASPAS no stderr (fora das crases): aqui
# só a ANCORAGEM dos padrões protege — ' 429' ou 'quota' soltos casariam.
fx "" '[surf 10:00:00] ▸ [1/2] "http 429 quota limits"
[surf 10:00:01] ✓ search brave 429ms (1 credits)'
chk "'429'/'quota' soltos no stderr (eco entre aspas, latência 429ms) → EMPTY" "$(cls 1)" "EMPTY"
fx "# what does QUOTA_EXCEEDED mean: monthly quota exhausted or billing required
- \`brave SUBSCRIPTION_QUOTA_EXCEEDED monthly quota exhausted billing required brave#0: 429\` — returned 0 results" ""
chk "QUERY ecoada com os literais ANCORADOS também não engana → EMPTY" "$(cls 1)" "EMPTY"
fx '{
  "query": "AllKeysExhausted brave#0: 429 QUOTA_EXCEEDED",
  "results": []
}' ""
chk "eco da query no --json não engana → EMPTY" "$(cls 1)" "EMPTY"

# SG-4: ecos FORA de crases. Formatos REAIS do surf 8.x — render.mjs ("Planned
# and never run:" / "**Open points...**": `- <query>` sem crases),
# cli.mjs (--json pretty: "answer" numa linha só, arrays de strings) e
# orchestrator.mjs (`# <pergunta>` multi-linha, fechada pelo `## What was attempted`).
ATT_EMPTY="> ❌ **No sources retrieved.** 3 search(es) ran — 0 failed and the rest came back empty — so there is nothing to synthesize."
ECHO_LISTS="## Open questions

Planned and never run:
- stripe invoice 402 billing required test clock
- brave SUBSCRIPTION_QUOTA_EXCEEDED monthly quota exhausted

**Open points recorded by the analyst:**
- whether AllKeysExhausted means brave#0: 429 on every key
"
fx "$ATT_EMPTY

# how to test stripe invoices

## What was attempted (1 query)
- \`stripe test clock\` — returned 0 results

$ECHO_LISTS" ""
chk "SG-4: query SEM crases em 'Planned and never run'/'Open points' → EMPTY" "$(cls 1)" "EMPTY"
fx "$ATT_EMPTY

# how to test stripe invoices

## What was attempted (1 query)
- \`stripe test clock\` — AllKeysExhausted: 'search' failed on every brave key: brave#0: 429.

$ECHO_LISTS" ""
chk "SG-4: …e o erro REAL na linha de tentativa continua FAILED_QUOTA (fail-closed)" "$(cls 1)" "FAILED_QUOTA"
fx "$ECHO_LISTS
> ⚠ Degraded: brave key #0 monthly quota exhausted — skipped, not retried" ""
chk "SG-4: o bloco de eco acaba na linha vazia (erro real DEPOIS dele é visto)" "$(cls 1)" "FAILED_QUOTA"

JSON_ECHO='{
  "operation": "surf-ai",
  "answer": "> ❌ **No sources retrieved.**\n\n# is billing required when QUOTA_EXCEEDED\n\n- brave#0: 429",
  "stop_reason": "Every search failed to find the billing required docs",
  "plan": {
    "sub_questions": [
      "is billing required once the monthly quota exhausted",
      "AllKeysExhausted brave#0: 429"
    ],
    "rationale": "the user asks about SUBSCRIPTION_QUOTA_EXCEEDED"
  },'
fx "$JSON_ECHO
  \"ledger\": { \"rows\": [ ] }
}" ""
chk "SG-4: --json — literais em \"answer\"/\"stop_reason\"/\"rationale\"/arrays de strings → EMPTY" "$(cls 1)" "EMPTY"
fx "$JSON_ECHO
  \"ledger\": {
    \"rows\": [
      {
        \"query\": \"billing required\",
        \"ok\": false,
        \"error\": {
          \"code\": \"AllKeysExhausted\",
          \"message\": \"'search' failed on every brave key: brave#0: 429.\"
        }
      }
    ]
  }
}" ""
chk "SG-4: --json — o erro REAL em \"error\".\"message\" continua FAILED_QUOTA" "$(cls 1)" "FAILED_QUOTA"
fx "$JSON_ECHO
  \"ledger\": { \"rows\": [ { \"ok\": false, \"error\": {
          \"code\": \"AllKeysExhausted\",
          \"message\": \"'search' failed on every brave key: brave#0: network.\"
  } } ] }
}" ""
chk "SG-4: --json — \"code\": AllKeysExhausted sem 429 → FAILED_OTHER" "$(cls 1)" "FAILED_OTHER"

fx "$ATT_EMPTY

# explain this error from our logs:
brave 429 SUBSCRIPTION_QUOTA_EXCEEDED
Every search failed with AllKeysExhausted — is billing required?

## What was attempted (1 query)
- \`brave error logs\` — returned 0 results" ""
chk "SG-4: pergunta MULTI-LINHA (2ª/3ª linha com os literais) → EMPTY" "$(cls 1)" "EMPTY"
fx "$ATT_EMPTY

# explain this error from our logs:
brave 429 SUBSCRIPTION_QUOTA_EXCEEDED

## What was attempted (1 query)
- \`brave error logs\` — AllKeysExhausted: 'search' failed on every brave key: brave#0: 5xx." ""
chk "SG-4: pergunta multi-linha + erro REAL depois do '## What was attempted' → FAILED_OTHER" "$(cls 1)" "FAILED_OTHER"
fx "" '[surf 10:00:00] ▸ [1/2] "is billing required when monthly quota exhausted"
[surf 10:00:01] ✓ search brave 120ms (1 credits)'
chk "SG-4: query entre ASPAS no progresso do stderr → EMPTY" "$(cls 1)" "EMPTY"
fx "" '[surf 10:00:00] ▸ [1/2] "is billing required"
[surf 10:00:01] ⚠ brave key #0 monthly quota exhausted — skipped, not retried'
chk "SG-4: …e o aviso REAL do progresso (sem aspas) continua FAILED_QUOTA" "$(cls 1)" "FAILED_QUOTA"

# SG-5: byte inválido ANTES da linha do erro. Sob locale UTF-8 o sed BSD aborta
# ("illegal byte sequence") e o resto do arquivo sumia: cota virava EMPTY.
: > "$CASE/o"
{ printf 'lixo \xff\xfe binario\n'
  printf '%s\n' "❌ Error [AllKeysExhausted]: 'search' failed on every brave key: brave#0: 429."; } > "$CASE/e"
for loc in en_US.UTF-8 C; do
  chk "SG-5: byte inválido antes do erro, LC_ALL=$loc → FAILED_QUOTA (nunca EMPTY)" \
      "$(LC_ALL=$loc PATH="$SAFE_PATH" "$GATE_SH" classify 1 "$CASE/o" "$CASE/e" 2>&1)" "FAILED_QUOTA"
done
{ printf '# pergunta com byte \xff invalido\n'; printf 'segunda linha \xfe billing required\n'
  printf '\n## What was attempted (1 query)\n'; printf -- '- `q \xff billing required` — returned 0 results\n'; } > "$CASE/o"
: > "$CASE/e"
chk "SG-5: byte inválido no eco, sem erro real, LC_ALL=en_US.UTF-8 → EMPTY (sem ruído no stderr)" \
    "$(LC_ALL=en_US.UTF-8 PATH="$SAFE_PATH" "$GATE_SH" classify 1 "$CASE/o" "$CASE/e" 2>&1)" "EMPTY"
fx "> ❌ **No sources retrieved — and no search was ever issued.** Not one request reached Brave, so no quota was spent." ""
chk "exit 1 + 'no search was ever issued' → EMPTY" "$(cls 1)" "EMPTY"
fx "" ""
chk "exit 1 sem nenhum padrão → EMPTY" "$(cls 1)" "EMPTY"
chk "exit desconhecido (3) sem padrão → FAILED_OTHER (fail-closed, nunca 'vazio')" "$(cls 3)" "FAILED_OTHER"
chk "exit 127 (binário sumiu no meio da onda) → FAILED_OTHER" "$(cls 127)" "FAILED_OTHER"
rm -f "$CASE/o" "$CASE/e"
chk "arquivos ausentes não derrubam o classify (exit 1 → EMPTY)" "$(cls 1)" "EMPTY"
fx "x" "y"
chk "a saída é UMA palavra, UMA linha" "$(cls 1 | wc -l | tr -d ' ')/$(cls 1 | wc -w | tr -d ' ')" "1/1"
PATH="$SAFE_PATH" "$GATE_SH" classify abc "$CASE/o" "$CASE/e" >/dev/null 2>&1
chk "exit não inteiro → erro de uso (2)" "$?" "2"
PATH="$SAFE_PATH" "$GATE_SH" classify 1 "$CASE/o" >/dev/null 2>&1
chk "faltando argumento → erro de uso (2)" "$?" "2"

section "G10 — pause/resume: estado em \$DO_STATE, pergunta fixa, busca SEMPRE mockada"
newcase
mkbin surf-search-normal 0
mksurf 78 "$MSG_COOLING"
ST="$CASE/state"; mkdir -p "$ST"
out="$(DO_STATE="$ST" RUN_ID="run-teste" gate pause 2 "onda2-api, onda2-ui" "handoff com SEARCH_STATUS: BLOCKED_78")"; rc=$?
chk "pause → exit 0" "$rc" "0"
chk "pause grava \$DO_STATE/search-pause.md" "$([ -f "$ST/search-pause.md" ] && echo 1 || echo 0)" "1"
chk "pause imprime PAUSE_FILE=<path>" "$(field "$out" PAUSE_FILE)" "$ST/search-pause.md"
chk "arquivo: onda" "$(sed -n 's/^- onda: //p' "$ST/search-pause.md")" "2"
chk "arquivo: sub-tarefas bloqueadas" "$(sed -n 's/^- sub-tarefas bloqueadas: //p' "$ST/search-pause.md")" "onda2-api, onda2-ui"
chk "arquivo: motivo" "$(sed -n 's/^- motivo: //p' "$ST/search-pause.md")" "handoff com SEARCH_STATUS: BLOCKED_78"
chk "arquivo: SURF_GATE/SURF_CODE" \
    "$(sed -n 's/^- SURF_GATE: //p' "$ST/search-pause.md")/$(sed -n 's/^- SURF_CODE: //p' "$ST/search-pause.md")" "78/BraveKeyCooling"
chk "arquivo: data ISO-8601 UTC" "$(grep -cE '^- data: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$ST/search-pause.md")" "1"
chk "arquivo: mensagem do portão VERBATIM" "$(grep -cF 'every Brave Search key is rate-limited right now.' "$ST/search-pause.md")" "2"
chk "bloco da pergunta: título do protocolo" "$(printf '%s\n' "$out" | grep -c '^===== PESQUISA-FALHOU')" "1"
chk "bloco da pergunta: as 4 opções numeradas" "$(printf '%s\n' "$out" | grep -cE '^  \[[1-4]\] ')" "4"
chk "opção [1]: comando EXATO de chave sem TTY" \
    "$(printf '%s\n' "$out" | grep -F '[1]' | grep -cF 'surf-research-skill keys add --provider brave <CHAVE>')" "1"
chk "opção [1]: interativo só em terminal separado ('surf add')" \
    "$(printf '%s\n' "$out" | grep -F '[1]' | grep -cF 'terminal separado: `surf add`')" "1"
chk "opção [2]: comando EXATO que limpa burn/cooldown" \
    "$(printf '%s\n' "$out" | grep -F '[2]' | grep -cF 'surf-research-skill keys reset --provider brave')" "1"
chk "opção [3]: seguir SEM pesquisa marca NÃO VERIFICADAS" "$(printf '%s\n' "$out" | grep -F '[3]' | grep -c 'NÃO VERIFICADAS')" "1"
chk "opção [4]: abortar = purge + relatório parcial" "$(printf '%s\n' "$out" | grep -F '[4]' | grep -c 'purge')" "1"
chk "bloco lista as sub-tarefas bloqueadas" "$(printf '%s\n' "$out" | grep -c '^Sub-tarefas bloqueadas: onda2-api, onda2-ui$')" "1"
chk "bloco cola a mensagem VERBATIM do portão" "$(printf '%s\n' "$out" | grep -cF '❌ Error [BraveKeyCooling]')" "1"
chk "bloco NUNCA manda 'keys list --json'" "$(printf '%s\n' "$out" | grep -c 'keys list')" "0"

out="$(DO_STATE="$ST" gate resume)"; rc=$?
chk "resume com portão ainda 78 → RESUME=STILL_BLOCKED" "$(field "$out" RESUME)" "STILL_BLOCKED"
chk "STILL_BLOCKED mantém o search-pause.md" "$([ -f "$ST/search-pause.md" ] && echo 1 || echo 0)" "1"
chk "STILL_BLOCKED repete a pergunta (4 opções)" "$(printf '%s\n' "$out" | grep -cE '^  \[[1-4]\] ')" "4"
chk "STILL_BLOCKED repete com as MESMAS sub-tarefas" "$(printf '%s\n' "$out" | grep -c '^Sub-tarefas bloqueadas: onda2-api, onda2-ui$')" "1"
chk "resume sai 0 (o veredito é a linha RESUME=)" "$rc" "0"
out="$(DO_STATE="$ST" gate resume --probe)"
chk "portão fechado + --probe → NÃO gasta o crédito da sonda" "$(calls "$CASE/search.calls")" "0"
chk "portão fechado + --probe → STILL_BLOCKED" "$(field "$out" RESUME)" "STILL_BLOCKED"

mksurf 0
out="$(DO_STATE="$ST" gate resume)"
chk "portão reabriu → RESUME=OK" "$(field "$out" RESUME)" "OK"
chk "RESUME=OK apaga o search-pause.md" "$([ -f "$ST/search-pause.md" ] && echo 1 || echo 0)" "0"
chk "resume sem --probe nunca busca" "$(calls "$CASE/search.calls")" "0"

# Cota: o portão grátis fica VERDE (a sonda de validação não enxerga cota) —
# só a sonda real de 1 crédito (aqui: mock) distingue.
out="$(DO_STATE="$ST" gate pause 3 "onda3-sdk" "2 handoffs FAILED_QUOTA")"
chk "pause com portão verde explica que ele não enxerga cota" "$(printf '%s\n' "$out" | grep -c 'NÃO enxerga cota')" "1"
printf '1' > "$CASE/search.rc"
printf '%s\n' "❌ Error [AllKeysExhausted]: 'search' failed on every brave key: brave#0: 429." > "$CASE/search.err"
out="$(DO_STATE="$ST" gate resume --probe)"
chk "--probe com cota esgotada → PROBE=FAILED_QUOTA" "$(field "$out" PROBE)" "FAILED_QUOTA"
chk "--probe com cota esgotada → RESUME=STILL_BLOCKED" "$(field "$out" RESUME)" "STILL_BLOCKED"
chk "--probe faz EXATAMENTE uma busca" "$(calls "$CASE/search.calls")" "1"
chk "--probe usa a busca barata documentada (1 crédito)" \
    "$(cat "$CASE/search.calls")" "search brave search api --max 1 --no-cache --quiet"
chk "STILL_BLOCKED mostra o stderr da sonda" "$(printf '%s\n' "$out" | grep -c 'brave#0: 429')" "1"
DO_STATE="$ST" gate resume --probe >/dev/null
chk "retomadas repetidas não acumulam 'sonda real' no motivo" \
    "$(sed -n 's/^- motivo: //p' "$ST/search-pause.md" | grep -o 'sonda real' | wc -l | tr -d ' ')" "1"
printf '0' > "$CASE/search.rc"; : > "$CASE/search.err"; printf '%s\n' "1 result" > "$CASE/search.out"
out="$(DO_STATE="$ST" gate resume --probe)"
chk "--probe com busca OK → PROBE=OK" "$(field "$out" PROBE)" "OK"
chk "--probe com busca OK → RESUME=OK" "$(field "$out" RESUME)" "OK"
chk "RESUME=OK (probe) apaga o search-pause.md" "$([ -f "$ST/search-pause.md" ] && echo 1 || echo 0)" "0"

# SG-6: `resume --probe` como SONDA do gatilho g3 — NÃO existe pausa gravada.
# Só veredito + mensagem: nada em disco, nenhuma pergunta com campos "-".
printf '1' > "$CASE/search.rc"; : > "$CASE/search.out"; : > "$CASE/search.calls"
printf '%s\n' "❌ Error [AllKeysExhausted]: 'search' failed on every brave key: brave#0: 429." > "$CASE/search.err"
out="$(DO_STATE="$ST" gate resume --probe)"; rc=$?
chk "SG-6: resume --probe sem pausa prévia → PROBE/RESUME saem normalmente" \
    "$(field "$out" PROBE)/$(field "$out" RESUME)/$rc" "FAILED_QUOTA/STILL_BLOCKED/0"
chk "SG-6: …NÃO grava search-pause.md" "$([ -e "$ST/search-pause.md" ] && echo 1 || echo 0)" "0"
chk "SG-6: …NÃO imprime a pergunta (nem título, nem [1]-[4], nem campos '-')" \
    "$(printf '%s\n' "$out" | grep -cE '^  \[[1-4]\] |^===== PESQUISA-FALHOU|^Onda: |^Sub-tarefas bloqueadas: ')" "0"
chk "SG-6: …mostra a mensagem (stderr da sonda)" "$(printf '%s\n' "$out" | grep -c 'brave#0: 429')" "1"
chk "SG-6: …e aponta o próximo passo (NEXT= com o comando pause)" \
    "$(printf '%s\n' "$out" | grep -c '^NEXT=.*"$DO_SURF_GATE" pause <onda>')" "1"
chk "SG-6: a sonda continua sendo UMA busca" "$(calls "$CASE/search.calls")" "1"
mksurf 78 "$MSG_COOLING"
out="$(DO_STATE="$ST" gate resume)"
chk "SG-6: resume (portão 78) sem pausa prévia → STILL_BLOCKED + mensagem VERBATIM, sem pergunta e sem arquivo" \
    "$(field "$out" RESUME)/$(printf '%s\n' "$out" | grep -cF '❌ Error [BraveKeyCooling]')/$(printf '%s\n' "$out" | grep -cE '^  \[[1-4]\] ')/$([ -e "$ST/search-pause.md" ] && echo 1 || echo 0)" \
    "STILL_BLOCKED/1/0/0"
out="$(gate resume --probe)"
chk "SG-6: resume sem DO_STATE → STILL_BLOCKED + NEXT=, sem pergunta" \
    "$(field "$out" RESUME)/$(printf '%s\n' "$out" | grep -c '^NEXT=')/$(printf '%s\n' "$out" | grep -cE '^  \[[1-4]\] ')" "STILL_BLOCKED/1/0"
mksurf 0
printf '0' > "$CASE/search.rc"; : > "$CASE/search.err"; printf '%s\n' "1 result" > "$CASE/search.out"

out="$(gate pause 1 "onda1-x" "sem estado" 2>/dev/null)"; rc=$?
chk "pause SEM DO_STATE → exit 2 (estado não gravado)…" "$rc" "2"
chk "…mas a PERGUNTA sai de qualquer jeito" "$(printf '%s\n' "$out" | grep -cE '^  \[[1-4]\] ')" "4"
DO_STATE="$ST" gate pause 4 "a
b" "m1
m2" >/dev/null
chk "argumento multi-linha vira UMA linha no arquivo" "$(sed -n 's/^- sub-tarefas bloqueadas: //p' "$ST/search-pause.md")" "a b"
gate pause 1 >/dev/null 2>&1
chk "pause sem os 3 argumentos → erro de uso (2)" "$?" "2"
gate resume --sonda >/dev/null 2>&1
chk "resume com flag desconhecida → erro de uso (2)" "$?" "2"
gate explode >/dev/null 2>&1
chk "subcomando desconhecido → erro de uso (2)" "$?" "2"

section "G10b — choose no-search|search: a opção [3] vira ESTADO (SURF_MODE=no-search)"
# SG-1: cota/429 deixa o portão grátis VERDE — a decisão do usuário não pode
# depender do veredito SURF_GATE=. Ela mora em $DO_STATE/search-mode.
newcase
mkbin surf-search-normal 0
mksurf 0
ST="$CASE/state"; mkdir -p "$ST"
chk "sem search-mode: portão verde continua EXATAMENTE 'SURF_GATE=0'" "$(DO_STATE="$ST" gate)" "SURF_GATE=0"
DO_STATE="$ST" gate pause 2 "onda2-api" "FAILED_QUOTA" >/dev/null
out="$(DO_STATE="$ST" gate choose no-search)"; rc=$?
chk "choose no-search → exit 0 + SURF_MODE=no-search + MODE_FILE=" \
    "$rc/$(field "$out" SURF_MODE)/$(field "$out" MODE_FILE)" "0/no-search/$ST/search-mode"
chk "choose no-search grava \$DO_STATE/search-mode = no-search" "$(cat "$ST/search-mode" 2>/dev/null)" "no-search"
chk "choose no-search APAGA o search-pause.md (a pergunta foi respondida)" "$([ -e "$ST/search-pause.md" ] && echo 1 || echo 0)" "0"
chk "choose não deixa arquivo temporário para trás" "$(ls -A "$ST" | grep -c 'tmp')" "0"
out="$(DO_STATE="$ST" gate)"
chk "portão VERDE + no-search → 'SURF_GATE=0' E 'SURF_MODE=no-search'" "$out" "SURF_GATE=0
SURF_MODE=no-search"
chk "surf-gate.last também carrega o SURF_MODE" "$(grep -c '^SURF_MODE=no-search$' "$ST/surf-gate.last")" "1"
DO_STATE="$ST" gate choose no-search >/dev/null
chk "choose no-search é idempotente" "$(cat "$ST/search-mode")/$(field "$(DO_STATE="$ST" gate)" SURF_MODE)" "no-search/no-search"
mksurf 78 "$MSG_COOLING"
out="$(DO_STATE="$ST" gate)"
chk "portão 78 + no-search → as 3 linhas CHAVE=valor saem ANTES da mensagem" \
    "$(printf '%s\n' "$out" | sed -n '1,3p' | tr '\n' ' ')" "SURF_GATE=78 SURF_CODE=BraveKeyCooling SURF_MODE=no-search "
chk "…e a mensagem VERBATIM continua inteira" "$(printf '%s\n' "$out" | grep -c '^Fix: wait for the cooldown')" "1"
out="$(DO_STATE="$ST" gate resume)"
chk "resume também mostra SURF_MODE=no-search (e o modo NÃO muda sozinho)" \
    "$(field "$out" SURF_MODE)/$(cat "$ST/search-mode")" "no-search/no-search"
err="$(DO_STATE="$ST" gate pause 3 "onda3-x" "engano" 2>&1 >/dev/null)"
chk "pause sob no-search AVISA no stderr que o usuário já escolheu [3]" "$(printf '%s\n' "$err" | grep -c 'SURF_MODE=no-search')" "1"
rm -f "$ST/search-pause.md"
mksurf 0
out="$(DO_STATE="$ST" gate choose search)"; rc=$?
chk "choose search → exit 0 + SURF_MODE=search + arquivo apagado" \
    "$rc/$(field "$out" SURF_MODE)/$([ -e "$ST/search-mode" ] && echo 1 || echo 0)" "0/search/0"
chk "depois do choose search o portão volta a 'SURF_GATE=0' puro" "$(DO_STATE="$ST" gate)" "SURF_GATE=0"
DO_STATE="$ST" gate choose search >/dev/null 2>&1
chk "choose search sem arquivo é idempotente (exit 0)" "$?" "0"
out="$(DO_STATE="$CASE/novo/state" gate choose no-search)"
chk "choose no-search cria o \$DO_STATE que falta (como o pause)" "$(cat "$CASE/novo/state/search-mode" 2>/dev/null)" "no-search"
out="$(gate choose no-search 2>/dev/null)"; rc=$?
chk "choose SEM DO_STATE → exit 2 e NENHUMA linha SURF_MODE= (escolha não gravada)" "$rc/$(printf '%s\n' "$out" | grep -c '^SURF_MODE=')" "2/0"
gate choose talvez >/dev/null 2>&1
chk "choose com valor desconhecido → erro de uso (2)" "$?" "2"
gate choose >/dev/null 2>&1
chk "choose sem argumento → erro de uso (2)" "$?" "2"
chk "choose NUNCA busca nem chama 'keys'" "$(calls "$CASE/search.calls")/$(calls "$CASE/forbidden.calls")" "0/0"

section "G11 — instalação e higiene bash 3.2 do surf-gate.sh"
ok "scripts/surf-gate.sh existe e é executável" "$([ -x "$GATE_SH" ]; echo $?)"
ok "bash -n surf-gate.sh" "$(bash -n "$GATE_SH" 2>/dev/null; echo $?)"
ok "sem array associativo / mapfile / \${var,,} / sed -i (macOS, bash 3.2, sed BSD)" \
   "$(! grep -nE 'declare -A|local -A|mapfile|readarray|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)|sed -i' "$GATE_SH" >/dev/null; echo $?)"
ok "surf-gate.sh nunca lê keys.json nem roda 'keys list' (só os cita como proibidos, em comentário)" \
   "$(! grep -vE '^[[:space:]]*#' "$GATE_SH" | grep -qE 'keys\.json|keys list'; echo $?)"
help="$(PATH="$SAFE_PATH" "$GATE_SH" --help)"
chk "--help imprime o cabeçalho INTEIRO (até o marcador, sem número de linha)" \
    "$(printf '%s\n' "$help" | grep -c -e 'surf-gate.sh resume \[--probe\]' -e 'Exit codes:')" "2"
chk "--help não vaza o marcador de fim" "$(printf '%s\n' "$help" | grep -c 'FIM-DO-CABECALHO')" "0"
ok "--help documenta 'choose no-search|search' e a linha SURF_MODE=no-search" \
   "$(grep -qF 'surf-gate.sh choose no-search|search' <<< "$help" && grep -qF 'SURF_MODE=no-search' <<< "$help"; echo $?)"
usage="$(PATH="$SAFE_PATH" "$GATE_SH" explode 2>&1 >/dev/null)"
chk "a linha de uso (erro 2) lista o choose" "$(printf '%s\n' "$usage" | grep -c 'choose no-search|search')" "1"
ok "check-install.sh registra scripts/surf-gate.sh" \
   "$(grep -q '"\$ROOT/scripts/surf-gate.sh" x' "$ROOT/scripts/check-install.sh"; echo $?)"
# Casa falsa = a real por symlink, MENOS o surf-gate.sh → precisa acusar a falta.
newcase
mkdir -p "$CASE/home/scripts"
ln -s "$ROOT/SKILL.md" "$CASE/home/SKILL.md"
ln -s "$ROOT/prompts" "$CASE/home/prompts"
for f in "$ROOT/scripts/"*; do
  [ "$(basename "$f")" = "surf-gate.sh" ] || ln -s "$f" "$CASE/home/scripts/$(basename "$f")"
done
out="$(bash "$ROOT/scripts/check-install.sh" --root "$CASE/home" 2>&1)"; rc=$?
chk "instalação sem surf-gate.sh → INCOMPLETA (exit 1)" "$rc" "1"
chk "…e o item faltando é o surf-gate.sh" "$(printf '%s\n' "$out" | grep -c '^  - scripts/ surf-gate.sh$')" "1"
ln -s "$GATE_SH" "$CASE/home/scripts/surf-gate.sh"
bash "$ROOT/scripts/check-install.sh" --root "$CASE/home" --quiet; rc=$?
chk "com o surf-gate.sh no lugar → COMPLETA (exit 0)" "$rc" "0"

section "G12 — integração v4.1.0: o MESMO contrato em SKILL.md, scripts e prompts"
# Cópias literais de um mesmo contrato vivem em arquivos de donos diferentes;
# quem mudar um lado sem o outro quebra aqui, não em produção.
newcase
mkbin surf-search-normal 0
mksurf 78 "$MSG_COOLING"
mkdir -p "$CASE/state"
out="$(DO_STATE="$CASE/state" RUN_ID="run-g12" gate pause 1 "onda1-x" "g12")"
miss=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  grep -qF -- "$line" "$SKILL_MD" || { miss=$((miss+1)); printf '    (ausente no SKILL.md) %s\n' "$line"; }
done <<EOF
$(printf '%s\n' "$out" | grep -E '^  \[[1-4]\] |^===== PESQUISA-FALHOU|^Rode os comandos no SEU terminal|^Outros: remover chave morta')
EOF
chk "o texto FIXO da pergunta (título, [1]-[4], adendos) do 'pause' está LITERAL no protocolo do SKILL.md" "$miss" "0"
SS='SEARCH_STATUS: NOT_NEEDED | OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78'
ok "a linha SEARCH_STATUS do handoff é a MESMA no SKILL.md e em prompts/search-prompts.md" \
   "$(grep -qF -- "$SS" "$SKILL_MD" && grep -qF -- "$SS" "$ROOT/prompts/search-prompts.md"; echo $?)"
ok "o template de sub-agente classifica com scripts/surf-gate.sh classify" \
   "$(grep -qF 'surf-gate.sh" classify' "$SKILL_MD"; echo $?)"
ok "prompts: [Verify this] com 78/127/cota vai ao protocolo (nunca 'MANTENHA a premissa' por conta própria)" \
   "$(grep -q 'PESQUISA-FALHOU' "$ROOT/prompts/plan-approval-prompts.md" && ! grep -qF 'MANTENHA a premissa' "$ROOT/prompts/plan-approval-prompts.md"; echo $?)"
ok "SKILL.md: os pontos de decisão da pesquisa existem (SEARCH_REQUIRED, PORTÃO PÓS-PLANO, TRIAGEM DE PESQUISA, resume --probe)" \
   "$(grep -q 'SEARCH_REQUIRED' "$SKILL_MD" && grep -q 'PORTÃO PÓS-PLANO' "$SKILL_MD" && grep -q 'TRIAGEM DE PESQUISA' "$SKILL_MD" && grep -qF 'resume --probe' "$SKILL_MD"; echo $?)"
ok "SKILL.md: frases do desenho antigo saíram ('PESQUISA IMPOSSÍVEL', 'se sair 78, mantenha a premissa')" \
   "$(! grep -qF 'PESQUISA IMPOSSÍVEL' "$SKILL_MD" && ! grep -qF 'se sair 78, mantenha a premissa' "$SKILL_MD"; echo $?)"
ok "SKILL.md: FASE 0 entrega as flags ao script (--flags='<TOKENS>') e nunca manda exportar variável" \
   "$(grep -qF -- "--flags='&lt;TOKENS&gt;'" "$SKILL_MD" && grep -q 'ESTADOS PENDENTES' "$SKILL_MD" && ! grep -qw 'exporte' "$SKILL_MD"; echo $?)"
ok "SKILL.md: limpeza por tarefa pelo script (integrate/gate, assert-clean --wave <N+1>, PURGE_RC, 'Não integrado')" \
   "$(grep -qF '"$DO_WT" integrate' "$SKILL_MD" && grep -qF 'assert-clean --wave &lt;N+1&gt;' "$SKILL_MD" \
      && grep -q 'PURGE_RC' "$SKILL_MD" && grep -qF '## Não integrado' "$SKILL_MD" \
      && grep -qF 'Tarefa concluída PARCIALMENTE' "$SKILL_MD"; echo $?)"
ok "SKILL.md: o passo 7/8 antigos saíram ('mark <nome> gate-pending', 'sweep; verify' sem assert-clean)" \
   "$(! grep -qF 'mark &lt;nome&gt; gate-pending' "$SKILL_MD" && ! grep -qF '"$DO_WT" sweep; "$DO_WT" verify' "$SKILL_MD"; echo $?)"
ok "SKILL.md: flags de teste chegam aos templates ({{TEST_POLICY}}, e2e-runner-unavailable; 'TDD Workflow' saiu)" \
   "$(grep -qF '{{TEST_POLICY}}' "$SKILL_MD" && grep -qF 'case id="e2e-runner-unavailable"' "$SKILL_MD" && ! grep -qF 'TDD Workflow' "$SKILL_MD"; echo $?)"
# Todo subcomando citado como "$DO_WT" <sub> / "$DO_SURF_GATE" <sub> existe no dispatch.
unk=""
for sub in $(sed -e 's/&quot;/"/g' "$SKILL_MD" "$ROOT/README.md" "$ROOT/scripts/README.md" \
             | grep -oE '"\$DO_WT" [a-z][a-z-]*' | awk '{print $2}' | sort -u); do
  grep -qE "^  $sub\)" "$ROOT/scripts/do-wt.sh" || unk="$unk $sub"
done
chk "todo '\"\$DO_WT\" <sub>' de SKILL.md/README/scripts README existe no dispatch do do-wt.sh" "$unk" ""
unk=""
for sub in $(grep -ohE '"\$DO_SURF_GATE" [a-z][a-z-]*' "$SKILL_MD" "$ROOT/README.md" "$ROOT/scripts/README.md" "$ROOT"/prompts/*.md \
             | awk '{print $2}' | sort -u); do
  grep -qE "^  $sub\)" "$GATE_SH" || unk="$unk $sub"
done
chk "todo '\"\$DO_SURF_GATE\" <sub>' citado existe no dispatch do surf-gate.sh" "$unk" ""
# Toda flag do argument-hint está na tabela do do-context.sh e no README.
hint="$(sed -n 's/^argument-hint: *//p' "$SKILL_MD" | head -n 1)"
unk=""
for tok in 'plan=' 'max-parallel=' 'surf-sub-agents=' 'wt=' 'no-stop' 'no-evolve' 'no-test' 'only-e2e' 'do-question'; do
  case "$hint" in *"$tok"*) : ;; *) unk="$unk hint:$tok" ;; esac
  grep -qE "^ +${tok}[^)]*\)" "$ROOT/scripts/do-context.sh" || unk="$unk ctx:$tok"
  grep -qF -- "$tok" "$ROOT/README.md" || unk="$unk readme:$tok"
done
chk "as 9 flags do argument-hint estão na tabela do do-context.sh e no README" "$unk" ""
# description <= 1024 (a listagem de skills trunca acima disso e esconde flags/triggers).
if command -v ruby >/dev/null 2>&1; then
  dl="$(ruby -ryaml -e 't=File.read(ARGV[0]); y=YAML.safe_load(t.split(/^---\s*$/)[1]); puts y["description"].length' "$SKILL_MD" 2>/dev/null)"
  ok "frontmatter parseia como YAML e description <= 1024 chars (é ${dl:-?})" "$([ -n "$dl" ] && [ "$dl" -le 1024 ]; echo $?)"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  dl="$(python3 -c 'import sys,yaml; t=open(sys.argv[1],encoding="utf-8").read(); print(len(yaml.safe_load(t.split("\n---")[0].split("---\n",1)[1])["description"]))' "$SKILL_MD" 2>/dev/null)"
  ok "frontmatter parseia como YAML e description <= 1024 chars (é ${dl:-?})" "$([ -n "$dl" ] && [ "$dl" -le 1024 ]; echo $?)"
else
  printf '  (pulado: sem ruby nem python3+PyYAML para parsear o frontmatter)\n'
fi
if command -v python3 >/dev/null 2>&1; then
  ok "o <orchestrator> do SKILL.md parseia como XML inteiro (nenhum '<' ou '&' cru fora de CDATA)" \
     "$(python3 -c 'import sys,re,xml.etree.ElementTree as E; t=open(sys.argv[1],encoding="utf-8").read(); m=re.search(r"<orchestrator[\s>].*</orchestrator>",t,re.S); E.fromstring(m.group(0))' "$SKILL_MD" 2>/dev/null; echo $?)"
else
  printf '  (pulado: sem python3 para parsear o XML)\n'
fi

# Rodada final (DESIGN-2): literais de INTERFACE dos outros scripts que o
# SKILL.md tem de citar (do-context.sh --boundary=, do-wt.sh MERGED-PARTIAL e
# `checklist final`).
for lit in "--boundary=" "MERGED-PARTIAL" "checklist final"; do
  ok "[DESIGN-2] SKILL.md cita o literal '$lit'" "$(grep -qF -- "$lit" "$SKILL_MD"; echo $?)"
done
if command -v python3 >/dev/null 2>&1; then
  # ORÇAMENTO: a condensação (DESIGN-2 parte C) mira <= 215.000; o teto duro é 220.000.
  sz="$(python3 -c 'import sys; print(len(open(sys.argv[1],encoding="utf-8").read()))' "$SKILL_MD" 2>/dev/null)"
  ok "[DESIGN-2] ORÇAMENTO: SKILL.md <= 220000 caracteres (é ${sz:-?})" "$([ -n "$sz" ] && [ "$sz" -le 220000 ]; echo $?)"
else
  printf '  (pulado: sem python3 para medir o SKILL.md em caracteres)\n'
fi
# B01: os números de passo do CARTÃO ("$DO_WT" checklist) são os MESMOS dos
# <step order> da FASE 3 — re-ancorar pelo cartão não pode trocar "passo 7".
steps3="$(awk '/<phase id="3"/{p=1} p && /<\/phase>/{p=0} p' "$SKILL_MD" \
          | sed -nE 's/.*<step order="([0-9]+(\.[0-9]+)?)".*/\1/p' | sort -u)"
cardnums() { # lê o cartão no stdin → números de passo (linha que COMEÇA com "N." / "N.N")
  sed -nE 's/^ {0,2}([0-9]+(\.[0-9]+)?)\.?[[:space:]].*/\1/p' | sort -u
}
card="$( { PATH="$SAFE_PATH" bash "$ROOT/scripts/do-wt.sh" checklist
           DO_QUESTION=1 PATH="$SAFE_PATH" bash "$ROOT/scripts/do-wt.sh" checklist; } 2>/dev/null | cardnums)"
chk "a FASE 3 do SKILL.md tem os 13 <step order> congelados (0 1 2 3 3.5 4 4.5 5 6 7 8 9 10)" \
    "$(printf '%s\n' "$steps3" | sort -n | tr '\n' ' ')" "0 1 2 3 3.5 4 4.5 5 6 7 8 9 10 "
if grep -qE '^(3\.5|4\.5)$' <<< "$card"; then
  extra=""
  for n in $card; do
    grep -qxF -- "$n" <<< "$steps3" || extra="$extra $n"
  done
  chk "os números de passo do '\"\$DO_WT\" checklist' ⊆ <step order> da FASE 3 (fora:$extra)" "$extra" ""
else
  printf '  (pulado — PENDENTE-DE-INTEGRACAO: o cartão do do-wt.sh checklist ainda não foi renumerado [sem 3.5/4.5]; números atuais: %s)\n' \
         "$(printf '%s' "$card" | sort -n | tr '\n' ' ')"
fi

section "G13 — hermeticidade (SG-2): ambiente de run VIVO herdado não muda nada"
# A suíte é re-executada com DO_STATE/RUN_ID/DO_* EXPORTADOS (como faz o
# ENV_FILE). Tem de dar os MESMOS números e não tocar o $DO_STATE herdado.
if [ -z "${SG_NESTED:-}" ]; then
  newcase
  mkdir -p "$CASE/live/state"
  P0=$PASS; F0=$FAIL   # a execução aninhada não roda o G13: compara com o placar ATÉ aqui
  nested="$(SG_NESTED=1 DO_STATE="$CASE/live/state" RUN_ID="run-vivo" DO_SURF_GATE="/nao/existe/surf-gate.sh" \
            DO_TEST_MODE=none DO_QUESTION=1 OWNED="$CASE/live/state/owned.tsv" \
            "${BASH:-/bin/bash}" "$SCRIPT_DIR/$(basename "$0")" 2>&1)"
  chk "com DO_STATE/RUN_ID herdados a suíte não cria NADA no \$DO_STATE do run vivo" \
      "$(find "$CASE/live" -mindepth 1 | sed "s|^$CASE/live/||" | tr '\n' ' ')" "state "
  chk "…o caso 'pause SEM DO_STATE → exit 2' passa mesmo com DO_STATE herdado" \
      "$(printf '%s\n' "$nested" | grep '✓' | grep -c 'pause SEM DO_STATE → exit 2')" "1"
  chk "…e o resultado é IDÊNTICO ao desta execução (mesmos passaram/falharam)" \
      "$(printf '%s\n' "$nested" | sed -n 's/.* \([0-9][0-9]*\) passaram, \([0-9][0-9]*\) falharam.*/\1 \2/p')" "$P0 $F0"
else
  printf '  (execução aninhada: G13 não se re-executa)\n'
fi

printf '\n\033[1mRESULTADO:\033[0m %d passaram, %d falharam\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "surf-gate-ok"
