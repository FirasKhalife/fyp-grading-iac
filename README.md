# fyp-grading infrastructure as code (AWS reference)

Two parallel descriptions of the same AWS deployment of the FYP grading platform, one in OpenTofu/Terraform and one in AWS CDK (TypeScript).

> **Nothing here has ever been applied or deployed.** There is no AWS account behind this repo, CI has no AWS credentials, and every check runs offline. The code is validated, linted, security-scanned, synthesized and unit-tested, but it has never created a real resource. The live demo runs somewhere else, see [Why the live demo is not on AWS](#why-the-live-demo-is-not-on-aws).

| Folder | What | Start here |
|---|---|---|
| [`terraform/`](terraform/) | OpenTofu/Terraform: VPC module, one private instance, SSM, KMS, SSM Parameter Store secrets, S3 state | [terraform/README.md](terraform/README.md) |
| [`cdk/`](cdk/) | AWS CDK v2 in TypeScript: the same design, plus cdk-nag security rules | [cdk/README.md](cdk/README.md) |

## The design, in one picture

```
                 Internet
                    |
            [Internet Gateway]
                    |
   public subnets (2 AZs)  -- NAT gateway (one, shared)
                    |
   private subnets (2 AZs)
        |
   one EC2 instance (t3.xlarge, Amazon Linux 2023)
        - Docker Compose runs the whole platform
          (7 Spring Boot services, Keycloak, Postgres, Mongo, RabbitMQ, Redis)
        - no public IP, no inbound rules, no SSH key
        - reached only through SSM Session Manager
        - IMDSv2 only, encrypted volumes, generated secrets
```

Both versions build exactly this. One difference: CloudFormation cannot create SSM `SecureString` parameters, so the CDK version keeps secrets in Secrets Manager (four secrets, about $1.60 a month) where Terraform uses SSM Parameter Store (free tier).

## Estimated monthly cost (if either were applied)

Rough on-demand `us-east-1` list prices, 730 hours a month. These are my estimates, not an `infracost` run.

| Item | Terraform $/month | CDK $/month |
|---|---|---|
| `t3.xlarge` instance | ~121 | ~121 |
| NAT gateway plus ~50 GB traffic | ~35 | ~35 |
| NAT public IPv4 address | ~4 | ~4 |
| 60 GB gp3 volume | ~5 | ~5 |
| Monitoring, KMS key, flow logs | ~5 | ~5 |
| Secrets | ~0 (SSM Parameter Store) | ~2 (Secrets Manager) |
| **Total** | **~$170** | **~$172** |

A public ALB would add about $18 plus traffic; it is deliberately not included.

## Why the live demo is not on AWS

A demo that a recruiter clicks a few times a month does not need about $170 a month of infrastructure. The live demo runs on a single Netcup VPS behind a Cloudflare Tunnel: a flat monthly price, no NAT or load balancer charges, and no open inbound ports (the tunnel dials out). It runs the same Docker Compose stack. This repo answers "how would you run it on AWS?", the VPS answers "where can I click it?". (I have not put a Netcup price here because it has not been checked against their current price list.)

## Running the checks locally

Everything below needs no AWS account. Tools: OpenTofu >= 1.9, tflint, checkov (Python) and Node 20+. Versions are pinned in [`.tool-versions`](.tool-versions) (read by `mise` or `asdf`).

```bash
# Terraform
cd terraform
tofu fmt -check -recursive
tofu init -backend=false && tofu validate
(cd bootstrap && tofu init -backend=false && tofu validate)
tofu test                          # mocked AWS provider
tflint --init && tflint --recursive
checkov -d . --framework terraform

# CDK
cd cdk
npm ci
npm run check                      # tsc, eslint, jest (incl. cdk-nag), cdk synth
```

There is no official npm package for OpenTofu or Terraform, so those tools are installed separately (or through `mise`). CDK needs only `npm ci`, because the CDK CLI, the linter and the test runner are all npm packages.

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the same two sets of checks on every pull request.
