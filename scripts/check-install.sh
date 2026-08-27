#!/usr/bin/env bash
# =============================================================================
# check-install.sh — prova de que UMA INSTALAÇÃO da skill está COMPLETA
# -----------------------------------------------------------------------------
# O contrato de instalação do deep-orchestrator-agent-skill: a CASA DA SKILL
# ($SKILL_HOME) é o diretório que CONTÉM SKILL.md e precisa carregar:
#   • scripts/   — as ferramentas executáveis do ciclo de orquestração
#                  (do-context.sh é o mínimo para a FASE 0 não abortar);
#   • prompts/   — os templates de prompt (ECC, busca, portão).
# Uma instalação incompleta (ex.: só o SKILL.md, sem scripts/) faz a FASE 0
# abortar com "PARE: do-context.sh nao encontrado". Este script detecta esse
# estado ANTES de qualquer execução.
#
# Layout aceito (qualquer um dos dois resolvidos como $SKILL_HOME):
#   • a RAIZ do repositório (SKILL.md real ou symlink + scripts/ + prompts/),
#     que pode ser o alvo de uma instalação manual por symlink; ou
#   • a pasta .claude/skills/deep-orchestrator-agent-skill/ (padrão Claude
#     Code), que espelha scripts/ e prompts/ por symlink para a
#     raiz — também é uma casa válida desde a v3.5.1.
#
# Uso:
#   check-install.sh [--root <dir>] [--json] [--quiet]
#     --root <dir>  verifica <dir> como casa da skill; default: a própria casa
#                   desta execução (o pai do diretório deste script).
#     --json        saída em JSON (uma linha, parseável).
#     --quiet       só o exit code (0 completo · 1 faltando · 2 erro de uso).
#
# Exit codes:
#   0 = instalação COMPLETA (SKILL.md + ferramentas + prompts)
#   1 = instalação INCOMPLETA (itens faltando listados na saída)
#   2 = erro de uso / raiz inválida
# =============================================================================

set -uo pipefail

SKILL_NAME="deep-orchestrator-agent-skill"
ROOT=""
JSON=0
QUIET=0

for a in "$@"; do
  case "$a" in
    --root) ROOT="__NEXT__" ;;
    --json) JSON=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      if [ "$ROOT" = "__NEXT__" ]; then ROOT="$a"; else
        printf 'check-install.sh: opção desconhecida: %s\n' "$a" >&2; exit 2
      fi ;;
  esac
done

[ "$ROOT" = "__NEXT__" ] && { printf 'check-install.sh: --root exige um diretório\n' >&2; exit 2; }

if [ -z "$ROOT" ]; then
  _self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null || true)
  ROOT=$(cd "$_self_dir/.." && pwd -P 2>/dev/null || true)
fi

declare -a MISSING=()
check() { # check <descrição> <path> [x|f|d]
  local desc="$1" p="$2" kind="${3:-e}"
  local ok=0
  case "$kind" in
    x) [ -x "$p" ] && ok=1 ;;
    d) [ -d "$p" ] && ok=1 ;;
    *) [ -e "$p" ] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    [ "$QUIET" = 0 ] && [ "$JSON" = 0 ] && printf '  [OK]    %s (%s)\n' "$desc" "$p"
  else
    MISSING+=("$desc")
    [ "$QUIET" = 0 ] && [ "$JSON" = 0 ] && printf '  [FALTA] %s (%s)\n' "$desc" "$p" >&2
  fi
}

if [ ! -d "$ROOT" ]; then
  printf 'check-install.sh: raiz não existe: %s\n' "$ROOT" >&2
  exit 2
fi

[ "$QUIET" = 0 ] && [ "$JSON" = 0 ] && printf 'check-install.sh — verificando %s\n' "$ROOT"

# --- 1. SKILL.md presente e com identity correta -----------------------------
check "SKILL.md" "$ROOT/SKILL.md"
if [ -f "$ROOT/SKILL.md" ] && ! grep -qx "name: $SKILL_NAME" "$ROOT/SKILL.md" 2>/dev/null; then
  MISSING+=("SKILL.md com 'name: $SKILL_NAME'")
  [ "$QUIET" = 0 ] && [ "$JSON" = 0 ] && printf '  [FALTA] SKILL.md não identifica a skill (name: %s)\n' "$SKILL_NAME" >&2
fi

# --- 2. Ferramentas executáveis (o mínimo para FASE 0..4) ---------------------
check "scripts/ do-context.sh"        "$ROOT/scripts/do-context.sh" x
check "scripts/ do-wt.sh"             "$ROOT/scripts/do-wt.sh" x
check "scripts/ search.sh"            "$ROOT/scripts/search.sh" x
check "scripts/ search-parallel.sh"   "$ROOT/scripts/search-parallel.sh" x
check "scripts/ check-search-credits.sh" "$ROOT/scripts/check-search-credits.sh" x
check "scripts/ check-plannotator.sh" "$ROOT/scripts/check-plannotator.sh" x
check "scripts/ plan-approval.sh"     "$ROOT/scripts/plan-approval.sh" x
check "scripts/ evolve-skill.sh"      "$ROOT/scripts/evolve-skill.sh" x
check "scripts/ do-prefs.sh"          "$ROOT/scripts/do-prefs.sh" x
check "scripts/ evolution-survey.sh"  "$ROOT/scripts/evolution-survey.sh" x
check "scripts/ lib/evolve-common.sh" "$ROOT/scripts/lib/evolve-common.sh"
check "scripts/ lib/plannotator-common.sh" "$ROOT/scripts/lib/plannotator-common.sh"

# --- 3. Prompts ---------------------------------------------------------------
check "prompts/ ecc-prompts.md"       "$ROOT/prompts/ecc-prompts.md"
check "prompts/ ecc-skills.md"        "$ROOT/prompts/ecc-skills.md"
check "prompts/ search-prompts.md"    "$ROOT/prompts/search-prompts.md"
check "prompts/ plan-approval-prompts.md" "$ROOT/prompts/plan-approval-prompts.md"
check "prompts/ evolution-guide.md"   "$ROOT/prompts/evolution-guide.md"

if [ "$JSON" = 1 ]; then
  if [ "${#MISSING[@]}" = 0 ]; then
    printf '{"root":"%s","complete":true,"missing":[]}\n' "$ROOT"
  else
    printf '{"root":"%s","complete":false,"missing":[%s]}\n' "$ROOT" \
      "$(printf '"%s",' "${MISSING[@]}" | sed 's/,$//')"
  fi
fi

if [ "${#MISSING[@]}" = 0 ]; then
  [ "$QUIET" = 0 ] && [ "$JSON" = 0 ] && printf 'RESULTADO: instalação COMPLETA (%s)\n' "$ROOT"
  exit 0
fi

[ "$QUIET" = 0 ] && [ "$JSON" = 0 ] && {
  printf 'RESULTADO: instalação INCOMPLETA — %d item(ns) faltando:\n' "${#MISSING[@]}"
  printf '  - %s\n' "${MISSING[@]}"
  printf 'Correção: aponte o symlink da skill para a RAIZ do repositório (ou garanta\n'
  printf 'scripts/ e prompts/ ao lado do SKILL.md) — depois rode este\n'
  printf 'script de novo. A FASE 0 aborta com "PARE: do-context.sh nao encontrado"\n'
  printf 'enquanto esta verificação não passar.\n'
}
exit 1