#!/usr/bin/env bash
# =============================================================================
# evolve-skill.sh — motor de AUTO-EVOLUÇÃO CONTÍNUA do deep-orchestrator-agent-skill
# -----------------------------------------------------------------------------
# A skill roda de QUALQUER projeto; ao fim de cada execução o orquestrador
# coleta aprendizados (erros, correções, anti-padrões) e os persiste na pasta
# da própria skill para não repetir erros. Este script é o mecanismo dessa
# memória episódica: anexa aprendizados num LEARNINGS.md, busca, mostra o diff
# pendente, commita em branch próprio (nunca push), consolida (dedupe,
# supersessão de contradições, poda de voláteis, orçamento, propostas de
# promoção) e reporta o status.
#
# Uso:
#   evolve-skill.sh add <arquivo-de-candidatos|-> [--source <rótulo>] [--dry-run]
#       Lê blocos de candidatos (separados por linhas '---'), valida cada um
#       (obrigatórios: title, type, confidence, source, observacao, acao;
#       enums de type/confidence/source; scan de segredos), deduplica contra o
#       LEARNINGS.md (título normalizado + type), gera id LEARN-YYYYMMDD-NNN,
#       anexa a entrada ao LEARNINGS.md e atualiza a seção '## Índice'.
#       O parser IGNORA linhas dentro de code fences (``` … ```) e blocos sem
#       'id: LEARN-<8 dígitos>-<3 dígitos>' válido — o TEMPLATE documentado no
#       LEARNINGS.md nunca vira entrada nem desloca a numeração.
#       '--source <rótulo>' aplica como default para blocos sem o campo.
#       '--dry-run' mostra o que anexaria, sem escrever nada.
#   evolve-skill.sh search <termo>
#       grep -i pelo termo em LEARNINGS.md + prompts/*.md + SKILL.md. Entradas
#       do LEARNINGS saem como 'id | data | type | confidence | source | título'
#       (dedup por id). Exit 0 com resultados, 1 sem.
#   evolve-skill.sh diff [--stat]
#       git diff HEAD -- <paths da allowlist> — mudanças pendentes da evolução;
#       '--stat' resume.
#   evolve-skill.sh apply [--direct] [--branch <nome>] [--message <msg>]
#       Valida antes de commitar (bash -n em scripts/*.sh novos/modificados;
#       verificação com shellcheck quando instalado, senão avisa). Sem
#       --direct/--branch o default é INTELIGENTE: se SÓ LEARNINGS.md /
#       learnings_archive.md mudaram (working tree vs HEAD) → commita DIRETO no
#       branch atual; se qualquer outro path da allowlist mudou (SKILL.md,
#       prompts/, docs/decisions/, README.md, scripts/README.md,
#       check-install.sh, CHANGELOG.md) → cria o branch evolve/YYYY-MM-DD a
#       partir do branch atual e commita lá (--direct: commit no branch atual;
#       --branch <nome>: usa o nome dado). Mensagem:
#       conventional commit 'evolve(learnings): <resumo>' (ou --message).
#       Imprime o diff --stat do commit. NUNCA faz push.
#   evolve-skill.sh consolidate [--apply] [--dry-run]
#       Default: dry-run (relatório + diff, nada escrito). Dedupe (title+type
#       iguais → mantém a mais nova; as antigas vão para learnings_archive.md),
#       supersessão de contradições (mesmo type + tags sobrepostas + título
#       similar em datas diferentes → a mais nova vence; a antiga vira
#       status: superseded + supersedes + '~~título~~ (obsoleto ...)' — NUNCA
#       apaga), poda de voláteis (type: fact com tags preço|versão|estado|
#       price|version|state e mais de 90 dias → learnings_archive.md), orçamento
#       (entradas ativas > 100 linhas → move as mais antigas para o arquivo),
#       e PROPOSTAS de promoção (entrada em probação com ≥2 ocorrências
#       independentes — mesmo título/type em datas diferentes — OU source: user;
#       fontes web|sub-agent|diff|model-output NUNCA promovem, nem aparecem na
#       proposta). '--apply' escreve os arquivos e commita em
#       evolve/consolidacao-YYYY-MM-DD (mesma validação do apply).
#   evolve-skill.sh status
#       SKILL_REPO, branch atual, versão da skill (lida do frontmatter do
#       SKILL.md), nº de entradas (ativas/superseded), orçamento (linhas do
#       LEARNINGS.md vs tetos), branches evolve/* abertas, última data.
#   evolve-skill.sh --help
#
# Exit codes:
#   0 = sucesso
#   1 = search sem resultados
#   2 = erro de uso/ambiente: opção desconhecida, candidato inválido (campo
#       obrigatório ausente, enum inválido, segredo detectado — o LOTE é
#       rejeitado sem escrever nada), skill instalada por CÓPIA sem git, lock
#       ocupado, validação bash -n/shellcheck falhou
#   3 = identidade: o SKILL.md da casa não tem 'name: deep-orchestrator-agent-skill'
#   4 = escrita detectada fora da allowlist (working tree, staged ou commit)
#
# GARANTIAS DE SEGURANÇA (implementadas como código, não como comentário):
#   • a casa da skill é resolvida pela localização DESTE script, com pwd -P
#     colapsando a cadeia de symlinks (o repo é alcançado por symlink de vários
#     agentes) — o cwd de invocação é irrelevante;
#   • sem repositório git válido → exit 2 (skill instalada por CÓPIA: rode
#     scripts/sync-global-skill.sh para converter para symlink);
#   • guarda de identidade: só opera se o SKILL.md contém exatamente
#     'name: deep-orchestrator-agent-skill' (o SKILL.md da raiz é symlink; o
#     grep lê através dele, i.e., o arquivo real);
#   • ALLOWLIST de paths que este script pode tocar (relativos a SKILL_REPO):
#     LEARNINGS.md, learnings_archive.md, SKILL.md, prompts/, docs/decisions/,
#     README.md, scripts/README.md, check-install.sh, CHANGELOG.md — o
#     git status --porcelain é fotografado no início e conferido após cada
#     mutação; qualquer path novo fora da allowlist → exit 4;
#   • NENHUM commit engole staged alheio: antes de commitar o índice é
#     conferido (git diff --cached --name-only) e QUALQUER path staged fora da
#     allowlist → exit 4 SEM tocar no índice (o staged do usuário/outra
#     sub-tarefa fica intacto);
#   • NUNCA apaga conteúdo: supersessão é marcação (~~…~~ + status), poda é
#     MUDANÇA para learnings_archive.md — nunca deleção;
#   • entrada sem source é rejeitada; fontes não-confiáveis
#     (web|sub-agent|diff|model-output) nunca promovem (nem aparecem na
#     proposta);
#   • flock exclusivo (em <gitdir>/evolve-skill.lock) durante apply,
#     consolidate e o append do add — execuções paralelas não colidem (adds
#     concorrentes serializam e nunca geram id duplicado);
#   • nunca usa $PWD do chamador para resolver nada da skill; nunca push;
#     nunca mexe na versão da skill (metadata.version é de outra sub-tarefa).
# =============================================================================

set -uo pipefail

# O orquestrador pode exportar GIT_DIR/GIT_WORK_TREE etc. para o próprio fluxo;
# `git -C` não sobrevive a isso (GIT_DIR tem precedência). Zeramos o ambiente
# git herdado para que TODOS os git aqui sejam explícitos via -C.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true

SKILL_NAME="deep-orchestrator-agent-skill"

err()  { printf 'evolve-skill.sh: %s\n' "$*" >&2; }
say()  { printf '%s\n' "$*"; }
warn() { printf 'evolve-skill.sh: %s\n' "$*" >&2; }
die()  { err "$*"; exit 2; }

# ---------------------------------------------------------------------------
# Resolução da casa da skill — NUNCA pelo cwd do chamador
# ---------------------------------------------------------------------------
_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)"
if [ -z "$_self" ]; then
  err "não consegui resolver o próprio diretório"
  exit 2
fi
SKILL_HOME="$(cd "$_self/.." && pwd -P 2>/dev/null || true)"
if [ -z "$SKILL_HOME" ] || [ ! -d "$SKILL_HOME/scripts" ]; then
  err "SKILL_HOME inválido ($SKILL_HOME)"
  exit 2
fi

# Repositório git que contém a casa da skill. Sem git → a skill está instalada
# por CÓPIA num lugar sem repositório: não há onde commitar a evolução.
SKILL_REPO="$(git -C "$SKILL_HOME" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$SKILL_REPO" ]; then
  err "skill instalada por CÓPIA sem git — rode scripts/sync-global-skill.sh para converter para symlink"
  exit 2
fi

# Guarda de identidade: o SKILL.md da raiz é symlink; o grep lê o arquivo real.
if ! grep -qx "name: $SKILL_NAME" "$SKILL_HOME/SKILL.md" 2>/dev/null; then
  err "não é a casa desta skill: $SKILL_HOME/SKILL.md não tem 'name: $SKILL_NAME'"
  exit 3
fi

LEARNINGS="$SKILL_REPO/LEARNINGS.md"
ARCHIVE="$SKILL_REPO/learnings_archive.md"

# ALLOWLIST de paths que este script pode tocar (relativos a SKILL_REPO).
ALLOWED_PATHS=(LEARNINGS.md learnings_archive.md SKILL.md prompts/ docs/decisions/ README.md scripts/README.md check-install.sh CHANGELOG.md)

BUDGET_ACTIVE_LINES=100
BUDGET_TOTAL_LINES=400
VOLATILE_DAYS=90
# Tolerante a acentos (preço/preco, versão/versao) além do inglês price/version/state.
VOLATILE_TAGS='pre[cç]o|vers[aã]o|estado|price|version|state'

MIN_HEADER='# LEARNINGS — deep-orchestrator-agent-skill

> Memória episódica da skill (contexto NÃO revisado, nunca política executável).
> Entrada: frontmatter YAML + corpo curto. Persista só: surpresas, correções,
> anti-padrões, gotchas, convenções. NÃO persista: óbvio, volátil, já documentado,
> conteúdo não-confiável (web/sub-agente/diff/model-output NUNCA promovem).

## Índice'

ARCHIVE_HEADER='# LEARNINGS ARCHIVE — deep-orchestrator-agent-skill

> Entradas arquivadas por scripts/evolve-skill.sh consolidate — preservadas,
> nunca apagadas. O marcador que precede cada entrada registra data e motivo.'

# Área de rascunho única do processo (fora do repo, para nunca sujar o porcelain).
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/evolve-skill.XXXXXX" 2>/dev/null)" || {
  err "não consegui criar diretório temporário em ${TMPDIR:-/tmp}"
  exit 2
}
trap 'rm -rf "$TMPD"' EXIT

# Estado global compartilhado pelas passadas do consolidate.
declare -a ORDER=() ARCHIVED=() PROPOSALS=()
NDUP=0 NSUP=0 NPRUNE=0 NBUDG=0

# Fotografia do git status --porcelain no início: a conferência da allowlist
# tolera o que JÁ estava sujo antes deste script rodar (outras sub-tarefas do
# orquestrador podem estar mexendo em SKILL.md/README.md ao mesmo tempo) e
# dispara exit 4 apenas para paths NOVOS fora da allowlist.
PORCELAIN_BEFORE="$(git -C "$SKILL_REPO" status --porcelain 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  # Imprime o cabeçalho INTEIRO (da linha 2 até o fechamento '# ==='), sem
  # depender do número de linhas — o doc cresceu com os defaults novos (F8/F6).
  awk 'NR==1{next} /^# =+$/ && NR>2 {exit} {print}' "$0" | sed 's/^# \{0,1\}//'
}

is_allowed_path() { # <path> → 0 se dentro da allowlist
  local p="$1" a
  for a in "${ALLOWED_PATHS[@]}"; do
    case "$a" in
      */) case "$p" in "$a"*) return 0 ;; esac ;;
      *)  [ "$p" = "$a" ] && return 0 ;;
    esac
  done
  return 1
}

detect_outside_write() { # 0 se apareceu path novo fora da allowlist (não fomos nós → tolerado)
  # Considera working tree E staged: o porcelain cobre ambos (coluna X =
  # staged) e o diff --cached é conferido explicitamente abaixo.
  local line st p out staged sp
  out="$(git -C "$SKILL_REPO" status --porcelain 2>/dev/null || true)"
  if [ -n "$out" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      st="${line:0:2}"
      p="${line:3}"
      if ! is_allowed_path "$p"; then
        if printf '%s\n' "$PORCELAIN_BEFORE" | grep -Fqx -- "$line"; then
          continue   # já estava assim antes de este script rodar — não fomos nós
        fi
        err "ESCRITA FORA DA ALLOWLIST detectada: $p ($st)"
        err "allowlist: ${ALLOWED_PATHS[*]}"
        return 0
      fi
    done <<< "$out"
  fi
  # staged explícito (diff --cached) — por completude do diagnóstico; a
  # garantia ABSOLUTA de commit (mesmo para staged pré-existente) é o
  # guard_staged_allowlist, que roda antes de qualquer mutação/commit.
  staged="$(git -C "$SKILL_REPO" diff --cached --name-only 2>/dev/null || true)"
  while IFS= read -r sp; do
    [ -n "$sp" ] || continue
    if ! is_allowed_path "$sp"; then
      if printf '%s\n' "$PORCELAIN_BEFORE" | grep -Fq -- "$sp"; then
        continue   # já estava staged antes — tolerado aqui; guard_staged_allowlist decide
      fi
      err "ESCRITA FORA DA ALLOWLIST detectada (staged): $sp"
      err "allowlist: ${ALLOWED_PATHS[*]}"
      return 0
    fi
  done <<< "$staged"
  return 1
}

guard_allowlist() {
  detect_outside_write && exit 4
  return 0
}

# Guarda pré-commit (F1): NENHUM path fora da allowlist pode estar no índice.
# O staged do usuário/outra sub-tarefa é preservado — nunca fazemos reset —
# mas o nosso commit NUNCA o engole: abortamos (exit 4) antes de qualquer
# mutação, listando o path.
guard_staged_allowlist() {
  local staged sp bad=0
  staged="$(git -C "$SKILL_REPO" diff --cached --name-only 2>/dev/null || true)"
  while IFS= read -r sp; do
    [ -n "$sp" ] || continue
    if ! is_allowed_path "$sp"; then
      err "PATH STAGED FORA DA ALLOWLIST: $sp — abortando SEM commitar (índice preservado)"
      bad=1
    fi
  done <<< "$staged"
  if [ "$bad" = 1 ]; then
    err "allowlist: ${ALLOWED_PATHS[*]}"
    return 1
  fi
  return 0
}

normalize() { # "$@" → minúsculas, só alfanuméricos, espaços simples
  printf '%s' "$*" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' \
    | sed 's/^ *//; s/ *$//; s/  */ /g'
}

entry_field() { # <arquivo-entrada> <campo> → valor da primeira linha 'campo: valor'
  local f="$1" k="$2"
  sed -n "s/^$k: *//p" "$f" | head -1
}

# split_entries <arquivo> <dir> — parte o LEARNINGS.md em entradas.
#   • <dir>/HEADER  → tudo antes da primeira entrada (título, blockquotes, '## Índice' e linhas antigas do índice)
#   • <dir>/NNN.entry (001, 002, ...) → uma entrada completa (frontmatter + título + corpo)
#   • <dir>/COUNT   → número de entradas
# Uma entrada tem exatamente duas linhas '---' (antes do frontmatter e entre o
# frontmatter e o corpo); a terceira '---' já abre a entrada seguinte. Por isso
# alternamos: '---' ímpar = início de entrada, '---' par = fronteira frontmatter/corpo.
# Linhas em branco finais de cada entrada (separadores entre entradas) são
# removidas na escrita — o rebuild volta a interpor exatamente uma.
split_entries() {
  local src="$1" dst="$2" line
  local n=0 idx=0 cur="" header="" infence=0
  : > "$dst/HEADER"
  : > "$dst/COUNT"
  while IFS= read -r line || [ -n "$line" ]; do
    # F6: linhas dentro de code fences (``` … ```) NUNCA são fronteira de
    # entrada — o TEMPLATE documentado no LEARNINGS.md fica no header.
    if [ "$infence" = 1 ]; then
      case "$line" in '```'*) infence=0 ;; esac
    else
      case "$line" in '```'*) infence=1 ;; esac
    fi
    if [ "$infence" = 1 ] || [ "$line" != "---" ]; then
      if [ "$idx" -eq 0 ]; then
        header=$header$line$'\n'
      else
        cur=$cur$'\n'$line
      fi
      continue
    fi
    # fora de fence e linha '---': fronteira de entrada
    n=$((n + 1))
    if [ $((n % 2)) -eq 1 ]; then
      if [ "$idx" -gt 0 ]; then
        printf '%s\n' "$cur" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' \
          > "$dst/$(printf '%03d' "$idx").entry"
      fi
      idx=$((idx + 1))
      cur="---"
    else
      cur=$cur$'\n---'
    fi
  done < "$src"
  if [ "$idx" -gt 0 ]; then
    printf '%s\n' "$cur" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' \
      > "$dst/$(printf '%03d' "$idx").entry"
  fi
  printf '%s' "$header" > "$dst/HEADER"
  printf '%d\n' "$idx" > "$dst/COUNT"
}

entry_meta() { # <arquivo> → 'id|date|type|confidence|source|status|tags|title'
  local f="$1" id date type conf src status tags title
  id=$(entry_field "$f" id)
  date=$(entry_field "$f" date)
  date=${date//\"/}
  type=$(entry_field "$f" type)
  conf=$(entry_field "$f" confidence)
  src=$(entry_field "$f" source)
  status=$(entry_field "$f" status)
  [ -z "$status" ] && status=active
  tags=$(entry_field "$f" tags)
  title=$(sed -n 's/^## //p' "$f" | head -1)
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$id" "$date" "$type" "$conf" "$src" "$status" "$tags" "$title"
}

# F6: um bloco só é ENTRADA se o frontmatter tem 'id: LEARN-<8 dígitos>-<3 dígitos>'.
# Blocos sem id válido (ex.: TEMPLATE em code fence com placeholders) são ignorados.
entry_valid_id() { # <arquivo> → 0 se id válido (grep -E)
  grep -Eq '^id: LEARN-[0-9]{8}-[0-9]{3}$' "$1"
}

tags_list() { # "[a, b]" → uma tag por linha
  printf '%s' "$1" | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true
}

tags_overlap() { # <tagsA> <tagsB> → 0 se a interseção não é vazia
  local a b
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    while IFS= read -r b; do
      [ -z "$b" ] && continue
      [ "$a" = "$b" ] && return 0
    done <<< "$(tags_list "$2")"
  done <<< "$(tags_list "$1")"
  return 1
}

tags_volatile() { # <tags> → 0 se alguma tag é volátil (preço|versão|estado|price|version|state)
  local t
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    printf '%s\n' "$t" | grep -Eiq "$VOLATILE_TAGS" && return 0
  done <<< "$(tags_list "$1")"
  return 1
}

titles_similar() { # <título1> <título2> → 0 se similares (idênticos OU ≥ metade das
  # palavras do menor compartilhadas). Distinto do dedupe: aqui é SEMELHANÇA,
  # para detectar contradição entre entradas que não são a mesma.
  local a b
  a="$(normalize "$1")"
  b="$(normalize "$2")"
  [ -n "$a" ] && [ "$a" = "$b" ] && return 0
  local -a wa wb
  read -r -a wa <<< "$a"
  read -r -a wb <<< "$b"
  [ "${#wa[@]}" -gt 0 ] && [ "${#wb[@]}" -gt 0 ] || return 1
  local min common=0 w
  if [ "${#wa[@]}" -le "${#wb[@]}" ]; then min="${#wa[@]}"; else min="${#wb[@]}"; fi
  for w in "${wa[@]}"; do
    case " $b " in
      *" $w "*) common=$((common + 1)) ;;
    esac
  done
  [ "$common" -ge 1 ] && [ "$common" -ge $(((min + 1) / 2)) ] && return 0
  return 1
}

next_id() { # → LEARN-YYYYMMDD-NNN — SÓ linhas 'id: LEARN-<hoje>-...' fora de code fences
  local today n line num infence=0
  today=$(date +%Y%m%d)
  n=0
  if [ -f "$LEARNINGS" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      # F6: ignora code fences (o TEMPLATE tem 'id: LEARN-YYYYMMDD-NNN').
      case "$line" in
        '```'*) if [ "$infence" = 1 ]; then infence=0; else infence=1; fi ;;
      esac
      [ "$infence" = 1 ] && continue
      # F7: só linhas que COMEÇAM com 'id: LEARN-<hoje>-'; exemplos em
      # comentários/placeholders (LEARN-AAAA-MM-DD-NNN etc.) nunca deslocam.
      case "$line" in
        "id: LEARN-$today-"*)
          num="${line#id: LEARN-$today-}"
          num="${num%%[!0-9]*}"
          if [ -n "$num" ] && [ "$num" -gt "$n" ] 2>/dev/null; then
            n="$num"
          fi
          ;;
      esac
    done < "$LEARNINGS"
  fi
  # 10# força base decimal: um id existente '008' seria lido como octal e
  # estouraria a aritmética do bash (valor muito grande para a base).
  n=$((10#${n:-0} + 1))
  printf 'LEARN-%s-%03d\n' "$today" "$n"
}

insert_before() { # <arquivo> <posição> <texto> — insere <texto> antes da linha <posição>
  local file="$1" pos="$2" text="$3"
  local total tmp
  total=$(wc -l < "$file")
  if [ "$pos" -gt "$total" ]; then
    printf '%s\n' "$text" >> "$file"
    return 0
  fi
  tmp="$TMPD/insert.$$"
  awk -v p="$pos" -v t="$text" 'NR==p{print t} {print}' "$file" > "$tmp" \
    && mv "$tmp" "$file"
}

insert_index_line() { # <data> <type> <título> <id> — atualiza a seção '## Índice'
  local date="$1" type="$2" title="$3" id="$4"
  local line="- $date | $type | $title [id: $id]"
  local hdr pos lastidx
  hdr=$(grep -n '^## Índice$' "$LEARNINGS" | head -1 | cut -d: -f1)
  if [ -z "$hdr" ]; then
    # sem seção '## Índice': cria antes da primeira entrada (ou anexa no fim)
    pos=$(grep -n '^---$' "$LEARNINGS" | head -1 | cut -d: -f1)
    if [ -z "$pos" ]; then
      printf '\n## Índice\n\n%s\n' "$line" >> "$LEARNINGS"
    else
      insert_before "$LEARNINGS" "$pos" "$(printf '## Índice\n\n%s' "$line")"
    fi
    return 0
  fi
  # Fim da seção = a ÚLTIMA linha de índice ('- ...') antes da primeira entrada;
  # a nova linha entra logo DEPOIS dela, mantendo o bloco de índice contíguo
  # (a linha em branco antes da primeira entrada fica onde deve).
  lastidx=$(awk -v s="$hdr" 'NR>s && /^---$/{exit} NR>s && /^- /{last=NR} END{print last+0}' "$LEARNINGS")
  if [ "$lastidx" -gt 0 ]; then
    insert_before "$LEARNINGS" "$((lastidx + 1))" "$line"
  else
    insert_before "$LEARNINGS" "$((hdr + 1))" "$line"
  fi
}

learnings_stats() { # → 'total_entradas ativas superseded linhas_totais linhas_ativas ultima_data'
  local tmp="$TMPD/stats" n i f lines
  local M_ID M_DATE M_TYPE M_CONF M_SRC M_STATUS M_TAGS M_TITLE
  mkdir -p "$tmp"
  split_entries "$LEARNINGS" "$tmp"
  n=$(cat "$tmp/COUNT")
  local total_e=0 act_e=0 sup_e=0 total_l=0 act_l=0 last=""
  for ((i = 1; i <= n; i++)); do
    f=$(printf '%s/%03d.entry' "$tmp" "$i")
    entry_valid_id "$f" || continue   # F6: blocos sem id válido (template) não contam
    IFS='|' read -r M_ID M_DATE M_TYPE M_CONF M_SRC M_STATUS M_TAGS M_TITLE <<< "$(entry_meta "$f")"
    total_e=$((total_e + 1))
    lines=$(wc -l < "$f")
    total_l=$((total_l + lines))
    case "$M_STATUS" in
      active)     act_e=$((act_e + 1)); act_l=$((act_l + lines)) ;;
      superseded) sup_e=$((sup_e + 1)) ;;
    esac
    [ -n "$M_DATE" ] && last="$M_DATE"
  done
  printf '%d %d %d %d %d %s\n' "$total_e" "$act_e" "$sup_e" "$total_l" "$act_l" "$last"
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------

parse_fields() { # <bloco> → popula B_TITLE B_TYPE B_CONFIDENCE B_SOURCE B_TAGS B_OBS B_ACAO
  local block="$1" line key val
  B_TITLE=""; B_TYPE=""; B_CONFIDENCE=""; B_SOURCE=""; B_TAGS=""; B_OBS=""; B_ACAO=""
  while IFS= read -r line; do
    case "$line" in
      ''|'---') continue ;;
      *:*)
        key="${line%%:*}"
        val="${line#*:}"
        val="${val# }"
        case "$key" in
          title)       B_TITLE="$val" ;;
          type)        B_TYPE="$val" ;;
          confidence)  B_CONFIDENCE="$val" ;;
          source)      B_SOURCE="$val" ;;
          tags)        B_TAGS="$val" ;;
          observacao)  B_OBS="$val" ;;
          acao)        B_ACAO="$val" ;;
        esac ;;
    esac
  done <<< "$block"
}

secret_scan() { # <texto> → 0 se parece conter CREDENCIAL (regex case-insensitive)
  # Só padrões de CREDENCIAL disparam: keyword + separador '=' ou ':' + valor,
  # ou cabeçalho de chave privada. Palavras soltas ("token de", "o token",
  # "password do") NÃO disparam. O valor capturado nunca é impresso.
  printf '%s\n' "$1" | grep -Eiq \
    '(access[_-]?token|auth[_-]?token|api[_-]?key|secret|password|passwd)[=:][[:space:]]*[^[:space:]]|BEGIN[[:space:]_-]+(RSA|OPENSSH|EC|DSA)[[:space:]_-]+PRIVATE[[:space:]_-]+KEY'
}

validate_candidate() { # <índice> <bloco> — erros em stderr; 0 válido / 1 inválido (NUNCA imprime valores de segredo)
  local i="$1" blk="$2" ok=1 label
  label="${B_TITLE:-<sem título>}"
  local -a missing=()
  [ -z "$B_TITLE" ]      && missing+=("title")
  [ -z "$B_TYPE" ]       && missing+=("type")
  [ -z "$B_CONFIDENCE" ] && missing+=("confidence")
  [ -z "$B_SOURCE" ]     && missing+=("source")
  [ -z "$B_OBS" ]        && missing+=("observacao")
  [ -z "$B_ACAO" ]       && missing+=("acao")
  if [ "${#missing[@]}" -gt 0 ]; then
    err "candidato #$i '$label' REJEITADO: campos obrigatórios ausentes: ${missing[*]}"
    ok=0
  fi
  if [ -n "$B_TYPE" ]; then
    case "$B_TYPE" in
      correction|fact|antipattern|gotcha|convention) ;;
      *) err "candidato #$i '$label' REJEITADO: type inválido '$B_TYPE' (correction|fact|antipattern|gotcha|convention)"; ok=0 ;;
    esac
  fi
  if [ -n "$B_CONFIDENCE" ]; then
    case "$B_CONFIDENCE" in
      high|medium|low) ;;
      *) err "candidato #$i '$label' REJEITADO: confidence inválida '$B_CONFIDENCE' (high|medium|low)"; ok=0 ;;
    esac
  fi
  if [ -n "$B_SOURCE" ]; then
    case "$B_SOURCE" in
      user|repo-doc|sub-agent|web|diff|model-output) ;;
      *) err "candidato #$i '$label' REJEITADO: source inválida '$B_SOURCE' (user|repo-doc|sub-agent|web|diff|model-output)"; ok=0 ;;
    esac
  fi
  if secret_scan "$blk"; then
    err "candidato #$i REJEITADO: possível segredo detectado (api key/secret/password/token/chave privada) — valor NÃO exibido"
    ok=0
  fi
  [ "$ok" = 1 ] && return 0
  return 1
}

entry_duplicate() { # <norm-título|type> → 0 se já existe no LEARNINGS.md
  [ -f "$LEARNINGS" ] || return 1
  local tmp="$TMPD/dup-check" n i f title type
  mkdir -p "$tmp"
  split_entries "$LEARNINGS" "$tmp"
  n=$(cat "$tmp/COUNT")
  for ((i = 1; i <= n; i++)); do
    f=$(printf '%s/%03d.entry' "$tmp" "$i")
    entry_valid_id "$f" || continue   # F6: blocos sem id válido (template) não contam
    title=$(sed -n 's/^## //p' "$f" | head -1)
    type=$(entry_field "$f" type)
    if [ "$(normalize "$title")|$type" = "$1" ]; then
      return 0
    fi
  done
  return 1
}

append_entry() { # <título> <type> <confidence> <source> <tags> <observacao> <acao> → imprime o id
  local title="$1" type="$2" conf="$3" src="$4" tags="$5" obs="$6" acao="$7"
  local today today_c id entry
  today=$(date +%Y%m%d)
  today_c=$(date +%Y-%m-%d)
  id="$(next_id)"
  entry=$(printf '%s\n' \
    '---' \
    "id: $id" \
    "date: \"$today_c\"" \
    "type: $type" \
    "confidence: $conf" \
    "source: $src" \
    'status: active' \
    'supersedes: ""' \
    "tags: ${tags:-[]}" \
    '---' \
    "## $title" \
    "- **Observação:** $obs" \
    "- **Ação:** $acao")
  if [ ! -f "$LEARNINGS" ]; then
    printf '%s\n' "$MIN_HEADER" > "$LEARNINGS"
  fi
  insert_index_line "$today_c" "$type" "$title" "$id"
  printf '\n%s\n' "$entry" >> "$LEARNINGS"
  printf '%s\n' "$id"
}

cmd_add() {
  local file="" dsrc="" dry=0 a
  while [ $# -gt 0 ]; do
    case "$1" in
      --source)   [ $# -ge 2 ] || die "add: --source exige um rótulo"; dsrc="$2"; shift 2 ;;
      --source=*) dsrc="${1#--source=}"; shift ;;
      --dry-run)  dry=1; shift ;;
      *) if [ -z "$file" ]; then file="$1"; shift
         else die "add: argumento inesperado: $1"; fi ;;
    esac
  done
  [ -n "$file" ] || die "add: falta o arquivo de candidatos (ou '-')"

  local input="$file"
  [ "$file" = "-" ] && input="/dev/stdin"
  [ "$input" = "/dev/stdin" ] || [ -f "$input" ] || die "add: arquivo não encontrado: $file"

  # Passada 1: quebra em blocos e valida TODOS os candidatos (lote atômico:
  # qualquer inválido → nada é escrito e o lote sai com exit 2).
  local -a candidates=()
  local cur="" line idx=0 bad=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "---" ]; then
      if [ -n "$cur" ]; then
        candidates+=("$cur")
        cur=""
      fi
    else
      cur+=$'\n'"$line"
    fi
  done < "$input"
  [ -n "$cur" ] && candidates+=("$cur")

  if [ "${#candidates[@]}" -eq 0 ]; then
    die "add: nenhum candidato encontrado no arquivo"
  fi

  local b
  for b in "${candidates[@]}"; do
    idx=$((idx + 1))
    parse_fields "$b"
    [ -z "$B_SOURCE" ] && B_SOURCE="$dsrc"
    if ! validate_candidate "$idx" "$b"; then
      bad=1
    fi
  done
  [ "$bad" = 0 ] || {
    err "lote REJEITADO: nenhuma entrada foi escrita (exit 2)"
    exit 2
  }

  # Passada 2: dedupe + anexa (ou só mostra, em dry-run).
  # F4: lock exclusivo durante leitura-next_id + append — adds paralelos
  # serializam e nunca geram id duplicado. dry-run não escreve → sem lock.
  if [ "$dry" = 0 ]; then
    wait_lock || exit 2
  fi
  local added=0 dup=0 newid norm
  idx=0
  for b in "${candidates[@]}"; do
    idx=$((idx + 1))
    parse_fields "$b"
    [ -z "$B_SOURCE" ] && B_SOURCE="$dsrc"
    norm="$(normalize "$B_TITLE")|$B_TYPE"
    if entry_duplicate "$norm"; then
      say "  duplicada, ignorada: '$B_TITLE' (type=$B_TYPE)"
      dup=$((dup + 1))
      continue
    fi
    if [ "$dry" = 1 ]; then
      say "  [dry-run] adicionaria: $B_TITLE (type=$B_TYPE, source=$B_SOURCE, confidence=$B_CONFIDENCE)"
      added=$((added + 1))
    else
      newid="$(append_entry "$B_TITLE" "$B_TYPE" "$B_CONFIDENCE" "$B_SOURCE" "${B_TAGS:-}" "$B_OBS" "$B_ACAO")"
      say "  adicionada: $newid — $B_TITLE (type=$B_TYPE)"
      added=$((added + 1))
    fi
  done

  if [ "$dry" = 0 ]; then
    release_lock
  fi

  if [ "$dry" = 0 ] && [ "$added" -gt 0 ] && [ -f "$LEARNINGS" ]; then
    local TE TA TS TL AL LAST
    read -r TE TA TS TL AL LAST <<< "$(learnings_stats)"
    if [ "$AL" -gt "$BUDGET_ACTIVE_LINES" ] || [ "$TL" -gt "$BUDGET_TOTAL_LINES" ]; then
      warn "ORÇAMENTO: rode evolve-skill.sh consolidate"
    fi
  fi

  # contrato antes/depois: a escrita do add só toca LEARNINGS.md (allowlist)
  if [ "$dry" = 0 ]; then
    guard_allowlist
  fi

  say "add: $added adicionada(s), $dup duplicada(s) ignorada(s)"
  return 0
}

# ---------------------------------------------------------------------------
# search
# ---------------------------------------------------------------------------

cmd_search() {
  local term="$1" found=0
  local tmp n i f
  local M_ID M_DATE M_TYPE M_CONF M_SRC M_STATUS M_TAGS M_TITLE
  local seen="" id
  if [ -f "$LEARNINGS" ]; then
    tmp="$TMPD/search"
    mkdir -p "$tmp"
    split_entries "$LEARNINGS" "$tmp"
    n=$(cat "$tmp/COUNT")
    for ((i = 1; i <= n; i++)); do
      f=$(printf '%s/%03d.entry' "$tmp" "$i")
      entry_valid_id "$f" || continue   # F6: blocos sem id válido (template) não entram no search
      if grep -qi "$term" "$f"; then
        IFS='|' read -r M_ID M_DATE M_TYPE M_CONF M_SRC M_STATUS M_TAGS M_TITLE <<< "$(entry_meta "$f")"
        id="$M_ID"
        if ! printf '%s\n' "$seen" | grep -Fqx -- "$id"; then
          seen="${seen}${id}"$'\n'
          printf '%s | %s | %s | %s | %s | %s\n' "$id" "$M_DATE" "$M_TYPE" "$M_CONF" "$M_SRC" "$M_TITLE"
          found=1
        fi
      fi
    done
  fi
  # prompts/ e SKILL.md: contexto bruto com arquivo:linha.
  local sf
  for sf in "$SKILL_HOME"/prompts/*.md "$SKILL_HOME/SKILL.md"; do
    [ -f "$sf" ] || continue
    while IFS= read -r line; do
      printf '%s: %s\n' "$(basename "$sf")" "$line"
      found=1
    done < <(grep -in "$term" "$sf")
  done
  [ "$found" = 1 ] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------

cmd_diff() {
  local stat=0
  if [ $# -gt 1 ]; then
    die "diff: aceita no máximo --stat"
  fi
  [ "${1:-}" = "--stat" ] && stat=1
  [ $# -eq 0 ] || [ "$1" = "--stat" ] || die "diff: opção desconhecida: $1"

  local -a paths=() a
  for a in "${ALLOWED_PATHS[@]}"; do
    case "$a" in
      */) [ -d "$SKILL_REPO/$a" ] && paths+=("$a") ;;
      *)  [ -e "$SKILL_REPO/$a" ] && paths+=("$a") ;;
    esac
  done
  if [ "$stat" = 1 ]; then
    git -C "$SKILL_REPO" diff HEAD --stat -- "${paths[@]}"
  else
    git -C "$SKILL_REPO" diff HEAD -- "${paths[@]}"
  fi
  # `git diff HEAD` não mostra arquivos NÃO RASTREADOS; os da allowlist entram no
  # próximo apply — listá-los evita um diff vazio enganoso após um `add`.
  local untracked
  untracked=$(git -C "$SKILL_REPO" ls-files --others --exclude-standard -- "${paths[@]}" 2>/dev/null || true)
  if [ -n "$untracked" ]; then
    if [ "$stat" = 1 ]; then
      printf '%s\n' "$untracked" | sed 's/^/novo (não rastreado): /'
    else
      printf '\n## Não rastreados (serão incluídos pelo apply):\n'
      printf '%s\n' "$untracked" | sed 's/^/  /'
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# apply / consolidate — validação e lock compartilhados
# ---------------------------------------------------------------------------

validate_scripts() { # 0 ok / 1 problemas (bash -n; shellcheck -S error se instalado)
  local changed untracked c
  changed=$(git -C "$SKILL_REPO" diff --name-only HEAD -- scripts/ 2>/dev/null || true)
  untracked=$(git -C "$SKILL_REPO" ls-files --others --exclude-standard -- scripts/ 2>/dev/null || true)
  local -a targets=() t
  while IFS= read -r c; do
    [ -n "$c" ] && [ "${c%.sh}" != "$c" ] && targets+=("$c")
  done <<< "$changed
$untracked"
  local -a uniq=() s
  for t in "${targets[@]}"; do
    case " ${uniq[*]} " in *" $t "*) ;; *) uniq+=("$t") ;; esac
  done
  if [ "${#uniq[@]}" -eq 0 ]; then
    say "  validação: nenhum scripts/*.sh novo/modificado"
    return 0
  fi
  local bad=0
  for s in "${uniq[@]}"; do
    say "  bash -n $s"
    if ! bash -n "$SKILL_REPO/$s" 2>&1; then
      err "erro de sintaxe em $s"
      bad=1
    fi
  done
  if command -v shellcheck >/dev/null 2>&1; then
    for s in "${uniq[@]}"; do
      say "  shellcheck -S error $s"
      if ! shellcheck -S error "$SKILL_REPO/$s" 2>&1; then
        err "shellcheck acusou problema em $s"
        bad=1
      fi
    done
  else
    warn "shellcheck não instalado — validação limitada a bash -n"
  fi
  [ "$bad" = 1 ] && return 1
  return 0
}

GIT_DIR_ABS=""
open_lock_fd() { # abre fd 9 no lock SEM redirecionar o stderr do processo (F3)
  if ! command -v flock >/dev/null 2>&1; then
    err "flock não disponível (util-linux) — não posso garantir exclusão mútua"
    return 1
  fi
  if [ -z "$GIT_DIR_ABS" ]; then
    GIT_DIR_ABS="$(git -C "$SKILL_REPO" rev-parse --absolute-git-dir 2>/dev/null || printf '%s/.git' "$SKILL_REPO")"
  fi
  LOCK_FILE="$GIT_DIR_ABS/evolve-skill.lock"
  if ! exec 9>>"$LOCK_FILE"; then
    err "não consegui abrir o lock $LOCK_FILE"
    return 1
  fi
  return 0
}

acquire_lock() { # flock EXCLUSIVO não-bloqueante em <gitdir>/evolve-skill.lock (apply/consolidate)
  open_lock_fd || return 1
  if ! flock -n 9; then
    err "outra execução (apply/consolidate/add) está em andamento — lock $LOCK_FILE ocupado"
    return 1
  fi
  return 0
}

wait_lock() { # flock EXCLUSIVO BLOQUEANTE (add — adds paralelos serializam, sem id duplicado)
  open_lock_fd || return 1
  flock 9 || { err "falha no flock de $LOCK_FILE"; return 1; }
  return 0
}

release_lock() { # libera o lock (fim do add); nunca redireciona stderr do processo
  flock -u 9 2>/dev/null || true
  exec 9>&- || true
}

changed_allowlist_paths() { # paths da allowlist com mudança real (working tree vs HEAD, incl. não rastreados)
  local -a paths=() a
  for a in "${ALLOWED_PATHS[@]}"; do
    case "$a" in
      */) [ -d "$SKILL_REPO/$a" ] && paths+=("$a") ;;
      *)  [ -e "$SKILL_REPO/$a" ] && paths+=("$a") ;;
    esac
  done
  {
    git -C "$SKILL_REPO" diff --name-only HEAD -- "${paths[@]}" 2>/dev/null || true
    git -C "$SKILL_REPO" ls-files --others --exclude-standard -- "${paths[@]}" 2>/dev/null || true
  } | sort -u
}

only_learnings_changed() { # F8: 0 se TODA mudança da allowlist é LEARNINGS.md/learnings_archive.md
  local changed c
  changed="$(changed_allowlist_paths)"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$c" in
      LEARNINGS.md|learnings_archive.md) ;;
      *) return 1 ;;
    esac
  done <<< "$changed"
  return 0
}

stage_allowlist_changed() { # F1: estágia APENAS paths da allowlist com mudança real no working tree
  local changed c
  local -a stage=()
  changed="$(changed_allowlist_paths)"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ -e "$SKILL_REPO/$c" ] || git -C "$SKILL_REPO" ls-files --error-unmatch -- "$c" >/dev/null 2>&1; then
      stage+=("$c")
    fi
  done <<< "$changed"
  if [ "${#stage[@]}" -gt 0 ]; then
    git -C "$SKILL_REPO" add -A -- "${stage[@]}" || die "falha no git add"
  fi
}

commit_and_report() { # <mensagem> — commit do que está staged + diff --stat
  local msg="$1"
  msg="${msg:0:72}"
  if git -C "$SKILL_REPO" diff --cached --quiet; then
    say "nada a commitar (sem mudanças nos paths da allowlist)"
    return 0
  fi
  git -C "$SKILL_REPO" commit --quiet -m "$msg" || die "falha no commit"
  say "commitado — $msg"
  git -C "$SKILL_REPO" show --stat --format='%h %s' HEAD
  return 0
}

switch_to_branch() { # <nome> — cria (se faltar) e entra no branch; nunca push
  local bname="$1"
  if git -C "$SKILL_REPO" rev-parse --verify --quiet "refs/heads/$bname" >/dev/null 2>&1; then
    git -C "$SKILL_REPO" checkout --quiet "$bname" || die "não consegui trocar para $bname"
  else
    git -C "$SKILL_REPO" checkout --quiet -b "$bname" || die "não consegui criar $bname"
  fi
  say "branch: $bname"
}

cmd_apply() {
  local direct=0 branch="" message="" a
  while [ $# -gt 0 ]; do
    case "$1" in
      --direct)    direct=1; shift ;;
      --branch)    [ $# -ge 2 ] || die "apply: --branch exige um nome"; branch="$2"; shift 2 ;;
      --branch=*)  branch="${1#--branch=}"; shift ;;
      --message)   [ $# -ge 2 ] || die "apply: --message exige um texto"; message="$2"; shift 2 ;;
      --message=*) message="${1#--message=}"; shift ;;
      *) die "apply: opção desconhecida: $1" ;;
    esac
  done
  [ "$direct" = 1 ] && [ -n "$branch" ] && die "apply: --direct e --branch são mutuamente exclusivos"

  say "apply: validando antes de commitar..."
  validate_scripts || die "apply: validação falhou — nada commitado"
  acquire_lock || exit 2
  guard_staged_allowlist || exit 4   # F1: staged fora da allowlist → aborta SEM tocar no índice
  guard_allowlist

  if [ "$direct" = 1 ]; then
    say "apply: commit direto no branch atual"
  elif [ -n "$branch" ]; then
    switch_to_branch "$branch"
  elif only_learnings_changed; then
    # F8: default inteligente — só LEARNINGS.md/learnings_archive.md mudaram → direto
    say "apply: apenas LEARNINGS.md/learnings_archive.md mudaram — commit direto no branch atual (default)"
  else
    switch_to_branch "evolve/$(date +%F)"
  fi

  stage_allowlist_changed

  local msg resumo nnew
  if [ -n "$message" ]; then
    msg="$message"
  else
    resumo=$(git -C "$SKILL_REPO" diff --cached HEAD -- LEARNINGS.md \
      | grep '^+## ' | grep -v '^+## Índice' | head -1 | sed 's/^+## *//')
    nnew=$(git -C "$SKILL_REPO" diff --cached HEAD -- LEARNINGS.md | grep -c '^+id: LEARN-' || true)
    if [ -n "$resumo" ]; then
      msg="evolve(learnings): ${nnew:-0} aprendizado(s) — $resumo"
    else
      msg="evolve(learnings): atualização de aprendizados"
    fi
  fi

  guard_staged_allowlist || exit 4   # F1: conferência final imediatamente antes do commit
  commit_and_report "$msg"
  guard_allowlist
  return 0
}

# ---------------------------------------------------------------------------
# consolidate
# ---------------------------------------------------------------------------

# Estado de trabalho: ORDER (índices de entradas que ficam), ARCHIVED (idx|motivo),
# ENT_DIR (pasta das entradas), NDUP/NSUP/NPRUNE/NBUDG (contadores do relatório).
ENT_DIR=""

load_meta() { # <índice> → popula M_ID M_DATE M_TYPE M_CONF M_SRC M_STATUS M_TAGS M_TITLE
  local idx="$1"
  IFS='|' read -r M_ID M_DATE M_TYPE M_CONF M_SRC M_STATUS M_TAGS M_TITLE \
    <<< "$(entry_meta "$ENT_DIR/$idx.entry")"
}

mark_superseded() { # <índice> <id-da-nova> <data-da-nova> — marca a antiga; NUNCA apaga
  local idx="$1" newid="$2" newdate="$3"
  local f="$ENT_DIR/$idx.entry"
  local title tmp
  title=$(sed -n 's/^## //p' "$f" | head -1)
  tmp="$TMPD/mark.$$"
  awk -v nid="$newid" -v nd="$newdate" -v t="$title" '
    /^status: /      { print "status: superseded"; next }
    /^supersedes: /  { print "supersedes: \"" nid "\""; next }
    /^## /           { print "## ~~" t "~~ (obsoleto " nd ": substituída por " nid ")"; next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

promotion_proposals() { # sobre o estado ORIGINAL; preenche PROPOSALS (anti-poisoning embutido)
  local -A groupdates=() groupsrc=()
  local idx key src cur
  for idx in "${ORDER[@]}"; do
    load_meta "$idx"
    [ "$M_STATUS" = "active" ] || continue
    key="$(normalize "$M_TITLE")|$M_TYPE"
    src="${M_SRC:-}"
    cur="${groupdates[$key]:-}"
    case "|$cur|" in
      *"|$M_DATE|"*) ;;
      *) groupdates[$key]="${cur:+$cur$'\n'}$M_DATE" ;;
    esac
    [ -n "${groupsrc[$key]:-}" ] || groupsrc[$key]="$src"
  done
  for idx in "${ORDER[@]}"; do
    load_meta "$idx"
    [ "$M_STATUS" = "active" ] || continue
    src="${M_SRC:-}"
    case "$src" in
      web|sub-agent|diff|model-output) continue ;;   # anti-poisoning: NUNCA candidatas
    esac
    key="$(normalize "$M_TITLE")|$M_TYPE"
    local ndates
    ndates=$(printf '%s\n' "${groupdates[$key]:-}" | sort -u | grep -c . || true)
    if [ "$src" = "user" ] || [ "$ndates" -ge 2 ]; then
      PROPOSALS+=("$M_ID|$M_TITLE|$M_TYPE|$src|$ndates")
    fi
  done
}

dedupe_pass() { # title+type iguais → mantém a mais nova; antigas vão para ARCHIVED
  local -A best=() bdate=()
  local idx key
  local -a neworder=()
  for idx in "${ORDER[@]}"; do
    load_meta "$idx"
    key="$(normalize "$M_TITLE")|$M_TYPE"
    if [ -z "${best[$key]:-}" ]; then
      best[$key]="$idx"
      bdate[$key]="$M_DATE"
      neworder+=("$idx")
    elif [ "$M_DATE" \> "${bdate[$key]:-}" ]; then
      # F2: a mais nova substitui a anterior — a ANTIGA SAI do ORDER (vai para o
      # learnings_archive.md) e não reaparece no LEARNINGS.md.
      ARCHIVED+=("${best[$key]}|duplicata de $idx ($M_TITLE)")
      NDUP=$((NDUP + 1))
      local -a no2=() x
      for x in "${neworder[@]}"; do
        [ "$x" != "${best[$key]}" ] && no2+=("$x")
      done
      neworder=("${no2[@]}")
      best[$key]="$idx"
      bdate[$key]="$M_DATE"
      neworder+=("$idx")
    else
      ARCHIVED+=("$idx|duplicata de ${best[$key]} ($M_TITLE)")
      NDUP=$((NDUP + 1))
    fi
  done
  ORDER=("${neworder[@]}")
}

supersede_pass() { # contradição: mesmo type + tags sobrepostas + título similar + datas diferentes → a mais nova vence
  local i j ia da ta taga tita
  for i in "${ORDER[@]}"; do
    load_meta "$i"
    ia="$M_ID"; da="$M_DATE"; ta="$M_TYPE"; taga="$M_TAGS"; tita="$M_TITLE"
    [ "$M_STATUS" = "active" ] || continue
    for j in "${ORDER[@]}"; do
      [ "$j" = "$i" ] && continue
      load_meta "$j"
      [ "$M_STATUS" = "active" ] || continue
      [ "$M_DATE" \< "$da" ] && continue   # j mais antigo que i → não supersede
      [ "$M_DATE" = "$da" ] && continue    # mesma data → empate indeterminado
      [ "$M_TYPE" != "$ta" ] && continue
      titles_similar "$M_TITLE" "$tita" || continue
      tags_overlap "$M_TAGS" "$taga" || continue
      mark_superseded "$i" "$M_ID" "$M_DATE"
      say "  superseded: $ia ($da) ← $M_ID ($M_DATE) [type=$ta, tags sobrepostas, título similar]"
      NSUP=$((NSUP + 1))
      break
    done
  done
}

prune_pass() { # type: fact + tags voláteis + mais de 90 dias → ARCHIVED (move, nunca apaga)
  local today cutoff idx lines
  today=$(date +%F)
  local -a neworder=()
  for idx in "${ORDER[@]}"; do
    load_meta "$idx"
    if [ "$M_STATUS" = "active" ] && [ "$M_TYPE" = "fact" ] && tags_volatile "$M_TAGS"; then
      if cutoff=$(date -d "$M_DATE + $VOLATILE_DAYS days" +%F 2>/dev/null); then
        if [ "$cutoff" \< "$today" ]; then
          ARCHIVED+=("$idx|fato volátil com mais de $VOLATILE_DAYS dias (tags: $M_TAGS)")
          NPRUNE=$((NPRUNE + 1))
          say "  arquivada (volátil): $M_ID — $M_TITLE ($M_DATE)"
          continue
        fi
      fi
    fi
    neworder+=("$idx")
  done
  ORDER=("${neworder[@]}")
}

budget_pass() { # entradas ativas > BUDGET_ACTIVE_LINES linhas → move as mais antigas para ARCHIVED
  local idx lines active=0 total=0
  for idx in "${ORDER[@]}"; do
    load_meta "$idx"
    lines=$(wc -l < "$ENT_DIR/$idx.entry")
    total=$((total + lines))
    [ "$M_STATUS" = "active" ] && active=$((active + lines))
  done
  if [ "$total" -gt "$BUDGET_TOTAL_LINES" ]; then
    warn "ORÇAMENTO: $total linhas totais (teto $BUDGET_TOTAL_LINES) — considere revisar o que é essencial"
  fi
  [ "$active" -le "$BUDGET_ACTIVE_LINES" ] && return 0
  local -a dates=() idx2
  for idx in "${ORDER[@]}"; do
    load_meta "$idx"
    [ "$M_STATUS" = "active" ] && dates+=("$M_DATE|$idx")
  done
  local sorted line didx
  sorted=$(printf '%s\n' "${dates[@]}" | sort -k1,1 -t'|' -s)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$active" -le "$BUDGET_ACTIVE_LINES" ] && break
    didx="${line#*|}"
    load_meta "$didx"
    lines=$(wc -l < "$ENT_DIR/$didx.entry")
    ARCHIVED+=("$didx|orçamento (entradas ativas acima de $BUDGET_ACTIVE_LINES linhas)")
    NBUDG=$((NBUDG + 1))
    say "  arquivada (orçamento): $M_ID — $M_TITLE ($M_DATE)"
    local -a no2=()
    for idx2 in "${ORDER[@]}"; do
      [ "$idx2" != "$didx" ] && no2+=("$idx2")
    done
    ORDER=("${no2[@]}")
    active=$((active - lines))
  done <<< "$sorted"
}

rebuild_learnings() { # <novo-arquivo> — header preservado (comentários + TEMPLATE em
  # code fence, descartando só as linhas antigas de índice) + índice novo + entradas
  local out="$1" header idx pre post o ititle
  header=$(cat "$ENT_DIR/HEADER")
  idx=$(printf '%s\n' "$header" | grep -n '^## Índice$' | head -1 | cut -d: -f1)
  if [ -n "$idx" ]; then
    pre=$(printf '%s\n' "$header" | sed -n "1,${idx}p")
    # F6: preserva o que vier DEPOIS do '## Índice' no header — comentários HTML
    # e o TEMPLATE em code fence (documentação de formato) — descartando apenas
    # as linhas antigas de ÍNDICE ('- AAAA-MM-DD | ... [id: LEARN-...]'),
    # regeneradas abaixo. (Filtro restrito ao formato do índice: linhas '- ...'
    # do template, como '- **Observação:**', são preservadas.)
    post=$(printf '%s\n' "$header" | sed -n "$((idx + 1)),\$p" | grep -vE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} \| .*\[id: LEARN-')
  else
    pre="$header"
    post=""
  fi
  # remove linhas em branco no início/fim do bloco pós-índice
  post=$(printf '%s\n' "$post" | awk 'NF{p=1} p' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
  {
    printf '%s\n' "$pre"
    for o in "${ORDER[@]}"; do
      load_meta "$o"
      ititle=$(sed -n 's/^## //p' "$ENT_DIR/$o.entry" | head -1)
      printf '%s\n' "- $M_DATE | $M_TYPE | $ititle [id: $M_ID]"
    done
    printf '\n'
    if [ -n "$post" ]; then
      printf '%s\n' "$post"
      printf '\n'
    fi
    local first=1
    for o in "${ORDER[@]}"; do
      if [ "$first" = 1 ]; then first=0; else printf '\n'; fi
      cat "$ENT_DIR/$o.entry"
    done
  } > "$out"
}

cmd_consolidate() {
  local apply=0 dry=1 a
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply)   apply=1; dry=0; shift ;;
      --dry-run) dry=1; shift ;;
      *) die "consolidate: opção desconhecida: $1" ;;
    esac
  done

  [ -f "$LEARNINGS" ] || { say "consolidate: LEARNINGS.md ainda não existe — nada a consolidar"; return 0; }

  if [ "$apply" = 1 ]; then
    acquire_lock || exit 2
    guard_staged_allowlist || exit 4   # F1: staged fora da allowlist → aborta SEM tocar no índice
    validate_scripts || die "consolidate: validação falhou — nada commitado"
    guard_allowlist
  fi

  local work="$TMPD/consolidate" n
  ENT_DIR="$work/entries"
  rm -rf "$work"
  mkdir -p "$ENT_DIR"
  split_entries "$LEARNINGS" "$ENT_DIR"
  n=$(cat "$ENT_DIR/COUNT")
  [ "$n" -eq 0 ] && { say "consolidate: nenhuma entrada encontrada"; return 0; }

  ORDER=()
  local i nvalid=0 f
  for ((i = 1; i <= n; i++)); do
    f=$(printf '%03d' "$i")
    entry_valid_id "$ENT_DIR/$f.entry" || continue   # F6: blocos sem id válido (template) não entram
    ORDER+=("$f")
    nvalid=$((nvalid + 1))
  done

  say "consolidate: $nvalid entrada(s) lidas de $LEARNINGS"
  [ "$nvalid" -eq 0 ] && { say "consolidate: nenhuma entrada válida encontrada"; return 0; }

  # FASE 1: propostas de promoção — sobre o estado ORIGINAL, antes de qualquer
  # transformação (o dedupe colapsaria as ≥2 ocorrências num só registro).
  promotion_proposals
  if [ "${#PROPOSALS[@]}" -gt 0 ]; then
    say "PROPOSTAS DE PROMOÇÃO (nunca aplicadas — exigem revisão humana + diff):"
    local pr PID PTITLE PTYPE PSRC PND
    for pr in "${PROPOSALS[@]}"; do
      IFS='|' read -r PID PTITLE PTYPE PSRC PND <<< "$pr"
      say "  promover para o corpo da skill (SKILL.md/prompts): $PID — $PTITLE (type=$PTYPE, source=$PSRC, $PND ocorrência(s) em datas distintas)"
    done
  else
    say "propostas de promoção: nenhuma"
  fi

  # FASE 2: dedupe (title+type iguais → mantém a mais nova)
  dedupe_pass
  # FASE 3: supersessão de contradições
  supersede_pass
  # FASE 4: poda de voláteis
  prune_pass
  # FASE 5: orçamento (ativas > 100 linhas → move as mais antigas)
  budget_pass

  say "consolidate: $NDUP duplicata(s) arquivada(s) · $NSUP superseded · $NPRUNE volátil(is) podada(s) · $NBUDG movida(s) por orçamento"

  # Monta o novo LEARNINGS.md
  local newfile="$work/LEARNINGS.new"
  rebuild_learnings "$newfile"

  if [ "$dry" = 1 ]; then
    say "consolidate: dry-run — nada foi alterado. Diff:"
    diff -u "$LEARNINGS" "$newfile" || true
    return 0
  fi

  # ---- apply: escreve arquivos e commita ----
  guard_allowlist
  cp "$newfile" "$LEARNINGS" || die "consolidate: falha ao gravar LEARNINGS.md"
  local marker adx aidx areason
  if [ "${#ARCHIVED[@]}" -gt 0 ]; then
    [ -f "$ARCHIVE" ] || printf '%s\n' "$ARCHIVE_HEADER" > "$ARCHIVE"
    for adx in "${ARCHIVED[@]}"; do
      aidx="${adx%%|*}"
      areason="${adx#*|}"
      marker="<!-- evolve-skill consolidate: arquivada em $(date +%F) — $areason -->"
      {
        printf '\n%s\n' "$marker"
        cat "$ENT_DIR/$aidx.entry"
        printf '\n'
      } >> "$ARCHIVE"
    done
    say "consolidate: $((${#ARCHIVED[@]})) entrada(s) movida(s) para $(basename "$ARCHIVE")"
  fi
  guard_allowlist
  guard_staged_allowlist || exit 4   # F1: conferência final imediatamente antes do commit

  switch_to_branch "evolve/consolidacao-$(date +%F)"
  stage_allowlist_changed
  commit_and_report "evolve(learnings): consolidação de aprendizados"
  guard_allowlist
  return 0
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

cmd_status() {
  local branch version
  branch=$(git -C "$SKILL_REPO" symbolic-ref --short HEAD 2>/dev/null || printf '(detached)')
  version=$(sed -n 's/^  version: *"\([^"]*\)".*/\1/p' "$SKILL_HOME/SKILL.md" | head -1)
  [ -n "$version" ] || version='?'
  say "SKILL_REPO  : $SKILL_REPO"
  say "SKILL_HOME  : $SKILL_HOME"
  say "branch      : $branch"
  say "versão      : $version"
  if [ -f "$LEARNINGS" ]; then
    local TE TA TS TL AL LAST
    read -r TE TA TS TL AL LAST <<< "$(learnings_stats)"
    say "entradas    : $TE (ativas $TA · superseded $TS)"
    say "linhas      : $TL totais (teto $BUDGET_TOTAL_LINES) · $AL em entradas ativas (teto $BUDGET_ACTIVE_LINES)"
    say "última data : ${LAST:-—}"
    if [ "$AL" -gt "$BUDGET_ACTIVE_LINES" ] || [ "$TL" -gt "$BUDGET_TOTAL_LINES" ]; then
      warn "ORÇAMENTO: rode evolve-skill.sh consolidate"
    fi
  else
    say "entradas    : 0 (LEARNINGS.md ainda não existe)"
    say "linhas      : —"
    say "última data : —"
  fi
  local eb
  eb=$(git -C "$SKILL_REPO" for-each-ref --format='%(refname:short)' 'refs/heads/evolve/*' | sort)
  if [ -n "$eb" ]; then
    say "evolve/*    :"
    printf '%s\n' "$eb" | sed 's/^/  /'
  else
    say "evolve/*    : (nenhuma)"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
  '')          usage >&2; exit 2 ;;
  -h|--help|help) usage; exit 0 ;;
  add)         shift; cmd_add "$@" ;;
  search)      shift; [ $# -eq 1 ] || die "search: aceita exatamente um termo"; cmd_search "$1" ;;
  diff)        shift; cmd_diff "$@" ;;
  apply)       shift; cmd_apply "$@" ;;
  consolidate) shift; cmd_consolidate "$@" ;;
  status)      shift; cmd_status "$@" ;;
  *)           die "subcomando desconhecido: ${1:-}" ;;
esac
