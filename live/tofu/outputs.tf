output "tunnel_id" {
  description = "The tunnel's ID (also shown in the dashboard)."
  value       = cloudflare_zero_trust_tunnel_cloudflared.assay.id
}

output "public_url" {
  description = "The demo's public URL. Ansible's assay_public_url must match it."
  value       = "https://${var.hostname}"
}

output "tunnel_token" {
  description = "The token cloudflared runs with (TUNNEL_TOKEN on the host). ../deploy.sh hands it to Ansible without printing it."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.assay.token
  sensitive   = true
}
