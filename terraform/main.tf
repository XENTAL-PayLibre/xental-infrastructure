provider "aws" {
  region = var.aws_region
}

locals {
  environments = toset(["staging", "production"])
}

# --- Networking (uses the account's default VPC for simplicity) -------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Ubuntu 24.04 LTS AMI.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# --- Security group: only 80/443 from the internet --------------------------
resource "aws_security_group" "web" {
  name        = "xental-web"
  description = "Public HTTP/HTTPS for Traefik; egress all. No inbound SSH (SSM only)."
  vpc_id      = data.aws_vpc.default.id
  tags        = var.tags

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EC2 hosts (one per environment) ----------------------------------------
resource "aws_instance" "host" {
  for_each = local.environments

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_types[each.key]
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/usr/bin/env bash
    set -euxo pipefail
    export ENV_NAME="${each.key}"
    export GIT_REMOTE="${var.git_remote}"
    export AWS_REGION="${var.aws_region}"
    # Pull the bootstrap script straight from the repo's main branch and run it.
    curl -fsSL https://raw.githubusercontent.com/${var.github_org}/${var.infra_repo}/main/scripts/bootstrap-host.sh -o /root/bootstrap-host.sh
    bash /root/bootstrap-host.sh
  EOF

  tags = merge(var.tags, {
    Name        = "xental-${each.key}"
    Environment = each.key
  })
}

resource "aws_eip" "host" {
  for_each = local.environments
  instance = aws_instance.host[each.key].id
  tags     = merge(var.tags, { Name = "xental-${each.key}" })
}
