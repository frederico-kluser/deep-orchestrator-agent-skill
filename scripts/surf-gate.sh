#!/usr/bin/env bash
# =============================================================================
# surf-gate.sh — PORTÃO DA SURF (R7) e protocolo PESQUISA-FALHOU, determinísticos
# -----------------------------------------------------------------------------
# A pesquisa web do deep-orchestrator é EXCLUSIVAMENTE a surf-agent-skill v9+
# (Brave-only, sem fallback). Este script é o ÚNICO lugar que interpreta o
# estado dela — o SKILL.md só lê as linhas `CHAVE=valor` que saem daqui.
# NUNCA gasta crédito de busca, salvo `resume --probe` (1 crédito, explícito).
# NUNCA lê ~/.config/surf/keys.json nem roda `keys list --json`.
#
# Uso (com o ENV_FILE da FASE 0 sourceado quando houver — $DO_STATE vem dele):
#   surf-gate.sh [gate]
#       Portão FAIL-CLOSED. Sem os binários no PATH => SURF_GATE=127. Senão roda
#       `surf-research-skill gate` (grátis) e QUALQUER saída != 0 conta como 78.
#       Imprime `SURF_GATE=<0|78|127>`; quando != 0 também
#       `SURF_CODE=<BraveKeyMissing|BraveKeyBurned|BraveKeyCooling|
#       BraveKeyInvalid|BraveKeyUnverified|BraveKeyUnproven|BraveKeyUnknown|
#       NotInstalled>` e a mensagem do portão VERBATIM (nunca uma chave).
#       Com $DO_STATE/search-mode presente (o usuário escolheu [3] — ver
#       `choose`) imprime TAMBÉM a linha `SURF_MODE=no-search`, mesmo com
#       SURF_GATE=0: a decisão vale até o fim da execução, com o portão verde
#       ou não (cota/429 não fecha o portão grátis).
#       Grava a mesma saída em $DO_STATE/surf-gate.last se $DO_STATE existir.
#       SEMPRE exit 0 — o veredito é a linha SURF_GATE=, não o exit code.
#   surf-gate.sh classify <exit> <stdout-file> <stderr-file>
#       Classifica UMA chamada surf já feita. Imprime UM de:
#       OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78 | KILLED_143 |
#       USAGE_2. Cota/429/402 NÃO sai como 78 no surf: sai exit 1 (0 fontes) —
#       por isso a classificação lê os arquivos, com padrões ANCORADOS e SEM
#       os ecos da pergunta/query (título multi-linha, crases, listas "Planned
#       and never run"/"Open points", chaves do --json, aspas do progresso): uma
#       QUERY contendo "429", "quota" ou "billing required" não vira
#       FAILED_QUOTA. Roda sob LC_ALL=C (byte inválido não vira EMPTY).
#   surf-gate.sh pause <onda> "<sub-tarefas bloqueadas>" "<motivo>"
#       Grava $DO_STATE/search-pause.md (onda, sub-tarefas, SURF_GATE/SURF_CODE,
#       mensagem verbatim, data) e imprime o BLOCO DA PERGUNTA pronto para
#       colar como ÚLTIMA coisa da resposta (o orquestrador ENCERRA o turno).
#   surf-gate.sh resume [--probe]
#       Reroda o portão. `--probe` faz UMA busca real barata (1 crédito — a
#       sonda grátis não enxerga cota) e classifica. Imprime `RESUME=OK` (e
#       apaga search-pause.md) ou `RESUME=STILL_BLOCKED` + mensagem. O bloco da
#       pergunta só é repetido (e o search-pause.md regravado) quando JÁ existe
#       uma pausa; sem pausa prévia (sonda do gatilho g3) sai só o veredito +
#       mensagem + `NEXT=` — nada é gravado. SEMPRE exit 0 — o veredito é a
#       linha RESUME=.
#   surf-gate.sh choose no-search|search
#       A escolha [3] do usuário vira ESTADO. `choose no-search` grava
#       $DO_STATE/search-mode (= no-search), apaga o search-pause.md e imprime
#       `SURF_MODE=no-search`; daí em diante `gate`/`resume` imprimem essa linha.
#       `choose search` apaga o arquivo (volta a pesquisar) e imprime
#       `SURF_MODE=search`. Sem $DO_STATE nada é gravado: exit 2.
#   surf-gate.sh -h | --help
#
# Exit codes: 0 = rodou (leia o veredito na saída) · 2 = erro de uso, ou
#   estado NÃO gravado por falta de $DO_STATE (pause/choose).
# FIM-DO-CABECALHO
# =============================================================================

set -u

SELF="surf-gate.sh"
PROBE_QUERY="brave search api"

err() { printf '%s\n' "$*" >&2; }
die_usage() { err "$SELF: $*"; err "Uso: $SELF [gate] | classify <exit> <stdout-file> <stderr-file> | pause <onda> \"<sub-tarefas>\" \"<motivo>\" | resume [--probe] | choose no-search|search"; exit 2; }

# Cinto de segurança: a mensagem do portão é repassada VERBATIM, mas uma chave
# NUNCA pode ir para o transcript — mascara qualquer token com cara de chave
# Brave (BSA + 16 ou mais caracteres) que o provedor tenha citado no erro.
# LC_ALL=C: sob locale UTF-8 o sed BSD ABORTA em byte inválido ("illegal byte
# sequence") e a mensagem sumiria; os padrões daqui são todos ASCII.
scrub() { LC_ALL=C sed -e 's/BSA[A-Za-z0-9_-]\{16,\}/BSA***[chave-mascarada]/g'; }

# --- modo de pesquisa da execução (SG-1) ---------------------------------------
# $DO_STATE/search-mode PRESENTE = o usuário escolheu [3] (seguir SEM pesquisa).
# A decisão é ESTADO em disco, não uma linha de prosa: cota/429 deixa o portão
# grátis VERDE, então o veredito SURF_GATE= sozinho não a carrega.
is_no_search() { [ -n "${DO_STATE:-}" ] && [ -f "$DO_STATE/search-mode" ]; }

# --- portão -------------------------------------------------------------------
# Popula G_RC (0|78|127), G_CODE e G_MSG. Nunca falha.
G_RC=0; G_CODE=""; G_MSG=""
run_gate() {
  local missing="" b rc
  G_RC=0; G_CODE=""; G_MSG=""
  for b in surf-research-skill surf-search-normal; do
    command -v "$b" >/dev/null 2>&1 || missing="$missing $b"
  done
  if [ -n "$missing" ]; then
    G_RC=127; G_CODE="NotInstalled"
    G_MSG="surf-agent-skill v9+ não está instalada (faltam no PATH:$missing).
Fix: npm i -g surf-agent-skill   (o orquestrador NUNCA instala sozinho — R9)"
    return 0
  fi
  # rc ANTES do scrub: dentro de $(a | b) o PIPESTATUS não chega aqui.
  G_MSG="$(surf-research-skill gate 2>&1)"; rc=$?
  G_MSG="$(printf '%s\n' "$G_MSG" | scrub)"
  if [ "$rc" -ne 0 ]; then
    # FAIL-CLOSED: 1, 2, sinal, exceção — qualquer != 0 conta como 78.
    G_RC=78
    G_CODE="$(printf '%s\n' "$G_MSG" | LC_ALL=C sed -n 's/.*Error \[\(BraveKey[A-Za-z]*\)\].*/\1/p' | head -n 1)"
    [ -n "$G_CODE" ] || G_CODE="BraveKeyUnknown"
    [ -n "$G_MSG" ] || G_MSG="(o portão saiu $rc sem mensagem)"
  fi
  return 0
}

# As linhas CHAVE=valor saem JUNTAS, antes da mensagem (que vai até o fim).
print_verdict() {
  printf 'SURF_GATE=%s\n' "$G_RC"
  [ "$G_RC" -ne 0 ] && printf 'SURF_CODE=%s\n' "$G_CODE"
  is_no_search && printf 'SURF_MODE=no-search\n'
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
  print_gate > "$DO_STATE/surf-gate.last" 2>/dev/null || true
}

cmd_gate() {
  run_gate
  print_gate
  save_gate
  exit 0
}

# --- classify -----------------------------------------------------------------
# Padrões ANCORADOS nos textos REAIS do surf 8.x (src/lib/dispatch.mjs,
# src/lib/providers/brave.mjs, src/lib/ai/orchestrator.mjs). Nada de ' 429' ou
# 'QUOTA' soltos: a query ecoada no relatório casaria.
PAT_QUOTA='brave#[0-9]+: 429|monthly quota exhausted|(SUBSCRIPTION_)?QUOTA_EXCEEDED|billing required|AllKeysExhausted.*429'
PAT_OTHER='AllKeysExhausted|NoProviderAvailable|LikelyAgentTimeout|Every search failed'

# Tira do texto os lugares onde o surf 8.x ECOA a pergunta/query ou texto
# escrito por LLM (src/lib/ai/orchestrator.mjs, render.mjs, progress.mjs). O
# erro real fica sempre FORA desses trechos:
#   1. título `# <pergunta>` — MULTI-LINHA: vai até o próximo `## `. Sem `## `
#      até o fim do arquivo o formato não é o esperado: as linhas seguintes
#      VOLTAM para a análise (fail-closed — erro real nunca some por isso);
#   2. listas "Planned and never run:" e "**Open points recorded by the
#      analyst:**" (queries/pontos SEM crases), até a linha vazia;
#   3. tabela "| Rejected candidate | Why |";
#   4. cabeçalho de batch `## [n/m] <query>` e rodapé `_Stopped because: ..._`;
#   5. --json (pretty): de linha COM chave só ficam as chaves de erro
#      (code/message/error/errors/detail) — "query", "answer", "rationale",
#      "sub_questions"... saem; elemento-string de array também sai;
#   6. progresso no stderr (`[surf HH:MM:SS] ▸ [1/2] "<query>"`): tira as ASPAS;
#   7. trechos entre crases (`- \`<query>\` — <erro real>`).
# awk (e não sed): o bloco do título precisa de estado. LC_ALL=C: bytes, nunca
# "illegal byte sequence"; os padrões são ASCII.
strip_echo() { # <arquivo>
  LC_ALL=C awk '
    function emit(line) {
      if (blk) { if (line ~ /^[ \t]*$/) blk = 0; return }
      if (line ~ /^Planned and never run:/ || line ~ /^\*\*Open points recorded by the analyst:\*\*/) { blk = 1; return }
      if (tbl) { if (line ~ /^\|/) return; tbl = 0 }
      if (line ~ /^\| Rejected candidate \|/) { tbl = 1; return }
      if (line ~ /^## \[[0-9]+\/[0-9]+\] / || line ~ /^_Stopped because: /) return
      if (line ~ /^[ \t]*"[^"]*"[ \t]*:/) {
        if (line !~ /^[ \t]*"(code|message|error|errors|detail)"[ \t]*:/) return
      } else if (line ~ /^[ \t]*".*",?[ \t]*$/) return
      if (line ~ /^\[surf [0-9:]+\] /) gsub(/"[^"]*"/, "", line)
      gsub(/`[^`]*`/, "", line)
      print line
    }
    {
      if (title) {
        if ($0 ~ /^## /) { title = 0; nt = 0 }   # fim do bloco: o eco é descartado
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
    78)  printf 'BLOCKED_78\n'; return 0 ;;
    143) printf 'KILLED_143\n'; return 0 ;;
    2)   printf 'USAGE_2\n'; return 0 ;;
  esac
  for f in "$2" "$3"; do
    [ -f "$f" ] || continue
    # Filtro falhou => arquivo CRU (fail-closed: prefere falso FAILED_* a
    # engolir uma cota como EMPTY).
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
  printf 'Portão: SURF_GATE=%s%s\n' "$G_RC" "$([ -n "$G_CODE" ] && printf ' SURF_CODE=%s' "$G_CODE")"
  if [ -n "$G_MSG" ] && [ "$G_RC" -ne 0 ]; then
    printf '%s\n' "----- MENSAGEM DO PORTÃO (VERBATIM) -----"
    printf '%s\n' "$G_MSG"
    printf '%s\n' "-----------------------------------------"
  else
    printf '%s\n' "(o portão grátis está verde — ele NÃO enxerga cota/429; a falha veio das buscas reais)"
  fi
  printf '%s\n' "Responda com o NÚMERO da opção:"
  printf '%s\n' "  [1] Adicionei/troquei a chave Brave — tente de novo  (\`surf-research-skill keys add --provider brave <CHAVE>\` | terminal separado: \`surf add\`)"
  printf '%s\n' "  [2] Ajustei o plano/cota ou esperei o cooldown — tente de novo  (\`surf-research-skill keys reset --provider brave\` limpa burn/cooldown em cache)"
  printf '%s\n' "  [3] Seguir SEM pesquisa — premissas ficam marcadas NÃO VERIFICADAS no plano, handoffs e relatório"
  printf '%s\n' "  [4] Abortar — fecho o que está aberto (purge) e entrego relatório parcial"
  printf '%s\n' "Rode os comandos no SEU terminal e NÃO cole a chave no chat (iria para o transcript). \`surf\` e \`surf add\` exigem TTY."
  printf '%s\n' "Outros: remover chave morta \`surf remove brave <i>\` · revalidar \`surf validate brave\` · painel de cota https://api-dashboard.search.brave.com"
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
    printf -- '- SURF_GATE: %s\n' "$G_RC"
    printf -- '- SURF_CODE: %s\n' "${G_CODE:--}"
    printf '\n## Mensagem do portão (VERBATIM)\n\n'
    printf '%s\n' "${G_MSG:-(portão verde — sem mensagem)}"
    printf '\n## Retomada\n\n'
    printf '%s\n' "FASE 0 (ESTADOS PENDENTES) acha este arquivo. [1]/[2] => \"\$DO_SURF_GATE\" resume --probe;"
    printf '%s\n' "RESUME=OK => re-delegar as bloqueadas NA MESMA worktree; STILL_BLOCKED => repetir a pergunta."
    printf '%s\n' "[3] => \"\$DO_SURF_GATE\" choose no-search (vira SURF_MODE=no-search até o fim da execução) +"
    printf '%s\n' "re-delegar com SURF_STATUS=\"NAO PESQUISE\"; [4] => purge + relatório parcial."
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

# Normaliza um argumento para UMA linha (o arquivo é lido por linha na retomada).
one_line() { printf '%s' "$1" | tr '\n\r\t' '   '; }

cmd_pause() {
  [ $# -eq 3 ] || die_usage "pause exige <onda> \"<sub-tarefas bloqueadas>\" \"<motivo>\""
  local onda subs motivo
  onda="$(one_line "$1")"; subs="$(one_line "$2")"; motivo="$(one_line "$3")"
  # A pausa não é recusada (a pergunta SEMPRE sai), mas sob no-search ela é engano.
  is_no_search && err "$SELF: AVISO — SURF_MODE=no-search: o usuário JÁ escolheu [3] nesta execução. NÃO pergunte de novo: re-delegue com NÃO PESQUISE (só rode '$SELF choose search' se ELE pediu para voltar a pesquisar)."
  run_gate
  save_gate
  if write_pause "$onda" "$subs" "$motivo"; then
    printf 'PAUSE_FILE=%s\n' "$DO_STATE/search-pause.md"
    print_question "$onda" "$subs" "$motivo"
    exit 0
  fi
  # Sem estado em disco a retomada não se acha — mas a PERGUNTA sai de qualquer jeito.
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
    # UMA busca real barata (1 crédito): só ela enxerga cota esgotada/429/402.
    t="$(mktemp -d 2>/dev/null)" || t=""
    if [ -n "$t" ]; then
      surf-research-skill search "$PROBE_QUERY" --max 1 --no-cache --quiet >"$t/out" 2>"$t/err"
      prc=$?
      pclass="$(classify_files "$prc" "$t/out" "$t/err")"
      pmsg="$(scrub < "$t/err" | head -n 12)"
      rm -rf "$t"
    else
      pclass="FAILED_OTHER"; pmsg="(mktemp falhou — sonda não rodou)"
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
  # SEM pausa prévia (sonda do gatilho g3, ou resume avulso): só veredito +
  # mensagem. NADA é gravado e a pergunta NÃO sai — ela sairia com campos "-" e
  # o orquestrador a colaria pulando o `pause` (estado sem onda/sub-tarefas).
  if ! { [ -n "${DO_STATE:-}" ] && [ -f "$DO_STATE/search-pause.md" ]; }; then
    print_gate_msg
    [ -n "$pmsg" ] && { printf '%s\n' "----- SAÍDA DA SONDA (stderr) -----"; printf '%s\n' "$pmsg"; }
    printf '%s\n' "NEXT=nenhuma pausa gravada — para pausar, execute o protocolo PESQUISA-FALHOU: \"\$DO_SURF_GATE\" pause <onda> \"<sub-tarefas bloqueadas>\" \"<motivo>\""
    exit 0
  fi
  local onda subs motivo
  onda="$(pause_field onda)"; subs="$(pause_field 'sub-tarefas bloqueadas')"; motivo="$(pause_field motivo)"
  [ -n "$onda" ] || onda="-"
  [ -n "$subs" ] || subs="-"
  [ -n "$motivo" ] || motivo="-"
  if [ -n "$pclass" ]; then
    motivo="${motivo%% | sonda real:*} | sonda real: $pclass"   # sem acumular a cada retomada
    [ -n "$pmsg" ] && { printf '%s\n' "----- SAÍDA DA SONDA (stderr) -----"; printf '%s\n' "$pmsg"; }
  fi
  # Mantém o estado em disco atualizado (veredito novo) e repete a pergunta.
  write_pause "$onda" "$subs" "$(one_line "$motivo")" || true
  print_question "$onda" "$subs" "$motivo"
  exit 0
}

# --- choose: a opção [3] vira estado (SG-1) -----------------------------------
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
    printf 'SURF_MODE=search\n'
    exit 0
  fi
  tmp="$f.tmp.$$"
  mkdir -p "$DO_STATE" 2>/dev/null \
    && printf 'no-search\n' > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; err "$SELF: AVISO — não gravei $f (DO_STATE sem escrita). A escolha NÃO foi gravada."; exit 2; }
  # A pergunta foi respondida: a pausa acabou (a FASE 0 não pode reencontrá-la).
  rm -f "$DO_STATE/search-pause.md" 2>/dev/null
  printf 'SURF_MODE=no-search\n'
  printf 'MODE_FILE=%s\n' "$f"
  exit 0
}

case "${1:-gate}" in
  gate)      [ $# -le 1 ] || die_usage "gate não recebe argumentos"; cmd_gate ;;
  classify)  shift; cmd_classify "$@" ;;
  pause)     shift; cmd_pause "$@" ;;
  resume)    shift; cmd_resume "$@" ;;
  choose)    shift; cmd_choose "$@" ;;
  -h|--help|help) sed -n '2,/FIM-DO-CABECALHO/p' "$0" | sed -e '/FIM-DO-CABECALHO/d' -e 's/^# \{0,1\}//'; exit 0 ;;
  *)         die_usage "subcomando desconhecido: $1" ;;
esac
