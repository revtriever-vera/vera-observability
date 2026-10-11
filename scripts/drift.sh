#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OUT_DIR="$TMP/grafana" "$HERE/pull.sh" "$1" >/dev/null

# Compara JSON canônico (chaves ordenadas, sem nulls) só da pasta vera, para que
# formatação ou campos nulos omitidos pelo Grafana não contem como drift.
canon() {
    jq -S 'walk(if type == "object" then with_entries(select(.value != null)) else . end)' "$1"
}

status=0
for dir in "$REPO" "$TMP/grafana"; do
    (cd "$dir" && find dashboards/vera alerts/rules -maxdepth 1 -name '*.json' 2>/dev/null || true)
done | sort -u > "$TMP/files"

while read -r rel; do
    if [ ! -f "$REPO/$rel" ]; then
        echo "só no Grafana: $rel"; status=1
    elif [ ! -f "$TMP/grafana/$rel" ]; then
        echo "só no repo: $rel"; status=1
    else
        diff -u --label "repo/$rel" --label "grafana/$rel" <(canon "$REPO/$rel") <(canon "$TMP/grafana/$rel") || status=1
    fi
done < "$TMP/files"

if [ "$status" -ne 0 ]; then
    echo ''
    echo "DRIFT: o Grafana ($1) diverge do repo na pasta vera — alguém editou a UI sem versionar, ou o repo não foi aplicado."
    exit 1
fi
echo "sem drift: Grafana ($1) e repo estão idênticos na pasta vera"
