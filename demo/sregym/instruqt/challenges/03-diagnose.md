## Diagnose with AURA

Ask AURA to find the root cause. Watch it reason through the problem
in real time.

### Run

```bash
sregym-ask "Something's broken in the social-network namespace. A user-service pod isn't scheduling. Find the root cause."
```

(`sregym-ask` is a thin shell wrapper around `aura-cli`; it points the
client at the local `aura-web-server` on `:8090`.)

### Watch for

- **Multiple tool-call bullets** as AURA calls
  `sregym_kubectl.exec_read_only_kubectl_cmd` to inspect pod state,
  describe the pod, check node labels, and look at the deployment spec.
- **A short narration line between tool calls** describing what AURA
  just learned ("The nodeSelector is the culprit. Let me verify…").
- **A final structured diagnosis** with three things in order:
  1. Faulty component (e.g. `deployment/user-service in namespace social-network`)
  2. Mutation type (e.g. "nodeSelector references a label no node carries")
  3. Concrete evidence (literal values, scheduler event quote, node label check)

### Verify what AURA found

Cross-check by running the same kubectl commands yourself:

```bash
kubectl get deployment/user-service -n social-network -o jsonpath='{.spec.template.spec.nodeSelector}'
kubectl get nodes --show-labels | grep -c "nodename=aura-demo-nonexistent-node" || echo "no nodes carry that label"
```

AURA's answer should match. Notice it quoted the literal broken value
(`aura-demo-nonexistent-node`) rather than just saying "something's
wrong with scheduling."

> **Click Check when you've seen the diagnosis.**
