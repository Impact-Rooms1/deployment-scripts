const pulumi = require("@pulumi/pulumi");
const aws = require("@pulumi/aws");

// Create an AWS resource (EC2 Instance)
const instance = new aws.ec2.Instance("my-instance", {
    instanceType: "t4.medium",
    ami: "ami-xxxxxxxxxxxxxxxxx", // Replace this with the AMI ID for Ubuntu 22.02 LTS
    tags: {
        Name: "my-ubuntu-instance",
    },
});

// Export the public IP address of the instance
exports.publicIp = instance.publicIp;