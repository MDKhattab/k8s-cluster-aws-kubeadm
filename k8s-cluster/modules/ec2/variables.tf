variable "subnet_id" {
  type = string
}
variable "security_group_id" {
  type = string
}
variable "key_name" {
  type = string
}
variable "project" {
  type = string
}
variable "master_instance_type" {
  type = string
  default = "t3.medium"
}
variable "worker_instance_type" {
  type = string
  default = "t3.small"
}
