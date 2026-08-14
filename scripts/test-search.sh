#!/usr/bin/env bash
# Testes de aceitação da cadeia de busca — F3-06 (16 correções) + F3-05 (paralelo)
#
# Casos (cada um isolado, com bins fake em PATH temporário, SEM rede — NENHUM
# teste consome quota real):
#   T1:    argv do Tier 1 usa --budget-ms (ms) e NÃO --timeout/--dev-mode
#   T2:    saída parcial + falha do Tier 1 não polui o stdout (captura; cadeia
#          continua para o Tier 2/3)
#   T3:    envelope --json UNIFICADO (Tier 1 normalizado p/ o formato do search.sh)
#   T4:    --max-evolutions implementado no Tier 2 (loop de evolução com mock;
#          credits_remaining = 2º valor de X-RateLimit-Remaining)
#   T5:    dependências ausentes (PATH sem curl/jq/python3) → exit 2 + mensagem
#   T6:    cadeia inteira vazia → exit 1 ("sem matches" ≠ "tudo falhou")
#   T7:    check-search-credits: HTTP 403 do DDG = REACHABLE (regex corrigido)
#   T8:    check-brave-credits: cache CREDITS_LOW + --fail-fast → exit 1
#   T9:    query com "*" não expande glob no cwd (evolve_query com read -ra)
#   T10:   >1 posicional → erro; "--" preserva a query
#   T11:   --timeout sem valor → erro limpo (exit 2, sem "unbound variable")
#   T12:   trap RETURN não corrompe exit code do check-search-credits
#   PAR-1: 20 queries em paralelo (mock dorme 0.1s): todas rodam; tempo ≈ tempo
#          de 1-2 jobs (não 20×); relatório deduplica URLs repetidas
#   PAR-2: 429 na 1ª tentativa + sucesso na 2ª (backoff exponencial com jitter)
#   PAR-3: queries idênticas no lote → apenas 1 chamada real (cache intra-run)
set -uo pipefail
SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SEARCH="$SKILL/scripts/search.sh"
PARALLEL="$SKILL/scripts/search-parallel.sh"
CHECK_SEARCH="$SKILL/scripts/check-search-credits.sh"
CHECK_BRAVE="$SKILL/scripts/check-brave-credits.sh"
LAB="${TMPDIR:-/tmp}/search-accept-$$"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (esperado='$3' obtido='$2')"; fi; }

rm -rf "$LAB"; mkdir -p "$LAB"; cd "$LAB"
trap 'rm -rf "$LAB"' EXIT   # nunca deixar labs /tmp/search-accept-* órfãos

unset BRAVE_API_KEY SEARCH_SH

# --- helpers ------------------------------------------------------------------
# newcase <nome>: dir próprio do caso (bin/ + home/), env limpo por caso
newcase() {
  CASE="$LAB/$1"
  mkdir -p "$CASE/bin"
  export CASE CASE_BIN="$CASE/bin"
  unset BRAVE_API_KEY SEARCH_SH BRAVE_QUERY_INTERVAL PARALLEL_JITTER_MAX TMPDIR
  export HOME="$CASE/home"; mkdir -p "$HOME"
  cd "$CASE"
  export PATH="$CASE_BIN:$PATH"
}

# make_fake <bin> <corpo>: instala fake executável (corpo roda com o env do caso)
make_fake() {
  local bin="$1"; shift
  { printf '#!/usr/bin/env bash\n'; printf '%s\n' "$1"; } > "$CASE_BIN/$bin"
  chmod +x "$CASE_BIN/$bin"
}

# fake curl do Tier 2 (Brave): grava cada q= em curlcalls.txt, responde web.results
FAKE_CURL_T2='o=""; d=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) o="$2"; shift 2 ;;
    -D) d="$2"; shift 2 ;;
    --data-urlencode)
      case "$2" in q=*) echo "${2#q=}" >> "$CASE/curlcalls.txt";; esac
      shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$o" ]] && echo "{\"web\": {\"results\": [{\"title\": \"R1\", \"url\": \"https://b.example/1\", \"description\": \"desc 1\"}, {\"title\": \"R2\", \"url\": \"https://b.example/2\", \"description\": \"desc 2\"}, {\"title\": \"R3\", \"url\": \"https://b.example/3\", \"description\": \"desc 3\"}]}}" > "$o"
[[ -n "$d" ]] && printf "X-RateLimit-Remaining: 950, 900\n" > "$d"
echo "200"'

echo "=== T1: argv do Tier 1 usa --budget-ms (ms) e NÃO --timeout/--dev-mode ==="
newcase t1
make_fake surf-search-normal 'printf "%s\n" "$@" > "${SURF_ARGV_FILE:?}"
exit 0'
export SURF_ARGV_FILE="$CASE/argv.txt"
PATH="$CASE_BIN:$PATH" "$SEARCH" --timeout 30 --dev-mode "test query" >/dev/null 2>&1
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

echo "=== T2: saída parcial + falha do Tier 1 não polui o stdout ==="
newcase t2
make_fake surf-search-normal 'echo "PARTIAL_JUNK_STDOUT"
exit 1'
make_fake curl 'echo "{\"Abstract\": \"\", \"AbstractText\": \"\", \"Heading\": \"\", \"RelatedTopics\": [{\"Text\": \"Titulo DDG - detalhe\", \"FirstURL\": \"https://ddg.example/1\"}], \"Results\": []}"'
out=$(PATH="$CASE_BIN:$PATH" "$SEARCH" --json "query generica" 2>/dev/null); rc=$?
chk "T2 exit 0 (Tier 3 respondeu)" "$rc" "0"
chk "T2 stdout NÃO contém o parcial do fake" "$(echo "$out" | grep -c PARTIAL_JUNK_STDOUT || true)" "0"
chk "T2 stdout contém o resultado do Tier 3" "$(echo "$out" | grep -c 'https://ddg.example/1' || true)" "1"

echo "=== T3: envelope --json unificado (Tier 1 normalizado) ==="
newcase t3
make_fake surf-search-normal 'echo "{\"answer\": \"resposta sintetizada\", \"sources\": [{\"title\": \"Titulo Surf\", \"url\": \"https://surf.example/1\", \"description\": \"desc surf\"}]}"
exit 0'
out=$(PATH="$CASE_BIN:$PATH" "$SEARCH" --json "test query" 2>/dev/null); rc=$?
chk "T3 exit 0" "$rc" "0"
chk "T3 query_original preservado" "$(echo "$out" | jq -r '.query_original')" "test query"
chk "T3 answer do surf no envelope" "$(echo "$out" | jq -r '.answer')" "resposta sintetizada"
chk "T3 url extraída de sources" "$(echo "$out" | jq -r '.results[0].url')" "https://surf.example/1"
chk "T3 source marcado como surf" "$(echo "$out" | jq -r '.results[0].source')" "surf"
chk "T3 total_results" "$(echo "$out" | jq -r '.total_results')" "1"
chk "T3 diagnostics.provider" "$(echo "$out" | jq -r '.diagnostics.provider')" "surf-skill"

echo "=== T4: --max-evolutions implementado no Tier 2 (loop de evolução) ==="
newcase t4
export BRAVE_API_KEY=fake-key
export BRAVE_QUERY_INTERVAL=0
make_fake surf-search-normal 'exit 1'
make_fake curl "$FAKE_CURL_T2"
out=$(PATH="$CASE_BIN:$PATH" "$SEARCH" --json --max-evolutions 1 "test evolution query" 2>/dev/null); rc=$?
chk "T4 exit 0" "$rc" "0"
chk "T4 2 chamadas à API (1 evolução)" "$(wc -l < "$CASE/curlcalls.txt")" "2"
q1=$(sed -n '1p' "$CASE/curlcalls.txt"); q2=$(sed -n '2p' "$CASE/curlcalls.txt")
chk "T4 2ª query evoluiu" "$( [[ "$q1" != "$q2" ]] && echo sim || echo nao )" "sim"
chk "T4 query_evolution no envelope" "$(echo "$out" | jq '.query_evolution | length')" "1"
chk "T4 provider brave" "$(echo "$out" | jq -r '.diagnostics.provider')" "brave"
chk "T4 total_results (dedup)" "$(echo "$out" | jq -r '.total_results')" "3"
chk "T4 credits = 2º valor de X-RateLimit-Remaining" "$(echo "$out" | jq -r '.credits_remaining')" "900"

echo "=== T5: dependências ausentes (PATH sem curl/jq/python3) → exit 2 ==="
newcase t5
for b in bash basename dirname date cat rm mktemp; do
  ln -s "$(command -v "$b")" "$CASE_BIN/$b"
done
out=$(PATH="$CASE_BIN" bash "$SEARCH" --json "teste" 2>&1); rc=$?
chk "T5 exit 2" "$rc" "2"
case "$out" in
  *"dependências ausentes"*"curl"*"jq"*"python3"*) ok "T5 mensagem clara" ;;
  *) bad "T5 mensagem inesperada: [$out]" ;;
esac

echo "=== T6: cadeia inteira vazia → exit 1 (relatório vazio ainda é emitido) ==="
newcase t6
make_fake surf-search-normal 'echo "JUNK"
exit 1'
make_fake curl 'echo "{\"Abstract\":\"\",\"AbstractText\":\"\",\"Heading\":\"\",\"RelatedTopics\":[],\"Results\":[]}"'
out=$(PATH="$CASE_BIN:$PATH" "$SEARCH" --json "query generica" 2>/dev/null); rc=$?
chk "T6 exit 1 (sem matches em toda a cadeia)" "$rc" "1"
chk "T6 envelope emitido mesmo vazio" "$(echo "$out" | jq -r '.total_results')" "0"
chk "T6 stdout não contém o junk do Tier 1" "$(echo "$out" | grep -c JUNK || true)" "0"

echo "=== T7: check-search-credits — HTTP 403 do DDG = REACHABLE (não exit 2 falso) ==="
newcase t7
make_fake surf-search-normal 'if [[ "$1" == "--version" ]]; then echo "surf-search-normal v9.9.9"; exit 0; fi
exit 1'
make_fake curl 'echo "403"'
out=$(PATH="$CASE_BIN:$PATH" "$CHECK_SEARCH" --json 2>/dev/null); rc=$?
chk "T7 exit 1 (apenas keyless)" "$rc" "1"
chk "T7 tier3 REACHABLE com 403" "$(echo "$out" | jq -r '.tiers["3"].status')" "REACHABLE"
chk "T7 tier1 DEGRADED (sem keys.json)" "$(echo "$out" | jq -r '.tiers["1"].status')" "DEGRADED"

echo "=== T8: check-brave-credits — cache CREDITS_LOW + --fail-fast → exit 1 ==="
newcase t8
export BRAVE_API_KEY=fake-key
export TMPDIR="$CASE/tmp"; mkdir -p "$TMPDIR"
echo '{"status":"CREDITS_LOW","detail":"5 creditos restantes","credits_remaining":5,"http_status":200}' > "$TMPDIR/brave-check-cache.json"
PATH="$CASE_BIN:$PATH" "$CHECK_BRAVE" --fail-fast >/dev/null 2>&1; rc=$?
chk "T8 cache + --fail-fast → 1" "$rc" "1"
PATH="$CASE_BIN:$PATH" "$CHECK_BRAVE" >/dev/null 2>&1; rc2=$?
chk "T8 cache sem --fail-fast → 0" "$rc2" "0"

echo "=== T9: query com '*' não expande glob no cwd ==="
newcase t9
export BRAVE_API_KEY=fake-key
export BRAVE_QUERY_INTERVAL=0
touch "$CASE/ab.txt"
make_fake surf-search-normal 'exit 1'
make_fake curl "$FAKE_CURL_T2"
PATH="$CASE_BIN:$PATH" "$SEARCH" --max-evolutions 1 "ab* query" >/dev/null 2>&1; rc=$?
chk "T9 exit 0" "$rc" "0"
chk "T9 2 chamadas à API" "$(wc -l < "$CASE/curlcalls.txt")" "2"
q2=$(sed -n '2p' "$CASE/curlcalls.txt")
case "$q2" in
  *"*"*) ok "T9 2ª query mantém o '*' literal: [$q2]" ;;
  *) bad "T9 glob expandiu na evolução: [$q2]" ;;
esac
case "$q2" in
  *ab.txt*) bad "T9 expandiu para arquivo do cwd: [$q2]" ;;
  *) ok "T9 sem expansão para arquivos do cwd" ;;
esac

echo "=== T10: >1 posicional → erro; '--' preserva a query ==="
newcase t10
make_fake surf-search-normal 'printf "%s\n" "$@" > "$CASE/argv.txt"
exit 0'
PATH="$CASE_BIN:$PATH" "$SEARCH" "q1" "q2" >/dev/null 2>err.txt; rc=$?
chk "T10 >1 posicional → exit 2" "$rc" "2"
case "$(cat err.txt)" in
  *"apenas UMA query"*) ok "T10 mensagem clara" ;;
  *) bad "T10 stderr: [$(cat err.txt)]" ;;
esac
PATH="$CASE_BIN:$PATH" "$SEARCH" --json -- "query com espaco" >/dev/null 2>&1; rc=$?
chk "T10 '--' preserva query → exit 0" "$rc" "0"
case " $(cat "$CASE/argv.txt" | tr '\n' ' ') " in
  *" query com espaco "*) ok "T10 query pós-'--' chegou ao Tier 1" ;;
  *) bad "T10 argv: [$(cat "$CASE/argv.txt")]" ;;
esac

echo "=== T11: --timeout sem valor → erro limpo (sem unbound variable) ==="
newcase t11
PATH="$CASE_BIN:$PATH" "$CHECK_SEARCH" --timeout >/dev/null 2>err1.txt; rc=$?
chk "T11 check-search --timeout → exit 2" "$rc" "2"
case "$(cat err1.txt)" in
  *"requer um valor"*) ok "T11 mensagem limpa" ;;
  *) bad "T11 stderr: [$(cat err1.txt)]" ;;
esac
case "$(cat err1.txt)" in
  *"unbound"*) bad "T11 unbound variable!" ;;
  *) ok "T11 sem unbound variable" ;;
esac
PATH="$CASE_BIN:$PATH" "$CHECK_BRAVE" --timeout >/dev/null 2>err2.txt; rc=$?
chk "T11b check-brave --timeout → exit 2" "$rc" "2"
case "$(cat err2.txt)" in
  *"unbound"*) bad "T11b unbound variable!" ;;
  *) ok "T11b sem unbound variable" ;;
esac

echo "=== T12: trap RETURN não corrompe exit code do check-search-credits ==="
newcase t12
export BRAVE_API_KEY=fake-key
make_fake surf-search-normal 'if [[ "$1" == "--version" ]]; then echo "surf-search-normal v9.9.9"; exit 0; fi
exit 1'
make_fake curl 'o=""; d=""; q=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) o="$2"; shift 2 ;;
    -D) d="$2"; shift 2 ;;
    --data-urlencode) case "$2" in q=*) q="${2#q=}";; esac; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -z "$d" ]]; then echo "200"; exit 0; fi
printf "X-RateLimit-Remaining: 0, 0\n" > "$d"
case "$q" in
  *connectivity*)
    echo "{\"web\": {\"results\": [{\"title\": \"t\", \"url\": \"https://x.example/1\", \"description\": \"d\"}]}}" > "$o" ;;
  *)
    echo "{\"web\": {\"results\": []}}" > "$o" ;;
esac
echo "200"'
PATH="$CASE_BIN:$PATH" "$CHECK_SEARCH" >out.txt 2>err.txt; rc=$?
chk "T12 exit 0 limpo (T2 ativo, traps exercitados)" "$rc" "0"
case "$(cat err.txt)" in
  *"unbound"*) bad "T12 unbound variable corrompeu exit code!" ;;
  *) ok "T12 sem unbound variable no stderr" ;;
esac

echo "=== PAR-1: 20 queries em paralelo (mock 0.1s) — todas rodam, tempo ≈ 1-2 jobs, dedup ==="
newcase par1
export PARALLEL_JITTER_MAX=0
export SEARCH_SH="$CASE_BIN/search.sh"
make_fake search.sh 'echo "call" >> "$CASE/calls.txt"
sleep 0.1
echo "{\"query_original\": \"$1\", \"results\": [{\"title\": \"A\", \"url\": \"https://par.example/a\", \"description\": \"da\", \"source\": \"mock\"}, {\"title\": \"B\", \"url\": \"https://par.example/b\", \"description\": \"db\", \"source\": \"mock\"}], \"total_results\": 2, \"diagnostics\": {\"provider\": \"mock\"}}"'
queries=""; for i in $(seq 1 20); do queries="$queries q$i"; done
start=$(date +%s%3N)
PATH="$CASE_BIN:$PATH" "$PARALLEL" --json $queries > out.json 2>/dev/null; rc=$?
end=$(date +%s%3N)
elapsed=$(( end - start ))
chk "PAR-1 exit 0" "$rc" "0"
chk "PAR-1 20 chamadas ao mock" "$(wc -l < "$CASE/calls.txt")" "20"
chk "PAR-1 20 queries no relatório" "$(jq -r '.diagnostics.total_queries' out.json)" "20"
chk "PAR-1 todas bem-sucedidas" "$(jq -r '.diagnostics.successful_queries' out.json)" "20"
chk "PAR-1 dedup por URL (2 únicas)" "$(jq -r '.diagnostics.unique_results' out.json)" "2"
if (( elapsed < 1500 )); then ok "PAR-1 paralelo (${elapsed}ms — 20×0.1s sequencial seria ~2000ms+)"; else bad "PAR-1 lento demais (${elapsed}ms)"; fi

echo "=== PAR-2: 429 na 1ª tentativa + sucesso na 2ª (backoff com jitter) ==="
newcase par2
export PARALLEL_JITTER_MAX=0
export SEARCH_SH="$CASE_BIN/search.sh"
make_fake search.sh 'n=0
[[ -f "$CASE/calls.txt" ]] && n=$(wc -l < "$CASE/calls.txt")
echo "call" >> "$CASE/calls.txt"
if (( n == 0 )); then
  echo "ERRO: rate limit da Brave API (HTTP 429) persistiu após 1 tentativa." >&2
  exit 1
fi
echo "{\"query_original\": \"$1\", \"results\": [{\"title\": \"ok\", \"url\": \"https://ok.example/1\", \"description\": \"d\", \"source\": \"mock\"}], \"total_results\": 1, \"diagnostics\": {\"provider\": \"mock\"}}"'
start=$(date +%s%3N)
PATH="$CASE_BIN:$PATH" "$PARALLEL" --json "retry-me" > out.json 2>/dev/null; rc=$?
end=$(date +%s%3N)
elapsed=$(( end - start ))
chk "PAR-2 exit 0" "$rc" "0"
chk "PAR-2 2 chamadas (1 retry)" "$(wc -l < "$CASE/calls.txt")" "2"
chk "PAR-2 sucesso final registrado" "$(jq -r '.diagnostics.successful_queries' out.json)" "1"
chk "PAR-2 falha inicial registrada como resolvida" "$(jq -r '.diagnostics.failed_queries' out.json)" "0"
if (( elapsed >= 900 )); then ok "PAR-2 backoff visível (${elapsed}ms)"; else bad "PAR-2 sem backoff (${elapsed}ms)"; fi

echo "=== PAR-3: queries idênticas no lote → 1 chamada real (cache intra-run) ==="
newcase par3
export PARALLEL_JITTER_MAX=0
export SEARCH_SH="$CASE_BIN/search.sh"
make_fake search.sh 'echo "call" >> "$CASE/calls.txt"
echo "{\"query_original\": \"$1\", \"results\": [{\"title\": \"X\", \"url\": \"https://p3.example/x\", \"description\": \"dx\", \"source\": \"mock\"}], \"total_results\": 1, \"diagnostics\": {\"provider\": \"mock\"}}"'
PATH="$CASE_BIN:$PATH" "$PARALLEL" --json "mesma" "mesma" "outra" > out.json 2>/dev/null; rc=$?
chk "PAR-3 exit 0" "$rc" "0"
chk "PAR-3 apenas 2 chamadas reais (não 3)" "$(wc -l < "$CASE/calls.txt")" "2"
chk "PAR-3 1 cache hit" "$(jq -r '.diagnostics.cached_queries' out.json)" "1"
chk "PAR-3 3 queries reportadas" "$(jq -r '.diagnostics.total_queries' out.json)" "3"
chk "PAR-3 duplicata marcada como cached" "$(jq -r '[.queries[] | select(.query == "mesma") | .cached] | sort | join(",")' out.json)" "false,true"
chk "PAR-3 duplicata resolveu com resultado" "$(jq -r '[.queries[] | select(.query == "mesma") | .total_results] | join(",")' out.json)" "1,1"

echo; printf 'RESULTADO: %s PASS, %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1
