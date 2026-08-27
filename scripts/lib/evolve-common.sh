# =============================================================================
# evolve-common.sh — validadores e parsers COMPARTILHADOS do formato de bloco
# -----------------------------------------------------------------------------
# Fonte única de verdade do formato de candidato/aprendizado usado por:
#   • scripts/do-prefs.sh        — memória consultiva em .deep-orchestrator-preferences/
#   • scripts/evolution-survey.sh — questionário de evolução pós-execução
#   • scripts/evolve-skill.sh    — search/status/diff/apply do corpo da skill
#
# Esta lib é SOURCEADA (`. "$SCRIPT_DIR/lib/evolve-common.sh"`) e só DEFINE
# funções — nunca executa nada por conta própria. Compatível com bash 3.2
# (macOS): sem namerefs, sem arrays associativos, sem readlink -f.
#
# Formato de bloco (candidato):
#   ---
#   title: "..."          (ou linha '## <título>' no corpo)
#   type: correction|fact|antipattern|gotcha|convention
#   confidence: high|medium|low
#   source: user|repo-doc|sub-agent|web|diff|model-output
#   tags: [a, b]
#   scope: project|global          (obrigatório desde v3.8.0)
#   key: P001                      (opcional — só questionário/propostas)
#   observacao: "..."   (ou corpo '- **Observação:** ...')
#   acao: "..."         (ou corpo '- **Ação:** ...')
#   contract: cmd1, cmd2           (opcional, preservado)
#   ---
#
# Formato de bloco (ARMAZENADO — o que do-prefs.sh grava):
#   mesmo frontmatter + 'id: P-YYYYMMDD-NNN' + 'status: active|pending' +
#   'supersedes: ""' + corpo com '## <título>' e linhas '- **Observação:**'/
#   '- **Ação:**'. O id é SEMPRE atribuído pelo script (nunca confia no input).
# =============================================================================

# --- normalize: "$@" → minúsculas, só alfanuméricos, espaços simples ----------
normalize() {
  printf '%s' "$*" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' \
    | sed 's/^ *//; s/ *$//; s/  */ /g'
}

# --- entry_field: <arquivo> <campo> → valor da primeira linha 'campo: valor' --
entry_field() {
  local f="$1" k="$2"
  sed -n "s/^$k: *//p" "$f" | head -1
}

# --- secret_scan: <texto> → 0 se parece conter CREDENCIAL ---------------------
# Só padrões de CREDENCIAL disparam: keyword + separador '=' ou ':' + valor,
# ou cabeçalho de chave privada. Palavras soltas ("token de", "o token",
# "password do") NÃO disparam. O valor capturado nunca é impresso.
secret_scan() {
  printf '%s\n' "$1" | grep -Eiq \
    '(access[_-]?token|auth[_-]?token|api[_-]?key|secret|password|passwd)[=:][[:space:]]*[^[:space:]]|BEGIN[[:space:]_-]+(RSA|OPENSSH|EC|DSA)[[:space:]_-]+PRIVATE[[:space:]_-]+KEY'
}

# --- tags_list: "[a, b]" → uma tag por linha ----------------------------------
tags_list() {
  printf '%s' "$1" | tr -d '[]' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true
}

# --- parse_fields: <bloco> → popula B_* (globais) -----------------------------
# Aceita as DUAS formas de Observação/Ação/Título (frontmatter OU corpo do
# TEMPLATE). Se ambas presentes, o frontmatter vence. Múltiplas linhas de corpo
# '- **Observação:**' / '- **Ação:**' são JUNTADAS por espaço — nenhuma é
# descartada.
parse_fields() {
  local block="$1" line key val
  local obs_src="" acao_src=""   # "" | frontmatter | body
  B_TITLE=""; B_TYPE=""; B_CONFIDENCE=""; B_SOURCE=""; B_TAGS=""; B_OBS=""; B_ACAO=""; B_CONTRACT=""; B_SCOPE=""; B_KEY=""
  while IFS= read -r line; do
    case "$line" in
      ''|'---') continue ;;
    esac
    if printf '%s\n' "$line" | grep -q '^- \*\*Observação:\*\*'; then
      if [ -z "$obs_src" ] || [ "$obs_src" = "body" ]; then
        B_OBS="${B_OBS:+$B_OBS }$(printf '%s\n' "$line" | sed 's/^- \*\*Observação:\*\* *//')"
        obs_src="body"
      fi
      continue
    fi
    if printf '%s\n' "$line" | grep -q '^- \*\*Ação:\*\*'; then
      if [ -z "$acao_src" ] || [ "$acao_src" = "body" ]; then
        B_ACAO="${B_ACAO:+$B_ACAO }$(printf '%s\n' "$line" | sed 's/^- \*\*Ação:\*\* *//')"
        acao_src="body"
      fi
      continue
    fi
    case "$line" in
      '## '*) [ -z "$B_TITLE" ] && B_TITLE="${line#'## '}" ;;
      *:*)
        key="${line%%:*}"
        val="${line#*:}"
        val="${val# }"
        # Um nível de aspas ao redor é do FORMATO DE EXEMPLO (ex.:
        # title: "Título") — não é conteúdo.
        case "$val" in
          '"'*'"') val="${val#\"}"; val="${val%\"}" ;;
        esac
        case "$key" in
          title)       B_TITLE="$val" ;;
          type)        B_TYPE="$val" ;;
          confidence)  B_CONFIDENCE="$val" ;;
          source)      B_SOURCE="$val" ;;
          tags)        B_TAGS="$val" ;;
          scope)       B_SCOPE="$val" ;;
          key)         B_KEY="$val" ;;
          observacao)  B_OBS="$val"; obs_src="frontmatter" ;;
          acao)        B_ACAO="$val"; acao_src="frontmatter" ;;
          contract)    B_CONTRACT="$val" ;;
        esac ;;
    esac
  done <<< "$block"
}

# --- validate_candidate: <índice> <bloco> — erros em stderr; 0 válido ---------
# Campos obrigatórios: title, type, confidence, source, scope, observacao,
# acao. Enums: type/confidence/source/scope. Secret scan. NUNCA imprime valores
# de segredo.
validate_candidate() {
  local i="$1" blk="$2" ok=1 label
  label="${B_TITLE:-<sem título>}"
  local -a missing=()
  [ -z "$B_TITLE" ]      && missing+=("title")
  [ -z "$B_TYPE" ]       && missing+=("type")
  [ -z "$B_CONFIDENCE" ] && missing+=("confidence")
  [ -z "$B_SOURCE" ]     && missing+=("source")
  [ -z "$B_SCOPE" ]      && missing+=("scope")
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
  if [ -n "$B_SCOPE" ]; then
    case "$B_SCOPE" in
      project|global) ;;
      *) err "candidato #$i '$label' REJEITADO: scope inválido '$B_SCOPE' (project|global)"; ok=0 ;;
    esac
  fi
  if secret_scan "$blk"; then
    err "candidato #$i REJEITADO: possível segredo detectado (api key/secret/password/token/chave privada) — valor NÃO exibido"
    ok=0
  fi
  [ "$ok" = 1 ] && return 0
  return 1
}

# --- read_candidates: <arquivo> → popula CANDIDATES/NBLK (globais) ------------
# Quebra o input em blocos separados por '---'. Um bloco de CORPO do formato
# TEMPLATE (começa com '## ' ou '- **') é continuação do candidato anterior
# APENAS se este ainda NÃO tem corpo (linhas '- **Observação:**' /
# '- **Ação:**'). Se o anterior JÁ tem corpo, o bloco é candidato NOVO. Blocos
# vazios (só espaços) não viram candidato. Nada é descartado.
read_candidates() {
  local input="$1" line cur="" idx=0 nblk=0
  CANDIDATES=(); NBLK=0
  flush_block() {
    cur="${cur#$'\n'}"
    if printf '%s\n' "$cur" | grep -q '[^[:space:]]'; then
      case "$cur" in
        '## '*|'- **'*)
          if [ "$nblk" -gt 0 ]; then
            if ! printf '%s\n' "${CANDIDATES[$((nblk - 1))]:-}" | grep -qE '^- \*\*(Observação|Ação):\*\*'; then
              CANDIDATES[$((nblk - 1))]+=$'\n'"$cur"
              cur=""
              return
            fi
          fi ;;
      esac
      CANDIDATES+=("$cur")
      nblk=$((nblk + 1))
    fi
    cur=""
  }
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "---" ]; then
      flush_block
    else
      cur+=$'\n'"$line"
    fi
  done < "$input"
  flush_block
  NBLK=$nblk
}

# --- split_entries: <arquivo> <dir> — parte um arquivo de blocos --------------
#   • <dir>/HEADER  → tudo antes da primeira entrada
#   • <dir>/NNN.entry (001, 002, ...) → uma entrada completa
#   • <dir>/COUNT   → número de entradas
# Uma entrada tem exatamente duas linhas '---' (antes do frontmatter e entre o
# frontmatter e o corpo); a terceira '---' já abre a entrada seguinte. Por isso
# alternamos: '---' ímpar = início de entrada, '---' par = fronteira
# frontmatter/corpo. Linhas dentro de code fences NUNCA são fronteira.
split_entries() {
  local src="$1" dst="$2" line
  local n=0 idx=0 cur="" header="" infence=0
  mkdir -p "$dst" || return 1
  : > "$dst/HEADER"
  : > "$dst/COUNT"
  while IFS= read -r line || [ -n "$line" ]; do
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

# --- entry_valid_id: <arquivo> → 0 se id válido (LEARN- ou P-YYYYMMDD-NNN) ---
entry_valid_id() {
  grep -Eq '^id: (LEARN|P)-[0-9]{8}-[0-9]{3}$' "$1"
}

# --- entry_meta: <arquivo> → 'id|date|type|confidence|source|status|tags|title'
entry_meta() {
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

# --- next_id_for: <prefixo> <arquivo> → <PREFIXO>-YYYYMMDD-NNN ---------------
# SÓ linhas 'id: <PREFIXO>-<hoje>-...' fora de code fences contam; exemplos em
# comentários/placeholders nunca deslocam a numeração.
next_id_for() {
  local prefix="$1" target="$2" today n line num infence=0
  today=$(date +%Y%m%d)
  n=0
  if [ -f "$target" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        '```'*) if [ "$infence" = 1 ]; then infence=0; else infence=1; fi ;;
      esac
      [ "$infence" = 1 ] && continue
      case "$line" in
        "id: $prefix-$today-"*)
          num="${line#id: $prefix-$today-}"
          num="${num%%[!0-9]*}"
          if [ -n "$num" ] && [ "$num" -gt "$n" ] 2>/dev/null; then
            n="$num"
          fi
          ;;
      esac
    done < "$target"
  fi
  # 10# força base decimal: um id existente '008' seria lido como octal e
  # estouraria a aritmética do bash.
  n=$((10#${n:-0} + 1))
  printf '%s-%s-%03d\n' "$prefix" "$today" "$n"
}

# --- is_untrusted_source / is_trusted_source ----------------------------------
is_untrusted_source() { # <source> → 0 se UNTRUSTED (web|sub-agent|diff|model-output)
  case "$1" in web|sub-agent|diff|model-output) return 0 ;; esac
  return 1
}

is_trusted_source() { # <source> → 0 se confiável (user|repo-doc)
  case "$1" in user|repo-doc) return 0 ;; esac
  return 1
}
