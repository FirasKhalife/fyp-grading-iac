import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as kms from "aws-cdk-lib/aws-kms";
import * as logs from "aws-cdk-lib/aws-logs";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import { NagSuppressions } from "cdk-nag";
import { Construct } from "constructs";
import { renderUserData } from "./user-data";

const SECRET_NAMES = ["postgres_password", "mongo_password", "rabbitmq_password", "keycloak_admin_password"] as const;
type SecretName = (typeof SECRET_NAMES)[number];

export interface FypGradingStackProps extends cdk.StackProps {
  /** Needs about 10-12 GiB for the whole Compose stack; 16 GiB leaves headroom. */
  readonly instanceType?: ec2.InstanceType;
  readonly rootVolumeSizeGb?: number;
  readonly vpcCidr?: string;
  readonly composeRepoUrl?: string;
}

/**
 * Same design as ../terraform: one private instance reached through SSM Session Manager,
 * IMDSv2 only, encrypted volumes, generated secrets, and a VPC with one NAT gateway.
 *
 * One deliberate difference: CloudFormation cannot create SSM SecureString parameters, so
 * secrets live in AWS Secrets Manager (four generated secrets) instead.
 */
export class FypGradingStack extends cdk.Stack {
  public readonly instance: ec2.Instance;
  public readonly secrets: Record<SecretName, secretsmanager.Secret>;

  constructor(scope: Construct, id: string, props: FypGradingStackProps = {}) {
    super(scope, id, props);

    const instanceType = props.instanceType ?? ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.XLARGE);
    const composeRepoUrl = props.composeRepoUrl ?? "https://github.com/FirasKhalife/fyp-grading-docker-compose.git";

    // ------------------------------------------------------------ encryption key
    const key = new kms.Key(this, "Key", {
      description: "fyp-grading: EBS volumes, secrets, flow logs",
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pendingWindow: cdk.Duration.days(7),
    });
    key.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: "AllowCloudWatchLogs",
        principals: [new iam.ServicePrincipal(`logs.${this.region}.amazonaws.com`)],
        actions: ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"],
        resources: ["*"],
      }),
    );

    // ------------------------------------------------------------ network
    const flowLogGroup = new logs.LogGroup(this, "FlowLogs", {
      retention: logs.RetentionDays.ONE_YEAR,
      encryptionKey: key,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const vpc = new ec2.Vpc(this, "Vpc", {
      ipAddresses: ec2.IpAddresses.cidr(props.vpcCidr ?? "10.20.0.0/16"),
      maxAzs: 2,
      natGateways: 1, // one shared NAT: cheapest, accepted single point of failure for a demo
      restrictDefaultSecurityGroup: true,
      subnetConfiguration: [
        { name: "public", subnetType: ec2.SubnetType.PUBLIC, cidrMask: 20, mapPublicIpOnLaunch: false },
        { name: "private", subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, cidrMask: 20 },
      ],
      flowLogs: {
        all: {
          destination: ec2.FlowLogDestination.toCloudWatchLogs(flowLogGroup),
          trafficType: ec2.FlowLogTrafficType.ALL,
        },
      },
    });

    // ------------------------------------------------------------ secrets
    this.secrets = Object.fromEntries(
      SECRET_NAMES.map((name) => [
        name,
        new secretsmanager.Secret(this, `Secret-${name}`, {
          description: `Generated ${name}`,
          encryptionKey: key,
          generateSecretString: { excludePunctuation: true, passwordLength: 32 }, // safe in JDBC / Mongo URIs
        }),
      ]),
    ) as Record<SecretName, secretsmanager.Secret>;

    // ------------------------------------------------------------ the instance
    const securityGroup = new ec2.SecurityGroup(this, "AppSg", {
      vpc,
      description: "App host: no inbound at all, outbound HTTPS only",
      allowAllOutbound: false,
    });
    securityGroup.addEgressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(443), "HTTPS out: SSM, repos, registries, Git");

    const role = new iam.Role(this, "AppRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      managedPolicies: [iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore")],
    });
    // The instance may read only its own secrets.
    Object.values(this.secrets).forEach((s) => s.grantRead(role));

    const secretArns = Object.fromEntries(SECRET_NAMES.map((n) => [n, this.secrets[n].secretArn]));

    this.instance = new ec2.Instance(this, "App", {
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      instanceType,
      machineImage: ec2.MachineImage.latestAmazonLinux2023(), // resolved from the public SSM parameter
      securityGroup,
      role,
      requireImdsv2: true,
      detailedMonitoring: true,
      ebsOptimized: true,
      associatePublicIpAddress: false,
      blockDevices: [
        {
          deviceName: "/dev/xvda",
          volume: ec2.BlockDeviceVolume.ebs(props.rootVolumeSizeGb ?? 60, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
            kmsKey: key,
            deleteOnTermination: true,
          }),
        },
      ],
      userData: ec2.UserData.custom(renderUserData({ region: this.region, composeRepoUrl, secretArns })),
      userDataCausesReplacement: true,
      disableApiTermination: true, // must be turned off before the host can be destroyed
    });
    cdk.Tags.of(this.instance).add("Name", "fyp-grading-app");

    // ------------------------------------------------------------ outputs
    new cdk.CfnOutput(this, "InstanceId", { value: this.instance.instanceId });
    new cdk.CfnOutput(this, "SsmSessionCommand", {
      value: `aws ssm start-session --target ${this.instance.instanceId} --region ${this.region}`,
    });

    this.addNagSuppressions(role);
  }

  private addNagSuppressions(role: iam.Role): void {
    NagSuppressions.addResourceSuppressions(role, [
      {
        id: "AwsSolutions-IAM4",
        reason: "AmazonSSMManagedInstanceCore is the AWS-documented policy for Session Manager.",
        appliesTo: ["Policy::arn:<AWS::Partition>:iam::aws:policy/AmazonSSMManagedInstanceCore"],
      },
    ]);
    NagSuppressions.addStackSuppressions(this, [
      { id: "AwsSolutions-SMG4", reason: "Demo passwords are rotated by redeploying; a rotation Lambda is overkill for a demo." },
    ]);
  }
}
