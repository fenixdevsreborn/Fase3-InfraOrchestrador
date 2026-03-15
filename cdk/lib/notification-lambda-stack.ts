import * as cdk from "aws-cdk-lib";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as iam from "aws-cdk-lib/aws-iam";
import * as logs from "aws-cdk-lib/aws-logs";
import * as lambdaEventSources from "aws-cdk-lib/aws-lambda-event-sources";
import { Construct } from "constructs";
import type { SharedInfraStack } from "./shared-infra-stack";

export interface NotificationLambdaStackProps extends cdk.StackProps {
  sharedInfra: SharedInfraStack;
  imageTag: string;
  memoryMb?: number;
  timeoutSec?: number;
}

export class NotificationLambdaStack extends cdk.Stack {
  public readonly notificationFunction: lambda.IFunction;

  constructor(scope: Construct, id: string, props: NotificationLambdaStackProps) {
    super(scope, id, props);

    const { sharedInfra, imageTag, memoryMb = 256, timeoutSec = 30 } = props;

    const repo = sharedInfra.ecrRepositories["notification-lambda"];
    if (!repo) {
      throw new Error("SharedInfra must have ecrRepositories['notification-lambda']");
    }

    const fn = new lambda.DockerImageFunction(this, "NotificationLambda", {
      functionName: `${sharedInfra.namePrefix}-notification`,
      code: lambda.DockerImageCode.fromEcr(repo, {
        tagOrDigest: imageTag,
      }),
      memorySize: memoryMb,
      timeout: cdk.Duration.seconds(timeoutSec),
      environment: {
        ASPNETCORE_ENVIRONMENT: "Production",
      },
      logRetention: logs.RetentionDays.TWO_WEEKS,
    });

    fn.addEventSource(
      new lambdaEventSources.SqsEventSource(sharedInfra.notificationQueue, {
        batchSize: 10,
      })
    );

    fn.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["ses:SendEmail", "ses:SendRawEmail"],
        resources: ["*"],
      })
    );

    this.notificationFunction = fn;
  }
}
