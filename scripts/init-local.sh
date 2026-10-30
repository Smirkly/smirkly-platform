#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
auth_local_dir="${root_dir}/.local/auth"
chat_local_dir="${root_dir}/.local/chat"
secrets_dir="${auth_local_dir}/secrets"
openbao_seed_dir="${root_dir}/.local/openbao/seeds"
config_path="${auth_local_dir}/config_vars.yaml"
template_path="${root_dir}/services/auth/config_vars.local.example.yaml"
chat_config_path="${chat_local_dir}/config_vars.yaml"
chat_template_path="${root_dir}/services/chat/config_vars.local.example.yaml"
private_key="${secrets_dir}/auth_jwt_private.pem"
public_key="${secrets_dir}/auth_jwt_public.pem"
openbao_postgres_password="${openbao_seed_dir}/postgres_password"
openbao_smtp_password="${openbao_seed_dir}/smtp_password"
openbao_refresh_token_pepper="${openbao_seed_dir}/refresh_token_pepper"

command -v openssl >/dev/null 2>&1 || {
  printf 'openssl is required to generate local JWT keys\n' >&2
  exit 1
}

install -d -m 0700 "${secrets_dir}" "${chat_local_dir}" \
  "${openbao_seed_dir}"

if [[ ! -f "${config_path}" ]]; then
  install -m 0600 "${template_path}" "${config_path}"
  printf 'created %s\n' "${config_path}"
fi

if [[ ! -f "${chat_config_path}" ]]; then
  install -m 0600 "${chat_template_path}" "${chat_config_path}"
  printf 'created %s\n' "${chat_config_path}"
fi

if [[ ! -f "${private_key}" ]]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${private_key}"
  chmod 0600 "${private_key}"
  printf 'created %s\n' "${private_key}"
fi

if [[ ! -f "${public_key}" ]]; then
  openssl pkey -in "${private_key}" -pubout -out "${public_key}"
  chmod 0644 "${public_key}"
  printf 'created %s\n' "${public_key}"
fi

if [[ ! -f "${openbao_postgres_password}" ]]; then
  printf '%s\n' 'smirkly_auth' >"${openbao_postgres_password}"
  chmod 0600 "${openbao_postgres_password}"
  printf 'created %s\n' "${openbao_postgres_password}"
fi

if [[ ! -f "${openbao_smtp_password}" ]]; then
  printf '%s\n' 'smirkly-local' >"${openbao_smtp_password}"
  chmod 0600 "${openbao_smtp_password}"
  printf 'created %s\n' "${openbao_smtp_password}"
fi

if [[ ! -f "${openbao_refresh_token_pepper}" ]]; then
  openssl rand -hex 32 >"${openbao_refresh_token_pepper}"
  chmod 0600 "${openbao_refresh_token_pepper}"
  printf 'created %s\n' "${openbao_refresh_token_pepper}"
fi
