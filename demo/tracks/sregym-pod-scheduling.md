# Track: Pod Stuck Pending — Diagnose with AURA

**Status:** Draft (Phase 1 — operator runbook for AWS-first validation)
**Created:** 2026-06-11
**Source benchmark:** SREGym problem `assign_to_non_existent_node` (social-network profile)
**Estimated duration:** ~25 min self-paced, ~15 min instructor-led

---

## 1. Why this scenario

Every SRE has been here:

> It's 2 AM. The pager fires. One of your services is degraded. You run
> `kubectl get pods` and there's a pod stuck in `Pending`. Nothing is
> scheduling. The codebase isn't yours. You have 15 minutes before the
> SLO breaches.

This is the most common failure mode in any Kubernetes-shaped environment:
a scheduling constraint (nodeSelector, taint, affinity rule, resource
request, missing PVC) that no node satisfies. The fault is upstream of
the symptom — the pod isn't broken, the *constraint* is broken — and
solving it requires walking from the visible symptom (`Pending`) backwards
through scheduler events to the configuration that put it there.

AURA, configured with the substrate-agnostic SRE preamble, does this walk
in about 30 seconds. The learner watches the reasoning unfold in their
terminal and finishes the demo with two takeaways:

1. The discipline AURA applies (causal-chain reasoning, symptom-vs-cause,
   cross-referencing scheduler events with resource state) is *how SREs
   should reason*, not just how a model reasons.
2. The toggle that turns ordinary AURA into "AURA that reasons like an
   SRE" is a single TOML field. Operators can apply this to their own
   AURA deployment in minutes.

---

## 2. Prerequisites

**For phase 1 (this runbook), AWS-first validation:**

- An AWS account you control (the existing Bella Vista demo's account is fine).
- A region with Bedrock access to `us.anthropic.claude-sonnet-4-6` — `us-east-1`
  is the path we've validated; cross-account Bedrock creds for the Mezmo
  Bedrock account `627029844476` are provided via Instruqt team secrets
  pattern for now and via `BEDROCK_AWS_ACCESS_KEY_ID` / `BEDROCK_AWS_SECRET_ACCESS_KEY`
  on the box.
- An SSH key pair already imported into EC2 in that region.
- Terraform installed locally.

**For phase 2 (Instruqt port — not yet implemented):**

- Same as above, just consumed through Instruqt's AWS sandbox accounts.
- A baked AMI to skip the ~10-minute cargo build at boot. The phase-1
  flow validates the bootstrap script; phase 2 wraps the result of a
  one-time AMI bake into the Instruqt track definition.

---

## 3. Bring up the demo box

```bash
cd ~/Documents/GitHub/aura-examples/demo/sregym/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: aws_region, key_name, your_ip_cidr,
#                       bedrock_access_key_id, bedrock_secret_access_key
terraform init
terraform apply
```

Apply takes ~3 min for the AWS resources. The instance takes another
~10-15 min on first boot to install Docker/kind, clone SREGym, build
AURA from source (this is the slow step — once we bake an AMI for
phase 2 it drops to ~2 min), bring up the kind cluster, deploy
social-network, start the bridges, and inject the fault.

While that's running, watch the bootstrap log:

```bash
# In the terraform output you'll see ssh_command — run it.
ssh ec2-user@<public-ip>
tail -f /var/log/aura-demo-bootstrap.log
```

Boot is complete when `/var/log/aura-demo-bootstrap.ready` exists
(`ls /var/log/aura-demo-bootstrap.ready` succeeds).

---

## 4. Verify the box is ready

```bash
sregym-status
```

Expected output ends with `=== ALL GREEN — demo is ready ===`. If any
component is DOWN, the script prints exactly where to look
(`journalctl -u aura-demo-server -f` etc.). Don't proceed until it's
green.

Sanity-check the fault is injected:

```bash
kubectl get pods -n social-network -l app=user-service
# Expected: at least one pod in Pending status
```

---

## 5. Walk the demo

Six steps. The Instruqt port will turn each of these into a challenge.

### Step 1 — The page (~3 min)

**Learner narrative:**

> You've been paged. The `user-service` in the social-network namespace
> isn't responding. Customers can't log in. You don't know this codebase.
> Get to a root cause.

**Learner runs:**

```bash
kubectl get pods -n social-network
```

**Expected observation:** one or more `user-service-*` pods stuck in
`Pending`. Other pods are `Running`.

**Try to triage manually:**

```bash
kubectl describe pod -n social-network -l app=user-service | head -40
```

**Expected observation:** the `Events` section shows a `FailedScheduling`
warning naming a nodeSelector key that no node carries (`nodename:
aura-demo-nonexistent-node`). The learner *could* fix this themselves
right now — but the point is to feel the cost of doing this for an
unfamiliar service while paged.

**Check criterion:** learner can name the symptom ("pod stuck Pending")
and the immediate event ("FailedScheduling on a nodeSelector"). They
don't need to identify the root cause yet — that's AURA's job.

### Step 2 — Meet AURA (~2 min)

**Learner narrative:**

> AURA is already running on this box. It's preconfigured with read-only
> kubectl access plus the SRE investigation preamble that teaches it to
> walk causal chains. You'll talk to it through `aura-cli` — a thin
> terminal client.

**Learner runs:**

```bash
cat /opt/aura-demo/aura-sregym-demo.toml | head -40
```

**Expected observation:** the learner sees the `[mcp.servers.*]` blocks
(three of them — kubectl, jaeger, prometheus) and the start of the
`system_prompt = """` block. Highlight the "Investigation discipline"
section — this is what makes AURA reason like an SRE rather than just
guess.

**Check criterion:** learner can explain in one sentence what's
different about this config from default AURA ("we gave it the SRE
preamble plus three tool surfaces").

### Step 3 — Diagnose with AURA (~5 min)

**Learner runs:**

```bash
sregym-ask
```

This drops them into the aura-cli REPL connected to the local
aura-web-server.

**Prompt to type:**

> Something's broken in the social-network namespace. A user-service pod
> isn't scheduling. Find the root cause.

**Expected behavior:** AURA narrates one short sentence, then calls
`sregym_kubectl.exec_read_only_kubectl_cmd` (probably `kubectl get pods`
or `kubectl describe pod`). It cross-references resource state with
events, identifies the `nodeSelector` requiring a nonexistent node,
and commits to a diagnosis along the lines of:

> **Faulty component:** `deployment/user-service` in namespace `social-network`.
> **Mutation type:** `nodeSelector` references a label key (`nodename`) with a
> value (`aura-demo-nonexistent-node`) that no node in the cluster carries.
> **Evidence:** `kubectl describe pod` shows `FailedScheduling: 0/N nodes
> available — node(s) didn't match Pod's node affinity/selector`. The
> deployment spec carries `nodeSelector: { nodename: aura-demo-nonexistent-node }`.
> No node in the cluster has this label (verified via `kubectl get nodes -L nodename`).

**Check criterion:** AURA commits to a single root cause and quotes
the actual broken value (the literal `aura-demo-nonexistent-node`
string). If it does, move on. If it gives a list of "could be X or Y
or Z" hedges, re-prompt with "What's the single most likely cause? Be
specific."

### Step 4 — Mitigate with AURA (~5 min)

**Prompt to type next:**

> Fix it.

**Expected behavior:** AURA states intent in one short sentence (per
the demo-mode safety rule in its system_prompt: announce any mutation
before making it), then calls `sregym_kubectl.exec_kubectl_cmd_safely`
to patch the deployment — either removing the `nodeSelector` or
correcting the label to one that exists. It then re-queries pod state
to confirm the rollout completed.

**Expected observation in another terminal:**

```bash
kubectl get pods -n social-network -l app=user-service -w
# Watch Pending → Running
```

**Check criterion:** the `user-service` pod transitions to `Running`
within ~60s and AURA confirms in chat that the fix is in place.

### Step 5 — What just happened (~5 min)

**Learner narrative:**

> Look at how AURA reasoned. It didn't just match the symptom to a
> known pattern — it followed a causal chain from `Pending` to
> `FailedScheduling event` to `nodeSelector mismatch` to the literal
> string `aura-demo-nonexistent-node`. That discipline came from the
> preamble.

**Learner runs:**

```bash
# Show the SRE preamble section that drove the reasoning
grep -A 30 "Causal-chain rule" /opt/aura-demo/aura-sregym-demo.toml
```

**Highlight points:**

- The preamble doesn't know anything about Kubernetes specifically — it's
  substrate-agnostic. The same reasoning works on ECS task definitions,
  Lambda config, Terraform state.
- Toggling this on for any AURA deployment is a single TOML field —
  show them the `system_prompt = """..."""` block.
- This isn't a model fine-tune. It's a configuration. Anyone with AURA
  + Bedrock can apply it tonight.

**Check criterion:** learner can articulate "the AURA harness ran a
stock Bedrock model; the change was in the system prompt." This is the
mental model that drives the upsell.

### Step 6 — Try it yourself (~5 min)

**Learner runs:**

```bash
reset-fault.sh                                    # restore healthy state
sregym-status                                     # verify ALL GREEN
inject-fault.sh assign_to_non_existent_node       # re-arm the fault
```

**Then:** the learner drives AURA themselves, freeform. They can:

- Ask it more open-ended questions ("What else might be wrong here?",
  "What would the blast radius have been?")
- Ask for the same diagnosis in a structured format ("Give me a JIRA
  ticket-ready post-mortem stub")
- Try a deliberately misleading prompt ("Restart the service") and watch
  AURA push back ("Restarting won't help — the nodeSelector is in the
  deployment spec, not the pod state. A restart re-creates a pod with
  the same broken constraint.")

**Check criterion:** the learner reaches `Running` state again, this
time driving AURA themselves. They've now closed the loop: they can
do this in their own environment with their own AURA deployment.

---

## 6. Tear down

```bash
cd ~/Documents/GitHub/aura-examples/demo/sregym/terraform
terraform destroy
```

Confirm:

```bash
aws ec2 describe-instances \
  --filters Name=tag:Project,Values=aura-sregym-demo \
            Name=instance-state-name,Values=pending,running,stopping,shutting-down \
  --query 'Reservations[].Instances[].InstanceId' --output text
# Expected: empty
```

---

## 7. What's deliberately out of scope (phase 1)

- **Multi-problem support.** This first iteration ships exactly one
  scenario. Adding more problems means: (a) extend `inject-fault.sh`'s
  case statement, (b) potentially deploy other SREGym workloads
  alongside social-network, (c) tune the AURA system_prompt's
  "Operational notes for this demo" section.
- **AMI bake.** We're cloning + building at boot, which costs ~10 min
  but lets the demo evolve in git. Phase 2 (Instruqt port) bakes the
  built state into an AMI to drop boot time to ~2 min.
- **AURA upstream `[agent].workflow = "sre"` toggle.** The branch is
  open against mezmo/aura; this demo embeds the preamble inline so
  it's independent of upstream merge timing. When the upstream feature
  lands, the TOML's `system_prompt = """..."""` block can be replaced
  with `workflow = "sre"` plus the substrate-specific notes — a one-line
  diff.
- **Idempotency guarantees on the inject/reset scripts beyond the
  documented happy path.** The scripts assume a healthy starting
  deployment. If something else has gone sideways (e.g. someone scaled
  the deployment to zero), the operator is expected to use kubectl
  directly to recover.

---

## 8. Known rough edges (will be smoothed in phase 1 validation)

- The first boot of `aura-web-server` may take a few seconds longer than
  the dependent bridges' health-checks expect; `Restart=always` covers
  this but the first `sregym-status` immediately after the ready
  sentinel may show DOWN for AURA briefly.
- `helm install` for social-network can take up to 10 min on m5.xlarge
  if image pulls are uncached. Subsequent boots from a baked AMI will
  be much faster.
- aura-cli's TUI may render oddly over very narrow ssh terminals (<100
  cols). The fix is `resize` or a wider terminal; not a demo-blocker.

---

## 9. Phase-2 hand-off (to Instruqt)

When this runbook is solid in our AWS account, the port to Instruqt is
mostly mechanical:

- Each numbered step in §5 becomes one Instruqt challenge with the
  learner-narrative text as the `assignment` and the check criterion as
  the `check.shell` script.
- The bootstrap script moves into a "lifecycle setup" Instruqt phase
  driven by AMI (no source-build at user-data time).
- Terraform module becomes the Instruqt sandbox provisioning template.
- The `bin/sregym-ask`, `bin/sregym-status`, `scripts/inject-fault.sh`,
  `scripts/reset-fault.sh` helpers are pre-installed on the AMI; the
  challenges call them by name.

See `demo/scripts/track-payload.json` (the existing Bella Vista track)
for the Instruqt mutation shape.
