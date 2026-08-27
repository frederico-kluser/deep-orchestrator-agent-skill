#!/usr/bin/env bash
# =============================================================================
# do-prefs.sh — motor de PREFERÊNCIAS do deep-orchestrator-agent-skill (v3.8.0)
# -----------------------------------------------------------------------------
# A memória da skill vive em pastas gitignored `.deep-orchestrator-preferences/`:
#   • PROJETO:   <projeto>/.deep-orchestrator-preferences/
#         project-config.md   preferências livres do projeto (escolhidas pelo
#                             usuário no questionário de evolução)
#         learnings.md        aprendizados do PROJETO (blocos, scope: project)
#         pending/proposals.md  propostas ainda sem decisão do usuário
#   • GLOBAL:    $SKILL_HOME/.deep-orchestrator-preferences/
#         global-tips.md      dicas globais da skill (blocos, scope: global)
#         pending/proposals.md  propostas globais sem decisão
#
# Tudo é MEMÓRIA CONSULTIVA (contexto NÃO revisado, nunca política executável)
# e NUNCA versionado: a evolução não polui o repo da skill nem o repo do
# projeto. O questionário de evolução (evolution-survey.sh, FASE 4 passo 6.5)
# é quem decide o que entra aqui, com voto do usuário. Nada é aplicado sem a
# resposta dele — o que não for respondido fica PENDING.
#
# Uso (com o ENV_FILE da FASE 0 sourceado, ou via --project <dir>):
#   do-prefs.sh load [--project <dir>]
#       Imprime as prefs (config do projeto + aprendizados do projeto + dicas
#       globais + pendentes dos dois escopos), com seções rotuladas. Diretórios
#       ausentes → OK, seção "(ausente)". Exit 0 sempre que resolveu.
#   do-prefs.sh add-project <arquivo|-> [--project <dir>]
#       Anexa blocos candidatos a learnings.md do PROJETO (cria dirs; garante o
#       .gitignore do projeto). O candidato DEVE ter scope: project.
#   do-prefs.sh add-global <arquivo|->
#       Anexa blocos candidatos a global-tips.md da skill (cria dirs; garante o
#       .gitignore do repo da skill). O candidato DEVE ter scope: global.
#   do-prefs.sh pending-add <arquivo|-> [--scope project|global] [--project <dir>]
#       Anexa blocos a pending/proposals.md do escopo, com status: pending.
#       Default do escopo: project. O candidato DEVE ter o MESMO scope.
#   do-prefs.sh pending-list [--scope project|global] [--project <dir>]
#       Imprime os blocos pendentes do escopo.
#   do-prefs.sh ensure-gitignore [--dir <dir>]
#       Acrescenta a linha '.deep-orchestrator-preferences/' ao .gitignore de
#       <dir> (default: raiz do projeto) APENAS se ausente (grep -Fqx); nunca
#       reescreve o arquivo; cria o arquivo se não existir.
#   do-prefs.sh status [--project <dir>]
#       Caminhos, contagens e última data de cada arquivo.
#   do-prefs.sh --help
#
# Exit codes:
#   0 = sucesso (add com entrada vazia → 0, nada escrito — D9)
#   1 = nada a anexar (entrada vazia) — emitido só em modo estrito futuro;
#       hoje entradas vazias saem 0 com 'nada a adicionar' (como evolve-skill)
#   2 = erro de uso/ambiente: opção desconhecida, candidato inválido (campo
#       obrigatório ausente, enum inválido, scope divergente, segredo
#       detectado — o LOTE é rejeitado sem escrever nada), lock ocupado,
#       identidade da skill errada, diretório de destino inexistente
#   3 = escrita fora da raiz de prefs (guarda estrutural — nunca deve disparar)
#
# GARANTIAS DE SEGURANÇA (implementadas como código, não como comentário):
#   • a casa da skill é resolvida pela localização DESTE script (pwd -P,
#     cadeia de symlinks colapsada) — o cwd de invocação é irrelevante;
#   • guarda de identidade: só opera se o SKILL.md da casa tem
#     'name: deep-orchestrator-agent-skill' (exit 3);
#   • TODA escrita é em paths construídos a partir de EXATAMENTE duas raízes
#     (PROJECT_PREFS_DIR e GLOBAL_PREFS_DIR, ou .gitignore das raízes de
#     prefs) — guarda estrutural de prefixo + exit 3 em violação;
#   • lote atômico: qualquer candidato inválido → NADA é escrito (exit 2);
#   • dedupe por id e por título+type normalizado contra o arquivo de destino;
#     bloco aprovado REMOVE os pendentes equivalentes (nunca fica zumbi);
#   • secret scan antes de persistir (prefs são gitignored mas podem vazar);
#   • flock exclusivo por diretório de prefs (.lock) durante add/pending-add —
#     execuções paralelas em projetos diferentes nunca colidem na global-tips;
#   • nunca usa $PWD do chamador para resolver nada; nunca push; nunca toca
#     arquivos versionados além do .gitignore (append de UMA linha);
#   • ids P-YYYYMMDD-NNN são SEMPRE atribuídos por este script — o input nunca
#     é confiado para numerar.
# =============================================================================

set -uo pipefail

# O orquestrador pode exportar GIT_DIR/GIT_WORK_TREE etc. para o próprio fluxo;
# zeramos o ambiente git herdado para que qualquer git aqui seja explícito.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

SKILL_NAME="deep-orchestrator-agent-skill"

err()  { printf 'do-prefs.sh: %s\n' "$*" >&2; }
say()  { printf '%s\n' "$*"; }
warn() { printf 'do-prefs.sh: %s\n' "$*" >&2; }
die()  { err "$*"; exit 2; }

# ---------------------------------------------------------------------------
# Resolução da casa da skill e do repo — NUNCA pelo cwd do chamador
# ---------------------------------------------------------------------------
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)"
[ -n "$_self_dir" ] || { err "não consegui resolver o próprio diretório"; exit 2; }
SKILL_HOME="$(cd "$_self_dir/.." && pwd -P 2>/dev/null || true)"
[ -n "$SKILL_HOME" ] && [ -d "$SKILL_HOME/scripts" ] || { err "SKILL_HOME inválido ($SKILL_HOME)"; exit 2; }

# Repositório git que contém a casa da skill (para o .gitignore global e o
# status). Sem git (instalação por cópia), o add-global ainda funciona — só
# não há .gitignore a garantir.
SKILL_REPO="$(git -C "$SKILL_HOME" rev-parse --show-toplevel 2>/dev/null || true)"

# Guarda de identidade (mesma do evolve-skill.sh): o SKILL.md da raiz pode ser
# symlink; o grep lê o arquivo real.
if ! grep -qx "name: $SKILL_NAME" "$SKILL_HOME/SKILL.md" 2>/dev/null; then
  err "não é a casa desta skill: $SKILL_HOME/SKILL.md não tem 'name: $SKILL_NAME'"
  exit 3
fi

# ---------------------------------------------------------------------------
# Parsers/validadores compartilhados do formato de bloco
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "$_self_dir/lib/evolve-common.sh"

# ---------------------------------------------------------------------------
# Resolução das raízes de prefs
# ---------------------------------------------------------------------------
GLOBAL_PREFS_DIR="$SKILL_HOME/.deep-orchestrator-preferences"
GLOBAL_TIPS="$GLOBAL_PREFS_DIR/global-tips.md"
GLOBAL_PENDING="$GLOBAL_PREFS_DIR/pending/proposals.md"

# Projeto: --project <dir> vence o ambiente (ENV_FILE sourceado pelo
# orquestrador exporta PROJECT_PREFS_DIR). A flag é varrida em QUALQUER
# posição (antes ou depois do subcomando) e removida dos argumentos.
PROJECT_PREFS_DIR="${PROJECT_PREFS_DIR:-}"
PROJECT_ROOT_ARG=""
local_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || die "--project exige um diretório"; PROJECT_ROOT_ARG="$2"; shift 2 ;;
    --project=*) PROJECT_ROOT_ARG="${1#--project=}"; shift ;;
    *) local_args+=("$1"); shift ;;
  esac
done
set -- "${local_args[@]}"
if [ -n "$PROJECT_ROOT_ARG" ]; then
  PROJECT_ROOT="$(cd "$PROJECT_ROOT_ARG" && pwd -P 2>/dev/null || true)"
  [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT" ] \
    || die "--project: diretório não encontrado: $PROJECT_ROOT_ARG"
  PROJECT_PREFS_DIR="$PROJECT_ROOT/.deep-orchestrator-preferences"
elif [ -n "$PROJECT_PREFS_DIR" ]; then
  PROJECT_ROOT="$(cd "${PROJECT_PREFS_DIR%/}/.." 2>/dev/null && pwd -P 2>/dev/null || true)"
else
  PROJECT_ROOT=""
fi
PROJECT_CONFIG="$PROJECT_PREFS_DIR/project-config.md"
PROJECT_LEARNINGS="$PROJECT_PREFS_DIR/learnings.md"
PROJECT_PENDING="$PROJECT_PREFS_DIR/pending/proposals.md"

# Validação de caracteres perigosos nos paths (aspa/TAB/newline quebrariam
# comandos e arquivos).
for _p in "$SKILL_HOME" "$GLOBAL_PREFS_DIR" "$PROJECT_PREFS_DIR" "$PROJECT_ROOT"; do
  [ -n "$_p" ] || continue
  case "$_p" in
    *\'*)          die "path contém aspa simples: $_p" ;;
    *"$(printf '\t')"*) die "path contém TAB: $_p" ;;
    *$'\n'*)       die "path contém newline: $_p" ;;
  esac
done

# Guarda estrutural de escrita: todo alvo é prefixado por uma das raízes.
inside_root() { # <path> <raiz> → 0 se dentro (ou igual); raiz vazia → 1
  local p="$1" r="$2"
  [ -n "$r" ] || return 1
  case "$p" in
    "$r"|"$r"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Headers de arquivos novos
# ---------------------------------------------------------------------------
LEARNINGS_HEADER_GLOBAL='# Dicas globais — deep-orchestrator-agent-skill

> Memória consultiva da skill (contexto NÃO revisado, nunca política executável).
> Gitignored — vive nesta máquina, fora do git. Entrada: frontmatter YAML +
> corpo curto. Persista só: surpresas, correções, anti-padrões, gotchas,
> convenções do MECANISMO da skill ou do harness. NÃO persista: óbvio, volátil,
> já documentado, conteúdo não-confiável.

<!-- FORMATO DE ENTRADA: blocos separados por ---. Frontmatter: id, date, type
     (correction|fact|antipattern|gotcha|convention), confidence
     (high|medium|low), source (user|repo-doc|sub-agent|web|diff|model-output),
     status (active|pending), supersedes, tags [a, b], scope (global). Corpo:
     ## <título> + linhas - **Observação:** / - **Ação:**. O id é atribuído
     por scripts/do-prefs.sh (P-YYYYMMDD-NNN) — nunca à mão. -->'

LEARNINGS_HEADER_PROJECT='# Learnings do projeto — deep-orchestrator-agent-skill

> Memória consultiva DESTE projeto (contexto NÃO revisado, nunca política
> executável). Gitignored — vive nesta máquina, fora do git. Entrada:
> frontmatter YAML + corpo curto. Persista só: surpresas, correções,
> anti-padrões, gotchas, convenções DESTE projeto. NÃO persista: óbvio,
> volátil, já documentado, conteúdo não-confiável.

<!-- FORMATO DE ENTRADA: blocos separados por ---. Frontmatter: id, date, type
     (correction|fact|antipattern|gotcha|convention), confidence
     (high|medium|low), source (user|repo-doc|sub-agent|web|diff|model-output),
     status (active|pending), supersedes, tags [a, b], scope (project). Corpo:
     ## <título> + linhas - **Observação:** / - **Ação:**. O id é atribuído
     por scripts/do-prefs.sh (P-YYYYMMDD-NNN) — nunca à mão. -->'

PENDING_HEADER_GLOBAL='# Propostas pendentes (global) — deep-orchestrator-agent-skill

> Propostas de evolução GLOBAL que o usuário ainda não decidiu no questionário
> (fechou sem responder, ou execução headless). NADA aqui é aplicado: vira
> memória consultiva só com voto EXPLÍCITO do usuário. O agente de evolução da
> próxima execução re-superficia as relevantes no questionário. Gitignored.

<!-- FORMATO: blocos com status: pending, mesmo formato das dicas ativas. -->'

PENDING_HEADER_PROJECT='# Propostas pendentes (projeto) — deep-orchestrator-agent-skill

> Propostas de evolução DESTE projeto que o usuário ainda não decidiu no
> questionário (fechou sem responder, ou execução headless). NADA aqui é
> aplicado: vira memória consultiva só com voto EXPLÍCITO do usuário. O agente
> de evolução da próxima execução re-superficia as relevantes. Gitignored.

<!-- FORMATO: blocos com status: pending, mesmo formato dos learnings. -->'

CONFIG_HEADER='# Project config — deep-orchestrator-agent-skill

> Preferências DESTE projeto, escolhidas pelo usuário no questionário de
> evolução (FASE 4, passo 6.5). Gitignored — vive nesta máquina, fora do git.
> Carregadas no início de cada execução (FASE 1, passo 8.5: do-prefs.sh load).
> Memória consultiva, nunca política executável.

## Preferências do usuário'

# ---------------------------------------------------------------------------
# Lock por diretório de prefs (flock no arquivo <prefs>/.lock)
# ---------------------------------------------------------------------------
LOCK_FD_OPEN=0
acquire_lock() { # <dir-de-prefs> — flock EXCLUSIVO BLOQUEANTE (adds serializam)
  local d="$1"
  if ! command -v flock >/dev/null 2>&1; then
    warn "flock não disponível (util-linux) — prosseguindo sem exclusão mútua"
    return 0
  fi
  mkdir -p "$d" || { err "não consegui criar $d"; return 1; }
  if ! exec 9>>"$d/.lock"; then
    err "não consegui abrir o lock $d/.lock"
    return 1
  fi
  if ! flock 9; then
    err "falha no flock de $d/.lock"
    return 1
  fi
  LOCK_FD_OPEN=1
  return 0
}
release_lock() {
  [ "$LOCK_FD_OPEN" = 1 ] || return 0
  flock -u 9 2>/dev/null || true
  exec 9>&- || true
  LOCK_FD_OPEN=0
}

# ---------------------------------------------------------------------------
# Duplicatas: por id e por título+type normalizado contra um arquivo de destino
# ---------------------------------------------------------------------------
entry_duplicate() { # <norm-título|type> <arquivo> → 0 se já existe
  [ -f "$2" ] || return 1
  local tmp n i f title type
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/do-prefs-dup.XXXXXX")" || return 1
  split_entries "$2" "$tmp"
  n=$(cat "$tmp/COUNT")
  for ((i = 1; i <= n; i++)); do
    f=$(printf '%s/%03d.entry' "$tmp" "$i")
    entry_valid_id "$f" || continue
    title=$(sed -n 's/^## //p' "$f" | head -1)
    type=$(entry_field "$f" type)
    if [ "$(normalize "$title")|$type" = "$1" ]; then
      rm -rf "$tmp"
      return 0
    fi
  done
  rm -rf "$tmp"
  return 1
}

# remove_pending_matches: <norm-título|type> <scope> — remove do pending do
# escopo os blocos equivalentes a um aprendizado recém-aprovado (nunca zumbi).
remove_pending_matches() {
  local key="$1" scope="$2" target root tmp n i f title type kept=0
  case "$scope" in
    project) target="$PROJECT_PENDING"; root="$PROJECT_PREFS_DIR" ;;
    global)  target="$GLOBAL_PENDING";  root="$GLOBAL_PREFS_DIR" ;;
    *) return 1 ;;
  esac
  [ -f "$target" ] || return 0
  inside_root "$target" "$root" || return 0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/do-prefs-rm.XXXXXX")" || return 1
  split_entries "$target" "$tmp"
  n=$(cat "$tmp/COUNT")
  local -a keep=()
  for ((i = 1; i <= n; i++)); do
    f=$(printf '%s/%03d.entry' "$tmp" "$i")
    entry_valid_id "$f" || continue
    title=$(sed -n 's/^## //p' "$f" | head -1)
    type=$(entry_field "$f" type)
    if [ "$(normalize "$title")|$type" = "$key" ]; then
      say "  pendente equivalente removido: $(entry_field "$f" id)"
    else
      keep+=("$f")
      kept=$((kept + 1))
    fi
  done
  {
    cat "$tmp/HEADER"
    local first=1
    # bash 3.2 + set -u: "${keep[@]}" vazio dá "unbound variable" — o guard
    # ${keep[@]+...} expande para NADA quando o array está vazio.
    for f in ${keep[@]+"${keep[@]}"}; do
      [ "$first" = 1 ] && first=0 || printf '\n'
      cat "$f"
    done
    # O `|| true` NÃO é opcional: quando kept=0, `[ ... ] && printf` retorna 1
    # e o grupo inteiro falharia — abortando o rebuild ANTES do mv.
    [ "$kept" -gt 0 ] && printf '\n' || true
  } > "$tmp/rebuild" || { rm -rf "$tmp"; return 1; }
  mv "$tmp/rebuild" "$target" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  return 0
}

# ---------------------------------------------------------------------------
# Núcleo do add (compartilhado por add-project/add-global/pending-add)
# ---------------------------------------------------------------------------
# add_blocks <scope> <status> <arquivo-de-destino> <header> <arquivo-input>
#   scope  project|global
#   status active|pending
# Retorna: 0 ok (nada a anexar incluído) · 2 lote inválido · 3 fora da raiz
add_blocks() {
  local scope="$1" status="$2" target="$3" header="$4" input="$5"
  local prefs_dir
  case "$scope" in
    project) prefs_dir="$PROJECT_PREFS_DIR" ;;
    global)  prefs_dir="$GLOBAL_PREFS_DIR" ;;
    *) err "scope inválido: $scope"; return 2 ;;
  esac
  [ -n "$prefs_dir" ] || { err "raiz de prefs do escopo $scope não resolvida (rode a FASE 0 ou passe --project)"; return 2; }
  inside_root "$target" "$prefs_dir" || { err "ESCRITA FORA DA RAIZ DE PREFS: $target"; return 3; }
  inside_root "$(dirname "$target")" "$prefs_dir" || { err "ESCRITA FORA DA RAIZ DE PREFS: $target"; return 3; }

  [ -f "$input" ] || { err "arquivo não encontrado: $input"; return 2; }

  # Passada 1: quebra em blocos e valida TODOS os candidatos (lote atômico).
  read_candidates "$input"
  if [ "$NBLK" -eq 0 ]; then
    say "add: nada a adicionar (entrada vazia)"
    return 0
  fi

  local idx=0 bad=0 b
  for b in "${CANDIDATES[@]}"; do
    idx=$((idx + 1))
    parse_fields "$b"
    if ! validate_candidate "$idx" "$b"; then
      bad=1
    elif [ "$B_SCOPE" != "$scope" ]; then
      # o conselho aponta o comando do scope DO CANDIDATO (o destino certo dele)
      err "candidato #$idx '${B_TITLE:-<sem título>}' REJEITADO: scope '${B_SCOPE:-<ausente>}' não bate com o destino (use $( [ "${B_SCOPE:-}" = project ] && echo add-project || echo add-global ) para scope=${B_SCOPE:-<ausente>})"
      bad=1
    fi
  done
  [ "$bad" = 0 ] || {
    err "lote REJEITADO: nenhuma entrada foi escrita (exit 2)"
    return 2
  }

  mkdir -p "$(dirname "$target")" || { err "não consegui criar $(dirname "$target")"; return 2; }
  acquire_lock "$prefs_dir" || return 2

  # Passada 2: dedupe + anexa (arquivo criado com header na primeira escrita).
  local added=0 dup=0 newid norm today today_c entry
  local -a written_keys=()
  idx=0
  for b in "${CANDIDATES[@]}"; do
    idx=$((idx + 1))
    parse_fields "$b"
    norm="$(normalize "$B_TITLE")|$B_TYPE"
    if entry_duplicate "$norm" "$target"; then
      say "  duplicada, ignorada: '$B_TITLE' (type=$B_TYPE)"
      dup=$((dup + 1))
      # A intenção "aprovar" já está satisfeita — remove o pendente
      # equivalente para não deixar zumbi aprovado-depois-ignorado.
      [ "$status" = active ] && remove_pending_matches "$norm" "$scope" || true
      continue
    fi
    if [ ! -f "$target" ]; then
      printf '%s\n\n' "$header" > "$target"
    fi
    today_c=$(date +%Y-%m-%d)
    newid="$(next_id_for P "$target")"
    # contrato opcional: preservado quando presente (revalidação manual futura).
    local contract_line=""
    [ -n "$B_CONTRACT" ] && contract_line="contract: $B_CONTRACT"
    entry=$(printf '%s\n' \
      '---' \
      "id: $newid" \
      "date: \"$today_c\"" \
      "type: $B_TYPE" \
      "confidence: $B_CONFIDENCE" \
      "source: $B_SOURCE" \
      "status: $status" \
      'supersedes: ""' \
      "tags: ${B_TAGS:-[]}" \
      "scope: $scope" \
      ${contract_line:+"$contract_line"} \
      '---' \
      "## $B_TITLE" \
      "- **Observação:** $B_OBS" \
      "- **Ação:** $B_ACAO")
    printf '\n%s\n' "$entry" >> "$target"
    written_keys+=("$norm")
    say "  adicionada: $newid — $B_TITLE (type=$B_TYPE, scope=$scope, status=$status)"
    added=$((added + 1))
  done
  # Blocos ativos aprovados removem os pendentes equivalentes (nunca zumbi).
  if [ "$status" = active ] && [ "$added" -gt 0 ]; then
    for norm in "${written_keys[@]}"; do
      remove_pending_matches "$norm" "$scope" || true
    done
  fi

  release_lock
  say "add: $added adicionada(s), $dup duplicada(s) ignorada(s) — destino: $target"
  return 0
}

# ---------------------------------------------------------------------------
# ensure-gitignore
# ---------------------------------------------------------------------------
cmd_ensure_gitignore() {
  local dir="" a
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) [ $# -ge 2 ] || die "ensure-gitignore: --dir exige um diretório"; dir="$2"; shift 2 ;;
      --dir=*) dir="${1#--dir=}"; shift ;;
      *) die "ensure-gitignore: opção desconhecida: $1" ;;
    esac
  done
  [ -n "$dir" ] || dir="$PROJECT_ROOT"
  [ -n "$dir" ] || die "ensure-gitignore: sem diretório (passe --dir ou rode com a FASE 0 sourceada)"
  [ -d "$dir" ] || die "ensure-gitignore: diretório não encontrado: $dir"
  local gi="$dir/.gitignore"
  if [ -f "$gi" ] && grep -Fqx -- '.deep-orchestrator-preferences/' "$gi"; then
    say "ensure-gitignore: linha já presente em $gi"
    return 0
  fi
  # Append de UMA linha — nunca reescreve o arquivo. Garante quebra de linha.
  if [ -f "$gi" ] && [ -s "$gi" ] && [ "$(tail -c 1 "$gi" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then
    printf '\n' >> "$gi"
  fi
  printf '.deep-orchestrator-preferences/\n' >> "$gi" \
    || die "ensure-gitignore: não consegui escrever em $gi"
  say "ensure-gitignore: '.deep-orchestrator-preferences/' acrescentado a $gi"
  return 0
}

# ---------------------------------------------------------------------------
# load
# ---------------------------------------------------------------------------
section() { # <rótulo> <path>
  local label="$1" path="$2"
  say ""
  say "### $label — $path"
  if [ -n "$path" ] && [ -f "$path" ]; then
    cat "$path"
  else
    say "(ausente)"
  fi
}

cmd_load() {
  section "[projeto] config" "$PROJECT_CONFIG"
  section "[projeto] aprendizados" "$PROJECT_LEARNINGS"
  section "[global] dicas" "$GLOBAL_TIPS"
  section "[pendentes · projeto]" "$PROJECT_PENDING"
  section "[pendentes · global]" "$GLOBAL_PENDING"
  return 0
}

# ---------------------------------------------------------------------------
# pending-list / status
# ---------------------------------------------------------------------------
cmd_pending_list() {
  local scope="project" a
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope) [ $# -ge 2 ] || die "pending-list: --scope exige project|global"; scope="$2"; shift 2 ;;
      --scope=*) scope="${1#--scope=}"; shift ;;
      *) die "pending-list: opção desconhecida: $1" ;;
    esac
  done
  case "$scope" in
    project|global) ;;
    *) die "pending-list: scope inválido '$scope' (project|global)" ;;
  esac
  local target
  case "$scope" in
    project) target="$PROJECT_PENDING" ;;
    global)  target="$GLOBAL_PENDING" ;;
  esac
  [ -n "$target" ] || die "pending-list: raiz do escopo $scope não resolvida"
  if [ -f "$target" ]; then
    cat "$target"
  else
    say "(vazio)"
  fi
  return 0
}

file_stats() { # <path> → 'entradas linhas última-data'
  local path="$1" n=0 lines=0 last=""
  if [ -f "$path" ]; then
    lines=$(wc -l < "$path" | tr -d ' ')
    local tmp i f
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/do-prefs-st.XXXXXX")" || { printf '0 0 %s\n' "${last:-—}"; return; }
    split_entries "$path" "$tmp"
    local count
    count=$(cat "$tmp/COUNT")
    for ((i = 1; i <= count; i++)); do
      f=$(printf '%s/%03d.entry' "$tmp" "$i")
      entry_valid_id "$f" || continue
      n=$((n + 1))
      last=$(entry_field "$f" date)
      last=${last//\"/}
    done
    rm -rf "$tmp"
  fi
  printf '%d %d %s\n' "$n" "$lines" "${last:-—}"
}

cmd_status() {
  say "SKILL_HOME         : $SKILL_HOME"
  say "SKILL_REPO         : ${SKILL_REPO:-<sem git — instalação por cópia>}"
  say "PROJECT_PREFS_DIR  : ${PROJECT_PREFS_DIR:-<não resolvido — rode a FASE 0 ou passe --project>}"
  say "GLOBAL_PREFS_DIR   : $GLOBAL_PREFS_DIR"
  local n l d
  read -r n l d <<< "$(file_stats "$PROJECT_LEARNINGS")"
  say "projeto learnings  : $n entrada(s), $l linha(s), última $d"
  read -r n l d <<< "$(file_stats "$PROJECT_PENDING")"
  say "projeto pendentes  : $n bloco(s), $l linha(s), última $d"
  read -r n l d <<< "$(file_stats "$GLOBAL_TIPS")"
  say "global tips        : $n entrada(s), $l linha(s), última $d"
  read -r n l d <<< "$(file_stats "$GLOBAL_PENDING")"
  say "global pendentes   : $n bloco(s), $l linha(s), última $d"
  if [ -f "$PROJECT_CONFIG" ]; then
    say "project config     : $(wc -l < "$PROJECT_CONFIG" | tr -d ' ') linha(s)"
  else
    say "project config     : (ausente)"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
usage() {
  sed -n '2,66p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  '')             usage >&2; exit 2 ;;
  -h|--help|help) usage; exit 0 ;;
  load)           shift; cmd_load "$@" ;;
  add-project)    shift; [ $# -eq 1 ] || die "add-project: aceita exatamente um arquivo de candidatos (ou '-')"
                  [ "$1" = "-" ] && die "add-project: '-' (stdin) não suportado — grave os candidatos num arquivo"
                  add_blocks project active "$PROJECT_LEARNINGS" "$LEARNINGS_HEADER_PROJECT" "$1"
                  rc=$?
                  if [ "$rc" = 0 ] && [ -n "${PROJECT_ROOT:-}" ]; then
                    cmd_ensure_gitignore --dir "$PROJECT_ROOT" >/dev/null || true
                  fi
                  exit $rc ;;
  add-global)     shift; [ $# -eq 1 ] || die "add-global: aceita exatamente um arquivo de candidatos (ou '-')"
                  [ "$1" = "-" ] && die "add-global: '-' (stdin) não suportado — grave os candidatos num arquivo"
                  add_blocks global active "$GLOBAL_TIPS" "$LEARNINGS_HEADER_GLOBAL" "$1"
                  rc=$?
                  if [ "$rc" = 0 ] && [ -n "$SKILL_REPO" ]; then
                    cmd_ensure_gitignore --dir "$SKILL_REPO" >/dev/null || true
                  fi
                  exit $rc ;;
  pending-add)    shift
                  scope="project"; file=""
                  while [ $# -gt 0 ]; do
                    case "$1" in
                      --scope) [ $# -ge 2 ] || die "pending-add: --scope exige project|global"; scope="$2"; shift 2 ;;
                      --scope=*) scope="${1#--scope=}"; shift ;;
                      *) [ -z "$file" ] && { file="$1"; shift; } || die "pending-add: argumento inesperado: $1" ;;
                    esac
                  done
                  [ -n "$file" ] || die "pending-add: falta o arquivo de candidatos"
                  case "$scope" in project|global) ;; *) die "pending-add: scope inválido '$scope'" ;; esac
                  case "$scope" in
                    project) add_blocks project pending "$PROJECT_PENDING" "$PENDING_HEADER_PROJECT" "$file" ;;
                    global)  add_blocks global pending "$GLOBAL_PENDING" "$PENDING_HEADER_GLOBAL" "$file" ;;
                  esac
                  rc=$?
                  if [ "$rc" = 0 ] && [ "$scope" = project ] && [ -n "${PROJECT_ROOT:-}" ]; then
                    cmd_ensure_gitignore --dir "$PROJECT_ROOT" >/dev/null || true
                  fi
                  exit $rc ;;
  pending-list)   shift; cmd_pending_list "$@" ;;
  ensure-gitignore) shift; cmd_ensure_gitignore "$@" ;;
  status)         shift; cmd_status "$@" ;;
  *)              die "subcomando desconhecido: ${1:-}" ;;
esac
