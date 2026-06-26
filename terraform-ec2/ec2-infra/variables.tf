variable "env" {
    description = "This is the environment variable"
    type = string
}

variable "instance_name" {
    description = "This is the name for the ec2 instance"
    type = string
}

variable "instance_type" {
    description = "This is the type of the ec2 instance"
    type = string
}

variable "ebs_storage" {
    description = "This is the amount of ec2 storage"
    type = number
}

variable "instance_count" {
    description = "This is the number of ec2 instances"
    type = number
}





