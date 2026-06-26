# 1. Create the IAM Role and define the Trust Policy (Allows EC2 to assume this role)
resource "aws_iam_role" "ec2_ecr_role" {
  name = "<YOUR_PROJECT_NAME>-ec2-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "production"
    Project     = "<YOUR_PROJECT_NAME>"
  }
}

# 2. Attach the AWS Managed Read-Only Policy for ECR to the Role
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# 3. Create the IAM Instance Profile (The wrapper required by EC2)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ecr-ec2-instance-profile"
  role = aws_iam_role.ec2_ecr_role.name
}