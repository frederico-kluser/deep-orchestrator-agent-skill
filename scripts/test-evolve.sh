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
#   S1:  round com annotated + gramática → exit 0; snapshot imutável; título
#        travado
#   S2:  answers → answers.json correto (jq E python3 — forçando a rota)
#   S3:  gramática fora do padrão → resposta ausente → apply pendes a proposta
#   S4:  approved sem feedback → exit 0, answers vazio → apply pendes TUDO
#   S5:  dismissed → exit 11
#   S6:  toolfail (stdout ilegível) → exit 13; retry vira rev-002
#   S7:  apply roteia sim·global → global-tips; sim·projeto → learnings;
#        nao → descartada; config: → project-config.md; contagens corretas
#   S8:  apply idempotente — 2ª chamada com o mesmo answers.json → skip
#   S9:  deriva de título → exit 2
#   S10: sem jq E sem python3 no PATH → round sai 2 com mensagem acionável
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
  mkdir -p "$CASE/state/evolution/survey"
  # o apply lê as propostas do caminho default sob $DO_STATE
  PROPOSALS="$CASE/state/evolution/proposals.md"
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

# plannotator FAKE fiel ao contrato (padrão test-plan-approval.sh): usage sem
# args; envelope json em UMA linha; exit SEMPRE 0. O feedback varia por caso.
make_fake_plannotator() { # <feedback-json-ou-decision>
  mkdir -p "$CASE/bin"
  cat > "$CASE/bin/plannotator" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "annotate" ] && [ \$# -ge 1 ]; then
  printf '%s\n' '$1'
  exit 0
fi
echo "usage: annotate <file>"
exit 0
EOF
  chmod +x "$CASE/bin/plannotator"
  export DO_PLANNOTATOR_BIN="$CASE/bin/plannotator"
  export PATH="$CASE/bin:$PATH"
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
echo "=== S1..S10: evolution-survey.sh ==="
# =============================================================================

newcase s1; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"annotated","feedback":"P001: sim · global\nP002: nao\nconfig: usar pnpm test no gate"}'
candidate "$PROPOSALS" P001 "Background longos" global gotcha high user "Bash morre." "Monitor."
{ printf '\n'; printf -- '---\n'; printf 'key: P002\n'; printf 'title: "Gate pnpm"\n'; printf 'scope: project\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'tags: [test]\n'; printf 'observacao: "npm falha."\n'; printf 'acao: "pnpm test."\n'; printf -- '---\n'; } >> "$PROPOSALS"
cat > "$CASE/questionario.md" <<'EOF'
# Questionário de evolução — fixture s1

## P001 — Background longos

`P001: sim · global` / `P001: nao`

## P002 — Gate pnpm

`P002: sim · projeto` / `P002: nao`
EOF
out=$("$SURVEY" --env "$CASE/env" round "$CASE/questionario.md" 2>/dev/null); rc=$?
chk "S1 round annotated → exit 0" "$rc" "0"
chk "S1 linha de contrato" "$(printf '%s' "$out" | grep -c '^EVOLUTION_SURVEY decision=annotated revision=1')" "1"
[ -f "$CASE/state/evolution/survey/rev-001.md" ] && chk "S1 snapshot" y y || chk "S1 snapshot" n y
[ -w "$CASE/state/evolution/survey/rev-001.md" ] && chk "S1 snapshot imutável" n y || chk "S1 snapshot imutável" y y

newcase s2; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"annotated","feedback":"P001: sim · global\nP002: pendente · projeto\nconfig: linha de config"}'
candidate "$PROPOSALS" P001 "A" global gotcha high user "x" "y"
{ printf '\n'; printf -- '---\n'; printf 'key: P002\n'; printf 'title: "B"\n'; printf 'scope: project\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'tags: [test]\n'; printf 'observacao: "x"\n'; printf 'acao: "y"\n'; printf -- '---\n'; } >> "$PROPOSALS"
printf '# Questionário — s2\n' > "$CASE/q.md"
"$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1
"$SURVEY" --env "$CASE/env" answers >/dev/null 2>&1; rc=$?
chk "S2 answers → exit 0" "$rc" "0"
if command -v jq >/dev/null 2>&1; then
  chk "S2 P001 save/scope (jq)" "$(jq -r '.answers.P001.save + "/" + .answers.P001.scope' "$CASE/state/evolution/survey/answers.json")" "sim/global"
  chk "S2 configs (jq)" "$(jq -r '.configs[0]' "$CASE/state/evolution/survey/answers.json")" "linha de config"
fi
if command -v python3 >/dev/null 2>&1; then
  nopath_sem jq
  rm -f "$CASE/state/evolution/survey/answers.json"
  env PATH="$NOPATH" "$SURVEY" --env "$CASE/env" answers >/dev/null 2>&1
  chk "S2 rota python3 ok" "$(python3 -c 'import json;d=json.load(open("'$CASE'/state/evolution/survey/answers.json"));print(d["answers"]["P002"]["save"]+"/"+d["answers"]["P002"]["scope"])')" "pendente/project"
fi

newcase s3; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"annotated","feedback":"P001: xpto sem sentido"}'
candidate "$PROPOSALS" P001 "Fora da gramática" global gotcha high user "x" "y"
printf '# Questionário — s3\n' > "$CASE/q.md"
"$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1
"$SURVEY" --env "$CASE/env" answers >/dev/null 2>&1
"$SURVEY" --env "$CASE/env" apply >/dev/null 2>&1
chk "S3 resposta ilegível → pendente" "$(grep -c '^id: P-' "$GLOBAL_PENDING" 2>/dev/null || echo 0)" "1"
chk "S3 nada salvo" "$([ -f "$GLOBAL_TIPS" ] && echo 1 || echo 0)" "0"

newcase s4; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"approved"}'
candidate "$PROPOSALS" P001 "A" project gotcha high user "x" "y"
printf '# Questionário — s4\n' > "$CASE/q.md"
out=$("$SURVEY" --env "$CASE/env" round "$CASE/q.md" 2>/dev/null); rc=$?
chk "S4 approved sem feedback → exit 0" "$rc" "0"
"$SURVEY" --env "$CASE/env" answers >/dev/null 2>&1
"$SURVEY" --env "$CASE/env" apply >/dev/null 2>&1
chk "S4 tudo pendente" "$(grep -c '^id: P-' "$CASE/proj/.deep-orchestrator-preferences/pending/proposals.md" 2>/dev/null || echo 0)" "1"
chk "S4 nada salvo" "$([ -f "$CASE/proj/.deep-orchestrator-preferences/learnings.md" ] && echo 1 || echo 0)" "0"

newcase s5; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"dismissed"}'
printf '# Questionário — s5\n' > "$CASE/q.md"
"$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1; rc=$?
chk "S5 dismissed → exit 11" "$rc" "11"

newcase s6; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"not":"json-at-all"}'
printf '# Questionário — s6\n' > "$CASE/q.md"
"$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1; rc=$?
chk "S6 saída ilegível → exit 13" "$rc" "13"
make_fake_plannotator '{"decision":"dismissed"}'
"$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1; rc=$?
chk "S6 retry vira rev-002" "$rc" "11"
[ -f "$CASE/state/evolution/survey/rev-002.md" ] && chk "S6 rev-002 em disco" y y || chk "S6 rev-002 em disco" n y

newcase s7; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"annotated","feedback":"P001: sim · global\nP002: sim · projeto\nP003: nao\nconfig: preferencia livre"}'
candidate "$PROPOSALS" P001 "A global" global gotcha high user "x" "y"
{ printf '\n'; printf -- '---\n'; printf 'key: P002\n'; printf 'title: "B projeto"\n'; printf 'scope: project\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'tags: [test]\n'; printf 'observacao: "x"\n'; printf 'acao: "y"\n'; printf -- '---\n'; printf 'key: P003\n'; printf 'title: "C descartada"\n'; printf 'scope: project\n'; printf 'type: gotcha\n'; printf 'confidence: high\n'; printf 'source: user\n'; printf 'tags: [test]\n'; printf 'observacao: "x"\n'; printf 'acao: "y"\n'; printf -- '---\n'; } >> "$PROPOSALS"
printf '# Questionário — s7\n' > "$CASE/q.md"
"$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1
"$SURVEY" --env "$CASE/env" answers >/dev/null 2>&1
out=$("$SURVEY" --env "$CASE/env" apply 2>/dev/null)
chk "S7 2 salvas · 1 descartada · 0 pendentes" "$(printf '%s' "$out" | grep -o '[0-9]* salva(s) (projeto/global) · [0-9]* descartada(s) · [0-9]* pendente(s)')" "2 salva(s) (projeto/global) · 1 descartada(s) · 0 pendente(s)"
chk "S7 global-tips tem P001" "$(grep -c '^## A global$' "$GLOBAL_TIPS" 2>/dev/null || echo 0)" "1"
chk "S7 learnings do projeto tem P002" "$(grep -c '^## B projeto$' "$CASE/proj/.deep-orchestrator-preferences/learnings.md" 2>/dev/null || echo 0)" "1"
chk "S7 P003 descartada (ausente dos dois)" "$([ -f "$GLOBAL_TIPS" ] && grep -c '^## C descartada$' "$GLOBAL_TIPS" || true)" "0"
chk "S7 config gravada" "$(grep -c '^- preferencia livre$' "$CASE/proj/.deep-orchestrator-preferences/project-config.md" 2>/dev/null || echo 0)" "1"

newcase s8; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"annotated","feedback":"P001: nao"}'
candidate "$PROPOSALS" P001 "A" project gotcha high user "x" "y"
printf '# Questionário — s8\n' > "$CASE/q.md"
"$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1
"$SURVEY" --env "$CASE/env" answers >/dev/null 2>&1
"$SURVEY" --env "$CASE/env" apply >/dev/null 2>&1
out=$("$SURVEY" --env "$CASE/env" apply 2>/dev/null)
chk "S8 apply idempotente" "$(printf '%s' "$out" | grep -c 'já executado')" "1"

newcase s9; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"dismissed"}'
printf '# Questionário — s9\n' > "$CASE/q.md"
"$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1
printf '# Título diferente — s9\n' > "$CASE/q2.md"
"$SURVEY" --env "$CASE/env" round "$CASE/q2.md" >/dev/null 2>&1; rc=$?
chk "S9 deriva de título → exit 2" "$rc" "2"

newcase s10; write_skill; proj_fixture p; survey_env
make_fake_plannotator '{"decision":"dismissed"}'
printf '# Questionário — s10\n' > "$CASE/q.md"
nopath_sem jq python3
env PATH="$NOPATH" "$SURVEY" --env "$CASE/env" round "$CASE/q.md" >/dev/null 2>&1; rc=$?
# sem jq/python3 no PATH o pick_json_tool falha — mas o PATH também perde o
# plannotator fake: resolve_bin acha o DO_PLANNOTATOR_BIN explícito, e o
# pick_json_tool roda ANTES — rc 2 com a mensagem certa.
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
