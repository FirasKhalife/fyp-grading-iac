import * as cdk from "aws-cdk-lib";
import { Aspects } from "aws-cdk-lib";
import { AwsSolutionsChecks } from "cdk-nag";
import { FypGradingStack } from "../lib/fyp-grading-stack";

const app = new cdk.App();

// Deliberately environment-agnostic: no account or region is baked in, so synth needs no
// credentials and no context lookups. The stack would pick them up from the CLI at deploy time.
new FypGradingStack(app, "FypGradingDemo", {
  description: "FYP grading platform: reference deployment (never deployed)",
});

Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
