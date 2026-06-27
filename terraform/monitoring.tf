# Dedicated observability/monitoring host. Runs the xental-observability stack
# (Prometheus, Grafana, Loki, Tempo, Alertmanager). App hosts push to it.

resource "aws_security_group" "monitoring" {
  name        = "xental-monitoring"
  description = "Monitoring host: receives metrics/logs/traces from app hosts; admin SSH + Grafana."
  vpc_id      = data.aws_vpc.default.id
  tags        = var.tags

  ingress {
    description = "SSH (key-only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }
  ingress {
    description = "Grafana UI (admin) — prefer an SSH tunnel; restricted to admin CIDR"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }
  ingress {
    description     = "Prometheus remote-write from app hosts"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
  ingress {
    description     = "Loki log ingest from app hosts"
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
  ingress {
    description     = "Tempo OTLP trace ingest from app hosts"
    from_port       = 4317
    to_port         = 4318
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.monitoring_instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name
  key_name               = aws_key_pair.deploy.key_name

  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    volume_size = var.monitoring_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  # Install Docker; the observability stack is brought up manually (one command)
  # per xental-observability/docs/RUNBOOK.md.
  user_data = <<-EOF
    #!/usr/bin/env bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl git
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    usermod -aG docker ubuntu || true
    mkdir -p /opt/xental-observability
    chown -R ubuntu:ubuntu /opt/xental-observability
  EOF

  tags = merge(var.tags, { Name = "xental-monitoring", Environment = "monitoring" })
}

resource "aws_eip" "monitoring" {
  instance = aws_instance.monitoring.id
  tags     = merge(var.tags, { Name = "xental-monitoring" })
}

output "monitoring_public_ip" {
  description = "Monitoring host public IP (SSH + tunnel to Grafana)."
  value       = aws_eip.monitoring.public_ip
}

output "monitoring_private_ip" {
  description = "Set this as MONITORING_HOST in the app env files so Alloy ships here."
  value       = aws_instance.monitoring.private_ip
}
