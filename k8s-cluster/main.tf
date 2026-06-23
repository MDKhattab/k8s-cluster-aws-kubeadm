module "vpc" {
  source     = "./modules/vpc"
  cidr_block = var.vpc_cidr
  project    = var.project
}

module "security_group" {
  source    = "./modules/security-group"
  vpc_id    = module.vpc.vpc_id
  my_ip     = var.my_ip
  project   = var.project
}

module "keypair" {
  source   = "./modules/keypair"
  key_name = var.key_name
}

module "ec2" {
  source               = "./modules/ec2"
  subnet_id            = module.vpc.subnet_id
  security_group_id    = module.security_group.sg_id
  key_name             = module.keypair.key_name
  project              = var.project
  master_instance_type = var.master_instance_type
  worker_instance_type = var.worker_instance_type
}
