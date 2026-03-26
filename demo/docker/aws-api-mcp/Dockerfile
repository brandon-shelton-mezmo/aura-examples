FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir mcp-proxy awslabs.aws-api-mcp-server

ENV READ_OPERATIONS_ONLY=true
ENV AWS_REGION=us-east-1

EXPOSE 8091

HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=45s \
  CMD curl -sf -X POST http://localhost:8091/mcp \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":0,"method":"ping"}' || exit 1

# mcp-proxy spawns awslabs.aws-api-mcp-server as a subprocess.
# Must pass through AWS_CONTAINER_CREDENTIALS_RELATIVE_URI for ECS task role auth,
# plus AWS_REGION and READ_OPERATIONS_ONLY.
CMD ["/bin/sh", "-c", "\
EXTRA_ARGS=\"\" && \
if [ -n \"$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI\" ]; then \
  EXTRA_ARGS=\"-e AWS_CONTAINER_CREDENTIALS_RELATIVE_URI $AWS_CONTAINER_CREDENTIALS_RELATIVE_URI\"; \
fi && \
exec mcp-proxy --transport streamablehttp --host 0.0.0.0 --port 8091 \
  -e READ_OPERATIONS_ONLY ${READ_OPERATIONS_ONLY:-true} \
  -e AWS_REGION ${AWS_REGION:-us-east-1} \
  -e AWS_DEFAULT_REGION ${AWS_REGION:-us-east-1} \
  $EXTRA_ARGS \
  -- awslabs.aws-api-mcp-server"]
