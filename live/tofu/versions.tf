terraform {
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.29"
    }
  }

  # The state holds the tunnel's secret, so it stays on this machine (git-ignored) and is encrypted at rest. The
  # passphrase comes from TF_VAR_state_passphrase (in ~/.config/assay/cloudflare.env, see ../README.md). Losing it
  # means losing the state, not the tunnel: see "Lost the state?" in ../README.md.
  encryption {
    key_provider "pbkdf2" "local" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "local" {
      keys = key_provider.pbkdf2.local
    }
    state {
      method   = method.aes_gcm.local
      enforced = true
    }
    plan {
      method   = method.aes_gcm.local
      enforced = true
    }
  }
}

# The API token comes from CLOUDFLARE_API_TOKEN, which the provider reads itself. Never put it in a .tf file.
provider "cloudflare" {}
