#!/usr/bin/env bash
# Testes de aceitação do PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5) — P1..P28 + G1..G9
#
# NENHUM teste abre navegador, sobe servidor, baixa binário ou toca a rede: o
# Plannotator é um bin FAKE num PATH temporário, e o instalador é um bin FAKE.
# Cada caso tem HOME próprio, para que ~/.local/bin/plannotator de um caso não
# contamine o seguinte.
#
# check-plannotator.sh (G*)
#   G1: binário presente e capaz → exit 0, status AVAILABLE
#   G2: DO_PLANNOTATOR_BIN vence o PATH
#   G3: ausente do PATH mas presente em ~/.local/bin → encontrado (o shell do
#       agente frequentemente não tem ~/.local/bin no PATH)
#   G4: ausente + curl ausente → exit 2 (não instalável)
#   G5: ausente + curl OK → exit 1 sem --install (reporta, não instala)
#   G6: ausente + --install → instalador roda com --minimal --non-interactive,
#       binário aparece, reavaliação → exit 0
#   G7: binário cujo `annotate` NÃO anuncia --gate/--json → INCAPABLE
#   G8: DO_PLANNOTATOR_INSTALL=0 proíbe a instalação mesmo com --install
#
# plan-approval.sh (P*)
#   P1:  round → approved            → exit 0
#   P2:  round → annotated           → exit 10 + feedback gravado
#   P3:  round → dismissed           → exit 11
#   P4:  round → timeout (bin trava) → exit 12
#   P5:  round → bin falha (exit≠0)  → exit 13
#   P6:  round → stdout ilegível     → exit 13
#   P7:  argv exato: annotate <snapshot> --gate --json
#   P8:  snapshot é IMUTÁVEL e é ELE que vai ao Plannotator (não o arquivo vivo)
#   P9:  numeração de revisões incrementa; trail.tsv append-only e parseável
#   P10: deriva de TÍTULO entre revisões → exit 2 (recusado, com diagnóstico)
#   P11: título igual entre revisões → aceito
#   P12: documento sem H1 → exit 2
#   P13: documento ausente → exit 2 ; documento vazio → exit 2
#   P14: orçamento esgotado → exit 14 (sem chamar o Plannotator)
#   P15: PLANNOTATOR_SHARE=disabled por default
#   P16: DO_PLAN_SHARE=1 NÃO desliga o compartilhamento
#   P17: PLANNOTATOR_CWD = BASE_DIR
#   P18: origin: claude-code > pi > jcode > opencode (prioridade pedida)
#   P19: jcode não emite PLANNOTATOR_ORIGIN (não é chave do Plannotator)
#   P20: feedback com aspas, newlines e acentos sobrevive ao round-trip
#   P21: stdout com ruído antes do JSON → última linha JSON vence
#   P22: annotated com feedback VAZIO → degrada para dismissed (exit 11)
#   P23: nada é escrito fora de $PLAN_APPROVAL_DIR
#   P24: `feedback` e `doc` resolvem a última revisão por default
#   P25: sem jq E sem python3 → exit 2 com mensagem acionável
#   P26: DO_PLAN_MAX_REVISIONS / DO_PLAN_TIMEOUT inválidos → exit 2
#   P27: `approved` é falso antes e depois de `annotated`, verdadeiro após
#        `approved` — a idempotência que o DO_REUSE da FASE 0 exige
#   P28: `approved` reporta a revisão aprovada
#   P29: timeout(1) estilo BSD (sem --foreground/-k) e timeout(1) AUSENTE — a
#        rodada continua correta nos dois; as flags são SONDADAS, não presumidas
#   DC1-DC3: do-context.sh exporta DO_PLAN_*/PLAN_APPROVAL_DIR/PLAN_DOC,
#        valida a entrada e anuncia PLAN_APPROVAL = ON/OFF no resumo
#   R1..R8: regressões dos 7 defeitos confirmados pela revisão adversarial —
#        R1 PLANNOTATOR_REMOTE=0 (o plano nunca é servido na LAN por causa de
#           SSH_TTY/SSH_CONNECTION, e /api/approve não tem autenticação)
#        R2 rodada interrompida (snapshot 0444 sem linha no trail) não trava
#        R3 falha de I/O no snapshot é 13, não 2 ("deriva de título")
#        R4 json_escape não come a letra `t` (sed do BSD não conhece \t)
#        R5 sync-global-skill não se autodestrói quando o destino É a casa
#        R6 cópia velha vira symlink verificado; diretório alheio é preservado
#        R7 DO_REUSE não reaproveita env com PLAN_APPROVAL divergente
#        R8 FASE 0 cria o diretório do plano quando o portão está ON
#   DC4: com o portão DESLIGADO (o default), a FASE 0 não cria diretório do
#        portão, não escreve o documento e não deixa artefato nenhum — quem não
#        pediu um plano tem o comportamento autônomo idêntico ao de antes
set -uo pipefail
SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
CHECK="$SKILL/scripts/check-plannotator.sh"
GATE="$SKILL/scripts/plan-approval.sh"
LAB="${TMPDIR:-/tmp}/plan-approval-accept-$$"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (esperado='$3' obtido='$2')"; fi; }
has()  { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (não achei '$3' em: $(printf '%s' "$2" | head -c 300))"; fi; }
hasnt(){ if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1 (achei '$3' e não devia)"; else ok "$1"; fi; }

ORIG_PATH="$PATH"
rm -rf "$LAB"; mkdir -p "$LAB"; cd "$LAB"
trap 'chmod -R u+w "$LAB" 2>/dev/null; rm -rf "$LAB"' EXIT

# Toda variável de harness precisa sair do ambiente: o suite roda DENTRO de um
# agente, e o CLAUDECODE dele vazaria para os casos de detecção.
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID \
      PI_CODING_AGENT PI_SESSION_ID PI_CODING_AGENT_DIR \
      JCODE_SESSION_ID JCODE_HOME OPENCODE OPENCODE_BIN_PATH \
      CODEX_THREAD_ID COPILOT_CLI GEMINI_CLI \
      DO_PLAN_ORIGIN DO_PLAN_SHARE DO_PLANNOTATOR_BIN \
      DO_PLANNOTATOR_INSTALL DO_PLANNOTATOR_INSTALL_URL DO_PLANNOTATOR_INSTALL_ARGS \
      DO_PLAN_MAX_REVISIONS DO_PLAN_TIMEOUT PLANNOTATOR_ORIGIN PLANNOTATOR_SHARE

# --- helpers -----------------------------------------------------------------
# newcase <nome>: dir próprio (bin/ + home/ + world/), env limpo por caso
newcase() {
  CASE="$LAB/$1"
  CASE_BIN="$CASE/bin"
  mkdir -p "$CASE_BIN" "$CASE/home/.local/bin" "$CASE/world" "$CASE/state"
  export CASE CASE_BIN
  export HOME="$CASE/home"
  # CLAUDE_CONFIG_DIR real (ex.: ~/.claude-k2.frederico) sobrevive ao HOME
  # falso e faria o sync-global-skill escrever na configuração DE VERDADE do
  # usuário durante o teste. Ancorar no HOME do caso é obrigatório.
  export CLAUDE_CONFIG_DIR="$CASE/home/.claude"
  export PATH="$CASE_BIN:$ORIG_PATH"
  export DO_STATE="$CASE/state"
  export BASE_DIR="$CASE/world"
  export PLAN_APPROVAL_DIR="$DO_STATE/plan-approval"
  unset DO_PLANNOTATOR_BIN DO_PLAN_SHARE DO_PLAN_ORIGIN DO_PLAN_REMOTE DO_PLANNOTATOR_INSTALL \
        DO_PLANNOTATOR_INSTALL_URL DO_PLANNOTATOR_INSTALL_ARGS \
        DO_PLAN_MAX_REVISIONS DO_PLAN_TIMEOUT \
        CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID \
        PI_CODING_AGENT PI_SESSION_ID PI_CODING_AGENT_DIR \
        JCODE_SESSION_ID JCODE_HOME OPENCODE OPENCODE_BIN_PATH
  cd "$CASE"
}

# minpath <dir> [extra...]: popula <dir> com as ferramentas que os scripts usam,
# de propósito SEM curl e SEM plannotator — o PATH real da máquina tem os dois e
# contaminaria os casos "ausente". Sem isso, G3/G4 testariam o binário REAL.
MIN_TOOLS="bash sh cat cp sed awk date printf wc chmod mkdir rmdir tr head tail sort
           env timeout ps sha256sum grep column dirname basename ls rm seq id df
           mktemp touch find cut expr uname stat"
minpath() {
  local dir="$1"; shift
  mkdir -p "$dir"
  local b src
  for b in $MIN_TOOLS "$@"; do
    src=$(PATH="$ORIG_PATH" command -v "$b" 2>/dev/null) && ln -sf "$src" "$dir/$b"
  done
  printf '%s\n' "$dir"
}

# fake_bin <dir> <nome> <corpo>
fake_bin() {
  local dir="$1" name="$2" body="$3"
  { printf '#!/usr/bin/env bash\n'; printf '%s\n' "$body"; } > "$dir/$name"
  chmod +x "$dir/$name"
}

# Corpo padrão de um plannotator FAKE. Reproduz o contrato REAL verificado no
# binário 0.19.17:
#   `annotate` sem argumento  → usage em stderr, exit 1 (sonda de capacidade)
#   `--version`               → "plannotator X.Y.Z"
#   `annotate <f> --gate --json` → UMA linha JSON em stdout, exit 0
# O comportamento por rodada vem de $CASE/fake-script (uma decisão por linha),
# e cada invocação é registrada em $CASE/calls.txt / $CASE/env-<n>.txt.
FAKE_PLANNOTATOR='
USAGE="Usage: plannotator annotate <file.md | file.html | https://... | folder/>  [--no-jina] [--gate] [--json] [--hook]"
case "${1:-}" in
  --version|-v) echo "plannotator ${FAKE_VERSION:-0.19.17}"; exit 0 ;;
  --help) echo "$USAGE"; exit 0 ;;
esac
if [ "${1:-}" = annotate ] && [ -z "${2:-}" ]; then
  echo "$USAGE" >&2; exit 1
fi
n=$(( $(cat "$CASE/callcount" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CASE/callcount"
printf "%s\n" "$*" >> "$CASE/calls.txt"
{ echo "PLANNOTATOR_CWD=${PLANNOTATOR_CWD-<unset>}"
  echo "PLANNOTATOR_ORIGIN=${PLANNOTATOR_ORIGIN-<unset>}"
  echo "PLANNOTATOR_SHARE=${PLANNOTATOR_SHARE-<unset>}"
  echo "PLANNOTATOR_REMOTE=${PLANNOTATOR_REMOTE-<unset>}"; } > "$CASE/env-$n.txt"
action=$(sed -n "${n}p" "$CASE/fake-script" 2>/dev/null)
[ -n "$action" ] || action=approved
case "$action" in
  approved)    echo "{\"decision\":\"approved\"}" ;;
  dismissed)   echo "{\"decision\":\"dismissed\"}" ;;
  annotated)   printf "%s\n" "{\"decision\":\"annotated\",\"feedback\":\"## 1. (line 3) Feedback on: \\\"algo\\\"\\n> troque isso\"}" ;;
  annotated-empty) echo "{\"decision\":\"annotated\",\"feedback\":\"\"}" ;;
  annotated-rich)  cat "$CASE/rich.json" ;;
  noisy)       echo "[warn] runtime aviso" ; echo "{\"decision\":\"approved\"}" ;;
  garbage)     echo "isto nao e json" ;;
  fail)        echo "boom" >&2; exit 3 ;;
  hang)        sleep 60 ;;
esac
exit 0
'

FAKE_PLANNOTATOR_OLD='
case "${1:-}" in
  --version|-v) echo "plannotator 0.19.17"; exit 0 ;;
esac
if [ "${1:-}" = annotate ] && [ -z "${2:-}" ]; then
  echo "Usage: plannotator annotate <file.md>  [--no-jina]" >&2; exit 1
fi
echo "{}"
'

# plan_doc <arquivo> <titulo> [corpo-extra]
plan_doc() {
  { printf '# %s\n\n' "$2"
    printf 'Corpo do plano.\n'
    [ $# -ge 3 ] && printf '%s\n' "$3"; } > "$1"
}

echo "=== G1/G2/G3/G7: resolução e capacidade do binário ==="
newcase g1
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
out=$("$CHECK" --json 2>/dev/null); rc=$?
chk "G1 exit" "$rc" "0"
has "G1 status AVAILABLE" "$out" '"status": "AVAILABLE"'
has "G1 bin no PATH do caso" "$out" "$CASE_BIN/plannotator"

newcase g2
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
mkdir -p "$CASE/alt"; fake_bin "$CASE/alt" plannotator "$FAKE_PLANNOTATOR"
out=$(DO_PLANNOTATOR_BIN="$CASE/alt/plannotator" "$CHECK" --json 2>/dev/null)
has "G2 override vence o PATH" "$out" "$CASE/alt/plannotator"

newcase g3
# fora do PATH, só em ~/.local/bin do CASO — o caminho que o instalador oficial
# usa e que o shell não-interativo do agente frequentemente não tem no PATH.
fake_bin "$HOME/.local/bin" plannotator "$FAKE_PLANNOTATOR"
minpath "$CASE/min" jq python3 >/dev/null
out=$(PATH="$CASE/min" "$CHECK" --json 2>/dev/null); rc=$?
chk "G3 exit" "$rc" "0"
has "G3 achou em ~/.local/bin" "$out" "$HOME/.local/bin/plannotator"

newcase g7
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR_OLD"
out=$("$CHECK" --json 2>/dev/null); rc=$?
chk "G7 exit != 0" "$([ "$rc" -ne 0 ] && echo sim || echo nao)" "sim"
has "G7 status INCAPABLE" "$out" '"status": "INCAPABLE"'

echo "=== G4/G5/G6/G8: instalabilidade e instalação ==="
newcase g4
minpath "$CASE/min" >/dev/null   # coreutils, mas SEM curl e SEM plannotator
PATH="$CASE/min" "$CHECK" --quiet >/dev/null 2>&1; rc=$?
chk "G4 sem curl → exit 2" "$rc" "2"

newcase g5
minpath "$CASE/min" jq python3 >/dev/null
fake_bin "$CASE/min" curl 'exit 0'   # instalador "alcançável"
out=$(PATH="$CASE/min" "$CHECK" --json 2>/dev/null); rc=$?
chk "G5 instalável sem --install → exit 1" "$rc" "1"
has "G5 installable=yes" "$out" '"installable": "yes"'
chk "G5 nada foi instalado" "$([ -e "$HOME/.local/bin/plannotator" ] && echo sim || echo nao)" "nao"

newcase g6
minpath "$CASE/min" jq python3 >/dev/null
# curl FAKE fiel ao que o script chama:
#   sonda   → `curl -fsSIL --max-time N -o /dev/null <url>`   (HEAD)
#   sonda2  → `curl -fsSL --max-time N -r 0-0 -o /dev/null <url>`
#   install → `curl -fsSL --max-time 120 <url>` → stdout canalizado para bash
# Ele HONRA -o (senão o corpo do instalador vazaria no stdout do
# check-plannotator, que com --json é contrato de máquina) e reconhece I/r
# DENTRO de flags COMBINADAS (-fsSIL, nunca -I solto).
cat > "$CASE/min/curl" <<CURLEOF
#!/usr/bin/env bash
outfile=''; probe=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) outfile="\$2"; shift 2 ;;
    -r) probe=1; shift 2 ;;
    -*) case "\$1" in *I*) probe=1 ;; esac; shift ;;
    *) shift ;;
  esac
done
[ "\$probe" = 1 ] && exit 0
emit() {
  echo "printf '%s\\n' \"\\\$*\" > '$CASE/install-args.txt'"
  echo "cp '$CASE_BIN/plannotator' '$HOME/.local/bin/plannotator'"
  echo "chmod +x '$HOME/.local/bin/plannotator'"
}
if [ -n "\$outfile" ]; then emit > "\$outfile"; else emit; fi
CURLEOF
chmod +x "$CASE/min/curl"
# O "binário instalado" é uma cópia do fake capaz. Ele lê $CASE para achar o
# fake-script — e newcase() já exportou CASE, então o filho o herda (repetir
# CASE="$CASE" aqui seria ruído: a atribuição só valeria para o processo
# forkado, que é exatamente quem já a tem).
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
out=$(PATH="$CASE/min" "$CHECK" --install --json 2>/dev/null); rc=$?
chk "G6 exit após instalar" "$rc" "0"
has "G6 status AVAILABLE" "$out" '"status": "AVAILABLE"'
has "G6 install_result ok" "$out" '"install_result": "ok"'
has "G6 binário aterrissou em ~/.local/bin" "$out" "$HOME/.local/bin/plannotator"
args=$(cat "$CASE/install-args.txt" 2>/dev/null)
has "G6 instalador recebeu --minimal" "$args" "--minimal"
has "G6 instalador recebeu --non-interactive" "$args" "--non-interactive"
hasnt "G6 nada de sudo" "$args" "sudo"
chk "G6 stdout do --json é JSON puro" "$(printf '%s' "$out" | head -c 1)" "{"

newcase g8
minpath "$CASE/min" jq python3 >/dev/null
fake_bin "$CASE/min" curl 'exit 0'
PATH="$CASE/min" DO_PLANNOTATOR_INSTALL=0 "$CHECK" --install --quiet >/dev/null 2>&1; rc=$?
chk "G8 DO_PLANNOTATOR_INSTALL=0 → exit 2" "$rc" "2"
chk "G8 nada instalado" "$([ -e "$HOME/.local/bin/plannotator" ] && echo sim || echo nao)" "nao"

echo "=== G9: instalação EXISTENTE nunca é sobrescrita ==="
newcase g9
minpath "$CASE/min" jq python3 >/dev/null
fake_bin "$CASE/min" curl 'exit 0'
fake_bin "$CASE/min" plannotator "$FAKE_PLANNOTATOR_OLD"   # presente, mas sem --gate/--json
before=$(md5sum "$CASE/min/plannotator" | cut -d" " -f1)
out=$(PATH="$CASE/min" "$CHECK" --install --json 2>/dev/null); rc=$?
chk "G9 exit 2 (não instalável por decisão)" "$rc" "2"
has "G9 install_result forbidden" "$out" '"install_result": "forbidden"'
chk "G9 binário existente intacto" "$(md5sum "$CASE/min/plannotator" | cut -d" " -f1)" "$before"

echo "=== P1..P6: decisões e exit codes de round ==="
for case_spec in "p1 approved 0" "p2 annotated 10" "p3 dismissed 11" "p5 fail 13" "p6 garbage 13"; do
  set -- $case_spec
  name="$1"; action="$2"; want="$3"
  newcase "$name"
  fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
  printf '%s\n' "$action" > "$CASE/fake-script"
  plan_doc "$CASE/PLANO.md" "Plano de teste"
  "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1; rc=$?
  chk "${name^^} $action → exit $want" "$rc" "$want"
done

newcase p2b
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano de teste"
out=$("$GATE" round "$CASE/PLANO.md" 2>/dev/null); rc=$?
chk "P2 exit" "$rc" "10"
has "P2 linha de contrato" "$out" "PLAN_APPROVAL decision=annotated revision=1/5"
fbfile="$PLAN_APPROVAL_DIR/rev-001.feedback.md"
chk "P2 feedback gravado" "$([ -s "$fbfile" ] && echo sim || echo nao)" "sim"
has "P2 feedback tem o comentário" "$(cat "$fbfile")" "troque isso"
has "P2 feedback preserva a linha citada" "$(cat "$fbfile")" '(line 3) Feedback on:'
chk "P2 decision file" "$(cat "$PLAN_APPROVAL_DIR/rev-001.decision")" "annotated"

newcase p4
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'hang\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano de teste"
DO_PLAN_TIMEOUT=2 "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1; rc=$?
chk "P4 timeout → exit 12" "$rc" "12"
chk "P4 decision=timeout" "$(cat "$PLAN_APPROVAL_DIR/rev-001.decision")" "timeout"

echo "=== P7/P8: argv e imutabilidade do snapshot ==="
newcase p7
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano de teste"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
call=$(cat "$CASE/calls.txt")
chk "P7 argv exato" "$call" "annotate $PLAN_APPROVAL_DIR/rev-001.md --gate --json"

newcase p8
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano de teste" "linha original"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
snap="$PLAN_APPROVAL_DIR/rev-001.md"
has "P8 snapshot copiou o conteúdo" "$(cat "$snap")" "linha original"
echo "mudou depois" >> "$CASE/PLANO.md"
hasnt "P8 snapshot não segue o arquivo vivo" "$(cat "$snap")" "mudou depois"
printf 'tentativa\n' >> "$snap" 2>/dev/null || true
hasnt "P8 snapshot é somente leitura" "$(cat "$snap")" "tentativa"

echo "=== P9/P10/P11: revisões, trail e imutabilidade do título ==="
newcase p9
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated\nannotated\napproved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano estável"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1; r1=$?
plan_doc "$CASE/PLANO.md" "Plano estável" "revisão 2"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1; r2=$?
plan_doc "$CASE/PLANO.md" "Plano estável" "revisão 3"
out3=$("$GATE" round "$CASE/PLANO.md" 2>/dev/null); r3=$?
chk "P9 r1" "$r1" "10"
chk "P9 r2" "$r2" "10"
chk "P11 r3 (mesmo título) aprovado" "$r3" "0"
has "P9 revisão 3 na linha de contrato" "$out3" "revision=3/5"
chk "P9 três snapshots" \
  "$(ls "$PLAN_APPROVAL_DIR"/rev-[0-9][0-9][0-9].md | wc -l | tr -d ' ')" "3"
chk "P9 trail com header + 3 linhas" \
  "$(wc -l < "$PLAN_APPROVAL_DIR/trail.tsv" | tr -d ' ')" "4"
chk "P9 trail decisões em ordem" \
  "$(awk -F'\t' 'NR>1{printf "%s:%s ", $1, $3}' "$PLAN_APPROVAL_DIR/trail.tsv")" \
  "1:annotated 2:annotated 3:approved "

newcase p10
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated\nannotated\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Título original"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
plan_doc "$CASE/PLANO.md" "Título TROCADO"
errout=$("$GATE" round "$CASE/PLANO.md" 2>&1 >/dev/null); rc=$?
chk "P10 deriva de título → exit 2" "$rc" "2"
has "P10 diagnóstico cita o travado" "$errout" "Título original"
has "P10 diagnóstico cita o recebido" "$errout" "Título TROCADO"
chk "P10 nenhuma 2ª chamada ao Plannotator" "$(cat "$CASE/callcount")" "1"
chk "P10 título travado intacto" "$("$GATE" title)" "Título original"

echo "=== P12/P13: validação da entrada ==="
newcase p12
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'sem heading nenhum\n' > "$CASE/PLANO.md"
errout=$("$GATE" round "$CASE/PLANO.md" 2>&1 >/dev/null); rc=$?
chk "P12 sem H1 → exit 2" "$rc" "2"
has "P12 diagnóstico explica o slug" "$errout" "PRIMEIRO heading"

newcase p13
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
"$GATE" round "$CASE/nao-existe.md" >/dev/null 2>&1; chk "P13 ausente → exit 2" "$?" "2"
: > "$CASE/vazio.md"
"$GATE" round "$CASE/vazio.md" >/dev/null 2>&1;    chk "P13 vazio → exit 2" "$?" "2"
"$GATE" round >/dev/null 2>&1;                     chk "P13 sem argumento → exit 2" "$?" "2"

echo "=== P14: orçamento de revisões ==="
newcase p14
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated\nannotated\nannotated\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano curto"
export DO_PLAN_MAX_REVISIONS=2
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1; chk "P14 r1" "$?" "10"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1; chk "P14 r2" "$?" "10"
errout=$("$GATE" round "$CASE/PLANO.md" 2>&1 >/dev/null); rc=$?
chk "P14 r3 → exit 14 (orçamento)" "$rc" "14"
has "P14 diagnóstico nomeia a variável" "$errout" "DO_PLAN_MAX_REVISIONS"
chk "P14 Plannotator NÃO foi chamado na 3ª" "$(cat "$CASE/callcount")" "2"
unset DO_PLAN_MAX_REVISIONS

echo "=== P15/P16/P17: ambiente da sessão ==="
newcase p15
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
env1=$(cat "$CASE/env-1.txt")
has "P15 share desligado por default" "$env1" "PLANNOTATOR_SHARE=disabled"
has "P17 PLANNOTATOR_CWD = BASE_DIR" "$env1" "PLANNOTATOR_CWD=$BASE_DIR"

newcase p16
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
DO_PLAN_SHARE=1 "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
hasnt "P16 DO_PLAN_SHARE=1 não desliga o share" "$(cat "$CASE/env-1.txt")" "PLANNOTATOR_SHARE=disabled"

echo "=== P18/P19: detecção de harness (claude-code > pi > jcode > opencode) ==="
newcase p18
chk "P18 claude-code" "$(CLAUDECODE=1 PI_CODING_AGENT=true OPENCODE=1 "$GATE" origin)" \
  "harness=claude-code origin=claude-code"
chk "P18 pi (sem claude)" "$(PI_CODING_AGENT=true OPENCODE=1 "$GATE" origin)" \
  "harness=pi origin=pi"
chk "P18 jcode (sem claude/pi)" "$(JCODE_SESSION_ID=x OPENCODE=1 "$GATE" origin)" \
  "harness=jcode origin=<default do Plannotator>"
chk "P18 opencode (só ele)" "$(OPENCODE=1 "$GATE" origin)" \
  "harness=opencode origin=opencode"
chk "P18 nenhum" "$("$GATE" origin)" "harness=unknown origin=<default do Plannotator>"
chk "P18 override explícito" "$(CLAUDECODE=1 DO_PLAN_ORIGIN=codex "$GATE" origin)" \
  "harness=codex origin=codex"

newcase p19
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
JCODE_SESSION_ID=x "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
has "P19 jcode → origin não setado" "$(cat "$CASE/env-1.txt")" "PLANNOTATOR_ORIGIN=<unset>"
newcase p19b
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
PI_CODING_AGENT=true "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
has "P19 pi → PLANNOTATOR_ORIGIN=pi" "$(cat "$CASE/env-1.txt")" "PLANNOTATOR_ORIGIN=pi"

echo "=== P20/P21/P22: robustez do parse ==="
newcase p20
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated-rich\n' > "$CASE/fake-script"
# feedback com aspas, newline, acento, backslash e crase — tudo escapado no JSON
python3 - "$CASE/rich.json" <<'PY'
import json, sys
fb = ('## 1. (line 7) Remove this\n```\ntrecho "citado"\n```\n'
      '> não quero isso — troque por `outra coisa` com \\barra\n')
open(sys.argv[1], "w", encoding="utf-8").write(
    json.dumps({"decision": "annotated", "feedback": fb}, ensure_ascii=False) + "\n")
PY
plan_doc "$CASE/PLANO.md" "Plano"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1; rc=$?
chk "P20 exit" "$rc" "10"
fb=$(cat "$PLAN_APPROVAL_DIR/rev-001.feedback.md")
has "P20 aspas preservadas" "$fb" 'trecho "citado"'
has "P20 acento preservado" "$fb" "não quero isso"
has "P20 backslash preservado" "$fb" '\barra'
chk "P20 newlines preservadas" "$(printf '%s' "$fb" | grep -c '^')" "5"

newcase p21
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'noisy\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
chk "P21 ruído antes do JSON → aprovado" "$?" "0"

newcase p22
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated-empty\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
chk "P22 annotated vazio → exit 11" "$?" "11"
chk "P22 decision=dismissed" "$(cat "$PLAN_APPROVAL_DIR/rev-001.decision")" "dismissed"

echo "=== P23: contenção de escrita ==="
newcase p23
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated\n' > "$CASE/fake-script"
plan_doc "$CASE/world/PLANO.md" "Plano"
before=$(cd "$CASE/world" && find . | sort | md5sum)
"$GATE" round "$CASE/world/PLANO.md" >/dev/null 2>&1
after=$(cd "$CASE/world" && find . | sort | md5sum)
chk "P23 raiz-de-mundo intacta" "$after" "$before"
outside=$(find "$DO_STATE" -mindepth 1 -maxdepth 1 ! -name plan-approval | wc -l | tr -d ' ')
chk "P23 nada no DO_STATE fora de plan-approval" "$outside" "0"

echo "=== P24: consultas ==="
newcase p24
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated\nannotated\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
plan_doc "$CASE/PLANO.md" "Plano" "rev2"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
chk "P24 doc default = última revisão" "$("$GATE" doc)" "$PLAN_APPROVAL_DIR/rev-002.md"
chk "P24 doc 1 explícito" "$("$GATE" doc 1)" "$PLAN_APPROVAL_DIR/rev-001.md"
has "P24 feedback default" "$("$GATE" feedback)" "troque isso"
has "P24 status lista as 2 revisões" "$("$GATE" status)" "annotated"
"$GATE" doc 99 >/dev/null 2>&1; chk "P24 revisão inexistente → exit 2" "$?" "2"

echo "=== P29: portabilidade do timeout(1) (GNU vs BSD vs ausente) ==="
newcase p29
minpath "$CASE/min" jq python3 >/dev/null
fake_bin "$CASE/min" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
# timeout estilo BSD: NÃO conhece --foreground nem -k. Um `runner` montado às
# cegas com essas flags morreria com erro de uso e o rc!=0 seria lido como
# "o Plannotator falhou" — exit 13 num caso em que o usuário APROVOU.
cat > "$CASE/min/timeout" <<'TOEOF'
#!/usr/bin/env bash
case "$1" in
  --foreground) echo "timeout: illegal option -- foreground" >&2; exit 125 ;;
  -k) echo "timeout: illegal option -- k" >&2; exit 125 ;;
esac
shift          # descarta a duração
exec "$@"
TOEOF
chmod +x "$CASE/min/timeout"
PATH="$CASE/min" "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
chk "P29 timeout sem --foreground/-k → aprovado mesmo assim" "$?" "0"
chk "P29 decisão correta" "$(cat "$PLAN_APPROVAL_DIR/rev-001.decision")" "approved"

newcase p29b
minpath "$CASE/min" jq python3 >/dev/null
rm -f "$CASE/min/timeout"      # timeout(1) AUSENTE (macOS sem coreutils)
fake_bin "$CASE/min" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
errout=$(PATH="$CASE/min" "$GATE" round "$CASE/PLANO.md" 2>&1 >/dev/null); rc=$?
chk "P29 sem timeout(1) → ainda funciona" "$rc" "0"
has "P29 avisa que pode bloquear" "$errout" "timeout(1) ausente"

echo "=== P27/P28: idempotência (approved) ==="
newcase p27
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'annotated\napproved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
"$GATE" approved >/dev/null 2>&1; chk "P27 sem trail → not-approved (exit 1)" "$?" "1"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
"$GATE" approved >/dev/null 2>&1; chk "P27 após annotated → ainda not-approved" "$?" "1"
plan_doc "$CASE/PLANO.md" "Plano" "rev2"
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
out=$("$GATE" approved 2>/dev/null); chk "P27 após approved → exit 0" "$?" "0"
has "P28 approved reporta a revisão" "$out" "approved revision=2"

echo "=== P25/P26: dependências e validação de env ==="
newcase p25
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
# PATH sem jq e sem python3 (mas com coreutils, senão nada roda)
mkdir -p "$CASE/min"
for b in bash sh cat cp sed awk date printf wc chmod mkdir tr head tail sort env \
         timeout ps sha256sum grep column dirname basename ls rm seq id df; do
  src=$(command -v "$b" 2>/dev/null) && ln -sf "$src" "$CASE/min/$b"
done
ln -sf "$CASE_BIN/plannotator" "$CASE/min/plannotator"
errout=$(PATH="$CASE/min" "$GATE" round "$CASE/PLANO.md" 2>&1 >/dev/null); rc=$?
chk "P25 sem jq/python3 → exit 2" "$rc" "2"
has "P25 mensagem acionável" "$errout" "jq OU python3"

newcase p26
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
plan_doc "$CASE/PLANO.md" "Plano"
DO_PLAN_MAX_REVISIONS=abc "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
chk "P26 MAX_REVISIONS inválido → exit 2" "$?" "2"
DO_PLAN_MAX_REVISIONS=0 "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
chk "P26 MAX_REVISIONS=0 → exit 2" "$?" "2"
DO_PLAN_TIMEOUT=-5 "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
chk "P26 TIMEOUT inválido → exit 2" "$?" "2"
( unset DO_STATE; "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1 )
chk "P26 sem DO_STATE → exit != 0" "$([ "$?" -ne 0 ] && echo sim || echo nao)" "sim"
"$GATE" origin >/dev/null 2>&1; chk "P26 origin funciona sem ENV_FILE" "$?" "0"

echo "=== DO-CONTEXT: DO_PLAN_* no ENV_FILE ==="
newcase dc
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$CASE/repo" && cd "$CASE/repo" && git init -q . \
  && echo x > a.txt && git add -A && git commit -qm init
envf=$("$SKILL/scripts/do-context.sh" --quiet 2>&1 | tail -1)
pval() { sed -n "s/.*$1='\([^']*\)'.*/\1/p" "$2"; }
chk "DC1 DO_PLAN_APPROVAL default 0" "$(pval DO_PLAN_APPROVAL "$envf")" "0"
chk "DC1 DO_PLAN_MAX_REVISIONS default" "$(pval DO_PLAN_MAX_REVISIONS "$envf")" "5"
chk "DC1 DO_PLAN_TIMEOUT default" "$(pval DO_PLAN_TIMEOUT "$envf")" "3600"
chk "DC1 PLAN_APPROVAL_DIR sob DO_STATE" \
  "$(pval PLAN_APPROVAL_DIR "$envf")" "$(pval DO_STATE "$envf")/plan-approval"
chk "DC1 PLAN_DOC dentro do PLAN_APPROVAL_DIR" \
  "$(pval PLAN_DOC "$envf")" "$(pval PLAN_APPROVAL_DIR "$envf")/PLANO.md"
envf2=$(DO_PLAN_APPROVAL=on "$SKILL/scripts/do-context.sh" --quiet 2>&1 | tail -1)
chk "DC2 plan=on normaliza para 1" "$(pval DO_PLAN_APPROVAL "$envf2")" "1"
DO_PLAN_APPROVAL=talvez "$SKILL/scripts/do-context.sh" --quiet >/dev/null 2>&1
chk "DC2 DO_PLAN_APPROVAL inválido → exit 2" "$?" "2"
DO_PLAN_MAX_REVISIONS=x "$SKILL/scripts/do-context.sh" --quiet >/dev/null 2>&1
chk "DC2 DO_PLAN_MAX_REVISIONS inválido → exit 2" "$?" "2"
out=$(DO_PLAN_APPROVAL=1 "$SKILL/scripts/do-context.sh" 2>&1)
has "DC3 resumo anuncia PLAN_APPROVAL = ON" "$out" "PLAN_APPROVAL = ON"
out=$("$SKILL/scripts/do-context.sh" 2>&1)
has "DC3 resumo anuncia PLAN_APPROVAL = OFF" "$out" "PLAN_APPROVAL = OFF"
cd "$LAB"

echo "=== R1..R7: regressões da revisão adversarial ==="

# R1 (P1) — o plano NUNCA é servido na rede sem pedido explícito.
newcase r1
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\napproved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
# SSH_CONNECTION no ambiente faz o Plannotator escutar em 0.0.0.0 por conta
# própria; PLANNOTATOR_REMOTE=0 é o que o impede.
SSH_CONNECTION="10.0.0.9 22 10.0.0.1 22" "$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1
has "R1 sessão SSH ainda assim escuta só em localhost" "$(cat "$CASE/env-1.txt")" "PLANNOTATOR_REMOTE=0"
newcase r1b
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
printf 'approved\n' > "$CASE/fake-script"
plan_doc "$CASE/PLANO.md" "Plano"
errout=$(DO_PLAN_REMOTE=1 "$GATE" round "$CASE/PLANO.md" 2>&1 >/dev/null)
has "R1 DO_PLAN_REMOTE=1 é respeitado" "$(cat "$CASE/env-1.txt")" "PLANNOTATOR_REMOTE=1"
has "R1 e avisa que qualquer um aprova" "$errout" "não tem autenticação"

# R2 (P3) — rodada interrompida NÃO trava o portão.
newcase r2
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
plan_doc "$CASE/PLANO.md" "Plano"
mkdir -p "$PLAN_APPROVAL_DIR"
printf 'revision\ttimestamp\tdecision\tdoc_sha\tsnapshot\tfeedback\n' > "$PLAN_APPROVAL_DIR/trail.tsv"
# simula o resíduo exato de uma rodada morta: snapshot 0444, trail sem a linha.
# O arquivo `title` guarda o TEXTO do H1 (sem o '#'), como o first_h1 produz.
cp "$CASE/PLANO.md" "$PLAN_APPROVAL_DIR/rev-001.md"; chmod a-w "$PLAN_APPROVAL_DIR/rev-001.md"
printf 'Plano\n' > "$PLAN_APPROVAL_DIR/title"
printf 'approved\n' > "$CASE/fake-script"
out=$("$GATE" round "$CASE/PLANO.md" 2>/dev/null); rc=$?
chk "R2 rodada após interrupção NÃO trava" "$rc" "0"
has "R2 a tentativa abortada não é reusada (vai para a rev 2)" "$out" "revision=2/5"
chk "R2 snapshot abortado preservado" \
  "$([ -f "$PLAN_APPROVAL_DIR/rev-001.md" ] && echo sim || echo nao)" "sim"

# R3 (P3) — falha de I/O no snapshot é TOOLFAIL, nunca "deriva de título".
newcase r3
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
plan_doc "$CASE/PLANO.md" "Plano"
mkdir -p "$PLAN_APPROVAL_DIR"
printf 'Plano\n' > "$PLAN_APPROVAL_DIR/title"
printf 'revision\ttimestamp\tdecision\tdoc_sha\tsnapshot\tfeedback\n' > "$PLAN_APPROVAL_DIR/trail.tsv"
chmod a-w "$PLAN_APPROVAL_DIR"          # diretório inteiro sem escrita
"$GATE" round "$CASE/PLANO.md" >/dev/null 2>&1; rc=$?
chmod u+w "$PLAN_APPROVAL_DIR"
chk "R3 I/O impossível → 13 (TOOLFAIL), não 2 (título)" "$rc" "13"

# R4 (P7) — json_escape não pode comer a letra 't'.
newcase r4
fake_bin "$CASE_BIN" plannotator "$FAKE_PLANNOTATOR"
out=$("$CHECK" --json 2>/dev/null)
has "R4 'not-attempted' intacto" "$out" '"install_result": "not-attempted"'
has "R4 caminho com 't' intacto" "$out" "plannotator"
chk "R4 nenhum TAB literal vazou no JSON" \
  "$(printf '%s' "$out" | tr -cd '\t' | wc -c | tr -d ' ')" "0"

# R5 (P2) — sync-global-skill NUNCA destrói a própria casa da skill.
SYNC="$SKILL/scripts/sync-global-skill.sh"
newcase r5
mkdir -p "$HOME/.claude/skills"
# cenário do README: a skill INSTALADA É o destino (clone direto).
cp -r "$SKILL" "$HOME/.claude/skills/deep-orchestrator"
out=$("$HOME/.claude/skills/deep-orchestrator/scripts/sync-global-skill.sh" 2>&1); rc=$?
chk "R5 exit 0" "$rc" "0"
has "R5 reconhece que o destino é a própria casa" "$out" "É a própria casa da skill"
chk "R5 a skill continua legível (sem ELOOP)" \
  "$([ -r "$HOME/.claude/skills/deep-orchestrator/SKILL.md" ] && echo sim || echo nao)" "sim"
chk "R5 scripts/ continua alcançável" \
  "$([ -d "$HOME/.claude/skills/deep-orchestrator/scripts" ] && echo sim || echo nao)" "sim"
chk "R5 nenhum .bak criado" \
  "$(ls -d "$HOME/.claude/skills"/deep-orchestrator.bak-* 2>/dev/null | wc -l | tr -d ' ')" "0"
# Irmão do R5: um symlink CORRETO também resolve para $SOURCE. Ele NÃO pode ser
# anunciado como "é a própria casa" — é o caso mais comum e a mensagem errada
# mascararia o que o script de fato fez.
newcase r5b
mkdir -p "$HOME/.agents/skills"
ln -sfn "$SKILL" "$HOME/.agents/skills/deep-orchestrator"
out=$("$SYNC" 2>&1)
has "R5b symlink correto é anunciado como symlink" "$out" "symlink já aponta para a casa da skill"
hasnt "R5b e NÃO como 'a própria casa'" "$out" "É a própria casa da skill"

# R6 (P2) — cópia velha VIRA symlink, e só é aceita se der para ler através.
newcase r6
mkdir -p "$HOME/.jcode/skills/deep-orchestrator"
printf -- '---\nname: deep-orchestrator\n---\nvelho\n' > "$HOME/.jcode/skills/deep-orchestrator/SKILL.md"
out=$("$SKILL/scripts/sync-global-skill.sh" 2>&1)
has "R6 cópia trocada por symlink" "$out" "jcode: CÓPIA"
chk "R6 destino é symlink" \
  "$([ -L "$HOME/.jcode/skills/deep-orchestrator" ] && echo sim || echo nao)" "sim"
chk "R6 e resolve para a casa da skill" \
  "$(cd "$HOME/.jcode/skills/deep-orchestrator" && pwd -P)" "$SKILL"
chk "R6 backup da cópia preservado" \
  "$(ls -d "$HOME/.jcode/skills"/deep-orchestrator.bak-* 2>/dev/null | wc -l | tr -d ' ')" "1"
# diretório de terceiro NUNCA é tocado
mkdir -p "$HOME/.pi/agent/skills/deep-orchestrator"
printf -- '---\nname: outra-coisa\n---\n' > "$HOME/.pi/agent/skills/deep-orchestrator/SKILL.md"
out=$("$SKILL/scripts/sync-global-skill.sh" 2>&1)
chk "R6 diretório alheio preservado" \
  "$([ -f "$HOME/.pi/agent/skills/deep-orchestrator/SKILL.md" ] && echo sim || echo nao)" "sim"
has "R6 e reportado, não apagado" "$out" "PRESERVADO"

echo "=== DC4: com o portão DESLIGADO, a FASE 2.5 é inerte ==="
# A garantia mais importante da feature: quem NÃO pediu um plano tem exatamente
# o comportamento autônomo de antes. Nenhum diretório, nenhum processo, nenhuma
# variável a mais no caminho — a FASE 0 só publica os DEFAULTS.
newcase dc4
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$CASE/repo" && cd "$CASE/repo" && git init -q . \
  && echo x > a.txt && git add -A && git commit -qm init
envf=$("$SKILL/scripts/do-context.sh" --quiet 2>&1 | tail -1)
pval() { sed -n "s/.*$1='\([^']*\)'.*/\1/p" "$2"; }
st=$(pval DO_STATE "$envf")
chk "DC4 portão desligado por default" "$(pval DO_PLAN_APPROVAL "$envf")" "0"
chk "DC4 FASE 0 NÃO cria o diretório do portão" \
  "$([ -d "$(pval PLAN_APPROVAL_DIR "$envf")" ] && echo sim || echo nao)" "nao"
chk "DC4 FASE 0 NÃO escreve o documento do plano" \
  "$([ -e "$(pval PLAN_DOC "$envf")" ] && echo sim || echo nao)" "nao"
# O conteúdo do DO_STATE tem que ser EXATAMENTE o de sempre — nada do portão.
chk "DC4 DO_STATE sem artefato do portão" \
  "$(ls "$st" | grep -c -i 'plan-approval\|plannotator\|rev-')" "0"
chk "DC4 nenhum arquivo TASK_PLAN.md prematuro" \
  "$([ -e "$(pval PLAN_FILE "$envf")" ] && echo sim || echo nao)" "nao"

# R7 (P4) — o DO_REUSE não pode inverter a decisão do portão em silêncio.
env_on=$(DO_PLAN_APPROVAL=1 "$SKILL/scripts/do-context.sh" --quiet 2>&1 | tail -1)
chk "R7 run com portão ON" "$(pval DO_PLAN_APPROVAL "$env_on")" "1"
# deixa uma sub-tarefa pendente para que o reuso seja tentado
printf 'r\tfeature\tx\tb\tp\ts\t-\t-\tACTIVE\n' >> "$(dirname "$env_on")/owned.tsv"
out=$("$SKILL/scripts/do-context.sh" 2>&1)          # invocação SEM portão
env_off=$(printf '%s' "$out" | tail -1)
chk "R7 invocação SEM portão não reusa o env com portão" \
  "$([ "$env_off" = "$env_on" ] && echo reusou || echo nova)" "nova"
chk "R7 e a run nova tem o portão desligado" "$(pval DO_PLAN_APPROVAL "$env_off")" "0"
has "R7 divergência é anunciada como DO_STALE" "$out" "inverteria a decisão do portão"
# E o caminho INVERSO: portão ON sobre um env SEM portão também não reusa.
# O laço de reuso varre run-*/env em ordem alfabética = cronológica, então o
# env_on (mais antigo) venceria e casaria legitimamente. Encerramos a run dele
# para que a única pendente seja a SEM portão.
sed -i 's/\tACTIVE$/\tREMOVED/' "$(dirname "$env_on")/owned.tsv"
printf 'r\tfeature\ty\tb\tp\ts\t-\t-\tACTIVE\n' >> "$(dirname "$env_off")/owned.tsv"
out2=$(DO_PLAN_APPROVAL=1 "$SKILL/scripts/do-context.sh" 2>&1)
has "R7 inverso (plan=on sobre env sem portão) também é DO_STALE" "$out2" "inverteria a decisão do portão"
# env legado (anterior à v3.4.0, sem a chave) também não pode ser reusado
legacy=$(dirname "$env_on")/legacy-env
grep -v '^DO_PLAN_APPROVAL=' "$env_on" > "$legacy"
chk "R7 env legado não tem a chave" "$(grep -c '^DO_PLAN_APPROVAL=' "$legacy" || true)" "0"

# R8 (P5) — com o portão ON, o diretório do plano já existe para o `cat >`.
env2=$(DO_PLAN_APPROVAL=1 "$SKILL/scripts/do-context.sh" --quiet --new-run 2>&1 | tail -1)
chk "R8 FASE 0 cria o diretório quando o portão está ON" \
  "$([ -d "$(pval PLAN_APPROVAL_DIR "$env2")" ] && echo sim || echo nao)" "sim"
( printf '# Plano\n' > "$(pval PLAN_DOC "$env2")" ) 2>/dev/null
chk "R8 'cat > \$PLAN_DOC' funciona de primeira" \
  "$([ -s "$(pval PLAN_DOC "$env2")" ] && echo sim || echo nao)" "sim"

cd "$LAB"

# --- resumo -------------------------------------------------------------------
echo
printf 'RESULTADO: %s PASS, %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1
