#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${root_dir}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${root_dir}/.env"
  set +a
fi

check_url() {
  local name="$1"
  local url="$2"

  printf 'checking %-12s %s\n' "${name}" "${url}"
  curl --fail --silent --show-error --max-time 5 "${url}" >/dev/null
}

check_url mailpit "http://127.0.0.1:${MAILPIT_HTTP_PORT:-8025}/readyz"
check_url prometheus "http://127.0.0.1:${PROMETHEUS_PORT:-9090}/-/ready"
check_url grafana "http://127.0.0.1:${GRAFANA_PORT:-3000}/api/health"
check_url openbao "http://127.0.0.1:${OPENBAO_PORT:-8200}/v1/sys/health"

docker compose --profile secrets exec -T openbao-agent-auth sh -ec '
  for path in \
    /run/secrets/smirkly-auth/postgres_password \
    /run/secrets/smirkly-auth/jwt_private_key.pem \
    /run/secrets/smirkly-auth/smtp_password \
    /run/secrets/smirkly-auth/refresh_token_pepper; do
    test -s "${path}"
  done
'

printf 'foundation is healthy\n'
