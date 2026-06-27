# EC2 instance role. Deploys arrive over SSH from GitHub Actions, so the role
# itself needs no deploy permissions. We attach AmazonSSMManagedInstanceCore
# only for break-glass access via SSM Session Manager (no secrets live in SSM).
data "aws_iam_policy_document" "host_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "host" {
  name               = "xental-host"
  assume_role_policy = data.aws_iam_policy_document.host_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "host_ssm_core" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "host" {
  name = "xental-host"
  role = aws_iam_role.host.name
}
