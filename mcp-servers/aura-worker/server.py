"""
Aura Worker MCP Server

An MCP server that wraps aura's /v1/chat/completions API, allowing an orchestrator
agent to delegate work to worker agent instances. Supports both sequential and
parallel task execution.

The orchestrator agent uses this as a tool: "send this prompt to a worker agent."
Each worker call gets a fresh aura request with a clean context window, solving
the context accumulation problem for large discovery scans.

Usage:
    # Install dependencies
    pip install mcp[cli] httpx

    # Run in stdio mode (for aura stdio transport)
    python server.py

    # Run in HTTP mode (for aura http_streamable transport)
    python server.py --transport streamable-http --port 8095

    # Configure worker URL
    AURA_WORKER_URL=http://localhost:8080 python server.py

Environment Variables:
    AURA_WORKER_URL     Base URL of the worker aura instance (default: http://localhost:8080)
    WORKER_TIMEOUT      Timeout in seconds for each worker request (default: 180)
    MAX_PARALLEL        Maximum parallel worker requests (default: 10)
"""

import asyncio
import json
import os
import time
from typing import Optional

import httpx
from mcp.server.fastmcp import FastMCP

# Configuration
AURA_WORKER_URL = os.getenv("AURA_WORKER_URL", "http://localhost:8080")
WORKER_TIMEOUT = int(os.getenv("WORKER_TIMEOUT", "300"))
MAX_PARALLEL = int(os.getenv("MAX_PARALLEL", "10"))
# Maximum characters to return from a worker response.
# Workers store full data in Qdrant — the orchestrator only needs a summary.
MAX_RESPONSE_LENGTH = int(os.getenv("MAX_RESPONSE_LENGTH", "1500"))

# Throttling: controls how many workers hit Bedrock simultaneously.
# Bedrock has per-model rate limits (tokens/min). Too many concurrent
# requests causes "Too many tokens" errors.
MAX_CONCURRENT = int(os.getenv("MAX_CONCURRENT", "2"))
DELAY_BETWEEN_WORKERS = float(os.getenv("DELAY_BETWEEN_WORKERS", "5.0"))
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "3"))
RETRY_BASE_DELAY = float(os.getenv("RETRY_BASE_DELAY", "15.0"))

# Semaphore to limit concurrent Bedrock requests
_semaphore = None

server = FastMCP("aura-worker-mcp")


def _get_semaphore():
    global _semaphore
    if _semaphore is None:
        _semaphore = asyncio.Semaphore(MAX_CONCURRENT)
    return _semaphore


async def _call_worker_with_retry(prompt: str, worker_url: str, timeout: int) -> dict:
    """Send a prompt with concurrency control and retry on rate limits."""
    semaphore = _get_semaphore()

    for attempt in range(1, MAX_RETRIES + 1):
        async with semaphore:
            try:
                result = await _call_worker_raw(prompt, worker_url, timeout)

                # Check if the response indicates a rate limit error
                content = result.get("content", "")
                if "Too many tokens" in content or "please wait" in content.lower():
                    if attempt < MAX_RETRIES:
                        delay = RETRY_BASE_DELAY * attempt
                        result["content"] = f"[Rate limited, retry {attempt}/{MAX_RETRIES} after {delay}s...]"
                        await asyncio.sleep(delay)
                        continue
                    else:
                        result["content"] += " [Max retries reached]"

                return result

            except httpx.HTTPStatusError as e:
                if e.response.status_code == 429 and attempt < MAX_RETRIES:
                    delay = RETRY_BASE_DELAY * attempt
                    await asyncio.sleep(delay)
                    continue
                raise

    return {"content": "All retries exhausted", "tokens": 0, "elapsed_seconds": 0}


async def _call_worker_raw(prompt: str, worker_url: str, timeout: int) -> dict:
    """Send a prompt to a worker aura instance and return the result."""
    start = time.time()
    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.post(
            f"{worker_url}/v1/chat/completions",
            json={"messages": [{"role": "user", "content": prompt}]},
            headers={"Content-Type": "application/json"},
        )
        response.raise_for_status()
        data = response.json()

    elapsed = round(time.time() - start, 1)
    content = data["choices"][0]["message"]["content"]
    tokens = data.get("usage", {})

    # Truncate response to keep orchestrator context small.
    # The worker already stored full data in Qdrant — the orchestrator
    # only needs a summary to coordinate next steps.
    if len(content) > MAX_RESPONSE_LENGTH:
        truncated = content[:MAX_RESPONSE_LENGTH]
        # Try to cut at a sentence boundary
        last_period = truncated.rfind(".")
        last_newline = truncated.rfind("\n")
        cut_at = max(last_period, last_newline)
        if cut_at > MAX_RESPONSE_LENGTH // 2:
            truncated = truncated[:cut_at + 1]
        content = truncated + f"\n\n[Response truncated — full data stored in Qdrant knowledge base. {len(content)} chars total.]"

    return {
        "content": content,
        "tokens": tokens.get("total_tokens", 0),
        "elapsed_seconds": elapsed,
    }


@server.tool()
async def run_agent(
    prompt: str,
    worker_url: Optional[str] = None,
) -> str:
    """Send a task to a worker aura agent and return its response.

    Use this to delegate a focused piece of work (e.g., "Discover all S3 buckets
    and store them in the knowledge base") to a worker agent. The worker gets a
    fresh context window, so it won't be affected by prior tool call results in
    your conversation.

    Args:
        prompt: The instruction to send to the worker agent. Be specific about
                what to discover, what CLI commands to use, and to store results
                in qdrant with collection_name 'aws_resources'.
        worker_url: Optional override for the worker aura URL.
                    Defaults to AURA_WORKER_URL environment variable.
    """
    url = worker_url or AURA_WORKER_URL
    try:
        result = await _call_worker_with_retry(prompt, url, WORKER_TIMEOUT)
        return (
            f"Worker completed in {result['elapsed_seconds']}s "
            f"({result['tokens']} tokens):\n\n{result['content']}"
        )
    except httpx.TimeoutException:
        return f"Worker timed out after {WORKER_TIMEOUT}s. The task may have been too large. Try breaking it into smaller pieces."
    except httpx.HTTPStatusError as e:
        return f"Worker returned error {e.response.status_code}: {e.response.text[:500]}"
    except Exception as e:
        return f"Worker error: {str(e)}"


@server.tool()
async def run_agents_parallel(
    prompts: list[str],
    worker_url: Optional[str] = None,
) -> str:
    """Send multiple tasks to worker agents in parallel and return all responses.

    Use this when you have several independent discovery tasks that can run
    simultaneously. Each task gets its own worker with a fresh context window.
    Results are returned in the same order as the prompts.

    Example prompts:
        ["Discover VPCs and store in KB", "Discover EC2 and store in KB", "Discover S3 and store in KB"]

    Args:
        prompts: List of instructions to send to worker agents in parallel.
                 Maximum {MAX_PARALLEL} parallel tasks.
        worker_url: Optional override for the worker aura URL.
    """
    url = worker_url or AURA_WORKER_URL

    if len(prompts) > MAX_PARALLEL:
        return f"Too many parallel tasks ({len(prompts)}). Maximum is {MAX_PARALLEL}."

    if not prompts:
        return "No prompts provided."

    start = time.time()

    # Stagger task starts to avoid Bedrock rate limit spikes.
    # The semaphore limits concurrent requests, and the stagger delay
    # spreads out the initial burst.
    async def _staggered_call(index: int, prompt: str):
        if index > 0:
            await asyncio.sleep(index * DELAY_BETWEEN_WORKERS)
        return await _call_worker_with_retry(prompt, url, WORKER_TIMEOUT)

    tasks = [_staggered_call(i, prompt) for i, prompt in enumerate(prompts)]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    elapsed = round(time.time() - start, 1)
    total_tokens = 0
    succeeded = 0
    failed = 0
    output_parts = []

    for i, result in enumerate(results):
        task_label = f"Task {i + 1}/{len(prompts)}"
        if isinstance(result, Exception):
            failed += 1
            output_parts.append(f"### {task_label}: FAILED\nError: {str(result)}\n")
        else:
            succeeded += 1
            total_tokens += result["tokens"]
            output_parts.append(
                f"### {task_label}: OK ({result['elapsed_seconds']}s, {result['tokens']} tokens)\n"
                f"{result['content']}\n"
            )

    summary = (
        f"## Parallel Execution Summary\n"
        f"- Tasks: {len(prompts)} ({succeeded} succeeded, {failed} failed)\n"
        f"- Total time: {elapsed}s (parallel)\n"
        f"- Total tokens: {total_tokens}\n\n"
    )

    return summary + "\n".join(output_parts)


@server.tool()
async def check_worker(
    worker_url: Optional[str] = None,
) -> str:
    """Check if a worker aura instance is running and responsive.

    Use this before sending tasks to verify the worker is available.

    Args:
        worker_url: Optional override for the worker aura URL.
    """
    url = worker_url or AURA_WORKER_URL
    try:
        result = await _call_worker("Say 'ready' and nothing else.", url, 30)
        return f"Worker at {url} is ready ({result['elapsed_seconds']}s response time)"
    except Exception as e:
        return f"Worker at {url} is not responding: {str(e)}"


@server.tool()
async def retry_incomplete(
    expected_services: list[str],
    scan_id: str,
    region: str = "us-east-1",
    qdrant_url: str = "http://localhost:6333",
    collection_name: str = "aws_resources",
    worker_url: Optional[str] = None,
) -> str:
    """Check what services are missing from the knowledge base and retry them.

    After a discovery run, some services may have failed due to rate limits.
    This tool checks Qdrant for what's stored, compares against expected
    services, and retries the missing ones sequentially with delays.

    Args:
        expected_services: List of service types that should exist
                          (e.g., ["ec2/vpc", "ec2/instance", "s3/bucket", "iam/role",
                                  "lambda/function", "ec2/security-group", "ec2/subnet",
                                  "elbv2/load-balancer", "route53/hosted-zone",
                                  "cloudformation/stack"])
        scan_id: The scan ID to use for stored resources.
        region: AWS region (default us-east-1).
        qdrant_url: Qdrant REST API URL (default http://localhost:6333).
        collection_name: Qdrant collection (default aws_resources).
        worker_url: Optional override for the worker aura URL.
    """
    import httpx as httpx_sync

    url = worker_url or AURA_WORKER_URL

    # Check what's already in Qdrant
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                f"{qdrant_url}/collections/{collection_name}/points/scroll",
                json={
                    "limit": 1000,
                    "with_payload": ["metadata.service", "metadata.resource_type"],
                    "with_vector": False,
                },
            )
            data = resp.json()
            points = data.get("result", {}).get("points", [])
    except Exception as e:
        return f"Error checking Qdrant: {e}"

    # Count what's stored by service/type
    stored = set()
    counts = {}
    for p in points:
        meta = p.get("payload", {}).get("metadata", {})
        svc = meta.get("service", "?")
        rtype = meta.get("resource_type", "?")
        key = f"{svc}/{rtype}"
        stored.add(key)
        counts[key] = counts.get(key, 0) + 1

    # Find missing services
    missing = [s for s in expected_services if s not in stored]

    if not missing:
        summary = "All expected services are present in the knowledge base:\n"
        for svc, count in sorted(counts.items()):
            summary += f"  {svc}: {count}\n"
        return summary

    # Map service/type to discovery prompts
    service_prompts = {
        "ec2/vpc": f"Discover VPCs. call_aws: aws ec2 describe-vpcs --region {region}. Then bulk_store_resources, service=ec2, resource_type=vpc, region={region}, collection_name={collection_name}, scan_id={scan_id}.",
        "ec2/instance": f"Discover EC2 instances. call_aws: aws ec2 describe-instances --region {region}. Then bulk_store_resources, service=ec2, resource_type=instance, region={region}, collection_name={collection_name}, scan_id={scan_id}.",
        "ec2/security-group": f"Discover security groups. call_aws: aws ec2 describe-security-groups --region {region}. Then bulk_store_resources, service=ec2, resource_type=security-group, region={region}, collection_name={collection_name}, scan_id={scan_id}.",
        "ec2/subnet": f"Discover subnets. call_aws: aws ec2 describe-subnets --region {region}. Then bulk_store_resources, service=ec2, resource_type=subnet, region={region}, collection_name={collection_name}, scan_id={scan_id}.",
        "s3/bucket": f"Discover S3 buckets. call_aws: aws s3api list-buckets. Then bulk_store_resources, service=s3, resource_type=bucket, region=global, collection_name={collection_name}, scan_id={scan_id}.",
        "lambda/function": f"Discover Lambda functions. call_aws: aws lambda list-functions --region {region}. Then bulk_store_resources, service=lambda, resource_type=function, region={region}, collection_name={collection_name}, scan_id={scan_id}.",
        "iam/role": f"Discover IAM roles. call_aws: aws iam list-roles --max-items 50. Then bulk_store_resources, service=iam, resource_type=role, region=global, collection_name={collection_name}, scan_id={scan_id}.",
        "elbv2/load-balancer": f"Discover load balancers. call_aws: aws elbv2 describe-load-balancers --region {region}. Then bulk_store_resources, service=elbv2, resource_type=load-balancer, region={region}, collection_name={collection_name}, scan_id={scan_id}.",
        "route53/hosted-zone": f"Discover Route53 hosted zones. call_aws: aws route53 list-hosted-zones. Then bulk_store_resources, service=route53, resource_type=hosted-zone, region=global, collection_name={collection_name}, scan_id={scan_id}.",
        "cloudformation/stack": f"Discover CloudFormation stacks. call_aws: aws cloudformation list-stacks --region {region} --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE. Then bulk_store_resources, service=cloudformation, resource_type=stack, region={region}, collection_name={collection_name}, scan_id={scan_id}.",
    }

    # Retry missing services SEQUENTIALLY with delays (to avoid rate limits)
    retried = []
    still_missing = []

    for svc in missing:
        prompt = service_prompts.get(svc)
        if not prompt:
            still_missing.append(f"{svc} (no retry prompt available)")
            continue

        # Wait between retries to avoid rate limits
        if retried:
            await asyncio.sleep(RETRY_BASE_DELAY)

        try:
            result = await _call_worker_with_retry(prompt, url, WORKER_TIMEOUT)
            retried.append(f"  ✅ {svc}: {result['content'][:200]}")
        except Exception as e:
            retried.append(f"  ❌ {svc}: {str(e)[:200]}")

    output = f"## Retry Results\n\n"
    output += f"Already stored: {len(stored)} service types ({sum(counts.values())} resources)\n"
    output += f"Missing: {len(missing)} service types\n"
    output += f"Retried: {len(retried)}\n\n"
    for r in retried:
        output += f"{r}\n"
    if still_missing:
        output += f"\nCould not retry: {', '.join(still_missing)}\n"

    return output


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Aura Worker MCP Server")
    args = parser.parse_args()

    # Always run in stdio mode — use mcp-proxy to expose as HTTP if needed:
    #   mcp-proxy --transport streamablehttp --port 8095 -- python server.py
    server.run(transport="stdio")


if __name__ == "__main__":
    main()
