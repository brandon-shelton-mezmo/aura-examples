# Quick Start -- AWS Infrastructure Discovery

See your entire AWS environment mapped out with one prompt: "Discover my AWS environment."

The orchestrator agent dispatches 10 parallel workers (2 batches of 5) that call AWS
directly and store results in Qdrant. No data passes through the LLM context window.
Result: 363 individual resources, 10 service types, 0 duplicates.

## Prerequisites

- **AWS credentials** with read-only access
- **Docker** (for Qdrant)
- **Python 3.11+** and **uv** (`pip install uv`)
- **aura-web-server** binary (built from `~/Documents/GitHub/aura`)
- **mcp-proxy** (`pip install mcp-proxy`)

## Step 1: Set credentials

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="wJalr..."
export AWS_REGION="us-east-1"
```

## Step 2: Start Qdrant

```bash
docker run -d --name qdrant -p 6333:6333 -v qdrant_data:/qdrant/storage qdrant/qdrant
```

## Step 3: Start custom Qdrant MCP (port 8000)

```bash
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8000 \
  -e QDRANT_URL http://localhost:6333 \
  -- uv run mcp-servers/aura-qdrant/server.py &
```

## Step 4: Start AWS MCP (port 8091)

```bash
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8091 \
  -e READ_OPERATIONS_ONLY true -e AWS_REGION $AWS_REGION \
  -e AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY \
  -- awslabs.aws-api-mcp-server &
```

## Step 5: Start worker aura (port 8080)

```bash
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml aura-web-server &
```

## Step 6: Start worker MCP (port 8095)

```bash
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8095 \
  -e AURA_WORKER_URL http://127.0.0.1:8080 \
  -- uv run mcp-servers/aura-worker/server.py &
```

## Step 7: Start orchestrator aura (port 3030)

```bash
CONFIG_PATH=examples/mcp-servers/aws/aws-orchestrator-agent.toml aura-web-server --port 3030 &
```

## Step 8: Run discovery

```bash
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Discover my AWS environment"}]}'
```

The orchestrator dispatches 2 batches of 5 workers. Each worker calls `discover_and_store`
which hits AWS via boto3 and writes directly to Qdrant. Expect ~363 resources across
10 service types in about 2-3 minutes.

## Step 9: Query the knowledge base

```bash
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What ECS services are running?"}]}'
```

## What Next

- [Architecture overview](orchestrator-architecture.md) -- how orchestrator + workers + custom MCPs fit together
- [AWS agent README](../examples/mcp-servers/aws/README.md) -- full agent inventory and gradual adoption path
- [Custom Qdrant MCP](../mcp-servers/aura-qdrant/README.md) -- the discover_and_store tool and 12 supported service types
- [Custom Worker MCP](../mcp-servers/aura-worker/README.md) -- throttling config and agent delegation
