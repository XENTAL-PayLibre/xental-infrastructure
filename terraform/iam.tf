# --- EC2 instance role: SSM-managed + read its own env's secrets ------------
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

# Lets the SSM agent register and receive Run Commands.
resource "aws_iam_role_policy_attachment" "host_ssm_core" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Read secrets + the GitHub token under /xental/* (SecureString via SSM KMS).
data "aws_iam_policy_document" "host_params" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${var.aws_region}:*:parameter/xental/*"]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "host_params" {
  name   = "xental-host-params"
  role   = aws_iam_role.host.id
  policy = data.aws_iam_policy_document.host_params.json
}

resource "aws_iam_instance_profile" "host" {
  name = "xental-host"
  role = aws_iam_role.host.name
}

# --- GitHub OIDC provider + deploy role -------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  # Create once per account if it doesn't exist; see README. If you prefer
  # Terraform to own it, replace this data source with an aws_iam_oidc... resource.
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.infra_repo}:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "xental-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
  tags               = var.tags
}

# The deploy role only needs to find the host and send it the deploy command.
data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  statement {
    actions   = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:*:instance/*",
      "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
    ]
  }
  statement {
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "xental-github-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
