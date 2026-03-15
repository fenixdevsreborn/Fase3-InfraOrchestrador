import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as rds from "aws-cdk-lib/aws-rds";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";
import type { SharedInfraStack } from "./shared-infra-stack";

export interface OptionalStackProps extends cdk.StackProps {
  sharedInfra: SharedInfraStack;
  enableRds?: boolean;
  enableFrontendBucket?: boolean;
  frontendBucketName?: string;
}

export class OptionalStack extends cdk.Stack {
  public readonly rdsInstance?: rds.IDatabaseInstance;
  public readonly frontendBucket?: s3.IBucket;

  constructor(scope: Construct, id: string, props: OptionalStackProps) {
    super(scope, id, props);

    const {
      sharedInfra,
      enableRds = false,
      enableFrontendBucket = false,
      frontendBucketName = "",
    } = props;

    if (enableRds) {
      const securityGroup = new ec2.SecurityGroup(this, "RdsSg", {
        vpc: sharedInfra.vpc,
        description: "RDS PostgreSQL",
        allowAllOutbound: true,
      });
      securityGroup.addIngressRule(
        ec2.Peer.ipv4(sharedInfra.vpc.vpcCidrBlock),
        ec2.Port.tcp(5432),
        "PostgreSQL from VPC"
      );

      this.rdsInstance = new rds.DatabaseInstance(this, "Postgres", {
        engine: rds.DatabaseInstanceEngine.postgres({
          version: rds.PostgresEngineVersion.VER_16,
        }),
        instanceIdentifier: `${sharedInfra.namePrefix}-postgres`,
        vpc: sharedInfra.vpc,
        vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
        securityGroups: [securityGroup],
        instanceType: ec2.InstanceType.of(
          ec2.InstanceClass.T3,
          ec2.InstanceSize.MICRO
        ),
        allocatedStorage: 20,
        maxAllocatedStorage: 40,
        storageEncrypted: true,
        credentials: rds.Credentials.fromGeneratedSecret("fcgadmin"),
      });
    }

    if (enableFrontendBucket) {
      const bucketName =
        frontendBucketName ||
        `${sharedInfra.namePrefix}-frontend-${this.node.addr.slice(-8)}`;
      this.frontendBucket = new s3.Bucket(this, "Frontend", {
        bucketName,
        versioned: true,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
        autoDeleteObjects: true,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      });
    }
  }
}
