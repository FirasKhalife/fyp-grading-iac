# Plan-level assertions with a mocked AWS provider: no credentials, no network, nothing is created.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/mock"
    }
  }
}

mock_provider "random" {}

override_data {
  target = data.aws_ssm_parameter.ami
  values = {
    value = "ami-0123456789abcdef0"
  }
}

run "host_is_private_and_hardened" {
  command = plan

  assert {
    condition     = aws_instance.app.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be enforced."
  }

  assert {
    condition     = aws_instance.app.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Metadata hop limit must be 1 so containers cannot reach IMDS."
  }

  assert {
    condition     = aws_instance.app.root_block_device[0].encrypted == true
    error_message = "Root volume must be encrypted."
  }

  assert {
    condition     = aws_instance.app.associate_public_ip_address == false
    error_message = "The instance must not get a public IP."
  }

  assert {
    condition     = endswith(aws_iam_role_policy_attachment.ssm_core.policy_arn, "AmazonSSMManagedInstanceCore")
    error_message = "Access must go through SSM Session Manager (no SSH key pair is configured)."
  }
}

run "no_inbound_rules_and_https_only_egress" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_egress_rule.https.from_port == 443 && aws_vpc_security_group_egress_rule.https.to_port == 443
    error_message = "Only HTTPS egress is allowed."
  }

  assert {
    condition     = length(aws_security_group.app.ingress) == 0
    error_message = "The app security group must have no inbound rules."
  }
}

run "secrets_are_secure_strings" {
  command = plan

  assert {
    condition     = alltrue([for p in aws_ssm_parameter.secret : p.type == "SecureString"])
    error_message = "All secrets must be SecureString parameters."
  }

  assert {
    condition     = length(aws_ssm_parameter.secret) == 4
    error_message = "Expected four generated secrets."
  }

  assert {
    condition     = !strcontains(aws_instance.app.user_data, "password=")
    error_message = "user_data must not embed secret values."
  }
}

run "vpc_layout_default" {
  command = plan

  assert {
    condition     = length(module.vpc.private_subnet_ids) == 2
    error_message = "Default layout has two private subnets."
  }
}

run "rejects_small_instance" {
  command = plan

  variables {
    instance_type = "t3.micro"
  }

  expect_failures = [var.instance_type]
}

run "rejects_bad_environment_name" {
  command = plan

  variables {
    environment = "Prod!"
  }

  expect_failures = [var.environment]
}
