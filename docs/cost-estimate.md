# Cost Estimate — AWS Discovery Agent Stack

**For a typical medium AWS environment (100-500 resources): ~$100-200/month.**

This assumes daily discovery scans, hourly change audits, self-hosted Qdrant, and
AWS Bedrock as the LLM provider. Your actual costs depend on environment size and
scan frequency. These are estimates based on Claude Sonnet 4 pricing on Bedrock.

---

## Cost Breakdown by Component

| Component | Monthly Cost (Medium Env) | Notes |
|-----------|--------------------------|-------|
| AWS Bedrock — Discovery scans | ~$3-5/day = $90-150/month | Daily full scan, Claude Sonnet 4, turn_depth=15 |
| AWS Bedrock — Change Audit | ~$0.50-1/run x 24/day = $12-24/month | Hourly runs, lighter scope, turn_depth=10 |
| AWS Bedrock — Incident Response | ~$1-3/incident | On-demand; 5-10 incidents/month = $5-30 |
| AWS Bedrock — Post-Mortem | ~$1-3/use | On-demand after incidents; similar token usage to incident response |
| AWS Bedrock — Capacity Planning | ~$2-4/run x 4/month = $8-16/month | Weekly scheduled run, turn_depth=10 |
| Qdrant (self-hosted Docker) | $0 | ~512MB RAM, minimal CPU — just container resources |
| Qdrant Cloud (managed) | $25-100/month | If you don't want to manage Qdrant yourself |
| AWS API calls (Describe/List) | ~$0 | Read-only API calls are free or fractions of a penny |

**Total (self-hosted Qdrant): ~$115-220/month** for all five agents at recommended cadences.

---

## By Environment Size

| Environment | Resource Count | Estimated Monthly Cost | What Changes |
|-------------|---------------|----------------------|--------------|
| **Small** | <100 resources | ~$50-80/month | Fewer API calls per scan, smaller LLM context windows, lower token usage |
| **Medium** | 100-500 resources | ~$100-200/month | Baseline estimate above |
| **Large** | 500+ resources | ~$200-400/month | More tokens per scan (larger resource inventories), longer LLM reasoning chains, more change audit events |

The main cost driver is Bedrock token usage, which scales with how many resources the
agent needs to describe, analyze, and store per scan. Large environments produce more
AWS API output, which means more input tokens to the LLM.

---

## By Agent

### Discovery Agent (daily scan)
- **Cost per full scan:** ~$3-5 (medium env)
- **Recommended cadence:** Daily at off-peak hours, or weekly for stable environments
- **Monthly at daily:** $90-150
- **Monthly at weekly:** $12-20
- **What drives cost:** Number of AWS services scanned, resource count, turn_depth=15

### Change Audit Agent (hourly)
- **Cost per run:** ~$0.50-1
- **Recommended cadence:** Every 1-4 hours (hourly during business hours)
- **Monthly at hourly (24/day):** $12-24
- **Monthly at every 4 hours (6/day):** $3-6
- **What drives cost:** Volume of CloudTrail events, number of changes to analyze

### Incident Response Agent (on-demand)
- **Cost per incident:** ~$1-3
- **Recommended cadence:** On-demand during active incidents
- **Monthly estimate:** $5-30 (assumes 5-10 incidents/month)
- **What drives cost:** Investigation depth (turn_depth=20), number of resources in blast radius

### Post-Mortem Agent (on-demand)
- **Cost per use:** ~$1-3
- **Recommended cadence:** After incident resolution, triggered by humans
- **Monthly estimate:** $5-15 (assumes 3-5 post-mortems/month)
- **What drives cost:** Incident complexity, timeline length, number of contributing factors

### Capacity Planning Agent (weekly)
- **Cost per run:** ~$2-4
- **Recommended cadence:** Weekly
- **Monthly (4 runs):** $8-16
- **What drives cost:** Number of services checked for quotas/utilization, turn_depth=10

---

## Cost Reduction Tips

| Change | Savings | Trade-off |
|--------|---------|-----------|
| Run discovery weekly instead of daily | ~$75-130/month | KB up to 7 days stale instead of 1 day |
| Run change audit every 4 hours instead of hourly | ~$9-18/month | Changes detected later (4hr lag vs 1hr) |
| Use scoped discovery instead of full scans | Varies — skip unused services | May miss resources in unscanned services |
| Lower turn_depth on discovery (15 -> 10) | ~20-30% less per scan | Less thorough cross-service analysis |
| Use Bedrock instead of OpenAI | ~50% savings | Data stays in AWS (this is actually a benefit) |

### Bedrock vs OpenAI Cost Comparison

| Provider | Estimated Monthly (Medium Env) | Data Residency |
|----------|-------------------------------|----------------|
| AWS Bedrock (Claude Sonnet 4) | ~$100-200 | Data stays in your AWS account |
| OpenAI (gpt-4o) | ~$200-400 | Data sent to OpenAI API |

Bedrock is roughly half the cost for this workload and keeps all data within AWS.
Unless you have a specific reason to use OpenAI, Bedrock is the better choice for
AWS infrastructure agents.

---

## What's Free

- **Qdrant (self-hosted)** — runs as a Docker container, costs only the compute resources it sits on (~512MB RAM)
- **AWS Describe/List API calls** — the read-only AWS APIs used by the discovery agent are free or cost fractions of a penny
- **The agent configs themselves** — this repository is open; you pay only for the LLM and infrastructure to run it
- **Aura runtime** — the aura-web-server binary has no license cost

---

## Assumptions Behind These Numbers

- LLM: Claude Sonnet 4 on AWS Bedrock
- Medium environment: 100-500 AWS resources across EC2, ECS, Lambda, RDS, S3, etc.
- Discovery: daily full scan at default turn_depth=15
- Change Audit: hourly at turn_depth=10
- Incident Response: 5-10 incidents/month (on-demand)
- Post-Mortem: 3-5/month (on-demand)
- Capacity Planning: weekly at turn_depth=10
- Qdrant: self-hosted via Docker (not Qdrant Cloud)
- Single region, single account

Multi-region or multi-account deployments multiply discovery and audit costs roughly
linearly by the number of regions/accounts scanned.
