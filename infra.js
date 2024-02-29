const pulumi = require("@pulumi/pulumi");
const aws = require("@pulumi/aws");

// Helper function to check if an Elastic IP exists
async function eipExists(name) {
    try {
        await aws.ec2.getEip({ filters: [{ name: "tag:Name", values: [name] }] });
        return true;
    } catch (error) {
        if (error.code === "NotFound") {
            return false;
        }
        throw error;
    }
}

// Helper function to create an EC2 instance with an Elastic IP
async function createInstance(name, ami, instanceType) {
    const eip = await createIfNotExists(`${name}-eip`);
    const instance = new aws.ec2.Instance(name, {
        instanceType: instanceType,
        ami: ami,
        tags: {
            Name: name,
        },
    });
    const eipAssociation = new aws.ec2.EipAssociation(`${name}-eipAssociation`, {
        instanceId: instance.id,
        allocationId: eip.id,
    });
    return { instance, eip };
}

// Helper function to create an Elastic IP if it doesn't exist
async function createIfNotExists(name) {
    if (!(await eipExists(name))) {
        return new aws.ec2.Eip(name, { tags: { Name: name } });
    }
}

// Create a PostgreSQL RDS instance
const postgresInstance = new aws.rds.Instance("my-postgres-instance", {
    engine: "postgres",
    engineVersion: "12.17",
    instanceClass: "db.t4.small",
    allocatedStorage: 20,
    name: "company",
    username: "masteruser",
    password: "SuperSecretPassword123", // Change this to your desired password
    skipFinalSnapshot: true,
});

// Export the endpoint, master username, and master password
// pass this to our scripts
// exports.endpoint = postgresInstance.endpoint;
// exports.masterUsername = postgresInstance.username;
// exports.masterPassword = postgresInstance.password;

// Server
const mainServer = await createInstance("haproxy-instance", "ami-xxxxxxxxxxxxxxxxx", "t4.medium");

// Create the HAProxy instance
const haproxyInstance = await createInstance("haproxy-instance", "ami-xxxxxxxxxxxxxxxxx", "t4.medium");

// Create a Target Group
const targetGroup = new aws.lb.TargetGroup("haproxy-target-group", {
    port: 80,
    protocol: "HTTP",
    targetType: "instance",
    healthCheck: {
        protocol: "HTTP",
        path: "/",
        port: "80",
    },
});

// Register the HAProxy instance with the Target Group
const targetGroupAttachment = new aws.lb.TargetGroupAttachment("haproxy-target-group-attachment", {
    targetGroupArn: targetGroup.arn,
    targetId: haproxyInstance.instance.id,
    port: 80,
});

// Create an Application Load Balancer
const alb = new aws.lb.LoadBalancer("my-alb", {
    internal: false,
    loadBalancerType: "application",
    securityGroups: [aws.lb.getSecurityGroups({ vpcId: aws.getVpc().id }).then(groups => groups.ids[0])],
    subnets: aws.ec2.getSubnetIds().then(subnets => subnets.ids),
});

// Create a Listener for the ALB
const listener = new aws.lb.Listener("listener", {
    loadBalancerArn: alb.arn,
    port: 80,
    protocol: "HTTP",
    defaultActions: [{
        type: "forward",
        targetGroupArn: targetGroup.arn,
    }],
});

// Export the public IP addresses of both instances
exports.haproxyPublicIp = haproxyInstance.eip.publicIp;
exports.albDnsName = alb.dnsName;