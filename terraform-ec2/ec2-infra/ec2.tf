# KEY PAIR
resource "aws_key_pair" "my_key_pairs" {
  key_name   = "${var.env}-terraform-ec2-key" # Dynamic Naming
  public_key = file("terraform-ec2-key.pub")
  tags = {
    Environment = var.env
  }
}

# VPC
resource "aws_default_vpc" "default" {}

# SECURITY GROUP
resource "aws_security_group" "my_op_security_groups" {
  name        = "${var.env}-ultra-security-group" # Dynamic Naming
  description = "Automatic SG by TF for ${var.env}"
  vpc_id      = aws_default_vpc.default.id
  tags = {
    Environment = var.env
  }
}

# SG RULES
# (No name interpolation needed here, rules don't have AWS names, they attach to the SG ID)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.my_op_security_groups.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
  tags = {
    Environment = var.env
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.my_op_security_groups.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  description       = "Anyone can access"
  tags = {
    Environment = var.env
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.my_op_security_groups.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "EC2 can connect to whole world"
  tags = {
    Environment = var.env
  }
}



# DYNAMIC UBUNTU AMI
data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"] 

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "my_instance_ultraop" {
  count = var.instance_count
  
  depends_on             = [aws_key_pair.my_key_pairs, aws_security_group.my_op_security_groups]
  key_name               = aws_key_pair.my_key_pairs.key_name
  vpc_security_group_ids = [aws_security_group.my_op_security_groups.id]
  instance_type          = var.instance_type
  ami                    = data.aws_ami.ubuntu_24_04.id 
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  user_data              = file("${path.module}/User_data-ec2.sh")

  root_block_device {
    # Replaced var.env with terraform.workspace
    volume_size = "${var.ebs_storage}"
    volume_type = "gp3"
  }
  
  tags = {
    Name        = "${var.env}-${var.instance_name}" # Dynamic Naming: dev-PARTH-ULTRA-MICRO
    Environment = var.env
  }
}

