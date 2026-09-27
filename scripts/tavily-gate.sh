#!/usr/bin/env bash
# =============================================================================
# tavily-gate.sh — PORTÃO DA PESQUISA (R7) e protocolo PESQUISA-FALHOU, determinísticos
# -----------------------------------------------------------------------------
# A pesquisa web do deep-orchestrator é EXCLUSIVAMENTE a tavily-agent-skill
# (API Tavily, rotação de chaves própria dela). Este script é o ÚNICO lugar que
# interpreta o estado dela — o SKILL.md só lê as linhas `CHAVE=valor` daqui.
# NUNCA gasta crédito de busca: `gate`/`premise` usam `tavily.py status` (e
# `status --check` para validação ao vivo via /usage, que NÃO consome créditos).
# NUNCA lê keys.json nem imprime material de chave (scrub em toda a saída).
#
# PREMISSA DE TRABALHO (v6.0.0): a skill está presente E há ≥1 chave Tavily
# VÁLIDA. Sem isso a execução NÃO começa: o orquestrador roda `premise`, e com
# TAVILY_PREMISE != ok ele PAUSA e pede uma chave ao usuário (bloco
# PREMISSA-KEY) e só segue depois de `keys add` + revalidação OK.
#
# Uso (com o ENV_FILE da FASE 0 sourceado quando houver — $DO_STATE vem dele):
#   tavily-gate.sh [gate]
#       Portão FAIL-CLOSED. Sem a skill instalada => TAVILY_GATE=127. Sem chave
#       ativa => 78. Com ≥1 chave ativa => 0. Imprime `TAVILY_GATE=<0|78|127>`;
#       quando != 0 também `TAVILY_CODE=<TavilySkillMissing|TavilyKeyMissing|
#       TavilyQuotaExhausted|TavilyAllBanned|TavilyUnknown>` e a mensagem
#       VERBATIM (nunca uma chave). Com $DO_STATE/search-mode presente (o
#       usuário escolheu [3]) imprime TAMBÉM `SEARCH_MODE=no-search`, mesmo com
#       TAVILY_GATE=0. Grava a mesma saída em $DO_STATE/tavily-gate.last se
#       $DO_STATE existir. SEMPRE exit 0 — o veredito é a linha TAVILY_GATE=.
#   tavily-gate.sh premise
#       A premissa de trabalho: skill presente + chave registrada + chave
#       VÁLIDA ao vivo (`tavily.py status --check`, sem créditos). Imprime o
#       veredito do gate e `TAVILY_PREMISE=ok|skill-missing|key-missing|
#       key-invalid|unknown` + `NEXT=<instrução>`. Exit 0 sempre.
#   tavily-gate.sh classify <exit> <stdout-file> <stderr-file>
#       Classifica UMA chamada de busca já feita. Imprime UM de:
#       OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_NOKEY | KILLED_143 |
#       USAGE_2. Padrões ANCORADOS nos textos REAIS da tavily-agent-skill
#       (mensagens "Erro: … / Solução: …", 429/432/401, AllKeysExhausted) e SEM
#       os ecos da pergunta/query (crases, --json, títulos multi-linha): uma
#       QUERY contendo "429" ou "quota" não vira FAILED_QUOTA. LC_ALL=C.
#   tavily-gate.sh pause <onda> "<sub-tarefas bloqueadas>" "<motivo>"
#       Grava $DO_STATE/search-pause.md (onda, sub-tarefas, TAVILY_GATE/
#       TAVILY_CODE, mensagem verbatim, data) e imprime o BLOCO DA PERGUNTA
#       pronto para colar como ÚLTIMA coisa da resposta (o orquestrador ENCERRA
#       o turno).
#   tavily-gate.sh resume [--probe]
#       Reroda o portão. `--probe` faz UMA busca real barata (1 crédito) e
#       classifica. Imprime `RESUME=OK` (e apaga search-pause.md) ou
#       `RESUME=STILL_BLOCKED` + mensagem. Sem pausa prévia sai só o veredito +
#       `NEXT=` — nada é gravado. SEMPRE exit 0.
#   tavily-gate.sh choose no-search|search
#       A escolha [3] do usuário vira ESTADO: grava/apaga $DO_STATE/search-mode
#       e imprime `SEARCH_MODE=no-search|search`. Sem $DO_STATE: exit 2.
#   tavily-gate.sh -h | --help
#
# Exit codes: 0 = rodou (leia o veredito na saída) · 2 = erro de uso, ou
#   estado NÃO gravado por falta de $DO_STATE (pause/choose).
# FIM-DO-CABECALHO
# =============================================================================

set -u

SELF="tavily-gate.sh"
PROBE_QUERY="tavily search api"

err() { printf '%s\n' "$*" >&2; }
die_usage() { err "$SELF: $*"; err "Uso: $SELF [gate] | premise | classify <exit> <stdout-file> <stderr-file> | pause <onda> \"<sub-tarefas>\" \"<motivo>\" | resume [--probe] | choose no-search|search"; exit 2; }

# Cinto de segurança: a mensagem do portão é repassada VERBATIM, mas uma chave
# NUNCA pode ir para o transcript — mascara qualquer token com cara de chave
# Tavily (tvly- + 8 ou mais caracteres) e ecos de keys.json.
# LC_ALL=C: sob locale UTF-8 o sed BSD ABORTA em byte inválido; padrões ASCII.
scrub() { LC_ALL=C sed -e 's/tvly-[A-Za-z0-9_-]\{8,\}/tvly***[chave-mascarada]/g'; }

# --- resolver a tavily-agent-skill (PREMISSA) --------------------------------
# $TAVILY_HOME (testes/fixtures) vence; senão varre as skill roots conhecidas.
resolve_tavily() { # imprime o dir da skill ou nada
  local d
  if [ -n "${TAVILY_HOME:-}" ]; then
    [ -f "$TAVILY_HOME/scripts/tavily.py" ] && { printf '%s\n' "$TAVILY_HOME"; return 0; }
    return 0
  fi
  for d in "$HOME/.agents/skills/tavily-agent-skill" \
           "$HOME/.claude/skills/tavily-agent-skill" \
           "$HOME/.dsh/skills/tavily-agent-skill" \
           "$HOME/.jcode/skills/tavily-agent-skill" \
           "$HOME/.pi/agent/skills/tavily-agent-skill" \
           "${SKILL_HOME:-}/../tavily-agent-skill"; do
    [ -n "$d" ] && [ -f "$d/scripts/tavily.py" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 0
}

TAVILY_DIR="$(resolve_tavily)"
TAVILY_PY="${TAVILY_DIR:+$TAVILY_DIR/scripts/tavily.py}"
[ -n "${PYTHON:-}" ] || PYTHON="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"

# --- modo de pesquisa da execução ---------------------------------------------
# $DO_STATE/search-mode PRESENTE = o usuário escolheu [3] (seguir SEM pesquisa).
is_no_search() { [ -n "${DO_STATE:-}" ] && [ -f "$DO_STATE/search-mode" ]; }

# --- portão -------------------------------------------------------------------
# Popula G_RC (0|78|127), G_CODE e G_MSG. Nunca falha. FAIL-CLOSED.
G_RC=0; G_CODE=""; G_MSG=""
run_gate() {
  G_RC=0; G_CODE=""; G_MSG=""
  if [ -z "$TAVILY_DIR" ] || [ -z "$PYTHON" ]; then
    G_RC=127; G_CODE="TavilySkillMissing"
    G_MSG="tavily-agent-skill não está instalada (ou falta python3) — PREMISSA de trabalho.
Fix: clone/copie a skill para ~/.agents/skills/tavily-agent-skill e registe uma chave:
  python3 ~/.agents/skills/tavily-agent-skill/scripts/tavily.py keys add \"tvly-...\" --label conta-A
(o orquestrador NUNCA instala sozinho — R9; peça a chave ao usuário e valide antes de iniciar)"
    return 0
  fi
  local st rc actives
  st="$("$PYTHON" "$TAVILY_PY" status 2>&1)"; rc=$?
  st="$(printf '%s\n' "$st" | scrub)"
  if [ "$rc" -ne 0 ]; then
    G_RC=78; G_CODE="TavilyUnknown"
    G_MSG="$st"
    [ -n "$G_MSG" ] || G_MSG="(tavily.py status saiu $rc sem mensagem)"
    return 0
  fi
  actives="$(printf '%s\n' "$st" | LC_ALL=C grep -c '\[ACTIVE\]')"
  if [ "$actives" -ge 1 ]; then
    G_RC=0
    return 0
  fi
  G_RC=78
  if printf '%s\n' "$st" | LC_ALL=C grep -q 'QUOTA_EXHAUSTED'; then
    G_CODE="TavilyQuotaExhausted"
    G_MSG="TODAS as chaves Tavily estão com cota esgotada (QUOTA_EXHAUSTED).
Fix: peça uma chave NOVA ao usuário (tavily.py keys add \"tvly-...\" --label nova) ou aguarde o reset mensal."
  elif printf '%s\n' "$st" | LC_ALL=C grep -q 'BANNED\|FORA DE ROTAÇÃO'; then
    G_CODE="TavilyAllBanned"
    G_MSG="Todas as chaves Tavily estão fora de rotação (ban temporário do pool).
Fix: \"tavily.py keys unban --all\" (readmite) ou registe outra chave; valide com \"tavily.py status --check\"."
  else
    G_CODE="TavilyKeyMissing"
    G_MSG="Nenhuma chave Tavily registrada/ativa — PREMISSA de trabalho.
Peça UMA chave ao usuário (NUNCA cole no chat — registe no terminal dele) e valide:
  python3 \"$TAVILY_PY\" keys add \"tvly-...\" --label conta-A
  python3 \"$TAVILY_PY\" status --check"
  fi
  return 0
}

# As linhas CHAVE=valor saem JUNTAS, antes da mensagem (que vai até o fim).
print_verdict() {
  printf 'TAVILY_GATE=%s\n' "$G_RC"
  [ "$G_RC" -ne 0 ] && printf 'TAVILY_CODE=%s\n' "$G_CODE"
  is_no_search && printf 'SEARCH_MODE=no-search\n'
  return 0
}

print_gate_msg() {
  [ "$G_RC" -ne 0 ] || return 0
  printf '%s\n' "----- MENSAGEM DO PORTÃO (repassar VERBATIM) -----"
  printf '%s\n' "$G_MSG"
}

print_gate() { print_verdict; print_gate_msg; }

save_gate() {
  [ -n "${DO_STATE:-}" ] && [ -d "$DO_STATE" ] || return 0
  print_gate > "$DO_STATE/tavily-gate.last" 2>/dev/null || true
}

cmd_gate() {
  run_gate
  print_gate
  save_gate
  exit 0
}

# --- premise (a premissa de trabalho: validar ANTES de iniciar) ---------------
cmd_premise() {
  run_gate
  save_gate
  print_gate
  case "$G_RC" in
    0)
      # Validação AO VIVO via /usage (NÃO gasta créditos).
      if [ -n "$TAVILY_PY" ] && "$PYTHON" "$TAVILY_PY" status --check >/dev/null 2>&1; then
        printf 'TAVILY_PREMISE=ok\n'
        printf 'NEXT=prossiga: pesquisa liberada (chave validada ao vivo)\n'
      else
        printf 'TAVILY_PREMISE=key-invalid\n'
        printf 'NEXT=as chaves registradas NÃO validaram ao vivo — PEÇA UMA CHAVE AO USUÁRIO (bloco PREMISSA-KEY), rode keys add e revalide: %s premise\n' "$SELF"
      fi
      ;;
    127)
      printf 'TAVILY_PREMISE=skill-missing\n'
      printf 'NEXT=instale a tavily-agent-skill (PREMISSA), peça a chave ao usuário e rode: %s premise\n' "$SELF"
      ;;
    *)
      printf 'TAVILY_PREMISE=key-missing\n'
      printf 'NEXT=PEÇA UMA CHAVE TAVILY AO USUÁRIO (bloco PREMISSA-KEY — nunca aceite chave colada no chat), rode keys add e revalide: %s premise\n' "$SELF"
      ;;
  esac
  exit 0
}

# --- classify -----------------------------------------------------------------
# Padrões ANCORADOS nos textos REAIS da tavily-agent-skill (contrato
# "Erro: … / Solução: …"; 401 chave morta, 429 rate limit, 432 cota,
# AllKeysExhausted). Nada de ' 429' ou 'quota' soltos: a query ecoada casaria.
PAT_QUOTA='HTTP 429|HTTP 432|HTTP 402|rate limit|quota|cota|esgotad|AllKeysExhausted|432 cota|429 rate'
PAT_OTHER='HTTP 401|chave (inválida|morta)|timeout|rede|5[0-9][0-9] |Erro:'

# Tira do texto os lugares onde a busca ECOA a pergunta/query ou texto gerado
# por LLM. O erro real fica sempre FORA desses trechos (mesma filosofia do
# contrato anterior — fail-closed: prefere falso FAILED_* a engolir cota como
# EMPTY). awk para o bloco multi-linha do título; LC_ALL=C para bytes.
strip_echo() { # <arquivo>
  LC_ALL=C awk '
    function emit(line) {
      if (blk) { if (line ~ /^[ \t]*$/) blk = 0; return }
      if (line ~ /^Planned and never run:/ || line ~ /^\*\*Open points recorded by the analyst:\*\*/) { blk = 1; return }
      if (tbl) { if (line ~ /^\|/) return; tbl = 0 }
      if (line ~ /^\| Rejected candidate \|/) { tbl = 1; return }
      if (line ~ /^## \[[0-9]+\/[0-9]+\] / || line ~ /^_Stopped because: /) return
      if (line ~ /^[ \t]*"[^"]*"[ \t]*:/) {
        if (line !~ /^[ \t]*"(code|message|error|errors|detail|answer|query)"[ \t]*:/) return
      } else if (line ~ /^[ \t]*".*",?[ \t]*$/) return
      gsub(/`[^`]*`/, "", line)
      print line
    }
    {
      if (title) {
        if ($0 ~ /^## /) { title = 0; nt = 0 }
        else { tb[++nt] = $0; next }
      }
      if ($0 ~ /^# /) { title = 1; nt = 0; next }
      emit($0)
    }
    END { if (title) for (i = 1; i <= nt; i++) emit(tb[i]) }
  ' "$1"
}

classify_files() { # <exit> <stdout-file> <stderr-file> → imprime a classe
  local ex="$1" f text="" part
  case "$ex" in
    0)   printf 'OK\n'; return 0 ;;
    78)  printf 'BLOCKED_NOKEY\n'; return 0 ;;
    143) printf 'KILLED_143\n'; return 0 ;;
    2)   printf 'USAGE_2\n'; return 0 ;;
  esac
  for f in "$2" "$3"; do
    [ -f "$f" ] || continue
    part="$(strip_echo "$f" 2>/dev/null)" || part="$(cat "$f" 2>/dev/null)"
    text="$text
$part"
  done
  if printf '%s\n' "$text" | LC_ALL=C grep -Eq -- "$PAT_QUOTA"; then
    printf 'FAILED_QUOTA\n'
  elif printf '%s\n' "$text" | LC_ALL=C grep -Eq -- "$PAT_OTHER"; then
    printf 'FAILED_OTHER\n'
  elif [ "$ex" -eq 1 ]; then
    printf 'EMPTY\n'   # rodou e não recuperou nada — degradação legítima
  else
    printf 'FAILED_OTHER\n'   # exit desconhecido: fail-closed, nunca "vazio"
  fi
}

cmd_classify() {
  [ $# -eq 3 ] || die_usage "classify exige <exit> <stdout-file> <stderr-file>"
  case "$1" in ''|*[!0-9]*) die_usage "classify: <exit> precisa ser inteiro (obtido: '$1')" ;; esac
  classify_files "$1" "$2" "$3"
  exit 0
}

# --- bloco da pergunta + estado da pausa --------------------------------------
# Texto FIXO (protocolo PESQUISA-FALHOU, passo D). Vale com ou sem do-question e
# VENCE "não me pergunte nada"/autônomo/no-stop/plan=off.
print_question() { # <onda> <sub-tarefas> <motivo>
  printf '%s\n' "===== PESQUISA-FALHOU — a pesquisa exigida não pôde ser feita; a decisão é SUA ====="
  printf 'Onda: %s\n' "$1"
  printf 'Sub-tarefas bloqueadas: %s\n' "$2"
  printf 'Motivo: %s\n' "$3"
  printf 'Portão: TAVILY_GATE=%s%s\n' "$G_RC" "$([ -n "$G_CODE" ] && printf ' TAVILY_CODE=%s' "$G_CODE")"
  if [ -n "$G_MSG" ] && [ "$G_RC" -ne 0 ]; then
    printf '%s\n' "----- MENSAGEM DO PORTÃO (VERBATIM) -----"
    printf '%s\n' "$G_MSG"
    printf '%s\n' "-----------------------------------------"
  else
    printf '%s\n' "(o portão está verde — a falha veio das buscas reais)"
  fi
  printf '%s\n' "Responda com o NÚMERO da opção:"
  printf '%s\n' "  [1] Registrei uma chave Tavily nova — tente de novo  (\`python3 <tavily-agent-skill>/scripts/tavily.py keys add \"<CHAVE>\" --label conta-N\`)"
  printf '%s\n' "  [2] Readmiti/recarreguei as chaves ou esperei o cooldown — tente de novo  (\`tavily.py keys unban --all\` | \`tavily.py status --check\`)"
  printf '%s\n' "  [3] Seguir SEM pesquisa — premissas ficam marcadas NÃO VERIFICADAS no plano, handoffs e relatório"
  printf '%s\n' "  [4] Abortar — fecho o que está aberto (purge) e entrego relatório parcial"
  printf '%s\n' "Rode os comandos no SEU terminal e NÃO cole a chave no chat (iria para o transcript). \`keys add\` exige TTY."
  printf '%s\n' "Outros: remover chave morta \`tavily.py keys remove <seletor>\` · ver o pool \`tavily.py status\` · próxima da rotação \`tavily.py keys next\`"
}

write_pause() { # <onda> <sub-tarefas> <motivo> → grava search-pause.md; rc 1 se não gravou
  [ -n "${DO_STATE:-}" ] || return 1
  mkdir -p "$DO_STATE" 2>/dev/null || return 1
  local f="$DO_STATE/search-pause.md" tmp
  tmp="$f.tmp.$$"
  {
    printf '# PESQUISA-FALHOU — pausa aguardando o usuário\n\n'
    printf -- '- data: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '- run: %s\n' "${RUN_ID:--}"
    printf -- '- onda: %s\n' "$1"
    printf -- '- sub-tarefas bloqueadas: %s\n' "$2"
    printf -- '- motivo: %s\n' "$3"
    printf -- '- TAVILY_GATE: %s\n' "$G_RC"
    printf -- '- TAVILY_CODE: %s\n' "${G_CODE:--}"
    printf '\n## Mensagem do portão (VERBATIM)\n\n'
    printf '%s\n' "${G_MSG:-(portão verde — sem mensagem)}"
    printf '\n## Retomada\n\n'
    printf '%s\n' "FASE 0 (ESTADOS PENDENTES) acha este arquivo. [1]/[2] => \"\$DO_TAVILY_GATE\" resume --probe;"
    printf '%s\n' "RESUME=OK => re-delegar as bloqueadas NA MESMA worktree; STILL_BLOCKED => repetir a pergunta."
    printf '%s\n' "[3] => \"\$DO_TAVILY_GATE\" choose no-search (vira SEARCH_MODE=no-search até o fim da execução) +"
    printf '%s\n' "re-delegar com SEARCH_STATUS=\"NAO PESQUISE\"; [4] => purge + relatório parcial."
    printf '\n## Pergunta feita ao usuário\n\n'
    print_question "$1" "$2" "$3"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}
# Um campo `- <nome>: <valor>` do search-pause.md (vazio se ausente).
pause_field() { # <nome>
  [ -n "${DO_STATE:-}" ] && [ -f "$DO_STATE/search-pause.md" ] || return 0
  sed -n "s/^- $1: //p" "$DO_STATE/search-pause.md" | head -n 1
}
one_line() { printf '%s' "$1" | tr '\n\r\t' '   '; }
cmd_pause() {
  [ $# -eq 3 ] || die_usage "pause exige <onda> \"<sub-tarefas bloqueadas>\" \"<motivo>\""
  local onda subs motivo
  onda="$(one_line "$1")"; subs="$(one_line "$2")"; motivo="$(one_line "$3")"
  is_no_search && err "$SELF: AVISO — SEARCH_MODE=no-search: o usuário JÁ escolheu [3] nesta execução. NÃO pergunte de novo: re-delegue com NÃO PESQUISE (só rode '$SELF choose search' se ELE pediu para voltar a pesquisar)."
  run_gate
  save_gate
  if write_pause "$onda" "$subs" "$motivo"; then
    printf 'PAUSE_FILE=%s\n' "$DO_STATE/search-pause.md"
    print_question "$onda" "$subs" "$motivo"
    exit 0
  fi
  err "$SELF: AVISO — não gravei search-pause.md (DO_STATE='${DO_STATE:-}' ausente/sem escrita). Sourceie o ENV_FILE e rode de novo."
  printf 'PAUSE_FILE=\n'
  print_question "$onda" "$subs" "$motivo"
  exit 2
}
cmd_resume() {
  local probe=0 a
  for a in "$@"; do
    case "$a" in
      --probe) probe=1 ;;
      *) die_usage "resume: argumento desconhecido: $a" ;;
    esac
  done
  local blocked=0 pclass="" pmsg="" t prc
  run_gate
  save_gate
  print_verdict
  if [ "$G_RC" -ne 0 ]; then
    blocked=1
  elif [ "$probe" -eq 1 ]; then
    # UMA busca real barata (1 crédito): só ela enxerga cota esgotada em runtime.
    t="$(mktemp -d 2>/dev/null)" || t=""
    if [ -n "$t" ] && [ -n "$TAVILY_PY" ]; then
      "$PYTHON" "$TAVILY_PY" search "$PROBE_QUERY" --max-results 1 --timeout 15 >"$t/out" 2>"$t/err"
      prc=$?
      pclass="$(classify_files "$prc" "$t/out" "$t/err")"
      pmsg="$(scrub < "$t/err" | head -n 12)"
      rm -rf "$t"
    else
      pclass="FAILED_OTHER"; pmsg="(sem tavily.py ou mktemp falhou — sonda não rodou)"
    fi
    printf 'PROBE=%s\n' "$pclass"
    [ "$pclass" = "OK" ] || blocked=1
  fi
  if [ "$blocked" -eq 0 ]; then
    [ -n "${DO_STATE:-}" ] && rm -f "$DO_STATE/search-pause.md" 2>/dev/null
    printf 'RESUME=OK\n'
    exit 0
  fi
  printf 'RESUME=STILL_BLOCKED\n'
  if ! { [ -n "${DO_STATE:-}" ] && [ -f "$DO_STATE/search-pause.md" ]; }; then
    print_gate_msg
    [ -n "$pmsg" ] && { printf '%s\n' "----- SAÍDA DA SONDA (stderr) -----"; printf '%s\n' "$pmsg"; }
    printf '%s\n' "NEXT=nenhuma pausa gravada — para pausar, execute o protocolo PESQUISA-FALHOU: \"\$DO_TAVILY_GATE\" pause <onda> \"<sub-tarefas bloqueadas>\" \"<motivo>\""
    exit 0
  fi
  print_question "$(pause_field onda)" "$(pause_field 'sub-tarefas bloqueadas')" "$(pause_field motivo)"
  exit 0
}
cmd_choose() {
  [ $# -eq 1 ] || die_usage "choose exige no-search|search"
  case "$1" in
    no-search|search) : ;;
    *) die_usage "choose: valor desconhecido: '$1' (use no-search|search)" ;;
  esac
  if [ -z "${DO_STATE:-}" ]; then
    err "$SELF: AVISO — DO_STATE ausente: a escolha NÃO foi gravada. Sourceie o ENV_FILE e rode de novo."
    exit 2
  fi
  local f="$DO_STATE/search-mode" tmp
  if [ "$1" = "search" ]; then
    rm -f "$f" 2>/dev/null
    [ ! -e "$f" ] || { err "$SELF: não consegui apagar $f"; exit 2; }
    printf 'SEARCH_MODE=search\n'
    exit 0
  fi
  tmp="$f.tmp.$$"
  mkdir -p "$DO_STATE" 2>/dev/null \
    && printf 'no-search\n' > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; err "$SELF: AVISO — não gravei $f (DO_STATE sem escrita). A escolha NÃO foi gravada."; exit 2; }
  rm -f "$DO_STATE/search-pause.md" 2>/dev/null
  printf 'SEARCH_MODE=no-search\n'
  printf 'MODE_FILE=%s\n' "$f"
  exit 0
}

case "${1:-}" in
  ""|-h|--help) sed -n '2,/^# ====*$/p' "$0" | sed '/^# FIM-DO-CABECALHO$/d'; exit 0 ;;
  gate)         shift; cmd_gate "$@" ;;
  premise)      shift; cmd_premise "$@" ;;
  classify)     shift; cmd_classify "$@" ;;
  pause)        shift; cmd_pause "$@" ;;
  resume)       shift; cmd_resume "$@" ;;
  choose)       shift; cmd_choose "$@" ;;
  *)            die_usage "subcomando desconhecido: $1" ;;
esac
