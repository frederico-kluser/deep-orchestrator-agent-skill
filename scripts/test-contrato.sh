#!/usr/bin/env bash
# =============================================================================
# test-contrato.sh — CONTRATO.md é a ESPECIFICAÇÃO; os donos têm de casar
# -----------------------------------------------------------------------------
# Verifica que os contratos de máquina documentados em CONTRATO.md existem
# byte-a-byte nos donos funcionais (scripts/*, SKILL.md e módulos
# references/+prompts/). É a rede de segurança do split v4.2.0: cada extração
# move conteúdo de dono e esta suíte garante que o conteúdo NÃO muda.
#
# Hermeticidade (SG-2): sem rede, sem browser, sem crédito de busca; só greps e
# o cartão do do-wt.sh (texto fixo, funciona SEM ENV_FILE). bash 3.2/macOS.
#
# Uso: bash scripts/test-contrato.sh   (exit 0 = tudo verde)
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SKILL_MD="$ROOT/.claude/skills/deep-orchestrator-agent-skill/SKILL.md"
CONTRATO="$ROOT/CONTRATO.md"
SKILL_ALL="$ROOT/.test-contrato-all.$$"
trap 'rm -f "$SKILL_ALL"' EXIT
: > "$SKILL_ALL"
awk '/^## 6\./{s=1} s&&/^```/{f++; next} s&&f==1&&!/^#/&&NF{print}' "$CONTRATO" 2>/dev/null \
  | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' \
  | while IFS= read -r m; do [ -f "$ROOT/$m" ] && cat "$ROOT/$m"; done >> "$SKILL_ALL"
DO_CTX="$ROOT/scripts/do-context.sh"
DO_WT="$ROOT/scripts/do-wt.sh"
GATE_SH="$ROOT/scripts/surf-gate.sh"

PASS=0; FAIL=0
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()  { if [ "$2" = 0 ]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"
        else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; fi; }
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"
        else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s — esperado "%s", obtido "%s"\n' "$1" "$3" "$2"; fi; }

# has3 <literal> — literal presente nos 3: dono funcional, SKILL.md/módulos, CONTRATO.md
has3() { # $1=literal $2=dono-funcional $3=descrição
  local lit="$1" owner="$2" desc="$3" miss=""
  grep -qF -- "$lit" "$owner"      || miss="$miss dono"
  grep -qF -- "$lit" "$SKILL_ALL"   || miss="$miss skill"
  grep -qF -- "$lit" "$CONTRATO"   || miss="$miss contrato"
  ok "$desc (dono × skill × CONTRATO.md)" "$([ -z "$miss" ]; echo $?)"
  [ -n "$miss" ] && printf '    ausente em:%s\n' "$miss"
  return 0
}

section "CT1 — CONTRATO.md existe e é a especificação"
ok "CONTRATO.md presente na raiz" "$([ -f "$CONTRATO" ]; echo $?)"
ok "CONTRATO.md identifica-se como fonte única" \
   "$(grep -q 'Fonte única de especificação dos contratos de máquina' "$CONTRATO"; echo $?)"

section "CT2 — bloco da pergunta PESQUISA-FALHOU (verbatim, 3 donos)"
# Fragmentos fixos de surf-gate.sh print_question — têm de viver nos 3 lados.
has3 '===== PESQUISA-FALHOU — a pesquisa exigida não pôde ser feita; a decisão é SUA =====' "$GATE_SH" "título da pergunta"
has3 '  [1] Adicionei/troquei a chave Brave — tente de novo' "$GATE_SH" "opção [1]"
has3 '  [2] Ajustei o plano/cota ou esperei o cooldown — tente de novo' "$GATE_SH" "opção [2]"
has3 '  [3] Seguir SEM pesquisa — premissas ficam marcadas NÃO VERIFICADAS no plano, handoffs e relatório' "$GATE_SH" "opção [3]"
has3 '  [4] Abortar — fecho o que está aberto (purge) e entrego relatório parcial' "$GATE_SH" "opção [4]"
has3 'Rode os comandos no SEU terminal e NÃO cole a chave no chat' "$GATE_SH" "adendo TTY"
has3 'Outros: remover chave morta' "$GATE_SH" "adendo manutenção"

section "CT3 — linha SEARCH_STATUS (contrato de handoff)"
SS='SEARCH_STATUS: NOT_NEEDED | OK | EMPTY | FAILED_QUOTA | FAILED_OTHER | BLOCKED_78'
ok "SEARCH_STATUS idêntica em SKILL.md, prompts/search-prompts.md e CONTRATO.md" \
   "$(grep -qF -- "$SS" "$SKILL_ALL" && grep -qF -- "$SS" "$ROOT/prompts/search-prompts.md" && grep -qF -- "$SS" "$CONTRATO"; echo $?)"

section "CT4 — literais de interface (byte-a-byte)"
for lit in 'PURGE_RC' '## Não integrado' 'Tarefa concluída PARCIALMENTE' 'MERGED-PARTIAL' 'checklist final' '--boundary='; do
  ok "SKILL.md/módulos citam '$lit'" "$(grep -qF -- "$lit" "$SKILL_ALL"; echo $?)"
  ok "CONTRATO.md documenta '$lit'" "$(grep -qF -- "$lit" "$CONTRATO"; echo $?)"
done
ok "dono funcional: 'MERGED-PARTIAL' no do-wt.sh (outcome)" "$(grep -qF 'MERGED-PARTIAL' "$DO_WT"; echo $?)"
ok "dono funcional: '--boundary=' no do-context.sh" "$(grep -qF -- '--boundary=' "$DO_CTX"; echo $?)"

section "CT5 — sequências de passos congeladas (ordem de ficheiro, sem sort)"
steps3="$(awk '/<phase id="3"/{p=1; if ($0 ~ /\/>/) p=0; next} p && /<\/phase>/{p=0} p' "$SKILL_ALL" \
          | sed -nE 's/.*<step order="([0-9]+(\.[0-9]+)?)".*/\1/p' | tr '\n' ' ')"
chk "FASE 3: 13 <step order> em ordem canónica" "$steps3" "0 1 2 3 3.5 4 4.5 5 6 7 8 9 10 "
f4="$(bash "$DO_WT" checklist final 2>/dev/null \
      | sed -nE 's/^ {0,2}([0-9]+(\.[0-9]+)?)\.?[[:space:]].*/\1/p' | sort -t. -k1,1n -k2,2n | tr '\n' ' ')"
chk "checklist final (FASE 4): passos canónicos" "$f4" "0 1 2 3 4 5 5.5 6 7 7.5 8 "
ok "CONTRATO.md documenta a sequência da FASE 3" \
   "$(grep -qF '0 1 2 3 3.5 4 4.5 5 6 7 8 9 10' "$CONTRATO"; echo $?)"
ok "CONTRATO.md documenta a sequência do checklist final" \
   "$(grep -qF '0 1 2 3 4 5 5.5 6 7 7.5 8' "$CONTRATO"; echo $?)"

section "CT6 — as 9 flags da invocação (validador único = do-context.sh)"
hint="$(sed -n 's/^argument-hint: *//p' "$SKILL_MD" | head -n 1)"
unk=""
for tok in 'plan=' 'max-parallel=' 'surf-sub-agents=' 'wt=' 'no-stop' 'no-evolve' 'no-test' 'only-e2e' 'do-question'; do
  case "$hint" in *"$tok"*) : ;; *) unk="$unk hint:$tok" ;; esac
  grep -qF -- "$tok" "$DO_CTX"    || unk="$unk ctx:$tok"
  grep -qF -- "$tok" "$CONTRATO"  || unk="$unk contrato:$tok"
done
chk "as 9 flags estão no argument-hint, na tabela do do-context.sh e no CONTRATO.md" "$unk" ""
ok "CONTRATO.md declara max-parallel como flag ÚNICA de concorrência (D-G)" \
   "$(grep -qF 'flag ÚNICA de concorrência' "$CONTRATO"; echo $?)"

section "CT7 — marcadores de stdout documentados × donos"
for pair in 'SNAPSHOT=:do-wt' 'GATE VERDE:do-wt' 'PURGE OK:do-wt' 'ASSERT-CLEAN:do-wt' 'RESUMO::do-wt' 'SURF_GATE=:surf'; do
  lit="${pair%:*}"; owner="${pair##*:}"
  case "$owner" in
    do-wt) f="$DO_WT" ;;
    *)     f="$GATE_SH" ;;
  esac
  ok "marcador '$lit' no dono ($owner)" "$(grep -qF -- "$lit" "$f"; echo $?)"
  ok "marcador '$lit' documentado no CONTRATO.md" "$(grep -qF -- "$lit" "$CONTRATO"; echo $?)"
done

section "CT8 — lista canónica de módulos de conteúdo (§6 do CONTRATO.md)"
# Cada ficheiro listado no bloco de código da §6 tem de existir — é esta lista
# que os testes usam para resolver o conteúdo da skill após cada extração.
missing=""
in_fence=0; seen=0
while IFS= read -r line; do
  case "$line" in
    '## 6.'*) in_fence=1; continue ;;
  esac
  [ "$in_fence" = 1 ] || continue
  case "$line" in
    '```'*) seen=$((seen+1)); [ "$seen" -ge 2 ] && break; continue ;;
  esac
  [ "$seen" -ge 1 ] || continue
  case "$line" in ''|'#'*) continue ;; esac
  # tira comentário final ("path   # nota") e espaços
  fpath="$(printf '%s' "$line" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  [ -n "$fpath" ] || continue
  f="$ROOT/$fpath"
  [ -e "$f" ] || missing="$missing $fpath"
done < "$CONTRATO"
chk "todos os módulos listados no CONTRATO.md (§6) existem" "$missing" ""
mods="$(awk '/^## 6\./{s=1} s&&/^```/{f++; next} s&&f==1&&!/^#/&&NF{print}' "$CONTRATO" | wc -l | tr -d ' ')"
ok "§6 lista pelo menos o SKILL.md router (≥1 módulo)" "$([ "$mods" -ge 1 ]; echo $?)"

printf '\n\033[1mRESULTADO: %d PASS, %d FAIL\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
