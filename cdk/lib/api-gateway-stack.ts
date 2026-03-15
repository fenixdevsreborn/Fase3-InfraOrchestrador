import * as cdk from "aws-cdk-lib";
import * as apigwv2 from "aws-cdk-lib/aws-apigatewayv2";
import * as apigwv2Integrations from "aws-cdk-lib/aws-apigatewayv2-integrations";
import { Construct } from "constructs";
import type { SharedInfraStack } from "./shared-infra-stack";
import type { EcsApisStack } from "./ecs-apis-stack";

export interface ApiGatewayStackProps extends cdk.StackProps {
  sharedInfra: SharedInfraStack;
  ecsApis: EcsApisStack;
  jwtIssuerUri: string;
  jwtAudience: string[];
}

export class ApiGatewayStack extends cdk.Stack {
  public readonly httpApi: apigwv2.IHttpApi;
  public readonly apiEndpoint: string;

  constructor(scope: Construct, id: string, props: ApiGatewayStackProps) {
    super(scope, id, props);

    const { sharedInfra, ecsApis, jwtAudience } = props;
    let { jwtIssuerUri } = props;

    const httpApi = new apigwv2.HttpApi(this, "HttpApi", {
      apiName: `${sharedInfra.namePrefix}-api`,
      description: "FCG Cloud Platform HTTP API",
      corsPreflight: {
        allowOrigins: ["*"],
        allowMethods: [
          apigwv2.CorsHttpMethod.GET,
          apigwv2.CorsHttpMethod.POST,
          apigwv2.CorsHttpMethod.PUT,
          apigwv2.CorsHttpMethod.PATCH,
          apigwv2.CorsHttpMethod.DELETE,
          apigwv2.CorsHttpMethod.OPTIONS,
        ],
        allowHeaders: [
          "authorization",
          "content-type",
          "x-correlation-id",
          "x-api-key",
        ],
        maxAge: cdk.Duration.days(1),
      },
      defaultIntegration: new apigwv2Integrations.HttpUrlIntegration(
        "DefaultIntegration",
        "https://httpbin.org/anything"
      ),
    });

    if (!jwtIssuerUri && httpApi.apiEndpoint) {
      jwtIssuerUri = httpApi.apiEndpoint;
    }

    let authorizer: apigwv2.IHttpRouteAuthorizer | undefined;
    if (jwtIssuerUri && jwtAudience.length > 0) {
      const jwtAuthorizer = new apigwv2.HttpAuthorizer(this, "JwtAuthorizer", {
        httpApi,
        type: apigwv2.HttpAuthorizerType.JWT,
        identitySource: ["$request.header.Authorization"],
        jwtAudience,
        jwtIssuer: jwtIssuerUri,
        authorizerName: `${sharedInfra.namePrefix}-jwt`,
      });
      authorizer = apigwv2.HttpAuthorizer.fromHttpAuthorizerAttributes(
        this,
        "JwtAuthorizerRef",
        {
          authorizerId: jwtAuthorizer.authorizerId,
          authorizerType: apigwv2.HttpAuthorizerType.JWT,
        }
      );
    }

    const usersAlbUrl = `http://${ecsApis.usersApi.loadBalancerDnsName}`;
    const gamesAlbUrl = `http://${ecsApis.gamesApi.loadBalancerDnsName}`;
    const paymentsAlbUrl = `http://${ecsApis.paymentsApi.loadBalancerDnsName}`;

    httpApi.addRoutes({
      path: "/.well-known/{proxy+}",
      methods: [apigwv2.HttpMethod.GET],
      integration: new apigwv2Integrations.HttpUrlIntegration(
        "UsersWellKnown",
        usersAlbUrl
      ),
    });
    httpApi.addRoutes({
      path: "/users/{proxy+}",
      methods: [
        apigwv2.HttpMethod.GET,
        apigwv2.HttpMethod.POST,
        apigwv2.HttpMethod.PUT,
        apigwv2.HttpMethod.PATCH,
        apigwv2.HttpMethod.DELETE,
      ],
      integration: new apigwv2Integrations.HttpUrlIntegration(
        "UsersApi",
        usersAlbUrl
      ),
      authorizer,
    });
    httpApi.addRoutes({
      path: "/auth/{proxy+}",
      methods: [apigwv2.HttpMethod.GET, apigwv2.HttpMethod.POST],
      integration: new apigwv2Integrations.HttpUrlIntegration(
        "Auth",
        usersAlbUrl
      ),
    });

    httpApi.addRoutes({
      path: "/games/{proxy+}",
      methods: [
        apigwv2.HttpMethod.GET,
        apigwv2.HttpMethod.POST,
        apigwv2.HttpMethod.PUT,
        apigwv2.HttpMethod.PATCH,
        apigwv2.HttpMethod.DELETE,
      ],
      integration: new apigwv2Integrations.HttpUrlIntegration(
        "GamesApi",
        gamesAlbUrl
      ),
      authorizer,
    });

    httpApi.addRoutes({
      path: "/payments/{proxy+}",
      methods: [
        apigwv2.HttpMethod.GET,
        apigwv2.HttpMethod.POST,
        apigwv2.HttpMethod.PUT,
        apigwv2.HttpMethod.PATCH,
        apigwv2.HttpMethod.DELETE,
      ],
      integration: new apigwv2Integrations.HttpUrlIntegration(
        "PaymentsApi",
        paymentsAlbUrl
      ),
      authorizer,
    });

    this.httpApi = httpApi;
    this.apiEndpoint = httpApi.apiEndpoint ?? "";

    new cdk.CfnOutput(this, "ApiEndpoint", {
      value: this.apiEndpoint,
      description: "API Gateway HTTP API endpoint",
      exportName: `${sharedInfra.namePrefix}-ApiEndpoint`,
    });
  }
}
