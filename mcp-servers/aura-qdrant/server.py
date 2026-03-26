#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "mcp[cli]>=1.0.0",
#     "qdrant-client>=1.12.0",
#     "fastembed>=0.4.0",
#     "boto3>=1.35.0",
# ]
# ///
"""
Aura Qdrant MCP Server

Custom MCP server for the Aura SRE platform knowledge base. Replaces the
generic mcp-server-qdrant with platform-specific capabilities:

  - Deterministic IDs from ARN (no duplicates — upsert semantics)
  - Metadata filtering alongside semantic search
  - Delete by ARN
  - Structured listing without semantic search
  - Multi-collection support (aws_resources, aws_changes, aws_postmortems, iac_resources, code_services)

Usage:
    # Install dependencies
    pip install "mcp[cli]" qdrant-client fastembed

    # Run in stdio mode (wrap with mcp-proxy for HTTP)
    QDRANT_URL=http://localhost:6333 python server.py

    # Or via mcp-proxy for aura http_streamable transport:
    mcp-proxy --transport streamablehttp --port 8000 \
      -e QDRANT_URL http://localhost:6333 \
      -- python server.py

Environment Variables:
    QDRANT_URL          Qdrant server URL (default: http://localhost:6333)
    QDRANT_API_KEY      Qdrant API key (optional, for Qdrant Cloud)
    EMBEDDING_MODEL     FastEmbed model name (default: sentence-transformers/all-MiniLM-L6-v2)
    DEFAULT_COLLECTION  Default collection name (default: aws_resources)
"""

import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Optional

from mcp.server.fastmcp import FastMCP
from qdrant_client import QdrantClient, models
from fastembed import TextEmbedding

# Configuration
QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY", None)
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
DEFAULT_COLLECTION = os.getenv("DEFAULT_COLLECTION", "aws_resources")

logger = logging.getLogger(__name__)

# Initialize Qdrant client
qdrant = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY)

# Initialize embedding model (lazy — loaded on first use)
_embedding_model = None


def get_embedding_model():
    global _embedding_model
    if _embedding_model is None:
        _embedding_model = TextEmbedding(model_name=EMBEDDING_MODEL)
    return _embedding_model


def embed_text(text: str) -> list[float]:
    """Embed a single text string."""
    model = get_embedding_model()
    embeddings = list(model.embed([text]))
    return embeddings[0].tolist()


def arn_to_id(arn: str) -> str:
    """Generate a deterministic point ID from an ARN.

    Same ARN always produces the same ID. This means qdrant upsert
    will overwrite the previous version — no duplicates.
    """
    return hashlib.md5(arn.encode()).hexdigest()


def content_to_id(content: str) -> str:
    """Generate a deterministic ID from content hash.

    Used for non-ARN documents (changes, manifests, summaries).
    """
    return hashlib.md5(content.encode()).hexdigest()


def ensure_collection(collection_name: str, vector_size: int = 384):
    """Create collection if it doesn't exist."""
    collections = [c.name for c in qdrant.get_collections().collections]
    if collection_name not in collections:
        qdrant.create_collection(
            collection_name=collection_name,
            vectors_config=models.VectorParams(
                size=vector_size,
                distance=models.Distance.COSINE,
            ),
        )
        # Create payload indexes for filtered search
        for field in ["metadata.service", "metadata.region", "metadata.resource_type",
                      "metadata.account", "metadata.arn", "metadata.scan_id",
                      "metadata.version", "metadata.pillar"]:
            try:
                qdrant.create_payload_index(
                    collection_name=collection_name,
                    field_name=field,
                    field_schema=models.PayloadSchemaType.KEYWORD,
                )
            except Exception:
                pass  # Index may already exist


# --- AWS Discovery Helper ---
# This calls AWS directly (via boto3) and stores results in Qdrant,
# bypassing the LLM for data transfer. The LLM just says WHAT to
# discover — the tool handles HOW.

# Service configurations: maps service/type to the boto3 call and response key
AWS_DISCOVERY_CONFIG = {
    "ec2/vpc": {
        "client": "ec2",
        "method": "describe_vpcs",
        "response_key": "Vpcs",
        "id_field": "VpcId",
        "name_fields": ["Tags"],
    },
    "ec2/instance": {
        "client": "ec2",
        "method": "describe_instances",
        "response_key": "Reservations",
        "flatten": "Instances",
        "id_field": "InstanceId",
        "name_fields": ["Tags"],
    },
    "ec2/security-group": {
        "client": "ec2",
        "method": "describe_security_groups",
        "response_key": "SecurityGroups",
        "id_field": "GroupId",
        "name_fields": ["GroupName"],
    },
    "ec2/subnet": {
        "client": "ec2",
        "method": "describe_subnets",
        "response_key": "Subnets",
        "id_field": "SubnetId",
        "name_fields": ["Tags"],
    },
    "s3/bucket": {
        "client": "s3",
        "method": "list_buckets",
        "response_key": "Buckets",
        "id_field": "Name",
        "name_fields": ["Name"],
    },
    "lambda/function": {
        "client": "lambda",
        "method": "list_functions",
        "response_key": "Functions",
        "id_field": "FunctionArn",
        "name_fields": ["FunctionName"],
    },
    "iam/role": {
        "client": "iam",
        "method": "list_roles",
        "response_key": "Roles",
        "id_field": "Arn",
        "name_fields": ["RoleName"],
    },
    "elbv2/load-balancer": {
        "client": "elbv2",
        "method": "describe_load_balancers",
        "response_key": "LoadBalancers",
        "id_field": "LoadBalancerArn",
        "name_fields": ["LoadBalancerName"],
    },
    "route53/hosted-zone": {
        "client": "route53",
        "method": "list_hosted_zones",
        "response_key": "HostedZones",
        "id_field": "Id",
        "name_fields": ["Name"],
    },
    "cloudformation/stack": {
        "client": "cloudformation",
        "method": "list_stacks",
        "params": {"StackStatusFilter": ["CREATE_COMPLETE", "UPDATE_COMPLETE"]},
        "response_key": "StackSummaries",
        "id_field": "StackName",
        "name_fields": ["StackName"],
    },
    "rds/instance": {
        "client": "rds",
        "method": "describe_db_instances",
        "response_key": "DBInstances",
        "id_field": "DBInstanceArn",
        "name_fields": ["DBInstanceIdentifier"],
    },
    "dynamodb/table": {
        "client": "dynamodb",
        "method": "list_tables",
        "response_key": "TableNames",
        "is_string_list": True,
    },
}


def _extract_name_from_tags(item: dict) -> str:
    """Extract Name from AWS Tags list."""
    tags = item.get("Tags", [])
    if isinstance(tags, list):
        for tag in tags:
            if isinstance(tag, dict) and tag.get("Key") == "Name":
                return tag.get("Value", "")
    return ""


def _build_resource_doc(item: Any, service: str, resource_type: str,
                        region: str, account: str, scan_id: str,
                        config: dict) -> tuple[str, str, dict]:
    """Build a [RESOURCE] document, ARN, and metadata from a raw AWS item."""

    # Handle string-list resources (e.g., DynamoDB table names)
    if isinstance(item, str):
        arn = f"arn:aws:{service}:{region}:{account}:{resource_type}/{item}"
        doc = (
            f"[RESOURCE] Service: {service} | Type: {resource_type} | Version: 1 | Scan: {scan_id}\n"
            f"ARN: {arn}\n"
            f"Name: {item} | Region: {region} | Account: {account}\n"
            f"Discovered: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
            f"---\n{service.upper()} {resource_type} '{item}' in {region}."
        )
        meta = {"arn": arn, "service": service, "resource_type": resource_type,
                "region": region, "account": account, "version": 1, "scan_id": scan_id,
                "pillar": "aws_environment"}
        return doc, arn, meta

    if not isinstance(item, dict):
        return None, None, None

    # Extract ARN
    arn = (
        item.get("Arn") or item.get("ARN") or
        item.get("LoadBalancerArn") or item.get("FunctionArn") or
        item.get("DBInstanceArn") or item.get("TopicArn") or
        None
    )

    id_field = config.get("id_field", "Id")
    resource_id = item.get(id_field, "unknown")

    if not arn:
        arn = f"arn:aws:{service}:{region}:{account}:{resource_type}/{resource_id}"

    # Extract name
    name = ""
    for nf in config.get("name_fields", []):
        if nf == "Tags":
            name = _extract_name_from_tags(item)
        else:
            name = item.get(nf, "")
        if name:
            break
    if not name:
        name = str(resource_id)

    # Build properties
    skip_keys = {"Tags", "Instances", "ResponseMetadata"}
    def _safe_value(v):
        """Convert value to string, handling datetime and complex types."""
        if isinstance(v, (dict, list)):
            try:
                return json.dumps(v, default=str)
            except (TypeError, ValueError):
                return str(v)
        return str(v)

    props = "\n".join(f"  {k}: {_safe_value(v)}"
                      for k, v in item.items()
                      if k not in skip_keys and v is not None)

    # Tags
    tags_list = item.get("Tags", [])
    tags_str = ", ".join(
        f"{t.get('Key', '?')}={t.get('Value', '?')}"
        for t in tags_list
    ) if isinstance(tags_list, list) else ""

    # Relationships
    relationships = []
    if item.get("VpcId"):
        relationships.append(f"  → VPC: {item['VpcId']}")
    if item.get("SubnetId"):
        relationships.append(f"  → Subnet: {item['SubnetId']}")
    if item.get("Role"):
        relationships.append(f"  → IAM Role: {item['Role']}")
    sgs = item.get("SecurityGroups", [])
    if isinstance(sgs, list):
        for sg in sgs:
            sg_id = sg if isinstance(sg, str) else sg.get("GroupId", str(sg))
            relationships.append(f"  → Security Group: {sg_id}")
    rel_str = "\n".join(relationships) if relationships else "  (none identified)"

    doc = (
        f"[RESOURCE] Service: {service} | Type: {resource_type} | Version: 1 | Scan: {scan_id}\n"
        f"ARN: {arn}\n"
        f"Name: {name} | Region: {region} | Account: {account}\n\n"
        f"Configuration:\n{props}\n\n"
        f"Tags: {tags_str or '(none)'}\n\n"
        f"Relationships:\n{rel_str}\n\n"
        f"Discovered: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
        f"---\n{service.upper()} {resource_type} '{name}' in {region}."
    )

    meta = {
        "arn": arn, "service": service, "resource_type": resource_type,
        "region": region, "account": account, "version": 1, "scan_id": scan_id,
        "pillar": "aws_environment",
        "stored_at": datetime.now(timezone.utc).isoformat(),
    }

    return doc, arn, meta


# --- MCP Server ---

server = FastMCP("aura-qdrant")


@server.tool()
def discover_and_store(
    service_type: str,
    collection_name: str,
    scan_id: str,
    region: str = "us-east-1",
    account: str = "",
) -> str:
    """Discover AWS resources and store them directly — NO LLM data relay needed.

    This tool calls AWS (via boto3) and stores each resource in Qdrant in one step.
    The LLM just tells it WHAT to discover. The tool handles the API call, JSON
    parsing, document generation, embedding, and storage internally.

    This avoids the context window problem — the raw AWS data never passes through
    the LLM's context. The LLM sees only a summary of counts and any issues.

    Args:
        service_type: What to discover. Format: "service/type". Valid values:
                      ec2/vpc, ec2/instance, ec2/security-group, ec2/subnet,
                      s3/bucket, lambda/function, iam/role, elbv2/load-balancer,
                      route53/hosted-zone, cloudformation/stack, rds/instance,
                      dynamodb/table
        collection_name: Qdrant collection (typically 'aws_resources').
        scan_id: Scan identifier (e.g., 'scan-2026-03-20-001').
        region: AWS region (default 'us-east-1'). Used for regional services.
                Global services (S3, IAM, Route53) ignore this.
        account: AWS account ID (auto-detected if not provided).
    """
    import boto3

    config = AWS_DISCOVERY_CONFIG.get(service_type)
    if not config:
        valid = ", ".join(sorted(AWS_DISCOVERY_CONFIG.keys()))
        return f"Unknown service_type '{service_type}'. Valid: {valid}"

    ensure_collection(collection_name)

    # Auto-detect account if not provided
    if not account:
        try:
            sts = boto3.client("sts")
            account = sts.get_caller_identity()["Account"]
        except Exception:
            account = "unknown"

    # Determine the effective region for the API call
    client_name = config["client"]
    global_services = {"s3", "iam", "route53"}
    effective_region = None if client_name in global_services else region

    try:
        if effective_region:
            client = boto3.client(client_name, region_name=effective_region)
        else:
            client = boto3.client(client_name)

        method = getattr(client, config["method"])
        params = config.get("params", {})
        response = method(**params)
    except Exception as e:
        return f"AWS API error for {service_type}: {str(e)}"

    # Extract resource list from response
    response_key = config["response_key"]
    items = response.get(response_key, [])

    # Flatten nested structures (e.g., Reservations → Instances)
    if config.get("flatten"):
        flat = []
        for item in items:
            if isinstance(item, dict) and config["flatten"] in item:
                flat.extend(item[config["flatten"]])
        items = flat

    service, rtype = service_type.split("/")
    effective_region_str = region if effective_region else "global"

    # Build and store each resource
    points_batch = []
    stored = 0
    errors = 0

    for item in items:
        doc, arn, meta = _build_resource_doc(
            item, service, rtype, effective_region_str, account, scan_id, config
        )
        if doc is None:
            errors += 1
            continue

        try:
            vector = embed_text(doc)
            points_batch.append(
                models.PointStruct(
                    id=arn_to_id(arn),
                    vector=vector,
                    payload={"document": doc, "metadata": meta},
                )
            )
            stored += 1
        except Exception as e:
            errors += 1
            logger.error(f"Failed to embed {arn}: {e}")

    # Batch upsert
    if points_batch:
        BATCH_SIZE = 50
        for i in range(0, len(points_batch), BATCH_SIZE):
            batch = points_batch[i:i + BATCH_SIZE]
            qdrant.upsert(collection_name=collection_name, points=batch)

    return (
        f"Discovered and stored {stored} {service_type} resources in {collection_name}. "
        f"Region: {effective_region_str}. Scan: {scan_id}. Errors: {errors}. "
        f"Each resource stored individually with ARN-based dedup."
    )


@server.tool()
def store_resource(
    information: str,
    arn: str,
    collection_name: str,
    metadata: Optional[dict] = None,
) -> str:
    """Store an AWS resource in the knowledge base, overwriting any previous version.

    Uses the ARN to generate a deterministic ID — storing the same resource
    again overwrites the previous document instead of creating a duplicate.

    Args:
        information: The structured document text for this resource.
                     Should follow the [RESOURCE] format with Configuration,
                     Networking, Tags, and Relationships sections.
        arn: The AWS ARN (e.g., arn:aws:ec2:us-east-1:123:instance/i-abc).
             This determines the point ID — same ARN = same point = overwrite.
        collection_name: The Qdrant collection (e.g., 'aws_resources').
        metadata: Optional structured metadata dict. Recommended fields:
                  service, resource_type, region, account, version, scan_id.
    """
    ensure_collection(collection_name)
    point_id = arn_to_id(arn)

    # Build metadata with defaults
    meta = metadata or {}
    meta.setdefault("arn", arn)
    meta.setdefault("stored_at", datetime.now(timezone.utc).isoformat())
    meta.setdefault("pillar", "aws_environment")

    vector = embed_text(information)
    qdrant.upsert(
        collection_name=collection_name,
        points=[
            models.PointStruct(
                id=point_id,
                vector=vector,
                payload={"document": information, "metadata": meta},
            )
        ],
    )

    return f"Stored resource {arn} in {collection_name} (id: {point_id[:12]}...)"


@server.tool()
def store_document(
    information: str,
    collection_name: str,
    document_id: Optional[str] = None,
    metadata: Optional[dict] = None,
) -> str:
    """Store a non-resource document (change record, manifest, summary, code, IaC).

    For documents that don't have an ARN (post-mortems, change records, IaC
    definitions, code summaries). Uses content hash for ID if no document_id provided.

    Args:
        information: The document text to store.
        collection_name: The Qdrant collection (e.g., 'aws_changes', 'aws_postmortems',
                         'iac_resources', 'code_services').
        document_id: Optional explicit ID. If not provided, uses content hash.
        metadata: Optional structured metadata dict.
    """
    ensure_collection(collection_name)
    point_id = document_id or content_to_id(information)

    meta = metadata or {}
    meta.setdefault("stored_at", datetime.now(timezone.utc).isoformat())

    vector = embed_text(information)
    qdrant.upsert(
        collection_name=collection_name,
        points=[
            models.PointStruct(
                id=point_id,
                vector=vector,
                payload={"document": information, "metadata": meta},
            )
        ],
    )

    return f"Stored document in {collection_name} (id: {point_id[:12]}...)"


@server.tool()
def bulk_store_resources(
    resources_json: str,
    service: str,
    resource_type: str,
    region: str,
    collection_name: str,
    scan_id: str = "",
    account: str = "",
) -> str:
    """Store multiple AWS resources at once from a JSON array. ONE tool call stores ALL resources.

    Use this after call_aws returns a list of resources. Pass the entire JSON response —
    this tool parses it and stores each resource as a separate document with a
    deterministic ID. No duplicates, no looping, no context accumulation.

    The tool generates a [RESOURCE] document for each item, extracts an ARN or ID for
    deduplication, and upserts into Qdrant.

    Args:
        resources_json: JSON string — either a JSON array of resource objects, or the
                        raw call_aws response text containing resource data.
                        Each object should have identifying fields (like Id, VpcId,
                        InstanceId, FunctionName, Name, Arn, GroupId, etc.)
        service: AWS service name (e.g., 'ec2', 's3', 'lambda', 'iam').
        resource_type: Resource type (e.g., 'instance', 'vpc', 'bucket', 'role', 'security-group').
        region: AWS region (e.g., 'us-east-1', 'global').
        collection_name: Qdrant collection (typically 'aws_resources').
        scan_id: Scan identifier (e.g., 'scan-2026-03-20-001').
        account: AWS account ID.
    """
    ensure_collection(collection_name)

    # === PARSE THE JSON ===
    # call_aws returns data in multiple possible formats:
    #
    # Format 1 (call_aws tool response wrapper):
    #   {"result": [{"response": {"as_json": "{\"Result\": [{...}]}"}}]}
    #
    # Format 2 (AWS Result wrapper):
    #   {"Result": [{...}, {...}]}
    #
    # Format 3 (AWS service wrapper):
    #   {"Vpcs": [{...}]} or {"Buckets": [{...}]} etc.
    #
    # Format 4 (direct array):
    #   [{...}, {...}]
    #
    # Format 5 (JSON embedded in text):
    #   "Here are the results: [{...}]"

    resources = None
    parse_errors = []

    # Step 1: Try to parse the input as JSON
    raw = resources_json.strip()
    parsed = None
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        # Try to find JSON embedded in text
        for start in ("{", "["):
            idx = raw.find(start)
            if idx >= 0:
                # Find the matching end
                bracket_map = {"{": "}", "[": "]"}
                end_char = bracket_map[start]
                depth = 0
                for i in range(idx, len(raw)):
                    if raw[i] == start:
                        depth += 1
                    elif raw[i] == end_char:
                        depth -= 1
                        if depth == 0:
                            try:
                                parsed = json.loads(raw[idx:i+1])
                                break
                            except json.JSONDecodeError:
                                continue
                if parsed is not None:
                    break

    if parsed is None:
        return f"Error: Could not find valid JSON in the input ({len(raw)} chars). First 200: {raw[:200]}"

    # Step 2: Unwrap call_aws tool response format
    # {"result": [{"response": {"as_json": "..."}}]}
    if isinstance(parsed, dict) and "result" in parsed and isinstance(parsed["result"], list):
        for result_item in parsed["result"]:
            if isinstance(result_item, dict) and "response" in result_item:
                as_json = result_item["response"].get("as_json")
                if as_json and isinstance(as_json, str):
                    try:
                        parsed = json.loads(as_json)
                        break
                    except json.JSONDecodeError:
                        parse_errors.append(f"Failed to parse as_json: {as_json[:100]}")

    # Step 3: Unwrap {"Result": [...]} wrapper
    if isinstance(parsed, dict) and "Result" in parsed:
        parsed = parsed["Result"]

    # Step 4: Unwrap AWS service-specific keys
    AWS_LIST_KEYS = [
        "Vpcs", "Reservations", "Instances", "Functions", "Buckets",
        "Roles", "SecurityGroups", "LoadBalancers", "Tables",
        "StackSummaries", "QueueUrls", "Topics", "HostedZones",
        "DistributionList", "Distributions", "MetricAlarms", "SecretList",
        "DBInstances", "DBClusters", "clusterArns", "serviceArns",
        "Subnets", "RouteTables", "NatGateways", "InternetGateways",
        "Addresses", "KeyPairs", "Images", "Snapshots", "Volumes",
        "Parameters", "Secrets",
    ]

    if isinstance(parsed, dict):
        for key in AWS_LIST_KEYS:
            if key in parsed:
                parsed = parsed[key]
                break

    # Step 5: Flatten EC2 Reservations → Instances
    if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
        if "Instances" in parsed[0]:
            instances = []
            for reservation in parsed:
                if isinstance(reservation, dict) and "Instances" in reservation:
                    instances.extend(reservation["Instances"])
            parsed = instances

    # Step 6: Ensure we have a list
    if isinstance(parsed, dict):
        parsed = [parsed]
    elif not isinstance(parsed, list):
        return f"Error: Parsed data is {type(parsed).__name__}, expected list or dict. First 200: {str(parsed)[:200]}"

    resources = [r for r in parsed if isinstance(r, dict)]

    if not resources:
        return f"No resource objects found after parsing. Parse errors: {parse_errors}"

    # Store each resource
    stored = 0
    errors = 0
    points_batch = []

    for item in resources:
        if not isinstance(item, dict):
            errors += 1
            continue

        # Extract ARN or generate one from available identifiers
        arn = (
            item.get("Arn") or
            item.get("ARN") or
            item.get("LoadBalancerArn") or
            item.get("FunctionArn") or
            item.get("RoleArn") or
            item.get("TopicArn") or
            item.get("QueueUrl") or
            None
        )

        # Build ARN from ID fields if no direct ARN
        if not arn:
            resource_id = (
                item.get("Id") or
                item.get("VpcId") or
                item.get("InstanceId") or
                item.get("GroupId") or
                item.get("SubnetId") or
                item.get("Name") or
                item.get("FunctionName") or
                item.get("RoleName") or
                item.get("DBInstanceIdentifier") or
                item.get("TableName") or
                item.get("StackName") or
                str(item)[:50]
            )
            arn = f"arn:aws:{service}:{region}:{account}:{resource_type}/{resource_id}"

        # Get human-readable name
        name = (
            item.get("Name") or
            item.get("FunctionName") or
            item.get("RoleName") or
            item.get("GroupName") or
            item.get("DBInstanceIdentifier") or
            item.get("LoadBalancerName") or
            item.get("StackName") or
            item.get("Id") or
            item.get("VpcId") or
            item.get("InstanceId") or
            item.get("GroupId") or
            "unnamed"
        )

        # Build document text
        props = "\n".join(f"  {k}: {v}" for k, v in item.items()
                         if k not in ("Tags",) and v is not None)

        # Extract tags if present
        tags_list = item.get("Tags") or []
        tags_str = ", ".join(f"{t.get('Key', t.get('K', '?'))}={t.get('Value', t.get('V', '?'))}"
                            for t in tags_list) if isinstance(tags_list, list) else ""

        # Extract relationships from known fields
        relationships = []
        if item.get("VpcId"):
            relationships.append(f"  → VPC: {item['VpcId']}")
        if item.get("SubnetId"):
            relationships.append(f"  → Subnet: {item['SubnetId']}")
        if item.get("Role"):
            relationships.append(f"  → IAM Role: {item['Role']}")
        if item.get("SecurityGroups"):
            sgs = item["SecurityGroups"]
            if isinstance(sgs, list):
                for sg in sgs:
                    sg_id = sg if isinstance(sg, str) else sg.get("GroupId", sg.get("Id", str(sg)))
                    relationships.append(f"  → Security Group: {sg_id}")

        rel_str = "\n".join(relationships) if relationships else "  (none identified)"

        doc = (
            f"[RESOURCE] Service: {service} | Type: {resource_type} | Version: 1 | Scan: {scan_id}\n"
            f"ARN: {arn}\n"
            f"Name: {name} | Region: {region} | Account: {account}\n\n"
            f"Configuration:\n{props}\n\n"
            f"Tags: {tags_str or '(none)'}\n\n"
            f"Relationships:\n{rel_str}\n\n"
            f"Discovered: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
            f"---\n"
            f"{service.upper()} {resource_type} '{name}' in {region}."
        )

        meta = {
            "arn": arn,
            "service": service,
            "resource_type": resource_type,
            "region": region,
            "account": account,
            "version": 1,
            "scan_id": scan_id,
            "pillar": "aws_environment",
            "stored_at": datetime.now(timezone.utc).isoformat(),
        }

        point_id = arn_to_id(arn)
        try:
            vector = embed_text(doc)
            points_batch.append(
                models.PointStruct(
                    id=point_id,
                    vector=vector,
                    payload={"document": doc, "metadata": meta},
                )
            )
            stored += 1
        except Exception as e:
            errors += 1
            logger.error(f"Failed to embed resource {arn}: {e}")

    # Batch upsert all points at once
    if points_batch:
        # Qdrant supports batch upsert — much faster than one at a time
        BATCH_SIZE = 50
        for i in range(0, len(points_batch), BATCH_SIZE):
            batch = points_batch[i:i + BATCH_SIZE]
            qdrant.upsert(collection_name=collection_name, points=batch)

    return (
        f"Stored {stored} {service}/{resource_type} resources in {collection_name}. "
        f"Errors: {errors}. Scan: {scan_id}. "
        f"Each resource has a deterministic ID from its ARN — no duplicates."
    )


@server.tool()
def search(
    query: str,
    collection_name: str,
    filter_service: Optional[str] = None,
    filter_region: Optional[str] = None,
    filter_resource_type: Optional[str] = None,
    filter_pillar: Optional[str] = None,
    filter_scan_id: Optional[str] = None,
    limit: int = 10,
) -> str:
    """Search the knowledge base with semantic search and optional metadata filters.

    Combines vector similarity (meaning-based) with structured metadata filtering.
    Filters narrow the candidate set BEFORE semantic ranking — faster and more precise.

    Args:
        query: Natural language search query (e.g., "checkout service dependencies",
               "security groups open to internet", "Lambda functions in production").
        collection_name: Collection to search (e.g., 'aws_resources', 'aws_changes').
        filter_service: Filter by AWS service (e.g., 'ec2', 's3', 'lambda', 'iam').
        filter_region: Filter by AWS region (e.g., 'us-east-1').
        filter_resource_type: Filter by resource type (e.g., 'instance', 'vpc', 'bucket').
        filter_pillar: Filter by data pillar (e.g., 'aws_environment', 'iac', 'code').
        filter_scan_id: Filter by scan ID (e.g., 'scan-2026-03-19-001').
        limit: Maximum results (default 10, max 50).
    """
    ensure_collection(collection_name)
    limit = min(limit, 50)

    # Build filter conditions
    must_conditions = []
    if filter_service:
        must_conditions.append(
            models.FieldCondition(key="metadata.service", match=models.MatchValue(value=filter_service))
        )
    if filter_region:
        must_conditions.append(
            models.FieldCondition(key="metadata.region", match=models.MatchValue(value=filter_region))
        )
    if filter_resource_type:
        must_conditions.append(
            models.FieldCondition(key="metadata.resource_type", match=models.MatchValue(value=filter_resource_type))
        )
    if filter_pillar:
        must_conditions.append(
            models.FieldCondition(key="metadata.pillar", match=models.MatchValue(value=filter_pillar))
        )
    if filter_scan_id:
        must_conditions.append(
            models.FieldCondition(key="metadata.scan_id", match=models.MatchValue(value=filter_scan_id))
        )

    query_filter = models.Filter(must=must_conditions) if must_conditions else None

    vector = embed_text(query)
    try:
        # qdrant-client >= 1.12 uses query_points
        results = qdrant.query_points(
            collection_name=collection_name,
            query=vector,
            query_filter=query_filter,
            limit=limit,
            with_payload=True,
        ).points
    except AttributeError:
        # Fallback for older qdrant-client
        results = qdrant.search(
            collection_name=collection_name,
            query_vector=vector,
            query_filter=query_filter,
            limit=limit,
            with_payload=True,
        )

    if not results:
        filters_desc = ""
        if must_conditions:
            active = [f for f in [filter_service, filter_region, filter_resource_type, filter_pillar, filter_scan_id] if f]
            filters_desc = f" (filters: {', '.join(active)})"
        return f"No results found for '{query}' in {collection_name}{filters_desc}"

    # Format results
    output_parts = [f"Found {len(results)} results in {collection_name}:\n"]
    for i, hit in enumerate(results):
        doc = hit.payload.get("document", "")
        meta = hit.payload.get("metadata", {})
        score = round(hit.score, 3)

        # Truncate document for readability
        preview = doc[:600]
        if len(doc) > 600:
            # Cut at sentence boundary
            last_period = preview.rfind(".")
            last_newline = preview.rfind("\n")
            cut_at = max(last_period, last_newline)
            if cut_at > 300:
                preview = preview[:cut_at + 1]
            preview += "\n  [...]"

        arn = meta.get("arn", "N/A")
        service = meta.get("service", "N/A")
        output_parts.append(
            f"--- Result {i + 1} (score: {score}, service: {service}, arn: {arn}) ---\n{preview}\n"
        )

    return "\n".join(output_parts)


@server.tool()
def delete_resource(
    arn: str,
    collection_name: str,
) -> str:
    """Delete a resource from the knowledge base by ARN.

    Removes the point with the deterministic ID derived from the ARN.

    Args:
        arn: The AWS ARN of the resource to delete.
        collection_name: The Qdrant collection.
    """
    point_id = arn_to_id(arn)
    try:
        qdrant.delete(
            collection_name=collection_name,
            points_selector=models.PointIdsList(points=[point_id]),
        )
        return f"Deleted resource {arn} from {collection_name}"
    except Exception as e:
        return f"Failed to delete {arn}: {str(e)}"


@server.tool()
def delete_by_filter(
    collection_name: str,
    filter_service: Optional[str] = None,
    filter_region: Optional[str] = None,
    filter_scan_id: Optional[str] = None,
) -> str:
    """Delete multiple resources by metadata filter.

    Use this to clear all resources for a service, region, or scan.
    At least one filter must be provided (safety check).

    Args:
        collection_name: The Qdrant collection.
        filter_service: Delete all resources for this service.
        filter_region: Delete all resources in this region.
        filter_scan_id: Delete all resources from this scan.
    """
    must_conditions = []
    if filter_service:
        must_conditions.append(
            models.FieldCondition(key="metadata.service", match=models.MatchValue(value=filter_service))
        )
    if filter_region:
        must_conditions.append(
            models.FieldCondition(key="metadata.region", match=models.MatchValue(value=filter_region))
        )
    if filter_scan_id:
        must_conditions.append(
            models.FieldCondition(key="metadata.scan_id", match=models.MatchValue(value=filter_scan_id))
        )

    if not must_conditions:
        return "Error: At least one filter (service, region, or scan_id) must be provided. Use drop_collection to clear everything."

    try:
        qdrant.delete(
            collection_name=collection_name,
            points_selector=models.FilterSelector(
                filter=models.Filter(must=must_conditions)
            ),
        )
        filters = [f for f in [filter_service, filter_region, filter_scan_id] if f]
        return f"Deleted resources matching filters ({', '.join(filters)}) from {collection_name}"
    except Exception as e:
        return f"Failed to delete: {str(e)}"


@server.tool()
def list_resources(
    collection_name: str,
    filter_service: Optional[str] = None,
    filter_region: Optional[str] = None,
    filter_resource_type: Optional[str] = None,
    filter_scan_id: Optional[str] = None,
    limit: int = 50,
) -> str:
    """List resources by metadata filter WITHOUT semantic search.

    Returns resources matching the filters, ordered by storage time.
    Use this when you need a structured listing ("all EC2 instances")
    rather than a meaning-based search.

    Args:
        collection_name: The Qdrant collection.
        filter_service: Filter by service (e.g., 'ec2', 's3').
        filter_region: Filter by region (e.g., 'us-east-1').
        filter_resource_type: Filter by type (e.g., 'instance', 'vpc').
        filter_scan_id: Filter by scan ID.
        limit: Maximum results (default 50).
    """
    ensure_collection(collection_name)

    must_conditions = []
    if filter_service:
        must_conditions.append(
            models.FieldCondition(key="metadata.service", match=models.MatchValue(value=filter_service))
        )
    if filter_region:
        must_conditions.append(
            models.FieldCondition(key="metadata.region", match=models.MatchValue(value=filter_region))
        )
    if filter_resource_type:
        must_conditions.append(
            models.FieldCondition(key="metadata.resource_type", match=models.MatchValue(value=filter_resource_type))
        )
    if filter_scan_id:
        must_conditions.append(
            models.FieldCondition(key="metadata.scan_id", match=models.MatchValue(value=filter_scan_id))
        )

    scroll_filter = models.Filter(must=must_conditions) if must_conditions else None

    results, _next_page = qdrant.scroll(
        collection_name=collection_name,
        scroll_filter=scroll_filter,
        limit=limit,
        with_payload=True,
        with_vectors=False,
    )

    if not results:
        return f"No resources found in {collection_name} with given filters"

    output_parts = [f"Found {len(results)} resources in {collection_name}:\n"]
    for point in results:
        meta = point.payload.get("metadata", {})
        arn = meta.get("arn", "N/A")
        service = meta.get("service", "N/A")
        rtype = meta.get("resource_type", "N/A")
        region = meta.get("region", "N/A")
        version = meta.get("version", "N/A")

        # Get first line of document as title
        doc = point.payload.get("document", "")
        title = doc.split("\n")[0][:120] if doc else "No content"

        output_parts.append(f"  [{service}/{rtype}] {arn}\n    {title}\n")

    return "\n".join(output_parts)


@server.tool()
def get_collection_stats(
    collection_name: str,
) -> str:
    """Get statistics about a knowledge base collection.

    Returns: total document count, indexed fields, and resource counts by service.

    Args:
        collection_name: The Qdrant collection.
    """
    try:
        info = qdrant.get_collection(collection_name=collection_name)
        total = info.points_count

        # Count by service
        service_counts = {}
        results, _ = qdrant.scroll(
            collection_name=collection_name,
            limit=10000,
            with_payload=["metadata.service"],
            with_vectors=False,
        )
        for point in results:
            service = point.payload.get("metadata", {}).get("service", "unknown")
            service_counts[service] = service_counts.get(service, 0) + 1

        output = f"Collection: {collection_name}\n"
        output += f"Total documents: {total}\n"
        output += f"Status: {info.status}\n\n"
        output += "Documents by service:\n"
        for service, count in sorted(service_counts.items(), key=lambda x: -x[1]):
            output += f"  {service}: {count}\n"

        return output
    except Exception as e:
        return f"Collection '{collection_name}' not found or error: {str(e)}"


@server.tool()
def drop_collection(
    collection_name: str,
    confirm: str = "",
) -> str:
    """Drop an entire collection. Requires confirmation.

    This permanently deletes ALL documents in the collection. Use with caution.

    Args:
        collection_name: The collection to drop.
        confirm: Must be set to 'yes-delete-everything' to proceed.
    """
    if confirm != "yes-delete-everything":
        return f"Safety check: set confirm='yes-delete-everything' to drop {collection_name}"

    try:
        qdrant.delete_collection(collection_name=collection_name)
        return f"Dropped collection '{collection_name}' and all its documents"
    except Exception as e:
        return f"Failed to drop collection: {str(e)}"


if __name__ == "__main__":
    server.run(transport="stdio")
