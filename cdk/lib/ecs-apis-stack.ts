import * as cdk from "aws-cdk-lib";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as ecs from "aws-cdk-lib/aws-ecs";
import * as ecsPatterns from "aws-cdk-lib/aws-ecs-patterns";
import * as logs from "aws-cdk-lib/aws-logs";
import { Construct } from "constructs";
import type { SharedInfraStack } from "./shared-infra-stack";

export interface EcsApisStackProps extends cdk.StackProps {
  sharedInfra: SharedInfraStack;
  imageTagUsers?: string;
  imageTagGames?: string;
  imageTagPayments?: string;
}

export interface EcsApiService {
  service: ecsPatterns.ApplicationLoadBalancedFargateService;
  loadBalancerDnsName: string;
}

export class EcsApisStack extends cdk.Stack {
  public readonly cluster: ecs.ICluster;
  public readonly usersApi: EcsApiService;
  public readonly gamesApi: EcsApiService;
  public readonly paymentsApi: EcsApiService;
  /** Base URL for the API Gateway (set after ApiGateway deploy); use in env for services. */
  public apiGatewayUrl: string = "";

  constructor(scope: Construct, id: string, props: EcsApisStackProps) {
    super(scope, id, props);

    const {
      sharedInfra,
      imageTagUsers = "latest",
      imageTagGames = "latest",
      imageTagPayments = "latest",
    } = props;

    const repoUsers = sharedInfra.ecrRepositories["users-api"];
    const repoGames = sharedInfra.ecrRepositories["games-api"];
    const repoPayments = sharedInfra.ecrRepositories["payments-api"];

    if (!repoUsers || !repoGames || !repoPayments) {
      throw new Error(
        "SharedInfra must have ecrRepositories for users-api, games-api, payments-api"
      );
    }

    this.cluster = new ecs.Cluster(this, "Cluster", {
      clusterName: `${sharedInfra.namePrefix}-cluster`,
      vpc: sharedInfra.vpc,
      containerInsights: false,
    });

    const queueUrl = sharedInfra.notificationQueue.queueUrl;

    const createService = (
      name: string,
      repo: ecr.IRepository,
      imageTag: string,
      serviceName: string
    ): EcsApiService => {
      const svc = new ecsPatterns.ApplicationLoadBalancedFargateService(
        this,
        name,
        {
          cluster: this.cluster,
          serviceName: `${sharedInfra.namePrefix}-${serviceName}`,
          taskImageOptions: {
            image: ecs.ContainerImage.fromEcrRepository(repo, imageTag),
            containerPort: 8080,
            environment: {
              ASPNETCORE_ENVIRONMENT: "Production",
              SQS_NOTIFICATION_QUEUE_URL: queueUrl,
              ApiBaseUrl: "", // Updated after API Gateway is deployed
            },
            logDriver: ecs.LogDrivers.awsLogs({
              streamPrefix: serviceName,
              logRetention: logs.RetentionDays.TWO_WEEKS,
            }),
          },
          memoryLimitMiB: 1024,
          cpu: 512,
          desiredCount: 1,
          publicLoadBalancer: true,
          healthCheckGracePeriod: cdk.Duration.seconds(60),
          listenerPort: 80,
        }
      );

      svc.targetGroup.configureHealthCheck({
        path: "/health",
        healthyHttpCodes: "200",
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
      });

      return {
        service: svc,
        loadBalancerDnsName: svc.loadBalancer.loadBalancerDnsName,
      };
    };

    this.usersApi = createService(
      "UsersApi",
      repoUsers,
      imageTagUsers,
      "users-api"
    );
    this.gamesApi = createService(
      "GamesApi",
      repoGames,
      imageTagGames,
      "games-api"
    );
    this.paymentsApi = createService(
      "PaymentsApi",
      repoPayments,
      imageTagPayments,
      "payments-api"
    );
  }
}
