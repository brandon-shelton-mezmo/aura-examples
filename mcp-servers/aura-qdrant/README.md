# Aura Qdrant MCP Server

Custom MCP server for the Aura SRE platform knowledge base. Replaces the generic
`mcp-server-qdrant` with platform-specific capabilities: direct AWS discovery via
boto3, deterministic IDs from ARNs, metadata-filtered search, and multi-collection
support.

The key innovation is `discover_and_store` -- it calls AWS APIs directly and writes
results to Qdrant in one step. Raw AWS data never passes through the LLM's context
window. The LLM tells it *what* to discover; the tool handles the API call, JSON
parsing, document generation, embedding, and storage internally.

## Tools

| Tool | Purpose |
|------|---------|
| `discover_and_store` | Call AWS via boto3, store each resource in Qdrant. Returns summary only. |
| `store_resource` | Store a single resource by ARN. Upsert semantics (same ARN = overwrite). |
| `bulk_store_resources` | Parse a JSON array of resources and store all at once. |
| `search` | Semantic search with optional metadata filters (service, region, type, scan). |
| `list_resources` | List resources by metadata filter, no semantic matching. |
| `delete_resource` | Delete a single resource by ARN. |
| `delete_by_filter` | Delete all resources matching a service, region, or scan filter. |
| `get_collection_stats` | Total document count and per-service breakdown. |
| `store_document` | Store a non-resource document (post-mortem, manifest, IaC). |
| `drop_collection` | Drop an entire collection. Requires explicit confirmation string. |

## discover_and_store

This is the primary discovery tool. It calls AWS (via boto3) and stores each resource
in Qdrant in a single tool call. The LLM sees only a count summary -- zero AWS JSON
passes through the context window.

### Supported service types

| Service Type | boto3 Call | What It Discovers |
|--------------|-----------|-------------------|
| `ec2/vpc` | `describe_vpcs` | VPCs with CIDR blocks, state, tags |
| `ec2/instance` | `describe_instances` | EC2 instances with type, state, networking |
| `ec2/security-group` | `describe_security_groups` | Security groups with inbound/outbound rules |
| `ec2/subnet` | `describe_subnets` | Subnets with AZ, CIDR, VPC association |
| `s3/bucket` | `list_buckets` | S3 buckets (global service) |
| `lambda/function` | `list_functions` | Lambda functions with runtime, memory, timeout |
| `iam/role` | `list_roles` | IAM roles with trust policies (global service) |
| `elbv2/load-balancer` | `describe_load_balancers` | ALBs and NLBs with listeners, VPC |
| `route53/hosted-zone` | `list_hosted_zones` | DNS hosted zones (global service) |
| `cloudformation/stack` | `list_stacks` | Active CloudFormation stacks |
| `rds/instance` | `describe_db_instances` | RDS database instances |
| `dynamodb/table` | `list_tables` | DynamoDB table names |

### How it works

1. Receives `service_type` (e.g., `ec2/vpc`) from the LLM
2. Calls the corresponding boto3 API directly (not through the AWS MCP)
3. Parses the response, extracts ARN/ID, name, tags, relationships
4. Generates a `[RESOURCE]` document with structured sections
5. Embeds with FastEmbed (`all-MiniLM-L6-v2`)
6. Upserts into Qdrant with deterministic ID from ARN hash (MD5)
7. Returns: `"Discovered and stored 42 ec2/vpc resources in aws_resources. Errors: 0."`

### Deterministic IDs

Every resource gets a point ID derived from `md5(arn)`. Storing the same resource
again overwrites the previous version. This means:

- Re-running discovery produces 0 duplicates
- Incremental scans update stale data automatically
- The knowledge base is always current, not cumulative

## How to Run

The server runs in stdio mode and must be wrapped with `mcp-proxy` for aura's
`http_streamable` transport.

```bash
# Install dependencies
pip install "mcp[cli]" qdrant-client fastembed boto3

# Start Qdrant first
docker run -d --name qdrant -p 6333:6333 -v qdrant_data:/qdrant/storage qdrant/qdrant

# Run via mcp-proxy (exposes as http_streamable on port 8000)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1

mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8000 \
  -e QDRANT_URL http://localhost:6333 \
  -e AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY \
  -e AWS_REGION $AWS_REGION \
  -- uv run mcp-servers/aura-qdrant/server.py

# Or with uv run directly (handles inline script deps):
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8000 \
  -e QDRANT_URL http://localhost:6333 \
  -- uv run mcp-servers/aura-qdrant/server.py
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `QDRANT_URL` | `http://localhost:6333` | Qdrant server URL |
| `QDRANT_API_KEY` | (none) | Qdrant API key (for Qdrant Cloud) |
| `EMBEDDING_MODEL` | `sentence-transformers/all-MiniLM-L6-v2` | FastEmbed model |
| `DEFAULT_COLLECTION` | `aws_resources` | Default collection name |
| `AWS_ACCESS_KEY_ID` | (from AWS creds chain) | Required for `discover_and_store` |
| `AWS_SECRET_ACCESS_KEY` | (from AWS creds chain) | Required for `discover_and_store` |
| `AWS_REGION` | `us-east-1` | Default region for regional services |

## Collections

The server supports multiple collections for different data types:

| Collection | Contents |
|-----------|----------|
| `aws_resources` | Discovered AWS infrastructure resources |
| `aws_changes` | CloudTrail change records |
| `aws_postmortems` | Post-mortem timeline documents |
| `iac_resources` | Infrastructure-as-code definitions |
| `code_services` | Code-level service summaries |

Each collection is created automatically on first write with cosine similarity
vectors and payload indexes on service, region, resource_type, account, arn,
scan_id, version, and pillar.

## Why Not mcp-server-qdrant?

The generic `mcp-server-qdrant` provides `qdrant-store` and `qdrant-find` -- basic
string-in, string-out operations. This custom server adds:

1. **discover_and_store** -- AWS data never touches the LLM context
2. **Deterministic IDs** -- ARN-based dedup instead of random UUIDs
3. **Metadata filters** -- filter by service, region, type before semantic search
4. **Structured listings** -- `list_resources` without semantic matching
5. **Bulk operations** -- `bulk_store_resources` for batch ingest
6. **Delete by filter** -- clear a service or scan without dropping the collection
