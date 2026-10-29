# smirkly-platform

Local orchestration, secret delivery, and observability for Smirkly services.

This repository owns the developer stack and service integration configuration. Application code stays in service repositories such as `smirkly-auth`; PostgreSQL data, generated keys, and secret seeds stay outside Git.

## Repository layout

Keep service repositories next to this one:

```text
smirkly/
|-- smirkly-auth/
`-- smirkly-platform/
```

The default `SMIRKLY_AUTH_CONTEXT=../smirkly-auth` assumes this layout. Override it in `.env` when needed.

The pinned userver v3.0 image is currently `amd64`-only, so the auth container explicitly uses `linux/amd64`. Docker Desktop runs it through emulation on Apple Silicon; builds there are expected to be slower.

## Prerequisites

- Docker Desktop with Compose v2
- OpenSSL
- curl
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
| Auth API | http://127.0.0.1:18080 |
| Mailpit UI/API | http://127.0.0.1:8025 |
| Mailpit SMTP | `127.0.0.1:1025` |
| Prometheus | http://127.0.0.1:9090 |
| Grafana | http://127.0.0.1:3000 |
| PostgreSQL | `127.0.0.1:55432` |

Grafana is provisioned with Prometheus and the **Smirkly Auth** dashboard. Anonymous access is read-only and intended only for this loopback-bound local stack.

The nonstandard host ports deliberately avoid the `5432` and `8080` defaults commonly used by the auth devcontainer and a CLion-run service. Internal service addresses remain `smirkly-postgres:5432` and `smirkly-auth:8080`. Override the host ports in `.env` when needed.

Use `make up` when observability is not needed. Run `make down` to stop containers while preserving data, or `make clean` to also delete local volumes and generated development secrets.

## Infrastructure foundation

The infrastructure foundation can run without building or starting auth:

```bash
make up-foundation
make health-foundation
```

This starts Mailpit, Prometheus, Grafana, and an in-memory OpenBao development server. The OpenBao bootstrap configures an auth-specific AppRole; OpenBao Agent then renders the file contract described in [`docs/service-contracts.md`](docs/service-contracts.md). Auth does not consume those files yet.

## Local secrets

`make init` creates `.local/auth/config_vars.yaml`, an RSA key pair under `.local/auth/secrets`, and OpenBao seed files under `.local/openbao/seeds`. The whole `.local` directory is ignored. Values in the tracked examples are local-only defaults and must never be reused for a deployed environment.

Production credentials belong in a secret manager and production deployment configuration belongs in a later deployment-specific layer. This Compose file is deliberately a developer integration stack, not a production manifest.

The `secrets` profile intentionally uses OpenBao dev mode with a fixed local root token. Its state is recreated by `make up-secrets`; it must never be exposed or used as a production OpenBao configuration.

## Validation

```bash
make validate
```

CI validates shell syntax, Compose interpolation, Prometheus configuration and rules, and Grafana dashboard JSON. Runtime validation requires Docker:

```bash
make up-foundation
make health-foundation
```

The auth monitor listener on port `8081` is not published to the host. Prometheus reaches it through the private Compose network.
