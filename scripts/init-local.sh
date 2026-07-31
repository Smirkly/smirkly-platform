#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_dir="${root_dir}/.local/auth"
secrets_dir="${local_dir}/secrets"
config_path="${local_dir}/config_vars.yaml"
template_path="${root_dir}/services/auth/config_vars.local.example.yaml"
private_key="${secrets_dir}/auth_jwt_private.pem"
public_key="${secrets_dir}/auth_jwt_public.pem"

command -v openssl >/dev/null 2>&1 || {
  printf 'openssl is required to generate local JWT keys\n' >&2
  exit 1
}

install -d -m 0700 "${secrets_dir}"

if [[ ! -f "${config_path}" ]]; then
  install -m 0600 "${template_path}" "${config_path}"
  printf 'created %s\n' "${config_path}"
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
