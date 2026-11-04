SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

-include .env

.PHONY: help init up up-auth-e2e test-auth-e2e up-foundation \
	up-observability up-secrets health-foundation down clean logs ps config \
	validate

PYTHON ?= python3
SMIRKLY_AUTH_PORT ?= 18080
MAILPIT_HTTP_PORT ?= 8025
AUTH_BASE_URL ?= http://127.0.0.1:$(SMIRKLY_AUTH_PORT)
MAILPIT_BASE_URL ?= http://127.0.0.1:$(MAILPIT_HTTP_PORT)

export SMIRKLY_AUTH_PORT MAILPIT_HTTP_PORT

help:
	@printf '%s\n' \
	  'make init              Generate ignored local service config, keys, and secret seeds' \
	  'make up                Start auth, chat, and their dependencies' \
	  'make up-auth-e2e       Start auth, PostgreSQL, migrations, and Mailpit' \
	  'make test-auth-e2e     Start dependencies and run the auth lifecycle E2E test' \
	  'make up-foundation     Start Mailpit, observability, and local OpenBao' \
	  'make up-observability  Start the complete application and observability stack' \
	  'make up-secrets        Recreate local OpenBao, bootstrap, and Agent' \
	  'make health-foundation Check foundation endpoints and rendered secrets' \
	  'make down              Stop the stack and preserve volumes' \
	  'make clean             Stop the stack and delete local data' \
	  'make logs              Follow service logs' \
	  'make validate          Validate all tracked configuration'

init:
	./scripts/init-local.sh

up: init
	docker compose up --build --detach

up-auth-e2e: init
	docker compose up --build --detach smirkly-auth

test-auth-e2e: up-auth-e2e
	AUTH_BASE_URL="$(AUTH_BASE_URL)" \
	MAILPIT_BASE_URL="$(MAILPIT_BASE_URL)" \
	$(PYTHON) -m unittest -v tests.e2e.test_auth_lifecycle

up-foundation: init
	docker compose --profile observability up --detach mailpit prometheus grafana
	docker compose --profile secrets up --detach --force-recreate \
	  openbao openbao-bootstrap openbao-agent-auth

up-observability: init
	docker compose --profile observability up --build --detach

up-secrets: init
	docker compose --profile secrets up --detach --force-recreate \
	  openbao openbao-bootstrap openbao-agent-auth

health-foundation:
	./scripts/check-foundation.sh

down:
	docker compose --profile observability --profile secrets down --remove-orphans

clean:
	docker compose --profile observability --profile secrets down --volumes --remove-orphans
	rm -rf .local

logs:
	docker compose --profile observability --profile secrets logs --follow

ps:
	docker compose --profile observability --profile secrets ps

config:
	docker compose --profile observability --profile secrets config

validate:
	bash -n scripts/init-local.sh
	bash -n scripts/check-foundation.sh
	sh -n openbao/bootstrap/bootstrap.sh
	$(PYTHON) -m compileall -q tests
	docker compose --env-file .env.example --profile observability --profile secrets config --quiet
	jq empty observability/grafana/dashboards/smirkly-auth.json
	docker run --rm --entrypoint promtool \
	  --volume "$(CURDIR)/observability/prometheus:/etc/prometheus:ro" \
	  prom/prometheus:v3.13.2@sha256:508729e0e2d18e11fd742a5a5ca70e557b940a93948c3c95fd0123a6fd538b69 \
	  check config /etc/prometheus/prometheus.yml
