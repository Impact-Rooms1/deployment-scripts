// used to switch staging to production instance

const pulumi = require("@pulumi/pulumi");
const aws = require("@pulumi/aws");

// Helper function to detach an Elastic IP from an EC2 instance
async function detachElasticIp(instanceId) {
    const eip = await aws.ec2.getEip({ instanceId });
    if (eip) {
        await aws.ec2.EipAssociation.delete("eipAssociation", { allocationId: eip.allocationId });
    }
}

// Helper function to attach an Elastic IP to an EC2 instance
async function attachElasticIp(instanceId, allocationId) {
    await aws.ec2.EipAssociation.create("eipAssociation", { instanceId, allocationId });
}

// Retrieve the IDs of the staging and production instances
const stagingInstanceId = pulumi.output(aws.ec2.getInstance({
    filters: [
        { name: "tag:Name", values: ["staging-instance"] },
    ],
}).then(instance => instance.id));

const prodInstanceId = pulumi.output(aws.ec2.getInstance({
    filters: [
        { name: "tag:Name", values: ["production-instance"] },
    ],
}).then(instance => instance.id));

// Retrieve the Elastic IPs for staging and production
const stagingEipAllocationId = pulumi.output(aws.ec2.getEipAllocationIds({
    filters: [
        { name: "tag:Name", values: ["stagingEip"] },
    ],
}).then(ids => ids.ids[0]));

const prodEipAllocationId = pulumi.output(aws.ec2.getEipAllocationIds({
    filters: [
        { name: "tag:Name", values: ["prodEip"] },
    ],
}).then(ids => ids.ids[0]));

// Detach and attach the Elastic IPs
detachElasticIp(stagingInstanceId);
detachElasticIp(prodInstanceId);

attachElasticIp(stagingInstanceId, prodEipAllocationId);
attachElasticIp(prodInstanceId, stagingEipAllocationId);
