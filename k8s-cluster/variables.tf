variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "project" {
  type    = string
  default = "k8s-cluster"
}

variable "my_ip" {
  type        = string
  description = "Your public IP in CIDR notation, e.g. 1.2.3.4/32"
}

variable "key_name" {
  type        = string
  description = "Name of existing AWS key pair"
}

variable "master_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.small"
}
