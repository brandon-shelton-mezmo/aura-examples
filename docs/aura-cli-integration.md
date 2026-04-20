# Aura CLI Integration

Connect the [aura-cli](~/Documents/GitHub/aura-cli) terminal client to aura-web-server
for interactive, streaming conversations with aura agents.

aura-cli is a Rust-based interactive REPL that speaks the OpenAI-compatible
`/v1/chat/completions` API. It adds local tool execution, conversation persistence,
token tracking, and a rich terminal UI on top of any running aura instance.

## Prerequisites

- **Rust 1.78+** (Cargo.lock v4 requires this; run `rustup update stable`)
- **aura-web-server** binary (built from `~/Documents/GitHub/aura`)
- **aura-cli** source at `~/Documents/GitHub/aura-cli`

## Build

```bash
cd ~/Documents/GitHub/aura-cli
cargo build --release
# Binary: target/release/aura-cli
```

Optional — add to PATH:

```bash
cp ~/Documents/GitHub/aura-cli/target/release/aura-cli /usr/local/bin/
```

## Configure

aura-cli resolves config in this order (highest priority first):

1. CLI flags (`--api-url`, `--api-key`, `--model`)
2. Environment variables (`AURA_AGENT_API_URL`, `AURA_AGENT_API_KEY`, `AURA_AGENT_MODEL`)
3. Config file (`~/.aura/config.toml`)
4. Defaults (`http://localhost:8080`, no auth, no model override)

### Minimal config file

```bash
mkdir -p ~/.aura
cat > ~/.aura/config.toml << 'EOF'
api_url = "http://localhost:8080"
EOF
```

### Environment variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `AURA_AGENT_API_URL` | Base URL of aura-web-server | `http://localhost:8080` |
| `AURA_AGENT_API_KEY` | Bearer token (if auth required) | none |
| `AURA_AGENT_MODEL` | Model override (omitted if unset) | none |
| `AURA_CLI_EXTRA_HEADERS` | Custom HTTP headers (`key:value,key:value`) | none |

## Start the Server (with CLI-friendly flags)

The CLI works against any running aura-web-server, but to get full visibility into
what the agent is doing (tool calls, execution times, reasoning), the server must
emit custom aura events.

**Required server flags for full CLI experience:**

```bash
AURA_CUSTOM_EVENTS=true \
TOOL_RESULT_MODE=aura \
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml \
  aura-web-server
```

| Server Flag | Purpose | Without It |
|-------------|---------|------------|
| `AURA_CUSTOM_EVENTS=true` | Emits `aura.tool_requested`, `aura.tool_start`, `aura.tool_complete` SSE events | `/stream` panel only shows generic chunk IDs |
| `TOOL_RESULT_MODE=aura` | Streams tool results inline via SSE | Tool execution appears as silent gaps |

### Verification

```bash
curl -s http://localhost:8080/health
# {"status":"healthy"}

curl -s http://localhost:8080/v1/models | python3 -m json.tool
# Shows the model configured in the TOML
```

## Run the CLI

### Interactive REPL (default)

```bash
aura-cli
```

### One-shot mode (for scripts/pipelines)

```bash
aura-cli --query "List EC2 instances in us-east-1"
```

### Resume a previous conversation

```bash
aura-cli --resume <conversation-id-or-prefix>
```

## REPL Commands

| Command | What It Does |
|---------|--------------|
| `/expand` | Toggle tool call detail view (arguments, results) |
| `/stream` | Toggle SSE event panel (tool_requested, tool_start, tool_complete) |
| `/model` | Browse and select from available models |
| `/conversations` | List saved conversations |
| `/resume <filter>` | Resume a conversation by ID or name |
| `/rename <name>` | Name the current conversation |
| `/clear` | Start a new conversation |
| `/help` | Show all commands |

**For visibility into agent behavior, enable both `/expand` and `/stream` after starting the REPL.**

## Data Storage

All data is local to your machine:

| Path | Contents |
|------|----------|
| `~/.aura/config.toml` | CLI configuration |
| `~/.aura/conversations/` | Saved conversation history (JSONL) |
| `.aura/settings.json` | Project-scoped tool permissions |

## Tool Permissions

aura-cli can execute tools locally (file reads, shell commands, searches). Permissions
are configured per-project in `.aura/settings.json`:

```json
{
  "permissions": {
    "allow": ["ListFiles(*)", "Read(*)", "FindFiles(*)", "SearchFiles(*)"],
    "deny": ["Shell(*)"]
  }
}
```

- **allow** — execute without prompting
- **deny** — block with reason
- **no match** — prompt user for approval
- Server-side tools (MCP) always execute on the server and bypass local permissions

## Known Issues and Findings

### Bedrock throttling on large discovery scans

When the discovery agent makes many rapid tool calls (call_aws, bulk_store_resources),
the conversation context grows quickly. After ~7 tool calls in 60 seconds, Bedrock
may reject with:

```
CompletionError: ProviderError: Too many tokens, please wait before trying again.
```

The CLI surfaces this as:
```
The upstream model provider returned an error and the request could not be completed.
```

**Workarounds:**

1. **Use targeted queries** — ask for one service at a time ("list EC2 instances")
   instead of "discover everything"
2. **Use the OpenAI dev config** for local development — higher rate limits:
   ```bash
   CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent-dev.toml aura-web-server
   ```
3. **Use the orchestrator** (port 3030) for full discovery — it delegates to parallel
   workers which each have independent Bedrock sessions

### Qdrant connection failures

If the Qdrant MCP server is not running, the agent will report knowledge base
unavailability but will fall back to direct AWS API calls. Start Qdrant and
the custom Qdrant MCP per the [quick start](quick-start.md) if you want persistence.

### Stream panel shows only message IDs

If `/stream` displays repetitive lines like:
```
message - chatcmpl-7c031a74-...
message - chatcmpl-7c031a74-...
```

The server was started **without** `AURA_CUSTOM_EVENTS=true`. Restart the server
with that flag to see rich event types.

## Architecture

```
┌─────────────┐     HTTP/SSE      ┌──────────────────┐     MCP      ┌─────────────┐
│  aura-cli   │ ───────────────── │ aura-web-server  │ ──────────── │  MCP Servers │
│  (terminal) │  /v1/chat/        │  (port 8080)     │              │  (AWS, Qdrant│
│             │  completions      │                  │              │   etc.)      │
└─────────────┘                   └──────────────────┘              └─────────────┘
     │                                    │
     │ ~/.aura/conversations/             │ AURA_CUSTOM_EVENTS=true
     │ (local persistence)                │ TOOL_RESULT_MODE=aura
     │                                    │ (rich SSE events)
```

- aura-cli sends messages to `{api_url}/v1/chat/completions` with `stream: true`
- Server executes tools via MCP and streams results back as SSE events
- CLI renders tool activity in the `/stream` and `/expand` panels
- Conversations are persisted locally in `~/.aura/conversations/` as JSONL

## What Next

- [Quick Start](quick-start.md) — full stack setup (Qdrant, MCP servers, orchestrator)
- [Orchestrator Architecture](orchestrator-architecture.md) — how multi-agent discovery works
- [Troubleshooting](troubleshooting.md) — common errors and fixes
- [Streaming API Guide](~/Documents/GitHub/aura/docs/streaming-api-guide.md) — full SSE event reference
