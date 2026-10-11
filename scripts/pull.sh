#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$1"

FINAL="${OUT_DIR:-$ROOT}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT/dashboards/$FOLDER_UID" "$OUT/alerts/rules"

echo "== dashboards (pasta $FOLDER_UID) =="
api GET "/api/search?type=dash-db&folderUIDs=$FOLDER_UID&limit=5000" | jq -r '.[].uid' | while read -r uid; do
    api GET "/api/dashboards/uid/$uid" | normalize_dashboard | tokenize > "$OUT/dashboards/$FOLDER_UID/${uid#"$PROJECT"-}.json"
    echo "  $(jq -r '.title' "$OUT/dashboards/$FOLDER_UID/${uid#"$PROJECT"-}.json")"
done

echo "== alert rules (pasta $FOLDER_UID) =="
folder_rule_uids | while read -r uid; do
    api GET "/api/v1/provisioning/alert-rules/$uid" | normalize_rule | tokenize > "$OUT/alerts/rules/${uid#"$PROJECT"-}.json"
    echo "  $(jq -r '.title' "$OUT/alerts/rules/${uid#"$PROJECT"-}.json")"
done

# O pull espelha a pasta: o que sumiu do Grafana some do repo também, mas só depois de tudo ter sido baixado.
mkdir -p "$FINAL/dashboards/$FOLDER_UID" "$FINAL/alerts/rules"
rm -f "$FINAL/dashboards/$FOLDER_UID"/*.json "$FINAL/alerts/rules"/*.json
cp "$OUT/dashboards/$FOLDER_UID"/*.json "$FINAL/dashboards/$FOLDER_UID/" 2>/dev/null || true
cp "$OUT/alerts/rules"/*.json "$FINAL/alerts/rules/" 2>/dev/null || true

echo "pull concluído em $FINAL"
