data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  private_ip             = "10.0.0.10"

  tags = { Name = "${var.project}-master", Role = "master" }
}

resource "aws_instance" "worker1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.worker_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  private_ip             = "10.0.0.11"

  tags = { Name = "${var.project}-worker1", Role = "worker" }
}

resource "aws_instance" "worker2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.worker_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  private_ip             = "10.0.0.12"

  tags = { Name = "${var.project}-worker2", Role = "worker" }
}
