SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help init up up-observability down clean logs ps config validate

help:
	@printf '%s\n' \
	  'make init              Generate ignored local auth config and keys' \
	  'make up                Start PostgreSQL, Mailpit, and auth' \
	  'make up-observability  Start the complete stack' \
	  'make down              Stop the stack and preserve volumes' \
	  'make clean             Stop the stack and delete local data' \
	  'make logs              Follow service logs' \
	  'make validate          Validate all tracked configuration'

init:
	./scripts/init-local.sh

up: init
	docker compose up --build --detach

up-observability: init
	docker compose --profile observability up --build --detach

down:
	docker compose --profile observability down --remove-orphans

clean:
	docker compose --profile observability down --volumes --remove-orphans
	rm -rf .local

logs:
	docker compose --profile observability logs --follow

ps:
	docker compose --profile observability ps

config:
	docker compose --profile observability config

validate:
	bash -n scripts/init-local.sh
	docker compose --env-file .env.example --profile observability config --quiet
	jq empty observability/grafana/dashboards/smirkly-auth.json
	docker run --rm --entrypoint promtool \
	  --volume "$(CURDIR)/observability/prometheus:/etc/prometheus:ro" \
	  prom/prometheus:v3.13.2@sha256:508729e0e2d18e11fd742a5a5ca70e557b940a93948c3c95fd0123a6fd538b69 \
	  check config /etc/prometheus/prometheus.yml
