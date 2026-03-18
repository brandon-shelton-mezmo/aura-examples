# Troubleshooting Runbook -- AWS Discovery Agents

SRE runbook for common operational issues. Every entry follows **SYMPTOM / CHECK / FIX**.

---

## 1. Agent says "AWS credentials not configured"

**SYMPTOM:** The agent replies with a message containing "AWS credentials not configured"
or the aura logs show `No credentials in the provider chain`.

**CHECK:**

```bash
# Verify the expected env vars are set
env | grep -E '^AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN|PROFILE|REGION)'

# Verify the credentials actually work
aws sts get-caller-identity
```

**FIX:**

- If `env` output is empty, export the credentials before starting the agent:
  ```bash
  export AWS_ACCESS_KEY_ID="..."
  export AWS_SECRET_ACCESS_KEY="..."
  export AWS_REGION="us-east-1"
  ```
- If `sts get-caller-identity` returns an error, the credentials are expired or invalid.
  Rotate them in IAM or refresh your SSO session (`aws sso login --profile <profile>`).

---

## 2. "Qdrant is not reachable"

**SYMPTOM:** Agent logs or preflight output includes `Qdrant is not reachable` or
`connection refused` on the Qdrant URL.

**CHECK:**

```bash
# Hit the Qdrant health endpoint directly
curl -s http://localhost:6333/healthz

# Confirm the Qdrant container is running
docker ps --filter "name=qdrant"
```

**FIX:**

- If `curl` gets no response, Qdrant is not running. Start it:
  ```bash
  docker compose up -d qdrant
  ```
- If `docker ps` shows the container but `curl` still fails, the port mapping may be
  wrong. Check `docker compose logs qdrant` for bind errors and verify the port in
  your TOML config matches the exposed port.

---

## 3. Discovery seems to miss resources

**SYMPTOM:** You know resources exist in the AWS account, but the agent does not
report them after a discovery run.

**CHECK:**

```bash
# Run the preflight check -- it validates connectivity and permissions
# (from the agent chat, send: "run preflight check")

# Or manually verify the IAM policy covers the expected services
aws iam simulate-principal-policy \
  --policy-source-arn "$(aws sts get-caller-identity --query Arn --output text)" \
  --action-names ec2:DescribeInstances s3:ListBuckets rds:DescribeDBInstances
```

**FIX:**

- If `simulate-principal-policy` shows `implicitDeny` for any action, the IAM role
  is missing read permissions. Attach the `ReadOnlyAccess` managed policy or add the
  specific `Describe*`/`List*` actions your discovery needs.
- If permissions look correct, check whether the discovery was scoped to a specific
  region. Resources in other regions will not appear. Re-run with the correct
  `AWS_REGION` or use a multi-region discovery scope.

---

## 4. Agent responses are slow (>60 seconds)

**SYMPTOM:** After sending a message, the agent takes over a minute to reply. The
browser or client may appear to hang.

**CHECK:**

```bash
# Check the turn_depth setting in your config
grep -i 'turn_depth' /path/to/your/config.toml

# Check if the agent is doing a full unscoped discovery (look for broad API calls)
# In the agent logs, look for lines like "Discovering all resources in account"
docker compose logs agent 2>&1 | tail -50
```

**FIX:**

- If `turn_depth` is set above 15, lower it. High turn depth means the agent can
  chain many tool calls in a single response. A value of 5-10 is typical:
  ```toml
  [agent]
  turn_depth = 8
  ```
- If the agent is scanning all services in a large account, switch to scoped discovery.
  Ask the agent to discover a specific service (e.g., "discover only EC2 instances in
  us-east-1") instead of running a full account scan.

---

## 5. Knowledge base returns stale results

**SYMPTOM:** The agent answers questions using outdated resource data (e.g., reports
instances that were terminated days ago).

**CHECK:**

```bash
# Check when the Qdrant collection was last updated
curl -s http://localhost:6333/collections/aws_resources | python3 -m json.tool

# Look at the points_count and compare to expected resource count
```

**FIX:**

- Run a fresh discovery to re-scan and update the knowledge base. From the agent chat,
  ask: "Run a fresh discovery of [service/region]."
- If you need a clean slate, delete the collection and re-discover:
  ```bash
  curl -X DELETE http://localhost:6333/collections/aws_resources
  ```
  Then trigger discovery again through the agent.

---

## 6. Agent says "rate limited" on AWS APIs

**SYMPTOM:** The agent reports throttling errors or the logs contain
`ThrottlingException` / `Rate exceeded` from AWS API calls.

**CHECK:**

```bash
# Look for throttling in recent logs
docker compose logs agent 2>&1 | grep -i -E 'throttl|rate.*(limit|exceed)'
```

**FIX:**

- This is normal for large AWS environments with many resources. The discovery tools
  make many `Describe*`/`List*` calls and AWS applies per-service rate limits.
- Use scoped discovery to reduce the blast radius. Instead of "discover everything,"
  ask the agent to scan one service or one region at a time.
- If throttling persists on a single service, wait a few minutes and retry. AWS
  throttle windows are typically short (seconds to low minutes).

---

## 7. Docker Compose fails to start

**SYMPTOM:** `docker compose up` exits with an error. The agent container never
becomes healthy.

**CHECK:**

```bash
# Validate the compose file syntax
docker compose config

# Check if the required ports are already in use
lsof -i :3030
lsof -i :6333
```

**FIX:**

- If `docker compose config` reports a syntax error, fix the compose file at the
  line indicated.
- If `lsof` shows a process on port 3030 or 6333, either stop that process or change
  the port mapping in `docker-compose.yml`:
  ```yaml
  ports:
    - "3031:3030"   # map to a different host port
  ```
- If the Docker daemon itself is not running (`Cannot connect to the Docker daemon`),
  start it:
  ```bash
  # macOS
  open -a Docker
  # Linux
  sudo systemctl start docker
  ```

---

## 8. MCP server connection failed

**SYMPTOM:** Agent logs show `MCP server connection failed` or `failed to start MCP
server` for one of the tool servers.

**CHECK:**

```bash
# For stdio-based MCP servers, verify the command is available
which uvx
uvx --version

# Try starting the MCP server manually to see its error output
uvx mcp-server-aws-resources 2>&1 | head -20
```

**FIX:**

- If `which uvx` returns nothing, install it:
  ```bash
  pip install uvx
  ```
  Or if the server uses plain Python: verify `python3` is on PATH and the server
  package is installed.
- If the server starts manually but fails inside Docker, check that the container
  image includes the required runtime (Python, Node, etc.) and that the `command`
  path in your TOML config is correct for the container filesystem.
- Check the server-specific logs. For stdio servers, the error output goes to stderr
  of the aura process.

---

## 9. Agent does not store results in knowledge base

**SYMPTOM:** Discovery runs and the agent reports findings, but subsequent questions
about those resources get "I don't have information about that" responses.

**CHECK:**

```bash
# Verify Qdrant is running and the collection exists
curl -s http://localhost:6333/collections

# Check the point count in the expected collection
curl -s http://localhost:6333/collections/aws_resources | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('points_count:', data.get('result', {}).get('points_count', 'N/A'))
"
```

**FIX:**

- If the collection does not exist or `points_count` is 0, the vector store config
  in your TOML may be wrong. Verify the collection name matches between your
  `[[vector_stores]]` config and what the discovery tools write to:
  ```toml
  [[vector_stores]]
  type = "qdrant"
  collection_name = "aws_resources"
  url = "http://localhost:6333"
  ```
- If Qdrant is not running at all, start it (see issue #2 above) and re-run discovery.

---

## 10. Preflight fails on Qdrant write test

**SYMPTOM:** The preflight check passes AWS connectivity but fails with a message
like `Qdrant write test failed` or `unable to write to collection`.

**CHECK:**

```bash
# Test writing a point to Qdrant directly
curl -s -X PUT "http://localhost:6333/collections/test_write/points" \
  -H "Content-Type: application/json" \
  -d '{"points":[{"id":1,"vector":[0.1,0.2,0.3],"payload":{"test":true}}]}'

# If using local file storage, check disk permissions
ls -la "${QDRANT_LOCAL_PATH:-/tmp/qdrant_data}"
```

**FIX:**

- If the `curl` write test returns an error, Qdrant may be running in read-only mode
  or the disk is full. Check `docker compose logs qdrant` for storage errors.
- If using a local storage path (`QDRANT_LOCAL_PATH`), verify the directory exists and
  is writable by the process running Qdrant:
  ```bash
  mkdir -p "${QDRANT_LOCAL_PATH:-/tmp/qdrant_data}"
  chmod 755 "${QDRANT_LOCAL_PATH:-/tmp/qdrant_data}"
  ```
- If running Qdrant in Docker, make sure the volume mount has correct permissions and
  the container user can write to the mounted path.
