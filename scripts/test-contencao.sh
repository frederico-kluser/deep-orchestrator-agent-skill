#!/usr/bin/env bash
# Testes de aceitação do MODO CONTIDO — A1..A20 + A22/A25/A26 (57 asserções)
set -uo pipefail
SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
CTX="$SKILL/scripts/do-context.sh"
WT="$SKILL/scripts/do-wt.sh"
LAB="${TMPDIR:-/tmp}/do-accept-$$"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (esperado='$3' obtido='$2')"; fi; }
# pval <CHAVE> <arquivo-env>: extrai o valor da linha CHAVE='...' (portável, sem grep -P)
pval() { sed -n "s/.*$1='\([^']*\)'.*/\1/p" "$2"; }

rm -rf "$LAB"; mkdir -p "$LAB"; cd "$LAB"
trap 'rm -rf "$LAB"' EXIT   # nunca deixar labs /tmp/do-accept-* órfãos
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- fixture: repo principal + worktree irmã + worktree de terceiro ----------
git init -q main && cd main
mkdir -p src && echo 'print("v1")' > src/app.py && echo root > root.txt
printf 'node_modules/\n.venv/\n' > .gitignore
git add -A && git commit -qm init
git worktree add -q ../wtA -b feat/x
git worktree add -q ../wtThird -b thirdparty
cd "$LAB"

echo "=== A1: cwd = subdiretório da árvore principal → MODE=normal ==="
mkdir -p main/src/deep
out=$(cd main/src/deep && "$CTX" --quiet 2>&1); env1=$(echo "$out" | tail -1)
chk "A1 MODE" "$(pval MODE "$env1")" "normal"
chk "A1 BASE_DIR" "$(pval BASE_DIR "$env1")" "$LAB/main"

echo "=== A2: cwd = subdiretório de worktree vinculada → MODE=contido ==="
mkdir -p wtA/src/deep
out=$(cd wtA/src/deep && "$CTX" --quiet 2>&1); ENVF=$(echo "$out" | tail -1)
chk "A2 MODE" "$(pval MODE "$ENVF")" "contido"
chk "A2 BASE_DIR" "$(pval BASE_DIR "$ENVF")" "$LAB/wtA"
chk "A2 BASE_BRANCH" "$(pval BASE_BRANCH "$ENVF")" "feat/x"
chk "A2 MAIN_ROOT" "$(pval MAIN_ROOT "$ENVF")" "$LAB/main"
chk "A4 PLACEMENT" "$(pval PLACEMENT "$ENVF")" "sibling"
chk "A4 CHILD_ROOT prefixo" "$(pval CHILD_ROOT "$ENVF" | sed "s#/[^/]*\$##")" "$LAB/.wtA-do"
chk "A2 SKILL_HOME" "$(pval SKILL_HOME "$ENVF")" "$SKILL"

echo "=== A3: HEAD destacado / sem commits / não-repo ==="
git -C wtThird checkout -q --detach
(cd wtThird && "$CTX" --quiet >/dev/null 2>&1); chk "A3 detached exit" "$?" "4"
git -C wtThird checkout -q thirdparty
git init -q empty && (cd empty && "$CTX" --quiet >/dev/null 2>&1); chk "A3 sem commits exit" "$?" "5"
mkdir -p norepo && (cd norepo && "$CTX" --quiet >/dev/null 2>&1); chk "A3 não-repo exit" "$?" "3"

echo "=== A5: worktree hospedada em <repo>/.claude/worktrees/<x> → nested ==="
git -C main worktree add -q "$LAB/main/.claude/worktrees/embedded" -b emb
out=$(cd main/.claude/worktrees/embedded && "$CTX" --quiet 2>&1); env5=$(echo "$out"|tail -1)
chk "A5 PLACEMENT" "$(pval PLACEMENT "$env5")" "nested"

echo "=== A6/A7/A11: onda completa com 2 filhas ==="
# sujeira preexistente do usuário na worktree (A10)
echo "MINHA EDICAO" >> wtA/root.txt
echo "rascunho" > wtA/meu-rascunho.txt
# re-bootstrap para o baseline capturar a sujeira
out=$(cd wtA && "$CTX" --quiet 2>&1); ENVF=$(echo "$out"|tail -1)
. "$ENVF"
MAIN_HEAD_BEFORE=$(git -C "$LAB/main" rev-parse HEAD)
THIRD_BEFORE=$(git -C "$LAB/wtThird" rev-parse --abbrev-ref HEAD)

"$WT" new feature onda1-cache >/dev/null || bad "A6 new onda1-cache"
"$WT" new feature onda1-schema >/dev/null || bad "A6 new onda1-schema"
chk "A6 filhas em CHILD_ROOT" "$(ls "$CHILD_ROOT" | tr '\n' ' ')" "onda1-cache onda1-schema "
chk "A4 gstatus esconde estado" "$(gstatus | grep -c deep-orchestrator)" "0"
chk "A4 add -A puro não pega filha" "$(cd "$BASE_DIR" && git add -A --dry-run 2>&1 | grep -c 'embedded git')" "0"
git -C "$BASE_DIR" reset -q 2>/dev/null

echo 'CACHE' > "$CHILD_ROOT/onda1-cache/cache.py"
git -C "$CHILD_ROOT/onda1-cache" add -A && git -C "$CHILD_ROOT/onda1-cache" commit -qm wip
echo 'SCHEMA' > "$CHILD_ROOT/onda1-schema/schema.py"   # de propósito NÃO commitado

"$WT" merge onda1-cache  "onda1-cache: adiciona cache" >/dev/null || bad "A6 merge cache"
"$WT" merge onda1-schema "onda1-schema: adiciona schema" >/dev/null || bad "A6 merge schema (restos)"
chk "A6 2 squash commits" "$(git -C "$BASE_DIR" rev-list --count HEAD)" "3"
chk "A6 restos não commitados foram salvos" "$(test -f "$BASE_DIR/schema.py" && echo sim || echo nao)" "sim"

# A11: remove aceita filha própria travada
"$WT" remove onda1-cache >/dev/null 2>&1; chk "A11 remove filha própria" "$?" "0"
# A11: recusa worktree de terceiro (mesmo travada)
git -C "$LAB/main" worktree lock --reason "alguem-mais" "$LAB/wtThird" 2>/dev/null
"$WT" remove naoexiste >/dev/null 2>&1; chk "A11 recusa nome desconhecido" "$?" "1"
chk "A7 worktree de terceiro sobreviveu" "$(test -d "$LAB/wtThird" && echo sim || echo nao)" "sim"
chk "A7 branch de terceiro intacto" "$(git -C "$LAB/wtThird" rev-parse --abbrev-ref HEAD)" "$THIRD_BEFORE"

"$WT" sweep >/dev/null 2>&1
chk "A6 branches da execução apagados" "$(git -C "$BASE_DIR" branch --list "$BRANCH_NS/*" | wc -l)" "0"
chk "A6 archive refs criados" "$(git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID" | wc -l)" "2"

echo "=== A6b: projeto principal intacto ==="
chk "A6 MAIN_ROOT HEAD" "$(git -C "$LAB/main" rev-parse HEAD)" "$MAIN_HEAD_BEFORE"
chk "A6 verify" "$("$WT" verify 2>&1 | tail -1)" "CONTENÇÃO OK"

echo "=== A11b: guarda de CHILD_ROOT (linha forjada apontando para worktree de terceiro) ==="
printf '%s\tfeature\tinvasor\tx\t%s\t\t\t\tMERGED\n' "$RUN_ID" "$LAB/wtThird" >> "$OWNED"
"$WT" remove invasor >/dev/null 2>&1; chk "A11b recusa fora de CHILD_ROOT" "$?" "1"
chk "A11b verify detecta a linha forjada" "$("$WT" verify 2>&1 | tail -1)" "CONTENÇÃO QUEBRADA — registre no TASK_PLAN e no relatório final"
sed -i '/invasor/d' "$OWNED"

echo "=== A10: COMMIT-FINAL estagia o NOSSO, preserva o do usuário ==="
echo "EXPLAINER" > "$BASE_DIR/EXPLAINER.html"          # artefato NOSSO, criado depois do baseline
echo "mais rascunho" >> "$BASE_DIR/meu-rascunho.txt"   # sujeira do usuário, continua sujeira
out=$("$WT" stage-delta 2>&1)
case "$(git -C "$BASE_DIR" diff --cached --name-only)" in *EXPLAINER.html*) ok "A10 artefato nosso estagiado" ;;
  *) bad "A10 EXPLAINER.html NAO foi estagiado" ;; esac
staged=$(git -C "$BASE_DIR" diff --cached --name-only | tr '\n' ' ')
case "$staged" in *meu-rascunho*|*root.txt*) bad "A10 sujeira do usuário foi estagiada: $staged" ;;
                  *) ok "A10 sujeira do usuário preservada (estagiado: ${staged:-nada})" ;; esac
git -C "$BASE_DIR" commit -qm "chore: entrega" && git -C "$BASE_DIR" reset -q
"$WT" stage-delta >/dev/null 2>&1
git -C "$BASE_DIR" commit -qm "chore: entrega" >/dev/null 2>&1 || git -C "$BASE_DIR" commit -q --allow-empty -m "chore: entrega"

echo "=== A15: merge recusa índice sujo da raiz-de-mundo ==="
echo "trabalho do usuario" > "$BASE_DIR/staged-pelo-usuario.txt"
git -C "$BASE_DIR" add staged-pelo-usuario.txt
"$WT" new feature onda2-guarda >/dev/null 2>&1
echo x > "$CHILD_ROOT/onda2-guarda/novo.txt"
git -C "$CHILD_ROOT/onda2-guarda" add -A && git -C "$CHILD_ROOT/onda2-guarda" commit -qm wip
"$WT" merge onda2-guarda "nao deveria passar" >/dev/null 2>&1; chk "A15 merge recusa índice sujo" "$?" "1"
chk "A15 nada foi commitado" "$(git -C "$BASE_DIR" log --oneline -1 --format=%s)" "chore: entrega"
chk "A15 arquivo do usuário segue apenas estagiado" "$(git -C "$BASE_DIR" diff --cached --name-only)" "staged-pelo-usuario.txt"
git -C "$BASE_DIR" reset -q && rm -f "$BASE_DIR/staged-pelo-usuario.txt"
"$WT" mark onda2-guarda MERGED >/dev/null; "$WT" remove onda2-guarda >/dev/null 2>&1; "$WT" drop-branch onda2-guarda >/dev/null 2>&1

echo "=== A8: duas execuções concorrentes → namespaces disjuntos ==="
e1=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); sleep 1
e2=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 )
n1=$(pval BRANCH_NS "$e1"); n2=$(pval BRANCH_NS "$e2")
if [ "$n1" != "$n2" ]; then ok "A8 namespaces disjuntos ($n1 != $n2)"; else bad "A8 namespaces iguais"; fi


echo "=== A12: reuso de execução em andamento vs --new-run ==="
r1=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$r1"
"$WT" new feature onda9-pendente >/dev/null
r2=$( (cd wtA && "$CTX" --quiet) | tail -1 )
chk "A12 reusa run com pendência" "$r2" "$r1"
r3=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 )
if [ "$r3" != "$r1" ]; then ok "A12 --new-run cria execução nova"; else bad "A12 --new-run reusou"; fi
. "$r1"; "$WT" mark onda9-pendente MERGED >/dev/null
"$WT" remove onda9-pendente >/dev/null 2>&1; "$WT" drop-branch onda9-pendente >/dev/null 2>&1

echo "=== A13/A14: stage-delta com acentos, espaços e prefixos ambíguos ==="
env14=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env14"
printf 'user\n' > "$BASE_DIR/notas.md.bak"          # sujeira do usuário (baseline)
printf 'user\n' > "$BASE_DIR/rascunho do usuario.txt"
env15=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env15"
printf 'nosso\n' > "$BASE_DIR/notas.md"             # nosso: prefixo de notas.md.bak
printf 'nosso\n' > "$BASE_DIR/relatório final.md"   # nosso: acento + espaço
out=$("$WT" stage-delta 2>&1); rc=$?
staged=$(git -C "$BASE_DIR" -c core.quotePath=false diff --cached --name-only | tr "\n" "|")
chk "A13 stage-delta exit 0" "$rc" "0"
case "$staged" in *"relatório final.md"*) ok "A13 path com acento e espaço estagiado" ;;
  *) bad "A13 path com acento/espaço NÃO estagiado: [$staged]" ;; esac
case "$staged" in *notas.md*) ok "A14 path prefixo-de-sujeira estagiado" ;;
  *) bad "A14 notas.md foi confundido com notas.md.bak" ;; esac
case "$staged" in *notas.md.bak*|*"rascunho do usuario"*) bad "A14 sujeira do usuário estagiada" ;;
  *) ok "A14 sujeira do usuário preservada" ;; esac
git -C "$BASE_DIR" reset -q; rm -f "$BASE_DIR/notas.md" "$BASE_DIR/relatório final.md" "$BASE_DIR/notas.md.bak" "$BASE_DIR/rascunho do usuario.txt"

echo "=== A16: remove --artifacts não apaga diretório RASTREADO ==="
env16=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env16"
"$WT" new feature onda9-art >/dev/null
mkdir -p "$CHILD_ROOT/onda9-art/bin" && echo '#!/bin/sh' > "$CHILD_ROOT/onda9-art/bin/setup"
printf 'node_modules/\n' > "$CHILD_ROOT/onda9-art/.gitignore"
mkdir -p "$CHILD_ROOT/onda9-art/node_modules/x" && echo 1 > "$CHILD_ROOT/onda9-art/node_modules/x/i.js"
git -C "$CHILD_ROOT/onda9-art" add -A && git -C "$CHILD_ROOT/onda9-art" commit -qm "bin rastreado"
"$WT" mark onda9-art MERGED >/dev/null
"$WT" remove onda9-art --artifacts >/dev/null 2>&1
chk "A16 worktree removida" "$(test -d "$CHILD_ROOT/onda9-art" && echo sim || echo nao)" "nao"
"$WT" drop-branch onda9-art >/dev/null 2>&1

echo "=== A17: gstatus não substitui o excludesFile global do usuário ==="
printf '*.swp\n' > "$LAB/global-ignore"
git -C wtA config --local core.excludesFile "$LAB/global-ignore"
env17=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env17"
touch "$BASE_DIR/x.swp"
chk "A17 arquivo globalmente ignorado não aparece" "$(gstatus | grep -c 'x.swp')" "0"
chk "A17 estado da skill continua escondido" "$(gstatus | grep -c 'deep-orchestrator')" "0"
rm -f "$BASE_DIR/x.swp"; git -C wtA config --local --unset core.excludesFile

echo "=== A18/A19: verify distingue vazamento nosso de trabalho do usuário ==="
env18=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env18"
chk "A18 baseline limpo" "$("$WT" verify 2>&1 | tail -1)" "CONTENÇÃO OK"
mkdir -p "$LAB/main/node_modules/left-pad" && echo 1 > "$LAB/main/node_modules/left-pad/index.js"
out18=$("$WT" verify 2>&1)
case "$out18" in *"working tree do projeto principal mudou"*) ok "A18 node_modules no principal é detectado" ;;
  *) bad "A18 escape por arquivo ignorado passou batido: $out18" ;; esac
rm -rf "$LAB/main/node_modules"
echo "edicao do usuario" >> "$LAB/main/a.txt"
git -C "$LAB/main" add -A && git -C "$LAB/main" commit -qm "usuario trabalhando no principal"
out19=$("$WT" verify 2>&1); rc19=$?
case "$out19" in *"não por commits desta execução"*) ok "A19 trabalho do usuário no principal = ALERTA, não violação" ;;
  *) bad "A19 falso alarme: $out19" ;; esac
chk "A19 verify não falha por trabalho do usuário" "$rc19" "0"

echo "=== A20: commit do sub-agente com -C fica na filha ==="
env20=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env20"
"$WT" new feature onda9-commit >/dev/null
head_antes=$(git -C "$BASE_DIR" rev-parse HEAD)
echo 'trabalho' > "$CHILD_ROOT/onda9-commit/entrega.txt"
# comando LITERAL do template do sub-agente
git -C "$CHILD_ROOT/onda9-commit" add -A -- ':(exclude,top).deep-orchestrator' \
  && git -C "$CHILD_ROOT/onda9-commit" commit -qm "wip"
chk "A20 raiz-de-mundo intacta" "$(git -C "$BASE_DIR" rev-parse HEAD)" "$head_antes"
chk "A20 commit foi para o branch da filha" "$(git -C "$CHILD_ROOT/onda9-commit" log --oneline -1 --format=%s)" "wip"
chk "A20 estado da skill não entrou no commit" "$(git -C "$CHILD_ROOT/onda9-commit" show --name-only --format= HEAD | grep -c deep-orchestrator)" "0"
"$WT" mark onda9-commit MERGED >/dev/null; "$WT" remove onda9-commit >/dev/null 2>&1; "$WT" drop-branch onda9-commit >/dev/null 2>&1

echo "=== A22a: undo com edição tracked do usuário no baseline → revert preserva a edição ==="
echo "edicao-do-usuario" >> wtA/root.txt
env22a=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env22a"
"$WT" new feature onda22a-undo >/dev/null
echo 'FEAT22A' > "$CHILD_ROOT/onda22a-undo/feat22a.py"
git -C "$CHILD_ROOT/onda22a-undo" add -A && git -C "$CHILD_ROOT/onda22a-undo" commit -qm wip
"$WT" merge onda22a-undo "onda22a-undo: adiciona feat22a" >/dev/null || bad "A22a merge"
"$WT" undo onda22a-undo >/dev/null 2>&1
if [ "$(grep -c 'edicao-do-usuario' "$BASE_DIR/root.txt")" = 1 ] \
   && [ "$(git -C "$BASE_DIR" log --oneline -1 --format=%s)" = 'Revert "onda22a-undo: adiciona feat22a"' ]; then
  ok "A22a undo reverteu (log mostra Revert) e preservou a edição do usuário em root.txt"
else
  bad "A22a (grep='$(grep -c 'edicao-do-usuario' "$BASE_DIR/root.txt")' log='$(git -C "$BASE_DIR" log --oneline -1 --format=%s)')"
fi

echo "=== A22b: undo com working tree sem modificações tracked → reset --hard arquivado ==="
git -C wtA checkout -q -- root.txt
env22b=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env22b"
"$WT" new feature onda22b-undo >/dev/null
echo 'FEAT22B' > "$CHILD_ROOT/onda22b-undo/feat22b.py"
git -C "$CHILD_ROOT/onda22b-undo" add -A && git -C "$CHILD_ROOT/onda22b-undo" commit -qm wip
"$WT" merge onda22b-undo "onda22b-undo: adiciona feat22b" >/dev/null || bad "A22b merge"
pre22b=$(git -C "$BASE_DIR" rev-parse HEAD~1)
"$WT" undo onda22b-undo >/dev/null 2>&1
if [ "$(git -C "$BASE_DIR" rev-parse HEAD)" = "$pre22b" ] \
   && [ "$(git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID" | grep -c 'undo-onda22b-undo')" = 1 ]; then
  ok "A22b undo usou reset --hard (HEAD voltou ao pré-merge; commit arquivado em refs/do-archive)"
else
  bad "A22b (HEAD='$(git -C "$BASE_DIR" rev-parse HEAD)' pre='$pre22b' refs='$(git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID" | grep -c 'undo-onda22b-undo')')"
fi

echo "=== A22c: undo com fixture GRANDE (4000 untracked + 1 tracked) — caça o padrão SIGPIPE ==="
# O fixture pequeno (A22a) não manifesta o bug do `gstatus | grep -qv`:
# com saída de poucos KB o grep não fecha o pipe antes do git terminar.
# Com ~75KB de saída (4000 untracked + " M root.txt" no começo), o grep -q
# sai no 1º match, o pipe fecha, o git morre com SIGPIPE (141) e o pipefail
# vira a condição para o reset --hard COM edição tracked (verificado em lab).
git -C wtA checkout -q -- root.txt
env22c=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env22c"
"$WT" new feature onda22c-undo >/dev/null
echo 'FEAT22C' > "$CHILD_ROOT/onda22c-undo/feat22c.py"
git -C "$CHILD_ROOT/onda22c-undo" add -A && git -C "$CHILD_ROOT/onda22c-undo" commit -qm wip
"$WT" merge onda22c-undo "onda22c-undo: adiciona feat22c" >/dev/null || bad "A22c merge"
echo "edicao-do-usuario-22c" >> "$BASE_DIR/root.txt"
for i in $(seq 1 4000); do echo "$i" > "$BASE_DIR/bulk-$i.tmp"; done
"$WT" undo onda22c-undo >/dev/null 2>&1
if [ "$(grep -c 'edicao-do-usuario-22c' "$BASE_DIR/root.txt")" = 1 ] \
   && [ "$(git -C "$BASE_DIR" log --oneline -1 --format=%s)" = 'Revert "onda22c-undo: adiciona feat22c"' ]; then
  ok "A22c fixture grande (4000 untracked + tracked): undo fez revert e preservou a edição"
else
  bad "A22c (grep='$(grep -c 'edicao-do-usuario-22c' "$BASE_DIR/root.txt")' log='$(git -C "$BASE_DIR" log --oneline -1 --format=%s)')"
fi
rm -f "$BASE_DIR"/bulk-*.tmp

echo "=== A25: stage-delta com arquivo novo em diretório untracked preexistente ==="
mkdir -p wtA/docs && echo "notas do usuario" > wtA/docs/notas-do-usuario.md
env25=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env25"
echo 'gerado pela skill' > "$BASE_DIR/docs/gerado-pela-skill.md"
"$WT" stage-delta >/dev/null 2>&1
staged=$(git -C "$BASE_DIR" diff --cached --name-only | tr '\n' ' ')
novo=0; usuario=0
case "$staged" in *docs/gerado-pela-skill.md*) novo=1 ;; esac
case "$staged" in *notas-do-usuario*) usuario=1 ;; esac
if [ "$novo" = 1 ] && [ "$usuario" = 0 ]; then
  ok "A25 arquivo novo dentro de dir untracked preexistente estagiado; o do usuário não"
else
  bad "A25 (novo=$novo usuario=$usuario estagiado=[$staged])"
fi
git -C "$BASE_DIR" reset -q

echo "=== A26: clean-ignored-delta preserva ignorados pré-existentes, remove só os novos ==="
mkdir -p wtA/node_modules/pkg && echo 1 > wtA/node_modules/pkg/i.js
env26=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env26"
"$WT" clean-ignored-delta >/dev/null 2>&1
if [ "$(test -f "$BASE_DIR/node_modules/pkg/i.js" && echo sim || echo nao)" = sim ]; then
  ok "A26a node_modules pré-existente (no baseline de ignorados) intacto após o delta"
else
  bad "A26a node_modules do usuário foi apagado"
fi
mkdir -p "$BASE_DIR/.venv/bin" && echo 1 > "$BASE_DIR/.venv/bin/python"
"$WT" clean-ignored-delta >/dev/null 2>&1
if [ "$(test -e "$BASE_DIR/.venv" && echo sim || echo nao)" = nao ] \
   && [ "$(test -f "$BASE_DIR/node_modules/pkg/i.js" && echo sim || echo nao)" = sim ]; then
  ok "A26b .venv novo removido; node_modules pré-existente preservado"
else
  bad "A26b (venv='$(test -e "$BASE_DIR/.venv" && echo sim || echo nao)' node_modules='$(test -f "$BASE_DIR/node_modules/pkg/i.js" && echo sim || echo nao)')"
fi
rm -f "$DO_STATE/ignored-baseline.nul"
"$WT" clean-ignored-delta >/dev/null 2>&1; chk "A26c recusa sem baseline de ignorados" "$?" "1"

echo; printf 'RESULTADO: %s PASS, %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1
