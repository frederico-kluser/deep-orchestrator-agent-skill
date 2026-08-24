#!/usr/bin/env bash
# Testes de aceitação do motor de AUTO-EVOLUÇÃO — E1..E30 (v3.7.0)
#
# Cada caso roda ISOLADO num repo fake da skill (git init + SKILL.md com
# identidade + scripts/evolve-skill.sh COPIADO), com HOME/tmp próprios, SEM
# rede. O script sob teste resolve a casa da skill pela própria localização
# (pwd -P) — por isso o fixture precisa de uma CÓPIA do script dentro do repo
# fake; o cwd de invocação é irrelevante (E1 prova isso).
#   E1:  resolução — invocado de cwd FORA do repo fake, add/search/diff/
#        apply/consolidate/status funcionam contra ele
#   E2:  guarda de identidade — SKILL.md sem 'name: ...' → exit 3
#   E3:  instalação por CÓPIA sem .git → exit 2 com a mensagem sync-global-skill.sh
#   E4:  add valida — candidato sem source → exit 2 e NADA escrito (lote atômico)
#   E5:  secret_scan — api_key=abc123 → exit 2 e o valor NUNCA impresso;
#        "O token de acesso expira" → PASSA (exit 0)
#   E6:  dedupe no add — mesma entrada 2× → 1 entrada, 2ª reportada duplicada
#   E7:  ids — primeiro add real = LEARN-<hoje>-001, segundo = -002 (template
#        em fence + placeholder no arquivo não deslocam)
#   E8:  parser/fence — LEARNINGS.md real (template ```markdown) → status conta
#        0 entradas; add anexa ao final; consolidate --dry-run NÃO toca o arquivo
#   E9:  consolidate contradição — par (mesmo type+tags+título similar, datas
#        distintas) → a nova vence; a antiga vira superseded + supersedes +
#        ~~…~~ (obsoleto …); NADA é apagado
#   E10: dedupe do consolidate — par idêntico → só a nova no LEARNINGS.md;
#        a antiga no archive 1×; 2º run arquiva 0
#   E11: anti-poisoning — entradas source=web NUNCA viram proposta de promoção
#   E12: promoção proposta — 2 entradas source=user (datas distintas) → imprime
#        PROPOSTA sem escrever no SKILL.md
#   E13: orçamento — LEARNINGS.md perto do teto → add avisa ORÇAMENTO;
#        consolidate move as mais antigas ao learnings_archive.md
#   E14: apply default inteligente — só LEARNINGS.md mudou → commit DIRETO no
#        branch atual (evolve(learnings): …); SKILL.md também mudou → branch
#        evolve/YYYY-MM-DD e commit lá
#   E15: allowlist/staged — segredo.txt criado E staged → apply --direct exit 4,
#        NÃO commitado, staged INTACTO; staged só na allowlist → commit normal
#   E16: flock — lock segurado em outro processo → apply sai != 0 COM mensagem
#        no stderr (não mudo)
#   E17: search — termo presente → exit 0 com id|data|type|confidence|source|
#        título; ausente → exit 1
#   E18: add paralelo — 5 pares de add concorrentes → 10 entradas, 10 ids únicos
#   E19: --dry-run — add e consolidate NÃO escrevem nada (git status limpo)
#   E20: apply idempotente — sem mudanças → exit 0, sem commit novo
#   E21: add aceita o formato do TEMPLATE (corpo '- **Observação:**'/
#        '- **Ação:**' + título '## ') e o anexa; frontmatter VENCE se ambas
#        presentes (F-A1)
#   E22: mudança no SKILL.md REAL (.claude/skills/.../SKILL.md) → apply sem
#        flags cria branch evolve/YYYY-MM-DD (NUNCA commit direto) e commita lá
#        (F-A2)
#   E23: superseded NÃO aparece no Índice após consolidate, mas permanece no
#        corpo marcada (F-3)
#   E24: add com entrada vazia → exit 0, 'nada a adicionar', nada escrito (F-4)
#   E25: contrato — 'contract: comando-inexistente-xyz' → consolidate marca
#        superseded 'contrato quebrado'; 'contract: bash' passa (F-5)
#   E26: supersessão por CONFIANÇA — web (nova) NUNCA supersede user (antiga):
#        a user vence, a web é marcada superseded; a web NÃO é proposta na
#        mesma execução (estado pós-supersessão) (F-10)
#   E27: índice > 30 linhas → add avisa 'ÍNDICE: rode consolidate' (F-6)
#   E28: dois candidatos body-only (títulos diferentes) separados por '---' →
#        add anexa 2 entradas, NENHUMA descartada (o 2º bloco não é mesclado
#        silenciosamente no 1º) (F-11a)
#   E29: promoção ≥2 restaurada — entrada ativa repo-doc + duplicata arquivada
#        (mesmo título+type, data diferente) → consolidate --dry-run propõe com
#        '2 ocorrência(s) em datas distintas'; idêntica situação com fonte
#        UNTRUSTED (web) → NENHUMA proposta (F-11b)
#   E30: múltiplas linhas '- **Observação:**' no mesmo bloco são JUNTADAS
#        (preservadas) na entrada anexada (F-11b)
set -uo pipefail
SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
EVOLVE_SRC="$SKILL/scripts/evolve-skill.sh"
LAB="${TMPDIR:-/tmp}/evolve-accept-$$"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (esperado='$3' obtido='$2')"; fi; }

rm -rf "$LAB"; mkdir -p "$LAB"; cd "$LAB"
trap 'rm -rf -- "$LAB"' EXIT   # nunca deixar labs /tmp/evolve-accept-* órfãos
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

TODAY=$(date +%Y%m%d)
TODAY_C=$(date +%F)
REALID='^id: LEARN-[0-9]{8}-[0-9]{3}$'

# --- fixture: repo fake da skill (evolve-skill.sh COPIADO; cwd fica fora) -----
newcase() { # <nome> — dir próprio do caso com repo fake isolado
  CASE="$LAB/$1"
  rm -rf "$CASE"
  mkdir -p "$CASE/repo/scripts"
  git init -q -b main "$CASE/repo"
  git -C "$CASE/repo" config user.name t
  git -C "$CASE/repo" config user.email t@t
  cp "$EVOLVE_SRC" "$CASE/repo/scripts/evolve-skill.sh"
  chmod +x "$CASE/repo/scripts/evolve-skill.sh"
  EVOLVE="$CASE/repo/scripts/evolve-skill.sh"
  cd "$CASE" || exit 1
}

write_skill() { # SKILL.md com identidade correta (grep -qx exige a linha exata)
  cat > "$CASE/repo/SKILL.md" <<'EOF'
---
name: deep-orchestrator-agent-skill
description: fixture de teste do motor de auto-evolucao
metadata:
  version: "3.7.0"
---
EOF
}

seed_learnings() { # LEARNINGS.md REAL (header + template em code fence) como fixture
  cp "$SKILL/LEARNINGS.md" "$CASE/repo/LEARNINGS.md"
}

commit_all() { # <msg> — commita tudo do repo fake
  git -C "$CASE/repo" add -A
  git -C "$CASE/repo" commit -qm "$1"
}

candidate() { # <arquivo> <título> <type> <confidence> <source> <tags> <obs> <acao>
  local f="$1"; shift
  {
    printf -- '---\n'
    printf 'title: %s\n' "$1"
    printf 'type: %s\n' "$2"
    printf 'confidence: %s\n' "$3"
    printf 'source: %s\n' "$4"
    printf 'tags: %s\n' "$5"
    printf 'observacao: %s\n' "$6"
    printf 'acao: %s\n' "$7"
    printf -- '---\n'
  } > "$f"
}

candidate_append() { # <arquivo> ... — bloco ADICIONAL (sem '---' inicial; blocos
  # precisam ficar ADJACENTES: linha em branco entre blocos criaria um candidato
  # vazio e o lote seria rejeitado)
  local f="$1"; shift
  {
    printf 'title: %s\n' "$1"
    printf 'type: %s\n' "$2"
    printf 'confidence: %s\n' "$3"
    printf 'source: %s\n' "$4"
    printf 'tags: %s\n' "$5"
    printf 'observacao: %s\n' "$6"
    printf 'acao: %s\n' "$7"
    printf -- '---\n'
  } >> "$f"
}

entry() { # <id> <date> <type> <conf> <source> <tags> <title> <obs> <acao>
  printf -- '---\nid: %s\ndate: "%s"\ntype: %s\nconfidence: %s\nsource: %s\nstatus: active\nsupersedes: ""\ntags: %s\n---\n## %s\n- **Observação:** %s\n- **Ação:** %s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
}

learnings_head() { # <título1> <type1> <id1> [<título2> <type2> <id2> ...] — cabeçalho + Índice
  printf '# LEARNINGS — deep-orchestrator-agent-skill\n\n> Memória episódica (fixture de teste).\n\n## Índice\n\n'
}

echo "=== E1: resolução — cwd FORA do repo fake; CLI completa funciona ==="
newcase e1
write_skill; seed_learnings; commit_all init
candidate "$CASE/c1.txt" "Cache invalidation gotcha" gotcha high user "[cache, build]" "invalidar o cache de build" "rodar clean antes"
"$EVOLVE" add "$CASE/c1.txt" >/dev/null 2>&1; chk "E1 add exit 0" "$?" "0"
chk "E1 primeiro id = LEARN-<hoje>-001" "$(grep -E "$REALID" "$CASE/repo/LEARNINGS.md" | head -1 | sed 's/^id: //')" "LEARN-$TODAY-001"
"$EVOLVE" search cache >/dev/null 2>&1;   chk "E1 search exit 0" "$?" "0"
"$EVOLVE" diff >/dev/null 2>&1;           chk "E1 diff exit 0" "$?" "0"
"$EVOLVE" apply >/dev/null 2>&1;          chk "E1 apply exit 0" "$?" "0"
chk "E1 branch atual preservado (main)" "$(git -C "$CASE/repo" rev-parse --abbrev-ref HEAD)" "main"
"$EVOLVE" consolidate --dry-run >/dev/null 2>&1; chk "E1 consolidate exit 0" "$?" "0"
"$EVOLVE" status >/dev/null 2>&1;         chk "E1 status exit 0" "$?" "0"

echo "=== E2: guarda de identidade — SKILL.md sem o name esperado → exit 3 ==="
newcase e2
printf -- '---\nname: outra-skill\ndescription: fixture\nmetadata:\n  version: "3.7.0"\n---\n' > "$CASE/repo/SKILL.md"
"$EVOLVE" status >/dev/null 2>&1; chk "E2 exit 3" "$?" "3"
out=$("$EVOLVE" status 2>&1)
case "$out" in *"não é a casa desta skill"*) ok "E2 mensagem clara de identidade" ;;
  *) bad "E2 sem mensagem de identidade: $out" ;; esac

echo "=== E3: instalação por CÓPIA sem .git → exit 2 + sync-global-skill.sh ==="
newcase e3
rm -rf "$CASE"
mkdir -p "$CASE/nogit/scripts"
cp "$EVOLVE_SRC" "$CASE/nogit/scripts/evolve-skill.sh"
chmod +x "$CASE/nogit/scripts/evolve-skill.sh"
printf -- '---\nname: deep-orchestrator-agent-skill\ndescription: fixture\nmetadata:\n  version: "3.7.0"\n---\n' > "$CASE/nogit/SKILL.md"
out=$("$CASE/nogit/scripts/evolve-skill.sh" status 2>&1); rc=$?
chk "E3 exit 2" "$rc" "2"
case "$out" in *sync-global-skill.sh*) ok "E3 mensagem manda rodar sync-global-skill.sh" ;;
  *) bad "E3 sem a instrução de conversão: $out" ;; esac

echo "=== E4: add valida — candidato sem source → exit 2 e NADA escrito ==="
newcase e4
write_skill; seed_learnings; commit_all init
printf -- '---\ntitle: Sem source\ntype: fact\nconfidence: high\ntags: [a]\nobservacao: obs\nacao: acao\n---\n' > "$CASE/bad.txt"
out=$("$EVOLVE" add "$CASE/bad.txt" 2>&1); rc=$?
chk "E4 exit 2" "$rc" "2"
chk "E4 lote rejeitado (mensagem)" "$(echo "$out" | grep -c 'lote REJEITADO' || true)" "1"
chk "E4 nada escrito (porcelain)" "$(git -C "$CASE/repo" status --porcelain | wc -l)" "0"
chk "E4 nenhum id novo" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "0"

echo "=== E5: secret_scan — api_key=abc123 rejeitado (valor nunca impresso); token textual passa ==="
newcase e5
write_skill; seed_learnings; commit_all init
printf -- '---\ntitle: Vazou segredo\ntype: fact\nconfidence: high\nsource: user\ntags: [s]\nobservacao: a api_key=abc123 foi usada\nacao: nao repetir\n---\n' > "$CASE/secret.txt"
out=$("$EVOLVE" add "$CASE/secret.txt" 2>&1); rc=$?
chk "E5 api_key=... → exit 2" "$rc" "2"
chk "E5 segredo detectado (mensagem)" "$(echo "$out" | grep -c 'segredo' || true)" "1"
chk "E5 valor NUNCA impresso (stdout+stderr)" "$(echo "$out" | grep -c 'abc123' || true)" "0"
chk "E5 nada escrito" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "0"
candidate "$CASE/ok.txt" "Token expira" fact high user "[t]" "O token de acesso expira em 30 dias" "renovar antes"
out2=$("$EVOLVE" add "$CASE/ok.txt" 2>&1); rc2=$?
chk "E5 'O token de acesso expira' passa (exit 0)" "$rc2" "0"
chk "E5 entrada escrita" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "1"

echo "=== E6: dedupe no add — mesma entrada 2× → 1 entrada, 2ª duplicada ==="
newcase e6
write_skill; seed_learnings; commit_all init
candidate "$CASE/dup.txt" "Mesma entrada" fact high user "[a]" "obs" "acao"
candidate_append "$CASE/dup.txt" "Mesma entrada" fact high user "[a]" "obs" "acao"
out=$("$EVOLVE" add "$CASE/dup.txt" 2>&1); rc=$?
chk "E6 exit 0" "$rc" "0"
chk "E6 2ª reportada duplicada" "$(echo "$out" | grep -c 'duplicada, ignorada' || true)" "1"
chk "E6 só 1 entrada real" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "1"

echo "=== E7: ids sequenciais — 001, 002 (template em fence NÃO desloca) ==="
newcase e7
write_skill; seed_learnings; commit_all init
candidate "$CASE/a.txt" "Primeira entrada" fact high user "[a]" "obs1" "acao1"
candidate "$CASE/b.txt" "Segunda entrada" fact medium repo-doc "[b]" "obs2" "acao2"
"$EVOLVE" add "$CASE/a.txt" >/dev/null 2>&1
"$EVOLVE" add "$CASE/b.txt" >/dev/null 2>&1
ids=$(grep -E "$REALID" "$CASE/repo/LEARNINGS.md" | sed 's/^id: //' | tr '\n' ' ')
chk "E7 primeiro id = -001" "$(echo "$ids" | awk '{print $1}')" "LEARN-$TODAY-001"
chk "E7 segundo id = -002" "$(echo "$ids" | awk '{print $2}')" "LEARN-$TODAY-002"
chk "E7 template com placeholder preservado" "$(grep -c 'id: LEARN-YYYYMMDD-NNN' "$CASE/repo/LEARNINGS.md")" "1"

echo "=== E8: parser ignora code fence — status conta 0; add anexa ao final; dry-run não toca ==="
newcase e8
write_skill; seed_learnings; commit_all init
out=$("$EVOLVE" status 2>&1)
chk "E8 status conta 0 entradas (template ignorado)" "$(echo "$out" | grep -cE 'entradas +: 0 \(ativas 0' || true)" "1"
candidate "$CASE/a.txt" "Entrada real" gotcha high user "[g]" "obs" "acao"
"$EVOLVE" add "$CASE/a.txt" >/dev/null 2>&1
chk "E8 add anexou ao FINAL do arquivo" "$(tail -6 "$CASE/repo/LEARNINGS.md" | grep -cE '^## Entrada real$' || true)" "1"
cp "$CASE/repo/LEARNINGS.md" "$CASE/antes.md"
"$EVOLVE" consolidate --dry-run >/dev/null 2>&1
chk "E8 consolidate --dry-run NÃO toca o arquivo" "$(cmp -s "$CASE/antes.md" "$CASE/repo/LEARNINGS.md" && echo sim || echo nao)" "sim"
chk "E8 template em fence intacto" "$(grep -c '^```markdown$' "$CASE/repo/LEARNINGS.md")" "1"

echo "=== E9: consolidate — contradição (type+tags+título similar, datas distintas) ==="
newcase e9
write_skill
{
  learnings_head
  printf -- '- 2026-08-01 | gotcha | Sempre use o flag cache ao rodar builds [id: LEARN-20260801-001]\n'
  printf -- '- 2026-08-22 | gotcha | Sempre use cache ao rodar builds [id: LEARN-20260822-001]\n\n'
  entry LEARN-20260801-001 2026-08-01 gotcha high user "[build, cache]" "Sempre use o flag cache ao rodar builds" "versao antiga" "usar cache"
  printf '\n'
  entry LEARN-20260822-001 2026-08-22 gotcha high user "[build, cache]" "Sempre use cache ao rodar builds" "versao nova" "usar cache"
} > "$CASE/repo/LEARNINGS.md"
commit_all init
out=$("$EVOLVE" consolidate --apply 2>&1); rc=$?
chk "E9 consolidate --apply exit 0" "$rc" "0"
chk "E9 superseded reportado" "$(echo "$out" | grep -c 'superseded: LEARN-20260801-001 (2026-08-01)' || true)" "1"
chk "E9 antiga vira status: superseded" "$(grep -c '^status: superseded$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E9 antiga ganha supersedes" "$(grep -c '^supersedes: "LEARN-20260822-001"$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E9 corpo marcado ~~…~~ (obsoleto …)" "$(grep -c '^## ~~Sempre use o flag cache ao rodar builds~~' "$CASE/repo/LEARNINGS.md")" "1"
chk "E9 NADA apagado (2 ids presentes)" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md")" "2"

echo "=== E10: consolidate — dedupe de par idêntico; archive 1×; 2º run arquiva 0 ==="
newcase e10
write_skill
{
  learnings_head
  printf -- '- 2026-08-01 | gotcha | Mesmo titulo [id: LEARN-20260801-001]\n'
  printf -- '- 2026-08-22 | gotcha | Mesmo titulo [id: LEARN-20260822-001]\n\n'
  entry LEARN-20260801-001 2026-08-01 gotcha high user "[build]" "Mesmo titulo" "obs A" "acao A"
  printf '\n'
  entry LEARN-20260822-001 2026-08-22 gotcha high user "[build]" "Mesmo titulo" "obs B" "acao B"
} > "$CASE/repo/LEARNINGS.md"
commit_all init
"$EVOLVE" consolidate --apply >/dev/null 2>&1; rc=$?
chk "E10 1ª consolidação exit 0" "$rc" "0"
chk "E10 LEARNINGS só com a nova" "$(grep -cE '^id: LEARN-20260822-001$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E10 antiga no archive 1×" "$(grep -cE '^id: LEARN-20260801-001$' "$CASE/repo/learnings_archive.md")" "1"
out2=$("$EVOLVE" consolidate --apply 2>&1)
chk "E10 2º run arquiva 0 duplicatas" "$(echo "$out2" | grep -c '0 duplicata(s) arquivada(s)' || true)" "1"
chk "E10 archive não cresceu na 2ª" "$(grep -cE '^id: LEARN-20260801-001$' "$CASE/repo/learnings_archive.md")" "1"

echo "=== E11: anti-poisoning — source=web NUNCA vira proposta de promoção ==="
newcase e11
write_skill
{
  learnings_head
  printf -- '- 2026-08-01 | fact | Achado da web [id: LEARN-20260801-001]\n'
  printf -- '- 2026-08-22 | fact | Achado da web [id: LEARN-20260822-001]\n\n'
  entry LEARN-20260801-001 2026-08-01 fact high web "[web]" "Achado da web" "obs A" "acao A"
  printf '\n'
  entry LEARN-20260822-001 2026-08-22 fact high web "[web]" "Achado da web" "obs B" "acao B"
} > "$CASE/repo/LEARNINGS.md"
commit_all init
out=$("$EVOLVE" consolidate --dry-run 2>&1); rc=$?
chk "E11 consolidate exit 0" "$rc" "0"
chk "E11 nenhuma PROPOSTA de promoção" "$(echo "$out" | grep -c 'PROPOSTAS DE PROMOÇÃO' || true)" "0"
chk "E11 relatório 'propostas: nenhuma'" "$(echo "$out" | grep -c 'propostas de promoção: nenhuma' || true)" "1"

echo "=== E12: promoção PROPOSTA (source=user, datas distintas) sem escrever no SKILL.md ==="
newcase e12
write_skill
{
  learnings_head
  printf -- '- 2026-08-01 | gotcha | Usuario confirmou o fluxo X [id: LEARN-20260801-001]\n'
  printf -- '- 2026-08-22 | gotcha | Usuario confirmou o fluxo X [id: LEARN-20260822-001]\n\n'
  entry LEARN-20260801-001 2026-08-01 gotcha high user "[fluxo]" "Usuario confirmou o fluxo X" "obs A" "acao A"
  printf '\n'
  entry LEARN-20260822-001 2026-08-22 gotcha high user "[fluxo]" "Usuario confirmou o fluxo X" "obs B" "acao B"
} > "$CASE/repo/LEARNINGS.md"
commit_all init
cp "$CASE/repo/SKILL.md" "$CASE/SKILL.antes"
out=$("$EVOLVE" consolidate --dry-run 2>&1); rc=$?
chk "E12 consolidate --dry-run exit 0" "$rc" "0"
chk "E12 imprime PROPOSTAS DE PROMOÇÃO" "$(echo "$out" | grep -c 'PROPOSTAS DE PROMOÇÃO' || true)" "1"
nprop=$(echo "$out" | grep -c 'promover para o corpo da skill (SKILL.md/prompts)' || true)
if [ "$nprop" -ge 1 ]; then ok "E12 linha(s) de proposta (texto)"; else bad "E12 sem linha de proposta"; fi
chk "E12 SKILL.md NÃO foi escrito" "$(cmp -s "$CASE/SKILL.antes" "$CASE/repo/SKILL.md" && echo sim || echo nao)" "sim"
chk "E12 porcelain limpo (nada escrito)" "$(git -C "$CASE/repo" status --porcelain | wc -l)" "0"

echo "=== E13: orçamento — add avisa ORÇAMENTO; consolidate move as mais antigas ==="
newcase e13
write_skill
{
  learnings_head
  printf -- '- 2026-08-01 | gotcha | Build lento com cache frio [id: LEARN-20260801-001]\n'
  printf -- '- 2026-08-02 | gotcha | Uso do cache de build [id: LEARN-20260802-001]\n\n'
  printf -- '---\nid: LEARN-20260801-001\ndate: "2026-08-01"\ntype: gotcha\nconfidence: high\nsource: user\nstatus: active\nsupersedes: ""\ntags: [ci]\n---\n## Build lento com cache frio\n- **Observação:**\n'
  for i in $(seq 1 110); do printf -- '- detalhe %s do cache frio\n' "$i"; done
  printf -- '- **Ação:** aquecer o cache\n\n'
  entry LEARN-20260802-001 2026-08-02 gotcha medium user "[build]" "Uso do cache de build" "obs pequena" "acao pequena"
} > "$CASE/repo/LEARNINGS.md"
commit_all init
candidate "$CASE/n.txt" "Novo aprendizado de orcamento" gotcha low user "[docs]" "obs nova" "acao nova"
out=$("$EVOLVE" add "$CASE/n.txt" 2>&1)
chk "E13 add avisa ORÇAMENTO" "$(echo "$out" | grep -c 'ORÇAMENTO' || true)" "1"
"$EVOLVE" consolidate --apply >/dev/null 2>&1; rc=$?
chk "E13 consolidate --apply exit 0" "$rc" "0"
chk "E13 antiga mais antiga movida ao archive" "$(grep -cE '^id: LEARN-20260801-001$' "$CASE/repo/learnings_archive.md")" "1"
chk "E13 saiu do LEARNINGS.md" "$(grep -cE '^id: LEARN-20260801-001$' "$CASE/repo/LEARNINGS.md")" "0"

echo "=== E14: apply default inteligente — só LEARNINGS → direto; +SKILL.md → branch evolve/ ==="
newcase e14a
write_skill; seed_learnings; commit_all init
candidate "$CASE/a.txt" "Entrada E14" gotcha high user "[g]" "obs" "acao"
"$EVOLVE" add "$CASE/a.txt" >/dev/null 2>&1
head_before=$(git -C "$CASE/repo" rev-parse HEAD)
"$EVOLVE" apply >/dev/null 2>&1; rc=$?
chk "E14a apply exit 0" "$rc" "0"
chk "E14a commit DIRETO no branch atual" "$(git -C "$CASE/repo" rev-parse --abbrev-ref HEAD)" "main"
chk "E14a HEAD avançou" "$([ "$(git -C "$CASE/repo" rev-parse HEAD)" != "$head_before" ] && echo sim || echo nao)" "sim"
chk "E14a mensagem evolve(learnings):" "$(git -C "$CASE/repo" log -1 --format=%s | grep -c '^evolve(learnings): 1 aprendizado(s)' || true)" "1"
newcase e14b
write_skill; seed_learnings; commit_all init
candidate "$CASE/a.txt" "Entrada E14b" gotcha high user "[g]" "obs" "acao"
"$EVOLVE" add "$CASE/a.txt" >/dev/null 2>&1
printf '\n# nota de teste do apply\n' >> "$CASE/repo/SKILL.md"
"$EVOLVE" apply >/dev/null 2>&1; rc=$?
chk "E14b apply exit 0" "$rc" "0"
chk "E14b cria branch evolve/YYYY-MM-DD" "$(git -C "$CASE/repo" rev-parse --abbrev-ref HEAD)" "evolve/$TODAY_C"
chk "E14b commit no branch novo" "$(git -C "$CASE/repo" log -1 --format=%s | grep -c '^evolve(learnings):' || true)" "1"

echo "=== E15: allowlist/staged — staged fora da allowlist → exit 4, intacto; só allowlist → commit ==="
newcase e15
write_skill; seed_learnings; commit_all init
candidate "$CASE/a.txt" "Entrada E15" gotcha high user "[g]" "obs" "acao"
"$EVOLVE" add "$CASE/a.txt" >/dev/null 2>&1
echo segredo > "$CASE/repo/segredo.txt"
git -C "$CASE/repo" add segredo.txt
head_before=$(git -C "$CASE/repo" rev-parse HEAD)
out=$("$EVOLVE" apply --direct 2>&1); rc=$?
chk "E15 apply --direct exit 4" "$rc" "4"
chk "E15 mensagem de staged fora da allowlist" "$(echo "$out" | grep -c 'PATH STAGED FORA DA ALLOWLIST: segredo.txt' || true)" "1"
chk "E15 staged INTACTO (diff --cached)" "$(git -C "$CASE/repo" diff --cached --name-only)" "segredo.txt"
chk "E15 NADA commitado (HEAD igual)" "$(git -C "$CASE/repo" rev-parse HEAD)" "$head_before"
git -C "$CASE/repo" reset -q; rm -f "$CASE/repo/segredo.txt"
git -C "$CASE/repo" add LEARNINGS.md
out2=$("$EVOLVE" apply --direct 2>&1); rc2=$?
chk "E15b staged só na allowlist → commit exit 0" "$rc2" "0"
chk "E15b commitado (mensagem)" "$(echo "$out2" | grep -c 'commitado — evolve(learnings):' || true)" "1"

echo "=== E16: flock — lock ocupado → apply sai != 0 COM mensagem no stderr ==="
newcase e16
write_skill; seed_learnings; commit_all init
lockfile="$(git -C "$CASE/repo" rev-parse --absolute-git-dir)/evolve-skill.lock"
touch "$lockfile"
( flock -x "$lockfile" -c "touch $CASE/holder-ready; sleep 3" ) &
while [ ! -f "$CASE/holder-ready" ]; do sleep 0.02; done
out=$("$EVOLVE" apply --direct 2>&1); rc=$?
chk "E16 apply sai != 0 (exit 2)" "$rc" "2"
chk "E16 mensagem de lock ocupado no stderr" "$(echo "$out" | grep -c 'lock .* ocupado' || true)" "1"
wait

echo "=== E17: search — presente → exit 0 (id|data|type|confidence|source|título); ausente → exit 1 ==="
newcase e17
write_skill; seed_learnings; commit_all init
candidate "$CASE/a.txt" "Cache invalidation gotcha" gotcha high user "[cache]" "invalidar o cache" "rodar clean antes"
"$EVOLVE" add "$CASE/a.txt" >/dev/null 2>&1
out=$("$EVOLVE" search cache 2>&1); rc=$?
chk "E17 termo presente → exit 0" "$rc" "0"
chk "E17 linha id|data|type|confidence|source|título" "$(echo "$out" | grep -cE "^LEARN-[0-9]{8}-[0-9]{3} \| [0-9]{4}-[0-9]{2}-[0-9]{2} \| gotcha \| high \| user \| Cache" || true)" "1"
"$EVOLVE" search zzzplugh-inexistente >/dev/null 2>&1; chk "E17 termo ausente → exit 1" "$?" "1"

echo "=== E18: add PARALELO — 5 pares concorrentes → 10 entradas, 10 ids únicos ==="
newcase e18
write_skill; seed_learnings; commit_all init
for i in 1 2 3 4 5; do
  candidate "$CASE/cand$i.txt" "Paralelo $i a" fact high user "[p]" "obs $i a" "acao $i a"
  candidate_append "$CASE/cand$i.txt" "Paralelo $i b" fact high user "[p]" "obs $i b" "acao $i b"
  "$EVOLVE" add "$CASE/cand$i.txt" --source user >/dev/null 2>&1 &
done
wait
chk "E18 10 entradas" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "10"
chk "E18 10 ids ÚNICOS" "$(grep -E "$REALID" "$CASE/repo/LEARNINGS.md" | sort -u | wc -l)" "10"

echo "=== E19: --dry-run — add e consolidate NÃO escrevem nada (git status limpo) ==="
newcase e19
write_skill; seed_learnings; commit_all init
candidate "$CASE/a.txt" "Entrada E19" gotcha high user "[g]" "obs" "acao"
"$EVOLVE" add --dry-run "$CASE/a.txt" >/dev/null 2>&1; rc=$?
chk "E19 add --dry-run exit 0" "$rc" "0"
chk "E19 add --dry-run nada escrito (porcelain)" "$(git -C "$CASE/repo" status --porcelain | wc -l)" "0"
chk "E19 add --dry-run nenhum id" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "0"
"$EVOLVE" add "$CASE/a.txt" >/dev/null 2>&1
commit_all wip
"$EVOLVE" consolidate --dry-run >/dev/null 2>&1; rc2=$?
chk "E19 consolidate --dry-run exit 0" "$rc2" "0"
chk "E19 consolidate --dry-run nada escrito (porcelain)" "$(git -C "$CASE/repo" status --porcelain | wc -l)" "0"

echo "=== E20: apply idempotente — sem mudanças → exit 0, sem commit novo ==="
newcase e20
write_skill; seed_learnings; commit_all init
head_before=$(git -C "$CASE/repo" rev-parse HEAD)
out=$("$EVOLVE" apply 2>&1); rc=$?
chk "E20 apply exit 0" "$rc" "0"
chk "E20 sem commit novo (HEAD igual)" "$(git -C "$CASE/repo" rev-parse HEAD)" "$head_before"
chk "E20 mensagem 'nada a commitar'" "$(echo "$out" | grep -c 'nada a commitar' || true)" "1"

echo "=== E21: add aceita o formato do TEMPLATE (corpo - **Observação:**/- **Ação:**); frontmatter vence ==="
newcase e21
write_skill; seed_learnings; commit_all init
{
  printf -- '---\ntype: gotcha\nconfidence: high\nsource: user\ntags: [cache, build]\n---\n## Formato do template aceito\n- **Observação:** obs do template\n- **Ação:** acao do template\n---\ntitle: Ambos presentes\ntype: fact\nconfidence: high\nsource: user\ntags: [ambos]\nobservacao: valor do frontmatter\nacao: acao do frontmatter\n---\n## Ambos presentes\n- **Observação:** valor do corpo\n- **Ação:** acao do corpo\n'
} > "$CASE/tpl.txt"
out=$("$EVOLVE" add "$CASE/tpl.txt" 2>&1); rc=$?
chk "E21 add exit 0" "$rc" "0"
chk "E21 2 entradas anexadas" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "2"
chk "E21 primeiro id = LEARN-<hoje>-001" "$(grep -E "$REALID" "$CASE/repo/LEARNINGS.md" | head -1 | sed 's/^id: //')" "LEARN-$TODAY-001"
chk "E21 corpo do template preservado" "$(grep -c -- '- \*\*Observação:\*\* obs do template' "$CASE/repo/LEARNINGS.md" || true)" "1"
chk "E21 título veio do corpo (## )" "$(grep -c '^## Formato do template aceito$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E21 frontmatter VENCE (obs do frontmatter)" "$(grep -c 'valor do frontmatter' "$CASE/repo/LEARNINGS.md" || true)" "1"
chk "E21 corpo NÃO vazou (obs do corpo)" "$(grep -c 'valor do corpo' "$CASE/repo/LEARNINGS.md" || true)" "0"

echo "=== E22: SKILL.md REAL (.claude/skills/...) mudado → apply cria branch evolve/ (NUNCA direto) ==="
newcase e22
mkdir -p "$CASE/repo/.claude/skills/deep-orchestrator-agent-skill"
cat > "$CASE/repo/.claude/skills/deep-orchestrator-agent-skill/SKILL.md" <<'EOF'
---
name: deep-orchestrator-agent-skill
description: fixture de teste do motor de auto-evolucao
metadata:
  version: "3.7.0"
---
EOF
ln -s .claude/skills/deep-orchestrator-agent-skill/SKILL.md "$CASE/repo/SKILL.md"
seed_learnings; commit_all init
printf '\n# nota de corpo da skill (path real)\n' >> "$CASE/repo/.claude/skills/deep-orchestrator-agent-skill/SKILL.md"
out=$("$EVOLVE" apply 2>&1); rc=$?
chk "E22 apply exit 0" "$rc" "0"
chk "E22 cria branch evolve/YYYY-MM-DD" "$(git -C "$CASE/repo" rev-parse --abbrev-ref HEAD)" "evolve/$TODAY_C"
chk "E22 commit no branch novo" "$(git -C "$CASE/repo" log -1 --format=%s | grep -c '^evolve(learnings):' || true)" "1"
chk "E22 change do SKILL.md real COMMITADO" "$([ -z "$(git -C "$CASE/repo" diff HEAD -- .claude/skills/deep-orchestrator-agent-skill/SKILL.md)" ] && echo sim || echo nao)" "sim"
chk "E22 porcelain limpo" "$(git -C "$CASE/repo" status --porcelain | wc -l)" "0"
chk "E22 main NÃO recebeu o commit (sem nota)" "$(git -C "$CASE/repo" show "main:.claude/skills/deep-orchestrator-agent-skill/SKILL.md" | grep -c 'nota de corpo' || true)" "0"

echo "=== E23: superseded NÃO aparece no Índice após consolidate (corpo permanece) ==="
newcase e23
write_skill
{
  learnings_head
  printf -- '- 2026-08-01 | gotcha | Sempre use o flag cache ao rodar builds [id: LEARN-20260801-001]\n'
  printf -- '- 2026-08-22 | gotcha | Sempre use cache ao rodar builds [id: LEARN-20260822-001]\n\n'
  entry LEARN-20260801-001 2026-08-01 gotcha high user "[build, cache]" "Sempre use o flag cache ao rodar builds" "versao antiga" "usar cache"
  printf '\n'
  entry LEARN-20260822-001 2026-08-22 gotcha high user "[build, cache]" "Sempre use cache ao rodar builds" "versao nova" "usar cache"
} > "$CASE/repo/LEARNINGS.md"
commit_all init
"$EVOLVE" consolidate --apply >/dev/null 2>&1; rc=$?
chk "E23 consolidate --apply exit 0" "$rc" "0"
idx=$(awk '/^## Índice$/{f=1;next} f&&/^---$/{exit} f&&/^- [0-9]{4}-[0-9]{2}-[0-9]{2} \|/{print}' "$CASE/repo/LEARNINGS.md")
chk "E23 índice tem só 1 linha" "$(echo "$idx" | grep -c . || true)" "1"
chk "E23 superseded NÃO no índice" "$(echo "$idx" | grep -c 'LEARN-20260801-001' || true)" "0"
chk "E23 ativa no índice" "$(echo "$idx" | grep -c 'LEARN-20260822-001' || true)" "1"
chk "E23 superseded permanece no corpo" "$(grep -c '^status: superseded$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E23 corpo marcado ~~…~~" "$(grep -c '^## ~~Sempre use o flag cache ao rodar builds~~' "$CASE/repo/LEARNINGS.md")" "1"

echo "=== E24: add com entrada vazia → exit 0, 'nada a adicionar', nada escrito ==="
newcase e24
write_skill; seed_learnings; commit_all init
head_before=$(git -C "$CASE/repo" rev-parse HEAD)
out=$(printf '' | "$EVOLVE" add - 2>&1); rc=$?
chk "E24 add vazio exit 0" "$rc" "0"
chk "E24 mensagem 'nada a adicionar'" "$(echo "$out" | grep -c 'nada a adicionar' || true)" "1"
chk "E24 nada escrito (porcelain)" "$(git -C "$CASE/repo" status --porcelain | wc -l)" "0"
chk "E24 HEAD igual" "$(git -C "$CASE/repo" rev-parse HEAD)" "$head_before"
chk "E24 nenhum id novo" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "0"

echo "=== E25: contrato — contract: comando-inexistente-xyz → superseded 'contrato quebrado'; contract: bash passa ==="
newcase e25
write_skill
{
  learnings_head
  printf -- '- 2026-08-01 | fact | Ferramenta ausente no PATH [id: LEARN-20260801-001]\n'
  printf -- '- 2026-08-02 | fact | Deploy com bash funciona [id: LEARN-20260802-001]\n\n'
  printf -- '---\nid: LEARN-20260801-001\ndate: "2026-08-01"\ntype: fact\nconfidence: high\nsource: user\nstatus: active\nsupersedes: ""\ntags: [c]\ncontract: comando-inexistente-xyz\n---\n## Ferramenta ausente no PATH\n- **Observação:** obs\n- **Ação:** acao\n\n'
  printf -- '---\nid: LEARN-20260802-001\ndate: "2026-08-02"\ntype: fact\nconfidence: high\nsource: user\nstatus: active\nsupersedes: ""\ntags: [d]\ncontract: bash\n---\n## Deploy com bash funciona\n- **Observação:** obs2\n- **Ação:** acao2\n'
} > "$CASE/repo/LEARNINGS.md"
commit_all init
out=$("$EVOLVE" consolidate --apply 2>&1); rc=$?
chk "E25 consolidate --apply exit 0" "$rc" "0"
chk "E25 reporta contrato quebrado" "$(echo "$out" | grep -c 'contrato quebrado' || true)" "1"
chk "E25 motivo no corpo" "$(grep -c 'contrato quebrado: comando-inexistente-xyz ausente' "$CASE/repo/LEARNINGS.md" || true)" "1"
chk "E25 entrada marcada superseded" "$(grep -c '^status: superseded$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E25 contract: bash passa (ativa)" "$(awk '/^id: LEARN-20260802-001$/{f=1} f&&/^status: /{print;f=0}' "$CASE/repo/LEARNINGS.md")" "status: active"

echo "=== E26: supersessão por CONFIANÇA — web (nova) NUNCA supersede user (antiga); web não proposta ==="
newcase e26
write_skill
{
  learnings_head
  printf -- '- 2026-08-01 | gotcha | Use o cache ao rodar builds [id: LEARN-20260801-001]\n'
  printf -- '- 2026-08-22 | gotcha | Use cache ao rodar builds [id: LEARN-20260822-001]\n\n'
  entry LEARN-20260801-001 2026-08-01 gotcha high user "[build, cache]" "Use o cache ao rodar builds" "usar cache" "usar cache sempre"
  printf '\n'
  entry LEARN-20260822-001 2026-08-22 gotcha high web "[build, cache]" "Use cache ao rodar builds" "achado na web" "usar cache"
} > "$CASE/repo/LEARNINGS.md"
commit_all init
out=$("$EVOLVE" consolidate --apply 2>&1); rc=$?
chk "E26 consolidate --apply exit 0" "$rc" "0"
chk "E26 user vence (status active)" "$(awk '/^id: LEARN-20260801-001$/{f=1} f&&/^status: /{print;f=0}' "$CASE/repo/LEARNINGS.md")" "status: active"
chk "E26 web marcada superseded" "$(awk '/^id: LEARN-20260822-001$/{f=1} f&&/^status: /{print;f=0}' "$CASE/repo/LEARNINGS.md")" "status: superseded"
chk "E26 web supersedes a user" "$(grep -c '^supersedes: "LEARN-20260801-001"$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E26 relatório cita UNTRUSTED não supersede" "$(echo "$out" | grep -c 'UNTRUSTED não supersede' || true)" "1"
chk "E26 web NÃO proposta (estado pós-supersessão)" "$(echo "$out" | sed -n '/PROPOSTAS DE PROMO/,/^consolidate:/p' | grep -c 'LEARN-20260822-001' || true)" "0"

echo "=== E27: índice > 30 linhas → add avisa ÍNDICE ==="
newcase e27
write_skill
{
  learnings_head
  for i in $(seq 1 31); do
    dd=$(printf '%02d' $((i % 28 + 1)))
    idn=$(printf '%03d' "$i")
    printf -- '- 2026-08-%s | fact | Titulo de orcamento %s [id: LEARN-202608%s-%s]\n' "$dd" "$i" "$dd" "$idn"
  done
  printf '\n'
  for i in $(seq 1 31); do
    dd=$(printf '%02d' $((i % 28 + 1)))
    idn=$(printf '%03d' "$i")
    entry "LEARN-202608$dd-$idn" "2026-08-$dd" fact high user "[o]" "Titulo de orcamento $i" "obs $i" "acao $i"
    printf '\n'
  done
} > "$CASE/repo/LEARNINGS.md"
commit_all init
candidate "$CASE/n.txt" "Entrada E27" fact high user "[g]" "obs" "acao"
out=$("$EVOLVE" add "$CASE/n.txt" 2>&1); rc=$?
chk "E27 add exit 0" "$rc" "0"
chk "E27 avisa ÍNDICE (rode consolidate)" "$(echo "$out" | grep -c 'ÍNDICE' || true)" "1"

echo "=== E28: dois candidatos body-only separados por '---' → add anexa 2 entradas (nenhuma descartada) ==="
newcase e28
write_skill; seed_learnings; commit_all init
{
  printf '## Primeiro aprendizado body-only\ntype: gotcha\nconfidence: high\nsource: user\ntags: [a]\n- **Observação:** obs um\n- **Ação:** acao um\n---\n## Segundo aprendizado body-only\ntype: fact\nconfidence: high\nsource: repo-doc\ntags: [b]\n- **Observação:** obs dois\n- **Ação:** acao dois\n'
} > "$CASE/body.txt"
out=$("$EVOLVE" add "$CASE/body.txt" 2>&1); rc=$?
chk "E28 add exit 0" "$rc" "0"
chk "E28 add reporta 2 adicionada(s)" "$(echo "$out" | grep -c 'add: 2 adicionada(s), 0 duplicada(s) ignorada(s)' || true)" "1"
chk "E28 2 entradas anexadas" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "2"
chk "E28 1º título preservado" "$(grep -c '^## Primeiro aprendizado body-only$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E28 2º título preservado (não descartado)" "$(grep -c '^## Segundo aprendizado body-only$' "$CASE/repo/LEARNINGS.md")" "1"
chk "E28 corpo do 2º preservado" "$(grep -c 'obs dois' "$CASE/repo/LEARNINGS.md" || true)" "1"

echo "=== E29: promoção ≥2 conta evidência no learnings_archive.md (F-11b) ==="
newcase e29
write_skill
{
  learnings_head
  printf -- '- 2026-08-22 | gotcha | Fluxo X confirmado [id: LEARN-20260822-001]\n\n'
  entry LEARN-20260822-001 2026-08-22 gotcha high repo-doc "[fluxo]" "Fluxo X confirmado" "obs B" "acao B"
} > "$CASE/repo/LEARNINGS.md"
{
  printf '# LEARNINGS ARCHIVE — deep-orchestrator-agent-skill\n\n> fixture de teste.\n\n'
  printf -- '<!-- evolve-skill consolidate: arquivada em 2026-08-22 — duplicata de LEARN-20260822-001 -->\n'
  entry LEARN-20260801-001 2026-08-01 gotcha high repo-doc "[fluxo]" "Fluxo X confirmado" "obs A" "acao A"
} > "$CASE/repo/learnings_archive.md"
commit_all init
out=$("$EVOLVE" consolidate --dry-run 2>&1); rc=$?
chk "E29 consolidate --dry-run exit 0" "$rc" "0"
chk "E29 imprime PROPOSTAS DE PROMOÇÃO" "$(echo "$out" | grep -c 'PROPOSTAS DE PROMOÇÃO' || true)" "1"
chk "E29 proposta cita 2 ocorrência(s) em datas distintas" "$(echo "$out" | grep -c '2 ocorrência(s) em datas distintas' || true)" "1"
chk "E29 proposta cita a entrada ativa" "$(echo "$out" | grep -c 'promover para o corpo da skill (SKILL.md/prompts): LEARN-20260822-001' || true)" "1"
chk "E29 dry-run nada escrito (porcelain)" "$(git -C "$CASE/repo" status --porcelain | wc -l)" "0"
# parte 2: idêntica situação com fonte UNTRUSTED (web) → NENHUMA proposta
{
  learnings_head
  printf -- '- 2026-08-22 | gotcha | Fluxo X confirmado [id: LEARN-20260822-001]\n\n'
  entry LEARN-20260822-001 2026-08-22 gotcha high web "[fluxo]" "Fluxo X confirmado" "obs B" "acao B"
} > "$CASE/repo/LEARNINGS.md"
commit_all web
out2=$("$EVOLVE" consolidate --dry-run 2>&1); rc2=$?
chk "E29 web: consolidate exit 0" "$rc2" "0"
chk "E29 web: NENHUMA proposta" "$(echo "$out2" | grep -c 'PROPOSTAS DE PROMOÇÃO' || true)" "0"
chk "E29 web: relatório 'propostas: nenhuma'" "$(echo "$out2" | grep -c 'propostas de promoção: nenhuma' || true)" "1"

echo "=== E30: múltiplas linhas '- **Observação:**' no mesmo bloco são juntadas (preservadas) ==="
newcase e30
write_skill; seed_learnings; commit_all init
{
  printf -- '---\ntitle: Duas observacoes\ntype: gotcha\nconfidence: high\nsource: user\ntags: [a]\n---\n## Duas observacoes\n- **Observação:** primeira observacao\n- **Observação:** segunda observacao\n- **Ação:** acao\n'
} > "$CASE/obs2.txt"
out=$("$EVOLVE" add "$CASE/obs2.txt" 2>&1); rc=$?
chk "E30 add exit 0" "$rc" "0"
chk "E30 1 entrada anexada" "$(grep -cE "$REALID" "$CASE/repo/LEARNINGS.md" || true)" "1"
chk "E30 ambas observações juntadas na entrada" "$(grep -c -- '- \*\*Observação:\*\* primeira observacao segunda observacao' "$CASE/repo/LEARNINGS.md" || true)" "1"
chk "E30 nenhuma observação descartada" "$(grep -c 'primeira observacao' "$CASE/repo/LEARNINGS.md" || true)" "1"
chk "E30 Ação preservada" "$(grep -c -- '- \*\*Ação:\*\* acao' "$CASE/repo/LEARNINGS.md" || true)" "1"

echo; printf 'RESULTADO: %s PASS, %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1
