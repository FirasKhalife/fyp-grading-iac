# CDK version (TypeScript)

The same AWS design as [`../terraform`](../terraform), written with AWS CDK v2. **Never deployed.** There is no AWS account behind it; synth and tests run fully offline.

## What it builds

One stack, `FypGradingDemo` (`lib/fyp-grading-stack.ts`):

- VPC `10.20.0.0/16`, two AZs, public and private `/20` subnets, one NAT gateway, locked-down default security group, flow logs to a KMS-encrypted log group.
- One `t3.xlarge` in a private subnet: Amazon Linux 2023 AMI resolved from the public SSM parameter, IMDSv2 required, encrypted gp3 root volume (KMS), detailed monitoring, termination protection, no public IP.
- Security group with no inbound rules and HTTPS-only egress. Access is by SSM Session Manager; there is no key pair.
- Four generated passwords in Secrets Manager, encrypted with a customer-managed KMS key (rotation on). The instance role can read only those four. The boot script (`lib/user-data.ts`) embeds secret ARNs, never values.

Differences from the Terraform version: secrets are in Secrets Manager (CloudFormation cannot create SSM `SecureString` parameters), and CloudFormation state is managed by AWS, so there is no S3 state bucket to bootstrap.

## Checks

```bash
npm ci
npm run build    # tsc type check
npm run lint     # eslint
npm test         # jest: 9 template assertions + the cdk-nag AwsSolutions rule pack
npm run synth    # cdk synth, no credentials needed
npm run check    # all of the above
```

The app is deliberately environment-agnostic (no account or region in code), so synth makes no AWS calls and needs no `cdk.context.json`. `cdk-nag` runs the AwsSolutions rules during synth and in the tests; the only suppressions are documented in the stack (the AWS-managed SSM policy and secret rotation, which is overkill for a demo).

`cdk deploy` and `cdk bootstrap` are intentionally never run. If you ever do deploy it, it costs about $172 a month, see the root README.

## Versions

Pinned in `package.json`: `aws-cdk-lib` 2.277.0, the `aws-cdk` CLI 2.1148.1, `cdk-nag` 2.38.2 (the 3.x line has a different API). Dependabot or Renovate would be the way to keep them current.
