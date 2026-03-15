import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as sqs from "aws-cdk-lib/aws-sqs";
import * as logs from "aws-cdk-lib/aws-logs";
import { Construct } from "constructs";

export interface SharedInfraStackProps extends cdk.StackProps {
  projectName: string;
  environment: string;
  createVpc?: boolean;
  logRetentionDays?: number;
  ecrRepositoryNames: string[];
  sqsNotificationQueueName: string;
  sqsMessageRetentionSeconds?: number;
}

export class SharedInfraStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly ecrRepositories: Record<string, ecr.IRepository> = {};
  public readonly notificationQueue: sqs.IQueue;
  public readonly notificationQueueDlq: sqs.IQueue;
  public readonly apiGatewayLogGroup: logs.ILogGroup;
  public readonly notificationLambdaLogGroup: logs.ILogGroup;
  public readonly namePrefix: string;

  constructor(scope: Construct, id: string, props: SharedInfraStackProps) {
    super(scope, id, props);

    const {
      projectName,
      environment,
      createVpc = true,
      logRetentionDays = 14,
      ecrRepositoryNames,
      sqsNotificationQueueName,
      sqsMessageRetentionSeconds = 86400,
    } = props;

    this.namePrefix = `${projectName}-${environment}`;

    this.vpc = createVpc
      ? new ec2.Vpc(this, "Vpc", {
          maxAzs: 3,
          natGateways: 1,
        })
      : ec2.Vpc.fromLookup(this, "Vpc", {
          isDefault: true,
        });

    for (const name of ecrRepositoryNames) {
      const repo = new ecr.Repository(this, `Ecr${this.sanitizeId(name)}`, {
        repositoryName: `${this.namePrefix}-${name}`,
        imageTagMutability: ecr.TagMutability.MUTABLE,
        imageScanOnPush: true,
        removalPolicy: cdk.RemovalPolicy.RETAIN,
      });
      repo.addLifecycleRule({
        description: "Keep last 10 images",
        maxImageCount: 10,
        rulePriority: 1,
      });
      this.ecrRepositories[name] = repo;
    }

    this.notificationQueueDlq = new sqs.Queue(this, "NotificationDlq", {
      queueName: `${this.namePrefix}-${sqsNotificationQueueName}-dlq`,
      retentionPeriod: cdk.Duration.days(14),
    });

    this.notificationQueue = new sqs.Queue(this, "NotificationQueue", {
      queueName: `${this.namePrefix}-${sqsNotificationQueueName}`,
      retentionPeriod: cdk.Duration.seconds(sqsMessageRetentionSeconds),
      visibilityTimeout: cdk.Duration.seconds(60),
      receiveMessageWaitTime: cdk.Duration.seconds(20),
      deadLetterQueue: {
        queue: this.notificationQueueDlq,
        maxReceiveCount: 3,
      },
    });

    const retention = this.toRetentionDays(logRetentionDays);
    this.apiGatewayLogGroup = new logs.LogGroup(this, "ApiGatewayLogGroup", {
      logGroupName: `/aws/apigateway/${this.namePrefix}-http-api`,
      retention,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.notificationLambdaLogGroup = new logs.LogGroup(
      this,
      "NotificationLambdaLogGroup",
      {
        logGroupName: `/aws/lambda/${this.namePrefix}-notification`,
        retention,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }
    );

    new cdk.CfnOutput(this, "NotificationQueueUrl", {
      value: this.notificationQueue.queueUrl,
      description: "SQS Notification Queue URL",
      exportName: `${this.namePrefix}-NotificationQueueUrl`,
    });
  }

  private sanitizeId(name: string): string {
    return name.replace(/[^a-zA-Z0-9]/g, "");
  }

  private toRetentionDays(days: number): logs.RetentionDays {
    const map: Record<number, logs.RetentionDays> = {
      1: logs.RetentionDays.ONE_DAY,
      3: logs.RetentionDays.THREE_DAYS,
      5: logs.RetentionDays.FIVE_DAYS,
      7: logs.RetentionDays.ONE_WEEK,
      14: logs.RetentionDays.TWO_WEEKS,
      30: logs.RetentionDays.ONE_MONTH,
    };
    return map[days] ?? logs.RetentionDays.TWO_WEEKS;
  }
}
