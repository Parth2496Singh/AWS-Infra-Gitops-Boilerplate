output "public_ip" {
  value = aws_instance.my_instance_ultraop[*].public_ip
}

output "public_dns" {
  value = aws_instance.my_instance_ultraop[*].public_dns
}

output "private_ip" {
  value = aws_instance.my_instance_ultraop[*].private_ip
}