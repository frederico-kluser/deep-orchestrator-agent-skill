#!/usr/bin/env bash
# =============================================================================
# plan-approval.sh — o PORTÃO DE APROVAÇÃO DO PLANO (FASE 2.5) via Plannotator
# -----------------------------------------------------------------------------
# O orquestrador NÃO conversa com o Plannotator na mão. Toda rodada de revisão
# passa por aqui, porque cada rodada tem cinco invariantes que um comando solto
# perde: (1) o TÍTULO do plano (primeiro `# heading`) é IMUTÁVEL entre revisões
# — é a âncora que o próprio Plannotator usa para rastrear versões do MESMO
# plano; (2) cada revisão é fotografada num arquivo IMUTÁVEL antes de ir para o
# navegador, para que o veredito seja auditável depois; (3) a decisão vem do
# envelope --json (contrato de máquina), NUNCA da leitura do texto humano;
# (4) o orçamento de revisões é mecânico, não confiado ao modelo; (5) o plano
# NÃO é publicado num serviço externo por acidente.
#
# CADA RODADA É UM PLANNOTATOR NOVO. Não há "editar a sessão anterior": ao
# receber feedback, o orquestrador REGENERA o plano e esta script abre uma
# sessão inteiramente nova (processo novo, servidor novo, aba nova), preservando
# a rodada anterior no trail. Isso é o coração do portão.
#
# Uso (com o ENV_FILE da FASE 0 sourceado, ou via --env <arquivo>):
#   plan-approval.sh init                     prepara o trail (idempotente)
#   plan-approval.sh round <doc.md>           UMA rodada de revisão no Plannotator
#   plan-approval.sh status                   imprime o trail
#   plan-approval.sh feedback [N]             feedback da revisão N (default: última)
#   plan-approval.sh doc [N]                  caminho do snapshot da revisão N
#   plan-approval.sh origin                   harness detectado + PLANNOTATOR_ORIGIN
#   plan-approval.sh title                    título travado na revisão 1
#   plan-approval.sh approved                 exit 0 se alguma revisão foi APROVADA
#                                             (idempotência: o ENV_FILE pode ser
#                                             REAPROVEITADO por outra sessão —
#                                             DO_REUSE da FASE 0 — e o plano já
#                                             aprovado não deve ser re-submetido)
#
# Exit codes de `round` (o orquestrador ramifica NELES, não em texto):
#   0  APPROVED   — usuário aprovou; siga para a FASE 3
#   10 ANNOTATED  — usuário pediu mudanças; REGENERE o plano e rode de novo
#   11 DISMISSED  — usuário fechou sem decidir
#   12 TIMEOUT    — ninguém decidiu dentro de $DO_PLAN_TIMEOUT
#   13 TOOLFAIL   — o Plannotator rodou e falhou (ou devolveu saída ilegível)
#   14 BUDGET     — orçamento de revisões esgotado ($DO_PLAN_MAX_REVISIONS)
#   2  USAGE/ENV  — ambiente ou entrada inválidos (inclui deriva de título)
#
# Ambiente (todos com default; os DO_* saem do ENV_FILE da FASE 0):
#   PLAN_APPROVAL_DIR      Diretório do trail (default $DO_STATE/plan-approval)
#   DO_PLAN_MAX_REVISIONS  Teto de rodadas (default 5)
#   DO_PLAN_TIMEOUT        Segundos de espera pela decisão (default 3600)
#   DO_PLANNOTATOR_BIN     Executável explícito do Plannotator
#   DO_PLAN_SHARE          1 permite o compartilhamento externo do Plannotator.
#                          Default: DESLIGADO. Em sessão remota (SSH) o
#                          Plannotator sobe um link de compartilhamento e
#                          ENVIA o texto do plano para um serviço de paste —
#                          publicar o plano de um repositório privado não pode
#                          ser efeito colateral silencioso de pedir revisão.
#   DO_PLAN_ORIGIN         Override do harness (claude-code|pi|opencode|codex|
#                          copilot-cli|gemini-cli)
#   DO_PLAN_REMOTE         1 deixa o Plannotator escutar em 0.0.0.0 (porta 19432).
#                          Default: 0 = SÓ 127.0.0.1. Sem isto, um shell com
#                          SSH_TTY/SSH_CONNECTION faria o Plannotator servir o
#                          plano na REDE, e /api/approve não tem autenticação:
#                          qualquer um aprovaria o plano por você. Para revisar
#                          por SSH, use um túnel (ssh -L 19432:127.0.0.1:19432).
# =============================================================================

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

if [ "${1:-}" = "--env" ]; then
  # shellcheck source=/dev/null
  . "$2" || { echo "plan-approval.sh: não consegui sourcear $2" >&2; exit 2; }
  shift 2
fi

err()  { printf '%s\n' "$*" >&2; }
note() { printf '%s\n' "$*" >&2; }   # diagnóstico humano: SEMPRE stderr, para
                                     # que o stdout continue sendo contrato.

# --- exit codes nomeados -----------------------------------------------------
EX_APPROVED=0
EX_USAGE=2
EX_ANNOTATED=10
EX_DISMISSED=11
EX_TIMEOUT=12
EX_TOOLFAIL=13
EX_BUDGET=14

# `help` e `origin` não tocam o estado da execução: respondem sem ENV_FILE, para
# que sirvam ao diagnóstico de uma máquina qualquer. Todo o resto exige a FASE 0.
case "${1:-}" in
  -h|--help|help)
    sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  '')
    sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2 ;;
  origin) : "${DO_STATE:=}" ;;
  *) : "${DO_STATE:?plan-approval.sh: sourceie o ENV_FILE da FASE 0 antes (ou use --env <arquivo>)}" ;;
esac

PLAN_APPROVAL_DIR="${PLAN_APPROVAL_DIR:-$DO_STATE/plan-approval}"
TRAIL="$PLAN_APPROVAL_DIR/trail.tsv"
TITLE_FILE="$PLAN_APPROVAL_DIR/title"
MAX_REVISIONS="${DO_PLAN_MAX_REVISIONS:-5}"
APPROVAL_TIMEOUT="${DO_PLAN_TIMEOUT:-3600}"

# Helpers compartilhados do contrato do Plannotator (binário, harness, envelope
# --json, snapshot, título) — a MESMA fonte usada pelo evolution-survey.sh.
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)"
# shellcheck source=/dev/null
. "$_self_dir/lib/plannotator-common.sh"

case "$MAX_REVISIONS" in
  ''|*[!0-9]*) err "plan-approval.sh: DO_PLAN_MAX_REVISIONS inválido: '$MAX_REVISIONS' (inteiro positivo)"; exit 2 ;;
esac
[ "$MAX_REVISIONS" -gt 0 ] 2>/dev/null \
  || { err "plan-approval.sh: DO_PLAN_MAX_REVISIONS precisa ser > 0"; exit 2; }
case "$APPROVAL_TIMEOUT" in
  ''|*[!0-9]*) err "plan-approval.sh: DO_PLAN_TIMEOUT inválido: '$APPROVAL_TIMEOUT' (segundos, inteiro positivo)"; exit 2 ;;
esac
[ "$APPROVAL_TIMEOUT" -gt 0 ] 2>/dev/null \
  || { err "plan-approval.sh: DO_PLAN_TIMEOUT precisa ser > 0"; exit 2; }

TRAIL_HEADER='revision	timestamp	decision	doc_sha	snapshot	feedback'

ensure_dir() {
  mkdir -p "$PLAN_APPROVAL_DIR" || { err "plan-approval.sh: não consegui criar $PLAN_APPROVAL_DIR"; exit 2; }
  [ -f "$TRAIL" ] || printf '%s\n' "$TRAIL_HEADER" > "$TRAIL"
}

# A revisão é o MAIOR entre o que o trail registrou e o que existe em disco.
# Só o trail não basta: a linha do trail é escrita no FIM da rodada, então uma
# rodada interrompida (Ctrl-C, SIGTERM, binário ausente, máquina suspensa) deixa
# um rev-NNN.md órfão sem linha nenhuma. Contando só o trail, a rodada seguinte
# reusaria o MESMO número e esbarraria no snapshot somente-leitura — travando o
# portão para o resto da execução. Olhar para o disco também torna cada tentativa
# auditável: o snapshot da rodada abortada fica lá, com o número dela.
last_revision() {
  local from_trail=0 from_disk=0
  [ -f "$TRAIL" ] && from_trail=$(awk -F'\t' 'NR>1 && $1 ~ /^[0-9]+$/ { if ($1+0 > m) m = $1+0 } END { print m+0 }' "$TRAIL")
  if [ -d "$PLAN_APPROVAL_DIR" ]; then
    from_disk=$(ls "$PLAN_APPROVAL_DIR" 2>/dev/null \
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

# ---------------------------------------------------------------------------
# init
# ---------------------------------------------------------------------------
cmd_init() {
  ensure_dir
  note "PORTÃO DE APROVAÇÃO pronto: $PLAN_APPROVAL_DIR (teto $MAX_REVISIONS revisões, timeout ${APPROVAL_TIMEOUT}s)"
  printf '%s\n' "$PLAN_APPROVAL_DIR"
}

# ---------------------------------------------------------------------------
# round <doc.md>
# ---------------------------------------------------------------------------
cmd_round() {
  local doc="${1:-}"
  [ -n "$doc" ] || { err "uso: plan-approval.sh round <doc.md>"; exit "$EX_USAGE"; }

  ensure_dir
  pick_json_tool || exit "$EX_USAGE"

  # --- validação do documento ---
  [ -f "$doc" ] || { err "plan-approval.sh: documento não encontrado: $doc"; exit "$EX_USAGE"; }
  [ -s "$doc" ] || { err "plan-approval.sh: documento vazio: $doc"; exit "$EX_USAGE"; }
  local title
  title="$(first_h1 "$doc")"
  if [ -z "$title" ]; then
    err "plan-approval.sh: o documento não tem um título '# ...'."
    err "              O Plannotator deriva o slug da versão do PRIMEIRO heading —"
    err "              sem ele não há como rastrear revisões do mesmo plano."
    exit "$EX_USAGE"
  fi

  # --- imutabilidade do título (regra do próprio Plannotator) ---
  if [ -f "$TITLE_FILE" ]; then
    local locked
    locked="$(cat "$TITLE_FILE")"
    if [ "$locked" != "$title" ]; then
      err "plan-approval.sh: o TÍTULO do plano mudou entre revisões — recusado."
      err "              travado : $locked"
      err "              recebido: $title"
      err "              O Plannotator rastreia versões do MESMO plano pelo primeiro"
      err "              heading. Trocá-lo cria um plano NOVO e joga o histórico de"
      err "              revisões fora. Restaure o título e coloque o que mudou no corpo."
      exit "$EX_USAGE"
    fi
  else
    printf '%s\n' "$title" > "$TITLE_FILE"
  fi

  # --- orçamento ---
  local last rev
  last="$(last_revision)"
  if [ "$last" -ge "$MAX_REVISIONS" ]; then
    err "plan-approval.sh: orçamento de revisões esgotado ($last/$MAX_REVISIONS)."
    err "              Ajuste DO_PLAN_MAX_REVISIONS se mais rodadas forem desejadas."
    exit "$EX_BUDGET"
  fi
  rev=$((last + 1))
  local pad; pad="$(rev_pad "$rev")"

  local snap="$PLAN_APPROVAL_DIR/rev-$pad.md"
  local fb="$PLAN_APPROVAL_DIR/rev-$pad.feedback.md"
  local out="$PLAN_APPROVAL_DIR/rev-$pad.stdout"
  local errf="$PLAN_APPROVAL_DIR/rev-$pad.stderr"
  local decfile="$PLAN_APPROVAL_DIR/rev-$pad.decision"

  # Snapshot IMUTÁVEL: é ELE que vai ao navegador, nunca o arquivo vivo. Se o
  # orquestrador reescrever o plano enquanto a aba está aberta, a revisão
  # auditada continua sendo a que o usuário viu.
  # O rm -f é a rede de segurança do somente-leitura: se por qualquer motivo um
  # snapshot com este número já existir (corrida, restauração de backup, estado
  # importado à mão), o cp esbarraria em EACCES e o portão morreria com um
  # diagnóstico enganoso. Apagar primeiro é sempre seguro — o número da revisão
  # já foi resolvido contra o disco logo acima.
  rm -f -- "$snap" 2>/dev/null || true
  # Falha de I/O NÃO é erro de uso: a FASE 2.5 lê exit 2 como "deriva de título"
  # e mandaria o orquestrador restaurar um título que nunca mudou, em laço.
  cp -- "$doc" "$snap" \
    || { err "plan-approval.sh: não consegui fotografar $doc em $snap (erro de I/O)"; exit "$EX_TOOLFAIL"; }
  chmod a-w "$snap" 2>/dev/null || true

  local bin
  if ! bin="$(resolve_bin)"; then
    err "plan-approval.sh: Plannotator não encontrado. Rode primeiro:"
    err "              \$SKILL_HOME/scripts/check-plannotator.sh --install"
    exit "$EX_TOOLFAIL"
  fi

  local harness origin
  harness="$(detect_harness)"
  origin="$(origin_for_plannotator "$harness")"

  # --- ambiente da sessão ---
  local -a envv=()
  # PLANNOTATOR_CWD ancora a resolução de caminhos/imagens do documento na
  # raiz-de-mundo; o cd abaixo alinha detectProjectName() (que roda git no cwd).
  envv+=("PLANNOTATOR_CWD=${BASE_DIR:-$PWD}")
  [ -n "$origin" ] && envv+=("PLANNOTATOR_ORIGIN=$origin")
  # PLANNOTATOR_REMOTE=0 é OBRIGATÓRIO, e a razão é de segurança, não de gosto.
  # O Plannotator considera "sessão remota" qualquer shell com SSH_TTY ou
  # SSH_CONNECTION no ambiente — e aí ele escuta em 0.0.0.0:19432 em vez de
  # 127.0.0.1. Como /api/approve NÃO tem autenticação, num servidor de
  # desenvolvimento acessado por SSH (o caso comum deste orquestrador) qualquer
  # pessoa da rede leria o plano E poderia APROVÁ-LO — e o orquestrador sairia
  # criando worktrees e commitando por conta de um POST de terceiro.
  # PLANNOTATOR_SHARE=disabled não cobre isto: ele só desliga o link de paste.
  if [ "${DO_PLAN_REMOTE:-0}" = "1" ]; then
    envv+=("PLANNOTATOR_REMOTE=1")
    note "  ATENÇÃO: DO_PLAN_REMOTE=1 — o Plannotator vai escutar em 0.0.0.0 (porta"
    note "           ${PLANNOTATOR_PORT:-19432}). QUALQUER pessoa que alcance esta máquina pode LER o"
    note "           plano e APROVÁ-LO (o endpoint /api/approve não tem autenticação)."
    note "           O caminho seguro para SSH é o túnel: ssh -L 19432:127.0.0.1:19432 <host>"
  else
    envv+=("PLANNOTATOR_REMOTE=0")
  fi
  if [ "${DO_PLAN_SHARE:-0}" = "1" ]; then
    note "PORTÃO DE APROVAÇÃO: compartilhamento externo HABILITADO por DO_PLAN_SHARE=1"
  else
    # Em sessão remota o Plannotator publicaria o texto do plano num serviço de
    # paste. Desligar é o default seguro; o usuário liga explicitamente.
    envv+=("PLANNOTATOR_SHARE=disabled")
  fi

  note "PORTÃO DE APROVAÇÃO revisão $rev/$MAX_REVISIONS — abrindo o Plannotator (sessão NOVA)"
  note "  documento : $snap"
  note "  título    : $title"
  note "  harness   : $harness${origin:+ (PLANNOTATOR_ORIGIN=$origin)}"
  note "  timeout   : ${APPROVAL_TIMEOUT}s"
  note "  Se o navegador não abrir, reabra a sessão ativa com: plannotator sessions --open 1"

  # --- execução ---
  # timeout(1) é o único freio contra uma aba esquecida aberta: o servidor de
  # annotate do Plannotator NÃO tem idle timeout — sem decisão, ele espera para
  # sempre. As flags são sondadas, não presumidas: --foreground e -k são do
  # coreutils GNU; um timeout BSD (ou o gtimeout de outra versão) recusaria a
  # flag, e o erro de uso voltaria como rc!=0 — que nós leríamos como "o
  # Plannotator falhou". Sondar custa uma execução de /bin/true.
  local rc=0
  local -a runner=()
  if command -v timeout >/dev/null 2>&1; then
    if timeout --foreground -k 1 1 true >/dev/null 2>&1; then
      runner=(timeout --foreground -k 10 "$APPROVAL_TIMEOUT")
    elif timeout -k 1 1 true >/dev/null 2>&1; then
      runner=(timeout -k 10 "$APPROVAL_TIMEOUT")
    elif timeout 1 true >/dev/null 2>&1; then
      runner=(timeout "$APPROVAL_TIMEOUT")
    else
      note "  AVISO: timeout(1) presente mas não utilizável — a rodada pode bloquear indefinidamente"
    fi
  else
    note "  AVISO: timeout(1) ausente (macOS sem coreutils?) — a rodada pode bloquear"
    note "         indefinidamente. Instale coreutils, ou feche a aba do Plannotator para liberar."
  fi

  # </dev/null é OBRIGATÓRIO, não higiene: o dispatch do Plannotator cai num
  # `else` final que LÊ STDIN como evento de hook. Um argv que ele não
  # reconheça (versão futura que renomeie o subcomando) passaria a consumir o
  # stdin herdado do agente em vez de falhar — silenciosamente, com exit 0.
  (
    cd "${BASE_DIR:-$PWD}" 2>/dev/null || cd "$PWD" || exit 127
    env "${envv[@]}" "${runner[@]+"${runner[@]}"}" \
      "$bin" annotate "$snap" --gate --json </dev/null
  ) > "$out" 2> "$errf"
  rc=$?

  # --- interpretação ---
  local decision="" feedback_len=0 json_line
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

  : > "$fb"
  if [ "$decision" = "annotated" ]; then
    json_field "$out.json" feedback > "$fb"
    feedback_len="$(wc -c < "$fb" | tr -d ' ')"
    # "Vazio" é AUSÊNCIA DE CONTEÚDO, não tamanho zero: `jq -r '.feedback'` de
    # uma string vazia imprime uma linha em branco (1 byte), e um teste por
    # tamanho deixaria passar um feedback sem uma única palavra.
    if ! grep -q '[^[:space:]]' "$fb"; then
      : > "$fb"
      # Feedback vazio com decision=annotated é contradição do lado do usuário
      # (submeteu sem anotar). Tratar como "quer mudanças, sem dizer quais"
      # travaria o loop: reportamos como dismissed, que é o que de fato ocorreu.
      note "  AVISO: decisão 'annotated' sem feedback — tratando como 'dismissed'"
      decision="dismissed"
    fi
  fi

  printf '%s\n' "$decision" > "$decfile"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$rev" "$(now_iso)" "$decision" "$(sha_of "$snap")" "$snap" \
    "$([ -s "$fb" ] && printf '%s' "$fb" || printf '-')" >> "$TRAIL"

  # Linha de contrato em stdout — uma só, parseável, sempre no mesmo formato.
  printf 'PLAN_APPROVAL decision=%s revision=%s/%s snapshot=%s feedback=%s\n' \
    "$decision" "$rev" "$MAX_REVISIONS" "$snap" \
    "$([ -s "$fb" ] && printf '%s' "$fb" || printf '-')"

  case "$decision" in
    approved)
      note "PORTÃO DE APROVAÇÃO: APROVADO na revisão $rev. Siga para a FASE 3."
      exit "$EX_APPROVED" ;;
    annotated)
      note "PORTÃO DE APROVAÇÃO: MUDANÇAS PEDIDAS na revisão $rev ($feedback_len bytes de feedback)."
      note "           REGENERE o plano a partir de $fb — NÃO implemente o feedback como código —"
      note "           e rode 'plan-approval.sh round' de novo: será um Plannotator NOVO."
      exit "$EX_ANNOTATED" ;;
    dismissed)
      note "PORTÃO DE APROVAÇÃO: sessão FECHADA sem decisão na revisão $rev."
      exit "$EX_DISMISSED" ;;
    timeout)
      note "PORTÃO DE APROVAÇÃO: TIMEOUT (${APPROVAL_TIMEOUT}s) na revisão $rev — ninguém decidiu."
      exit "$EX_TIMEOUT" ;;
    *)
      note "PORTÃO DE APROVAÇÃO: o Plannotator falhou na revisão $rev (exit $rc, decisão '$decision')."
      note "           stdout: $out"
      note "           stderr: $errf"
      exit "$EX_TOOLFAIL" ;;
  esac
}

# ---------------------------------------------------------------------------
# consultas
# ---------------------------------------------------------------------------
cmd_status() {
  if [ ! -f "$TRAIL" ]; then
    note "PORTÃO DE APROVAÇÃO: nenhum trail em $PLAN_APPROVAL_DIR"
    return 0
  fi
  if command -v column >/dev/null 2>&1; then
    column -t -s "$(printf '\t')" < "$TRAIL"
  else
    cat "$TRAIL"
  fi
}

# resolve_rev [N] → número da revisão (default: a última registrada)
resolve_rev() {
  local n="${1:-}"
  if [ -z "$n" ]; then n="$(last_revision)"; fi
  case "$n" in
    ''|*[!0-9]*) err "plan-approval.sh: revisão inválida: '$n'"; return 1 ;;
  esac
  [ "$n" -ge 1 ] 2>/dev/null || { err "plan-approval.sh: nenhuma revisão registrada ainda"; return 1; }
  printf '%s\n' "$n"
}

cmd_feedback() {
  local n f
  n="$(resolve_rev "${1:-}")" || exit "$EX_USAGE"
  f="$PLAN_APPROVAL_DIR/rev-$(rev_pad "$n").feedback.md"
  [ -f "$f" ] || { err "plan-approval.sh: sem feedback para a revisão $n"; exit "$EX_USAGE"; }
  cat "$f"
}

cmd_doc() {
  local n f
  n="$(resolve_rev "${1:-}")" || exit "$EX_USAGE"
  f="$PLAN_APPROVAL_DIR/rev-$(rev_pad "$n").md"
  [ -f "$f" ] || { err "plan-approval.sh: sem snapshot para a revisão $n"; exit "$EX_USAGE"; }
  printf '%s\n' "$f"
}

cmd_origin() {
  local harness origin
  harness="$(detect_harness)"
  origin="$(origin_for_plannotator "$harness")"
  printf 'harness=%s origin=%s\n' "$harness" "${origin:-<default do Plannotator>}"
}

cmd_title() {
  [ -f "$TITLE_FILE" ] || { err "plan-approval.sh: nenhum título travado ainda"; exit "$EX_USAGE"; }
  cat "$TITLE_FILE"
}

# approved → exit 0 se ALGUMA revisão foi aprovada; 1 caso contrário.
# Existe por causa do DO_REUSE da FASE 0: um ENV_FILE de execução em andamento é
# REAPROVEITADO por uma sessão seguinte, e re-submeter um plano já aprovado
# abriria um navegador do nada e queimaria uma revisão do orçamento.
cmd_approved() {
  if [ -f "$TRAIL" ] && awk -F'\t' 'NR>1 && $3=="approved" { found=1 } END { exit !found }' "$TRAIL"; then
    local rev
    rev="$(awk -F'\t' 'NR>1 && $3=="approved" { r=$1 } END { print r }' "$TRAIL")"
    printf 'approved revision=%s\n' "$rev"
    return 0
  fi
  printf 'not-approved\n'
  return 1
}

usage() {
  sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  init)     shift; cmd_init "$@" ;;
  round)    shift; cmd_round "$@" ;;
  status)   shift; cmd_status "$@" ;;
  feedback) shift; cmd_feedback "$@" ;;
  doc)      shift; cmd_doc "$@" ;;
  origin)   shift; cmd_origin "$@" ;;
  title)    shift; cmd_title "$@" ;;
  approved) shift; cmd_approved "$@" ;;
  -h|--help|help) usage; exit 0 ;;
  '')       usage >&2; exit "$EX_USAGE" ;;
  *)        err "plan-approval.sh: subcomando desconhecido: $1"; usage >&2; exit "$EX_USAGE" ;;
esac
