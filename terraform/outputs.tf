output "instance_id" {
  description = "Instance ID, used as the Session Manager target."
  value       = aws_instance.app.id
}

output "ssm_session_command" {
  description = "Open a shell on the host (no SSH, no public IP)."
  value       = "aws ssm start-session --target ${aws_instance.app.id} --region ${var.region}"
}

output "ssm_port_forward_command" {
  description = "Forward the API gateway (8080) to localhost:8080."
  value       = "aws ssm start-session --target ${aws_instance.app.id} --region ${var.region} --document-name AWS-StartPortForwardingSession --parameters portNumber=8080,localPortNumber=8080"
}

output "secret_parameter_names" {
  description = "SSM parameter names holding the generated secrets (names only, never values)."
  value       = [for p in aws_ssm_parameter.secret : p.name]
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}
