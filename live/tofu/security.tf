# Free-plan protections. A zone has one entry-point ruleset per phase: if the dashboard already made one for a phase
# below, `tofu apply` fails with "already exists". Import it first (../README.md, "Troubleshooting").

# Sign-in attempts. Brute-force lockout is off in the realm (it would lock the shared personas out for everyone), and
# each password check costs Keycloak real CPU, so Cloudflare limits how fast one address may call the token endpoint.
# The free plan allows one rate-limiting rule, a 10 s period and a 10 s block, counted per IP and data centre.
resource "cloudflare_ruleset" "rate_limit" {
  zone_id     = local.zone_id
  name        = "Assay rate limits"
  description = "Managed by fyp-grading-iac/live/tofu"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "assay_token_endpoint"
      description = "Assay: Keycloak token endpoint, per IP"
      # The free plan matches on the path only (no host field), so this also covers the path on other hostnames.
      expression = "(http.request.uri.path eq \"/realms/assay/protocol/openid-connect/token\")"
      action     = "block"
      enabled    = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 10
        requests_per_period = var.token_rate_limit
        mitigation_timeout  = 10
      }
    },
  ]
}

# HSTS on the demo hostname only, as a response header rule, so the zone's other hostnames are not affected.
resource "cloudflare_ruleset" "response_headers" {
  zone_id     = local.zone_id
  name        = "Assay response headers"
  description = "Managed by fyp-grading-iac/live/tofu"
  kind        = "zone"
  phase       = "http_response_headers_transform"

  rules = [
    {
      ref         = "assay_hsts"
      description = "Assay: HSTS"
      expression  = "(http.host eq \"${var.hostname}\")"
      action      = "rewrite"
      enabled     = true
      action_parameters = {
        headers = {
          "Strict-Transport-Security" = {
            operation = "set"
            value     = "max-age=${var.hsts_max_age}"
          }
        }
      }
    },
  ]
}

# Zone-wide TLS settings. Brotli isn't here: Cloudflare now compresses with Brotli on every plan and retired the
# setting. The Free Managed Ruleset (WAF) is on by default for free zones and stays as Cloudflare manages it.
locals {
  zone_settings = var.manage_zone_settings ? {
    always_use_https         = "on"
    min_tls_version          = "1.2"
    tls_1_3                  = "on"
    automatic_https_rewrites = "on"
  } : {}
}

resource "cloudflare_zone_setting" "this" {
  for_each = local.zone_settings

  zone_id    = local.zone_id
  setting_id = each.key
  value      = each.value
}
