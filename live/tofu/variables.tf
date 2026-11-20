variable "cloudflare_account_id" {
  description = "Cloudflare account ID (TF_VAR_cloudflare_account_id). Not a secret, but kept out of the public repo."
  type        = string
  nullable    = false
}

variable "state_passphrase" {
  description = "Passphrase for OpenTofu state and plan encryption (TF_VAR_state_passphrase), at least 16 characters."
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters."
  }
}

variable "zone_name" {
  description = "The Cloudflare zone the demo lives in."
  type        = string
  default     = "firaskhalife.dev"
}

variable "hostname" {
  description = "The demo's public hostname. It must be in zone_name and match assay_public_url in Ansible."
  type        = string
  default     = "assay.firaskhalife.dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.hostname))
    error_message = "hostname must be a bare host name, e.g. assay.example.dev (no scheme, no path)."
  }
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel, as shown in the dashboard."
  type        = string
  default     = "assay-netcup"
}

variable "origin_service" {
  description = "Where cloudflared sends the hostname's traffic. cloudflared runs in the compose stack's tunnel profile, next to the edge."
  type        = string
  default     = "http://edge:8080"
}

variable "token_rate_limit" {
  description = "Requests per 10 s one IP may send to Keycloak's token endpoint before a 10 s block (the free plan fixes both at 10 s)."
  type        = number
  default     = 20

  validation {
    condition     = var.token_rate_limit >= 5
    error_message = "token_rate_limit below 5 would block ordinary sign-ins."
  }
}

variable "manage_zone_settings" {
  description = "Manage the zone-wide TLS settings (always HTTPS, min TLS 1.2, TLS 1.3, automatic HTTPS rewrites). They apply to every hostname in the zone, not only the demo."
  type        = bool
  default     = true
}

variable "hsts_max_age" {
  description = "HSTS max-age in seconds, for the demo hostname only (no includeSubDomains, no preload)."
  type        = number
  default     = 31536000
}
