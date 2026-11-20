data "cloudflare_zone" "this" {
  filter = {
    name = var.zone_name
  }
}

locals {
  zone_id = data.cloudflare_zone.this.zone_id
}

# A remotely managed tunnel: its ingress lives in Cloudflare (below), so cloudflared on the host needs only the
# token, and the host opens no inbound port. Cloudflare generates the tunnel secret.
resource "cloudflare_zero_trust_tunnel_cloudflared" "assay" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "assay" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.assay.id

  config = {
    ingress = [
      {
        hostname = var.hostname
        service  = var.origin_service
      },
      # Anything else that reaches the tunnel (another hostname pointed at it) gets a plain 404.
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "assay" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.assay.id
}

resource "cloudflare_dns_record" "assay" {
  zone_id = local.zone_id
  name    = var.hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.assay.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # automatic, required for proxied records
  comment = "Assay demo through its Cloudflare Tunnel (fyp-grading-iac/live/tofu)"
}
