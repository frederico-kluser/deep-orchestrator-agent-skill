#!/usr/bin/env bash
# =============================================================================
# evolution-survey.sh — QUESTIONÁRIO DE EVOLUÇÃO pós-execução (FASE 4, 6.5)
# -----------------------------------------------------------------------------
# O orquestrador NÃO conversa com o questionário na mão. Toda rodada passa por
# aqui, com os mesmos invariantes do plan-approval.sh (snapshot IMUTÁVEL,
# decisão pelo envelope --json, travas de rede 127.0.0.1/share desligado) e as
# diferenças da natureza do questionário:
#   • o questionário é a ÚNICA rodada da execução (não há revisões/orçamento);
#   • SEM LIMITE DE TEMPO por decisão do usuário (DO_SURVEY_TIMEOUT=0 default;
#     >0 liga o freio opcional para execuções headless — e aí timeout vira
#     DISMISSED, que manda tudo para pending);
#   • as RESPOSTAS do usuário são ANOTAÇÕES na gramática do documento:
#         P001: sim · global      P001: sim · projeto
#         P001: sim               P001: nao
#         P001: pendente          config: <texto livre>
#     A decisão do envelope vira: annotated (com feedback) = RESPONDIDO,
#     approved (sem feedback) = NADA respondido (tudo pending), dismissed =
#     FECHADO SEM DECIDIR (tudo pending). Em TODOS os casos, NADA é aplicado
#     sem o voto explícito do usuário — a persistência é do `apply`.
#   • `apply` roteia as respostas para scripts/do-prefs.sh (projeto/global/
#     pending) — idempotente por marcação, nunca falha a execução (D9).
#
# Uso (com o ENV_FILE da FASE 0 sourceado, ou via --env <arquivo>):
#   evolution-survey.sh round <doc.md>          UMA rodada do questionário
#   evolution-survey.sh answers                 parseia o feedback → answers.json
#   evolution-survey.sh apply                   aplica as respostas via do-prefs.sh
#   evolution-survey.sh status                  imprime o trail
#   evolution-survey.sh feedback [N]            feedback da rodada N (default: última)
#   evolution-survey.sh doc [N]                 caminho do snapshot da rodada N
#
# Exit codes de `round` (o orquestrador ramifica NELES, não em texto):
#   0  FINALIZADO — usuário respondeu (annotated) OU aprovou sem responder
#   2  USAGE/ENV  — entrada ou ambiente inválidos (inclui deriva de título)
#   11 DISMISSED  — usuário fechou sem decidir (ou timeout com DO_SURVEY_TIMEOUT)
#   13 TOOLFAIL   — o Plannotator rodou e falhou (ou devolveu saída ilegível)
#
# Ambiente (todos com default; os DO_* saem do ENV_FILE da FASE 0):
#   DO_STATE                Diretório de estado da execução (obrigatório)
#   DO_SURVEY_TIMEOUT       Segundos de espera (default 0 = SEM limite)
#   DO_PLANNOTATOR_BIN      Executável explícito do Plannotator
#   DO_PLAN_SHARE           1 permite o compartilhamento externo do Plannotator
#                           (default: DESLIGADO — nada vai a serviço de paste)
#   DO_PLAN_REMOTE          1 deixa o Plannotator escutar em 0.0.0.0
#                           (default: 0 = SÓ 127.0.0.1 — /api/approve não tem
#                           autenticação; para SSH use um túnel)
#   DO_PLAN_ORIGIN          Override do harness (claude-code|pi|opencode|codex|
#                           copilot-cli|gemini-cli)
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

# --- exit codes nomeados -----------------------------------------------------
EX_DONE=0
EX_USAGE=2
EX_DISMISSED=11
EX_TOOLFAIL=13

# Helpers compartilhados do contrato do Plannotator (binário, harness,
# envelope --json, snapshot, título) — a MESMA fonte do plan-approval.sh — e
# os parsers de bloco (split_entries/entry_field) do do-prefs.sh.
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)"
# shellcheck source=/dev/null
. "$_self_dir/lib/plannotator-common.sh"
# shellcheck source=/dev/null
. "$_self_dir/lib/evolve-common.sh"

case "${1:-}" in
  -h|--help|help)
    sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  '')
    sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit "$EX_USAGE" ;;
  *) : "${DO_STATE:?evolution-survey.sh: sourceie o ENV_FILE da FASE 0 antes (ou use --env <arquivo>)}" ;;
esac

SURVEY_DIR="$DO_STATE/evolution/survey"
TRAIL="$SURVEY_DIR/trail.tsv"
TITLE_FILE="$SURVEY_DIR/title"
SURVEY_TIMEOUT="${DO_SURVEY_TIMEOUT:-0}"

case "$SURVEY_TIMEOUT" in
  ''|*[!0-9]*) err "evolution-survey.sh: DO_SURVEY_TIMEOUT inválido: '$SURVEY_TIMEOUT' (segundos, inteiro ≥ 0)"; exit "$EX_USAGE" ;;
esac

TRAIL_HEADER='revision	timestamp	decision	doc_sha	snapshot	feedback'

ensure_dir() {
  mkdir -p "$SURVEY_DIR" || { err "evolution-survey.sh: não consegui criar $SURVEY_DIR"; exit "$EX_USAGE"; }
  [ -f "$TRAIL" ] || printf '%s\n' "$TRAIL_HEADER" > "$TRAIL"
}

# A rodada é o MAIOR entre o que o trail registrou e o que existe em disco —
# uma rodada interrompida deixa um rev-NNN.md órfão sem linha no trail; contando
# só o trail, a tentativa seguinte reusaria o número e esbarraria no snapshot
# somente-leitura. Cada tentativa (retry de TOOLFAIL) consome um número novo.
last_revision() {
  local from_trail=0 from_disk=0
  [ -f "$TRAIL" ] && from_trail=$(awk -F'\t' 'NR>1 && $1 ~ /^[0-9]+$/ { if ($1+0 > m) m = $1+0 } END { print m+0 }' "$TRAIL")
  if [ -d "$SURVEY_DIR" ]; then
    from_disk=$(ls "$SURVEY_DIR" 2>/dev/null \
      | sed -n 's/^rev-0*\([0-9]\{1,\}\)\.md$/\1/p' \
      | sort -n | tail -n 1)
    [ -n "$from_disk" ] || from_disk=0
  fi
  if [ "$from_disk" -gt "$from_trail" ] 2>/dev/null; then
    printf '%s\n' "$from_disk"
  else
    printf '%s\n' "$from_trail"
  fi
}

resolve_rev() { # [N] → número da rodada (default: a última registrada)
  local n="${1:-}"
  if [ -z "$n" ]; then n="$(last_revision)"; fi
  case "$n" in
    ''|*[!0-9]*) err "evolution-survey.sh: rodada inválida: '$n'"; return 1 ;;
  esac
  [ "$n" -ge 1 ] 2>/dev/null || { err "evolution-survey.sh: nenhuma rodada registrada ainda"; return 1; }
  printf '%s\n' "$n"
}

# ---------------------------------------------------------------------------
# round <doc.md>
# ---------------------------------------------------------------------------
cmd_round() {
  local doc="${1:-}"
  [ -n "$doc" ] || { err "uso: evolution-survey.sh round <doc.md>"; exit "$EX_USAGE"; }

  ensure_dir
  pick_json_tool || exit "$EX_USAGE"

  # --- validação do documento ---
  [ -f "$doc" ] || { err "evolution-survey.sh: documento não encontrado: $doc"; exit "$EX_USAGE"; }
  [ -s "$doc" ] || { err "evolution-survey.sh: documento vazio: $doc"; exit "$EX_USAGE"; }
  local title
  title="$(first_h1 "$doc")"
  if [ -z "$title" ]; then
    err "evolution-survey.sh: o documento não tem um título '# ...'."
    err "              O Plannotator deriva o rastreamento do PRIMEIRO heading —"
    err "              o questionário nasce com um único H1."
    exit "$EX_USAGE"
  fi

  # --- imutabilidade do título entre tentativas da MESMA execução ---
  if [ -f "$TITLE_FILE" ]; then
    local locked
    locked="$(cat "$TITLE_FILE")"
    if [ "$locked" != "$title" ]; then
      err "evolution-survey.sh: o TÍTULO do questionário mudou entre tentativas — recusado."
      err "              travado : $locked"
      err "              recebido: $title"
      err "              Restaure o título exato (evolution-survey.sh title) e repita."
      exit "$EX_USAGE"
    fi
  else
    printf '%s\n' "$title" > "$TITLE_FILE"
  fi

  local rev pad snap fb out errf decfile
  rev="$(last_revision)"
  rev=$((rev + 1))
  pad="$(rev_pad "$rev")"
  snap="$SURVEY_DIR/rev-$pad.md"
  fb="$SURVEY_DIR/rev-$pad.feedback.md"
  out="$SURVEY_DIR/rev-$pad.stdout"
  errf="$SURVEY_DIR/rev-$pad.stderr"
  decfile="$SURVEY_DIR/rev-$pad.decision"

  # Snapshot IMUTÁVEL: é ELE que vai ao navegador, nunca o arquivo vivo.
  rm -f -- "$snap" 2>/dev/null || true
  cp -- "$doc" "$snap" \
    || { err "evolution-survey.sh: não consegui fotografar $doc em $snap (erro de I/O)"; exit "$EX_TOOLFAIL"; }
  chmod a-w "$snap" 2>/dev/null || true

  local bin
  if ! bin="$(resolve_bin)"; then
    err "evolution-survey.sh: Plannotator não encontrado. Rode primeiro:"
    err "              \$SKILL_HOME/scripts/check-plannotator.sh --install"
    exit "$EX_TOOLFAIL"
  fi

  local harness origin
  harness="$(detect_harness)"
  origin="$(origin_for_plannotator "$harness")"

  # --- ambiente da sessão (mesmas travas do plan-approval.sh) ---
  local -a envv=()
  envv+=("PLANNOTATOR_CWD=${BASE_DIR:-$PWD}")
  [ -n "$origin" ] && envv+=("PLANNOTATOR_ORIGIN=$origin")
  if [ "${DO_PLAN_REMOTE:-0}" = "1" ]; then
    envv+=("PLANNOTATOR_REMOTE=1")
    note "  ATENÇÃO: DO_PLAN_REMOTE=1 — o Plannotator vai escutar em 0.0.0.0 (porta"
    note "           ${PLANNOTATOR_PORT:-19432}). QUALQUER pessoa que alcance esta máquina pode LER o"
    note "           questionário e RESPONDÊ-LO (o endpoint /api/approve não tem autenticação)."
    note "           O caminho seguro para SSH é o túnel: ssh -L 19432:127.0.0.1:19432 <host>"
  else
    envv+=("PLANNOTATOR_REMOTE=0")
  fi
  if [ "${DO_PLAN_SHARE:-0}" = "1" ]; then
    note "QUESTIONÁRIO: compartilhamento externo HABILITADO por DO_PLAN_SHARE=1"
  else
    envv+=("PLANNOTATOR_SHARE=disabled")
  fi

  note "QUESTIONÁRIO DE EVOLUÇÃO — abrindo o Plannotator (sem limite de tempo)"
  note "  documento : $snap"
  note "  título    : $title"
  note "  harness   : $harness${origin:+ (PLANNOTATOR_ORIGIN=$origin)}"
  note "  timeout   : ${SURVEY_TIMEOUT}s (0 = sem limite)"
  note "  Responda anotando as linhas da gramática (P001: sim · global etc.) e envie;"
  note "  clique Approve só para terminar SEM responder (tudo fica pendente)."
  note "  Se o navegador não abrir, reabra a sessão ativa com: plannotator sessions --open 1"

  # --- execução ---
  # Sem limite de tempo por decisão do usuário; DO_SURVEY_TIMEOUT>0 liga o
  # freio opcional (headless). As flags do timeout(1) são sondadas, não
  # presumidas — um timeout BSD recusaria --foreground e o erro voltaria como
  # rc!=0, que leríamos como "o Plannotator falhou".
  local rc=0
  local -a runner=()
  if [ "$SURVEY_TIMEOUT" -gt 0 ] && command -v timeout >/dev/null 2>&1; then
    if timeout --foreground -k 1 1 true >/dev/null 2>&1; then
      runner=(timeout --foreground -k 10 "$SURVEY_TIMEOUT")
    elif timeout -k 1 1 true >/dev/null 2>&1; then
      runner=(timeout -k 10 "$SURVEY_TIMEOUT")
    elif timeout 1 true >/dev/null 2>&1; then
      runner=(timeout "$SURVEY_TIMEOUT")
    else
      note "  AVISO: timeout(1) presente mas não utilizável — a rodada pode bloquear"
    fi
  elif [ "$SURVEY_TIMEOUT" -gt 0 ]; then
    note "  AVISO: timeout(1) ausente — DO_SURVEY_TIMEOUT=$SURVEY_TIMEOUT não será aplicado"
  fi

  # </dev/null é OBRIGATÓRIO, não higiene: o dispatch do Plannotator cai num
  # `else` final que LÊ STDIN como evento de hook (mesmo contrato do
  # plan-approval.sh).
  (
    cd "${BASE_DIR:-$PWD}" 2>/dev/null || cd "$PWD" || exit 127
    env "${envv[@]}" "${runner[@]+"${runner[@]}"}" \
      "$bin" annotate "$snap" --gate --json </dev/null
  ) > "$out" 2> "$errf"
  rc=$?

  # --- interpretação ---
  local decision="" json_line
  json_line="$(last_json_line "$out")"

  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    decision="timeout"
  elif [ -n "$json_line" ]; then
    printf '%s\n' "$json_line" > "$out.json"
    decision="$(json_field "$out.json" decision)"
    if [ -z "$decision" ]; then
      decision="unparseable"
    fi
  elif [ "$rc" -ne 0 ]; then
    decision="toolfail"
  else
    decision="unparseable"
  fi

  # Feedback: o envelope contractado só traz feedback em 'annotated', mas
  # lemos o campo REGARDLESS da decisão (forward-compat: se uma versão futura
  # anexar feedback a 'approved', as respostas não se perdem).
  : > "$fb"
  if [ -f "$out.json" ]; then
    json_field "$out.json" feedback > "$fb" 2>/dev/null || true
  fi
  if ! grep -q '[^[:space:]]' "$fb"; then
    : > "$fb"
  fi

  # Classificação final:
  #   annotated   → RESPONDIDO (exit 0; answers parseia o feedback)
  #   approved    → FINALIZADO sem respostas (exit 0; apply pendes tudo)
  #   dismissed   → FECHADO SEM DECIDIR (exit 11)
  #   timeout     → DISMISSED (exit 11; ninguém respondeu)
  #   toolfail/unparseable → TOOLFAIL (exit 13)
  case "$decision" in
    annotated)
      if ! grep -q '[^[:space:]]' "$fb"; then
        note "  AVISO: decisão 'annotated' sem feedback — tratando como aprovado sem respostas"
        decision="approved"
      fi ;;
  esac
  printf '%s\n' "$decision" > "$decfile"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$rev" "$(now_iso)" "$decision" "$(sha_of "$snap")" "$snap" \
    "$([ -s "$fb" ] && printf '%s' "$fb" || printf '-')" >> "$TRAIL"

  # Linha de contrato em stdout — uma só, parseável, sempre no mesmo formato.
  printf 'EVOLUTION_SURVEY decision=%s revision=%s snapshot=%s feedback=%s\n' \
    "$decision" "$rev" "$snap" \
    "$([ -s "$fb" ] && printf '%s' "$fb" || printf '-')"

  case "$decision" in
    annotated)
      note "QUESTIONÁRIO: RESPONDIDO na rodada $rev — rode 'evolution-survey.sh answers' e 'apply'."
      exit "$EX_DONE" ;;
    approved)
      note "QUESTIONÁRIO: FINALIZADO sem respostas na rodada $rev — 'apply' mandará TUDO para pending."
      exit "$EX_DONE" ;;
    dismissed)
      note "QUESTIONÁRIO: FECHADO sem decisão na rodada $rev — 'apply' mandará TUDO para pending."
      exit "$EX_DISMISSED" ;;
    timeout)
      note "QUESTIONÁRIO: TIMEOUT (${SURVEY_TIMEOUT}s) na rodada $rev — tratado como FECHADO (tudo pending)."
      exit "$EX_DISMISSED" ;;
    *)
      note "QUESTIONÁRIO: o Plannotator falhou na rodada $rev (exit $rc, decisão '$decision')."
      note "           stdout: $out"
      note "           stderr: $errf"
      exit "$EX_TOOLFAIL" ;;
  esac
}

# ---------------------------------------------------------------------------
# answers — gramática estrita → answers.json
# ---------------------------------------------------------------------------
# A página do questionário instrui o usuário a anotar com a linha exata:
#   P001: sim · global      P001: sim · projeto
#   P001: sim               P001: nao
#   P001: pendente          config: <texto livre>
# A última resposta por proposta vence; resposta ilegível ou ausente →
# save=pending com o scope da proposta (o `apply` decide o escopo final).
cmd_answers() {
  ensure_dir
  pick_json_tool || exit "$EX_USAGE"
  local n fb
  n="$(resolve_rev "${1:-}")" || exit "$EX_USAGE"
  fb="$SURVEY_DIR/rev-$(rev_pad "$n").feedback.md"

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/evol-survey.XXXXXX")" || { err "sem tmp"; exit "$EX_USAGE"; }
  trap 'rm -rf "$tmp"' RETURN

  # Passada 1: extrai respostas em TSV (chave<TAB>save<TAB>scope) e configs.
  local line key save scope rest
  if [ -f "$fb" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if printf '%s\n' "$line" | grep -Eq '^[[:space:]]*P0?[0-9]{3}:[[:space:]]*(sim|nao|pendente)([[:space:]]*[·•][[:space:]]*(global|projeto))?[[:space:]]*$'; then
        key=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*P0?([0-9]{3}):.*/P\1/')
        save=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*P0?[0-9]{3}:[[:space:]]*//' | sed -E 's/[[:space:]]*[·•].*$//' | tr -d ' ')
        rest=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*P0?[0-9]{3}:[[:space:]]*(sim|nao|pendente)[[:space:]]*//')
        scope=""
        case "$rest" in
          *[·•]*global*) scope=global ;;
          *[·•]*projeto*) scope=project ;;
        esac
        printf 'answers\t%s\t%s\t%s\n' "$key" "$save" "$scope" >> "$tmp/raw.tsv"
      elif printf '%s\n' "$line" | grep -Eq '^[[:space:]]*config:[[:space:]]*[^[:space:]]'; then
        printf 'configs\t%s\n' "$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*config:[[:space:]]*//' | tr -d '\t\r\n')" >> "$tmp/raw.tsv"
      fi
    done < "$fb"
  fi

  # Passada 2: monta o JSON com a ferramenta escolhida (nunca à mão).
  local gen run_id
  gen="$(now_iso)"
  run_id="${RUN_ID:-$(date +%s)}"
  case "$JSON_TOOL" in
    jq)
      jq -Rn --arg run "$run_id" --arg gen "$gen" '
        reduce inputs as $l ({run_id: $run, generated_at: $gen, answers: {}, configs: []};
          ($l | split("\t")) as $p |
          if $p[0] == "answers" then
            .answers[$p[1]] = {save: $p[2], scope: $p[3]}
          elif $p[0] == "configs" then
            .configs += [$p[1]]
          else . end)' < "$tmp/raw.tsv" > "$tmp/answers.json" 2>/dev/null || true
      ;;
    python3)
      python3 - "$tmp/raw.tsv" "$run_id" "$gen" > "$tmp/answers.json" <<'PYEOF' || true
import json, sys
raw, run_id, gen = sys.argv[1], sys.argv[2], sys.argv[3]
out = {"run_id": run_id, "generated_at": gen, "answers": {}, "configs": []}
try:
    with open(raw, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if p[0] == "answers" and len(p) >= 4:
                out["answers"][p[1]] = {"save": p[2], "scope": p[3]}
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

  cp "$tmp/answers.json" "$SURVEY_DIR/answers.json" \
    || { err "evolution-survey.sh: não consegui gravar $SURVEY_DIR/answers.json"; exit "$EX_USAGE"; }
  printf 'EVOLUTION_SURVEY answers=%s\n' "$SURVEY_DIR/answers.json"
  cat "$SURVEY_DIR/answers.json"
  exit "$EX_DONE"
}

# ---------------------------------------------------------------------------
# apply — respostas → do-prefs.sh (idempotente; nunca falha a execução — D9)
# ---------------------------------------------------------------------------
cmd_apply() {
  local proposals="${DO_STATE}/evolution/proposals.md" answers="$SURVEY_DIR/answers.json"
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

  ensure_dir
  pick_json_tool || exit "$EX_USAGE"
  : "${DO_PREFS:?apply: DO_PREFS não resolvido — sourceie o ENV_FILE da FASE 0}"
  : "${PROJECT_LEARNINGS:?apply: PROJECT_LEARNINGS não resolvido — sourceie o ENV_FILE}"
  : "${GLOBAL_TIPS:?apply: GLOBAL_TIPS não resolvido — sourceie o ENV_FILE}"
  : "${PROJECT_CONFIG:?apply: PROJECT_CONFIG não resolvido — sourceie o ENV_FILE}"
  : "${PROJECT_PENDING:?apply: PROJECT_PENDING não resolvido — sourceie o ENV_FILE}"
  : "${GLOBAL_PENDING:?apply: GLOBAL_PENDING não resolvido — sourceie o ENV_FILE}"
  # Fallback defensivo: o ENV_FILE da FASE 0 exporta PROJECT_PREFS_DIR, mas se
  # faltar (env fabricado/parcial), deriva da raiz de PROJECT_PENDING.
  PROJECT_PREFS_DIR="${PROJECT_PREFS_DIR:-$(dirname "$(dirname "$PROJECT_PENDING")")}"
  export PROJECT_PREFS_DIR

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/evol-apply.XXXXXX")" || { err "sem tmp"; exit "$EX_USAGE"; }
  trap 'rm -rf "$tmp"' RETURN

  # Idempotência: answers já aplicado com o MESMO conteúdo → skip.
  local marker sig
  marker="$SURVEY_DIR/apply.done"
  if [ -f "$answers" ]; then
    sig="$(sha_of "$answers")"
    if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$sig" ]; then
      say_apply "apply: já executado para este answers.json ($sig) — nada a fazer (idempotente)"
      exit "$EX_DONE"
    fi
  else
    sig="<sem answers.json>"
  fi

  # Dump das respostas em TSV (key<TAB>save<TAB>scope) + configs.
  : > "$tmp/ans.tsv"
  : > "$tmp/configs.tsv"
  if [ -f "$answers" ]; then
    case "$JSON_TOOL" in
      jq)
        jq -r '.answers | to_entries[] | "\(.key)\t\(.value.save // "pending")\t\(.value.scope // "")"' "$answers" >> "$tmp/ans.tsv" 2>/dev/null || true
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
        a.write(f"{k}\t{v.get('save','pending')}\t{v.get('scope','')}\n")
    for line in d.get("configs", []):
        c.write(str(line).replace("\t", " ").replace("\n", " ") + "\n")
PYEOF
        ;;
    esac
  fi

  # Propostas em blocos — o MESMO parser do do-prefs.sh (read_candidates
  # espera o formato de candidato: um '---' separando blocos). Chave = campo
  # 'key:' de cada bloco; scope final = resposta do usuário, senão o da proposta.
  local -a yes_project=() yes_global=() pend_project=() pend_global=() discard=()
  local bi bkey bscope save scope line
  if [ -f "$proposals" ]; then
    read_candidates "$proposals"
    for b in "${CANDIDATES[@]}"; do
      bi=$((bi + 1))
      parse_fields "$b"
      bkey="$B_KEY"
      bscope="${B_SCOPE:-project}"
      [ -n "$bkey" ] || { warn_apply "proposta #$bi sem 'key:' ignorada no apply"; continue; }
      save="pending"; scope=""
      while IFS= read -r line; do
        case "$line" in
          "$bkey"*) save=$(printf '%s\n' "$line" | cut -f2); scope=$(printf '%s\n' "$line" | cut -f3) ;;
        esac
      done < "$tmp/ans.tsv"
      case "$save" in
        sim)
          scope="${scope:-$bscope}"
          case "$scope" in
            project) yes_project+=("$b") ;;
            global)  yes_global+=("$b") ;;
            *) scope="$bscope"; case "$scope" in project) yes_project+=("$b") ;; *) yes_global+=("$b") ;; esac ;;
          esac ;;
        nao)
          discard+=("$bkey") ;;
        *)
          # pendente (explícito ou sem resposta): escopo da resposta, senão da proposta
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

  # Monta os arquivos de candidatos aprovados (blocos com o scope FINAL gravado)
  # e os pendentes, e chama o do-prefs.sh.
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
        '> Preferências DESTE projeto, escolhidas pelo usuário no questionário de' \
        '> evolução (FASE 4, passo 6.5). Gitignored. Carregadas no início de cada' \
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

  say_apply ""
  say_apply "apply: $n_saved salva(s) (projeto/global) · $n_disc descartada(s) · $n_pend pendente(s)"
  local k
  for k in ${discard[@]+"${discard[@]}"}; do
    say_apply "  descartada (voto do usuário): $k"
  done
  exit "$EX_DONE"
}

say_apply()  { printf 'EVOLUTION_SURVEY %s\n' "$*"; }
warn_apply() { printf 'EVOLUTION_SURVEY AVISO %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# consultas
# ---------------------------------------------------------------------------
cmd_status() {
  if [ ! -f "$TRAIL" ]; then
    note "QUESTIONÁRIO: nenhum trail em $SURVEY_DIR"
    return 0
  fi
  if command -v column >/dev/null 2>&1; then
    column -t -s "$(printf '\t')" < "$TRAIL"
  else
    cat "$TRAIL"
  fi
}

cmd_feedback() {
  local n f
  n="$(resolve_rev "${1:-}")" || exit "$EX_USAGE"
  f="$SURVEY_DIR/rev-$(rev_pad "$n").feedback.md"
  [ -f "$f" ] || { err "evolution-survey.sh: sem feedback para a rodada $n"; exit "$EX_USAGE"; }
  cat "$f"
}

cmd_doc() {
  local n f
  n="$(resolve_rev "${1:-}")" || exit "$EX_USAGE"
  f="$SURVEY_DIR/rev-$(rev_pad "$n").md"
  [ -f "$f" ] || { err "evolution-survey.sh: sem snapshot para a rodada $n"; exit "$EX_USAGE"; }
  printf '%s\n' "$f"
}

cmd_title() {
  [ -f "$TITLE_FILE" ] || { err "evolution-survey.sh: nenhum título travado ainda"; exit "$EX_USAGE"; }
  cat "$TITLE_FILE"
}

usage() {
  sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  round)    shift; cmd_round "$@" ;;
  answers)  shift; cmd_answers "$@" ;;
  apply)    shift; cmd_apply "$@" ;;
  status)   shift; cmd_status "$@" ;;
  feedback) shift; cmd_feedback "$@" ;;
  doc)      shift; cmd_doc "$@" ;;
  title)    shift; cmd_title "$@" ;;
  -h|--help|help) usage; exit 0 ;;
  '')       usage >&2; exit "$EX_USAGE" ;;
  *)        err "evolution-survey.sh: subcomando desconhecido: $1"; usage >&2; exit "$EX_USAGE" ;;
esac
