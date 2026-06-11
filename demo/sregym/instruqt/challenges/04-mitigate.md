## Mitigate with AURA

Now ask AURA to fix it.

### Run

```bash
sregym-ask "You diagnosed that deployment/user-service has a nodeSelector requiring nodename=aura-demo-nonexistent-node. Fix it. State your intent before making any change, then verify the rollout reaches healthy state."
```

### What AURA does

1. **States intent first.** AURA's system prompt enforces a demo-mode
   safety rule: announce mutations in plain English before making them.
   You'll see a line like *"Intent: Patch deployment/user-service to
   remove the invalid nodeSelector via a JSON patch remove operation."*

2. **Calls `sregym_kubectl.exec_kubectl_cmd_safely`** — the mutating
   variant of kubectl (read-only `exec_read_only_kubectl_cmd` is used
   in the diagnosis phase). The patch removes the bad `nodeSelector`.

3. **Watches the rollout.** AURA polls `kubectl get deployment` until
   it reports READY=1/1, AVAILABLE=1. It declares success only when
   the substrate confirms steady state — not when the patch API
   accepts the call.

### Verify

In a different terminal tab (or same after AURA finishes):

```bash
kubectl get pods -n social-network -l service=user-service
# Expected: one pod, status Running, no Pending
kubectl get deployment/user-service -n social-network -o jsonpath='nodeSelector={.spec.template.spec.nodeSelector}'
# Expected: nodeSelector={} (empty)
```

> **Click Check when the pod is Running.**
