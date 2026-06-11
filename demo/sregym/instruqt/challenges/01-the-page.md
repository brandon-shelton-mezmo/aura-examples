## The page

It's 2 AM. You've been paged.

The `social-network` Kubernetes app is degraded — customers can't log in.
The previous engineer left no runbook, and you've never touched this
codebase. Your SLO breach clock starts in 15 minutes.

Your only access is a terminal on the cluster's bastion host. Open the
**Demo Box** tab.

### Step 1: see the symptom

```bash
kubectl get pods -n social-network -l service=user-service
```

You'll see one `user-service-*` pod `Running` (the existing replica from
before the bad deploy) and one `Pending` (the new replica that won't
schedule).

### Step 2: get the immediate cause

```bash
kubectl describe pod -n social-network -l service=user-service | tail -30
```

Read the `Events:` section. You'll see a `FailedScheduling` warning
naming a `nodeSelector` key that no node carries.

You *could* fix this yourself right now. The point is to feel the cost
of doing this for an unfamiliar service while paged.

In the next challenge, you'll let **AURA** do the investigation for you
— but with an SRE preamble baked into its system prompt that teaches
it to reason like an SRE walking a causal chain.

> **Click Check when you're ready.**
