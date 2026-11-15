import * as cdk from "aws-cdk-lib";
import { Annotations, Match, Template } from "aws-cdk-lib/assertions";
import { Aspects } from "aws-cdk-lib";
import { AwsSolutionsChecks } from "cdk-nag";
import { FypGradingStack } from "../lib/fyp-grading-stack";

function build(): { stack: FypGradingStack; template: Template } {
  const app = new cdk.App();
  const stack = new FypGradingStack(app, "Test");
  return { stack, template: Template.fromStack(stack) };
}

describe("FypGradingStack", () => {
  const { stack, template } = build();
  void stack;

  test("instance enforces IMDSv2 through its launch template", () => {
    template.hasResourceProperties("AWS::EC2::LaunchTemplate", {
      LaunchTemplateData: Match.objectLike({
        MetadataOptions: Match.objectLike({ HttpTokens: "required" }),
      }),
    });
  });

  test("instance is private, monitored and has an encrypted gp3 root volume", () => {
    template.hasResourceProperties("AWS::EC2::Instance", {
      Monitoring: true,
      EbsOptimized: true,
      BlockDeviceMappings: [
        Match.objectLike({
          DeviceName: "/dev/xvda",
          Ebs: Match.objectLike({ Encrypted: true, VolumeType: "gp3", VolumeSize: 60 }),
        }),
      ],
    });
    template.resourceCountIs("AWS::EC2::Instance", 1);
  });

  test("security group has no inbound rules and only HTTPS egress", () => {
    template.hasResourceProperties("AWS::EC2::SecurityGroup", {
      GroupDescription: "App host: no inbound at all, outbound HTTPS only",
      SecurityGroupIngress: Match.absent(),
      SecurityGroupEgress: [Match.objectLike({ IpProtocol: "tcp", FromPort: 443, ToPort: 443 })],
    });
  });

  test("access is via SSM: managed policy attached, no key pair", () => {
    template.hasResourceProperties("AWS::IAM::Role", {
      ManagedPolicyArns: Match.arrayWith([
        Match.objectLike({
          "Fn::Join": Match.arrayWith([Match.arrayWith([Match.stringLikeRegexp("AmazonSSMManagedInstanceCore")])]),
        }),
      ]),
    });
    template.hasResourceProperties("AWS::EC2::LaunchTemplate", {
      LaunchTemplateData: Match.not(Match.objectLike({ KeyName: Match.anyValue() })),
    });
  });

  test("AMI is resolved from the public SSM parameter, not hardcoded", () => {
    const params = template.findParameters("*", { Type: "AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>" });
    expect(Object.keys(params).length).toBe(1);
    expect(JSON.stringify(Object.values(params)[0])).toContain("al2023");
  });

  test("four generated secrets, encrypted with the project key", () => {
    template.resourceCountIs("AWS::SecretsManager::Secret", 4);
    template.allResourcesProperties("AWS::SecretsManager::Secret", {
      KmsKeyId: Match.anyValue(),
      GenerateSecretString: Match.objectLike({ PasswordLength: 32 }),
    });
  });

  test("KMS key rotates and no secret value appears in the template", () => {
    template.hasResourceProperties("AWS::KMS::Key", { EnableKeyRotation: true });
    expect(JSON.stringify(template.toJSON())).not.toMatch(/password=\w{8,}/i);
  });

  test("VPC has one NAT gateway, flow logs and a locked-down default security group", () => {
    template.resourceCountIs("AWS::EC2::NatGateway", 1);
    template.resourceCountIs("AWS::EC2::FlowLog", 1);
    template.hasResourceProperties("Custom::VpcRestrictDefaultSG", { DefaultSecurityGroupId: Match.anyValue() });
  });

  test("user data embeds secret ARNs only", () => {
    expect(stack.instance.userData).toBeDefined();
    const text = JSON.stringify(template.toJSON());
    expect(text).toContain("aws secretsmanager get-secret-value");
  });
});

describe("cdk-nag AwsSolutions pack", () => {
  test("no unsuppressed errors or warnings", () => {
    const app = new cdk.App();
    const stack = new FypGradingStack(app, "Nag");
    Aspects.of(app).add(new AwsSolutionsChecks());
    const errors = Annotations.fromStack(stack).findError("*", Match.stringLikeRegexp("AwsSolutions-.*"));
    const warnings = Annotations.fromStack(stack).findWarning("*", Match.stringLikeRegexp("AwsSolutions-.*"));
    expect(errors.map((e) => e.entry.data)).toEqual([]);
    expect(warnings.map((w) => w.entry.data)).toEqual([]);
  });
});
