auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path                   = "/openbao/approle/role-id"
      secret_id_file_path                 = "/openbao/approle/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }
}

template_config {
  exit_on_retry_failure = true
}

template {
  source      = "/openbao/templates/postgres_password.ctmpl"
  destination = "/run/secrets/smirkly-auth/postgres_password"
  perms       = "0400"
}

template {
  source      = "/openbao/templates/jwt_private_key.ctmpl"
  destination = "/run/secrets/smirkly-auth/jwt_private_key.pem"
  perms       = "0400"
}

template {
  source      = "/openbao/templates/smtp_password.ctmpl"
  destination = "/run/secrets/smirkly-auth/smtp_password"
  perms       = "0400"
}

template {
  source      = "/openbao/templates/refresh_token_pepper.ctmpl"
  destination = "/run/secrets/smirkly-auth/refresh_token_pepper"
  perms       = "0400"
}
