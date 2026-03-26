#!/bin/bash
# Aura Demo Setup — runs in Instruqt cloud-client container
# Installs tools, downloads Terraform bundle, deploys ECS infrastructure

LOG="/tmp/aura-setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Aura Demo Setup $(date) ==="

# Install AWS CLI v2
echo "[1/5] Installing AWS CLI v2..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update 2>/dev/null || /tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws
aws --version || true

# Install Terraform
echo "[2/5] Installing Terraform..."
curl -sf "https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip" -o /tmp/terraform.zip
unzip -q /tmp/terraform.zip -d /usr/local/bin/
rm -f /tmp/terraform.zip
terraform version || true

# Install jq
which jq > /dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq jq > /dev/null 2>&1) || true

# Disable AWS CLI pager
export AWS_PAGER=""

# Download demo bundle
echo "[3/5] Downloading demo bundle..."
curl -sf "https://aura-demo-bundle.s3.amazonaws.com/aura-demo-bundle.tar.gz" -o /tmp/aura-demo-bundle.tar.gz
mkdir -p /opt/aura
tar xzf /tmp/aura-demo-bundle.tar.gz -C /opt/aura
rm -f /tmp/aura-demo-bundle.tar.gz

# Install helper scripts
chmod +x /opt/aura/bin/* 2>/dev/null || true
ln -sf /opt/aura/bin/* /usr/local/bin/ 2>/dev/null || true

# Configure AWS credentials (admin creds from Instruqt)
echo "[4/5] Configuring credentials..."

ADMIN_KEY="${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_ADMIN_AWS_ACCESS_KEY_ID:-}"
ADMIN_SECRET="${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_ADMIN_AWS_SECRET_ACCESS_KEY:-}"

if [ -z "$ADMIN_KEY" ]; then
  ADMIN_KEY="${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_ADMIN_ACCESS_KEY_ID:-}"
  ADMIN_SECRET="${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_ADMIN_SECRET_ACCESS_KEY:-}"
fi

if [ -n "$ADMIN_KEY" ]; then
  echo "Using ADMIN credentials for Terraform"
  export AWS_ACCESS_KEY_ID="$ADMIN_KEY"
  export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET"
else
  echo "WARNING: No admin credentials found."
fi

export AWS_DEFAULT_REGION=us-east-1
aws configure set region us-east-1

echo "Current identity:"
aws sts get-caller-identity 2>&1 || true

# Bedrock credentials — cross-account to Mezmo (627029844476)
# These come from Instruqt team secrets (Settings > Secrets in the Instruqt UI).
# If Instruqt team secrets aren't available, you can hardcode fallback creds here:
#   BEDROCK_KEY="${BEDROCK_ACCESS_KEY_ID:-AKIA...}"
#   BEDROCK_SECRET="${BEDROCK_SECRET_ACCESS_KEY:-...}"
BEDROCK_KEY="${BEDROCK_ACCESS_KEY_ID:-}"
BEDROCK_SECRET="${BEDROCK_SECRET_ACCESS_KEY:-}"
echo "Bedrock key present: $([ -n "$BEDROCK_KEY" ] && echo 'yes' || echo 'no')"

# Run Terraform
echo "[5/5] Running Terraform..."
cd /opt/aura/terraform
terraform init -input=false 2>&1 || true

# Write Bedrock creds to tfvars file (more reliable than -var args)
if [ -n "$BEDROCK_KEY" ]; then
  cat > /opt/aura/terraform/bedrock.auto.tfvars <<TFVARS
bedrock_access_key_id     = "${BEDROCK_KEY}"
bedrock_secret_access_key = "${BEDROCK_SECRET}"
TFVARS
  echo "Wrote bedrock.auto.tfvars"
fi

echo "Running Terraform apply..."
terraform apply -auto-approve -input=false 2>&1 || {
  echo "WARNING: Terraform apply failed. Retrying in 10 seconds..."
  sleep 10
  terraform apply -auto-approve -input=false 2>&1 || true
}

# Export ALB DNS and config bucket
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "not-ready")
S3_BUCKET=$(terraform output -raw s3_config_bucket 2>/dev/null || echo "not-ready")
echo "export ALB_DNS=${ALB_DNS}" >> /root/.bashrc
echo "export S3_BUCKET=${S3_BUCKET}" >> /root/.bashrc
echo "export ALB_DNS=${ALB_DNS}" > /etc/profile.d/aura-demo.sh
echo "export S3_BUCKET=${S3_BUCKET}" >> /etc/profile.d/aura-demo.sh
chmod +x /etc/profile.d/aura-demo.sh 2>/dev/null || true

# Upload Terraform files to the sandbox S3 config bucket for IaC indexing
echo "Uploading Terraform files to S3 for IaC indexing..."
for f in /opt/aura/terraform/*.tf; do
  aws s3 cp "$f" "s3://${S3_BUCKET}/terraform/$(basename $f)" --quiet 2>/dev/null || true
done
echo "  Uploaded $(ls /opt/aura/terraform/*.tf 2>/dev/null | wc -l | tr -d ' ') .tf files"

# Wait for orchestrator (best-effort, don't fail setup if it's slow)
echo ""
echo "Waiting for Aura services to start..."
HEALTHY=false
for i in $(seq 1 30); do
  if curl -sf "http://${ALB_DNS}:3030/health" > /dev/null 2>&1; then
    echo "Orchestrator is healthy!"
    HEALTHY=true
    break
  fi
  echo "  Waiting for orchestrator... ($i/30)"
  sleep 10
done

if [ "$HEALTHY" = "false" ]; then
  echo "WARNING: Orchestrator not yet healthy. Services may still be starting."
fi

# Set up reverse proxy for OpenWebUI — Instruqt service tabs proxy to cloud-client ports
# nginx properly handles HTTP proxying with correct headers for SPA routing
echo "Setting up OpenWebUI proxy on port 3000..."
which nginx > /dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq nginx > /dev/null 2>&1) || true
if which nginx > /dev/null 2>&1 && [ "${ALB_DNS}" != "not-ready" ]; then
  cat > /etc/nginx/sites-available/openwebui << NGINX_CONF
server {
    listen 3000;
    location / {
        proxy_pass http://${ALB_DNS}:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
NGINX_CONF
  # Also serve TOML config files on port 8080 for the "Agent Config" tab
  cat >> /etc/nginx/sites-available/openwebui << NGINX_TOML

server {
    listen 8080;
    root /opt/aura/configs;
    autoindex on;
    default_type text/plain;

    location / {
        add_header Content-Type text/plain;
    }
}
NGINX_TOML

  ln -sf /etc/nginx/sites-available/openwebui /etc/nginx/sites-enabled/openwebui 2>/dev/null || true
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  nginx -t 2>/dev/null && nginx 2>/dev/null &
  echo "  OpenWebUI nginx proxy running on port 3000 → ${ALB_DNS}:3000"
  echo "  TOML config server running on port 8080"
else
  echo "  WARNING: nginx not available or ALB not ready. OpenWebUI tab may not work."
  # Fallback to socat
  which socat > /dev/null 2>&1 || (apt-get install -y -qq socat > /dev/null 2>&1) || true
  if which socat > /dev/null 2>&1; then
    nohup socat TCP-LISTEN:3000,fork,reuseaddr TCP:${ALB_DNS}:3000 > /dev/null 2>&1 &
    echo "  Fallback: socat proxy on port 3000"
  fi
fi

# Create log tail helper scripts for each agent
# These are used by the "Live Logs" terminal tabs in Instruqt
mkdir -p /opt/aura/logs
for agent in orchestrator incident-response change-audit post-mortem capacity-planning discovery-worker; do
  cat > /usr/local/bin/tail-${agent} << TAIL_SCRIPT
#!/bin/sh
export AWS_PAGER=""
echo "=== Live logs for ${agent} ==="
echo "Streaming from CloudWatch /ecs/bella-vista..."
echo ""
aws logs tail /ecs/bella-vista --follow --format short --filter-pattern "${agent}" --region us-east-1 2>/dev/null || \
  echo "Waiting for logs... (agent may still be starting)"
TAIL_SCRIPT
  chmod +x /usr/local/bin/tail-${agent}
done

# Also create a combined log tail
cat > /usr/local/bin/tail-aura << 'TAIL_ALL'
#!/bin/sh
export AWS_PAGER=""
echo "=== Live Aura logs ==="
echo "Streaming all agent logs from CloudWatch /ecs/bella-vista..."
echo ""
aws logs tail /ecs/bella-vista --follow --format short --region us-east-1 2>/dev/null || \
  echo "Waiting for logs... (services may still be starting)"
TAIL_ALL
chmod +x /usr/local/bin/tail-aura

echo ""
echo "=== Setup Complete ==="
echo "ALB: http://${ALB_DNS}"
echo "Orchestrator: http://${ALB_DNS}:3030"
echo "OpenWebUI: http://${ALB_DNS}:3000 (proxied on cloud-client:3000)"
echo "Config viewer: http://cloud-client:8080/"
echo "S3 Config Bucket: ${S3_BUCKET}"
echo ""
echo "Log tail commands: tail-orchestrator, tail-incident-response, tail-aura (all)"
echo "Setup log: $LOG"

# Always exit 0 — infrastructure is deployed, services may still be starting
exit 0
