#!/usr/bin/env bash
# Testes de aceitação das FLAGS da FASE 0 (do-context.sh --flags='...') — FL1..FL14
#
# SEM REDE, SEM surf, SEM Plannotator: só do-context.sh (e, no FL10e, o purge
# real do do-wt.sh) contra repositórios DESCARTÁVEIS num mktemp -d, apagado ao
# fim. Nada toca o repositório da skill nem cria worktree/branch nele.
#
#   FL1  --flags='' e ausência de --flags = DEFAULTS; o ENV_FILE grava E exporta
#        as variáveis novas (um processo-filho as enxerga) com aspas simples
#   FL2  cada flag da tabela → variável no ENV_FILE + linha no resumo
#   FL3  flag VENCE a variável de ambiente
#   FL4  variável de ambiente SOZINHA ainda funciona (fallback; com e sem
#        --flags=''); valor inválido no env → exit 2
#   FL5  token desconhecido → exit 2 com sugestão determinística (apelidos), sem
#        resíduo em disco; glob ('*') não expande
#   FL6  no-test + only-e2e → exit 2 "mutuamente exclusivos" (nas duas ordens);
#        token repetido igual é inofensivo; plan=on + plan=off → exit 2
#   FL7  surf-sub-agents fora de 1..20 → exit 2; os limites 1 e 20 passam
#   FL8  anti-stale do TEST_MODE: flag divergente cria execução NOVA; igual
#        REAPROVEITA; chave ausente em env antigo = full
#   FL9  anti-stale do QUESTION: idem; chave ausente = 0
#   FL10 DO_ORPHAN_RUNS: run anterior viva não reusada (DO_STALE, --new-run, só
#        BLOCKED/ORPHANED) é impressa com o comando EXATO de purge — e o comando
#        impresso, rodado de verdade, fecha a worktree abandonada (FL10e)
#   FL11 wt=<nome>: cria, REENTRA (nunca <nome>-2), a flag sobrevive ao re-exec,
#        DO_REUSE volta a funcionar dentro do wt, run pendente do principal não
#        sequestra o wt=, dedupe só contra o que NÃO é o wt-root deste repo
#   FL12 owned.tsv: cabeçalho de 11 colunas; linhas vivas contadas pela coluna 9
#   FL13 --help imprime o cabeçalho INTEIRO (não trunca por número de linha)
#   FL14 path com ESPAÇO e ACENTO: flags, DO_ORPHAN_RUNS (comando impresso segue
#        válido e executável) e reentrada no wt= continuam corretos
#
# Uso: bash scripts/test-flags.sh
set -uo pipefail
SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
CTX="$SKILL/scripts/do-context.sh"
WT="$SKILL/scripts/do-wt.sh"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/do-flags-XXXXXX") || { echo "mktemp falhou" >&2; exit 1; }
LAB=$(cd "$LAB" && pwd -P)     # canônico: no macOS /var -> /private/var, e o git devolve o real
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (esperado='$3' obtido='$2')"; fi; }
has()  { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (não achei '$3' em: $(printf '%s' "$2" | head -c 300))"; fi; }
hasnt(){ if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1 (achei '$3' e não devia)"; else ok "$1"; fi; }
hasre(){ if printf '%s' "$2" | grep -qE -- "$3"; then ok "$1"; else bad "$1 (não casei /$3/ em: $(printf '%s' "$2" | head -c 300))"; fi; }
# pval <CHAVE> <arquivo-env>: valor da linha CHAVE='...' ANCORADA no início (DO_WT
# não pode casar com DO_WT_ROOT)
pval() { sed -n "s/^$1='\([^']*\)'.*/\1/p" "$2"; }

trap 'rm -rf -- "$LAB" 2>/dev/null' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# A suíte roda DENTRO de um agente: um ENV_FILE sourceado na sessão exporta DO_*
# e contaminaria todos os casos de default/fallback.
unset DO_PLAN_APPROVAL DO_PLAN_MAX_REVISIONS DO_PLAN_TIMEOUT DO_MAX_PARALLEL \
      DO_SURF_SUB_AGENTS DO_WT_ROOT DO_WT_NAME DO_WT_ROOT_ENTERED WT_ROOT_BASE \
      DO_NO_STOP DO_EVOLUTION_SURVEY DO_TEST_MODE DO_QUESTION DO_FORCE_NESTED \
      DO_STATE DO_HOME DO_WT GIT_DIR GIT_WORK_TREE 2>/dev/null || true

# --- helpers -----------------------------------------------------------------
# newrepo <nome>: repo descartável $LAB/<nome>/proj com 1 commit; entra nele.
# Cada cenário tem o SEU repo: o reuso da FASE 0 é por raiz-de-mundo.
newrepo() {
  REPO="$LAB/$1/proj"
  mkdir -p "$REPO" && cd "$REPO" && git init -q . \
    && echo x > a.txt && git add -A && git commit -qm init
}
# ctx <args...>: roda a FASE 0 no cwd. OUT = stdout+stderr, RC = exit, ENVF = última linha.
ctx() { OUT=$("$CTX" "$@" 2>&1); RC=$?; ENVF=$(printf '%s\n' "$OUT" | tail -1); }
# pend <env> <nome> <status>: injeta uma linha de 11 colunas no ledger da run
# (7/8 VAZIAS de propósito — é o caso que `IFS=$'\t' read` colapsaria).
pend() { printf 'r\tfeature\t%s\tb\tp\ts\t\t\t%s\t-\t-\n' "$2" "$3" >> "$(dirname "$1")/owned.tsv"; }
nruns() { ls -d "$1"/.deep-orchestrator/run-* 2>/dev/null | wc -l | tr -d ' '; }
# under <path> <prefixo>: "sim" se <path> começa por <prefixo>. (Função, e não um
# `case` dentro de $(...): o bash 3.2 do macOS não parseia `pat)` em substituição.)
under() { if [ "${1#"$2"}" != "$1" ]; then echo sim; else echo "nao:$1"; fi; }

echo "=== FL1: --flags='' e ausência de --flags = DEFAULTS ==="
newrepo fl1
for form in "com --flags=''" "sem --flags"; do
  if [ "$form" = "sem --flags" ]; then ctx; else ctx --flags=''; fi
  chk "FL1 ($form) exit 0" "$RC" "0"
  chk "FL1 ($form) última linha é o ENV_FILE" "$([ -f "$ENVF" ] && echo sim || echo nao)" "sim"
  chk "FL1 ($form) DO_PLAN_APPROVAL=0"    "$(pval DO_PLAN_APPROVAL "$ENVF")" "0"
  chk "FL1 ($form) DO_MAX_PARALLEL=50"    "$(pval DO_MAX_PARALLEL "$ENVF")" "50"
  chk "FL1 ($form) DO_SURF_SUB_AGENTS=10" "$(pval DO_SURF_SUB_AGENTS "$ENVF")" "10"
  chk "FL1 ($form) DO_NO_STOP=0"          "$(pval DO_NO_STOP "$ENVF")" "0"
  chk "FL1 ($form) DO_EVOLUTION_SURVEY=1" "$(pval DO_EVOLUTION_SURVEY "$ENVF")" "1"
  chk "FL1 ($form) DO_TEST_MODE=full"     "$(pval DO_TEST_MODE "$ENVF")" "full"
  chk "FL1 ($form) DO_QUESTION=0"         "$(pval DO_QUESTION "$ENVF")" "0"
  chk "FL1 ($form) DO_WT_ROOT=0"          "$(pval DO_WT_ROOT "$ENVF")" "0"
  chk "FL1 ($form) DO_WT_NAME vazio"      "$(pval DO_WT_NAME "$ENVF")" ""
  has "FL1 ($form) resumo TEST_MODE = full" "$OUT" "TEST_MODE = full"
  has "FL1 ($form) resumo QUESTION = 0"     "$OUT" "QUESTION = 0"
  has "FL1 ($form) resumo WT_ROOT = OFF"    "$OUT" "WT_ROOT = OFF"
  has "FL1 ($form) resumo SURF_SUB_AGENTS = 10" "$OUT" "SURF_SUB_AGENTS = 10"
done
chk "FL1 DO_SURF_GATE aponta para scripts/surf-gate.sh da skill" \
  "$(pval DO_SURF_GATE "$ENVF")" "$SKILL/scripts/surf-gate.sh"
# O ENV_FILE é sourceado por TODA chamada Bash: cada chave nova tem que ser uma
# linha CHAVE='valor' (aspas simples) e o arquivo tem que parsear.
for k in DO_TEST_MODE DO_QUESTION DO_SURF_SUB_AGENTS DO_WT_ROOT DO_WT_NAME DO_SURF_GATE; do
  chk "FL1 $k gravada UMA vez, entre aspas simples" "$(grep -c "^$k='[^']*'\$" "$ENVF")" "1"
done
bash -n "$ENVF" 2>/dev/null; chk "FL1 ENV_FILE parseia (bash -n)" "$?" "0"
# ...e EXPORTA: um processo-FILHO do shell que sourceou tem que enxergar (é assim
# que o do-wt.sh lê DO_TEST_MODE). Ambiente zerado para provar que vem do arquivo.
ctx --new-run --flags='no-test do-question surf-sub-agents=4'
child=$(env -i PATH="$PATH" HOME="$HOME" bash -c '. "$1" >/dev/null 2>&1; bash -c "printf %s \"\$DO_TEST_MODE:\$DO_QUESTION:\$DO_SURF_SUB_AGENTS:\$DO_WT_ROOT:\${DO_WT_NAME:-vazio}:\${DO_SURF_GATE##*/}\""' _ "$ENVF")
chk "FL1 variáveis novas EXPORTADAS para processo-filho" "$child" "none:1:4:0:vazio:surf-gate.sh"

echo "=== FL2: cada flag da tabela → ENV_FILE + resumo ==="
newrepo fl2
ctx --flags='plan=on';          chk "FL2 plan=on → DO_PLAN_APPROVAL=1" "$(pval DO_PLAN_APPROVAL "$ENVF")" "1"
hasre "FL2 plan=on no resumo" "$OUT" 'PLAN_APPROVAL += ON'
ctx --flags='plan=off';         chk "FL2 plan=off → DO_PLAN_APPROVAL=0" "$(pval DO_PLAN_APPROVAL "$ENVF")" "0"
hasre "FL2 plan=off no resumo" "$OUT" 'PLAN_APPROVAL += OFF'
# (CTX-07) OFF desliga SÓ o portão do plano: o resumo não pode mais afirmar
# "nenhuma interação" — a pergunta de pesquisa (incondicional) e a de evolução valem.
has   "FL2 plan=off: o resumo diz o que OFF desliga (só o portão do plano)" "$OUT" "PLAN_APPROVAL = OFF (sem portão de plano;"
has   "FL2 plan=off: ...e que a pergunta de pesquisa e a de evolução continuam valendo" "$OUT" "a pergunta de pesquisa (chave/cota Brave) e a de evolução continuam valendo)"
hasnt "FL2 plan=off: o texto antigo 'nenhuma interação com o usuário' saiu" "$OUT" "nenhuma interação"
hasnt "FL2 plan=off: ...e 'autonomia total' também" "$OUT" "autonomia total"
ctx --flags='plan=off do-question'
hasnt "FL2 plan=off + do-question: o resumo não se contradiz (sem 'nenhuma interação')" "$OUT" "nenhuma interação"
has   "FL2 plan=off + do-question: QUESTION = 1 na mesma saída" "$OUT" "QUESTION = 1"
ctx --flags='max-parallel=7';   chk "FL2 max-parallel=7 → DO_MAX_PARALLEL=7" "$(pval DO_MAX_PARALLEL "$ENVF")" "7"
has "FL2 max-parallel no resumo" "$OUT" "DO_MAX_PARALLEL = 7"
ctx --flags='surf-sub-agents=3'; chk "FL2 surf-sub-agents=3 → DO_SURF_SUB_AGENTS=3" "$(pval DO_SURF_SUB_AGENTS "$ENVF")" "3"
has "FL2 surf-sub-agents no resumo" "$OUT" "SURF_SUB_AGENTS = 3"
ctx --flags='no-stop';          chk "FL2 no-stop → DO_NO_STOP=1" "$(pval DO_NO_STOP "$ENVF")" "1"
hasre "FL2 no-stop no resumo" "$OUT" 'NO_STOP += ON'
ctx --flags='no-evolve';        chk "FL2 no-evolve → DO_EVOLUTION_SURVEY=0" "$(pval DO_EVOLUTION_SURVEY "$ENVF")" "0"
hasre "FL2 no-evolve no resumo" "$OUT" 'EVOLUTION += OFF'
ctx --flags='no-test';          chk "FL2 no-test → DO_TEST_MODE=none" "$(pval DO_TEST_MODE "$ENVF")" "none"
has "FL2 no-test no resumo" "$OUT" "TEST_MODE = none"
ctx --flags='only-e2e';         chk "FL2 only-e2e → DO_TEST_MODE=e2e" "$(pval DO_TEST_MODE "$ENVF")" "e2e"
has "FL2 only-e2e no resumo" "$OUT" "TEST_MODE = e2e"
ctx --flags='do-question';      chk "FL2 do-question → DO_QUESTION=1" "$(pval DO_QUESTION "$ENVF")" "1"
has "FL2 do-question no resumo" "$OUT" "QUESTION = 1"
# todas juntas, em ordem embaralhada e com espaços sobrando — UM argv só
ctx --flags='  do-question no-evolve   plan=on max-parallel=12 only-e2e surf-sub-agents=20 no-stop '
chk "FL2 todas juntas: exit 0" "$RC" "0"
chk "FL2 todas juntas: valores" \
  "$(pval DO_PLAN_APPROVAL "$ENVF"):$(pval DO_MAX_PARALLEL "$ENVF"):$(pval DO_SURF_SUB_AGENTS "$ENVF"):$(pval DO_NO_STOP "$ENVF"):$(pval DO_EVOLUTION_SURVEY "$ENVF"):$(pval DO_TEST_MODE "$ENVF"):$(pval DO_QUESTION "$ENVF")" \
  "1:12:20:1:0:e2e:1"
# --flags convive com as opções antigas, em qualquer posição
ctx --quiet --flags='no-test' --new-run
chk "FL2 --quiet + --flags + --new-run: só o ENV_FILE na saída" "$OUT" "$ENVF"
chk "FL2 ...e a flag valeu" "$(pval DO_TEST_MODE "$ENVF")" "none"

echo "=== FL3: flag VENCE a variável de ambiente ==="
newrepo fl3
OUT=$(DO_TEST_MODE=none "$CTX" --flags='only-e2e' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 only-e2e vence DO_TEST_MODE=none" "$(pval DO_TEST_MODE "$ENVF")" "e2e"
OUT=$(DO_TEST_MODE=e2e "$CTX" --flags='no-test' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 no-test vence DO_TEST_MODE=e2e (env não conta como conflito)" "$(pval DO_TEST_MODE "$ENVF")" "none"
OUT=$(DO_PLAN_APPROVAL=1 "$CTX" --flags='plan=off' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 plan=off vence DO_PLAN_APPROVAL=1" "$(pval DO_PLAN_APPROVAL "$ENVF")" "0"
OUT=$(DO_MAX_PARALLEL=9 "$CTX" --flags='max-parallel=4' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 max-parallel=4 vence DO_MAX_PARALLEL=9" "$(pval DO_MAX_PARALLEL "$ENVF")" "4"
OUT=$(DO_SURF_SUB_AGENTS=5 "$CTX" --flags='surf-sub-agents=2' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 surf-sub-agents=2 vence DO_SURF_SUB_AGENTS=5" "$(pval DO_SURF_SUB_AGENTS "$ENVF")" "2"
OUT=$(DO_QUESTION=0 "$CTX" --flags='do-question' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 do-question vence DO_QUESTION=0" "$(pval DO_QUESTION "$ENVF")" "1"
OUT=$(DO_NO_STOP=0 "$CTX" --flags='no-stop' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 no-stop vence DO_NO_STOP=0" "$(pval DO_NO_STOP "$ENVF")" "1"
OUT=$(DO_EVOLUTION_SURVEY=1 "$CTX" --flags='no-evolve' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 no-evolve vence DO_EVOLUTION_SURVEY=1" "$(pval DO_EVOLUTION_SURVEY "$ENVF")" "0"
# env INVÁLIDO é coberto pela flag: quem decide é o token
OUT=$(DO_TEST_MODE=banana "$CTX" --flags='no-test' 2>&1); rc=$?; ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL3 flag cobre env inválido: exit 0" "$rc" "0"
chk "FL3 flag cobre env inválido: valor" "$(pval DO_TEST_MODE "$ENVF")" "none"

echo "=== FL4: variável de ambiente SOZINHA ainda funciona (fallback) ==="
newrepo fl4
OUT=$(DO_TEST_MODE=none "$CTX" 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL4 DO_TEST_MODE=none (sem --flags)" "$(pval DO_TEST_MODE "$ENVF")" "none"
has "FL4 ...e aparece no resumo" "$OUT" "TEST_MODE = none"
OUT=$(DO_TEST_MODE=e2e "$CTX" --flags='' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL4 DO_TEST_MODE=e2e (com --flags='')" "$(pval DO_TEST_MODE "$ENVF")" "e2e"
OUT=$(DO_TEST_MODE=full "$CTX" 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL4 DO_TEST_MODE=full aceito" "$(pval DO_TEST_MODE "$ENVF")" "full"
OUT=$(DO_QUESTION=1 "$CTX" 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL4 DO_QUESTION=1" "$(pval DO_QUESTION "$ENVF")" "1"
OUT=$(DO_QUESTION=on "$CTX" --flags='no-stop' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL4 DO_QUESTION=on normaliza para 1 (token de OUTRA flag não apaga o env)" \
  "$(pval DO_QUESTION "$ENVF"):$(pval DO_NO_STOP "$ENVF")" "1:1"
OUT=$(DO_SURF_SUB_AGENTS=7 "$CTX" 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL4 DO_SURF_SUB_AGENTS=7" "$(pval DO_SURF_SUB_AGENTS "$ENVF")" "7"
OUT=$(DO_NO_STOP=1 DO_EVOLUTION_SURVEY=0 DO_PLAN_APPROVAL=on DO_MAX_PARALLEL=3 "$CTX" --flags='' 2>&1); ENVF=$(printf '%s\n' "$OUT" | tail -1)
chk "FL4 env legado (NO_STOP/EVOLUTION/PLAN/MAX_PARALLEL) com --flags=''" \
  "$(pval DO_NO_STOP "$ENVF"):$(pval DO_EVOLUTION_SURVEY "$ENVF"):$(pval DO_PLAN_APPROVAL "$ENVF"):$(pval DO_MAX_PARALLEL "$ENVF")" "1:0:1:3"
before=$(nruns "$REPO")
DO_TEST_MODE=banana "$CTX" >/dev/null 2>&1;      chk "FL4 DO_TEST_MODE inválido → exit 2" "$?" "2"
DO_QUESTION=talvez "$CTX" >/dev/null 2>&1;       chk "FL4 DO_QUESTION inválido → exit 2" "$?" "2"
DO_SURF_SUB_AGENTS=0 "$CTX" >/dev/null 2>&1;     chk "FL4 DO_SURF_SUB_AGENTS=0 → exit 2" "$?" "2"
DO_SURF_SUB_AGENTS=21 "$CTX" >/dev/null 2>&1;    chk "FL4 DO_SURF_SUB_AGENTS=21 → exit 2" "$?" "2"
DO_SURF_SUB_AGENTS=abc "$CTX" >/dev/null 2>&1;   chk "FL4 DO_SURF_SUB_AGENTS=abc → exit 2" "$?" "2"
DO_WT_ROOT=banana "$CTX" >/dev/null 2>&1;        chk "FL4 DO_WT_ROOT inválido → exit 2" "$?" "2"
DO_MAX_PARALLEL=0 "$CTX" >/dev/null 2>&1;        chk "FL4 DO_MAX_PARALLEL=0 → exit 2" "$?" "2"
chk "FL4 nenhum run-* criado pelos aborts" "$(nruns "$REPO")" "$before"
# DO_MAX_PARALLEL é validada DEPOIS do mkdir do estado (0.9b): o rollback do die
# tem que levar junto o container de worktrees que acabou de nascer.
newrepo fl4b
DO_MAX_PARALLEL=0 "$CTX" >/dev/null 2>&1
chk "FL4 abort tardio (após o mkdir) não deixa resíduo: run-*" "$(nruns "$REPO")" "0"
chk "FL4 ...nem o container <repo>-worktrees vazio" "$([ -e "$LAB/fl4b/proj-worktrees" ] && echo sim || echo nao)" "nao"

echo "=== FL5: token desconhecido → exit 2 com sugestão ==="
newrepo fl5
before=$(nruns "$REPO")
for spec in "no-tests|no-test" "notest|no-test" "skip-tests|no-test" \
            "e2e-only|only-e2e" "e2e|only-e2e" "mp=8|max-parallel=8" \
            "ask|do-question" "question|do-question" "do-questions|do-question"; do
  tok=${spec%%|*}; sug=${spec#*|}
  ctx --flags="$tok"
  chk "FL5 '$tok' → exit 2" "$RC" "2"
  has "FL5 '$tok' sugere '$sug'" "$OUT" "quis dizer '$sug'"
done
has "FL5 a mensagem ensina o escape '--'" "$OUT" "'--'"
has "FL5 a mensagem sai como DO_ABORT 2" "$OUT" "DO_ABORT 2"
# (FT-01) flag MAL ESCRITA em --flags (hábito de CLI, caixa, underscore): exit 2 com
# a FORMA CERTA — nunca a mensagem genérica, e NUNCA consertada em silêncio.
for spec in "--no-test|no-test" "--only-e2e|only-e2e" "No-Test|no-test" "no_test|no-test" \
            "only_e2e|only-e2e" "NO-STOP|no-stop" "--do-question|do-question" "Plan=on|plan=on" \
            "--max-parallel=8|max-parallel=8" "--no-tests|no-test" "E2E-Only|only-e2e"; do
  tok=${spec%%|*}; sug=${spec#*|}
  ctx --flags="$tok"
  chk "FL5 mal escrita '$tok' → exit 2" "$RC" "2"
  has "FL5 mal escrita '$tok' sugere a forma certa '$sug'" "$OUT" "quis dizer '$sug'"
done
ctx --flags='no-stop --no-test'
chk "FL5 '--no-test' depois de flag válida → exit 2 (não aplica no-test por conta própria)" "$RC" "2"
has "FL5 ...com a forma certa" "$OUT" "quis dizer 'no-test'"
# (CTX-04) --flags= REPETIDO: antes o ÚLTIMO vencia e os tokens do 1º sumiam calados
# (--flags='no-test' --flags='do-question' => TEST_MODE=full, sem exit 2).
ctx --flags='no-test' --flags='do-question'
chk "FL5 --flags= repetido → exit 2" "$RC" "2"
has "FL5 ...a mensagem nomeia o problema" "$OUT" "--flags= repetido (2 vezes)"
has "FL5 ...e ensina a forma certa (UM argv com todos os tokens)" "$OUT" "--flags='no-test plan=off'"
ctx --quiet --new-run --flags='' --flags=''
chk "FL5 --flags= repetido → exit 2 mesmo com os dois vazios e outras opções no meio" "$RC" "2"
ctx --flags='no-stop foo=bar'
chk "FL5 token sem apelido → exit 2" "$RC" "2"
has "FL5 ...nomeia o token" "$OUT" "'foo=bar'"
has "FL5 ...e lista as flags válidas" "$OUT" "no-test only-e2e do-question"
ctx --flags='plan=talvez';      chk "FL5 plan=talvez → exit 2" "$RC" "2"
ctx --flags='max-parallel=abc'; chk "FL5 max-parallel=abc → exit 2" "$RC" "2"
ctx --flags='max-parallel=0';   chk "FL5 max-parallel=0 → exit 2" "$RC" "2"
ctx --flags='max-parallel=';    chk "FL5 max-parallel= (vazio) → exit 2" "$RC" "2"
ctx --flags='wt=on';            chk "FL5 wt=on cru → exit 2 (o orquestrador troca por wt=<slug>)" "$RC" "2"
has "FL5 ...com instrução" "$OUT" "wt=<slug"
# glob: '*' num repo com arquivos NÃO pode virar lista de arquivos
ctx --flags='*'
chk "FL5 '*' → exit 2" "$RC" "2"
has "FL5 '*' chega literal (sem glob)" "$OUT" "'*'"
hasnt "FL5 ...e o nome de arquivo do repo não vazou" "$OUT" "a.txt"
# a forma `--flags <valor>` (dois argv) é recusada: quebraria o re-exec do wt=
ctx --flags no-test;            chk "FL5 '--flags no-test' (dois argv) → exit 2" "$RC" "2"
chk "FL5 nenhum resíduo em disco (nenhum run-* criado)" "$(nruns "$REPO")" "$before"
chk "FL5 ...nem container de worktrees" "$([ -e "$LAB/fl5/proj-worktrees" ] && echo sim || echo nao)" "nao"
# um `--` literal ENCERRA a zona de prefixo: o que vem depois é texto da tarefa
ctx --flags='no-test -- no-tests e2e'
chk "FL5 '--' encerra a zona: tokens depois dele não são julgados" "$RC:$(pval DO_TEST_MODE "$ENVF")" "0:none"

echo "=== FL6: no-test + only-e2e → exit 2 ==="
newrepo fl6
ctx --flags='no-test only-e2e'
chk "FL6 no-test only-e2e → exit 2" "$RC" "2"
has "FL6 mensagem 'mutuamente exclusivos'" "$OUT" "mutuamente exclusivos"
ctx --flags='only-e2e max-parallel=3 no-test'
chk "FL6 ordem inversa, com outra flag no meio → exit 2" "$RC" "2"
has "FL6 ...mesma mensagem" "$OUT" "mutuamente exclusivos"
chk "FL6 nenhum run-* criado" "$(nruns "$REPO")" "0"
ctx --flags='no-test no-test'
chk "FL6 token repetido IGUAL é inofensivo" "$RC:$(pval DO_TEST_MODE "$ENVF")" "0:none"
ctx --flags='plan=on plan=off'
chk "FL6 plan=on + plan=off → exit 2" "$RC" "2"
has "FL6 ...anunciado como contraditório" "$OUT" "contraditórias"

echo "=== FL7: surf-sub-agents fora de 1..20 → exit 2 ==="
newrepo fl7
for v in 0 21 abc -1 1.5 999999999999999999999 ""; do
  ctx --flags="surf-sub-agents=$v"
  chk "FL7 surf-sub-agents='$v' → exit 2" "$RC" "2"
done
chk "FL7 nenhum run-* criado" "$(nruns "$REPO")" "0"
ctx --flags='surf-sub-agents=1';  chk "FL7 limite 1 passa"  "$RC:$(pval DO_SURF_SUB_AGENTS "$ENVF")" "0:1"
ctx --flags='surf-sub-agents=20'; chk "FL7 limite 20 passa" "$RC:$(pval DO_SURF_SUB_AGENTS "$ENVF")" "0:20"
ctx --flags='surf-sub-agents=08'; chk "FL7 '08' não é octal → 8" "$RC:$(pval DO_SURF_SUB_AGENTS "$ENVF")" "0:8"

echo "=== FL8: anti-stale do TEST_MODE ==="
newrepo fl8
ctx --flags='no-test'; env_nt="$ENVF"
pend "$env_nt" onda1-x ACTIVE
ctx --flags='no-test'
chk "FL8 mesma flag → REAPROVEITA a execução" "$ENVF" "$env_nt"
has "FL8 ...anunciado como DO_REUSE com TEST_MODE" "$OUT" "TEST_MODE=none"
ctx --flags=''
chk "FL8 sem a flag → execução NOVA" "$([ "$ENVF" != "$env_nt" ] && [ -f "$ENVF" ] && echo nova || echo reusou)" "nova"
has "FL8 divergência anunciada como DO_STALE" "$OUT" "TEST_MODE='none'"
has "FL8 ...com o motivo" "$OUT" "inverteria no-test/only-e2e"
chk "FL8 a run nova é full" "$(pval DO_TEST_MODE "$ENVF")" "full"
newrepo fl8b
ctx --flags=''; env_full="$ENVF"
pend "$env_full" onda1-x ACTIVE
ctx --flags='only-e2e'
chk "FL8 inverso (only-e2e sobre run full) → execução NOVA" "$([ "$ENVF" != "$env_full" ] && echo nova || echo reusou)" "nova"
chk "FL8 ...e a run nova é e2e" "$(pval DO_TEST_MODE "$ENVF")" "e2e"
# env ANTIGO (anterior à v4.1.0): sem NENHUMA das 6 chaves novas nem a linha de
# export delas — é o que o do-context.sh do HEAD anterior gravava.
NEWKEYS='^DO_TEST_MODE=\|^DO_QUESTION=\|^DO_SURF_SUB_AGENTS=\|^DO_WT_ROOT=\|^DO_WT_NAME=\|^DO_SURF_GATE='
oldify() { grep -v "$NEWKEYS\|^export DO_TEST_MODE " "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
newrepo fl8c
ctx --flags=''; env_old="$ENVF"
oldify "$env_old"
chk "FL8 env antigo não tem as chaves" "$(grep -c "$NEWKEYS" "$env_old" | tr -d ' ')" "0"
chk "FL8 fixture: sem completar, o portão de pesquisa do env antigo é 'command not found' (rc 127)" \
  "$(env -i PATH="$PATH" HOME="$HOME" /bin/bash -c '. "$1" >/dev/null 2>&1; "$DO_SURF_GATE" >/dev/null 2>&1; echo $?' _ "$env_old")" "127"
pend "$env_old" onda1-x ACTIVE
# primeiro a DIVERGÊNCIA (o env ainda está como a versão antiga o gravou)...
ctx --flags='no-test'
chk "FL8 chave ausente + no-test → execução NOVA" "$([ "$ENVF" != "$env_old" ] && echo nova || echo reusou)" "nova"
has "FL8 ...e o DO_STALE mostra o valor implícito 'full'" "$OUT" "TEST_MODE='full'"
chk "FL8 ...e um env PRETERIDO (DO_STALE) não é tocado — só o reusado é completado" "$(grep -c "$NEWKEYS" "$env_old" | tr -d ' ')" "0"
# ...depois o REUSO, por quem não passou flag de teste
ctx --flags='surf-sub-agents=6'
chk "FL8 chave ausente = full/0 → run antiga REAPROVEITADA por quem não passou flag" "$ENVF" "$env_old"
# (CTX-01/SG-7) o DO_REUSE COMPLETA o env antigo: sem isto `"$DO_SURF_GATE"` saía
# "command not found" sem linha SURF_GATE= e a pergunta da chave Brave nunca disparava.
has "FL8 DO_REUSE anuncia que completou o env antigo" "$OUT" "completei as chaves que faltavam"
for k in DO_TEST_MODE DO_QUESTION DO_SURF_SUB_AGENTS DO_WT_ROOT DO_WT_NAME DO_SURF_GATE; do
  chk "FL8 env reusado ganhou $k (UMA vez, entre aspas simples)" "$(grep -c "^$k='[^']*'\$" "$env_old")" "1"
done
chk "FL8 valores completados: full/0, o surf-sub-agents DESTA invocação, fora de wt-root" \
  "$(pval DO_TEST_MODE "$env_old"):$(pval DO_QUESTION "$env_old"):$(pval DO_SURF_SUB_AGENTS "$env_old"):$(pval DO_WT_ROOT "$env_old"):$(pval DO_WT_NAME "$env_old")" "full:0:6:0:"
chk "FL8 DO_SURF_GATE completado aponta para o surf-gate.sh DESTA skill" "$(pval DO_SURF_GATE "$env_old")" "$SKILL/scripts/surf-gate.sh"
bash -n "$env_old" 2>/dev/null; chk "FL8 env completado parseia (bash -n)" "$?" "0"
chk "FL8 env completado, sourceado sob set -u: DO_SURF_GATE é EXECUTÁVEL e as chaves chegam EXPORTADAS ao processo-filho" \
  "$(env -i PATH="$PATH" HOME="$HOME" /bin/bash -c 'set -u; . "$1" >/dev/null 2>&1; [ -x "$DO_SURF_GATE" ] || echo nao-executavel; /bin/bash -c "printf %s \"\$DO_TEST_MODE:\$DO_QUESTION:\$DO_SURF_SUB_AGENTS:\$DO_WT_ROOT:\${DO_SURF_GATE##*/}\""' _ "$env_old")" \
  "full:0:6:0:surf-gate.sh"
chk "FL8 o que o env antigo JÁ tinha ficou intacto (anexa, não reescreve)" \
  "$(pval MODE "$env_old"):$(pval BASE_DIR "$env_old"):$(grep -c '^gassert() {' "$env_old" | tr -d ' ')" "normal:$REPO:1"
ctx --flags=''
chk "FL8 2º reuso: nada é anexado de novo (cada chave segue UMA vez)" \
  "$ENVF:$(grep -c "$NEWKEYS" "$env_old" | tr -d ' ')" "$env_old:6"
hasnt "FL8 ...nem anunciado de novo" "$OUT" "completei as chaves"
# env antigo PARCIAL (só 2 chaves faltando): completa SÓ o que falta
newrepo fl8d
ctx --flags=''; env_part="$ENVF"
grep -v "^DO_TEST_MODE=\|^DO_SURF_GATE=" "$env_part" > "$env_part.tmp" && mv "$env_part.tmp" "$env_part"
pend "$env_part" onda1-x ACTIVE
ctx --flags=''
has "FL8 env parcial: o anúncio lista SÓ as chaves que faltavam" "$OUT" "(DO_TEST_MODE DO_SURF_GATE)"
chk "FL8 env parcial: nenhuma chave duplicada" \
  "$(for k in DO_TEST_MODE DO_QUESTION DO_SURF_SUB_AGENTS DO_WT_ROOT DO_WT_NAME DO_SURF_GATE; do grep -c "^$k=" "$env_part"; done | tr -d ' ' | tr '\n' ' ')" "1 1 1 1 1 1 "

echo "=== FL9: anti-stale do QUESTION ==="
newrepo fl9
ctx --flags='do-question'; env_q="$ENVF"
pend "$env_q" onda1-x ACTIVE
ctx --flags='do-question'
chk "FL9 mesma flag → REAPROVEITA" "$ENVF" "$env_q"
has "FL9 ...DO_REUSE mostra QUESTION" "$OUT" "QUESTION=1"
ctx --flags=''
chk "FL9 sem a flag → execução NOVA" "$([ "$ENVF" != "$env_q" ] && [ -f "$ENVF" ] && echo nova || echo reusou)" "nova"
has "FL9 divergência anunciada como DO_STALE" "$OUT" "QUESTION='1'"
has "FL9 ...com o motivo" "$OUT" "inverteria a flag do-question"
chk "FL9 a run nova tem QUESTION=0" "$(pval DO_QUESTION "$ENVF")" "0"
newrepo fl9b
ctx --flags=''; env_nq="$ENVF"
grep -v "^DO_QUESTION=" "$env_nq" > "$env_nq.tmp" && mv "$env_nq.tmp" "$env_nq"
pend "$env_nq" onda1-x ACTIVE
ctx --flags='do-question'
chk "FL9 chave ausente (=0) + do-question → execução NOVA" "$([ "$ENVF" != "$env_nq" ] && echo nova || echo reusou)" "nova"
has "FL9 ...DO_STALE mostra o valor implícito '0'" "$OUT" "QUESTION='0'"

echo "=== FL10: DO_ORPHAN_RUNS — run anterior viva nunca é abandonada em silêncio ==="
# (a) DO_STALE
newrepo fl10a
ctx --flags='no-test'; env_a="$ENVF"; rid_a=$(basename "$(dirname "$env_a")"); rid_a=${rid_a#run-}
pend "$env_a" onda1-x ACTIVE
pend "$env_a" onda1-y BLOCKED
pend "$env_a" onda1-z REMOVED
ctx --flags=''
has "FL10a bloco DO_ORPHAN_RUNS impresso" "$OUT" "DO_ORPHAN_RUNS: 1 "
has "FL10a nomeia a run, conta as VIVAS pela coluna 9 (ACTIVE+BLOCKED, sem a REMOVED) e o motivo" \
  "$OUT" "run=$rid_a vivas=2 motivo=DO_STALE"
has "FL10a comando EXATO de purge da run abandonada" "$OUT" ". '$env_a'; \"\$DO_WT\" purge"
chk "FL10a a ÚLTIMA linha continua sendo o ENV_FILE novo" \
  "$([ -f "$ENVF" ] && [ "$ENVF" != "$env_a" ] && echo sim || echo nao)" "sim"
chk "FL10a o env antigo NÃO foi apagado (é a única alça de limpeza)" "$([ -f "$env_a" ] && echo sim || echo nao)" "sim"
# a run nova (owned.tsv só com cabeçalho) não é órfã de ninguém
ctx --flags=''
has "FL10a segunda invocação continua listando a órfã" "$OUT" "run=$rid_a vivas=2"
chk "FL10a ...e só ela (runs vazias não entram)" "$(printf '%s\n' "$OUT" | grep -c '^  run=' | tr -d ' ')" "1"
# --quiet cala o bloco, mas a saída continua sendo só o ENV_FILE
ctx --quiet --flags=''
chk "FL10a --quiet: saída = só o ENV_FILE" "$OUT" "$ENVF"
# (b) --new-run
newrepo fl10b
ctx --flags=''; env_b="$ENVF"; rid_b=$(basename "$(dirname "$env_b")"); rid_b=${rid_b#run-}
pend "$env_b" onda1-x ACTIVE
ctx --new-run --flags=''
chk "FL10b --new-run cria execução nova" "$([ "$ENVF" != "$env_b" ] && echo nova || echo reusou)" "nova"
has "FL10b ...e a run viva preterida é listada" "$OUT" "run=$rid_b vivas=1 motivo=--new-run"
has "FL10b ...com o comando de purge" "$OUT" ". '$env_b'; \"\$DO_WT\" purge"
# (c) run só com BLOCKED/ORPHANED: não é reaproveitável, mas a worktree segue viva
newrepo fl10c
ctx --flags=''; env_c="$ENVF"; rid_c=$(basename "$(dirname "$env_c")"); rid_c=${rid_c#run-}
pend "$env_c" int-onda1-x BLOCKED
pend "$env_c" onda1-y ORPHANED
ctx --flags=''
chk "FL10c run só com BLOCKED/ORPHANED NÃO é reaproveitada" "$([ "$ENVF" != "$env_c" ] && echo nova || echo reusou)" "nova"
has "FL10c ...mas é listada como órfã" "$OUT" "run=$rid_c vivas=2 motivo=so-BLOCKED/ORPHANED"
has "FL10c ...com o comando de purge" "$OUT" ". '$env_c'; \"\$DO_WT\" purge"
# (d) sem linha viva → sem bloco; e o DO_REUSE também lista as OUTRAS vivas
newrepo fl10d
ctx --flags=''; env_d1="$ENVF"
pend "$env_d1" onda1-x REMOVED
ctx --flags=''
hasnt "FL10d run só com REMOVED → nenhum DO_ORPHAN_RUNS" "$OUT" "DO_ORPHAN_RUNS"
env_d2="$ENVF"; pend "$env_d2" onda1-a ACTIVE
sleep 1
ctx --new-run --flags=''; env_d3="$ENVF"; pend "$env_d3" onda1-b ACTIVE
ctx --flags=''
chk "FL10d duas pendentes: a mais ANTIGA é reaproveitada" "$ENVF" "$env_d2"
rid_d3=$(basename "$(dirname "$env_d3")"); rid_d3=${rid_d3#run-}
has "FL10d ...e a outra aparece no DO_ORPHAN_RUNS do caminho DO_REUSE" "$OUT" "run=$rid_d3 vivas=1 motivo=preterida"
# (e) o comando IMPRESSO, rodado de verdade, fecha a worktree abandonada
newrepo fl10e
ctx --flags='no-test'; env_e="$ENVF"
( . "$env_e" >/dev/null 2>&1; "$WT" new feature onda1-abandonada >/dev/null 2>&1 )
wt_e=$(awk -F'\t' 'NR>1 && $3=="onda1-abandonada" {print $5}' "$(dirname "$env_e")/owned.tsv")
chk "FL10e fixture: worktree-filha real criada pelo do-wt.sh" "$([ -n "$wt_e" ] && [ -d "$wt_e" ] && echo sim || echo nao)" "sim"
ctx --flags=''          # o usuário reinvoca SEM a flag: DO_STALE abandona a run
cmd_e=$(printf '%s\n' "$OUT" | grep -F "; \"\$DO_WT\" purge" | head -1 | sed 's/^ *//')
has "FL10e o comando impresso aponta para o env ANTIGO" "$cmd_e" "$env_e"
bash -n -c "$cmd_e" 2>/dev/null; chk "FL10e o comando impresso é shell válido" "$?" "0"
( cd / && bash -c "$cmd_e" ) >/dev/null 2>&1
chk "FL10e rodar o comando impresso REMOVE a worktree abandonada" "$([ -d "$wt_e" ] && echo viva || echo removida)" "removida"
chk "FL10e ...e o git só enxerga o checkout principal" "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" "1"
chk "FL10e ...e o ledger antigo não tem mais linha viva (coluna 9)" \
  "$(awk -F'\t' 'NR>1 && $9!="REMOVED" {c++} END{print c+0}' "$(dirname "$env_e")/owned.tsv")" "0"
ctx --flags=''
hasnt "FL10e depois do purge a run deixa de ser órfã" "$OUT" "DO_ORPHAN_RUNS"

echo "=== FL11: wt=<nome> — cria, REENTRA, e a flag sobrevive ao re-exec ==="
newrepo fl11
WTS="$LAB/fl11/proj.worktrees"
ctx --flags='wt=feat no-test do-question'
chk "FL11 1ª invocação: exit 0" "$RC" "0"
chk "FL11 worktree irmã criada em <repo>.worktrees/feat" "$([ -d "$WTS/feat" ] && echo sim || echo nao)" "sim"
chk "FL11 o ENV_FILE vive DENTRO do wt" "$(under "$ENVF" "$WTS/feat/.deep-orchestrator/")" "sim"
chk "FL11 MODE=contido, BASE_DIR = o wt, branch do/wt/feat" \
  "$(pval MODE "$ENVF"):$(pval BASE_DIR "$ENVF"):$(pval BASE_BRANCH "$ENVF")" "contido:$WTS/feat:do/wt/feat"
chk "FL11 DO_WT_ROOT=1 + DO_WT_NAME=feat no ENV_FILE" "$(pval DO_WT_ROOT "$ENVF"):$(pval DO_WT_NAME "$ENVF")" "1:feat"
chk "FL11 as flags SOBREVIVEM ao re-exec (no-test + do-question)" "$(pval DO_TEST_MODE "$ENVF"):$(pval DO_QUESTION "$ENVF")" "none:1"
has "FL11 resumo WT_ROOT = ON (feat)" "$OUT" "WT_ROOT = ON (feat)"
has "FL11 resumo TEST_MODE = none após o re-exec" "$OUT" "TEST_MODE = none"
chk "FL11 checkout principal intocado (sem .deep-orchestrator, árvore limpa)" \
  "$([ -e "$REPO/.deep-orchestrator" ] && echo sujo || echo limpo):$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')" "limpo:0"
# trabalho da 1ª execução, commitado no branch do wt
( cd "$WTS/feat" && echo w > w.txt && git add w.txt && git commit -qm "trabalho da 1a execucao" )
env_w1="$ENVF"
ctx --flags='wt=feat no-test do-question'
chk "FL11 2ª invocação: exit 0" "$RC" "0"
has "FL11 2ª invocação REENTRA" "$OUT" "REENTRANDO $WTS/feat"
chk "FL11 NÃO criou feat-2" "$([ -e "$WTS/feat-2" ] && echo criou || echo nao)" "nao"
chk "FL11 git worktree list: principal + UM wt" "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" "2"
chk "FL11 nenhum branch do/wt/feat-2" "$(git -C "$REPO" branch --list 'do/wt/feat-2' | wc -l | tr -d ' ')" "0"
chk "FL11 BASE_DIR continua sendo o MESMO wt, no MESMO branch" \
  "$(pval BASE_DIR "$ENVF"):$(pval BASE_BRANCH "$ENVF")" "$WTS/feat:do/wt/feat"
chk "FL11 o trabalho da 1ª execução está lá" "$([ -f "$(pval BASE_DIR "$ENVF")/w.txt" ] && echo sim || echo nao)" "sim"
chk "FL11 a flag sobrevive ao re-exec também na REENTRADA" "$(pval DO_TEST_MODE "$ENVF"):$(pval DO_QUESTION "$ENVF")" "none:1"
hasnt "FL11 o typo 'DOCTYPE:' saiu da saída" "$OUT" "DOCTYPE"
# run interrompida DENTRO do wt: reinvocar do principal tem que dar DO_REUSE nela
env_w2="$ENVF"; pend "$env_w2" onda1-x ACTIVE
ctx --flags='wt=feat no-test do-question'
has "FL11 run pendente dentro do wt → DO_REUSE" "$OUT" "DO_REUSE"
chk "FL11 ...reaproveitando o env do wt" "$ENVF" "$env_w2"
# ...e com flag divergente o anti-stale vale LÁ DENTRO (a flag chegou pelo re-exec)
ctx --flags='wt=feat'
has "FL11 flag divergente dentro do wt → DO_STALE" "$OUT" "TEST_MODE='none'"
has "FL11 ...e a run abandonada do wt vira DO_ORPHAN_RUNS" "$OUT" ". '$env_w2'; \"\$DO_WT\" purge"
# uma run pendente do checkout PRINCIPAL não pode sequestrar o wt=
newrepo fl11b
WTS="$LAB/fl11b/proj.worktrees"
ctx --flags=''; env_main="$ENVF"; pend "$env_main" onda1-m ACTIVE
ctx --flags=''
chk "FL11b controle: sem wt=, a pendente do principal é reaproveitada" "$ENVF" "$env_main"
ctx --flags='wt=iso'
chk "FL11b com wt=, a run do principal NÃO sequestra: o env é do wt" \
  "$(under "$ENVF" "$WTS/iso/.deep-orchestrator/")" "sim"
# (CTX-02) ...mas também não é ABANDONADA em silêncio: só o REUSO é adiado para a
# re-execução; o inventário de órfãs do principal roda ANTES do re-exec.
rid_main=$(basename "$(dirname "$env_main")"); rid_main=${rid_main#run-}
has "FL11b wt= a partir do principal: a run viva do principal vira DO_ORPHAN_RUNS" "$OUT" "DO_ORPHAN_RUNS: 1 "
has "FL11b ...nomeada, contada e com o motivo wt=" "$OUT" "run=$rid_main vivas=1 motivo=wt="
has "FL11b ...com o comando EXATO de purge (env do PRINCIPAL)" "$OUT" ". '$env_main'; \"\$DO_WT\" purge"
chk "FL11b ...o bloco sai ANTES do resumo da re-execução (a última linha segue sendo o ENV_FILE do wt)" \
  "$(printf '%s\n' "$OUT" | awk '/^DO_ORPHAN_RUNS:/{o=NR} /^FASE 0 OK/{f=NR} END{print (o>0 && f>o) ? "antes" : "depois-ou-ausente"}'):$([ -f "$ENVF" ] && echo env || echo nao)" "antes:env"
ctx --flags='wt=iso'
has "FL11b ...e na REENTRADA do wt a órfã do principal continua anunciada" "$OUT" "run=$rid_main vivas=1 motivo=wt="
ctx --quiet --flags='wt=iso'
chk "FL11b ...--quiet cala o bloco: saída = só o ENV_FILE" "$OUT" "$ENVF"
# invocado de DENTRO do wt, sem o prefixo: DO_WT_ROOT vem do FATO (branch do/wt/*)
cd "$WTS/iso" && ctx --flags='' && cd "$REPO"
chk "FL11b de dentro do wt, sem wt=: DO_WT_ROOT=1 + nome" "$(pval DO_WT_ROOT "$ENVF"):$(pval DO_WT_NAME "$ENVF")" "1:iso"
# (CTX-05) wt=<OUTRO> pedido de DENTRO de um wt-root: o trabalho iria para o branch de
# outra tarefa sem aviso, e o resumo (ON (iso)) divergiria do digitado sem explicação.
cd "$WTS/iso" && ctx --flags='wt=other'; cd "$REPO"
chk "FL11b wt=other de dentro do wt-root iso: exit 0, segue no iso" "$RC:$(pval DO_WT_NAME "$ENVF"):$(pval BASE_BRANCH "$ENVF")" "0:iso:do/wt/iso"
has "FL11b ...com DO_WARN nomeando o pedido e o wt-root atual" "$OUT" "DO_WARN: wt=other pedido, mas o cwd JÁ é o wt-root 'iso'"
has "FL11b ...e a saída documentada (invocar do checkout principal)" "$OUT" "invoque a partir do checkout principal ($REPO)"
chk "FL11b ...e nenhuma worktree 'other' nasceu (nem branch)" \
  "$([ -e "$WTS/other" ] && echo criou || echo nao):$(git -C "$REPO" branch --list 'do/wt/other' | wc -l | tr -d ' ')" "nao:0"
cd "$WTS/iso" && ctx --flags='wt=iso'; cd "$REPO"
hasnt "FL11b wt=iso de dentro do iso (mesmo nome): sem DO_WARN" "$OUT" "DO_WARN: wt="
cd "$WTS/iso" && ctx --flags='wt=ISO'; cd "$REPO"
hasnt "FL11b wt=ISO de dentro do iso (mesmo slug): sem DO_WARN" "$OUT" "DO_WARN: wt="
# dedupe SÓ contra o que NÃO é o wt-root deste repo
mkdir -p "$WTS/alien" && echo lixo > "$WTS/alien/f.txt"
ctx --flags='wt=alien'
has "FL11b diretório estranho com o mesmo nome → deduplica" "$OUT" "nome deduplicado -> alien-2"
hasnt "FL11b ...e o nome deduplicado na re-execução NÃO é tratado como 'wt=<outro>' (sem DO_WARN)" "$OUT" "DO_WARN: wt="
chk "FL11b ...DO_WT_NAME é o nome DEDUPLICADO (a flag trazia o cru)" "$(pval DO_WT_NAME "$ENVF"):$(pval BASE_BRANCH "$ENVF")" "alien-2:do/wt/alien-2"
chk "FL11b ...e o diretório estranho ficou intocado" "$(cat "$WTS/alien/f.txt")" "lixo"
ctx --flags='wt=alien'
has "FL11b reinvocar wt=alien REENTRA no alien-2 (mesmo pedido = mesma worktree)" "$OUT" "REENTRANDO $WTS/alien-2"
chk "FL11b ...sem criar alien-3" "$([ -e "$WTS/alien-3" ] && echo criou || echo nao)" "nao"
# worktree DESTE repo no path, mas em OUTRO branch → não é o wt-root: deduplica
git -C "$REPO" worktree add -q "$WTS/outro" -b feature/outro
ctx --flags='wt=outro'
has "FL11b worktree deste repo em outro branch → deduplica (não reentra)" "$OUT" "nome deduplicado -> outro-2"
chk "FL11b ...e a worktree alheia continua no branch dela" "$(git -C "$WTS/outro" branch --show-current)" "feature/outro"
# wt= pedido de dentro de uma worktree vinculada que NÃO é wt-root: avisa, não finge
cd "$WTS/outro" && ctx --flags='wt=xyz' && cd "$REPO"
chk "FL11b wt= dentro de worktree comum: DO_WT_ROOT=0 (fato)" "$(pval DO_WT_ROOT "$ENVF"):$(pval MODE "$ENVF")" "0:contido"
has "FL11b ...com DO_WARN" "$OUT" "DO_WARN: wt= pedido"
chk "FL11b ...e nenhuma worktree xyz nasceu" "$([ -e "$WTS/xyz" ] && echo criou || echo nao)" "nao"

echo "=== FL12: owned.tsv — 11 colunas, linhas vivas pela coluna 9 ==="
newrepo fl12
ctx --flags=''; own="$(dirname "$ENVF")/owned.tsv"
chk "FL12 cabeçalho tem 11 colunas" "$(awk -F'\t' 'NR==1 {print NF}' "$own")" "11"
chk "FL12 colunas 9/10/11 = status/parent/outcome" "$(awk -F'\t' 'NR==1 {print $9 ":" $10 ":" $11}' "$own")" "status:parent:outcome"
chk "FL12 colunas 1..8 inalteradas" "$(awk -F'\t' 'NR==1 {print $1 ":" $2 ":" $3 ":" $4 ":" $5 ":" $6 ":" $7 ":" $8}' "$own")" \
  "run_id:kind:name:branch:path:base_sha:pre_merge_sha:post_merge_sha"
# status REMOVED na coluna 9 com outcome "vivo-parecendo" na 11: NÃO é pendente
env12="$ENVF"
printf 'r\tfeature\tonda1-a\tb\tp\ts\t\t\tREMOVED\t-\tNEVER-MERGED:ACTIVE\n' >> "$own"
ctx --flags=''
chk "FL12 REMOVED na col 9 (com 'ACTIVE' na col 11) não conta como viva" "$([ "$ENVF" != "$env12" ] && echo nova || echo reusou)" "nova"
hasnt "FL12 ...nem vira órfã" "$OUT" "DO_ORPHAN_RUNS"
# gate-pending na coluna 9, com 7/8 vazias e 10/11 preenchidas: É pendente
env12b="$ENVF"
printf 'r\tfeature\tonda1-b\tb\tp\ts\t\t\tgate-pending\t-\t-\n' >> "$(dirname "$env12b")/owned.tsv"
ctx --flags=''
chk "FL12 gate-pending na col 9 (status NÃO é a última coluna) → DO_REUSE" "$ENVF" "$env12b"
# linha ANTIGA de 9 colunas segue sendo lida (10/11 ausentes = '-')
newrepo fl12b
ctx --flags=''; env12c="$ENVF"
printf 'r\tfeature\tonda1-c\tb\tp\ts\t-\t-\tACTIVE\n' >> "$(dirname "$env12c")/owned.tsv"
ctx --flags=''
chk "FL12 linha legada de 9 colunas ACTIVE → DO_REUSE" "$ENVF" "$env12c"

echo "=== FL13: --help imprime o cabeçalho inteiro ==="
help=$("$CTX" --help 2>&1); rc=$?
chk "FL13 --help → exit 0" "$rc" "0"
has "FL13 documenta --flags" "$help" "--flags="
has "FL13 documenta a tabela (do-question → DO_QUESTION=1)" "$help" "do-question → DO_QUESTION=1"
has "FL13 chega ao ÚLTIMO exit code (9) — não trunca por nº de linha" "$help" "9 = colisão de namespace"
hasnt "FL13 ...e para no fim do cabeçalho (não vaza código)" "$help" "set -uo pipefail"

echo "=== FL14: path com espaço e acento ==="
newrepo "fl14 espaço é acentuação"
ctx --flags='no-test'; env_s="$ENVF"
chk "FL14 FASE 0 com flag em path com espaço/acento" "$RC:$(pval DO_TEST_MODE "$ENVF")" "0:none"
( . "$env_s" >/dev/null 2>&1; "$WT" new feature onda1-espaco >/dev/null 2>&1 )
wt_s=$(awk -F'\t' 'NR>1 && $3=="onda1-espaco" {print $5}' "$(dirname "$env_s")/owned.tsv")
chk "FL14 fixture: worktree-filha real" "$([ -n "$wt_s" ] && [ -d "$wt_s" ] && echo sim || echo nao)" "sim"
ctx --flags='only-e2e'
has "FL14 DO_ORPHAN_RUNS traz o path com espaço entre aspas simples" "$OUT" ". '$env_s'; \"\$DO_WT\" purge"
cmd_s=$(printf '%s\n' "$OUT" | grep -F "; \"\$DO_WT\" purge" | head -1 | sed 's/^ *//')
( cd / && bash -c "$cmd_s" ) >/dev/null 2>&1
chk "FL14 o comando impresso fecha a worktree abandonada (path com espaço)" "$([ -d "$wt_s" ] && echo viva || echo removida)" "removida"
ctx --flags='wt=com-espaco only-e2e'; env_s1="$ENVF"
chk "FL14 wt= em path com espaço: criado, flag sobrevive ao re-exec" \
  "$RC:$(pval DO_WT_NAME "$ENVF"):$(pval DO_TEST_MODE "$ENVF")" "0:com-espaco:e2e"
ctx --flags='wt=com-espaco only-e2e'
has "FL14 ...e a 2ª invocação REENTRA" "$OUT" "REENTRANDO $LAB/fl14 espaço é acentuação/proj.worktrees/com-espaco"
chk "FL14 ...sem criar com-espaco-2" "$([ -e "$LAB/fl14 espaço é acentuação/proj.worktrees/com-espaco-2" ] && echo criou || echo nao)" "nao"

cd "$LAB"
echo; printf 'RESULTADO: %s PASS, %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1
