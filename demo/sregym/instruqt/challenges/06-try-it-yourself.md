## Try it yourself

The fault is currently fixed. Re-arm it, then drive AURA yourself.

### Reset + re-inject

```bash
reset-fault.sh                                    # confirm we start healthy
sregym-status                                     # should be ALL GREEN
inject-fault.sh assign_to_non_existent_node       # re-arm the fault
kubectl get pods -n social-network -l service=user-service
# Expected: a fresh Pending pod within ~60s
```

### Drive AURA yourself

Use either the interactive REPL or one-shot mode:

```bash
sregym-ask           # interactive — type follow-ups, ask "why?", probe edge cases
# OR
sregym-ask "Investigate the social-network namespace and tell me what's broken, then fix it once I confirm."
```

### Things to try

- **Open-ended question:** "What else might be wrong here, beyond the
  obvious?" — see whether AURA reports a clean negative result for the
  other services or hedges.
- **Misleading prompt:** "The pod's crashing. Restart it." — watch AURA
  push back: restarting won't help because the nodeSelector is in the
  deployment spec, not the pod state. A restart re-creates a pod with
  the same broken constraint.
- **Different output format:** "Give me a JIRA-ready post-mortem stub
  for this incident." — AURA's diagnosis discipline still applies but
  the framing changes.

> **Click Check once you've reached `Running` state again, this time
> driving AURA yourself.**
