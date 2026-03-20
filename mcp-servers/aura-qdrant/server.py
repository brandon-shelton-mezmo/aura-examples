#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "mcp[cli]>=1.0.0",
#     "qdrant-client>=1.12.0",
#     "fastembed>=0.4.0",
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


# --- MCP Server ---

server = FastMCP("aura-qdrant")


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

    # Parse the JSON — handle multiple formats from call_aws
    try:
        resources = json.loads(resources_json)
    except json.JSONDecodeError:
        # call_aws sometimes returns text with embedded JSON
        # Try to find a JSON array or object in the text
        for start_char in ("[", "{"):
            idx = resources_json.find(start_char)
            if idx >= 0:
                try:
                    resources = json.loads(resources_json[idx:])
                    break
                except json.JSONDecodeError:
                    continue
        else:
            return f"Error: Could not parse resources_json as JSON. Pass the raw JSON from call_aws."

    # Unwrap response wrappers — call_aws often wraps in {"Result": [...]}
    if isinstance(resources, dict):
        # Check for call_aws Result wrapper
        if "Result" in resources and isinstance(resources["Result"], list):
            resources = resources["Result"]
        elif "Result" in resources and isinstance(resources["Result"], dict):
            resources = resources["Result"]
            # Fall through to unwrap the inner dict

        if isinstance(resources, dict):
            # Try common AWS response keys
            for key in ["Vpcs", "Reservations", "Instances", "Functions", "Buckets",
                        "Roles", "SecurityGroups", "LoadBalancers", "Tables",
                        "StackSummaries", "QueueUrls", "Topics", "HostedZones",
                        "DistributionList", "MetricAlarms", "SecretList",
                        "DBInstances", "clusterArns", "serviceArns",
                        "Subnets", "RouteTables", "NatGateways", "InternetGateways"]:
                if key in resources:
                    resources = resources[key]
                    break

    # Handle EC2 instances nested in Reservations
    if isinstance(resources, list) and resources and isinstance(resources[0], dict):
        if "Instances" in resources[0]:
            instances = []
            for reservation in resources:
                instances.extend(reservation.get("Instances", []))
            resources = instances

    if not isinstance(resources, list):
        resources = [resources]

    if not resources:
        return f"No resources found in the provided data."

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
