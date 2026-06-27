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

# --- SSH key authorised on the hosts ----------------------------------------
resource "aws_key_pair" "deploy" {
  key_name   = "xental-deploy"
  public_key = var.ssh_public_key
  tags       = var.tags
}

# --- Security group: 80/443 public + 22 (key-only) --------------------------
resource "aws_security_group" "web" {
  name        = "xental-web"
  description = "Public HTTP/HTTPS for Traefik + SSH for deploys (key-only)."
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
  ingress {
    description = "SSH (key-only; from GitHub Actions runners)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
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
  key_name               = aws_key_pair.deploy.key_name

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  # Install Docker + compose, grant the login user docker access, prepare the
  # deploy dir. Files + the rendered env are rsynced in later by the workflow.
  user_data = <<-EOF
    #!/usr/bin/env bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    usermod -aG docker ubuntu || true
    mkdir -p /opt/xental-infrastructure/env
    chown -R ubuntu:ubuntu /opt/xental-infrastructure
    # SSH brute-force protection.
    apt-get install -y fail2ban
    printf '[sshd]\nenabled = true\nmaxretry = 5\nbantime = 1h\nfindtime = 10m\n' > /etc/fail2ban/jail.d/sshd.local
    systemctl enable --now fail2ban
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
