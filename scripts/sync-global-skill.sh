#!/usr/bin/env bash
# =============================================================================
# sync-global-skill.sh — publica ESTA skill para todos os agentes da máquina
# -----------------------------------------------------------------------------
# O problema: cada agente lê skills de um lugar diferente, e alguns IMPORTAM POR
# CÓPIA. Uma cópia congela a versão do dia da importação — verificado nesta
# máquina: ~/.jcode/skills/deep-orchestrator-agent-skill estava em 3.1.0 enquanto a skill
# viva já estava em 3.4.0. Rodar a skill por lá executava um orquestrador de
# duas versões atrás, sem as fases novas. Este script substitui cópia por
# SYMLINK, e symlink não envelhece.
#
# Ele é chamado pelo hook SessionStart do Claude Code (settings.json) e pode ser
# rodado à mão a qualquer momento. É idempotente e NUNCA falha uma sessão:
# sai 0 mesmo quando não consegue sincronizar algo (use --strict para inverter).
#
# Uso:
#   sync-global-skill.sh [--quiet] [--dry-run] [--strict]
#
# Destinos (só os que JÁ existem — nenhum agente é "instalado" por aqui):
#   ~/.claude/skills/            Claude Code   (respeita $CLAUDE_CONFIG_DIR)
#   ~/.agents/skills/            pi · jcode · opencode (raiz comum)
#   ~/.jcode/skills/             jcode  (importa por CÓPIA — o caso que dói)
#   ~/.pi/agent/skills/          pi     (skills globais, sempre confiáveis)
#
# GARANTIAS DE SEGURANÇA — este script mexe em $HOME, então:
#   • toca EXCLUSIVAMENTE a entrada <destino>/deep-orchestrator-agent-skill; nenhuma outra
#     skill do usuário é lida, movida ou apagada;
#   • se o destino JÁ É a casa da skill (quem clonou direto em
#     ~/.claude/skills/deep-orchestrator-agent-skill), não faz nada: sem essa guarda, o
#     script moveria a skill viva e criaria um link para si mesma (ELOOP),
#     em silêncio, a partir de um hook;
#   • um symlink só é dado como bem-sucedido depois de LER através dele
#     (<destino>/scripts precisa existir); caso contrário a cópia é restaurada;
#   • só substitui um diretório depois de CONFIRMAR que ele é uma cópia desta
#     mesma skill (tem SKILL.md com `name: deep-orchestrator-agent-skill`). Qualquer outra
#     coisa é preservada e reportada — nunca há rm -rf às cegas;
#   • não cria o diretório-pai de um agente que não existe: quem não usa jcode
#     não ganha um ~/.jcode;
#   • a cópia substituída é preservada em <destino>/deep-orchestrator-agent-skill.bak-<data>
#     na primeira vez, para que nada seja destruído sem rede de segurança.
#
# Exit codes:
#   0 = sempre, exceto com --strict
#   1 = --strict e algum destino falhou
#   2 = erro de uso, ou a casa da skill não pôde ser resolvida
# =============================================================================

set -uo pipefail

SKILL_NAME="deep-orchestrator-agent-skill"
QUIET=0
DRY_RUN=0
STRICT=0

for a in "$@"; do
  case "$a" in
    --quiet)   QUIET=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --strict)  STRICT=1 ;;
    -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'sync-global-skill.sh: opção desconhecida: %s\n' "$a" >&2; exit 2 ;;
  esac
done

say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# --- casa da skill: resolvida pela localização deste script, nunca adivinhada -
_self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)
[ -n "$_self_dir" ] || { warn "sync-global-skill.sh: não consegui resolver o próprio diretório"; exit 2; }
SKILL_HOME=$(cd "$_self_dir/.." && pwd -P 2>/dev/null || true)
[ -n "$SKILL_HOME" ] && [ -d "$SKILL_HOME/scripts" ] \
  || { warn "sync-global-skill.sh: SKILL_HOME inválido ($SKILL_HOME)"; exit 2; }

# O alvo do link é o diretório que CONTÉM o SKILL.md. Nesta skill o SKILL.md da
# raiz é um symlink para .claude/skills/deep-orchestrator-agent-skill/SKILL.md, e é a raiz
# que carrega scripts/ e prompts/ — então a raiz é o alvo certo.
SOURCE="$SKILL_HOME"
[ -e "$SOURCE/SKILL.md" ] \
  || { warn "sync-global-skill.sh: $SOURCE/SKILL.md não existe — nada a publicar"; exit 2; }

VERSION=$(sed -n 's/^  version: *"\([^"]*\)".*/\1/p' "$SOURCE/SKILL.md" 2>/dev/null | head -1)

FAILED=0
STAMP=$(date +%Y%m%d-%H%M%S)

# is_this_skill <dir> → 0 se o diretório é (uma cópia d)esta skill.
# É a guarda que separa "cópia velha minha, pode trocar" de "coisa do usuário,
# não encoste".
is_this_skill() {
  local d="$1" f
  for f in "$d/SKILL.md" "$d/.claude/skills/$SKILL_NAME/SKILL.md"; do
    [ -f "$f" ] && grep -qx "name: $SKILL_NAME" "$f" 2>/dev/null && return 0
  done
  return 1
}

# link_into <diretório-de-skills> <rótulo>
link_into() {
  # Três `local` separados: numa mesma declaração o valor de `dir` ainda não
  # está visível para `dest` (SC2318) e o `set -u` estoura com "unbound".
  local dir="$1"
  local label="$2"
  local dest="$dir/$SKILL_NAME"

  # Diretório-pai ausente = agente não instalado. Não criamos nada: quem não
  # usa jcode não deve ganhar um ~/.jcode por efeito colateral de um hook.
  if [ ! -d "$dir" ]; then
    say "  $label: ausente — pulando (agente não instalado)"
    return 0
  fi

  # Já é o symlink certo? Nada a fazer.
  if [ -L "$dest" ]; then
    local cur
    cur=$(cd "$(dirname "$dest")" && readlink "$dest" 2>/dev/null || true)
    local resolved
    resolved=$(cd "$dest" 2>/dev/null && pwd -P || true)
    if [ "$resolved" = "$SOURCE" ]; then
      say "  $label: OK (symlink já aponta para a casa da skill)"
      return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
      say "  $label: [dry-run] repontaria o symlink ($cur → $SOURCE)"
      return 0
    fi
    if ln -sfn "$SOURCE" "$dest" 2>/dev/null && [ -d "$dest/scripts" ]; then
      say "  $label: symlink repontado ($cur → $SOURCE)"
    else
      warn "  $label: FALHA ao repontar o symlink para algo utilizável"
      FAILED=1
    fi
    return 0
  fi

  # Existe e NÃO é symlink: é cópia, é a própria casa, ou é coisa do usuário.
  if [ -e "$dest" ]; then
  # O DESTINO É A PRÓPRIA CASA DA SKILL? Não encoste.
  # Este é o caso do README: quem instala clonando direto em
  # ~/.claude/skills/deep-orchestrator-agent-skill (ou em ~/.agents/skills/...) faz
  # dest == SOURCE. Sem esta guarda, o ramo de "cópia antiga" moveria a skill
  # VIVA para .bak-<data> e criaria um symlink apontando para o caminho que
  # acabou de esvaziar: um link para si mesmo. O `ln` teria sucesso, o rollback
  # nunca dispararia, o script sairia 0 dizendo "CÓPIA -> symlink" — e o
  # diretório viraria ELOOP, ilegível para TODOS os agentes. Como isto roda num
  # hook SessionStart com --quiet, aconteceria em silêncio.
  # A checagem é por realpath, e por isso vem DEPOIS do ramo de symlink: um
  # symlink CORRETO também resolve para $SOURCE (o `cd` o atravessa), e seria
  # anunciado como "é a própria casa" — mensagem errada para o caso mais comum.
  # Aqui $dest já é garantidamente não-symlink.
  local dest_real
  dest_real=$(cd "$dest" 2>/dev/null && pwd -P || true)
  if [ -n "$dest_real" ] && [ "$dest_real" = "$SOURCE" ]; then
    say "  $label: OK (o destino É a própria casa da skill — nada a fazer)"
    return 0
  fi

    if [ ! -d "$dest" ]; then
      warn "  $label: $dest existe e não é diretório nem symlink — PRESERVADO, resolva à mão"
      FAILED=1
      return 0
    fi
    if ! is_this_skill "$dest"; then
      warn "  $label: $dest é um diretório que NÃO parece ser esta skill — PRESERVADO"
      warn "         (nenhum SKILL.md com 'name: $SKILL_NAME'). Nada foi apagado."
      FAILED=1
      return 0
    fi
    local old_version
    old_version=$(sed -n 's/^  version: *"\([^"]*\)".*/\1/p' "$dest/SKILL.md" 2>/dev/null | head -1)
    if [ "$DRY_RUN" = 1 ]; then
      say "  $label: [dry-run] trocaria a CÓPIA ${old_version:-<sem versão>} por symlink → ${VERSION:-?}"
      return 0
    fi
    local bak="$dest.bak-$STAMP"
    if mv -- "$dest" "$bak" 2>/dev/null; then
      # `ln` ter sucesso NÃO prova que o link é utilizável: um link para um
      # caminho inexistente, ou para si mesmo, também "sucede". A prova é ler
      # através dele.
      if ln -sfn "$SOURCE" "$dest" 2>/dev/null && [ -d "$dest/scripts" ] && [ -e "$dest/SKILL.md" ]; then
        say "  $label: CÓPIA ${old_version:-<sem versão>} → symlink ${VERSION:-?} (cópia antiga em $(basename "$bak"))"
      else
        rm -f -- "$dest" 2>/dev/null       # tira o link quebrado do caminho
        mv -- "$bak" "$dest" 2>/dev/null   # desfaz: melhor a cópia velha que nada
        warn "  $label: FALHA ao criar um symlink utilizável — cópia antiga RESTAURADA"
        FAILED=1
      fi
    else
      warn "  $label: FALHA ao mover a cópia antiga — nada mudou"
      FAILED=1
    fi
    return 0
  fi

  # Não existe: criar.
  if [ "$DRY_RUN" = 1 ]; then
    say "  $label: [dry-run] criaria o symlink → $SOURCE"
    return 0
  fi
  if ln -sfn "$SOURCE" "$dest" 2>/dev/null && [ -d "$dest/scripts" ]; then
    say "  $label: symlink criado"
  else
    rm -f -- "$dest" 2>/dev/null
    warn "  $label: FALHA ao criar um symlink utilizável"
    FAILED=1
  fi
}

say "sync-global-skill.sh — publicando $SKILL_NAME ${VERSION:+v$VERSION}"
say "  casa da skill: $SOURCE"
[ "$DRY_RUN" = 1 ] && say "  (dry-run: nada será alterado)"

# CLAUDE_CONFIG_DIR existe e é usado: hardcodar ~/.claude erra em quem o define.
link_into "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" "claude-code"
link_into "$HOME/.agents/skills"                        "agents (pi/jcode/opencode)"
link_into "$HOME/.jcode/skills"                         "jcode"
link_into "$HOME/.pi/agent/skills"                      "pi"

if [ "$FAILED" = 1 ]; then
  warn "sync-global-skill.sh: um ou mais destinos não foram sincronizados (nada foi destruído)."
  [ "$STRICT" = 1 ] && exit 1
fi
exit 0
