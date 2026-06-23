terraform {
  backend "s3" {
    bucket       = "k8s-cluster-task"
    key          = "k8s-cluster/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
