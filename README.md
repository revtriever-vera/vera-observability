# vera-observability

Dashboards e alertas da [Vera](https://github.com/revtriever-vera/vera) como código: JSON tokenizado da Grafana versionado aqui, com scripts para aplicar (`apply`), comparar (`drift`) e trazer de volta (`pull`).

## As duas stacks

Uma Grafana por ambiente, o mesmo texto tokenizado nas duas:

| Ambiente | Onde | Datasources |
|---|---|---|
| dev | Grafana Cloud (opcional) | `grafanacloud-prom`, `grafanacloud-logs`, `grafanacloud-traces` |
| prod | Grafana self-hosted na EC2 LGTM compartilhada da organização, atrás do Cloudflare Access | nomes definidos por variável do repositório |

Os dashboards e alertas usam os tokens `__DS_PROMETHEUS__`, `__DS_LOKI__` e `__DS_TEMPO__`; o `apply` troca pelos nomes de datasource do ambiente e o `pull` faz o caminho inverso.

Este repositório é público: nenhuma URL, token, ID de datasource real ou canal de notificação é versionado. Esses valores vêm de variáveis e secrets do repositório ou de arquivos de ambiente ignorados pelo git.

## Modelo

- Pasta única "Vera" (`uid` `vera`), com `dashboards/vera/*.json` e `alerts/rules/*.json`. O nome do arquivo é o `uid` sem o prefixo `vera-`.
- A Grafana é compartilhada com outros produtos. Os scripts só escrevem na pasta `vera` e recusam escrever num `uid` que já exista em outra pasta.
- Contact points e política de notificação são da infraestrutura compartilhada e não ficam aqui. Toda alert rule tem `labels.project = vera`, `labels.severity` igual a `critical` ou `warning` e não tem `notification_settings`; o `apply.sh` valida isso antes de escrever. A política raiz da Grafana deve rotear `project=vera`.
- Telemetria separada por label: `service_namespace=vera`, `service_name=vera-api` e `deployment_environment_name`. Dashboards filtram por `$project` (fixa em `vera`), `$service` e `$env`. No Loki, `identifier`, `requestId` e `companyId` são structured metadata: filtre depois do seletor, por exemplo `{service_namespace="vera", service_name="vera-api"} | identifier="queue-consumer"`.

## O que existe hoje

Dashboards:

- **Saúde da aplicação**: RED por rota, latência, 5xx, readiness, banco, event loop e logs.
- **Filas**: idade do job mais antigo por fila, erros por `LOG_IDENTIFIER`, jobs abandonados (DLQ), heartbeat e atraso de comandos agendados.

Alertas:

| Arquivo | Regra | Severidade |
|---|---|---|
| `5xx.json` | 5xx acima de 1% por 5 min | critical |
| `sem-log.json` | nenhum log em 10 min (sem dado conta como alerta) | critical |
| `readiness.json` | readiness degradado por 5 min | critical |
| `dlq.json` | job abandonado após esgotar as tentativas | critical |
| `fila-parada.json` | job mais antigo em espera acima de 10 min | warning |
| `comando-ausente.json` | próximo disparo de comando agendado vencido há mais de 10 min | warning |

Métricas e logs de negócio (webhook, IA, lojas, WhatsApp, cobrança) nascem com os épicos que os instrumentam.

## Scripts

```bash
scripts/apply.sh <dev|prod>   # aplica a pasta vera (dashboards + alert rules)
scripts/drift.sh <dev|prod>   # compara a pasta vera da Grafana com o repo
scripts/pull.sh  <dev|prod>   # traz a pasta vera da Grafana para o repo (espelha: apaga o que sumiu)
```

Cada script lê `environments/<env>.env` (ou `<env>.env.example` se o primeiro não existir). Variáveis de ambiente de mesmo nome sobrepõem o arquivo.

## Autenticação e configuração

- `GRAFANA_URL`: sempre por variável de ambiente (nenhum arquivo versionado tem URL real).
- `GRAFANA_TOKEN` no ambiente, ou o arquivo apontado por `GRAFANA_TOKEN_FILE` (token de service account com permissão na pasta `vera`).
- Prod também precisa de `CF_ACCESS_CLIENT_ID` e `CF_ACCESS_CLIENT_SECRET` (service token do Cloudflare Access).
- Para rodar contra prod localmente: `cp environments/prod.env.example environments/prod.env` (ignorado pelo git), ajuste os nomes de datasource e exporte `GRAFANA_URL`.
- `DS_POSTGRES` (`vera-postgres`) é reservado para o datasource Postgres de leitura. Ele deve usar um usuário read-only escopado ao banco `vera`, nunca a bancos de outros produtos. Nenhum painel o usa ainda.

## CI

Tudo em `ubuntu-latest` e atrás de `vars.GRAFANA_ENABLED == 'true'`. Sem os secrets, os passos de aplicação são pulados sem erro.

- `apply.yml`: push em `main` aplica em dev (canário) e, só se o drift de dev ficar limpo, aplica em prod. Sem Grafana de dev (`GRAFANA_URL_DEV` vazia) o canário não roda e o push não toca prod: o dono aplica em prod conscientemente com `workflow_dispatch`.
- `drift.yml`: drift diário em dev e prod.
- Variáveis do repositório: `GRAFANA_ENABLED`, `GRAFANA_URL_DEV`, `GRAFANA_URL_PROD`, `GRAFANA_DS_PROMETHEUS_PROD`, `GRAFANA_DS_LOKI_PROD`, `GRAFANA_DS_TEMPO_PROD`.
- Secrets: `GRAFANA_TOKEN_DEV`, `GRAFANA_TOKEN_PROD`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`.

## Antes do primeiro uso

1. Criar a service account da Grafana com acesso à pasta `vera` e guardar o token como secret.
2. Garantir que a política raiz de notificação roteia `project=vera` (e `severity=critical`) para um contact point.
3. Confirmar que o `vera-api` envia OTLP para a stack (`OTEL_EXPORTER_OTLP_ENDPOINT`) antes de aplicar: regras antes da telemetria geram ruído de NoData.
4. Rodar `scripts/apply.sh <env>` e em seguida `scripts/drift.sh <env>`; deve ficar limpo.
