## What just happened

Look at how AURA reasoned. It didn't just match the symptom to a known
pattern. It followed a causal chain:

> Pod is Pending →
> Scheduler event says no nodes available →
> Pod spec has a nodeSelector →
> No node has the matching label →
> The literal broken value is `aura-demo-nonexistent-node` →
> **Root cause:** the deployment spec.

That discipline came from the preamble. Take a look:

```bash
grep -A 30 "Causal-chain rule" /opt/aura-demo/aura-sregym-demo.toml
```

### Three takeaways

1. **The preamble is substrate-agnostic.** It doesn't know anything
   specific to Kubernetes. The same reasoning works on ECS task
   definitions, Lambda configs, Terraform state, or anything where
   configuration defines steady state and runtime events are how
   steady state breaks.

2. **No model fine-tuning was involved.** AURA ran a stock Bedrock
   Claude Sonnet model. The behavior change came from the system
   prompt. Anyone with AURA + Bedrock can apply this configuration
   tonight.

3. **The toggle is a single TOML field.** This demo embeds the
   preamble inline in `system_prompt`, but the upstream feature
   `[agent].workflow = "sre"` (currently being merged into mezmo/aura)
   reduces it to one line per agent config.

### Optional: scan the full preamble

```bash
sed -n '/# AURA SRE Investigation Preamble/,/## SREGym substrate-specific/p' /opt/aura-demo/aura-sregym-demo.toml | head -80
```

> **Click Check when ready.**
