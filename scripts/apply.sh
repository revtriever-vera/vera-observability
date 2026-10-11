#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$1"

# Valida tudo antes de escrever qualquer coisa: o contrato da Grafana compartilhada
# exige pasta própria, labels project/severity e roteamento só pela política raiz.
for file in "$ROOT"/alerts/rules/*.json; do
    [ -f "$file" ] || continue
    problem="$(jq -r --arg f "$FOLDER_UID" --arg p "$PROJECT" '
        if .folderUID != $f then "folderUID deve ser \($f)"
        elif .labels.project != $p then "label project deve ser \($p)"
        elif (.labels.severity | IN("critical", "warning") | not) then "label severity deve ser critical ou warning"
        elif .notification_settings != null then "notification_settings não é permitido: o roteamento é da política compartilhada"
        else empty end' "$file")"
    if [ -n "$problem" ]; then
        echo "$(basename "$file"): $problem" >&2
        exit 1
    fi
done

echo "== pasta $FOLDER_TITLE ($FOLDER_UID) =="
if [ -z "$(api_get_optional "/api/folders/$FOLDER_UID")" ]; then
    api POST '/api/folders' -d "$(jq -n --arg uid "$FOLDER_UID" --arg title "$FOLDER_TITLE" '{uid: $uid, title: $title}')" >/dev/null
    echo "  + $FOLDER_TITLE"
fi

echo "== dashboards =="
for file in "$ROOT/dashboards/$FOLDER_UID"/*.json; do
    [ -f "$file" ] || continue
    payload="$(detokenize < "$file")"
    uid="$(jq -r '.uid' <<< "$payload")"
    current="$(dashboard_folder "$uid")"
    if [ -n "$current" ] && [ "$current" != "$FOLDER_UID" ]; then
        echo "dashboard $uid já existe na pasta $current: não é do $PROJECT, abortando" >&2
        exit 1
    fi
    jq -n --argjson d "$payload" --arg folderUid "$FOLDER_UID" '{dashboard: $d, folderUid: $folderUid, overwrite: true}' \
        | api POST '/api/dashboards/db' -d @- | jq -r '"  \(.status) \(.slug // .uid)"'
done

echo "== alert rules =="
for file in "$ROOT"/alerts/rules/*.json; do
    [ -f "$file" ] || continue
    rule="$(detokenize < "$file")"
    uid="$(jq -r '.uid' <<< "$rule")"
    current="$(rule_folder "$uid")"
    if [ -z "$current" ]; then
        api POST '/api/v1/provisioning/alert-rules' -d "$rule" >/dev/null && echo "  + $(jq -r '.title' <<< "$rule")"
    elif [ "$current" = "$FOLDER_UID" ]; then
        api PUT "/api/v1/provisioning/alert-rules/$uid" -d "$rule" >/dev/null && echo "  ~ $(jq -r '.title' <<< "$rule")"
    else
        echo "alert rule $uid já existe na pasta $current: não é do $PROJECT, abortando" >&2
        exit 1
    fi
done

echo "apply concluído em $GRAFANA_URL (pasta $FOLDER_UID)"
