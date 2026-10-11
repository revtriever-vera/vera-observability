#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_NAME="${1:?uso: <script> <dev|prod>}"
ENV_FILE="$ROOT/environments/$ENV_NAME.env"
[ -f "$ENV_FILE" ] || ENV_FILE="$ROOT/environments/$ENV_NAME.env.example"
[ -f "$ENV_FILE" ] || { echo "ambiente desconhecido: $ENV_NAME" >&2; exit 1; }

# A Grafana é compartilhada com outros produtos: este repo só lê e escreve
# dashboards e alert rules da pasta abaixo. Contact points e a política de
# notificação pertencem ao revtriever-observability-infra.
FOLDER_UID=vera
FOLDER_TITLE="$(cat "$ROOT/dashboards/$FOLDER_UID/.folder")"
PROJECT=vera

OVERRIDABLE=(GRAFANA_URL GRAFANA_TOKEN_FILE DS_PROMETHEUS DS_LOKI DS_TEMPO DS_POSTGRES)
OVERRIDES=()
for name in "${OVERRIDABLE[@]}"; do
    if [ -n "${!name:-}" ]; then
        OVERRIDES+=("$name=${!name}")
    fi
done

set -a
source "$ENV_FILE"
for entry in "${OVERRIDES[@]}"; do
    export "$entry"
done
set +a

[ -n "${GRAFANA_URL:-}" ] || { echo "GRAFANA_URL não definido (variável de ambiente ou $ENV_FILE)" >&2; exit 1; }
case "$GRAFANA_URL" in
    *.invalid*) echo "GRAFANA_URL é o placeholder do .example: defina a URL real por variável de ambiente" >&2; exit 1 ;;
esac

if [ -z "${GRAFANA_TOKEN:-}" ] && [ -n "${GRAFANA_TOKEN_FILE:-}" ]; then
    GRAFANA_TOKEN="$(cat "${GRAFANA_TOKEN_FILE/#\~/$HOME}")"
fi
[ -n "${GRAFANA_TOKEN:-}" ] || { echo "GRAFANA_TOKEN não definido (env ou GRAFANA_TOKEN_FILE)" >&2; exit 1; }

ACCESS_HEADERS=()
if [ -n "${CF_ACCESS_CLIENT_ID:-}" ] && [ -n "${CF_ACCESS_CLIENT_SECRET:-}" ]; then
    ACCESS_HEADERS=(-H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET")
fi

api() {
    local method="$1" path="$2"
    shift 2
    curl -sf -X "$method" "$GRAFANA_URL$path" \
        -H "Authorization: Bearer $GRAFANA_TOKEN" \
        -H 'Content-Type: application/json' \
        -H 'X-Disable-Provenance: true' \
        "${ACCESS_HEADERS[@]}" \
        "$@"
}

# GET que devolve vazio (status 0) quando o recurso não existe (404) e falha em qualquer outro erro.
api_get_optional() {
    local body code
    body="$(mktemp)"
    code="$(curl -s -o "$body" -w '%{http_code}' "$GRAFANA_URL$1" \
        -H "Authorization: Bearer $GRAFANA_TOKEN" \
        "${ACCESS_HEADERS[@]}")"
    case "$code" in
        200) cat "$body"; rm -f "$body" ;;
        404) rm -f "$body" ;;
        *) echo "GET $1 falhou: HTTP $code" >&2; rm -f "$body"; return 1 ;;
    esac
}

# Pasta em que um dashboard existente está ("" se o uid não existe).
dashboard_folder() {
    api_get_optional "/api/dashboards/uid/$1" | jq -r '.meta.folderUid // ""'
}

# Pasta de uma alert rule existente ("" se o uid não existe).
rule_folder() {
    api_get_optional "/api/v1/provisioning/alert-rules/$1" | jq -r '.folderUID // ""'
}

# UIDs das alert rules da pasta do projeto (export filtrado por pasta; 404 = pasta sem regras).
folder_rule_uids() {
    api_get_optional "/api/v1/provisioning/alert-rules/export?folderUid=$FOLDER_UID&format=json" \
        | jq -r '.groups[]?.rules[]?.uid'
}

tokenize() {
    sed -e "s/\"$DS_LOKI\"/\"__DS_LOKI__\"/g" \
        -e "s/\"$DS_PROMETHEUS\"/\"__DS_PROMETHEUS__\"/g" \
        -e "s/\"$DS_TEMPO\"/\"__DS_TEMPO__\"/g"
}

detokenize() {
    sed -e "s/__DS_LOKI__/$DS_LOKI/g" \
        -e "s/__DS_PROMETHEUS__/$DS_PROMETHEUS/g" \
        -e "s/__DS_TEMPO__/$DS_TEMPO/g"
}

# Campos que o Grafana gera sozinho e que não são versionados.
normalize_rule() {
    jq --indent 1 'del(.id, .updated, .provenance) | .version = 0'
}

normalize_dashboard() {
    jq --indent 1 '.dashboard | del(.id) | .version = 0'
}
