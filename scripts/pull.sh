#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$1"

OUT="${OUT_DIR:-$ROOT}"
mkdir -p "$OUT/dashboards/$FOLDER_UID" "$OUT/alerts/rules"
# O pull espelha a pasta: o que sumiu do Grafana some do repo também.
rm -f "$OUT/dashboards/$FOLDER_UID"/*.json "$OUT/alerts/rules"/*.json

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

echo "pull concluído em $OUT"
