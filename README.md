# smirkly-platform

Local orchestration and observability for Smirkly services.

This repository owns the developer stack and service integration configuration. Application code stays in service repositories such as `smirkly-auth`; PostgreSQL data and generated secrets stay outside Git.

## Repository layout

Keep service repositories next to this one:

```text
smirkly/
|-- smirkly-auth/
`-- smirkly-platform/
```

The default `SMIRKLY_AUTH_CONTEXT=../smirkly-auth` assumes this layout. Override it in `.env` when needed.

## Prerequisites

- Docker Desktop with Compose v2
- OpenSSL
- jq
- the `smirkly-auth` repository checked out on a revision that exposes Prometheus metrics on its private monitor listener

## Start the stack

```bash
cp .env.example .env
make init
make up-observability
```

The first build compiles `smirkly-auth` and can take several minutes. The stack then exposes only loopback-bound developer endpoints:

| Component | URL |
|---|---|
| Auth API | http://127.0.0.1:8080 |
| Mailpit | http://127.0.0.1:8025 |
| Prometheus | http://127.0.0.1:9090 |
| Grafana | http://127.0.0.1:3000 |
| PostgreSQL | `127.0.0.1:5432` |

Grafana is provisioned with Prometheus and the **Smirkly Auth** dashboard. Anonymous access is read-only and intended only for this loopback-bound local stack.

Stop any standalone auth process or service Compose stack first if it already occupies ports `5432` or `8080`. The auth devcontainer remains the canonical environment for service development and tests; this repository is the integration environment for running several services together.

Use `make up` when observability is not needed. Run `make down` to stop containers while preserving data, or `make clean` to also delete local volumes and generated development secrets.

## Local secrets

`make init` creates `.local/auth/config_vars.yaml` plus an RSA key pair under `.local/auth/secrets`. The whole `.local` directory is ignored. Values in the tracked example are local-only defaults and must never be reused for a deployed environment.

Production credentials belong in a secret manager and production deployment configuration belongs in a later deployment-specific layer. This Compose file is deliberately a developer integration stack, not a production manifest.

## Validation

```bash
make validate
```

CI validates shell syntax, Compose interpolation, Prometheus configuration and rules, and Grafana dashboard JSON. Runtime validation still requires Docker:

```bash
make up-observability
docker compose ps
curl --fail http://127.0.0.1:9090/-/ready
curl --fail 'http://127.0.0.1:9090/api/v1/targets?state=active'
```

The auth monitor listener on port `8081` is not published to the host. Prometheus reaches it through the private Compose network.
