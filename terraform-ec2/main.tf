
module "production-infra" {
    source = "./ec2-infra"
    env = "prod"
    instance_name = "my-good-instance"
    instance_type = "t3.small"
    ebs_storage = 20
    instance_count = 1
}
