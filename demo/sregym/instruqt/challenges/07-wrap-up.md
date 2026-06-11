## Wrap-up

You just watched AURA walk a real Kubernetes incident end-to-end:

| Phase | What you saw |
|---|---|
| Diagnose | ~5 tool calls, causal-chain reasoning, literal-value quoting |
| Mitigate | Intent statement first, JSON-patch via kubectl, rollout verification |
| Steady state | Pod `Running`, deployment 1/1 READY |

All with a stock Bedrock model. The behavior shift came from a **single
TOML field** — the SRE investigation preamble in `system_prompt`.

### Take this back to your environment

The full config you used today is at:

```
/opt/aura-demo/aura-sregym-demo.toml
```

Three blocks make it work:

1. `[mcp.servers.*]` — wire AURA to any tool surface (kubectl, jaeger,
   prometheus today; CloudWatch, Datadog, AWS APIs in your environment).
2. `system_prompt = """..."""` — the SRE preamble, copy-pasteable.
3. `[agent.llm]` — pick your provider; the demo uses Bedrock but
   Anthropic-direct + OpenAI + Gemini all work.

### Where to go next

- **github.com/mezmo/aura** — upstream AURA repo with full docs.
- **github.com/mezmo/aura-examples** — this demo lives at
  `demo/sregym/`. Phase 2 of the SRE-preamble work upstreams it as
  `[agent].workflow = "sre"` (one-liner toggle).
- Try the Bella Vista AWS/ECS demo for the multi-agent discovery flow
  that complements this single-agent incident-response flow.

> **Click Check to complete the track.**
