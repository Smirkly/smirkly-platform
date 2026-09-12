# smirkly-platform

Local orchestration and observability for Smirkly services.

This repository owns the developer stack and service integration configuration. Application code stays in service repositories such as `smirkly-auth` and `smirkly-chat`; PostgreSQL data and generated secrets stay outside Git.

## Repository layout

Keep service repositories next to this one:

```text
smirkly/
|-- smirkly-auth/
|-- smirkly-chat/
`-- smirkly-platform/
```

The default service build contexts assume this layout. Override them in `.env` when needed.

The pinned userver v3.0 image is currently `amd64`-only, so the service containers explicitly use `linux/amd64`. Docker Desktop runs them through emulation on Apple Silicon; builds there are expected to be slower.

## Prerequisites

- Docker Desktop with Compose v2
- OpenSSL
- jq
- the `smirkly-auth` repository checked out on a revision that exposes Prometheus metrics on its private monitor listener
- the `smirkly-chat` repository checked out next to this repository

## Start the stack

```bash
cp .env.example .env
make init
make up-observability
```

The first build compiles `smirkly-auth` and `smirkly-chat` and can take several minutes. The stack then exposes only loopback-bound developer endpoints:

| Component | URL |
|---|---|
| Auth API | http://127.0.0.1:18080 |
| Chat API | http://127.0.0.1:18081 |
| Mailpit | http://127.0.0.1:8025 |
| Prometheus | http://127.0.0.1:9090 |
| Grafana | http://127.0.0.1:3000 |
| Auth PostgreSQL | `127.0.0.1:55432` |
| Chat PostgreSQL | `127.0.0.1:55433` |

Grafana is provisioned with Prometheus and the **Smirkly Auth** dashboard. Anonymous access is read-only and intended only for this loopback-bound local stack.

The nonstandard host ports deliberately avoid defaults commonly used by the service devcontainers and CLion-run processes. Internal service addresses remain private to the Compose network. Override the host ports in `.env` when needed.

Use `make up` when observability is not needed. Run `make down` to stop containers while preserving data, or `make clean` to also delete local volumes and generated development secrets.

## Local secrets

`make init` creates local config for both services plus an RSA key pair under `.local/auth/secrets`. The whole `.local` directory is ignored. Values in the tracked examples are local-only defaults and must never be reused for a deployed environment.

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
