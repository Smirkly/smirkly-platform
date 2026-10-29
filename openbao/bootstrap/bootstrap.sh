#!/bin/sh
set -eu

if ! bao secrets list -format=json | grep -q '"secret/"'; then
  bao secrets enable -path=secret kv-v2
fi

if ! bao auth list -format=json | grep -q '"approle/"'; then
  bao auth enable approle
fi

bao policy write smirkly-auth /openbao/policies/smirkly-auth.hcl

bao write auth/approle/role/smirkly-auth \
  token_policies=smirkly-auth \
  token_num_uses=0 \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_num_uses=0 \
  secret_id_ttl=0

bao kv put secret/smirkly-auth \
  postgres_password="$(cat /openbao/seeds/postgres_password)" \
  smtp_password="$(cat /openbao/seeds/smtp_password)" \
  refresh_token_pepper="$(cat /openbao/seeds/refresh_token_pepper)" \
  jwt_private_key="$(cat /openbao/auth-secrets/auth_jwt_private.pem)"

rm -f /openbao/approle/role-id /openbao/approle/secret-id

bao read -field=role_id auth/approle/role/smirkly-auth/role-id \
  >/openbao/approle/role-id
bao write -field=secret_id -f auth/approle/role/smirkly-auth/secret-id \
  >/openbao/approle/secret-id
chmod 0444 /openbao/approle/role-id /openbao/approle/secret-id
