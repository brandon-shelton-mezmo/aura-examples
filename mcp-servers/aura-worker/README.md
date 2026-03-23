# Aura Worker MCP Server

An MCP server that wraps aura's `/v1/chat/completions` API, enabling an orchestrator
agent to delegate work to worker agent instances. Each worker call gets a fresh aura
request with a clean context window.

This solves the context accumulation problem: instead of one agent filling its context
with raw AWS data across many tool calls, the orchestrator dispatches short tasks to
workers. Workers store full results in Qdrant and return only summaries. The
orchestrator's context stays small no matter how many resources are discovered.

## Tools

| Tool | Purpose |
|------|---------|
| `run_agent` | Send a single prompt to a worker and return the response. |
| `run_agents_parallel` | Send multiple prompts in parallel with staggered starts and concurrency control. |
| `check_worker` | Verify a worker instance is running and responsive. |
| `retry_incomplete` | Check Qdrant for gaps, retry missing service types sequentially. |

### run_agents_parallel

The primary tool for discovery. Sends N prompts to the worker aura instance in
parallel, with staggered starts and a concurrency semaphore to respect Bedrock
rate limits. Each worker gets a fresh context window.

The orchestrator typically dispatches 2 batches of 5 workers:

```
Batch 1: VPCs, EC2 instances, S3 buckets, Lambda functions, IAM roles
Batch 2: Security groups, subnets, load balancers, Route53, CloudFormation
```

### retry_incomplete

After the parallel batches, this tool queries Qdrant to see which service types
have stored resources and which are missing. Missing services are retried
sequentially with delays between each attempt.

## How to Run

The server runs in stdio mode. Use `mcp-proxy` to expose it over HTTP for aura's
`http_streamable` transport.

```bash
# Install dependencies
pip install "mcp[cli]" httpx

# Start the worker aura instance first (port 8080)
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml aura-web-server &

# Run via mcp-proxy (exposes as http_streamable on port 8095)
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8095 \
  -e AURA_WORKER_URL http://127.0.0.1:8080 \
  -- uv run mcp-servers/aura-worker/server.py
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AURA_WORKER_URL` | `http://localhost:8080` | Base URL of the worker aura instance |
| `WORKER_TIMEOUT` | `300` | Timeout per worker request (seconds) |
| `MAX_PARALLEL` | `10` | Maximum parallel worker requests |
| `MAX_RESPONSE_LENGTH` | `1500` | Max chars returned per worker (full data is in Qdrant) |

### Throttling Configuration

These settings control how aggressively the server hits Bedrock. Too many concurrent
requests causes "Too many tokens" rate limit errors.

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_CONCURRENT` | `2` | Max simultaneous requests to the worker (semaphore size) |
| `DELAY_BETWEEN_WORKERS` | `5.0` | Seconds between staggered task starts |
| `MAX_RETRIES` | `3` | Retry count on rate limit errors |
| `RETRY_BASE_DELAY` | `15.0` | Base delay between retries (multiplied by attempt number) |

The default settings (`MAX_CONCURRENT=2`, `DELAY_BETWEEN_WORKERS=5.0`) are tuned
for Bedrock Claude Sonnet with standard rate limits. If you have higher limits or
use OpenAI, you can increase `MAX_CONCURRENT` and decrease the delays.

## Response Truncation

Worker responses are truncated to `MAX_RESPONSE_LENGTH` (default 1500 chars) before
returning to the orchestrator. This is intentional -- workers store full data in
Qdrant, so the orchestrator only needs summaries to coordinate. Truncation keeps the
orchestrator's context small even after many worker dispatches.

## Architecture Context

```
Orchestrator (port 3030)
  |
  |-- aura-worker MCP (port 8095) ----> Worker Aura (port 8080)
  |                                       |
  |                                       |-- aura-qdrant MCP (port 8000) --> Qdrant (6333)
  |                                       |-- AWS MCP (port 8091) ----------> AWS APIs
  |
  |-- aura-qdrant MCP (port 8000) -----> Qdrant (6333)
```

The orchestrator delegates via the worker MCP. Workers have their own MCP connections
to the Qdrant and AWS servers. The orchestrator also connects to Qdrant directly for
post-discovery synthesis and queries.
