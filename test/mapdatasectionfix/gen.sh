#!/usr/bin/env bash
# gen.sh OUT SHAPE LEN N — the deterministic fixture generator for test/mapdatasectioncheck.sh.
#
# Writes one fixture tree into OUT (created; must not exist): eight Python functions in app.py — a call chain
# under an uncalled `main`, plus an uncalled `_helper` — and ONE data file whose N entries index as
# SymKind::Section rows:
#   S1  db/schema.rb   N tables, each an implicit `id`, seven typed columns and `t.timestamps`
#                      (Rails schema columns; Sections only on a build that carries the #339 capture)
#   S2  docs/guide.md  N `##` headings (plus the doc file's own whole-file Section)
#   S3  config.yaml    N top-level keys
#   S4  data.json      N top-level keys
# LEN picks the data names: `long` names are >= 8 characters and >= 2 words, so priorwt::weight gives them
# the x1.7 specific-name boost; `short` names are one short word (no boost). Code names never change.
# The output is a pure function of the arguments: no dates, no randomness, no environment reads.
set -eu
out="$1"; shape="$2"; len="$3"; n="$4"
case "$shape" in S1|S2|S3|S4) ;; *) echo "gen.sh: SHAPE must be S1|S2|S3|S4" >&2; exit 2 ;; esac
case "$len" in long|short) ;; *) echo "gen.sh: LEN must be long|short" >&2; exit 2 ;; esac
case "$n" in ''|*[!0-9]*) echo "gen.sh: N must be a positive integer" >&2; exit 2 ;; esac
[ -e "$out" ] && { echo "gen.sh: $out exists" >&2; exit 2; }
mkdir -p "$out"

cat >"$out/app.py" <<'EOF'
def load(path):
    with open(path) as handle:
        return handle.read()


def parse(text):
    return text.split()


def normalize(item):
    return item.strip()


def transform(items):
    return [normalize(item) for item in items]


def render(items):
    return "\n".join(items)


def save(text, path):
    with open(path, "w") as handle:
        handle.write(text)


def _helper(value):
    return value


def main():
    data = load("in.txt")
    items = transform(parse(data))
    save(render(items), "out.txt")
EOF

i=1
case "$shape" in
S1)
    mkdir -p "$out/db"
    {
        printf 'ActiveRecord::Schema[8.1].define(version: 2026_09_30_000001) do\n'
        while [ "$i" -le "$n" ]; do
            printf '  create_table "table_%d", force: :cascade do |t|\n' "$i"
            for j in 1 2 3 4 5 6 7; do
                if [ "$len" = long ]; then
                    printf '    t.string "billing_address_line_%d_%d"\n' "$i" "$j"
                else
                    printf '    t.string "c%d"\n' "$j"
                fi
            done
            printf '    t.timestamps\n  end\n\n'
            i=$(( i + 1 ))
        done
        printf 'end\n'
    } >"$out/db/schema.rb"
    ;;
S2)
    mkdir -p "$out/docs"
    {
        printf '# Guide\n\n'
        while [ "$i" -le "$n" ]; do
            if [ "$len" = long ]; then printf '## Installation step %d details\n\nText.\n\n' "$i"
            else printf '## s%d\n\nText.\n\n' "$i"; fi
            i=$(( i + 1 ))
        done
    } >"$out/docs/guide.md"
    ;;
S3)
    {
        while [ "$i" -le "$n" ]; do
            if [ "$len" = long ]; then printf 'database_url_%d: value\n' "$i"
            else printf 'k%d: value\n' "$i"; fi
            i=$(( i + 1 ))
        done
    } >"$out/config.yaml"
    ;;
S4)
    {
        printf '{\n'
        while [ "$i" -le "$n" ]; do
            sep=','; [ "$i" -eq "$n" ] && sep=''
            if [ "$len" = long ]; then printf '  "database_url_%d": "value"%s\n' "$i" "$sep"
            else printf '  "k%d": "value"%s\n' "$i" "$sep"; fi
            i=$(( i + 1 ))
        done
        printf '}\n'
    } >"$out/data.json"
    ;;
esac
