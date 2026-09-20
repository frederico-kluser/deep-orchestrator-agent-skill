#!/usr/bin/env bash
# Testes de aceitação do MODO CONTIDO — A1..A20 + A22/A23/A25..A34 + A35..A56 (309 asserções)
# Equivalências do plano registradas aqui (NÃO duplicadas): A33 cobre o A21
# (undo com HEAD avançado); A32 cobre o A24 (wave-files após 2 squashes — o
# diff da onda já sai correto com a onda anterior fora do escopo).
# Cobertura F4-07 (robustez): A23 (conflito SEM sujar a raiz + re-merge; A23b =
# fluxo antigo com rollback), A28/A29 (exits 6/7/9 da FASE 0 — caracteres
# proibidos e colisão de prefixo), A30 (lock — sem lost update), A31
# (kind=validation — ciclo completo).
# Cobertura v4.1.0 (fechamento por tarefa): A35 (integrate + gate verde fecha
# filha e snapshot), A36 (gate vermelho rc 4; finish rc 3/4/--gate-ok), A37
# (close: validation, --discard/NEVER-MERGED, EMPTY), A38 (squash vazio rc 4;
# mark MERGED manual não apaga trabalho), A39 (hook que falha; rollback do
# índice), A40/A41 (purge: sujo, rc 3 + bloco, dir ausente, sem OK falso;
# ledger), A42 (sweep: snapshot órfão, feature ACTIVE), A43 (assert-clean
# --wave; new rc 6; DO_TEST_MODE=none), A44 (lock mkdir sem flock), A45
# (ledger de 9 colunas; --help; checklist), A46 (path com espaço/acento: gate
# sobre MERGED legado, snapshot -r2, undo+remove no ledger), A47 (re-integrate
# que perderia deleção/reversão do fix é RECUSADO, nunca "sem delta novo").
# Cobertura da rodada de revisão (DESIGN-2): A48 (HEAD destacado/`switch -c`:
# integrate RECUSA; close arquiva <nome>-HEAD e NUNCA classifica EMPTY), A49
# (re-integração preserva o pre do 1º squash; undo desfaz TODOS: árvore volta ao
# pre do 1º; wave-files vê a onda inteira), A50 (undo com outra filha no meio:
# 2 reverts, o alheio fica), A51 (gate vermelho + cauda => MERGED-PARTIAL no
# finish e no purge; parciais= no ledger; purge rc 3 com o bloco "NUNCA
# INTEGRADAS / PARCIAIS"), A52 (snapshot de test-onda(N-1) não trava `new fix
# ondaN-*`; hint manda resolver o PARENT), A53 (2º gate concorrente recusa rc 3
# sem tocar log/rc; .rc amarrado ao squash), A54 (kind=test com DO_TEST_MODE=e2e
# roda a etapa e2e sem --e2e; feature não roda; --e2e segue aceito), A55 (cartão
# do checklist = <step order> da FASE 3; checklist final = passos 0-8 da FASE 4;
# DO_QUESTION=1 acrescenta a rodada de pergunta), A56 (gate sobre filha MERGED
# com snapshot LEGADO vivo vira gate-pending — o vermelho não é ignorado).
# Portável para macOS (bash 3.2, BSD sed/wc, sem flock): nada de `sed -i`, nada
# de comparar `wc -l` cru como string, base temporária física e sem "//".
set -uo pipefail
SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
CTX="$SKILL/scripts/do-context.sh"
WT="$SKILL/scripts/do-wt.sh"
# Base FÍSICA e sem barra final: no macOS o TMPDIR termina em "/" (geraria "//"
# nos paths esperados) e /tmp é symlink para /private/tmp — o do-context resolve
# BASE_DIR pelo git (path real), então o esperado tem que ser o path real.
TMPBASE=$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || TMPBASE=$(cd /tmp && pwd -P)
LAB="$TMPBASE/do-accept-$$"
LAB27="$TMPBASE/do-accept-$$ espaço é acentuação"   # A27 (F4-06)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (esperado='$3' obtido='$2')"; fi; }
# pval <CHAVE> <arquivo-env>: extrai o valor da linha CHAVE='...' (portável, sem grep -P).
# ANCORADO no início da linha: o ENV_FILE tem DO_TEST_MODE='...', que um ".*MODE="
# solto também casaria (devolvendo duas linhas).
pval() { sed -n "s/^$1='\([^']*\)'.*/\1/p" "$2"; }

rm -rf "$LAB"; mkdir -p "$LAB"; cd "$LAB"
trap 'rm -rf -- "$LAB" "$LAB27" 2>/dev/null' EXIT   # nunca deixar labs /tmp/do-accept-* órfãos
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
chk "A4 gstatus esconde estado" "$(gstatus | grep -c deep-orchestrator-agent-skill)" "0"
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
chk "A6 branches da execução apagados" "$(git -C "$BASE_DIR" branch --list "$BRANCH_NS/*" | wc -l | tr -d ' ')" "0"
chk "A6 archive refs criados" "$(git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID" | wc -l | tr -d ' ')" "2"

echo "=== A6b: projeto principal intacto ==="
chk "A6 MAIN_ROOT HEAD" "$(git -C "$LAB/main" rev-parse HEAD)" "$MAIN_HEAD_BEFORE"
chk "A6 verify" "$("$WT" verify 2>&1 | tail -1)" "CONTENÇÃO OK"

echo "=== A11b: guarda de CHILD_ROOT (linha forjada apontando para worktree de terceiro) ==="
printf '%s\tfeature\tinvasor\tx\t%s\t\t\t\tMERGED\n' "$RUN_ID" "$LAB/wtThird" >> "$OWNED"
"$WT" remove invasor >/dev/null 2>&1; chk "A11b recusa fora de CHILD_ROOT" "$?" "1"
chk "A11b verify detecta a linha forjada" "$("$WT" verify 2>&1 | tail -1)" "CONTENÇÃO QUEBRADA — registre no TASK_PLAN e no relatório final"
grep -v 'invasor' "$OWNED" > "$OWNED.sem-invasor" && mv "$OWNED.sem-invasor" "$OWNED"

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
"$WT" close onda2-guarda --discard "fixture A15" >/dev/null 2>&1

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
. "$r1"; "$WT" close onda9-pendente >/dev/null 2>&1

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
"$WT" close onda9-art --discard "fixture A16" >/dev/null 2>&1

echo "=== A17: gstatus não substitui o excludesFile global do usuário ==="
printf '*.swp\n' > "$LAB/global-ignore"
git -C wtA config --local core.excludesFile "$LAB/global-ignore"
env17=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env17"
touch "$BASE_DIR/x.swp"
chk "A17 arquivo globalmente ignorado não aparece" "$(gstatus | grep -c 'x.swp')" "0"
chk "A17 estado da skill continua escondido" "$(gstatus | grep -c 'deep-orchestrator-agent-skill')" "0"
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
chk "A20 estado da skill não entrou no commit" "$(git -C "$CHILD_ROOT/onda9-commit" show --name-only --format= HEAD | grep -c deep-orchestrator-agent-skill)" "0"
"$WT" close onda9-commit --discard "fixture A20" >/dev/null 2>&1

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

echo "=== A23: merge com CONFLITO → detectado SEM sujar a raiz → resolução na filha → re-merge (F4-07.2) ==="
# Fixture ampliada (M5): além do arquivo em conflito, a filha MODIFICA outro
# tracked e CRIA um arquivo. O fluxo antigo deixava UU no índice e a
# meia-feature (tracked modificado + untracked novo) no working tree da raiz — o
# re-merge nunca convergia e o stage-delta engolia o resto. Agora o conflito é
# detectado por `git merge-tree` ANTES de tocar a árvore.
git -C wtA checkout -q -- root.txt
env23=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env23"
"$WT" new feature onda23-conflito >/dev/null
echo "versao da filha" > "$CHILD_ROOT/onda23-conflito/root.txt"
echo 'print("v23")' > "$CHILD_ROOT/onda23-conflito/src/app.py"
echo "novo da filha" > "$CHILD_ROOT/onda23-conflito/novo23.txt"
git -C "$CHILD_ROOT/onda23-conflito" add -A && git -C "$CHILD_ROOT/onda23-conflito" commit -qm wip
echo "versao da raiz" >> "$BASE_DIR/root.txt"
git -C "$BASE_DIR" add root.txt && git -C "$BASE_DIR" commit -qm "raiz-de-mundo mexeu em root.txt"
st23_antes=$(gstatus --untracked-files=all); head23_antes=$(git -C "$BASE_DIR" rev-parse HEAD)
out23=$("$WT" merge onda23-conflito "onda23-conflito: conflita" 2>&1); rc23=$?
if [ "$rc23" != 0 ] && case "$out23" in *CONFLITO*root.txt*) true ;; *) false ;; esac; then
  ok "A23 squash com conflito recusa (mensagem CONFLITO lista root.txt)"
else
  bad "A23 conflito (rc=$rc23 out=[$out23])"
fi
if [ "$(git -C "$BASE_DIR" diff --name-only --diff-filter=U | wc -l | tr -d ' ')" = 0 ] \
   && [ "$(gstatus --untracked-files=all)" = "$st23_antes" ] \
   && [ "$(git -C "$BASE_DIR" rev-parse HEAD)" = "$head23_antes" ] \
   && [ ! -e "$BASE_DIR/novo23.txt" ]; then
  ok "A23 conflito detectado SEM sujar a raiz (sem UU, status e HEAD idênticos ao pré-merge, sem novo23.txt)"
else
  bad "A23 raiz suja após conflito (uu='$(git -C "$BASE_DIR" diff --name-only --diff-filter=U | tr '\n' ' ')' status=[$(gstatus --untracked-files=all | tr '\n' '|')])"
fi
chk "A23 conflito não vira MERGED (status segue ACTIVE)" "$(awk -F'\t' 'NR>1 && $3=="onda23-conflito" {print $9}' "$OWNED")" "ACTIVE"
# Fluxo implementado (F4-07.2): resolver DENTRO da filha — a filha traz as
# mudanças da raiz com `git merge "$BASE_BRANCH"`, resolve lá e commita.
git -C "$CHILD_ROOT/onda23-conflito" merge -q "$BASE_BRANCH" >/dev/null 2>&1
echo "resolucao final" > "$CHILD_ROOT/onda23-conflito/root.txt"
git -C "$CHILD_ROOT/onda23-conflito" add -A && git -C "$CHILD_ROOT/onda23-conflito" commit -qm "resolucao do conflito na filha"
out23b=$("$WT" merge onda23-conflito "onda23-conflito: adiciona conflito (resolvido)" 2>&1); rc23b=$?
if [ "$rc23b" = 0 ] && [ "$(git -C "$BASE_DIR" diff --name-only --diff-filter=U | wc -l | tr -d ' ')" = 0 ] \
   && [ "$(grep -c 'resolucao final' "$BASE_DIR/root.txt")" = 1 ] \
   && [ "$(grep -c 'v23' "$BASE_DIR/src/app.py")" = 1 ] && [ -f "$BASE_DIR/novo23.txt" ]; then
  ok "A23 re-merge pós-conflito: sucesso, índice limpo, resolução + os 3 arquivos da filha aplicados"
else
  bad "A23 re-merge (rc=$rc23b out=[$out23b] uu='$(git -C "$BASE_DIR" diff --name-only --diff-filter=U | tr '\n' ' ')')"
fi
"$WT" remove onda23-conflito >/dev/null 2>&1; "$WT" drop-branch onda23-conflito >/dev/null 2>&1

echo "=== A23b: mesmo conflito pelo fluxo ANTIGO (git < 2.38, DO_WT_MERGE_TREE=0) → rollback imediato ==="
"$WT" new feature onda23-fb >/dev/null
echo "versao da filha fb" > "$CHILD_ROOT/onda23-fb/root.txt"
echo 'print("v23fb")' > "$CHILD_ROOT/onda23-fb/src/app.py"
echo "novo fb" > "$CHILD_ROOT/onda23-fb/novo23fb.txt"
git -C "$CHILD_ROOT/onda23-fb" add -A && git -C "$CHILD_ROOT/onda23-fb" commit -qm wip
echo "raiz mexeu de novo" >> "$BASE_DIR/root.txt"
git -C "$BASE_DIR" add root.txt && git -C "$BASE_DIR" commit -qm "raiz-de-mundo mexeu em root.txt (fb)"
st23fb=$(gstatus --untracked-files=all)
out23fb=$(DO_WT_MERGE_TREE=0 "$WT" merge onda23-fb "onda23-fb: conflita" 2>&1); rc23fb=$?
if [ "$rc23fb" != 0 ] && case "$out23fb" in *CONFLITO*) true ;; *) false ;; esac \
   && [ "$(gstatus --untracked-files=all)" = "$st23fb" ] \
   && [ "$(git -C "$BASE_DIR" diff --cached --name-only | wc -l | tr -d ' ')" = 0 ] && [ ! -e "$BASE_DIR/novo23fb.txt" ]; then
  ok "A23b fluxo antigo: conflito faz rollback (reset --merge) — raiz idêntica ao pré-merge, sem meia-feature"
else
  bad "A23b (rc=$rc23fb out=[$out23fb] status=[$(gstatus --untracked-files=all | tr '\n' '|')])"
fi
git -C "$CHILD_ROOT/onda23-fb" merge -q "$BASE_BRANCH" >/dev/null 2>&1
echo "resolucao fb" > "$CHILD_ROOT/onda23-fb/root.txt"
git -C "$CHILD_ROOT/onda23-fb" add -A && git -C "$CHILD_ROOT/onda23-fb" commit -qm "resolucao fb"
DO_WT_MERGE_TREE=0 "$WT" merge onda23-fb "onda23-fb: resolvido" >/dev/null 2>&1; chk "A23b re-merge converge no fluxo antigo" "$?" "0"
chk "A23b os arquivos da filha entraram" "$(test -f "$BASE_DIR/novo23fb.txt" && grep -c 'resolucao fb' "$BASE_DIR/root.txt")" "1"
"$WT" remove onda23-fb >/dev/null 2>&1; "$WT" drop-branch onda23-fb >/dev/null 2>&1

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

echo "=== A27: lab com ESPAÇO e ACENTO no nome — ponta a ponta (F4-06) ==="
# Espaço e acento SÃO permitidos pelo do-context (só aspa/TAB/newline são
# proibidos). O script roda com cwd dentro do lab — atenção às aspas.
rm -rf "$LAB27"; mkdir -p "$LAB27/main"
cd "$LAB27/main"
git init -q . && mkdir -p src && echo v1 > src/app.py && echo root > root.txt
git add -A && git commit -qm init
git worktree add -q ../wtA27 -b feat27
mkdir -p ../wtA27/src/deep
out27=$(cd ../wtA27/src/deep && "$CTX" --quiet 2>&1); env27=$(echo "$out27" | tail -1)
chk "A27 MODE" "$(pval MODE "$env27")" "contido"
chk "A27 BASE_DIR" "$(pval BASE_DIR "$env27")" "$LAB27/wtA27"
. "$env27"
"$WT" new feature onda27-a >/dev/null 2>&1; chk "A27 new" "$?" "0"
echo 'FEAT27' > "$CHILD_ROOT/onda27-a/feat27.txt"
git -C "$CHILD_ROOT/onda27-a" add -A && git -C "$CHILD_ROOT/onda27-a" commit -qm wip
"$WT" merge onda27-a "onda27-a: adiciona feat27" >/dev/null 2>&1; chk "A27 merge" "$?" "0"
chk "A27 squash no log" "$(git -C "$BASE_DIR" log --oneline -1 --format=%s)" "onda27-a: adiciona feat27"
"$WT" remove onda27-a >/dev/null 2>&1; "$WT" drop-branch onda27-a >/dev/null 2>&1
cd "$LAB"

echo "=== A28/A29: exits 6/7/9 da FASE 0 (validações do do-context.sh) ==="
git -C main worktree add -q "$LAB/wtA28" -b feat28
# (a) índice sujo → exit 6
echo x > wtA28/estagiado.txt && git -C wtA28 add estagiado.txt
out28a=$(cd wtA28 && "$CTX" --quiet 2>&1); rc28a=$?
chk "A28a índice sujo → exit 6" "$rc28a" "6"
git -C wtA28 reset -q && rm -f wtA28/estagiado.txt
# (b) branch com aspa simples ("it's") → exit 7 com mensagem de path
git -C main branch "it's"
git -C wtA28 checkout -q "it's"
out28b=$(cd wtA28 && "$CTX" --quiet 2>&1); rc28b=$?
chk "A28b branch com aspa simples → exit 7" "$rc28b" "7"
case "$out28b" in *aspa*) ok "A28b mensagem clara (aspa simples)" ;; *) bad "A28b sem mensagem de aspa: $out28b" ;; esac
git -C wtA28 checkout -q feat28; git -C main branch -D "it's" >/dev/null 2>&1
# (c) branch com newline: o git REFUSA criar refname com newline (check-ref-format
#     proíbe byte de controle) e REFUSA resolver um symref para refname inválido
#     ("failed to resolve HEAD as a valid ref") — verificado em lab. O único
#     estado possível é um HEAD corrompido, que a FASE 0 trata como HEAD não
#     resolvível: sai com erro CLARO (exit 4, "HEAD destacado"), nunca 0/3/5/6/8/9
#     enganoso. O guard de newline do próprio do-context (die 7) é exercitado em
#     (d) pelo MESMO case que cobre BASE_BRANCH.
brn=$(printf 'feat\nnl')
mkdir -p "$LAB/main/.git/refs/heads"
printf '%s\n' "$(git -C main rev-parse feat28)" > "$LAB/main/.git/refs/heads/$brn"
headf=$(git -C wtA28 rev-parse --git-path HEAD)
printf 'ref: refs/heads/%s\n' "$brn" > "$headf"
(cd wtA28 && "$CTX" --quiet >/dev/null 2>&1); chk "A28c symref corrompido com newline → erro claro (exit 4)" "$?" "4"
rm -f "$LAB/main/.git/refs/heads/$brn"
git -C wtA28 symbolic-ref HEAD refs/heads/feat28
# (d) path com newline (diretório com newline no nome) → exit 7
nl_dir="$LAB/$(printf 'nl\npath')"
mkdir -p "$nl_dir/inner" && git -C "$nl_dir" init -q && git -C "$nl_dir" commit -q --allow-empty -m init
out28d=$(cd "$nl_dir/inner" && "$CTX" --quiet 2>&1); rc28d=$?
chk "A28d path com newline → exit 7" "$rc28d" "7"
case "$out28d" in *newline*) ok "A28d mensagem clara (newline)" ;; *) bad "A28d sem mensagem de newline: $out28d" ;; esac
# (e) colisão de PREFIXO do namespace (F4-07.4): branch do/wtA28 pré-existente
#     na raiz (prefixo do namespace do/wtA28/<run>/...) → FASE 0 recusa com
#     exit 9 — o cmd_new NUNCA chega a falhar depois. O branch precisa ser o
#     PREFIXO de um namespace NUNCA usado antes: o slug wtA28 é novo (as runs
#     anteriores da suíte usam do/wtA/<run>, que já virou diretório).
git -C main branch do/wtA28
out28e=$(cd wtA28 && "$CTX" --quiet --new-run 2>&1); rc28e=$?
chk "A28e branch do/wtA28 (prefixo do namespace) → exit 9" "$rc28e" "9"
case "$out28e" in *prefixo*) ok "A29 mensagem clara de colisão de prefixo" ;; *) bad "A29 sem mensagem de colisão: $out28e" ;; esac
git -C main branch -D do/wtA28 >/dev/null 2>&1
git -C main worktree remove --force "$LAB/wtA28" >/dev/null 2>&1
git -C main branch -D feat28 >/dev/null 2>&1

echo "=== A32: wave-files resolve a filha MERGED quando a 1ª filha da onda está BLOCKED ==="
# Fixture (F2-09): onda ANTERIOR mergeada (onda31-prev) cujo arquivo NÃO pode entrar
# no diff da onda atual; 1ª filha da onda (onda32-a) criada e marcada BLOCKED SEM
# merge (não tem pre_merge_sha); 2ª filha (onda32-b) com um arquivo, mergeada.
env32=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env32"
"$WT" new feature onda31-prev >/dev/null
echo 'PREV32' > "$CHILD_ROOT/onda31-prev/prev32.txt"
git -C "$CHILD_ROOT/onda31-prev" add -A && git -C "$CHILD_ROOT/onda31-prev" commit -qm wip
"$WT" merge onda31-prev "onda31-prev: adiciona prev32" >/dev/null
"$WT" finish onda31-prev >/dev/null    # onda 31 fechada: o `new` recusa a onda 32 com sobra (rc 6)
"$WT" new feature onda32-a >/dev/null
echo 'X32' > "$CHILD_ROOT/onda32-a/x32.txt"
git -C "$CHILD_ROOT/onda32-a" add -A && git -C "$CHILD_ROOT/onda32-a" commit -qm wip
"$WT" mark onda32-a BLOCKED >/dev/null
"$WT" new feature onda32-b >/dev/null
echo 'Y32' > "$CHILD_ROOT/onda32-b/y32.txt"
git -C "$CHILD_ROOT/onda32-b" add -A && git -C "$CHILD_ROOT/onda32-b" commit -qm wip
"$WT" merge onda32-b "onda32-b: adiciona y32" >/dev/null
# (a) nome da 1ª filha BLOCKED -> resolução automática pela MERGED do prefixo onda32-
out32a=$("$WT" wave-files onda32-a 2>&1); rc32a=$?
# (b) nome da filha MERGED -> caminho direto preservado (zero surpresa)
out32b=$("$WT" wave-files onda32-b 2>&1); rc32b=$?
if [ "$rc32a" = 0 ] && [ "$rc32b" = 0 ] \
   && case "$out32a" in *y32.txt*) true ;; *) false ;; esac \
   && case "$out32a" in *prev32.txt*|*x32.txt*) false ;; *) true ;; esac \
   && case "$out32b" in *y32.txt*) true ;; *) false ;; esac \
   && case "$out32b" in *prev32.txt*|*x32.txt*) false ;; *) true ;; esac; then
  ok "A32 wave-files com 1ª filha BLOCKED resolve pela MERGED (diff só com y32.txt) e o caminho direto segue OK"
else
  bad "A32 (a: rc=$rc32a out=[$out32a]; b: rc=$rc32b out=[$out32b])"
fi
# (c) ramo test-: filha MERGED com prefixo test-ondaN-* também resolve (F2-09)
"$WT" new test test-onda32-x >/dev/null
echo 'Z32' > "$CHILD_ROOT/test-onda32-x/z32.txt"
git -C "$CHILD_ROOT/test-onda32-x" add -A && git -C "$CHILD_ROOT/test-onda32-x" commit -qm wip
"$WT" merge test-onda32-x "test-onda32-x: adiciona z32" >/dev/null
"$WT" new test test-onda32-y >/dev/null
"$WT" mark test-onda32-y BLOCKED >/dev/null
out32c=$("$WT" wave-files test-onda32-y 2>&1); rc32c=$?
if [ "$rc32c" = 0 ] \
   && case "$out32c" in *z32.txt*) true ;; *) false ;; esac \
   && case "$out32c" in *prev32.txt*) false ;; *) true ;; esac; then
  ok "A32-c filha MERGED com prefixo test-ondaN- resolve (diff contém z32.txt, sem prev32)"
else
  bad "A32-c (rc=$rc32c out=[$out32c])"
fi
"$WT" close onda32-a --discard "fixture A32" >/dev/null 2>&1
"$WT" remove onda32-b >/dev/null 2>&1; "$WT" drop-branch onda32-b >/dev/null 2>&1
"$WT" remove test-onda32-x >/dev/null 2>&1; "$WT" drop-branch test-onda32-x >/dev/null 2>&1
"$WT" close test-onda32-y >/dev/null 2>&1

echo "=== A33: FALHA TARDIA de gate de snapshot — undo da 1ª com HEAD avançado (F3-01) ==="
# O gate do snapshot da 1ª filha só ficou vermelho DEPOIS do merge da 2ª (gate
# em worktree efêmera, fora da seção crítica). O undo precisa reverter EXATAMENTE
# o squash da 1ª, deixando o squash da 2ª INTACTO no log, e arquivar o commit
# desfeito em refs/do-archive/$RUN_ID/undo-<nome>.
env33=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env33"
"$WT" new feature onda33-a >/dev/null
echo 'A33' > "$CHILD_ROOT/onda33-a/a33.txt"
git -C "$CHILD_ROOT/onda33-a" add -A && git -C "$CHILD_ROOT/onda33-a" commit -qm wip
"$WT" merge onda33-a "onda33-a: adiciona a33" >/dev/null || bad "A33 merge a"
"$WT" new feature onda33-b >/dev/null
echo 'B33' > "$CHILD_ROOT/onda33-b/b33.txt"
git -C "$CHILD_ROOT/onda33-b" add -A && git -C "$CHILD_ROOT/onda33-b" commit -qm wip
"$WT" merge onda33-b "onda33-b: adiciona b33" >/dev/null || bad "A33 merge b"
"$WT" undo onda33-a >/dev/null 2>&1
if [ "$(git -C "$BASE_DIR" log --oneline -1 --format=%s)" = 'Revert "onda33-a: adiciona a33"' ] \
   && [ "$(git -C "$BASE_DIR" log --oneline -1 --format=%s 'HEAD~1')" = 'onda33-b: adiciona b33' ] \
   && [ "$(git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID" | grep -c 'undo-onda33-a')" = 1 ]; then
  ok "A33 undo da 1ª com HEAD avançado: revert exato do squash da 1ª, 2ª intacta, undo arquivado"
else
  bad "A33 (log='$(git -C "$BASE_DIR" log --oneline -2 | tr '\n' '|')' refs='$(git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID" | tr '\n' '|')')"
fi
# Restauração (como o orquestrador faria após o fix): re-merge da filha corrigida
"$WT" merge onda33-a "onda33-a: adiciona a33 (re-merge pós-fix)" >/dev/null || bad "A33 re-merge"
chk "A33 re-merge restaurou a33.txt" "$(test -f "$BASE_DIR/a33.txt" && echo sim || echo nao)" "sim"
"$WT" remove onda33-a >/dev/null 2>&1; "$WT" drop-branch onda33-a >/dev/null 2>&1
"$WT" remove onda33-b >/dev/null 2>&1; "$WT" drop-branch onda33-b >/dev/null 2>&1

echo "=== A34: gate-pending bloqueia o fim de onda (sweep sai != 0), F3-01 ==="
env34=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env34"
"$WT" new feature onda34-a >/dev/null
echo 'A34' > "$CHILD_ROOT/onda34-a/a34.txt"
git -C "$CHILD_ROOT/onda34-a" add -A && git -C "$CHILD_ROOT/onda34-a" commit -qm wip
"$WT" merge onda34-a "onda34-a: adiciona a34" >/dev/null || bad "A34 merge"
"$WT" mark onda34-a gate-pending >/dev/null
out34=$("$WT" sweep 2>&1); rc34=$?
if [ "$rc34" != 0 ] && case "$out34" in *gate-pending*) true ;; *) false ;; esac; then
  ok "A34 sweep sai != 0 com aviso de gate-pending (fim de onda não fecha)"
else
  bad "A34 (rc=$rc34 out=[$out34])"
fi
"$WT" mark onda34-a MERGED >/dev/null
out34b=$("$WT" sweep 2>&1); rc34b=$?
chk "A34 sweep OK após mark MERGED" "$rc34b" "0"
"$WT" remove onda34-a >/dev/null 2>&1; "$WT" drop-branch onda34-a >/dev/null 2>&1

echo "=== A30: lock — dois marks PARALELOS no owned.tsv sem lost update (F4-07.1) ==="
# Sem lock, os dois row_set fariam read-modify-write + mv em rajada e o ÚLTIMO
# venceria — um dos status sumiria. Com lock (flock, ou mkdir onde não há
# flock — macOS), ambos caem.
env30=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env30"
"$WT" new feature onda30-a >/dev/null
"$WT" new feature onda30-b >/dev/null
# BARREIRA: os dois processos só PROSSEGUEM depois que ambos sinalizaram —
# sem isso, o catch do lost update vira corrida de timing (se o 2º mark
# começar depois do 1º terminar, o bug passa batido — verificado em lab).
bar30="$LAB/a30-barrier"
( touch "$bar30.1"; while [ ! -f "$bar30.2" ]; do sleep 0.01; done
  "$WT" mark onda30-a BLOCKED >/dev/null 2>&1 ) &
( touch "$bar30.2"; while [ ! -f "$bar30.1" ]; do sleep 0.01; done
  "$WT" mark onda30-b ORPHANED >/dev/null 2>&1 ) &
wait
rm -f "$bar30".*
st30a=$(awk -F'\t' 'NR>1 && $3=="onda30-a" {print $9}' "$OWNED")
st30b=$(awk -F'\t' 'NR>1 && $3=="onda30-b" {print $9}' "$OWNED")
n30=$(wc -l < "$OWNED" | tr -d ' ')
if [ "$st30a" = BLOCKED ] && [ "$st30b" = ORPHANED ] && [ "$n30" = 3 ]; then
  ok "A30 marks paralelos com lock: sem lost update (a=BLOCKED b=ORPHANED, $n30 linhas)"
else
  bad "A30 (a=$st30a b=$st30b linhas=$n30)"
fi
"$WT" close onda30-a >/dev/null 2>&1; "$WT" close onda30-b >/dev/null 2>&1

echo "=== A31: kind=validation — ciclo completo new → remove → drop-branch (F2-02) ==="
env31=$( (cd wtA && "$CTX" --quiet --new-run) | tail -1 ); . "$env31"
"$WT" new validation val-onda1-gate >/dev/null 2>&1; chk "A31 new validation" "$?" "0"
chk "A31 kind registrado" "$(awk -F'\t' 'NR>1 && $3=="val-onda1-gate" {print $2}' "$OWNED")" "validation"
chk "A31 branch sob o namespace" "$(awk -F'\t' 'NR>1 && $3=="val-onda1-gate" {print $4}' "$OWNED" | sed 's#/[^/]*$##')" "$BRANCH_NS"
"$WT" remove val-onda1-gate >/dev/null 2>&1; chk "A31 remove" "$?" "0"
chk "A31 status REMOVED" "$(awk -F'\t' 'NR>1 && $3=="val-onda1-gate" {print $9}' "$OWNED")" "REMOVED"
"$WT" drop-branch val-onda1-gate >/dev/null 2>&1; chk "A31 drop-branch aceita (REMOVED)" "$?" "0"

# =============================================================================
# v4.1.0 — fechamento POR TAREFA (integrate/gate/finish/close), portão inter-onda
# (assert-clean + new rc 6), purge honesto (rc 3 + bloco NUNCA INTEGRADAS),
# ledger de 11 colunas e lock sem flock. Helpers locais:
newrun() { local e; e=$( (cd "$LAB/wtA" && "$CTX" --quiet --new-run) | tail -1 ); . "$e"; }
# mk_child <kind> <nome> <arquivo>: cria a filha e COMMITA um arquivo nela
mk_child() {
  "$WT" new "$1" "$2" >/dev/null 2>&1 || return 1
  echo "$3" > "$CHILD_ROOT/$2/$3.txt"
  git -C "$CHILD_ROOT/$2" add -A && git -C "$CHILD_ROOT/$2" commit -qm "wip $2"
}
col() { awk -F'\t' -v n="$1" -v c="$2" 'NR>1 && $3==n {print $c}' "$OWNED"; }   # <nome> <coluna>
nbranches() { git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/heads/$BRANCH_NS/" | wc -l | tr -d ' '; }
narchive() { git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID/$1" | wc -l | tr -d ' '; }
nlocked() { git -C "$BASE_DIR" worktree list --porcelain | grep -c "run=$RUN_ID"; }
has() { case "$1" in *"$2"*) echo sim ;; *) echo nao ;; esac; }                    # <texto> <trecho>
git -C "$LAB/wtA" checkout -q -- root.txt 2>/dev/null

echo "=== A35: integrate + gate VERDE fecha a filha E o snapshot sozinho (I-CLEAN) ==="
newrun
mk_child feature onda35-a a35 || bad "A35 mk_child"
"$WT" gate-set build 'test -f a35.txt' >/dev/null      # só passa se o cwd for o snapshot no SHA pós-merge
"$WT" gate-set test 'test "$HUSKY" = 0 && test "$CI" = 1' >/dev/null
"$WT" gate-set lint 'true' >/dev/null
"$WT" gate-set lint '' >/dev/null                      # string vazia = remove = "sem lint"
chk "A35 gate-set '' remove a etapa" "$(test -e "$DO_STATE/gate/lint.cmd" && echo existe || echo removida)" "removida"
out35=$("$WT" integrate onda35-a "onda35-a: adiciona a35" 2>&1); rc35=$?
snap35=$(printf '%s\n' "$out35" | sed -n 's/^SNAPSHOT=//p')
chk "A35 integrate rc" "$rc35" "0"
chk "A35 integrate imprime SNAPSHOT=<path> existente" "$(test -n "$snap35" && test -d "$snap35" && echo sim || echo nao)" "sim"
chk "A35 filha fica gate-pending" "$(col onda35-a 9)" "gate-pending"
chk "A35 snapshot registrado (kind/parent)" "$(col int-onda35-a 2)/$(col int-onda35-a 10)" "integration/onda35-a"
chk "A35 linhas novas têm 11 colunas (10/11 nunca vazias)" \
    "$(awk -F'\t' 'NR>1 && (NF!=11 || $10=="" || $11=="") {c++} END{print c+0}' "$OWNED")" "0"
chk "A35 snapshot nasce no SHA pós-merge" "$(git -C "$snap35" rev-parse HEAD)" "$(col onda35-a 8)"
out35g=$("$WT" gate onda35-a 2>&1); rc35g=$?
chk "A35 gate verde rc" "$rc35g" "0"
chk "A35 gate imprime o veredito" "$(printf '%s\n' "$out35g" | tail -1)" "GATE VERDE — onda35-a fechado"
chk "A35 gate gravou rc=0 amarrado ao squash (.rc = '0 <post>')" \
    "$(awk '{print $1}' "$DO_STATE/gates/onda35-a.rc")/$(awk '{print $2}' "$DO_STATE/gates/onda35-a.rc")" "0/$(col onda35-a 8)"
if [ ! -e "$CHILD_ROOT/onda35-a" ] && [ ! -e "$snap35" ] && [ "$(nbranches)" = 0 ] && [ "$(nlocked)" = 0 ]; then
  ok "A35 verde fechou SOZINHO: filha, snapshot, os 2 branches e os 2 registros travados"
else
  bad "A35 sobra após o verde (filha=$(test -e "$CHILD_ROOT/onda35-a" && echo viva) snap=$(test -e "$snap35" && echo vivo) branches=$(nbranches) locked=$(nlocked))"
fi
chk "A35 ledger: filha REMOVED/MERGED" "$(col onda35-a 9)/$(col onda35-a 11)" "REMOVED/MERGED"
chk "A35 ledger: snapshot REMOVED/DISPOSABLE" "$(col int-onda35-a 9)/$(col int-onda35-a 11)" "REMOVED/DISPOSABLE"
chk "A35 branch arquivado antes de apagar" "$(narchive onda35-a)" "1"
chk "A35 o squash está em BASE_BRANCH" "$(test -f "$BASE_DIR/a35.txt" && echo sim || echo nao)" "sim"
"$WT" finish onda35-a >/dev/null 2>&1; chk "A35 finish é idempotente (já fechado = rc 0)" "$?" "0"
"$WT" gate onda35-a >/dev/null 2>&1; chk "A35 gate em filha já fechada = rc 0" "$?" "0"

echo "=== A36: gate VERMELHO não limpa nada (rc 4); finish recusa gate-pending sem rc verde ==="
mk_child feature onda35-b b35 || bad "A36 mk_child"
"$WT" gate-set test 'echo FALHOU-DE-PROPOSITO; exit 7' >/dev/null
out36=$("$WT" integrate onda35-b "onda35-b: adiciona b35" 2>&1)
snap36=$(printf '%s\n' "$out36" | sed -n 's/^SNAPSHOT=//p')
out36g=$("$WT" gate onda35-b 2>&1); rc36g=$?
chk "A36 gate vermelho rc" "$rc36g" "4"
chk "A36 veredito nomeia a etapa" "$(has "$out36g" "GATE VERMELHO — onda35-b: a etapa 'test' falhou")" "sim"
chk "A36 mostra o fim do log" "$(has "$out36g" "FALHOU-DE-PROPOSITO")" "sim"
if [ -d "$CHILD_ROOT/onda35-b" ] && [ -d "$snap36" ] && [ "$(col onda35-b 9)" = gate-pending ] && [ "$(nbranches)" = 2 ]; then
  ok "A36 vermelho NÃO limpou nada (filha, snapshot e branches vivos; status gate-pending)"
else
  bad "A36 vermelho limpou algo (st=$(col onda35-b 9) branches=$(nbranches))"
fi
"$WT" finish onda35-b >/dev/null 2>&1; chk "A36 finish com gate vermelho → rc 4" "$?" "4"
chk "A36 finish recusado não limpou" "$(test -d "$CHILD_ROOT/onda35-b" && echo viva || echo sumiu)" "viva"
echo running > "$DO_STATE/gates/onda35-b.rc"
"$WT" finish onda35-b >/dev/null 2>&1; chk "A36 finish com gate rodando → rc 3" "$?" "3"
rm -f "$DO_STATE/gates/onda35-b.rc"
"$WT" finish onda35-b >/dev/null 2>&1; chk "A36 finish sem veredito de gate → rc 3" "$?" "3"
"$WT" sweep >/dev/null 2>&1; chk "A36 sweep não fecha com gate-pending (rc != 0)" "$(test $? != 0 && echo sim || echo nao)" "sim"
"$WT" finish onda35-b --gate-ok >/dev/null 2>&1; chk "A36 finish --gate-ok (LLM atesta o verde) → rc 0" "$?" "0"
if [ ! -e "$CHILD_ROOT/onda35-b" ] && [ ! -e "$snap36" ] && [ "$(nbranches)" = 0 ]; then
  ok "A36 finish fechou a filha e TODOS os snapshots do parent"
else
  bad "A36 finish deixou sobra (branches=$(nbranches))"
fi
"$WT" finish onda35-b >/dev/null 2>&1; chk "A36 finish idempotente" "$?" "0"
"$WT" new feature onda35-c >/dev/null 2>&1
"$WT" finish onda35-c >/dev/null 2>&1; chk "A36 finish recusa filha ACTIVE (rc 1)" "$?" "1"
"$WT" gate onda35-c >/dev/null 2>&1; chk "A36 gate recusa filha não integrada (rc 5)" "$?" "5"
"$WT" close onda35-c >/dev/null 2>&1

echo "=== A37: close — validation, feature com commits (exige --discard), EMPTY, integrada ==="
newrun
"$WT" new validation val-onda37-gate >/dev/null 2>&1
mkdir -p "$CHILD_ROOT/val-onda37-gate/coverage" && echo x > "$CHILD_ROOT/val-onda37-gate/coverage/lcov.info"
"$WT" remove val-onda37-gate >/dev/null 2>&1; chk "A37 remove recusa validation suja (untracked não-ignorado)" "$?" "1"
"$WT" close val-onda37-gate >/dev/null 2>&1; chk "A37 close de validation suja → rc 0" "$?" "0"
chk "A37 validation REMOVED/DISPOSABLE, sem dir" \
    "$(col val-onda37-gate 9)/$(col val-onda37-gate 11)/$(test -e "$CHILD_ROOT/val-onda37-gate" && echo dir || echo semdir)" "REMOVED/DISPOSABLE/semdir"
mk_child feature onda37-a a37 || bad "A37 mk_child"
out37=$("$WT" close onda37-a 2>&1); rc37=$?
chk "A37 close recusa feature com commits sem --discard" "$rc37" "1"
chk "A37 a recusa ensina o --discard" "$(has "$out37" "--discard")" "sim"
chk "A37 recusa não tocou na filha" "$(test -d "$CHILD_ROOT/onda37-a" && col onda37-a 9)" "ACTIVE"
"$WT" close onda37-a --discard "" >/dev/null 2>&1; chk "A37 --discard sem motivo → erro de uso (rc 2)" "$?" "2"
echo "resto nao commitado" > "$CHILD_ROOT/onda37-a/resto37.txt"
"$WT" close onda37-a --discard "abandonada no teste" >/dev/null 2>&1; chk "A37 close --discard → rc 0" "$?" "0"
chk "A37 ledger registra NEVER-MERGED:<motivo>" "$(col onda37-a 11)" "NEVER-MERGED:abandonada no teste"
chk "A37 ref de arquivo existe" "$(narchive onda37-a)" "1"
chk "A37 o rescue-commit salvou o resto não commitado no arquivo" \
    "$(git -C "$BASE_DIR" ls-tree -r --name-only "refs/do-archive/$RUN_ID/onda37-a" | grep -c 'resto37.txt')" "1"
chk "A37 filha e branch fechados" "$(test -e "$CHILD_ROOT/onda37-a" && echo dir || echo semdir)/$(nbranches)" "semdir/0"
"$WT" close onda37-a >/dev/null 2>&1; chk "A37 close idempotente" "$?" "0"
"$WT" new feature onda37-vazia >/dev/null 2>&1
"$WT" close onda37-vazia >/dev/null 2>&1; chk "A37 close de filha vazia e limpa dispensa --discard" "$?" "0"
chk "A37 outcome EMPTY" "$(col onda37-vazia 11)" "EMPTY"
mk_child feature onda37-m m37 && "$WT" merge onda37-m "onda37-m: adiciona m37" >/dev/null 2>&1
out37m=$("$WT" close onda37-m --discard "nao deveria" 2>&1); rc37m=$?
chk "A37 close recusa filha INTEGRADA" "$rc37m" "1"
chk "A37 a recusa manda usar finish" "$(has "$out37m" "use finish")" "sim"
"$WT" finish onda37-m >/dev/null 2>&1; chk "A37 finish fecha a MERGED" "$?" "0"

echo "=== A38: squash VAZIO não vira MERGED (rc 4); mark MERGED manual não apaga trabalho ==="
"$WT" new feature onda37-nada >/dev/null 2>&1
head38=$(git -C "$BASE_DIR" rev-parse HEAD)
out38=$("$WT" merge onda37-nada "onda37-nada: nada" 2>&1); rc38=$?
chk "A38 merge vazio rc" "$rc38" "4"
chk "A38 mensagem VAZIO" "$(has "$out38" "VAZIO:")" "sim"
chk "A38 status segue ACTIVE, sem squash registrado" "$(col onda37-nada 9)/$(col onda37-nada 8)" "ACTIVE/"
chk "A38 nada foi commitado" "$(git -C "$BASE_DIR" rev-parse HEAD)" "$head38"
"$WT" integrate onda37-nada "onda37-nada: nada" >/dev/null 2>&1; chk "A38 integrate devolve o rc do merge (4)" "$?" "4"
chk "A38 merge falhou → nada de snapshot" "$(col int-onda37-nada 3)" ""
"$WT" close onda37-nada >/dev/null 2>&1
mk_child feature onda37-mark k37 || bad "A38 mk_child"
"$WT" mark onda37-mark MERGED >/dev/null; "$WT" remove onda37-mark >/dev/null 2>&1
"$WT" drop-branch onda37-mark >/dev/null 2>&1; chk "A38 drop-branch recusa MERGED por mark manual (sem squash)" "$?" "1"
chk "A38 o branch com o trabalho sobreviveu" "$(nbranches)" "1"
"$WT" finish onda37-mark >/dev/null 2>&1; chk "A38 finish também recusa (sem squash registrado)" "$?" "1"
"$WT" close onda37-mark --discard "mark manual" >/dev/null 2>&1; chk "A38 close --discard fecha e arquiva" "$?/$(narchive onda37-mark)" "0/1"

echo "=== A39: hook pre-commit que FALHA não trava o merge; commit recusado → índice desfeito ==="
newrun
mk_child feature onda39-hook h39 || bad "A39 mk_child"
echo "resto sem commit" > "$CHILD_ROOT/onda39-hook/resto39.txt"     # força o wip-commit DENTRO da filha
mk_child feature onda39-pcm p39 || bad "A39 mk_child pcm"
echo 'print("v39")' > "$CHILD_ROOT/onda39-pcm/src/app.py"
git -C "$CHILD_ROOT/onda39-pcm" add -A && git -C "$CHILD_ROOT/onda39-pcm" commit -qm "wip pcm"
hooks39="$LAB/main/.git/hooks"; mkdir -p "$hooks39"
printf '#!/bin/sh\necho "lint-staged: FAIL" >&2\nexit 1\n' > "$hooks39/pre-commit"; chmod +x "$hooks39/pre-commit"
"$WT" merge onda39-hook "onda39-hook: adiciona h39" >/dev/null 2>&1; chk "A39 merge passa com pre-commit que falha (--no-verify)" "$?" "0"
chk "A39 squash e restos entraram" "$(test -f "$BASE_DIR/h39.txt" && test -f "$BASE_DIR/resto39.txt" && echo sim || echo nao)" "sim"
rm -f "$hooks39/pre-commit"
# --no-verify NÃO pula o prepare-commit-msg: é o "falhou mesmo assim" do contrato.
printf '#!/bin/sh\nexit 1\n' > "$hooks39/prepare-commit-msg"; chmod +x "$hooks39/prepare-commit-msg"
st39=$(gstatus --untracked-files=all)
out39=$("$WT" merge onda39-pcm "onda39-pcm: adiciona p39" 2>&1); rc39=$?
rm -f "$hooks39/prepare-commit-msg"
chk "A39 commit do squash recusado → rc != 0" "$(test "$rc39" != 0 && echo sim || echo nao)" "sim"
if git -C "$BASE_DIR" diff --cached --quiet && [ "$(gstatus --untracked-files=all)" = "$st39" ] && [ ! -e "$BASE_DIR/p39.txt" ]; then
  ok "A39 índice do squash desfeito (paths restaurados do HEAD, untracked criado removido)"
else
  bad "A39 rollback incompleto (status=[$(gstatus --untracked-files=all | tr '\n' '|')] out=[$out39])"
fi
chk "A39 a mensagem não culpa o usuário" "$(has "$out39" "ESTAGIADAS que não são desta execução")" "nao"
"$WT" merge onda39-pcm "onda39-pcm: adiciona p39" >/dev/null 2>&1; chk "A39 re-merge é possível depois do rollback" "$?" "0"
"$WT" finish onda39-hook >/dev/null 2>&1; "$WT" finish onda39-pcm >/dev/null 2>&1

echo "=== A40: purge — árvore suja/untracked, nunca-integrada (rc 3 + bloco), diretório ausente ==="
newrun
mk_child feature onda40-ok ok40 || bad "A40 mk_child ok"
out40i=$("$WT" integrate onda40-ok "onda40-ok: adiciona ok40" 2>&1); snap40=$(printf '%s\n' "$out40i" | sed -n 's/^SNAPSHOT=//p')
mkdir -p "$snap40/coverage" && echo x > "$snap40/coverage/lcov.info"          # untracked NÃO ignorado no snapshot
mk_child feature onda40-blk blk40 || bad "A40 mk_child blk"
echo "edicao nao commitada" >> "$CHILD_ROOT/onda40-blk/root.txt"              # tracked modificado
echo "untracked" > "$CHILD_ROOT/onda40-blk/solto40.txt"
"$WT" mark onda40-blk BLOCKED >/dev/null
mk_child test test-onda40-cov cov40 || bad "A40 mk_child test"                # commitada, NUNCA mergeada (ACTIVE)
"$WT" new validation val-onda40-gate >/dev/null 2>&1; echo lixo > "$CHILD_ROOT/val-onda40-gate/relatorio.junit"
mk_child feature onda40-sumiu s40 || bad "A40 mk_child sumiu"
rm -rf "$CHILD_ROOT/onda40-sumiu"                                             # diretório ausente, registro TRAVADO fica
"$WT" new feature onda40-vazia >/dev/null 2>&1
out40=$("$WT" purge 2>&1); rc40=$?
chk "A40 purge com nunca-integrada sai rc 3" "$rc40" "3"
chk "A40 imprime o bloco obrigatório" "$(has "$out40" "PURGE: NUNCA INTEGRADAS / PARCIAIS (obrigatorio no relatorio final):")" "sim"
blk40=$(printf '%s\n' "$out40" | sed -n '/NUNCA INTEGRADAS/,$p')
if [ "$(has "$blk40" "onda40-blk")" = sim ] && [ "$(has "$blk40" "test-onda40-cov")" = sim ] && [ "$(has "$blk40" "onda40-sumiu")" = sim ] \
   && [ "$(has "$blk40" "refs/do-archive/$RUN_ID/test-onda40-cov")" = sim ] \
   && [ "$(has "$blk40" "onda40-ok")" = nao ] && [ "$(has "$blk40" "onda40-vazia")" = nao ] && [ "$(has "$blk40" "val-onda40-gate")" = nao ]; then
  ok "A40 o bloco lista as 3 nunca-integradas (nome/kind/ref) e SÓ elas"
else
  bad "A40 bloco errado: [$blk40]"
fi
chk "A40 todas as linhas fechadas" "$(awk -F'\t' 'NR>1 && $9!="REMOVED" {c++} END{print c+0}' "$OWNED")" "0"
if [ "$(ls -A "$CHILD_ROOT" 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && [ "$(nbranches)" = 0 ] && [ "$(nlocked)" = 0 ]; then
  ok "A40 purge fechou TUDO: árvore suja, untracked não-ignorado, dir ausente (sem worktree, branch nem registro travado)"
else
  bad "A40 sobrou (dirs=[$(ls -A "$CHILD_ROOT" | tr '\n' ' ')] branches=$(nbranches) locked=$(nlocked)) out=[$out40]"
fi
chk "A40 'PURGE OK' só depois de ledger E realidade fecharem" "$(has "$out40" "PURGE OK")" "sim"
chk "A40 outcomes: integrada/snapshot/validation/vazia" \
    "$(col onda40-ok 11)|$(col int-onda40-ok 11)|$(col val-onda40-gate 11)|$(col onda40-vazia 11)" "MERGED|DISPOSABLE|DISPOSABLE|EMPTY"
chk "A40 outcome NEVER-MERGED:purge" "$(col onda40-blk 11)|$(col test-onda40-cov 11)" "NEVER-MERGED:purge|NEVER-MERGED:purge"
chk "A40 nada se perde: a edição não commitada está no arquivo" \
    "$(git -C "$BASE_DIR" show "refs/do-archive/$RUN_ID/onda40-blk:root.txt" | grep -c 'edicao nao commitada')" "1"
chk "A40 idem o untracked" "$(git -C "$BASE_DIR" ls-tree -r --name-only "refs/do-archive/$RUN_ID/onda40-blk" | grep -c 'solto40.txt')" "1"
"$WT" purge >/dev/null 2>&1; chk "A40 purge idempotente (rc 3 de novo: o bloco continua obrigatório)" "$?" "3"
"$WT" assert-clean >/dev/null 2>&1; chk "A40 assert-clean (fim da execução) → rc 0" "$?" "0"
led40=$("$WT" ledger 2>&1)
chk "A40 ledger: cabeçalho" "$(printf '%s\n' "$led40" | head -1 | tr -s ' ')" "NOME KIND ONDA STATUS OUTCOME ARCHIVE_REF"
chk "A40 ledger: linha da nunca-integrada com a ref de arquivo" \
    "$(printf '%s\n' "$led40" | grep '^test-onda40-cov ' | tr -s ' ')" "test-onda40-cov test 40 REMOVED NEVER-MERGED:purge refs/do-archive/$RUN_ID/test-onda40-cov"
chk "A40 ledger: snapshot herda a onda do parent" "$(printf '%s\n' "$led40" | awk '$1=="int-onda40-ok" {print $3}')" "40"

echo "=== A41: purge com diretório ausente / sobra real NÃO declara 'PURGE OK' falso ==="
newrun
mk_child feature onda41-a a41 && "$WT" merge onda41-a "onda41-a: adiciona a41" >/dev/null 2>&1
rm -rf "$CHILD_ROOT/onda41-a"                       # MERGED, dir sumiu, registro travado + branch vivos
mkdir -p "$CHILD_ROOT/intruso"                      # diretório em CHILD_ROOT fora do ledger
out41=$("$WT" purge 2>&1); rc41=$?
chk "A41 realidade não fechou → rc 1" "$rc41" "1"
chk "A41 NÃO declara PURGE OK" "$(has "$out41" "PURGE OK")" "nao"
chk "A41 aponta a sobra" "$(has "$out41" "SEM linha no owned.tsv")" "sim"
rmdir "$CHILD_ROOT/intruso"
out41b=$("$WT" purge 2>&1); rc41b=$?
chk "A41 sem a sobra → rc 0 e PURGE OK" "$rc41b/$(has "$out41b" "PURGE OK")" "0/sim"
chk "A41 dir ausente: registro travado e branch foram embora de verdade" "$(nlocked)/$(nbranches)" "0/0"
mk_child feature onda41-b b41 || bad "A41 mk_child b"
rm -rf "$CHILD_ROOT/onda41-b"
out41r=$("$WT" remove onda41-b 2>&1); rc41r=$?
chk "A41 remove com dir ausente desregistra SÓ aquela entrada" "$rc41r/$(nlocked)/$(col onda41-b 9)" "0/0/REMOVED"
out41n=$("$WT" remove nao-existe-41 2>&1); rc41n=$?
chk "A41 remove de nome inexistente: erro claro" "$rc41n/$(has "$out41n" "não está no owned.tsv")/$(has "$out41n" "path vazio")" "1/sim/nao"
"$WT" close onda41-b --discard "fixture A41" >/dev/null 2>&1

echo "=== A42: sweep fecha snapshot órfão e FALHA com feature ACTIVE (test ACTIVE só é listada) ==="
newrun
mk_child feature onda42-a a42 || bad "A42 mk_child a"
out42i=$("$WT" integrate onda42-a "onda42-a: adiciona a42" 2>&1); snap42=$(printf '%s\n' "$out42i" | sed -n 's/^SNAPSHOT=//p')
# parent fechado pelos PRIMITIVOS (ritual antigo esquecendo o snapshot) → snapshot órfão
"$WT" mark onda42-a MERGED >/dev/null; "$WT" remove onda42-a >/dev/null 2>&1; "$WT" drop-branch onda42-a >/dev/null 2>&1
chk "A42 remove pelos primitivos registra o destino" "$(col onda42-a 11)" "MERGED"
mk_child feature onda42-b b42 || bad "A42 mk_child b"
"$WT" new test test-onda42-x >/dev/null 2>&1
out42=$("$WT" sweep 2>&1); rc42=$?
chk "A42 sweep com feature ACTIVE → rc != 0" "$(test "$rc42" != 0 && echo sim || echo nao)" "sim"
chk "A42 sweep fechou o snapshot órfão" "$(test -e "$snap42" && echo vivo || echo fechado)/$(col int-onda42-a 9)/$(col int-onda42-a 11)" "fechado/REMOVED/DISPOSABLE"
chk "A42 sweep nomeia a não integrada e o conserto" "$(has "$out42" "onda42-b")/$(has "$out42" "NÃO INTEGRADA")/$(has "$out42" "integrate onda42-b")" "sim/sim/sim"
chk "A42 sweep NÃO destrói a feature ACTIVE nem a subwave" "$(test -d "$CHILD_ROOT/onda42-b" && test -d "$CHILD_ROOT/test-onda42-x" && echo vivas || echo sumiu)" "vivas"
"$WT" close onda42-b --discard "fixture A42" >/dev/null 2>&1
"$WT" sweep >/dev/null 2>&1; chk "A42 só subwave test ACTIVE → sweep rc 0 (apenas listada)" "$?" "0"
"$WT" close test-onda42-x >/dev/null 2>&1

echo "=== A43: assert-clean --wave barra sobra e aceita subwave N-1; new recusa a onda N+1 (rc 6) ==="
newrun
mk_child feature onda1-x x43 || bad "A43 mk_child"
"$WT" new test test-onda1-t >/dev/null 2>&1
"$WT" new validation val-onda1-gate >/dev/null 2>&1
"$WT" assert-clean --wave 1 >/dev/null 2>&1; chk "A43 --wave 1: nada de onda anterior → rc 0" "$?" "0"
out43=$("$WT" assert-clean --wave 2 2>&1); rc43=$?
chk "A43 --wave 2 barra a feature ACTIVE da onda 1" "$rc43/$(has "$out43" "onda1-x")/$(has "$out43" "conserto:")" "1/sim/sim"
chk "A43 --wave 2 aceita a subwave da onda N-1" "$(has "$out43" "test-onda1-t")/$(has "$out43" "val-onda1-gate")" "nao/nao"
out43n=$("$WT" new feature onda2-y 2>&1); rc43n=$?
chk "A43 new recusa a onda 2 com sobra da onda 1 (rc 6)" "$rc43n" "6"
chk "A43 a recusa traz a MESMA tabela de conserto" "$(has "$out43n" "onda1-x")/$(has "$out43n" "conserto:")" "sim/sim"
chk "A43 a recusa não criou nada" "$(test -e "$CHILD_ROOT/onda2-y" && echo dir || echo semdir)/$(col onda2-y 3)" "semdir/"
"$WT" new fix fix-final-y >/dev/null 2>&1; chk "A43 nome SEM onda (fix-final-*) não entra no portão" "$?" "0"
"$WT" close fix-final-y >/dev/null 2>&1
"$WT" close onda1-x --discard "fixture A43" >/dev/null 2>&1
"$WT" assert-clean --wave 2 >/dev/null 2>&1; chk "A43 sobra fechada → --wave 2 rc 0 (subwave N-1 em voo é aceita)" "$?" "0"
"$WT" new feature onda2-y >/dev/null 2>&1; chk "A43 new libera a onda 2" "$?" "0"
out43c=$("$WT" assert-clean --wave 3 2>&1); rc43c=$?
chk "A43 --wave 3 barra subwave da onda 1 (N-2) e a feature da onda 2" \
    "$rc43c/$(has "$out43c" "test-onda1-t")/$(has "$out43c" "val-onda1-gate")/$(has "$out43c" "onda2-y")" "1/sim/sim/sim"
"$WT" new feature onda3-z >/dev/null 2>&1; chk "A43 new recusa a onda 3 (rc 6)" "$?" "6"
"$WT" close test-onda1-t >/dev/null 2>&1; "$WT" close val-onda1-gate >/dev/null 2>&1
echo 'Y' > "$CHILD_ROOT/onda2-y/y43.txt"; git -C "$CHILD_ROOT/onda2-y" add -A; git -C "$CHILD_ROOT/onda2-y" commit -qm wip
"$WT" integrate onda2-y "onda2-y: adiciona y43" >/dev/null 2>&1
out43s=$("$WT" assert-clean --wave 3 2>&1)
chk "A43 snapshot herda a onda do parent e também barra" "$(has "$out43s" "int-onda2-y")" "sim"
"$WT" finish onda2-y --gate-ok >/dev/null 2>&1
"$WT" assert-clean --wave 3 >/dev/null 2>&1; chk "A43 tudo fechado → --wave 3 rc 0" "$?" "0"
mkdir -p "$CHILD_ROOT/intruso43"
out43r=$("$WT" assert-clean --wave 3 2>&1); rc43r=$?
chk "A43 (c) realidade x ledger: dir em CHILD_ROOT sem linha barra" "$rc43r/$(has "$out43r" "intruso43")" "1/sim"
rmdir "$CHILD_ROOT/intruso43"
out43t=$(DO_TEST_MODE=none "$WT" new test test-onda3-k 2>&1); rc43t=$?
chk "A43 DO_TEST_MODE=none recusa kind=test" "$(test "$rc43t" != 0 && echo sim || echo nao)/$(has "$out43t" "RECUSADO: TEST_MODE=none (no-test)")" "sim/sim"
DO_TEST_MODE=none "$WT" new feature test-onda3-k2 >/dev/null 2>&1
chk "A43 DO_TEST_MODE=none recusa nome test-onda* (qualquer kind)" "$(test $? != 0 && echo sim || echo nao)/$(col test-onda3-k2 3)" "sim/"
DO_TEST_MODE=none "$WT" new validation val-onda3-gate >/dev/null 2>&1; chk "A43 no-test NÃO desliga a validation" "$?" "0"
"$WT" close val-onda3-gate >/dev/null 2>&1
"$WT" new teste onda3-kind >/dev/null 2>&1; chk "A43 kind fora do conjunto é recusado" "$?" "1"

echo "=== A44: lock SEM flock (fallback mkdir) — escritas concorrentes não perdem linha ==="
newrun
DO_WT_NO_FLOCK=1 "$WT" new feature onda44-a >/dev/null 2>"$LAB/a44.err1"
DO_WT_NO_FLOCK=1 "$WT" new feature onda44-b >/dev/null 2>"$LAB/a44.err2"
chk "A44 AVISO do fallback no máximo 1x (por execução)" "$(cat "$LAB/a44.err1" "$LAB/a44.err2" | grep -c 'flock(1) ausente')" "1"
# Rajada: 2 processos reescrevendo (mark) + 1 append (new) ao mesmo tempo. Sem
# exclusão mútua o mv de um row_set sobrescreve o arquivo SEM a linha do new.
bar44="$LAB/a44-barrier"
( touch "$bar44.1"; while [ ! -f "$bar44.2" ]; do sleep 0.01; done
  for i in 1 2 3 4 5 6 7 8; do DO_WT_NO_FLOCK=1 "$WT" mark onda44-a ACTIVE; DO_WT_NO_FLOCK=1 "$WT" mark onda44-a BLOCKED; done >/dev/null 2>&1 ) &
( touch "$bar44.2"; while [ ! -f "$bar44.1" ]; do sleep 0.01; done
  for i in 1 2 3 4 5 6 7 8; do DO_WT_NO_FLOCK=1 "$WT" mark onda44-b ACTIVE; DO_WT_NO_FLOCK=1 "$WT" mark onda44-b ORPHANED; done >/dev/null 2>&1 ) &
while [ ! -f "$bar44.1" ] || [ ! -f "$bar44.2" ]; do sleep 0.01; done
DO_WT_NO_FLOCK=1 "$WT" new feature onda44-c >/dev/null 2>&1; rc44c=$?
wait
rm -f "$bar44".*
n44=$(wc -l < "$OWNED" | tr -d ' ')
if [ "$rc44c" = 0 ] && [ "$(col onda44-a 9)" = BLOCKED ] && [ "$(col onda44-b 9)" = ORPHANED ] && [ "$(col onda44-c 9)" = ACTIVE ] && [ "$n44" = 4 ]; then
  ok "A44 33 escritas concorrentes sem flock: nenhuma linha perdida (a=BLOCKED b=ORPHANED c=ACTIVE, $n44 linhas)"
else
  bad "A44 (rc_new=$rc44c a=$(col onda44-a 9) b=$(col onda44-b 9) c=$(col onda44-c 9) linhas=$n44)"
fi
chk "A44 lock liberado e sem temporário órfão" "$(ls "$DO_STATE" | grep -c 'owned.tsv.lock.d\|owned.tsv.tmp')" "0"
mkdir "$OWNED.lock.d" && echo 999999 > "$OWNED.lock.d/pid"          # lock VELHO: dono morto
DO_WT_NO_FLOCK=1 "$WT" mark onda44-c BLOCKED >/dev/null 2>&1; rc44s=$?
chk "A44 lock de dono morto é quebrado (não trava, não perde a escrita)" "$rc44s/$(col onda44-c 9)/$(test -e "$OWNED.lock.d" && echo preso || echo livre)" "0/BLOCKED/livre"
"$WT" close onda44-a >/dev/null 2>&1; "$WT" close onda44-b >/dev/null 2>&1; "$WT" close onda44-c >/dev/null 2>&1

echo "=== A45: ledger antigo de 9 colunas é tolerado; --help completo; checklist ==="
newrun
"$WT" new feature onda45-a >/dev/null 2>&1
cut -f1-9 "$OWNED" > "$OWNED.v9" && mv "$OWNED.v9" "$OWNED"           # simula owned.tsv da v4.0 (cabeçalho e linha de 9)
chk "A45 fixture: arquivo de 9 colunas" "$(awk -F'\t' 'NF!=9 {c++} END{print c+0}' "$OWNED")" "0"
"$WT" ledger >/dev/null 2>&1; chk "A45 ledger lê linha de 9 colunas" "$?" "0"
chk "A45 10/11 ausentes valem '-'" "$("$WT" ledger 2>/dev/null | awk '$1=="onda45-a" {print $5}')" "-"
mk_child feature onda45-b b45 || bad "A45 new sobre arquivo de 9 colunas"
chk "A45 linha NOVA nasce com 11 colunas mesmo sob cabeçalho de 9" "$(awk -F'\t' '$3=="onda45-b" {print NF}' "$OWNED")" "11"
"$WT" mark onda45-a BLOCKED >/dev/null 2>&1
chk "A45 a 1ª reescrita completa a linha antiga e o cabeçalho (11 colunas)" "$(awk -F'\t' 'NF!=11 {c++} END{print c+0}' "$OWNED")" "0"
chk "A45 status lido na coluna certa (7/8 vazias não colapsam)" "$(col onda45-a 9)/$(col onda45-a 7)$(col onda45-a 8)" "BLOCKED/"
"$WT" merge onda45-b "onda45-b: adiciona b45" >/dev/null 2>&1
out45p=$("$WT" purge 2>&1); rc45p=$?
chk "A45 purge sem nunca-integrada com trabalho → rc 0" "$rc45p/$(has "$out45p" "PURGE OK")/$(has "$out45p" "NUNCA INTEGRADAS")" "0/sim/nao"
chk "A45 purge: MERGED→finish, BLOCKED vazia→EMPTY" "$(col onda45-b 11)/$(col onda45-a 11)" "MERGED/EMPTY"
help45=$(env -i PATH="$PATH" bash "$WT" --help 2>&1); rc45h=$?
chk "A45 --help funciona SEM o ENV_FILE" "$rc45h" "0"
chk "A45 --help imprime o cabeçalho INTEIRO (antes truncava em sweep)" \
    "$(has "$help45" "do-wt.sh integrate")/$(has "$help45" "do-wt.sh purge")/$(has "$help45" "do-wt.sh verify")/$(has "$help45" "do-wt.sh mark")/$(has "$help45" "kind: feature")" "sim/sim/sim/sim/sim"
chk "A45 --help para na régua de fim (não vaza código)" "$(has "$help45" "set -uo pipefail")" "nao"
card45=$(env -i PATH="$PATH" bash "$WT" checklist 2>&1)
chk "A45 checklist: cartão fixo <= 30 linhas com o portão inter-onda" \
    "$(test "$(printf '%s\n' "$card45" | wc -l | tr -d ' ')" -le 30 && echo cabe || echo grande)/$(has "$card45" "assert-clean --wave")/$(has "$card45" "integrate")" "cabe/sim/sim"

echo "=== A46: path com ESPAÇO/ACENTO — merge legado + gate recria snapshot; re-integrate (-r2); undo+remove ==="
e46=$( (cd "$LAB27/wtA27" && "$CTX" --quiet --new-run) | tail -1 ); . "$e46"
mk_child feature onda46-a a46 || bad "A46 mk_child"
"$WT" merge onda46-a "onda46-a: adiciona a46" >/dev/null 2>&1          # primitivo legado: fica MERGED, sem snapshot
"$WT" gate-set test 'test -f fix46.txt' >/dev/null
"$WT" gate onda46-a >/dev/null 2>&1; rc46=$?
chk "A46 gate sobre MERGED legado recria o snapshot, roda e fica vermelho (rc 4, gate-pending)" \
    "$rc46/$(col onda46-a 9)/$(col int-onda46-a 10)" "4/gate-pending/onda46-a"
echo fix > "$CHILD_ROOT/onda46-a/fix46.txt"; git -C "$CHILD_ROOT/onda46-a" add -A; git -C "$CHILD_ROOT/onda46-a" commit -qm "fix na MESMA worktree"
out46=$("$WT" integrate onda46-a "onda46-a: fix" 2>/dev/null | tail -1)
chk "A46 re-integrate cria snapshot -r2 (nome já usado)" "$out46" "SNAPSHOT=$CHILD_ROOT/int-onda46-a-r2"
chk "A46 re-integrate invalida o veredito vermelho anterior" "$(test -e "$DO_STATE/gates/onda46-a.rc" && echo ficou || echo apagado)" "apagado"
"$WT" gate onda46-a >/dev/null 2>&1; chk "A46 gate roda no ÚLTIMO snapshot vivo → verde" "$?" "0"
chk "A46 finish fechou a filha e os DOIS snapshots" \
    "$(col onda46-a 11)/$(col int-onda46-a 9)/$(col int-onda46-a-r2 9)/$(ls -A "$CHILD_ROOT" | wc -l | tr -d ' ')/$(nbranches)" "MERGED/REMOVED/REMOVED/0/0"
mk_child feature onda46-u u46 && "$WT" merge onda46-u "onda46-u: adiciona u46" >/dev/null 2>&1
"$WT" undo onda46-u >/dev/null 2>&1; "$WT" remove onda46-u >/dev/null 2>&1
chk "A46 undo + remove NÃO some do ledger como integrada" "$(col onda46-u 9)/$(col onda46-u 11)" "REMOVED/NEVER-MERGED:revertida por undo"
"$WT" drop-branch onda46-u >/dev/null 2>&1; chk "A46 ciclo undo → remove → drop-branch continua fechando (F4-07.8)" "$?/$(narchive onda46-u)" "0/1"
"$WT" purge >/dev/null 2>&1; chk "A46 purge relata a revertida (rc 3)" "$?" "3"
chk "A46 verify" "$("$WT" verify 2>&1 | tail -1)" "CONTENÇÃO OK"
cd "$LAB"

echo "=== A47: re-integrate após gate vermelho NÃO perde deleção/reversão do fix em silêncio ==="
# Antes: a filha não contém o próprio squash, o merge-base segue no base_sha e o
# 3-way descartava a deleção e a reversão ("theirs == base"): saía "sem delta
# novo", rc 0, e o gate nunca mais ficava verde. Agora o merge RECUSA em memória
# (raiz intacta) com a lista de paths; o conserto é merge do BASE na filha + fix.
newrun
"$WT" new feature onda47-a >/dev/null 2>&1 || bad "A47 new"
w47="$CHILD_ROOT/onda47-a"; pre47=$(git -C "$BASE_DIR" rev-parse HEAD)
echo lixo > "$w47/lixo47.txt"; echo RUIM >> "$w47/root.txt"; echo bom > "$w47/bom47.txt"
git -C "$w47" add -A && git -C "$w47" commit -qm "feat 47"
"$WT" gate-set test 'test ! -f lixo47.txt && ! grep -q RUIM root.txt' >/dev/null
"$WT" integrate onda47-a "onda47-a: feat" >/dev/null 2>&1; "$WT" gate onda47-a >/dev/null 2>&1
chk "A47 gate vermelho (rc 4) com a filha preservada" "$?/$(col onda47-a 9)" "4/gate-pending"
git -C "$w47" rm -q lixo47.txt; git -C "$w47" checkout -q "$pre47" -- root.txt
git -C "$w47" commit -qm "fix: apaga lixo47 e desfaz RUIM"; tip47=$(git -C "$w47" rev-parse HEAD)
head47=$(git -C "$BASE_DIR" rev-parse HEAD); st47=$(git -C "$BASE_DIR" status --porcelain)
out47=$("$WT" integrate onda47-a "onda47-a: fix" 2>&1); rc47=$?
chk "A47 re-integrate que perderia o fix é RECUSADO (rc 1), nunca 'sem delta novo'" \
    "$rc47/$(has "$out47" "PERDERIA parte do fix")/$(has "$out47" "sem delta novo")" "1/sim/nao"
chk "A47 a recusa lista os DOIS paths (deleção e reversão) e o comando do merge na filha" \
    "$(has "$out47" "    lixo47.txt")/$(has "$out47" "    root.txt")/$(has "$out47" "git -C \"$w47\" merge \"$BASE_BRANCH\"")" "sim/sim/sim"
chk "A47 raiz intacta e nenhum snapshot novo" \
    "$(test "$(git -C "$BASE_DIR" rev-parse HEAD)" = "$head47" && echo mesmo)/$(test "$(git -C "$BASE_DIR" status --porcelain)" = "$st47" && echo igual)/$(col int-onda47-a-r2 3)" "mesmo/igual/"
git -C "$w47" merge -q -m "merge base" "$BASE_BRANCH" >/dev/null 2>&1
git -C "$w47" rm -q lixo47.txt; git -C "$w47" checkout -q "$tip47" -- root.txt; git -C "$w47" commit -qm "fix reaplicado"
"$WT" integrate onda47-a "onda47-a: fix" >/dev/null 2>&1; rc47i=$?
"$WT" gate onda47-a >/dev/null 2>&1
chk "A47 merge do BASE na filha + fix reaplicado → integrate OK, gate VERDE, fix inteiro na base" \
    "$rc47i/$?/$(test -f "$BASE_DIR/lixo47.txt" && echo ficou || echo apagado)/$(grep -c RUIM "$BASE_DIR/root.txt")/$(col onda47-a 11)" "0/0/apagado/0/MERGED"
"$WT" purge >/dev/null 2>&1; chk "A47 purge + verify" "$?/$("$WT" verify 2>&1 | tail -1)" "0/CONTENÇÃO OK"
cd "$LAB"

# =============================================================================
# Rodada final (DESIGN-2, revisão adversarial): A48 WT-F1 (HEAD destacado /
# `git switch -c`), A49/A50 WT-F2+BEH-01 (undo de TODOS os squashes; wave-files
# vê a onda inteira), A51 WT-F3 (MERGED-PARTIAL no finish e no purge; parciais=
# no ledger), A52 WT-F4/BEH-03 (snapshot de test-onda(N-1) não trava o `new fix`
# da onda N), A53 WT-F5 (2º gate concorrente recusa rc 3 sem tocar log/rc),
# A54 FT-03 (etapa e2e sozinha com DO_TEST_MODE=e2e), A55 B01 (cartões de passo
# = <step order> do SKILL.md).

echo "=== A48: HEAD destacado e 'git switch -c' — integrate RECUSA; close arquiva <nome>-HEAD e NUNCA classifica EMPTY ==="
newrun
mk_child feature onda48-a a48 || bad "A48 mk_child a"
w48="$CHILD_ROOT/onda48-a"
git -C "$w48" checkout -q --detach
echo extra > "$w48/extra48.txt"; echo sujo > "$w48/sujo48.txt"   # untracked: entra no wip-commit
git -C "$w48" add -A && git -C "$w48" commit -qm "trabalho em HEAD destacado"
head48=$(git -C "$BASE_DIR" rev-parse HEAD)
out48=$("$WT" integrate onda48-a "onda48-a: feat" 2>&1); rc48=$?
chk "A48 integrate com HEAD destacado RECUSA (rc 1)" "$rc48" "1"
chk "A48 a recusa nomeia o desvio e manda switch + merge do SHA + re-executar" \
    "$(has "$out48" "saiu do branch registrado")/$(has "$out48" "switch")/$(has "$out48" "Re-execute este comando")" "sim/sim/sim"
chk "A48 NADA foi tocado na raiz-de-mundo" \
    "$(git -C "$BASE_DIR" rev-parse HEAD)/$(test -e "$BASE_DIR/extra48.txt" && echo sujou || echo limpo)" "$head48/limpo"
sha48=$(printf '%s\n' "$out48" | sed -nE 's/.*&& git -C "[^"]*" merge ([0-9a-f]+).*/\1/p')
br48=$(col onda48-a 4)
git -C "$w48" switch "$br48" >/dev/null 2>&1 && git -C "$w48" merge -q -m "de volta ao registrado" "$sha48" >/dev/null 2>&1
"$WT" integrate onda48-a "onda48-a: feat" >/dev/null 2>&1; chk "A48 switch + merge do SHA impresso => integrate OK" "$?" "0"
chk "A48 o trabalho destacado entrou no squash" "$(test -f "$BASE_DIR/extra48.txt" && echo sim || echo nao)" "sim"
"$WT" finish onda48-a --gate-ok >/dev/null 2>&1
mk_child feature onda48-b b48 || bad "A48 mk_child b"
w48b="$CHILD_ROOT/onda48-b"
git -C "$w48b" checkout -q --detach
echo feito > "$w48b/feito48.txt"; echo sujo > "$w48b/sujo48b.txt"
git -C "$w48b" add -A && git -C "$w48b" commit -qm "feat 48b"
out48b=$("$WT" close onda48-b --discard "sub-agente saiu do branch" 2>&1); rc48b=$?
chk "A48b close --discard com HEAD destacado → rc 0 e NEVER-MERGED (nunca EMPTY)" \
    "$rc48b/$(col onda48-b 11)" "0/NEVER-MERGED:sub-agente saiu do branch"
chk "A48b o ref <nome>-HEAD existe e contém o trabalho commitado destacado" \
    "$(git -C "$BASE_DIR" ls-tree -r --name-only "refs/do-archive/$RUN_ID/onda48-b-HEAD" 2>/dev/null | grep -c 'feito48.txt')" "1"
chk "A48b o rescue-commit salvou o untracked no MESMO ref" \
    "$(git -C "$BASE_DIR" ls-tree -r --name-only "refs/do-archive/$RUN_ID/onda48-b-HEAD" 2>/dev/null | grep -c 'sujo48b.txt')" "1"
chk "A48b o AVISO aponta o ref do HEAD da filha" "$(has "$out48b" "arquivado TAMBÉM em refs/do-archive/$RUN_ID/onda48-b-HEAD")" "sim"
mk_child feature onda48-c c48 || bad "A48 mk_child c"
w48c="$CHILD_ROOT/onda48-c"
git -C "$w48c" switch -c feature/minha48 >/dev/null 2>&1
echo mais > "$w48c/mais48.txt"
git -C "$w48c" add -A && git -C "$w48c" commit -qm "feat 48c"
out48c=$("$WT" close onda48-c --discard "branch proprio" 2>&1); rc48c=$?
chk "A48c close após 'git switch -c' → rc 0 e NEVER-MERGED" "$rc48c/$(col onda48-c 11 | cut -c1-12)" "0/NEVER-MERGED"
chk "A48c o branch FORA do namespace é LISTADO no aviso" "$(has "$out48c" "feature/minha48")" "sim"
chk "A48c o branch fora do namespace NÃO foi apagado (R8d)" \
    "$(git -C "$BASE_DIR" branch --list feature/minha48 | wc -l | tr -d ' ')" "1"
chk "A48c o HEAD da filha está no ref <nome>-HEAD" \
    "$(git -C "$BASE_DIR" rev-parse "refs/do-archive/$RUN_ID/onda48-c-HEAD" 2>/dev/null)" "$(git -C "$BASE_DIR" rev-parse feature/minha48)"
git -C "$BASE_DIR" branch -D feature/minha48 >/dev/null 2>&1
mk_child feature onda48-d d48 || bad "A48 mk_child d"
w48d="$CHILD_ROOT/onda48-d"
git -C "$w48d" checkout -q --detach
echo so > "$w48d/somente48.txt"
git -C "$w48d" add -A && git -C "$w48d" commit -qm "feat 48d"
out48d=$("$WT" close onda48-d 2>&1); rc48d=$?
chk "A48d close SEM --discard recusa commits só no HEAD destacado (nunca EMPTY)" \
    "$rc48d/$(has "$out48d" "NÃO INTEGRADO")" "1/sim"
"$WT" close onda48-d --discard "fix perdido" >/dev/null 2>&1
chk "A48d com --discard fecha NEVER-MERGED e o ref -HEAD existe" \
    "$(col onda48-d 11)/$(narchive onda48-d-HEAD)" "NEVER-MERGED:fix perdido/1"

echo "=== A49: re-integração preserva o pre do 1º squash; undo desfaz TODOS (árvore = pre do 1º); wave-files vê a onda inteira ==="
newrun
mk_child feature onda49-a a49 || bad "A49 mk_child"
w49="$CHILD_ROOT/onda49-a"
echo bug > "$w49/bug49.txt"
git -C "$w49" add -A && git -C "$w49" commit -qm "commit com bug"
pre49=$(git -C "$BASE_DIR" rev-parse HEAD)
"$WT" gate-set test 'test ! -f bug49.txt' >/dev/null
"$WT" integrate onda49-a "onda49-a: feat" >/dev/null 2>&1; chk "A49 integrate #1" "$?" "0"
post1_49=$(col onda49-a 8); sq49="$DO_STATE/squashes/onda49-a"
"$WT" gate onda49-a >/dev/null 2>&1; chk "A49 gate #1 vermelho (rc 4)" "$?" "4"
echo fix > "$w49/fix49.txt"
git -C "$w49" add -A && git -C "$w49" commit -qm "fix 1"
"$WT" integrate onda49-a "onda49-a: fix" >/dev/null 2>&1; chk "A49 re-integrar após o fix OK" "$?" "0"
chk "A49 col 7 continua o pre do PRIMEIRO squash" "$(col onda49-a 7)" "$pre49"
chk "A49 col 8 é o ÚLTIMO post" "$(col onda49-a 8)" "$(git -C "$BASE_DIR" rev-parse HEAD)"
chk "A49 lista de squashes guarda as 2 integrações (mais antiga primeiro)" \
    "$(awk 'END{print NR}' "$sq49")/$(sed -n 1p "$sq49")" "2/$post1_49"
out49w=$("$WT" wave-files onda49-a 2>&1)
chk "A49 wave-files vê a onda INTEIRA (1º squash + fix)" \
    "$(has "$out49w" "a49.txt")/$(has "$out49w" "bug49.txt")/$(has "$out49w" "fix49.txt")" "sim/sim/sim"
"$WT" gate onda49-a >/dev/null 2>&1; chk "A49 gate #2 vermelho de novo (teto de fixes)" "$?" "4"
"$WT" undo onda49-a >/dev/null 2>&1; chk "A49 undo com 2 squashes vivos" "$?" "0"
chk "A49 árvore de BASE_BRANCH restaurada à do PRE do 1º squash" \
    "$(git -C "$BASE_DIR" rev-parse 'HEAD^{tree}')" "$(git -C "$BASE_DIR" rev-parse "$pre49^{tree}")"
chk "A49 nada do squash sobrou no working tree" \
    "$(test -e "$BASE_DIR/bug49.txt" && echo ficou || echo apagado)/$(test -e "$BASE_DIR/fix49.txt" && echo ficou || echo apagado)" "apagado/apagado"
chk "A49 a lista de squashes é TRUNCADA pelo undo" "$(test -e "$sq49" && echo ficou || echo apagado)" "apagado"
chk "A49 os 2 squashes arquivados (undo-<nome>-1 e -2)" \
    "$(git -C "$BASE_DIR" for-each-ref --format='%(refname)' "refs/do-archive/$RUN_ID" | grep -c 'undo-onda49-a')" "2"
chk "A49 status REVERTED" "$(col onda49-a 9)" "REVERTED"
"$WT" close onda49-a --discard "gate vermelho persistente: test" >/dev/null 2>&1
chk "A49 close --discard pós-undo → NEVER-MERGED" \
    "$(col onda49-a 11)" "NEVER-MERGED:gate vermelho persistente: test"

echo "=== A50: undo com OUTRA filha integrada no meio → 2 reverts; o squash da outra filha fica ==="
newrun
mk_child feature onda50-a a50 || bad "A50 mk_child a"
w50="$CHILD_ROOT/onda50-a"
"$WT" integrate onda50-a "onda50-a: 1" >/dev/null 2>&1
mk_child feature onda50-b b50 || bad "A50 mk_child b"
"$WT" integrate onda50-b "onda50-b: 1" >/dev/null 2>&1
echo fix > "$w50/fix50a.txt"
git -C "$w50" add -A && git -C "$w50" commit -qm "fix a"
"$WT" integrate onda50-a "onda50-a: 2" >/dev/null 2>&1
"$WT" undo onda50-a >/dev/null 2>&1; chk "A50 undo com squash alheio no intervalo → revert" "$?" "0"
chk "A50 os 2 squashes de a saíram (2 Revert)" \
    "$(git -C "$BASE_DIR" log --format=%s | grep -c '^Revert "onda50-a:')" "2"
chk "A50 o arquivo da OUTRA filha FICA" "$(test -f "$BASE_DIR/b50.txt" && echo sim || echo nao)" "sim"
chk "A50 os arquivos de a saíram" \
    "$(test -e "$BASE_DIR/fix50a.txt" || echo apagado)/$(test -e "$BASE_DIR/a50.txt" || echo apagado)" "apagado/apagado"
chk "A50 status REVERTED para a / gate-pending para b" "$(col onda50-a 9)/$(col onda50-b 9)" "REVERTED/gate-pending"
"$WT" finish onda50-b >/dev/null 2>&1
"$WT" close onda50-a --discard "fixture A50" >/dev/null 2>&1

echo "=== A51: gate vermelho + cauda não integrada => MERGED-PARTIAL (finish e purge); ledger parciais=; purge rc 3 ==="
newrun
mk_child feature onda51-a a51 || bad "A51 mk_child a"
w51="$CHILD_ROOT/onda51-a"
echo RUIM > "$w51/a51.txt"
git -C "$w51" add -A && git -C "$w51" commit -qm "feat com bug"
"$WT" gate-set test 'grep -q CORRIGIDO a51.txt' >/dev/null
"$WT" integrate onda51-a "onda51-a: feat" >/dev/null 2>&1
"$WT" gate onda51-a >/dev/null 2>&1; chk "A51 gate #1 vermelho" "$?" "4"
echo CORRIGIDO > "$w51/a51.txt"; echo tail > "$w51/tail51.txt"    # fix SEM merge do BASE + untracked
git -C "$w51" add -A && git -C "$w51" commit -qm "fix: corrige"
out51=$("$WT" integrate onda51-a "onda51-a: fix" 2>&1); rc51=$?
chk "A51 re-integrar sem o merge do BASE RECUSA (CONFLITO, raiz intacta)" "$rc51/$(has "$out51" "CONFLITO")" "1/sim"
out51p=$("$WT" purge 2>&1); rc51p=$?
chk "A51 purge com gate vermelho + cauda sai rc 3" "$rc51p" "3"
chk "A51 o bloco obrigatório tem o título novo (NUNCA INTEGRADAS / PARCIAIS)" \
    "$(has "$out51p" "PURGE: NUNCA INTEGRADAS / PARCIAIS (obrigatorio no relatorio final):")" "sim"
chk "A51 a filha parcial está no bloco com o outcome MERGED-PARTIAL" \
    "$(has "$out51p" "onda51-a")/$(has "$out51p" "MERGED-PARTIAL")" "sim/sim"
chk "A51 o AVISO do fechamento declara MERGED-PARTIAL com o motivo" \
    "$(has "$out51p" "fecha como MERGED-PARTIAL")/$(has "$out51p" "cauda nao integrada")/$(has "$out51p" "gate vermelho (rc=1)")" "sim/sim/sim"
led51=$("$WT" ledger 2>&1)
chk "A51 o RESUMO do ledger conta parciais=1" "$(printf '%s\n' "$led51" | grep -o 'parciais=[0-9]*')" "parciais=1"
chk "A51 outcome da filha começa com MERGED-PARTIAL" "$(col onda51-a 11 | cut -c1-14)" "MERGED-PARTIAL"
chk "A51 o fix não integrado SÓ existe no arquivo" \
    "$(grep -c CORRIGIDO "$BASE_DIR/a51.txt" || true)/$(git -C "$BASE_DIR" ls-tree -r --name-only "refs/do-archive/$RUN_ID/onda51-a" | grep -c 'tail51.txt')" "0/1"
mk_child feature onda51-b b51 || bad "A51 mk_child b"
w51b="$CHILD_ROOT/onda51-b"
echo RUIM > "$w51b/b51.txt"
git -C "$w51b" add -A && git -C "$w51b" commit -qm "feat b com bug"
"$WT" gate-set test 'grep -q CORRIGIDO b51.txt' >/dev/null
"$WT" integrate onda51-b "onda51-b: feat" >/dev/null 2>&1
"$WT" gate onda51-b >/dev/null 2>&1
echo CORRIGIDO > "$w51b/b51.txt"
git -C "$w51b" add -A && git -C "$w51b" commit -qm "fix b"
out51f=$("$WT" finish onda51-b --gate-ok 2>&1); rc51f=$?
chk "A51 finish --gate-ok com vermelho + cauda → rc 0 (mas MERGED-PARTIAL)" "$rc51f" "0"
chk "A51 outcome MERGED-PARTIAL + aviso visível" \
    "$(has "$out51f" "fecha como MERGED-PARTIAL")/$(col onda51-b 11 | cut -c1-14)" "sim/MERGED-PARTIAL"
chk "A51 o RESUMO do ledger agora conta parciais=2" "$("$WT" ledger 2>&1 | grep -o 'parciais=[0-9]*')" "parciais=2"
chk "A51 purge idempotente continua rc 3 (bloco obrigatório)" "$("$WT" purge >/dev/null 2>&1; echo $?)" "3"

echo "=== A52: snapshot de test-onda(N-1) NÃO trava o 'new fix ondaN-*' (rc != 6); hint manda resolver o PARENT ==="
newrun
mk_child feature onda1-x x52 || bad "A52 mk_child"
"$WT" integrate onda1-x "onda1-x: x52" >/dev/null 2>&1
"$WT" finish onda1-x --gate-ok >/dev/null 2>&1          # onda 1 fechada
mk_child test test-onda1-t t52 || bad "A52 mk_child test"
"$WT" integrate test-onda1-t "test-onda1-t: t52" >/dev/null 2>&1
chk "A52 fixture: filha de teste gate-pending com snapshot vivo" \
    "$(col test-onda1-t 9)/$(col int-test-onda1-t 2)" "gate-pending/integration"
"$WT" new fix onda2-fix-bug >/dev/null 2>&1; rc52n=$?
chk "A52 'new fix onda2-*' NÃO trava com o snapshot de teste vivo (rc != 6)" \
    "$(test "$rc52n" != 6 && echo sim || echo nao)/$rc52n" "sim/0"
"$WT" assert-clean --wave 2 >/dev/null 2>&1
chk "A52 assert-clean --wave 2 aceita a subwave da onda N-1" "$?" "0"
out52=$("$WT" assert-clean --wave 3 2>&1); rc52w=$?
chk "A52 --wave 3 barra o snapshot da onda 1 (regra da onda N-2)" \
    "$rc52w/$(has "$out52" "int-test-onda1-t")" "1/sim"
chk "A52 o conserto é o do PARENT (gate do teste), nunca 'close <snapshot>' com o gate em voo" \
    "$(has "$out52" "resolva o PARENT")/$(has "$out52" "gate test-onda1-t")/$(has "$out52" "close int-test-onda1-t")" "sim/sim/nao"
"$WT" finish test-onda1-t --gate-ok >/dev/null 2>&1      # fecha filha + snapshot
chk "A52 parent fechado => snapshot fechou junto (--wave 3 sem a sobra do snapshot)" \
    "$(has "$("$WT" assert-clean --wave 3 2>&1)" "int-test-onda1-t")" "nao"
"$WT" close onda2-fix-bug --discard "fixture A52" >/dev/null 2>&1

echo "=== A53: 2º 'gate' concorrente no mesmo nome → rc 3 AGUARDE, sem tocar log/rc ==="
newrun
mk_child feature onda53-a a53 || bad "A53 mk_child"
"$WT" gate-set test 'sleep 2; test -f a53.txt' >/dev/null
"$WT" integrate onda53-a "onda53-a: a53" >/dev/null 2>&1
"$WT" gate onda53-a >"$LAB/a53-g1.log" 2>&1 & g53=$!
sleep 0.5
chk "A53 o 1º gate está rodando (.rc = 'running <pid> <post_sha>')" \
    "$(awk '{print $1}' "$DO_STATE/gates/onda53-a.rc")/$(awk 'NF==3 && $2 ~ /^[0-9]+$/ {print "sim"}' "$DO_STATE/gates/onda53-a.rc")" "running/sim"
sum53=$(cksum "$DO_STATE/gates/onda53-a.log" "$DO_STATE/gates/onda53-a.rc" 2>/dev/null | awk '{print $1}' | tr '\n' '-')
out53g2=$("$WT" gate onda53-a 2>&1); rc53g2=$?
chk "A53 o 2º gate recusa com rc 3 e AGUARDE" "$rc53g2/$(has "$out53g2" "AGUARDE")" "3/sim"
chk "A53 o 2º gate NÃO tocou log nem .rc" \
    "$(cksum "$DO_STATE/gates/onda53-a.log" "$DO_STATE/gates/onda53-a.rc" 2>/dev/null | awk '{print $1}' | tr '\n' '-')" "$sum53"
out53s=$("$WT" sweep 2>&1); rc53s=$?
chk "A53 o hint do sweep lê o .rc rodando (aguarde, não rode outro)" \
    "$(test "$rc53s" != 0 && echo sim || echo nao)/$(has "$out53s" "rodando em background")" "sim/sim"
wait "$g53"; rc53g1=$?
chk "A53 o 1º gate terminou VERDE e fechou a filha sozinho" \
    "$rc53g1/$(col onda53-a 9)/$(col onda53-a 11)" "0/REMOVED/MERGED"
chk "A53 .rc final amarrado ao squash (0 <post_sha>)" \
    "$(awk '{print $1}' "$DO_STATE/gates/onda53-a.rc")/$(awk '{print $2}' "$DO_STATE/gates/onda53-a.rc")" "0/$(col onda53-a 8)"

echo "=== A54: gate de kind=test com DO_TEST_MODE=e2e roda a etapa e2e SOZINHO (o --e2e segue aceito) ==="
newrun
mk_child test test-onda54-e2e-login e54 || bad "A54 mk_child"
echo spec > "$CHILD_ROOT/test-onda54-e2e-login/spec54.txt"
git -C "$CHILD_ROOT/test-onda54-e2e-login" add -A && git -C "$CHILD_ROOT/test-onda54-e2e-login" commit -qm "spec"
mk_child test test-onda54-manual m54 || bad "A54 mk_child manual"
"$WT" gate-set test 'true' >/dev/null
"$WT" gate-set e2e "echo x >> $LAB/a54-e2e-rodou" >/dev/null   # $LAB expande AGORA: o .cmd é cru no gate
"$WT" integrate test-onda54-e2e-login "test-onda54-e2e-login: e54" >/dev/null 2>&1
DO_TEST_MODE=e2e "$WT" gate test-onda54-e2e-login >/dev/null 2>&1; rc54=$?
chk "A54 gate SEM --e2e fica verde e fecha sozinho" "$rc54/$(col test-onda54-e2e-login 9)" "0/REMOVED"
chk "A54 a etapa e2e RODOU sem a flag (marcador + log)" \
    "$(wc -l < "$LAB/a54-e2e-rodou" | tr -d ' ')/$(grep -c '=== \[e2e\] rc=' "$DO_STATE/gates/test-onda54-e2e-login.log")" "1/1"
mk_child feature onda54-f f54 || bad "A54 mk_child f"
"$WT" integrate onda54-f "onda54-f: f54" >/dev/null 2>&1
DO_TEST_MODE=e2e "$WT" gate onda54-f >/dev/null 2>&1; rc54f=$?
chk "A54 kind=feature NÃO roda o e2e (verde sem a etapa)" "$rc54f" "0"
chk "A54 o contador do e2e não mudou para feature" "$(wc -l < "$LAB/a54-e2e-rodou" | tr -d ' ')" "1"
chk "A54 o log da feature não tem etapa e2e" "$(grep -c '=== \[e2e\] rc=' "$DO_STATE/gates/onda54-f.log")" "0"
"$WT" integrate test-onda54-manual "test-onda54-manual: m54" >/dev/null 2>&1
"$WT" gate test-onda54-manual --e2e >/dev/null 2>&1; rc54m=$?
chk "A54 o --e2e segue aceito (etapa roda e fecha)" "$rc54m/$(col test-onda54-manual 9)" "0/REMOVED"
chk "A54 o contador do e2e subiu com --e2e" "$(wc -l < "$LAB/a54-e2e-rodou" | tr -d ' ')" "2"

echo "=== A55: cartões de passo — checklist (FASE 3) e checklist final (FASE 4) = <step order> do SKILL.md ==="
sk55="$SKILL/SKILL.md"
steps3=$(awk '/<phase id="3"/{p=1} p && /<\/phase>/{p=0} p' "$sk55" \
         | sed -nE 's/.*<step order="([0-9]+(\.[0-9]+)?)".*/\1/p' | LC_ALL=C sort -u | LC_ALL=C sort -n | tr '\n' ' ')
steps4=$(awk '/<phase id="4"/{p=1} p && /<\/phase>/{p=0} p' "$sk55" \
         | sed -nE 's/.*<step order="([0-9]+(\.[0-9]+)?)".*/\1/p' | LC_ALL=C sort -u | LC_ALL=C sort -n | tr '\n' ' ')
card55=$(env -i PATH="$PATH" bash "$WT" checklist 2>&1)
fin55=$(env -i PATH="$PATH" bash "$WT" checklist final 2>&1)
chk "A55 os <step order> da FASE 3 estão congelados" "$steps3" "0 1 2 3 3.5 4 4.5 5 6 7 8 9 10 "
chk "A55 os <step order> da FASE 4 (0-8) estão congelados" "$steps4" "0 1 2 3 4 5 5.5 6 7 7.5 8 "
nums3=$(printf '%s\n' "$card55" | grep -oE '^ {0,2}[0-9]+(\.[0-9]+)?' | tr -d ' ' | tr '\n' ' ')
nums4=$(printf '%s\n' "$fin55" | grep -oE '^ {0,2}[0-9]+(\.[0-9]+)?' | tr -d ' ' | tr '\n' ' ')
chk "A55 o CARTÃO usa EXATAMENTE a numeração dos passos da FASE 3" "$nums3" "$steps3"
chk "A55 o CHECKLIST FINAL usa EXATAMENTE os passos 0-8 da FASE 4" "$nums4" "$steps4"
chk "A55 cartão e checklist final <= 30 linhas" \
    "$(test "$(printf '%s\n' "$card55" | wc -l | tr -d ' ')" -le 30 && echo sim)/$(test "$(printf '%s\n' "$fin55" | wc -l | tr -d ' ')" -le 30 && echo sim)" "sim/sim"
q55=$(env -i PATH="$PATH" DO_QUESTION=1 bash "$WT" checklist 2>&1)
chk "A55 DO_QUESTION=1 acrescenta a linha da rodada de pergunta (+1 linha, sem número de passo)" \
    "$(test "$(printf '%s\n' "$q55" | wc -l | tr -d ' ')" = $(( $(printf '%s\n' "$card55" | wc -l | tr -d ' ') + 1 )) && echo +1)/$(has "$q55" "do-question")" "+1/sim"

echo "=== A56: gate sobre filha MERGED com snapshot LEGADO vivo → vira gate-pending (o vermelho não é mais ignorado) ==="
newrun
mk_child feature onda56-a a56 || bad "A56 mk_child"
post56=$(git -C "$BASE_DIR" rev-parse HEAD)
"$WT" merge onda56-a "onda56-a: a56" >/dev/null 2>&1            # primitivo: MERGED, SEM snapshot
"$WT" new integration int-onda56-a "$post56" >/dev/null 2>&1    # snapshot legado criado À MÃO (vivo)
chk "A56 fixture: filha MERGED com snapshot vivo" "$(col onda56-a 9)/$(col int-onda56-a 2)" "MERGED/integration"
"$WT" gate-set test 'test ! -f a56.txt' >/dev/null
"$WT" gate onda56-a >/dev/null 2>&1; rc56=$?
chk "A56 o gate roda e fica vermelho" "$rc56" "4"
chk "A56 a filha vira gate-pending (antes a transição era pulada no snapshot legado)" "$(col onda56-a 9)" "gate-pending"
out56s=$("$WT" sweep 2>&1); rc56s=$?
chk "A56 o sweep NÃO fecha a filha vermelha (rc != 0, aponta o fix)" \
    "$(test "$rc56s" != 0 && echo sim || echo nao)/$(has "$out56s" "gate VERMELHO")" "sim/sim"
"$WT" finish onda56-a --gate-ok >/dev/null 2>&1                  # cleanup: fecha filha + snapshot

echo; printf 'RESULTADO: %s PASS, %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1
