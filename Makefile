SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help init up up-foundation up-observability up-secrets \
	health-foundation down clean logs ps config validate

help:
	@printf '%s\n' \
	  'make init              Generate ignored local service config, keys, and secret seeds' \
	  'make up                Start auth, chat, and their dependencies' \
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
	docker compose --env-file .env.example --profile observability --profile secrets config --quiet
	jq empty observability/grafana/dashboards/smirkly-auth.json
	docker run --rm --entrypoint promtool \
	  --volume "$(CURDIR)/observability/prometheus:/etc/prometheus:ro" \
	  prom/prometheus:v3.13.2@sha256:508729e0e2d18e11fd742a5a5ca70e557b940a93948c3c95fd0123a6fd538b69 \
	  check config /etc/prometheus/prometheus.yml
