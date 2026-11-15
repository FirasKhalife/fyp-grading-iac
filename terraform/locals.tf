locals {
  name = "fyp-grading-${var.environment}"

  # Secrets live in SSM Parameter Store under this path; the instance role may read only this path.
  ssm_path = "/fyp-grading/${var.environment}"

  secret_names = toset([
    "postgres_password",
    "mongo_password",
    "rabbitmq_password",
    "keycloak_admin_password",
  ])
}
