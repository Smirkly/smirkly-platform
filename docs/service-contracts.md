# Local service contracts

This document defines the stable boundaries between `smirkly-platform` and the
application repositories. Host ports are developer conveniences and may be
overridden in `.env`; container DNS names and internal ports are the service
contract.

## Compose profiles

| Profile | Purpose |
|---|---|
| no profile | PostgreSQL, Mailpit, migrations, and application services |
| `observability` | Prometheus and Grafana |
| `secrets` | Local OpenBao, bootstrap job, and the auth OpenBao Agent |

`make up-foundation` starts Mailpit, observability, and secrets without building
or starting an application service. OpenBao runs in ephemeral development mode;
it is not a deployment manifest.

## Network endpoints

| Component | Compose address | Host address | Exposure |
|---|---|---|---|
| Auth API | `smirkly-auth:8080` | `127.0.0.1:18080` | loopback |
| Auth monitor | `smirkly-auth:8081` | not published | private |
| Auth PostgreSQL | `smirkly-postgres:5432` | `127.0.0.1:55432` | loopback |
| Mailpit SMTP | `mailpit:1025` | `127.0.0.1:1025` | loopback |
| Mailpit HTTP/API | `mailpit:8025` | `127.0.0.1:8025` | loopback |
| Prometheus | `prometheus:9090` | `127.0.0.1:9090` | loopback |
| Grafana | `grafana:3000` | `127.0.0.1:3000` | loopback |
| OpenBao API | `openbao:8200` | `127.0.0.1:8200` | loopback |

The planned chat contract reserves `smirkly-chat:8080` for its API and
`smirkly-chat:8082` for its monitor listener. Its Compose integration remains
owned by the separate chat integration change.

## Monitor endpoints

| Service | Listener | Metrics path |
|---|---|---|
| `smirkly-auth` | `smirkly-auth:8081` | `/service/monitor` |
| `smirkly-chat` | `smirkly-chat:8082` | `/service/monitor` |

Monitor listeners stay on the private observability network. Prometheus is the
only component expected to scrape them.

## Secret delivery

The local OpenBao bootstrap enables KV v2 at `secret/`, creates the
`smirkly-auth` AppRole and grants it read-only access to
`secret/data/smirkly-auth`. OpenBao Agent renders the following files:

| File | Consumer setting |
|---|---|
| `/run/secrets/smirkly-auth/postgres_password` | PostgreSQL credentials |
| `/run/secrets/smirkly-auth/jwt_private_key.pem` | JWT signing key |
| `/run/secrets/smirkly-auth/smtp_password` | SMTP credential |
| `/run/secrets/smirkly-auth/refresh_token_pepper` | refresh-token hashing pepper |

Application containers do not mount these files yet. The auth integration must
add explicit file-based configuration before replacing its existing local
configuration. A missing or empty secret must make the application fail during
startup rather than silently use a default.

Seed material is generated under ignored `.local/openbao/seeds`. AppRole
credentials and rendered files live in Docker volumes and must never be
committed. Production must replace dev mode, the fixed root token, unlimited
SecretID lifetime, and plaintext local HTTP with an operated OpenBao deployment.
