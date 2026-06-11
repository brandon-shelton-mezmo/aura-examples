## Meet AURA

AURA is already running on this box. It's preconfigured with read-only
kubectl access plus the **SRE investigation preamble** that teaches it
to walk causal chains rather than guess.

You'll talk to it through `aura-cli` — a thin terminal client.

### Step 1: confirm the stack is up

```bash
sregym-status
```

All eight checks should be **OK** (kind cluster, MCP server, social-network
namespace, the five systemd services, MCP bridges, aura-web-server,
aura-cli). The social-network row notes "1 Pending" — that's the
injected fault you just observed.

### Step 2: glance at the AURA config

```bash
head -50 /opt/aura-demo/aura-sregym-demo.toml
```

Three things to notice:

- Three `[mcp.servers.*]` blocks — kubectl, jaeger, and prometheus.
  This is the toolset AURA can reach.
- A `system_prompt = """..."""` block that starts with the **SRE
  investigation preamble** — substrate-agnostic discipline (causal-chain
  rule, symptom-vs-cause distinction, anti-anchoring).
- `provider = "bedrock"` + `model = "us.anthropic.claude-sonnet-4-6"` —
  stock Bedrock, no fine-tuning. The behavior change comes from the
  prompt, not the model.

That preamble is the toggle that turns ordinary AURA into "AURA that
reasons like an SRE." We'll see it in action next.

> **Click Check when ready.**
