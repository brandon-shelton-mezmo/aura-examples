#!/bin/bash
# setup-ecr.sh — Create ECR repos, set cross-account policies, build and push images
#
# Run this ONCE from the Mezmo account (627029844476) to set up all Docker images
# that Instruqt managed sandbox accounts will pull.
#
# Prerequisites:
#   - AWS CLI configured with 627029844476 credentials
#   - Docker running locally
#   - Aura source built: ~/Documents/GitHub/aura/target/release/aura-web-server
#
# Usage:
#   cd aura-examples
#   ./demo/scripts/setup-ecr.sh

set -euo pipefail

ACCOUNT_ID="627029844476"
REGION="us-east-1"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# ECR repos to create
REPOS=(
  "aura-demo/aura"
  "aura-demo/qdrant-mcp"
  "aura-demo/worker-mcp"
  "aura-demo/aws-api-mcp"
)

# Cross-account pull policy — allows any account to pull (images aren't sensitive)
CROSS_ACCOUNT_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossAccountPull",
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ]
    }
  ]
}'

echo "=== ECR Setup for Aura Demo ==="
echo "Account: ${ACCOUNT_ID}"
echo "Region:  ${REGION}"
echo ""

# Authenticate Docker to ECR
echo "Authenticating Docker to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$REGISTRY"

# Create repos and set policies
for repo in "${REPOS[@]}"; do
  echo ""
  echo "--- Repo: ${repo} ---"

  # Create repo (ignore if exists)
  aws ecr create-repository \
    --repository-name "$repo" \
    --region "$REGION" \
    --image-scanning-configuration scanOnPush=false \
    2>/dev/null || echo "  (already exists)"

  # Set cross-account pull policy
  aws ecr set-repository-policy \
    --repository-name "$repo" \
    --region "$REGION" \
    --policy-text "$CROSS_ACCOUNT_POLICY"
  echo "  Cross-account pull policy set"
done

# Also set policy on existing restaurant-app repo (Bella Vista)
echo ""
echo "--- Repo: restaurant-app (Bella Vista) ---"
aws ecr set-repository-policy \
  --repository-name "restaurant-app" \
  --region "$REGION" \
  --policy-text "$CROSS_ACCOUNT_POLICY" 2>/dev/null || echo "  (repo may not exist yet)"

echo ""
echo "=== Building and Pushing Images ==="

DEMO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$DEMO_DIR/.." && pwd)"

# Build and push: qdrant-mcp
echo ""
echo "--- Building aura-demo/qdrant-mcp ---"
cp "$PROJECT_ROOT/mcp-servers/aura-qdrant/server.py" "$DEMO_DIR/docker/qdrant-mcp/server.py"
cp "$PROJECT_ROOT/mcp-servers/aura-qdrant/requirements.txt" "$DEMO_DIR/docker/qdrant-mcp/requirements.txt"
docker build --platform linux/amd64 -t "${REGISTRY}/aura-demo/qdrant-mcp:latest" "$DEMO_DIR/docker/qdrant-mcp"
docker push "${REGISTRY}/aura-demo/qdrant-mcp:latest"
rm "$DEMO_DIR/docker/qdrant-mcp/server.py" "$DEMO_DIR/docker/qdrant-mcp/requirements.txt"
echo "  Pushed ${REGISTRY}/aura-demo/qdrant-mcp:latest"

# Build and push: worker-mcp
echo ""
echo "--- Building aura-demo/worker-mcp ---"
cp "$PROJECT_ROOT/mcp-servers/aura-worker/server.py" "$DEMO_DIR/docker/worker-mcp/server.py"
cp "$PROJECT_ROOT/mcp-servers/aura-worker/requirements.txt" "$DEMO_DIR/docker/worker-mcp/requirements.txt"
docker build --platform linux/amd64 -t "${REGISTRY}/aura-demo/worker-mcp:latest" "$DEMO_DIR/docker/worker-mcp"
docker push "${REGISTRY}/aura-demo/worker-mcp:latest"
rm "$DEMO_DIR/docker/worker-mcp/server.py" "$DEMO_DIR/docker/worker-mcp/requirements.txt"
echo "  Pushed ${REGISTRY}/aura-demo/worker-mcp:latest"

# Build and push: aws-api-mcp
echo ""
echo "--- Building aura-demo/aws-api-mcp ---"
docker build --platform linux/amd64 -t "${REGISTRY}/aura-demo/aws-api-mcp:latest" "$DEMO_DIR/docker/aws-api-mcp"
docker push "${REGISTRY}/aura-demo/aws-api-mcp:latest"
echo "  Pushed ${REGISTRY}/aura-demo/aws-api-mcp:latest"

# Build and push: aura (requires aura source)
echo ""
echo "--- Building aura-demo/aura ---"
AURA_SRC="$HOME/Documents/GitHub/aura"
if [ -f "$AURA_SRC/Dockerfile" ]; then
  docker build --platform linux/amd64 -t "${REGISTRY}/aura-demo/aura:latest" "$AURA_SRC"
  docker push "${REGISTRY}/aura-demo/aura:latest"
  echo "  Pushed ${REGISTRY}/aura-demo/aura:latest"
elif [ -f "$AURA_SRC/target/release/aura-web-server" ]; then
  echo "  No Dockerfile found. Creating minimal image from binary..."
  cat > /tmp/aura-dockerfile << 'DOCKERFILE'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY target/release/aura-web-server /app/aura-web-server
ENV CONFIG_PATH=/app/config.toml
EXPOSE 3030
HEALTHCHECK --interval=10s --timeout=3s --retries=5 --start-period=10s \
  CMD curl -sf http://localhost:3030/health || exit 1
ENTRYPOINT ["/app/aura-web-server"]
DOCKERFILE
  docker build --platform linux/amd64 -t "${REGISTRY}/aura-demo/aura:latest" -f /tmp/aura-dockerfile "$AURA_SRC"
  docker push "${REGISTRY}/aura-demo/aura:latest"
  rm /tmp/aura-dockerfile
  echo "  Pushed ${REGISTRY}/aura-demo/aura:latest"
else
  echo "  WARNING: Aura source not found at $AURA_SRC"
  echo "  Skipping aura image build. Push manually:"
  echo "    docker build -t ${REGISTRY}/aura-demo/aura:latest ~/Documents/GitHub/aura"
  echo "    docker push ${REGISTRY}/aura-demo/aura:latest"
fi

echo ""
echo "=== Summary ==="
echo "Images pushed to ${REGISTRY}:"
for repo in "${REPOS[@]}"; do
  echo "  ${REGISTRY}/${repo}:latest"
done
echo "  ${REGISTRY}/restaurant-app:latest (Bella Vista — if previously pushed)"
echo ""
echo "Cross-account pull policy set on all repos."
echo "Any AWS account can now pull these images."
