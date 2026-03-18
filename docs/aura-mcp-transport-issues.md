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
