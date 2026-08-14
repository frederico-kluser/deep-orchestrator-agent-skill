#!/usr/bin/env bash
#
# generate-explainer.sh — Gera o EXPLAINER.html da execução a partir do template
# templates/html-explainer.html (a casa da skill é resolvida pelo path do
# próprio script: "$(dirname "$0")/..").
#
# ENTRADA:
#   Tokens inline (OBRIGATÓRIOS — erro claro + exit 1 se faltar):
#     --version <v>         {{VERSION}}        --date <data>          {{DATE}}
#     --branch <branch>     {{BRANCH}}         --task-summary <texto> {{TASK_SUMMARY}}
#     --total-waves <N>     {{TOTAL_WAVES}}    --total-agents <N>     {{TOTAL_AGENTS}}
#     --total-commits <N>   {{TOTAL_COMMITS}}
#   Slots (OPCIONAIS — cada flag recebe um ARQUIVO com o conteúdo HTML da seção):
#     --waves-table <f>     {{WAVES_TABLE}}    --files-table <f>   {{FILES_TABLE}}
#     --commits-list <f>    {{COMMITS_LIST}}   --before-after <f>  {{BEFORE_AFTER}}
#     --impact <f>          {{IMPACT}}         --capabilities <f>  {{CAPABILITIES}}
#     --decisions <f>       {{DECISIONS}}      --timeline <f>      {{TIMELINE}}
#   Saída:
#     --output <arquivo>    escreve no arquivo (sem --output: stdout; "-" = stdout)
#     --template <arquivo>  template alternativo (default: ../templates/html-explainer.html)
#
# COMPORTAMENTO:
#   · Slot com arquivo: o conteúdo do arquivo substitui o bloco INTEIRO entre
#     os marcadores <!-- {{NOME}} begin --> ... <!-- {{NOME}} end --> (os
#     marcadores morrem).
#   · Slot sem arquivo: o bloco demo do template permanece, com os marcadores
#     neutralizados e anotados como "(não preenchido — conteúdo demo)".
#   · Validação final: nenhum "{{" residual no output — nem token, nem slot,
#     nem placeholder genérico de bloco demo. Se sobrar, exit 1 com a lista.
#     Conteúdo de slot NÃO pode conter "{{".
#   · O comentário-cabeçalho do template (docs de uso, com exemplos {{...}})
#     é removido no output gerado.
#
# EXIT CODES: 0 ok · 1 erro de geração/validação · 2 erro de uso.
# DEPENDÊNCIA: python3 (a mesma da cadeia de busca — brave-search.sh).
#
# Exemplo:
#   generate-explainer.sh --version v3.2.0 --date 2026-08-14 --branch development \
#     --task-summary "Execução de teste" --total-waves 3 --total-agents 7 \
#     --total-commits 12 --waves-table /tmp/waves.html --decisions /tmp/dec.html \
#     --output EXPLAINER.html
set -u

usage() {
  awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
}

# get_val <flag> <valor...> — valida que a flag tem valor; grava em $val.
get_val() {
  if [ $# -lt 2 ]; then
    echo "ERRO: a flag $1 requer um valor" >&2
    exit 2
  fi
  val="$2"
}

template=""
output=""
version=""
date=""
branch=""
task_summary=""
total_waves=""
total_agents=""
total_commits=""
waves_table=""
files_table=""
commits_list=""
before_after=""
impact=""
capabilities=""
decisions=""
timeline=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --version)       get_val "$@"; version="$val"; shift 2 ;;
    --date)          get_val "$@"; date="$val"; shift 2 ;;
    --branch)        get_val "$@"; branch="$val"; shift 2 ;;
    --task-summary)  get_val "$@"; task_summary="$val"; shift 2 ;;
    --total-waves)   get_val "$@"; total_waves="$val"; shift 2 ;;
    --total-agents)  get_val "$@"; total_agents="$val"; shift 2 ;;
    --total-commits) get_val "$@"; total_commits="$val"; shift 2 ;;
    --waves-table)   get_val "$@"; waves_table="$val"; shift 2 ;;
    --files-table)   get_val "$@"; files_table="$val"; shift 2 ;;
    --commits-list)  get_val "$@"; commits_list="$val"; shift 2 ;;
    --before-after)  get_val "$@"; before_after="$val"; shift 2 ;;
    --impact)        get_val "$@"; impact="$val"; shift 2 ;;
    --capabilities)  get_val "$@"; capabilities="$val"; shift 2 ;;
    --decisions)     get_val "$@"; decisions="$val"; shift 2 ;;
    --timeline)      get_val "$@"; timeline="$val"; shift 2 ;;
    --output)        get_val "$@"; output="$val"; shift 2 ;;
    --template)      get_val "$@"; template="$val"; shift 2 ;;
    *) echo "ERRO: flag desconhecida: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- Tokens obrigatórios -----------------------------------------------------
missing=""
[ -n "$version" ]       || missing="$missing --version"
[ -n "$date" ]          || missing="$missing --date"
[ -n "$branch" ]        || missing="$missing --branch"
[ -n "$task_summary" ]  || missing="$missing --task-summary"
[ -n "$total_waves" ]   || missing="$missing --total-waves"
[ -n "$total_agents" ]  || missing="$missing --total-agents"
[ -n "$total_commits" ] || missing="$missing --total-commits"
if [ -n "$missing" ]; then
  echo "ERRO: token(s) obrigatório(s) faltando:$missing" >&2
  echo "Uso: $0 --help" >&2
  exit 1
fi

# --- Template ----------------------------------------------------------------
if [ -z "$template" ]; then
  template="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/templates/html-explainer.html"
fi
if [ ! -f "$template" ] || [ ! -r "$template" ]; then
  echo "ERRO: template não encontrado ou ilegível: $template" >&2
  exit 1
fi

# --- Arquivos de slot --------------------------------------------------------
for entry in \
  "WAVES_TABLE|$waves_table" "FILES_TABLE|$files_table" "COMMITS_LIST|$commits_list" \
  "BEFORE_AFTER|$before_after" "IMPACT|$impact" "CAPABILITIES|$capabilities" \
  "DECISIONS|$decisions" "TIMELINE|$timeline"; do
  name="${entry%%|*}"
  path="${entry#*|}"
  if [ -n "$path" ] && { [ ! -f "$path" ] || [ ! -r "$path" ]; }; then
    echo "ERRO: arquivo do slot $name não encontrado ou ilegível: $path" >&2
    exit 1
  fi
done

# --- python3 -----------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERRO: python3 não encontrado no PATH (dependência da cadeia de busca — brave-search.sh)" >&2
  exit 1
fi

python3 - \
  --template "$template" \
  --version "$version" --date "$date" --branch "$branch" \
  --task-summary "$task_summary" \
  --total-waves "$total_waves" --total-agents "$total_agents" --total-commits "$total_commits" \
  --waves-table "$waves_table" --files-table "$files_table" --commits-list "$commits_list" \
  --before-after "$before_after" --impact "$impact" --capabilities "$capabilities" \
  --decisions "$decisions" --timeline "$timeline" \
  --output "$output" <<'PY'
import re
import sys

TOKENS = ["VERSION", "DATE", "BRANCH", "TASK_SUMMARY",
          "TOTAL_WAVES", "TOTAL_AGENTS", "TOTAL_COMMITS"]
SLOTS = ["WAVES_TABLE", "FILES_TABLE", "COMMITS_LIST", "BEFORE_AFTER",
         "IMPACT", "CAPABILITIES", "DECISIONS", "TIMELINE"]


def fail(msg):
    sys.stderr.write("generate-explainer.sh: ERRO: %s\n" % msg)
    sys.exit(1)


def flag_of(name):
    return "--" + name.lower().replace("_", "-")


def main():
    argv = sys.argv[1:]
    args = {}
    i = 0
    while i < len(argv):
        name = argv[i]
        if i + 1 >= len(argv):
            fail("flag sem valor: %s" % name)
        args[name] = argv[i + 1]
        i += 2

    template = args.get("--template", "")
    if not template:
        fail("template não informado")
    try:
        with open(template, "r", encoding="utf-8") as fh:
            html = fh.read()
    except OSError as exc:
        fail("não foi possível ler o template %s: %s" % (template, exc))

    # 1. Remove o comentário-cabeçalho do template (docs de uso, com exemplos
    #    {{...}} — não pertence ao documento gerado e vazaria na validação).
    html = re.sub(r"<!--.*?-->", "", html, count=1, flags=re.S)

    # 2. Tokens inline (todos obrigatórios).
    missing = []
    for name in TOKENS:
        val = args.get(flag_of(name), "")
        if val == "":
            missing.append("{{%s}}" % name)
            continue
        html = html.replace("{{%s}}" % name, val)
    if missing:
        fail("token(s) obrigatório(s) faltando: %s" % ", ".join(missing))

    # 3. Slots: arquivo substitui o bloco INTEIRO (marcadores morrem); sem
    #    arquivo, o bloco demo permanece com os marcadores neutralizados.
    for name in SLOTS:
        flag = flag_of(name)
        path = args.get(flag, "")
        begin = "<!-- {{%s}} begin -->" % name
        end = "<!-- {{%s}} end -->" % name
        if path:
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    content = fh.read()
            except OSError as exc:
                fail("não foi possível ler o conteúdo do slot %s (%s): %s"
                     % (name, path, exc))
            pattern = re.compile(r"[ \t]*" + re.escape(begin) + r".*?"
                                 + re.escape(end) + r"[ \t]*\r?\n?", re.S)
            new_html, n = pattern.subn(content.rstrip("\n") + "\n", html, count=1)
            if n == 0:
                fail("marcadores do slot %s não encontrados no template: %s ... %s"
                     % (name, begin, end))
            html = new_html
        else:
            note = "(não preenchido — conteúdo demo do template)"
            html = html.replace(begin, "<!-- %s begin %s -->" % (name, note))
            html = html.replace(end, "<!-- %s end %s -->" % (name, note))

    # 4. Validação: nenhum token/slot residual...
    residual = []
    for name in TOKENS + SLOTS:
        token = "{{%s}}" % name
        if token in html:
            residual.append(token)
    if residual:
        fail("token(s) residual(is) no output: %s (drift do template?)"
             % ", ".join(residual))

    # ...nem "{{" genérico: placeholders {{...}} que sobrarem em blocos demo
    # não preenchidos viram "(...)" — o output nunca pode conter "{{".
    html = re.sub(r"\{\{[^}]*\}\}", "(...)", html)
    if "{{" in html:
        fail("ainda existe '{{' no output — conteúdo de slot com placeholder? "
             "Reveja os arquivos de slot e o template")

    if not html.endswith("\n"):
        html += "\n"

    out = args.get("--output", "")
    if out and out != "-":
        try:
            with open(out, "w", encoding="utf-8") as fh:
                fh.write(html)
        except OSError as exc:
            fail("não foi possível escrever %s: %s" % (out, exc))
    else:
        sys.stdout.write(html)

    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
exit $?
