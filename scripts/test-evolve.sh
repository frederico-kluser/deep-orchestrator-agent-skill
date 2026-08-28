#!/usr/bin/env bash
# Testes de aceitação do motor de EVOLUÇÃO v3.8.0 — F1..F13, S1..S10, E1..E6
#
# Cada caso roda ISOLADO num repo fake da skill (git init + SKILL.md com
# identidade + scripts/do-prefs.sh, scripts/evolution-survey.sh,
# scripts/evolve-skill.sh e scripts/lib/* COPIADOS), com HOME/tmp próprios,
# SEM rede. Os scripts sob teste resolvem a casa da skill pela própria
# localização (pwd -P) — por isso o fixture precisa de uma CÓPIA dos scripts
# dentro do repo fake; o cwd de invocação é irrelevante.
#   F1:  load com dirs ausentes → exit 0, seções '(ausente)'
#   F2:  add-project cria dirs + header + entrada P-<hoje>-001 (scope/status
#        corretos) + .gitignore do projeto ganha a linha (idempotente)
#   F3:  dedupe no add-project — mesma entrada 2× → 2ª duplicada, ignorada
#   F4:  add-global escreve em global-tips.md do SKILL_HOME fake
#   F5:  pending-add grava status: pending em pending/proposals.md
#   F6:  lote atômico — 2 candidatos, 1 sem scope → exit 2 e NADA escrito
#   F7:  secret scan — api_key=abc123 → exit 2 e o valor NUNCA impresso
#   F8:  scope divergente — add-project com scope: global → exit 2, nada escrito
#   F9:  aprovação remove o pendente equivalente (nunca zumbi)
#   F10: ensure-gitignore preserva conteúdo do usuário + idempotente + cria
#        o arquivo se ausente
#   F11: identidade errada do SKILL.md → exit 3 (add-global)
#   F12: add com entrada vazia → exit 0, 'nada a adicionar', nada escrito (D9)
#   F13: aspas ao redor de title/observacao/acao são removidas no armazenamento
#   S1:  ask com propostas → exit 0; pendente.md gravado; bloco numerado com
#        opções a/b/c e a linha "1 = fix local · 2 = fix global"
#   S2:  ask sem propostas → marca SEM-PROPOSTAS e exit 0
#   S3:  answer "1:b2 2:c1" → answers.json: P001 sim/global/opcao b (jq)
#   S4:  answer rota python3 (sem jq no PATH) → answers.json correto
#   S5:  answer "nada" → answers vazio → apply pendes TUDO, nada salvo
#   S6:  answer fora da gramática → exit 2 com mensagem acionável
#   S7:  apply roteia 1:b2 → global-tips com a AÇÃO da opção b; 2:a1 →
#        learnings com a AÇÃO da opção a; 3:c → descartada; config inline →
#        project-config.md; contagens corretas
#   S8:  apply idempotente — 2ª chamada com o mesmo answers.json → skip
#   S9:  dismiss → answers vazio → tudo pendente
#   S10: sem jq E sem python3 no PATH → answer sai 2 com mensagem acionável
#   E1:  evolve-skill.sh search encontra em global-tips.md e em prefs do
#        projeto (--project)
#   E2:  evolve-skill.sh add → exit 2 com a mensagem de migração
#   E3:  evolve-skill.sh status mostra versão e prefs
#   E4:  apply de corpo → branch evolve/<hoje> SEMPRE (nunca commit direto)
#   E5:  apply com staged fora da allowlist → exit 4, índice INTACTO
#   E6:  diff --stat funciona sobre os paths do corpo
set -uo pipefail
SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
LAB="${TMPDIR:-/tmp}/evolve-accept-$$"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (esperado='$3' obtido='$2')"; fi; }

rm -rf "$LAB"; mkdir -p "$LAB"; cd "$LAB"
trap 'rm -rf -- "$LAB"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

TODAY=$(date +%Y%m%d)
TODAY_C=$(date +%F)

# --- fixture: repo fake da skill (scripts COPIADOS; cwd fica fora) ------------
newcase() { # <nome> — dir próprio do caso com repo fake isolado
  CASE="$LAB/$1"
  rm -rf "$CASE"
  mkdir -p "$CASE/repo/scripts/lib"
  git init -q -b main "$CASE/repo"
  git -C "$CASE/repo" config user.name t
  git -C "$CASE/repo" config user.email t@t
  cp "$SKILL/scripts/do-prefs.sh" "$SKILL/scripts/evolution-survey.sh" \
     "$SKILL/scripts/evolve-skill.sh" "$CASE/repo/scripts/"
  cp "$SKILL/scripts/lib/evolve-common.sh" "$SKILL/scripts/lib/plannotator-common.sh" \
     "$CASE/repo/scripts/lib/"
  chmod +x "$CASE/repo/scripts/"*.sh
  DO_PREFS="$CASE/repo/scripts/do-prefs.sh"
  SURVEY="$CASE/repo/scripts/evolution-survey.sh"
  EVOLVE="$CASE/repo/scripts/evolve-skill.sh"
  SKILL_REPO="$CASE/repo"
  GLOBAL_TIPS="$SKILL_REPO/.deep-orchestrator-preferences/global-tips.md"
  GLOBAL_PENDING="$SKILL_REPO/.deep-orchestrator-preferences/pending/proposals.md"
  cd "$CASE" || exit 1
}

write_skill() { # SKILL.md com identidade correta (grep -qx exige a linha exata)
  cat > "$SKILL_REPO/SKILL.md" <<'EOF'
---
name: deep-orchestrator-agent-skill
description: fixture de teste do motor de evolucao v3.8.0
metadata:
  version: "3.8.0"
---
EOF
}

commit_all() { # <msg> — commita tudo do repo fake
  git -C "$SKILL_REPO" add -A
  git -C "$SKILL_REPO" commit -qm "$1"
}

# proj_fixture: cria um repo fake de PROJETO separado
proj_fixture() { # <nome>
  PROJ="$CASE/$1"
  rm -rf "$PROJ"; mkdir -p "$PROJ"
  git init -q -b main "$PROJ"
  git -C "$PROJ" config user.name t
  git -C "$PROJ" config user.email t@t
  printf 'node_modules/\n' > "$PROJ/.gitignore"
  git -C "$PROJ" add -A && git -C "$PROJ" commit -qm init
  PROJ_PREFS="$PROJ/.deep-orchestrator-preferences"
}

candidate() { # <arquivo> <key> <título> <scope> <type> <confidence> <source> <obs> <acao>
  local f="$1"; shift
  {
    printf -- '---\n'
    printf 'key: %s\n' "$1"
    printf 'title: "%s"\n' "$2"
    printf 'scope: %s\n' "$3"
    printf 'type: %s\n' "$4"
    printf 'confidence: %s\n' "$5"
    printf 'source: %s\n' "$6"
    printf 'tags: [test]\n'
    printf 'observacao: "%s"\n' "$7"
    printf 'acao: "%s"\n' "$8"
    printf -- '---\n'
  } > "$f"
}

survey_env() { # ENV_FILE fabricado apontando para o fixture
  cat > "$CASE/env" <<EOF
DO_STATE='$CASE/state'
BASE_DIR='$CASE/proj'
RUN_ID='fixture'
DO_PREFS='$DO_PREFS'
DO_SURVEY='$SURVEY'
PROJECT_PREFS_DIR='$CASE/proj/.deep-orchestrator-preferences'
PROJECT_LEARNINGS='$CASE/proj/.deep-orchestrator-preferences/learnings.md'
GLOBAL_TIPS='$GLOBAL_TIPS'
PROJECT_CONFIG='$CASE/proj/.deep-orchestrator-preferences/project-config.md'
PROJECT_PENDING='$CASE/proj/.deep-orchestrator-preferences/pending/proposals.md'
GLOBAL_PENDING='$GLOBAL_PENDING'
export DO_STATE BASE_DIR RUN_ID DO_PREFS DO_SURVEY PROJECT_PREFS_DIR PROJECT_LEARNINGS GLOBAL_TIPS PROJECT_CONFIG PROJECT_PENDING GLOBAL_PENDING
EOF
  mkdir -p "$CASE/state/evolution"
  # o ask/answer/apply lê as propostas do caminho default sob $DO_STATE
  PROPOSALS="$CASE/state/evolution/proposals.md"
}

# candidato_v39: formato v3.9.0 — com as opções a/b/c da PERGUNTA
candidato_v39() { # <arquivo> <key> <título> <scope> <obs> <opcao_a> <opcao_b>
  local f="$1"; shift
  {
    printf -- '---\n'
    printf 'key: %s\n' "$1"
    printf 'title: "%s"\n' "$2"
    printf 'scope: %s\n' "$3"
    printf 'type: gotcha\n'
    printf 'confidence: high\n'
    printf 'source: user\n'
    printf 'tags: [test]\n'
    printf 'observacao: "%s"\n' "$4"
    printf 'acao: "acao original"\n'
    printf 'opcao_a: "%s"\n' "$5"
    printf 'opcao_b: "%s"\n' "$6"
    printf 'opcao_c: "Não fazer nada (descartar)"\n'
    printf -- '---\n'
  } > "$f"
}

# nopath_sem <bin1> [bin2...] — PATH espelhado por symlinks, sem os bins dados
nopath_sem() {
  NOPATH=$(mktemp -d "$LAB/nopath.XXXXXX")
  local d b base skip
  for d in $(printf '%s' "$PATH" | tr ':' ' '); do
    [ -d "$d" ] || continue
    for b in "$d"/*; do
      [ -x "$b" ] || continue
      base=$(basename "$b")
      skip=0
      for x in "$@"; do case "$base" in "$x"|"$x".*) skip=1 ;; esac; done
      [ "$skip" = 0 ] && ln -sf "$b" "$NOPATH/$base" 2>/dev/null
    done
  done
}

# =============================================================================
echo "=== F1..F13: do-prefs.sh ==="
# =============================================================================

newcase f1; write_skill
mkdir -p "$CASE/rootvazio"
out=$("$DO_PREFS" load --project "$CASE/rootvazio" 2>&1); rc=$?
chk "F1 load com dirs ausentes → exit 0" "$rc" "0"
chk "F1 seção (ausente) presente" "$(printf '%s' "$out" | grep -c '(ausente)')" "5"

newcase f2; write_skill; proj_fixture p
candidate "$CASE/c.md" "" "Gate deste projeto usa pnpm" project gotcha high user \
  "npm test falha; runner real é pnpm test." "Usar pnpm test no gate."
"$DO_PREFS" add-project "$CASE/c.md" --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "F2 add-project → exit 0" "$rc" "0"
[ -f "$PROJ_PREFS/learnings.md" ] && chk "F2 learnings.md criado" y y || chk "F2 learnings.md criado" n y
grep -q "^id: P-$TODAY-001$" "$PROJ_PREFS/learnings.md" && chk "F2 id P-hoje-001" y y || chk "F2 id P-hoje-001" n y
grep -q "^scope: project$" "$PROJ_PREFS/learnings.md" && chk "F2 scope project" y y || chk "F2 scope project" n y
grep -q "^status: active$" "$PROJ_PREFS/learnings.md" && chk "F2 status active" y y || chk "F2 status active" n y
grep -Fqx -- '.deep-orchestrator-preferences/' "$PROJ/.gitignore" && chk "F2 .gitignore do projeto" y y || chk "F2 .gitignore do projeto" n y
grep -q '^## Gate deste projeto usa pnpm$' "$PROJ_PREFS/learnings.md" && chk "F13 aspas removidas do título" y y || chk "F13 aspas removidas do título" n y

newcase f3; write_skill; proj_fixture p
candidate "$CASE/c.md" "" "Gate deste projeto usa pnpm" project gotcha high user \
  "npm test falha." "Usar pnpm test."
"$DO_PREFS" add-project "$CASE/c.md" --project "$PROJ" >/dev/null 2>&1
out=$("$DO_PREFS" add-project "$CASE/c.md" --project "$PROJ" 2>&1)
chk "F3 dedupe: 2ª chamada 'duplicada'" "$(printf '%s' "$out" | grep -c 'duplicada, ignorada')" "1"
chk "F3 1 entrada no arquivo" "$(grep -c '^id: P-' "$PROJ_PREFS/learnings.md")" "1"

newcase f4; write_skill
candidate "$CASE/c.md" "" "Sub-agentes background longos são mortos" global gotcha high user \
  "Bash background de minutos morre." "Usar Monitor."
"$DO_PREFS" add-global "$CASE/c.md" >/dev/null 2>&1; rc=$?
chk "F4 add-global → exit 0" "$rc" "0"
[ -f "$GLOBAL_TIPS" ] && chk "F4 global-tips.md criado" y y || chk "F4 global-tips.md criado" n y
grep -q "^scope: global$" "$GLOBAL_TIPS" && chk "F4 scope global" y y || chk "F4 scope global" n y
grep -Fqx -- '.deep-orchestrator-preferences/' "$SKILL_REPO/.gitignore" && chk "F4 .gitignore do repo da skill" y y || chk "F4 .gitignore do repo da skill" n y

newcase f5; write_skill; proj_fixture p
candidate "$CASE/c.md" "" "Pendente de teste" project gotcha high user "x" "y"
"$DO_PREFS" pending-add "$CASE/c.md" --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "F5 pending-add → exit 0" "$rc" "0"
grep -q "^status: pending$" "$PROJ_PREFS/pending/proposals.md" && chk "F5 status pending" y y || chk "F5 status pending" n y

newcase f6; write_skill; proj_fixture p
candidate "$CASE/c1.md" "" "A" project gotcha high user "x" "y"
{ printf '\n---\n'; printf 'title: "B sem scope"\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'observacao: "x"\n'; printf 'acao: "y"\n'; printf -- '---\n'; } >> "$CASE/c1.md"
"$DO_PREFS" add-project "$CASE/c1.md" --project "$PROJ" >/dev/null 2>&1; rc=$?
chk "F6 lote atômico → exit 2" "$rc" "2"
chk "F6 nada escrito" "$([ -f "$PROJ_PREFS/learnings.md" ] && echo 1 || echo 0)" "0"

newcase f7; write_skill; proj_fixture p
candidate "$CASE/c.md" "" "Segredo" project gotcha high user "api_key=abc123 vazou" "remover"
out=$("$DO_PREFS" add-project "$CASE/c.md" --project "$PROJ" 2>&1); rc=$?
chk "F7 secret scan → exit 2" "$rc" "2"
chk "F7 valor nunca impresso" "$(printf '%s' "$out" | grep -c 'abc123')" "0"
chk "F7 nada escrito" "$([ -f "$PROJ_PREFS/learnings.md" ] && echo 1 || echo 0)" "0"

newcase f8; write_skill; proj_fixture p
candidate "$CASE/c.md" "" "Scope errado" global gotcha high user "x" "y"
out=$("$DO_PREFS" add-project "$CASE/c.md" --project "$PROJ" 2>&1); rc=$?
chk "F8 scope divergente → exit 2" "$rc" "2"
chk "F8 mensagem aponta o destino certo" "$(printf '%s' "$out" | grep -c 'use add-global')" "1"

newcase f9; write_skill; proj_fixture p
candidate "$CASE/c.md" "" "Zumbi nunca" project gotcha high user "x" "y"
"$DO_PREFS" pending-add "$CASE/c.md" --project "$PROJ" >/dev/null 2>&1
"$DO_PREFS" add-project "$CASE/c.md" --project "$PROJ" >/dev/null 2>&1
chk "F9 pendente removido na aprovação" "$(grep -c '^id: P-' "$PROJ_PREFS/pending/proposals.md" 2>/dev/null || true)" "0"
chk "F9 ativo presente" "$(grep -c '^id: P-' "$PROJ_PREFS/learnings.md")" "1"

newcase f10; write_skill; proj_fixture p
printf 'minha-linha\n' > "$PROJ/.gitignore"
"$DO_PREFS" ensure-gitignore --dir "$PROJ" >/dev/null 2>&1
"$DO_PREFS" ensure-gitignore --dir "$PROJ" >/dev/null 2>&1
chk "F10 linha acrescentada 1×" "$(grep -c '^\.deep-orchestrator-preferences/$' "$PROJ/.gitignore")" "1"
chk "F10 conteúdo do usuário preservado" "$(grep -c '^minha-linha$' "$PROJ/.gitignore")" "1"
mkdir -p "$CASE/vazio" && "$DO_PREFS" ensure-gitignore --dir "$CASE/vazio" >/dev/null 2>&1
chk "F10 .gitignore criado se ausente" "$([ -f "$CASE/vazio/.gitignore" ] && echo 1 || echo 0)" "1"

newcase f11; proj_fixture p
printf 'name: outra-skill\n' > "$SKILL_REPO/SKILL.md"
candidate "$CASE/c.md" "" "X" global gotcha high user "x" "y"
"$DO_PREFS" add-global "$CASE/c.md" >/dev/null 2>&1; rc=$?
chk "F11 identidade errada → exit 3" "$rc" "3"

newcase f12; write_skill; proj_fixture p
: > "$CASE/vazio.md"
out=$("$DO_PREFS" add-project "$CASE/vazio.md" --project "$PROJ" 2>&1); rc=$?
chk "F12 entrada vazia → exit 0" "$rc" "0"
chk "F12 'nada a adicionar'" "$(printf '%s' "$out" | grep -c 'nada a adicionar')" "1"
chk "F12 nada escrito" "$([ -f "$PROJ_PREFS/learnings.md" ] && echo 1 || echo 0)" "0"

# =============================================================================
echo "=== S1..S10: evolution-survey.sh (pergunta em texto — v3.9.0) ==="
# =============================================================================

newcase s1; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "Dependencias em worktree" global \
  "Toda vez que criamos uma worktree precisamos instalar as dependencias" \
  "usar symlinks" "merge para principal e testar"
{ printf '\n'; printf -- '---\n'; printf 'key: P002\n'; printf 'title: "Gate pnpm"\n'; printf 'scope: project\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'tags: [test]\n'; printf 'observacao: "npm falha."\n'; printf 'acao: "acao original"\n'; printf 'opcao_a: "pnpm test"\n'; printf 'opcao_b: "documentar"\n'; printf 'opcao_c: "Não fazer nada (descartar)"\n'; printf -- '---\n'; } >> "$PROPOSALS"
out=$("$SURVEY" --env "$CASE/env" ask 2>/dev/null); rc=$?
chk "S1 ask → exit 0" "$rc" "0"
chk "S1 pergunta numerada (1 -)" "$(printf '%s' "$out" | grep -c '^1 - Toda vez')" "1"
chk "S1 opções a/b/c (2 propostas × 3)" "$(printf '%s' "$out" | grep -c '^   [abc]:')" "6"
chk "S1 linha de escopo (1 = fix local · 2 = fix global)" "$(printf '%s' "$out" | grep -c '1 = fix local · 2 = fix global')" "2"
chk "S1 pendente.md gravado" "$([ -f "$CASE/state/evolution/pendente.md" ] && echo 1 || echo 0)" "1"

newcase s2; write_skill; proj_fixture p; survey_env
: > "$PROPOSALS"
out=$("$SURVEY" --env "$CASE/env" ask 2>/dev/null); rc=$?
chk "S2 sem propostas → SEM-PROPOSTAS" "$(printf '%s' "$out" | grep -c '^SEM-PROPOSTAS$')" "1"
chk "S2 exit 0" "$rc" "0"

newcase s3; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "A" global "obs a" "acao a1" "acao a2"
{ printf '\n'; printf -- '---\n'; printf 'key: P002\n'; printf 'title: "B"\n'; printf 'scope: project\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'tags: [test]\n'; printf 'observacao: "obs b"\n'; printf 'acao: "acao original"\n'; printf 'opcao_a: "b1"\n'; printf 'opcao_b: "b2"\n'; printf 'opcao_c: "Não fazer nada (descartar)"\n'; printf -- '---\n'; } >> "$PROPOSALS"
"$SURVEY" --env "$CASE/env" answer "1:b2 2:c1" >/dev/null 2>&1; rc=$?
chk "S3 answer → exit 0" "$rc" "0"
if command -v jq >/dev/null 2>&1; then
  chk "S3 P001 save/scope/opcao (jq)" "$(jq -r '.answers.P001.save + "/" + .answers.P001.scope + "/" + .answers.P001.opcao' "$CASE/state/evolution/answers.json")" "sim/global/b"
  chk "S3 P002 c → nao" "$(jq -r '.answers.P002.save' "$CASE/state/evolution/answers.json")" "nao"
fi

newcase s4; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "A" project "obs" "x1" "x2"
nopath_sem jq
"$SURVEY" --env "$CASE/env" answer "1:a1" >/dev/null 2>&1
env PATH="$NOPATH" "$SURVEY" --env "$CASE/env" answer "1:a1" >/dev/null 2>&1; rc=$?
chk "S4 answer rota python3 → exit 0" "$rc" "0"
if command -v python3 >/dev/null 2>&1; then
  chk "S4 answers correto (python3)" "$(python3 -c 'import json;d=json.load(open("'$CASE'/state/evolution/answers.json"));print(d["answers"]["P001"]["save"]+"/"+d["answers"]["P001"]["scope"]+"/"+d["answers"]["P001"]["opcao"])')" "sim/project/a"
fi

newcase s5; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "A" project "obs" "x1" "x2"
"$SURVEY" --env "$CASE/env" answer "nada" >/dev/null 2>&1; rc=$?
chk "S5 answer nada → exit 0" "$rc" "0"
"$SURVEY" --env "$CASE/env" apply >/dev/null 2>&1
chk "S5 tudo pendente" "$(grep -c '^id: P-' "$CASE/proj/.deep-orchestrator-preferences/pending/proposals.md" 2>/dev/null || echo 0)" "1"
chk "S5 nada salvo" "$([ -f "$CASE/proj/.deep-orchestrator-preferences/learnings.md" ] && echo 1 || echo 0)" "0"

newcase s6; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "A" global "obs" "x1" "x2"
out=$("$SURVEY" --env "$CASE/env" answer "xpto sem sentido" 2>&1); rc=$?
chk "S6 gramática inválida → exit 2" "$rc" "2"
m6=$(printf '%s' "$out" | grep -c 'Esperado: N:XY'); [ "$m6" -ge 1 ] && chk "S6 mensagem acionável" ">=1" ">=1" || chk "S6 mensagem acionável" "0" ">=1"

newcase s7; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "A global" global "obs a" "acao a1" "acao a2"
{ printf '\n'; printf -- '---\n'; printf 'key: P002\n'; printf 'title: "B projeto"\n'; printf 'scope: project\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'tags: [test]\n'; printf 'observacao: "obs b"\n'; printf 'acao: "acao original"\n'; printf 'opcao_a: "b1"\n'; printf 'opcao_b: "b2"\n'; printf 'opcao_c: "Não fazer nada (descartar)"\n'; printf -- '---\n'; printf 'key: P003\n'; printf 'title: "C descartada"\n'; printf 'scope: project\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'tags: [test]\n'; printf 'observacao: "obs c"\n'; printf 'acao: "acao original"\n'; printf 'opcao_a: "c1"\n'; printf 'opcao_b: "c2"\n'; printf 'opcao_c: "Não fazer nada (descartar)"\n'; printf -- '---\n'; } >> "$PROPOSALS"
"$SURVEY" --env "$CASE/env" answer "1:b2 2:a1 3:c2 config: preferencia livre" >/dev/null 2>&1
out=$("$SURVEY" --env "$CASE/env" apply 2>/dev/null)
chk "S7 2 salvas · 1 descartada · 0 pendentes" "$(printf '%s' "$out" | grep -o '[0-9]* salva(s) (projeto/global) · [0-9]* descartada(s) · [0-9]* pendente(s)')" "2 salva(s) (projeto/global) · 1 descartada(s) · 0 pendente(s)"
chk "S7 global-tips tem P001" "$(grep -c '^## A global$' "$GLOBAL_TIPS" 2>/dev/null || echo 0)" "1"
chk "S7 AÇÃO de P001 = opção b (global)" "$(grep -c -- '- \*\*Ação:\*\* acao a2' "$GLOBAL_TIPS" 2>/dev/null || echo 0)" "1"
chk "S7 learnings do projeto tem P002" "$(grep -c '^## B projeto$' "$CASE/proj/.deep-orchestrator-preferences/learnings.md" 2>/dev/null || echo 0)" "1"
chk "S7 AÇÃO de P002 = opção a (projeto)" "$(grep -c -- '- \*\*Ação:\*\* b1' "$CASE/proj/.deep-orchestrator-preferences/learnings.md" 2>/dev/null || echo 0)" "1"
chk "S7 P003 descartada (ausente dos dois)" "$([ -f "$GLOBAL_TIPS" ] && grep -c '^## C descartada$' "$GLOBAL_TIPS" || true)" "0"
chk "S7 config gravada" "$(grep -c '^- preferencia livre$' "$CASE/proj/.deep-orchestrator-preferences/project-config.md" 2>/dev/null || echo 0)" "1"

newcase s8; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "A" project "obs" "x1" "x2"
"$SURVEY" --env "$CASE/env" answer "1:c1" >/dev/null 2>&1
"$SURVEY" --env "$CASE/env" apply >/dev/null 2>&1
out=$("$SURVEY" --env "$CASE/env" apply 2>/dev/null)
chk "S8 apply idempotente" "$(printf '%s' "$out" | grep -c 'já executado')" "1"

newcase s9; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "A" project "obs" "x1" "x2"
"$SURVEY" --env "$CASE/env" dismiss >/dev/null 2>&1; rc=$?
chk "S9 dismiss → exit 0" "$rc" "0"
chk "S9 tudo pendente" "$(grep -c '^id: P-' "$CASE/proj/.deep-orchestrator-preferences/pending/proposals.md" 2>/dev/null || echo 0)" "1"
chk "S9 nada salvo" "$([ -f "$CASE/proj/.deep-orchestrator-preferences/learnings.md" ] && echo 1 || echo 0)" "0"

newcase s10; write_skill; proj_fixture p; survey_env
candidato_v39 "$PROPOSALS" P001 "A" global "obs" "x1" "x2"
nopath_sem jq python3
env PATH="$NOPATH" "$SURVEY" --env "$CASE/env" answer "1:b2" >/dev/null 2>&1; rc=$?
chk "S10 sem jq/python3 → exit 2" "$rc" "2"

# =============================================================================
echo "=== E1..E6: evolve-skill.sh ==="
# =============================================================================

newcase e1; write_skill
candidate "$CASE/c.md" "" "Dica global única" global gotcha high user "observacao marcante zeta" "acao"
"$DO_PREFS" add-global "$CASE/c.md" >/dev/null 2>&1
out=$("$EVOLVE" search "marcante"); rc=$?
chk "E1 search encontra global-tips" "$rc" "0"
chk "E1 formato id|data|..." "$(printf '%s' "$out" | grep -c ' | .* | .* | .* | .* | Dica global única')" "1"
proj_fixture p
mkdir -p "$PROJ_PREFS"
printf '## Preferências do usuário\n- preferencia marcante dois\n' > "$PROJ_PREFS/project-config.md"
out=$("$EVOLVE" search "marcante" --project "$PROJ"); rc=$?
chk "E1 search encontra prefs do projeto" "$rc" "0"
chk "E1 linha do project-config" "$(printf '%s' "$out" | grep -c 'preferencia marcante dois')" "1"
"$EVOLVE" search "termo-inexistente-xyz" >/dev/null 2>&1; rc=$?
chk "E1 search sem resultados → exit 1" "$rc" "1"

newcase e2; write_skill
out=$("$EVOLVE" add /dev/null 2>&1); rc=$?
chk "E2 add → exit 2" "$rc" "2"
chk "E2 mensagem de migração" "$(printf '%s' "$out" | grep -c 'do-prefs.sh')" "1"

newcase e3; write_skill
out=$("$EVOLVE" status 2>&1); rc=$?
chk "E3 status → exit 0" "$rc" "0"
chk "E3 versão 3.8.0" "$(printf '%s' "$out" | grep -c 'versão      : 3.8.0')" "1"
chk "E3 menção a prefs" "$(printf '%s' "$out" | grep -c 'memória     : .deep-orchestrator-preferences/')" "1"

newcase e4; write_skill; commit_all init
printf '\n# corpo evoluído\n' >> "$SKILL_REPO/README.md"
git -C "$SKILL_REPO" config user.name t; git -C "$SKILL_REPO" config user.email t@t
"$EVOLVE" apply >/dev/null 2>&1; rc=$?
chk "E4 apply corpo → exit 0" "$rc" "0"
branch=$(git -C "$SKILL_REPO" symbolic-ref --short HEAD)
chk "E4 branch evolve/<hoje> SEMPRE" "$branch" "evolve/$TODAY_C"

newcase e5; write_skill; commit_all init
printf 'segredo-staged\n' > "$SKILL_REPO/fora-allowlist.txt"
git -C "$SKILL_REPO" add -A
printf '\n# corpo\n' >> "$SKILL_REPO/README.md"
out=$("$EVOLVE" apply 2>&1); rc=$?
chk "E5 staged fora da allowlist → exit 4" "$rc" "4"
staged=$(git -C "$SKILL_REPO" diff --cached --name-only)
chk "E5 índice INTACTO" "$staged" "fora-allowlist.txt"

newcase e6; write_skill; commit_all init
printf '\n# corpo\n' >> "$SKILL_REPO/README.md"
out=$("$EVOLVE" diff --stat 2>&1); rc=$?
chk "E6 diff --stat → exit 0" "$rc" "0"
chk "E6 lista README.md" "$(printf '%s' "$out" | grep -c 'README.md')" "1"

# =============================================================================
printf '\nRESULTADO: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
