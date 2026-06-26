resource aws_s3_bucket my-remote-buckets {
    bucket = "my-project-terraform-state-bucket"
    force_destroy = true
    tags = {
        name = "my-project-terraform-state-bucket"
    }
}