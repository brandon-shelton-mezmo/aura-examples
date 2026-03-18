# Aura MCP Transport Issues — Engineering Report

**Date:** 2026-03-18
**Aura Version:** 1.14.5 (main branch, commit `e791a7e`)
**rmcp Version:** 0.12.0
**Tested Against:** `awslabs.aws-api-mcp-server` v1.3.21, `mcp-server-qdrant` v1.26.0
**Environment:** macOS, local Docker, Bedrock us-east-1

---

## Summary

Aura has two MCP transport issues that affect reliability when connecting to external
MCP servers. Both stem from the same root cause: **aura builds a new agent and creates
fresh MCP connections on every API request**, then tears them down when the request
completes. This per-request lifecycle creates race conditions and unnecessary latency.

A workaround using `mcp-proxy` is in place and achieves 100% reliability, but the
underlying issues should be addressed in aura for production readiness.

---

## Issue 1: stdio Transport — Process Exits Before Tool Calls Execute

### Symptom

MCP servers configured with `transport = "stdio"` connect successfully during
initialization (tools are discovered), but all subsequent tool calls fail with
`Transport closed`.

### Reproduction

```toml
[mcp.servers.aws_api]
transport = "stdio"
cmd = ["awslabs.aws-api-mcp-server"]
args = []
```

1. Start aura with the above config
2. Send a chat request that triggers a `call_aws` tool call
3. Tool call fails: `ToolCallError: MCP tool error: Tool returned an error: Transport closed`

### What We Observe in Logs

```
INFO  Spawning STDIO server: ["awslabs.aws-api-mcp-server"]
INFO  Connected to MCP server 'aws_api': AWS-API-MCP v3.1.1
INFO  Discovered 2 tools from 'aws_api'
INFO  aws_api - Connected successfully, 2 tools discovered
...
INFO  Streaming tool call: call_aws
WARN  Error while calling tool: ... MCP tool error: Tool returned an error: Transport closed
```

The MCP server initializes and tools are discovered. But by the time the LLM decides
to call a tool (a few seconds later, after Bedrock responds), the stdio child process
has exited or its transport has been closed.

### Root Cause

In `crates/aura-web-server/src/handlers.rs:121`:

```rust
/// Build a fresh agent for a request, applying headers_from_request mappings.
async fn build_agent_for_request(...)
```

This is called on **every API request** (line 188). The agent build spawns stdio
child processes for MCP servers, initializes them, discovers tools, then the agent
is used for the conversation. When the request completes, the agent is dropped,
which drops the MCP client, which drops the `TokioChildProcess` transport.

The issue is that the stdio child process lifetime is tied to the agent, which is
tied to the request. The child process may be cleaned up by Tokio's task scheduler
before the tool call response can be read back from the pipe. The `rmcp` crate's
`TokioChildProcess` creates the process with `kill_on_drop: false`, but the
transport's `Drop` implementation still closes the stdin/stdout pipes.

### Impact

- **All stdio MCP servers are unreliable** — tool initialization works but tool execution fails
- Tested with both `awslabs.aws-api-mcp-server` and `mcp-server-qdrant` in stdio mode
- Consistent failure across aura v1.13.2 and v1.14.5

---

## Issue 2: http_streamable Transport — Intermittent Connection Failures

### Symptom

MCP servers configured with `transport = "http_streamable"` sometimes fail to
initialize with `unexpected server response: empty sse stream`. When it works,
it works perfectly. When it fails, all tool calls for that request fail.

### Reproduction

```toml
[mcp.servers.aws_api]
transport = "http_streamable"
url = "http://localhost:8091/mcp"
```

1. Start the AWS MCP server in HTTP mode
2. Start aura
3. Send multiple requests — some succeed, some fail with empty SSE stream

### What We Observe in Logs (Failure Case)

```
INFO  Creating streamable HTTP MCP client for: http://localhost:8091/mcp
DEBUG received message before initialize response; continuing to drain stream
      Error(JsonRpcError { code: -32602, message: "Invalid request parameters" })
ERROR worker quit with fatal: unexpected server response: empty sse stream,
      when process initialize response
WARN  HTTP Streamable MCP connection failed
INFO  aws_api - Connected successfully, 0 tools discovered
```

### What We Observe (Success Case)

```
INFO  Creating streamable HTTP MCP client for: http://localhost:8091/mcp
INFO  Service initialized as client
      peer_info = InitializeResult { server_info: "AWS-API-MCP" v3.1.1 }
INFO  Successfully established streamable HTTP MCP client
INFO  Discovered 2 tools from HTTP streamable server 'aws_api'
```

### Root Cause

Same per-request agent build. The `rmcp` client sends an `initialize` request to the
MCP server's streamable-http endpoint. The server responds with an SSE stream containing
the initialize result. Sometimes `rmcp` reads the stream before the server has written
the response event, sees an empty stream, and gives up.

This is a race condition between:
- `rmcp` opening the SSE stream and reading events
- The MCP server processing the initialize request and writing the response event

The `mcp-server-qdrant` is less affected because it responds faster (simpler server,
no AWS SDK initialization). The `awslabs.aws-api-mcp-server` has more startup work
(loading awscli, creating working directories), making the race window larger.

### Impact

- Intermittent — works ~70-90% of the time when servers are warm
- Fails more often on cold start or under load
- Once a connection fails for a request, all tool calls for that request fail
- The next request may succeed (new connection attempt)

---

## Root Cause: Per-Request Agent Build

Both issues trace back to `build_agent_for_request()` in `handlers.rs`:

```
Request arrives
  → build_agent_for_request()
    → RigBuilder::new(config)
    → builder.build_agent_with_headers()
      → For each MCP server:
        → Connect (stdio: spawn process / http: SSE handshake)
        → Initialize (MCP protocol)
        → Discover tools
      → Build agent with tools
  → Run conversation (LLM + tool calls)
  → Drop agent
    → Drop MCP connections
    → (stdio: pipes close, process may be killed)
    → (http: SSE stream closed, session deleted)
```

This happens on **every request**. There is no connection pooling, agent caching,
or MCP session reuse. The reason is the `headers_from_request` feature — per-request
auth headers need to be forwarded to MCP servers, which requires per-request connections.

### Suggested Fix Options

**Option A: Connection Pool for Static MCP Servers**

For MCP servers that don't use `headers_from_request`, maintain a pool of pre-initialized
connections. On request, grab a connection from the pool instead of creating a new one.
Only create fresh connections for servers that need per-request headers.

```rust
// Pseudocode
if server.headers_from_request.is_empty() {
    // Use pooled connection (initialized once, reused across requests)
    pool.get_or_create(server_name)
} else {
    // Create fresh connection with per-request headers
    connect_fresh(server_config, request_headers)
}
```

**Option B: Pre-Built Agent with Lazy Header Injection**

Build the agent once at startup (or on first request), cache it in `AppState`, and
inject per-request headers at the tool-call level rather than the connection level.

**Option C: MCP Session Keep-Alive**

For http_streamable, don't delete the session after each request. Reuse the
`mcp-session-id` across requests to the same server. This avoids re-initialization.

**Option D: Retry with Backoff on Connection Failure**

If the SSE stream is empty on initialize, retry 2-3 times with a short backoff
(100ms, 200ms, 400ms) before giving up. This would make the intermittent
http_streamable failures transparent to the user.

---

## Current Workaround: mcp-proxy

We use `mcp-proxy` (PyPI package) to bridge the AWS MCP server:

```
aura (http_streamable) → mcp-proxy (http) → AWS MCP server (stdio, persistent)
```

`mcp-proxy` spawns the AWS MCP server as a stdio child process **once at startup**
and keeps it alive. It exposes a streamable-http endpoint that aura connects to
per-request. Because the underlying stdio connection is persistent, the initialization
race condition doesn't apply — the server is already initialized.

### Reliability Test Results

| Approach | 5/5 Requests | Notes |
|----------|-------------|-------|
| stdio (direct) | 0/5 | Transport closed on every tool call |
| http_streamable (direct) | 3-5/5 | Intermittent; depends on server warmth |
| http_streamable (via mcp-proxy) | **5/5** | 100% reliable |

### How to Use

```bash
# Install
pip install mcp-proxy awslabs.aws-api-mcp-server

# Run proxy (keeps AWS MCP server alive persistently)
mcp-proxy --transport streamablehttp --host 0.0.0.0 --port 8091 \
  -e READ_OPERATIONS_ONLY true \
  -e AWS_REGION us-east-1 \
  -e AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY \
  -- awslabs.aws-api-mcp-server
```

Aura config:
```toml
[mcp.servers.aws_api]
transport = "http_streamable"
url = "http://localhost:8091/mcp"
```

### Limitation

This workaround adds another process to manage. The proper fix is in aura's
MCP connection lifecycle.

---

## Full Debugging Timeline — Everything We Tried

This section documents every approach tested during the debugging session on 2026-03-18,
in chronological order. Each entry includes what was tried, what happened, and what we
learned. Use this to reproduce any finding or to avoid re-testing dead ends.

### Step 1: Validate MCP Servers Work Independently

**What:** Installed both MCP servers via `uv tool install` and tested with the MCP inspector.

```bash
# Install servers as persistent tools
uv tool install awslabs.aws-api-mcp-server
uv tool install mcp-server-qdrant

# Test with MCP inspector
npx @modelcontextprotocol/inspector --cli --method tools/list \
  ~/.local/bin/awslabs.aws-api-mcp-server

npx @modelcontextprotocol/inspector --cli --method tools/list \
  ~/.local/bin/mcp-server-qdrant
```

**Result:** Both servers installed and worked perfectly via inspector. AWS MCP exposed
`call_aws` and `suggest_aws_commands`. Qdrant MCP exposed `qdrant-store` and `qdrant-find`.
`collection_name` confirmed as required parameter on both Qdrant tools.

**Learned:** The MCP servers themselves are fine. The `awslabs.aws-api-mcp-server` bundles
its own `awscli` as a Python dependency — the host `aws` CLI is not needed.

### Step 2: Test stdio Transport with Aura v1.13.2

**What:** Started aura (v1.13.2, pre-existing build) with stdio transport config for both servers.

```toml
[mcp.servers.aws_api]
transport = "stdio"
cmd = ["awslabs.aws-api-mcp-server"]
args = []

[mcp.servers.qdrant]
transport = "stdio"
cmd = ["mcp-server-qdrant"]
args = []
```

```bash
CONFIG_PATH=aws-discovery-agent.toml aura-web-server
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Use call_aws to run aws sts get-caller-identity"}]}'
```

**Result:** Both MCP servers connected, 4 tools discovered. But every `call_aws` tool
call failed with `Transport closed`. The connection initialized but died before execution.

**Log evidence:**
```
INFO  Discovered 2 tools from 'aws_api'
INFO  aws_api - Connected successfully, 2 tools discovered
INFO  Streaming tool call: call_aws
WARN  Error while calling tool: ... Transport closed
```

**Learned:** stdio transport has a lifecycle bug — process dies between init and tool calls.

### Step 3: Rebuild Aura from Latest Main (v1.14.5)

**What:** Checked if the bug was fixed in newer aura. Main was at v1.14.5 vs built v1.13.2.

```bash
cd ~/Documents/GitHub/aura
git checkout main
cargo build --release --bin aura-web-server
# Built v1.14.5
```

**Result:** Same stdio failure on v1.14.5. No fix between versions.

**Learned:** Not a version-specific issue. The bug exists in the current main branch.

### Step 4: Try stdio with Direct Binary Path (Not uvx)

**What:** Tested if the issue was `uvx` wrapper vs direct binary execution.

```toml
[mcp.servers.aws_api]
transport = "stdio"
cmd = ["/Users/brandon.shelton/.local/bin/awslabs.aws-api-mcp-server"]
```

**Result:** Same failure. Tools discovered, `Transport closed` on execution.

**Learned:** Not a uvx issue. The stdio lifecycle bug affects direct binaries too.

### Step 5: Start MCP Servers in HTTP Mode Manually

**What:** Started both MCP servers as standalone HTTP services and connected aura via
`http_streamable` transport.

```bash
# AWS MCP in HTTP mode
AWS_API_MCP_TRANSPORT=streamable-http AWS_API_MCP_PORT=8090 \
  AUTH_TYPE=no-auth READ_OPERATIONS_ONLY=true \
  awslabs.aws-api-mcp-server

# Qdrant MCP in HTTP mode
QDRANT_URL=http://localhost:6333 COLLECTION_NAME=aws_resources \
  mcp-server-qdrant --transport streamable-http
```

```toml
[mcp.servers.aws_api]
transport = "http_streamable"
url = "http://127.0.0.1:8090/mcp"

[mcp.servers.qdrant]
transport = "http_streamable"
url = "http://127.0.0.1:8000/mcp"
```

**Result:** First test worked! `call_aws` executed successfully, discovered S3 buckets (78),
Lambda functions (19), VPCs (28), and stored results in Qdrant. Subsequent tests were
intermittent — sometimes 0 tools discovered for `aws_api` while `qdrant` always worked.

**Learned:** http_streamable works but is flaky for the AWS MCP server. Qdrant is
consistently reliable on the same transport.

### Step 6: Investigate Why Qdrant Works but AWS Doesn't

**What:** Compared response times and response formats between the two servers.

```bash
# Response time comparison
time curl -s -o /dev/null -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{...}}'
# Qdrant: 59ms

time curl -s -o /dev/null -X POST http://localhost:8091/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{...}}'
# AWS: 25ms
```

**Result:** Both fast when warm. Both return `content-type: text/event-stream` with
`Transfer-Encoding: chunked`. Qdrant has a 307 redirect from `/mcp` to `/mcp/` but
otherwise identical format.

**Learned:** Response format is identical. The flakiness is a race condition in rmcp's
SSE stream reading, not a format incompatibility.

### Step 7: Intercept Exact HTTP Traffic with Proxy

**What:** Built a Python HTTP interceptor to capture the exact request aura sends and the
exact response the AWS MCP server returns.

```python
# Interceptor proxy on :8090 forwarding to AWS MCP on :8091
class InterceptHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        # Log request headers and body
        # Forward to real server
        # Log response
```

**Result:** Captured the exact exchange:

Request from aura (rmcp):
```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-03-26",
    "capabilities": {},
    "clientInfo": {"name": "rmcp", "version": "0.12.0"}
  }
}
```

Response from AWS MCP:
```
HTTP 200 OK
content-type: text/event-stream
mcp-session-id: c19956c30a034c33b0a432b1abbf1fcd

event: message
data: {"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2025-03-26",...}}
```

**Learned:** The request format is correct and the server responds successfully. The
issue is in rmcp's SSE stream parsing — it sometimes reads the stream before the event
data arrives and reports "empty sse stream."

### Step 8: Check Protocol Version Compatibility

**What:** Verified that the protocol versions match between rmcp and the MCP servers.

```
rmcp 0.12.0:       sends "2025-03-26" (LATEST in rmcp)
AWS MCP server:    supports ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
Qdrant MCP server: supports "2025-03-26"
```

**Result:** `2025-03-26` is supported by all parties. Not a version mismatch.

**Learned:** Protocol versions are compatible. Eliminated version mismatch as a cause.

### Step 9: Check for Configuration Options in Aura

**What:** Searched aura source for any config to cache agents, pool connections, or keep
MCP sessions alive.

```rust
// handlers.rs:121
/// Build a fresh agent for a request, applying headers_from_request mappings.
async fn build_agent_for_request(...)

// handlers.rs:188
let agent = match build_agent_for_request(&data.config, req_headers_map).await {
```

**Result:** No configuration option exists. Per-request agent build is hardcoded. `AppState`
stores only config and server settings, no agent cache.

**Learned:** Cannot fix this from the config side. Requires aura source change.

### Step 10: Test mcp-proxy as Bridge

**What:** Used `mcp-proxy` to wrap the AWS MCP server (stdio) and expose it as
streamable-http. The proxy maintains a persistent connection to the AWS MCP server.

```bash
uvx mcp-proxy \
  --transport streamablehttp \
  --host 127.0.0.1 --port 9090 \
  -e READ_OPERATIONS_ONLY true \
  -e AWS_REGION us-east-1 \
  -e AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY \
  -- awslabs.aws-api-mcp-server
```

```toml
[mcp.servers.aws_api]
transport = "http_streamable"
url = "http://127.0.0.1:9090/mcp"
```

**Result:** 5/5 requests succeeded. 100% reliable.

**Learned:** mcp-proxy solves both issues because it maintains a persistent stdio
connection to the AWS MCP server (no per-request reconnection) and exposes a clean
HTTP endpoint that rmcp can connect to per-request without the SSE race condition.

### Step 11: Reliability Comparison Test

**What:** Ran 5 consecutive identical requests against three configurations.

```bash
# Same request for all three:
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Use call_aws with cli_command \"aws sts get-caller-identity\" and tell me the account ID."}]}'
```

**Results:**

| Config | Request 1 | Request 2 | Request 3 | Request 4 | Request 5 | Rate |
|--------|-----------|-----------|-----------|-----------|-----------|------|
| stdio (direct) | FAIL | FAIL | FAIL | FAIL | FAIL | 0% |
| http_streamable (direct, warm) | OK | OK | OK | OK | OK | 100% |
| http_streamable (direct, cold) | FAIL | OK | FAIL | OK | OK | 60% |
| http_streamable (via mcp-proxy) | OK | OK | OK | OK | OK | 100% |

**Learned:** Direct http_streamable works when the server is warm (already handled a
request recently) but fails on cold connections. mcp-proxy eliminates cold-start issues
because the underlying connection is always warm.

### Step 12: Verified Full Discovery Pipeline Works

**What:** With mcp-proxy in place, ran a full discovery scan.

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Discover S3 buckets using call_aws with cli_command \"aws s3api list-buckets\". Then store a summary in qdrant with collection_name aws_resources."}]}'
```

**Result:** Discovered 78 S3 buckets, categorized them, and stored in Qdrant.
Full `call_aws` → process → `qdrant-store` pipeline confirmed working.

**Learned:** The complete agent workflow functions correctly once the transport is reliable.

---

## How to Reproduce

### Prerequisites

```bash
# 1. Build aura from main
cd ~/Documents/GitHub/aura
git checkout main
cargo build --release --bin aura-web-server

# 2. Install MCP servers
uv tool install awslabs.aws-api-mcp-server
uv tool install mcp-server-qdrant
pip install mcp-proxy  # or: uvx mcp-proxy (for workaround)

# 3. Start Qdrant
docker run -d --name qdrant -p 6333:6333 qdrant/qdrant:latest

# 4. Set AWS credentials
export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
export AWS_REGION=us-east-1
```

### Reproduce Issue 1 (stdio Transport closed)

```bash
# Create config
cat > /tmp/test-stdio.toml << 'EOF'
[llm]
provider = "bedrock"
model = "us.anthropic.claude-sonnet-4-20250514-v1:0"
region = "us-east-1"

[agent]
name = "test"
temperature = 0.3
turn_depth = 5
system_prompt = "Use call_aws to run AWS commands."

[mcp.servers.aws_api]
transport = "stdio"
cmd = ["awslabs.aws-api-mcp-server"]
args = []
description = "AWS API"

[mcp.servers.aws_api.env]
AWS_REGION = "us-east-1"
AWS_ACCESS_KEY_ID = "YOUR_KEY"
AWS_SECRET_ACCESS_KEY = "YOUR_SECRET"
READ_OPERATIONS_ONLY = "true"
EOF

# Start aura
CONFIG_PATH=/tmp/test-stdio.toml RUST_LOG=info aura-web-server &
sleep 5

# Send request — will fail with Transport closed
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Use call_aws with cli_command \"aws sts get-caller-identity\""}]}'

# Check logs for "Transport closed"
# Expected: tools discovered, then Transport closed on execution
```

### Reproduce Issue 2 (http_streamable intermittent)

```bash
# Start AWS MCP server in HTTP mode
AWS_API_MCP_TRANSPORT=streamable-http AWS_API_MCP_PORT=8091 \
  AUTH_TYPE=no-auth READ_OPERATIONS_ONLY=true \
  awslabs.aws-api-mcp-server &
sleep 5

# Create config
cat > /tmp/test-http.toml << 'EOF'
[llm]
provider = "bedrock"
model = "us.anthropic.claude-sonnet-4-20250514-v1:0"
region = "us-east-1"

[agent]
name = "test"
temperature = 0.3
turn_depth = 5
system_prompt = "Use call_aws to run AWS commands."

[mcp.servers.aws_api]
transport = "http_streamable"
url = "http://127.0.0.1:8091/mcp"
description = "AWS API"
EOF

# Start aura
CONFIG_PATH=/tmp/test-http.toml RUST_LOG=info aura-web-server &
sleep 5

# Send 10 requests in a row — some will fail, some succeed
for i in $(seq 1 10); do
  RESULT=$(curl -s http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Use call_aws with cli_command \"aws sts get-caller-identity\""}]}' | \
    python3 -c "import sys,json; d=json.load(sys.stdin); c=d['choices'][0]['message']['content']; print('OK' if '627' in c else 'FAIL')" 2>&1)
  echo "Request $i: $RESULT"
done

# Expected: mix of OK and FAIL, especially if server was just started
# Check logs for "empty sse stream" on failures
```

### Verify Workaround (mcp-proxy)

```bash
# Start mcp-proxy wrapping AWS MCP
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8091 \
  -e READ_OPERATIONS_ONLY true \
  -e AWS_REGION us-east-1 \
  -e AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY \
  -- awslabs.aws-api-mcp-server &
sleep 8

# Same config as Issue 2, same url
CONFIG_PATH=/tmp/test-http.toml RUST_LOG=info aura-web-server &
sleep 5

# Send 10 requests — all should succeed
for i in $(seq 1 10); do
  RESULT=$(curl -s http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Use call_aws with cli_command \"aws sts get-caller-identity\""}]}' | \
    python3 -c "import sys,json; d=json.load(sys.stdin); c=d['choices'][0]['message']['content']; print('OK' if '627' in c else 'FAIL')" 2>&1)
  echo "Request $i: $RESULT"
done

# Expected: 10/10 OK
```

---

## Affected Components

| File | Description |
|------|-------------|
| `crates/aura-web-server/src/handlers.rs:121` | `build_agent_for_request()` — per-request agent creation |
| `crates/aura-web-server/src/handlers.rs:188` | Call site — every request builds fresh |
| `crates/aura/src/mcp.rs:468-533` | `try_connect_stdio()` — stdio child process spawning |
| `crates/aura/src/mcp_streamable_http.rs` | HTTP streamable client connection |
| `crates/aura/src/builder.rs:460-489` | Tool registration from MCP connections |
| `Cargo.toml` | `rmcp = "0.12.0"` — the MCP client library |

## Test Environment

- Aura v1.14.5 built from `main` (commit `e791a7e`)
- `awslabs.aws-api-mcp-server` v1.3.21 (uses FastMCP 3.1.1, MCP protocol 2025-11-25)
- `mcp-server-qdrant` v1.26.0 (MCP protocol 2025-03-26)
- `rmcp` v0.12.0 (MCP protocol 2025-03-26)
- `mcp-proxy` latest (bridges stdio ↔ streamable-http)
- macOS Darwin 24.6.0, Docker Desktop, AWS Bedrock us-east-1
