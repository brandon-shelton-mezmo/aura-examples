# Quick Start -- AWS Infrastructure Discovery

See your entire AWS environment mapped out in under 15 minutes.

## Prerequisites

- **AWS credentials** with read access (access key ID + secret access key)
- **Docker** and **Docker Compose** installed

## Step 1: Clone the repo
```bash
git clone https://github.com/mezmo/aura-examples.git
cd aura-examples
```

## Step 2: Set AWS credentials
```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="wJalr..."
export AWS_REGION="us-east-1"
```
Read-only access is sufficient. The agent enforces `READ_OPERATIONS_ONLY=true`.

## Step 3: Start services
```bash
docker compose -f examples/mcp-servers/aws/docker-compose.yml up -d
```
Starts Qdrant (vector DB) and the Aura agent on port 3030.

## Step 4: Run preflight
```bash
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Run preflight checks and recommend agent configuration."}]}'
```
Validates AWS credentials, MCP server connections, and Qdrant health.

## Step 5: Run discovery
```bash
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Discover and catalog all resources in this AWS environment."}]}'
```
Scans VPCs, EC2, ECS, Lambda, RDS, S3, and more. Stores everything in Qdrant.

## Step 6: Ask a question
```bash
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What ECS services are running?"}]}'
```
Searches the knowledge base first, then queries AWS for anything missing.

## What Next

See [examples/mcp-servers/aws/README.md](../examples/mcp-servers/aws/README.md) for the gradual adoption path: preflight, scoped discovery, incident response, change audit, capacity planning, and postmortem agents.
