#!/usr/bin/env bash
# =============================================================================
# evolution-survey.sh — PERGUNTA DE EVOLUÇÃO pós-execução (FASE 4, passo 7.5)
# -----------------------------------------------------------------------------
# A evolução NÃO é mais um site (Plannotator): é UMA PERGUNTA EM TEXTO no
# terminal, feita DEPOIS de TUDO (commit, push, relatório — v3.9.0). O
# orquestrador roda `ask`, imprime o bloco da pergunta na mensagem final e
# ENCERRA o turno; o usuário responde com códigos na próxima mensagem; o
# orquestrador (FASE 0, passo 0.4 — continuação) roda `answer` + `apply`.
#
# Uso (com o ENV_FILE da FASE 0 sourceado, ou via --env <arquivo>):
#   evolution-survey.sh ask                  monta a pergunta → pendente.md + stdout
#   evolution-survey.sh answer "<texto>"     parseia a resposta do usuário → answers.json
#   evolution-survey.sh apply                aplica as respostas via do-prefs.sh
#   evolution-survey.sh dismiss              sem resposta (seguiu em frente) → tudo pendente
#   evolution-survey.sh status               imprime o trail do passo de evolução
#
# Gramática da resposta (uma proposta → um código):
#   N:XY     N = número da proposta (1..N) · X = opção (a|b|c) · Y = escopo (1|2)
#   b2       forma abreviada quando há UMA proposta só
#   a|b = salvar com a AÇÃO escolhida (opção vira o acao) · c = descartar
#   1 = fix LOCAL (projeto) · 2 = fix GLOBAL (skill)
#   "nada" | "pular" | "skip" | vazio → nada salvo (tudo pendente)
#   "config: <texto>"                    → preferência livre do projeto
#
# Exit codes: 0 ok · 2 uso/ambiente/gramática inválidos.
# Ambiente: DO_STATE (obrigatório via ENV_FILE), DO_PREFS, PROJECT_* (apply).
# =============================================================================

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

if [ "${1:-}" = "--env" ]; then
  # shellcheck source=/dev/null
  . "$2" || { echo "evolution-survey.sh: não consegui sourcear $2" >&2; exit 2; }
  shift 2
fi

err()  { printf '%s\n' "$*" >&2; }
note() { printf '%s\n' "$*" >&2; }   # diagnóstico humano: SEMPRE stderr, para
                                     # que o stdout continue sendo contrato.

EX_DONE=0
EX_USAGE=2

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)"
# shellcheck source=/dev/null
. "$_self_dir/lib/evolve-common.sh"

case "${1:-}" in
  -h|--help|help)
    sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  '')
    sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit "$EX_USAGE" ;;
  *) : "${DO_STATE:?evolution-survey.sh: sourceie o ENV_FILE da FASE 0 antes (ou use --env <arquivo>)}" ;;
esac

EVOL_DIR="$DO_STATE/evolution"
PROPOSALS="$EVOL_DIR/proposals.md"
PENDENTE="$EVOL_DIR/pendente.md"
TRAIL="$EVOL_DIR/trail.tsv"
TRAIL_HEADER='when	step	detail'

trail() { # <step> <detail>
  mkdir -p "$EVOL_DIR" 2>/dev/null || true
  [ -f "$TRAIL" ] || printf '%s\n' "$TRAIL_HEADER" > "$TRAIL"
  printf '%s\t%s\t%s\n' "$(now_iso)" "$1" "$2" >> "$TRAIL"
}

pick_json_tool() {
  if command -v jq >/dev/null 2>&1; then
    JSON_TOOL=jq; return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    JSON_TOOL=python3; return 0
  fi
  err "evolution-survey.sh: preciso de jq OU python3 para montar o answers.json"
  return 1
}

# ---------------------------------------------------------------------------
# ask — monta a PERGUNTA em texto a partir das propostas (proposals.md)
# ---------------------------------------------------------------------------
# Gera $EVOL_DIR/pendente.md (a pergunta no formato de códigos, preservada no
# disco para a continuação FASE 0 0.4) e imprime o bloco no stdout — o
# orquestrador cola esse bloco na mensagem final e encerra o turno.
cmd_ask() {
  [ -f "$PROPOSALS" ] || { err "evolution-survey.sh: proposals não encontrado: $PROPOSALS (o agente de evolução não rodou?)"; exit "$EX_USAGE"; }

  local -a blocks=()
  read_candidates "$PROPOSALS"
  local n=0
  for b in "${CANDIDATES[@]}"; do
    parse_fields "$b"
    [ -n "$B_KEY" ] || { err "evolution-survey.sh: proposta sem 'key:' ignorada no ask"; continue; }
    [ -n "$B_OBS" ] || { err "evolution-survey.sh: proposta $B_KEY sem 'observacao' ignorada no ask"; continue; }
    if [ -z "$B_OPCAO_A" ] || [ -z "$B_OPCAO_B" ]; then
      err "evolution-survey.sh: proposta $B_KEY sem 'opcao_a'/'opcao_b' — a pergunta exige as duas (v3.9.0)"; continue
    fi
    [ -n "$B_OPCAO_C" ] || B_OPCAO_C="Não fazer nada (descartar)"
    n=$((n + 1))
    blocks+=("$b")
  done

  if [ "$n" -eq 0 ]; then
    printf 'SEM-PROPOSTAS\n'
    trail ask "sem propostas qualificadas"
    exit "$EX_DONE"
  fi

  local out="" i=0 blk obs oa ob oc
  out=$(printf '%s\n' \
    "# Pergunta de evolução — run $RUN_ID" \
    '' \
    'EVOLUÇÃO PÓS-EXECUÇÃO — como quer resolver? (responda com códigos; "nada" para pular)')
  for blk in "${blocks[@]}"; do
    i=$((i + 1))
    parse_fields "$blk"
    obs="$B_OBS"; oa="$B_OPCAO_A"; ob="$B_OPCAO_B"; oc="$B_OPCAO_C"
    out=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$out" \
      "$i - $obs" \
      "   como resolver definitivamente?" \
      "   a: $oa" \
      "   b: $ob" \
      "   c: $oc" \
      "   (1 = fix local · 2 = fix global — qual config você quer? ex.: $i:b2)")
  done
  out=$(printf '%s\n%s\n%s\n' "$out" \
    '' \
    'Responda com os códigos (ex.: "1:b2 2:c1"), "nada" para não salvar nada, ou "config: <texto>" para salvar uma preferência do projeto.')

  mkdir -p "$EVOL_DIR" 2>/dev/null || { err "evolution-survey.sh: não consegui criar $EVOL_DIR"; exit "$EX_USAGE"; }
  printf '%s\n' "$out" > "$PENDENTE" \
    || { err "evolution-survey.sh: não consegui gravar $PENDENTE"; exit "$EX_USAGE"; }
  trail ask "N propostas: $n"
  printf '%s\n' "$out"
  exit "$EX_DONE"
}

# ---------------------------------------------------------------------------
# answer "<texto>" — gramática de códigos → answers.json
# ---------------------------------------------------------------------------
# answers.json mantém o contrato do apply: {run_id, generated_at, answers,
# configs} com answers = {P001: {save: sim|nao|pendente, scope: project|global,
# opcao: a|b|c}}. O `apply` consome isto.
cmd_answer() {
  [ -f "$PROPOSALS" ] || { err "evolution-survey.sh: proposals não encontrado: $PROPOSALS"; exit "$EX_USAGE"; }
  pick_json_tool || exit "$EX_USAGE"

  local -a keys=()
  read_candidates "$PROPOSALS"
  local b
  for b in "${CANDIDATES[@]}"; do
    parse_fields "$b"
    [ -n "$B_KEY" ] && keys+=("$B_KEY")
  done
  local nprops=${#keys[@]}
  [ "$nprops" -gt 0 ] || { err "evolution-survey.sh: nenhuma proposta com key em $PROPOSALS"; exit "$EX_USAGE"; }

  local texto="${1:-}"
  # "nada"/"pular"/vazio → nada salvo (answers.json vazio; apply pende tudo)
  local norm
  norm=$(printf '%s' "$texto" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ *//; s/ *$//')
  if [ -z "$norm" ] || [ "$norm" = "nada" ] || [ "$norm" = "pular" ] || [ "$norm" = "skip" ] \
     || [ "$norm" = "nao" ] || [ "$norm" = "não" ] || [ "$norm" = "nao salvar" ]; then
    texto=""
  fi

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/evol-answer.XXXXXX")" || { err "sem tmp"; exit "$EX_USAGE"; }
  trap 'rm -rf "$tmp"' RETURN
  : > "$tmp/raw.tsv"

  # Passada 1: linha a linha sobre o texto bruto. Uma linha pode ser:
  #   • uma cláusula `config: <texto>` (o texto tem espaços — nunca quebrar),
  #     no início OU no meio da linha ("1:b2 config: texto");
  #   • códigos separados por espaço/vírgula/ponto-e-vírgula (ex.: "1:b2 2:c1").
  # (aqui-string, NÃO pipeline — um pipeline roda o loop em subshell e o
  # flag de erro não propagaria; compatível com bash 3.2)
  local ok=1 line key save scope opcao tok restline cfgpart
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$line" ] || continue
    # cláusula config: pode vir no início OU no meio da linha — tudo a
    # partir de 'config:' até o fim da linha é o texto da config
    restline="$line"
    if printf '%s\n' "$line" | grep -Eq '(^|[[:space:]])config:'; then
      cfgpart=$(printf '%s\n' "$line" | sed -E 's/^.*config:[[:space:]]*//')
      restline=$(printf '%s\n' "$line" | sed -E 's/[[:space:]]*config:.*//')
      [ -n "$cfgpart" ] && printf 'configs\t%s\n' "$(printf '%s' "$cfgpart" | tr -d '\t\r\n')" >> "$tmp/raw.tsv"
    fi
    # quebra o restante em tokens (espaço/vírgula/ponto-e-vírgula)
    while IFS= read -r tok || [ -n "$tok" ]; do
      [ -n "$tok" ] || continue
      if printf '%s\n' "$tok" | grep -Eq '^[0-9]+:[abc][12]$'; then
        printf 'answers\t%s\t%s\t%s\n' \
          "$(printf '%s\n' "$tok" | sed -E 's/^([0-9]+):.*/\1/')" \
          "$(printf '%s\n' "$tok" | sed -E 's/^[0-9]+:([abc]).*/\1/')" \
          "$(printf '%s\n' "$tok" | sed -E 's/^[0-9]+:[abc]([12]).*/\1/')" >> "$tmp/raw.tsv"
      elif [ "$nprops" -eq 1 ] && printf '%s\n' "$tok" | grep -Eq '^[abc][12]$'; then
        printf 'answers\t1\t%s\t%s\n' \
          "$(printf '%s\n' "$tok" | sed -E 's/^([abc]).*/\1/')" \
          "$(printf '%s\n' "$tok" | sed -E 's/^[abc]([12]).*/\1/')" >> "$tmp/raw.tsv"
      else
        err "evolution-survey.sh: resposta ilegível: '$tok'"
        err "              Esperado: N:XY (ex.: 1:b2) · 'nada' · 'config: <texto>'"
        ok=0
      fi
    done <<< "$(printf '%s\n' "$restline" | tr -s ' ,;' '\n')"
  done <<< "$texto"
  [ "$ok" = 1 ] || exit "$EX_USAGE"

  # Passada 2: resolve chaves (N → key do proposals) e deriva save/scope/opcao.
  # (sem arrays associativos — compatível com bash 3.2: mapa em arquivo)
  : > "$tmp/ans.tsv"
  : > "$tmp/keymap"
  local i=0 k
  for k in "${keys[@]}"; do
    i=$((i + 1))
    printf '%s\t%s\n' "$i" "$k" >> "$tmp/keymap"
  done
  local line_num keynum opt digit scope_k save_k opcao_k
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      answers*)
        keynum=$(printf '%s\n' "$line" | cut -f2)
        opt=$(printf '%s\n' "$line" | cut -f3)
        digit=$(printf '%s\n' "$line" | cut -f4)
        [ "$keynum" -ge 1 ] 2>/dev/null && [ "$keynum" -le "$nprops" ] 2>/dev/null || {
          err "evolution-survey.sh: número de proposta fora do intervalo: $keynum (1..$nprops)"; exit "$EX_USAGE"; }
        k=$(awk -F'\t' -v n="$keynum" '$1==n { print $2; exit }' "$tmp/keymap")
        [ -n "$k" ] || { err "evolution-survey.sh: chave não resolvida para a proposta $keynum"; exit "$EX_USAGE"; }
        case "$opt" in
          a|b) save_k=sim ;;
          c)   save_k=nao ;;
        esac
        case "$digit" in
          1) scope_k=project ;;
          2) scope_k=global ;;
        esac
        opcao_k="$opt"
        # schema do jq/python3 da passada 3: answers<TAB>key<TAB>save<TAB>scope<TAB>opcao
        printf 'answers\t%s\t%s\t%s\t%s\n' "$k" "$save_k" "$scope_k" "$opcao_k" >> "$tmp/ans.tsv"
        ;;
      configs*)
        printf '%s\n' "$line" >> "$tmp/ans.tsv" ;;
    esac
  done < "$tmp/raw.tsv"

  # Passada 3: raw.tsv → answers.json (nunca à mão — jq ou python3).
  local run_id gen
  gen="$(now_iso)"
  run_id="${RUN_ID:-$(date +%s)}"
  case "$JSON_TOOL" in
    jq)
      jq -Rn --arg run "$run_id" --arg gen "$gen" '
        reduce inputs as $l ({run_id: $run, generated_at: $gen, answers: {}, configs: []};
          ($l | split("\t")) as $p |
          if $p[0] == "answers" then
            .answers[$p[1]] = {save: $p[2], scope: $p[3], opcao: $p[4]}
          elif $p[0] == "configs" then
            .configs += [$p[1]]
          else . end)' < "$tmp/ans.tsv" > "$tmp/answers.json" 2>/dev/null || true
      ;;
    python3)
      python3 - "$tmp/ans.tsv" "$run_id" "$gen" > "$tmp/answers.json" <<'PYEOF' || true
import json, sys
raw, run_id, gen = sys.argv[1], sys.argv[2], sys.argv[3]
out = {"run_id": run_id, "generated_at": gen, "answers": {}, "configs": []}
try:
    with open(raw, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if p[0] == "answers" and len(p) >= 4:
                out["answers"][p[1]] = {"save": p[2], "scope": p[3], "opcao": p[4]}
            elif p[0] == "configs" and len(p) >= 2:
                out["configs"].append(p[1])
except FileNotFoundError:
    pass
json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
PYEOF
      ;;
  esac
  if [ ! -s "$tmp/answers.json" ]; then
    printf '{\n  "run_id": "%s",\n  "generated_at": "%s",\n  "answers": {},\n  "configs": []\n}\n' "$run_id" "$gen" > "$tmp/answers.json"
  fi

  mkdir -p "$EVOL_DIR" 2>/dev/null || { err "evolution-survey.sh: não consegui criar $EVOL_DIR"; exit "$EX_USAGE"; }
  cp "$tmp/answers.json" "$EVOL_DIR/answers.json" \
    || { err "evolution-survey.sh: não consegui gravar $EVOL_DIR/answers.json"; exit "$EX_USAGE"; }
  trail answer "resposta registrada em answers.json"
  printf 'EVOLUTION_SURVEY answer=%s\n' "$EVOL_DIR/answers.json"
  cat "$EVOL_DIR/answers.json"
  exit "$EX_DONE"
}

# ---------------------------------------------------------------------------
# apply — respostas → do-prefs.sh (idempotente; nunca falha a execução — D9)
# ---------------------------------------------------------------------------
# v3.9.0: a opção escolhida (a/b) SUBSTITUI o campo acao do bloco — o usuário
# decidiu a AÇÃO definitiva, não só "salvar ou não".
cmd_apply() {
  local proposals="$PROPOSALS" answers="$EVOL_DIR/answers.json"
  local a
  while [ $# -gt 0 ]; do
    case "$1" in
      --proposals) [ $# -ge 2 ] || { err "apply: --proposals exige um arquivo"; exit "$EX_USAGE"; }; proposals="$2"; shift 2 ;;
      --proposals=*) proposals="${1#--proposals=}"; shift ;;
      --answers)    [ $# -ge 2 ] || { err "apply: --answers exige um arquivo"; exit "$EX_USAGE"; }; answers="$2"; shift 2 ;;
      --answers=*)  answers="${1#--answers=}"; shift ;;
      *) err "apply: opção desconhecida: $1"; exit "$EX_USAGE" ;;
    esac
  done

  pick_json_tool || exit "$EX_USAGE"
  : "${DO_PREFS:?apply: DO_PREFS não resolvido — sourceie o ENV_FILE da FASE 0}"
  : "${PROJECT_LEARNINGS:?apply: PROJECT_LEARNINGS não resolvido — sourceie o ENV_FILE}"
  : "${GLOBAL_TIPS:?apply: GLOBAL_TIPS não resolvido — sourceie o ENV_FILE}"
  : "${PROJECT_CONFIG:?apply: PROJECT_CONFIG não resolvido — sourceie o ENV_FILE}"
  : "${PROJECT_PENDING:?apply: PROJECT_PENDING não resolvido — sourceie o ENV_FILE}"
  : "${GLOBAL_PENDING:?apply: GLOBAL_PENDING não resolvido — sourceie o ENV_FILE}"
  PROJECT_PREFS_DIR="${PROJECT_PREFS_DIR:-$(dirname "$(dirname "$PROJECT_PENDING")")}"
  export PROJECT_PREFS_DIR

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/evol-apply.XXXXXX")" || { err "sem tmp"; exit "$EX_USAGE"; }
  trap 'rm -rf "$tmp"' RETURN

  local marker sig
  marker="$EVOL_DIR/apply.done"
  if [ -f "$answers" ]; then
    sig="$(sha_of "$answers")"
    if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$sig" ]; then
      say_apply "apply: já executado para este answers.json ($sig) — nada a fazer (idempotente)"
      exit "$EX_DONE"
    fi
  else
    sig="<sem answers.json>"
  fi

  # Dump das respostas em TSV (key<TAB>save<TAB>scope<TAB>opcao) + configs.
  : > "$tmp/ans.tsv"
  : > "$tmp/configs.tsv"
  if [ -f "$answers" ]; then
    case "$JSON_TOOL" in
      jq)
        jq -r '.answers | to_entries[] | "\(.key)\t\(.value.save // "pending")\t\(.value.scope // "")\t\(.value.opcao // "")"' "$answers" >> "$tmp/ans.tsv" 2>/dev/null || true
        jq -r '.configs[]?' "$answers" >> "$tmp/configs.tsv" 2>/dev/null || true
        ;;
      python3)
        python3 - "$answers" "$tmp/ans.tsv" "$tmp/configs.tsv" <<'PYEOF' || true
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    d = {"answers": {}, "configs": []}
with open(sys.argv[2], "w", encoding="utf-8") as a, open(sys.argv[3], "w", encoding="utf-8") as c:
    for k, v in d.get("answers", {}).items():
        a.write(f"{k}\t{v.get('save','pending')}\t{v.get('scope','')}\t{v.get('opcao','')}\n")
    for line in d.get("configs", []):
        c.write(str(line).replace("\t", " ").replace("\n", " ") + "\n")
PYEOF
        ;;
    esac
  fi

  # Propostas em blocos — o MESMO parser do do-prefs.sh (read_candidates espera
  # o formato de candidato: um '---' separando blocos). Chave = campo 'key:'.
  # Scope final = resposta do usuário, senão o da proposta. Opção a/b = a ação
  # ESCOLHIDA vira o acao do bloco salvo.
  local -a yes_project=() yes_global=() pend_project=() pend_global=() discard=()
  local bi=0 bkey bscope save scope opcao line
  if [ -f "$proposals" ]; then
    read_candidates "$proposals"
    for b in "${CANDIDATES[@]}"; do
      bi=$((bi + 1))
      parse_fields "$b"
      bkey="$B_KEY"
      bscope="${B_SCOPE:-project}"
      [ -n "$bkey" ] || { warn_apply "proposta #$bi sem 'key:' ignorada no apply"; continue; }
      save="pending"; scope=""; opcao=""
      while IFS= read -r line; do
        case "$line" in
          "$bkey"*) save=$(printf '%s\n' "$line" | cut -f2)
                    scope=$(printf '%s\n' "$line" | cut -f3)
                    opcao=$(printf '%s\n' "$line" | cut -f4) ;;
        esac
      done < "$tmp/ans.tsv"
      case "$save" in
        sim)
          scope="${scope:-$bscope}"
          # opção escolhida (a|b) → ação definitiva no bloco
          if [ -n "$opcao" ] && [ "$opcao" != c ]; then
            b="$(block_with_opcao "$b" "$opcao")"
          fi
          case "$scope" in
            project) yes_project+=("$b") ;;
            global)  yes_global+=("$b") ;;
            *) scope="$bscope"; case "$scope" in project) yes_project+=("$b") ;; *) yes_global+=("$b") ;; esac ;;
          esac ;;
        nao)
          discard+=("$bkey") ;;
        *)
          scope="${scope:-$bscope}"
          case "$scope" in
            global) pend_global+=("$b") ;;
            *)      pend_project+=("$b") ;;
          esac ;;
      esac
    done
  else
    warn_apply "proposals não encontrado: $proposals — nada a aplicar (todas as respostas viram no-op)"
  fi

  build_batch() { # <array-nome> <scope-final> <arquivo-saída>
    local -a src=()
    local arr="$1[@]" scope="$2" out="$3" x
    src=("${!arr:-}")
    : > "$out"
    for x in ${src[@]+"${src[@]}"}; do
      printf '%s\n' "$x" | sed "s/^scope: .*/scope: $scope/" >> "$out"
      printf '\n' >> "$out"
    done
  }
  local n_saved=0 n_disc=0 n_pend=0
  if [ "${#yes_project[@]}" -gt 0 ]; then
    build_batch yes_project project "$tmp/yes-project.md"
    "$DO_PREFS" add-project "$tmp/yes-project.md" || warn_apply "add-project falhou (rc=$?) — registrado, execução segue"
    n_saved=$((n_saved + ${#yes_project[@]}))
  fi
  if [ "${#yes_global[@]}" -gt 0 ]; then
    build_batch yes_global global "$tmp/yes-global.md"
    "$DO_PREFS" add-global "$tmp/yes-global.md" || warn_apply "add-global falhou (rc=$?) — registrado, execução segue"
    n_saved=$((n_saved + ${#yes_global[@]}))
  fi
  if [ "${#pend_project[@]}" -gt 0 ]; then
    build_batch pend_project project "$tmp/pend-project.md"
    "$DO_PREFS" pending-add "$tmp/pend-project.md" --scope project || warn_apply "pending-add projeto falhou (rc=$?)"
    n_pend=$((n_pend + ${#pend_project[@]}))
  fi
  if [ "${#pend_global[@]}" -gt 0 ]; then
    build_batch pend_global global "$tmp/pend-global.md"
    "$DO_PREFS" pending-add "$tmp/pend-global.md" --scope global || warn_apply "pending-add global falhou (rc=$?)"
    n_pend=$((n_pend + ${#pend_global[@]}))
  fi
  n_disc=${#discard[@]}

  # Configs livres → project-config.md (seção '## Preferências do usuário').
  if [ -s "$tmp/configs.tsv" ]; then
    mkdir -p "$(dirname "$PROJECT_CONFIG")" \
      || warn_apply "não consegui criar $(dirname "$PROJECT_CONFIG")"
    if [ ! -f "$PROJECT_CONFIG" ]; then
      printf '%s\n\n' '# Project config — deep-orchestrator-agent-skill' \
        '> Preferências DESTE projeto, escolhidas pelo usuário na pergunta de' \
        '> evolução (FASE 4, passo 7.5). Gitignored. Carregadas no início de cada' \
        '> execução (FASE 1, passo 8.5: do-prefs.sh load).' \
        '' '## Preferências do usuário' > "$PROJECT_CONFIG" \
        || warn_apply "não consegui gravar $PROJECT_CONFIG"
    elif ! grep -q '^## Preferências do usuário$' "$PROJECT_CONFIG"; then
      printf '\n## Preferências do usuário\n' >> "$PROJECT_CONFIG"
    fi
    local cline
    while IFS= read -r cline; do
      [ -n "$cline" ] || continue
      if grep -Fqx -- "- $cline" "$PROJECT_CONFIG"; then
        continue
      fi
      printf -- '- %s\n' "$cline" >> "$PROJECT_CONFIG" \
        || warn_apply "não consegui gravar config '$cline'"
      say_apply "config salva no projeto: $cline"
    done < "$tmp/configs.tsv"
  fi

  printf '%s\n' "$sig" > "$marker"
  trail apply "$n_saved salvas · $n_disc descartadas · $n_pend pendentes"

  say_apply ""
  say_apply "apply: $n_saved salva(s) (projeto/global) · $n_disc descartada(s) · $n_pend pendente(s)"
  local k
  for k in ${discard[@]+"${discard[@]}"}; do
    say_apply "  descartada (voto do usuário): $k"
  done
  exit "$EX_DONE"
}

# block_with_opcao: <bloco> <opcao> → bloco com o acao substituído pela opção
block_with_opcao() {
  local blk="$1" op="$2" val=""
  case "$op" in
    a) val="$B_OPCAO_A" ;;
    b) val="$B_OPCAO_B" ;;
  esac
  [ -n "$val" ] || { printf '%s' "$blk"; return; }
  local esc
  esc=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '%s\n' "$blk" | sed -E "s/^acao: .*/acao: \"$esc\"/"
}

# ---------------------------------------------------------------------------
# dismiss — sem resposta (usuário seguiu em frente) → tudo pendente
# ---------------------------------------------------------------------------
cmd_dismiss() {
  pick_json_tool || exit "$EX_USAGE"
  local gen run_id
  gen="$(now_iso)"
  run_id="${RUN_ID:-$(date +%s)}"
  mkdir -p "$EVOL_DIR" 2>/dev/null || { err "evolution-survey.sh: não consegui criar $EVOL_DIR"; exit "$EX_USAGE"; }
  printf '{\n  "run_id": "%s",\n  "generated_at": "%s",\n  "answers": {},\n  "configs": []\n}\n' "$run_id" "$gen" > "$EVOL_DIR/answers.json" \
    || { err "evolution-survey.sh: não consegui gravar $EVOL_DIR/answers.json"; exit "$EX_USAGE"; }
  trail dismiss "sem resposta — tudo vai para pending"
  cmd_apply
}

say_apply()  { printf 'EVOLUTION_SURVEY %s\n' "$*"; }
warn_apply() { printf 'EVOLUTION_SURVEY AVISO %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# consultas
# ---------------------------------------------------------------------------
cmd_status() {
  if [ ! -f "$TRAIL" ]; then
    note "EVOLUÇÃO: nenhum trail em $TRAIL"
    return 0
  fi
  if command -v column >/dev/null 2>&1; then
    column -t -s "$(printf '\t')" < "$TRAIL"
  else
    cat "$TRAIL"
  fi
}

usage() {
  sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  ask)      shift; cmd_ask "$@" ;;
  answer)   shift; cmd_answer "$@" ;;
  apply)    shift; cmd_apply "$@" ;;
  dismiss)  shift; cmd_dismiss "$@" ;;
  status)   shift; cmd_status "$@" ;;
  -h|--help|help) usage; exit 0 ;;
  '')       usage >&2; exit "$EX_USAGE" ;;
  *)        err "evolution-survey.sh: subcomando desconhecido: $1"; usage >&2; exit "$EX_USAGE" ;;
esac
