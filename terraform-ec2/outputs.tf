output "ec2_public_ip" {
  value = module.production-infra.public_ip
}

output "ec2_public_dns" {
  value = module.production-infra.public_dns
}

output "ec2_private_ip" {
  value = module.production-infra.private_ip
}