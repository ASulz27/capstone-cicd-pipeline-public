variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "capstone-cicd-pipeline"
}

variable "admin_cidr" {
  description = "The CIDR block for the admin access"
  type        = string
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type for both servers"
}

