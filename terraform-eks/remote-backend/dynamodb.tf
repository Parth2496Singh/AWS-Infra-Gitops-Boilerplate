resource "aws_dynamodb_table" "basic-dynamodb-table" {
  name           = "my-project-terraform-lock-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S" # S=string
  }
  tags = {
    Name        = "my-project-terraform-lock-table"
  }
}