# EC2 instance for the SREGym demo box.
#
# user_data is a thin wrapper that:
#   1. Writes /etc/aura-demo.env with the cross-account Bedrock creds the
#      systemd aura-demo-server unit consumes.
#   2. Clones aura-examples, then execs the canonical bootstrap script.
# This keeps bootstrap-instance.sh as the single source of truth for the
# boot flow — the user_data is just the bootstrapper's bootstrapper.

locals {
  user_data = <<-USERDATA
    #!/bin/bash
    set -uxo pipefail
    exec > >(tee -a /var/log/aura-demo-userdata.log) 2>&1

    dnf install -y git

    # Only materialize /etc/aura-demo.env when cross-account Bedrock creds
    # were supplied; an empty file here would set AWS_ACCESS_KEY_ID="" in
    # the systemd unit's env and OVERRIDE the EC2 instance profile's
    # IMDS-served credentials, silently breaking Bedrock. When the demo
    # instance runs in the Mezmo Bedrock account itself, the IAM role on
    # the instance is sufficient — leave this file absent.
    if [ -n "${var.bedrock_access_key_id}" ]; then
      install -m 0700 -d /etc
      cat > /etc/aura-demo.env <<EOF
    AWS_ACCESS_KEY_ID=${var.bedrock_access_key_id}
    AWS_SECRET_ACCESS_KEY=${var.bedrock_secret_access_key}
    EOF
      chmod 600 /etc/aura-demo.env
    fi

    sudo -u ec2-user git clone --branch "${var.aura_examples_git_ref}" \
      "${var.aura_examples_git_url}" /home/ec2-user/aura-examples
    cd /home/ec2-user/aura-examples/demo/sregym

    export DEMO_S3_BUCKET="${var.demo_s3_bucket}"
    export SREGYM_COMMIT_SHA="${var.sregym_commit_sha}"
    export AURA_GIT_REF="${var.aura_git_ref}"

    bash scripts/bootstrap-instance.sh
  USERDATA
}

resource "aws_instance" "demo" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.demo.id]
  iam_instance_profile   = aws_iam_instance_profile.demo.name
  user_data              = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 60  # SREGym + AURA + Docker images need ~30 GB; 60 leaves headroom
    encrypted   = true
  }

  tags = merge(local.tags, {
    Name = "${local.project}"
  })

  # Replace the instance if user_data changes — otherwise an edit to
  # bootstrap-instance.sh wouldn't re-bootstrap on `terraform apply`.
  user_data_replace_on_change = true
}
